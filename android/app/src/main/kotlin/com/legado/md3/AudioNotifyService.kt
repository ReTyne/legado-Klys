package com.legado.md3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

/**
 * 音频播放前台服务 + 通知栏控制。
 *
 * 设计：真正的音频解码与播放在 Dart 侧（audioplayers），本服务负责两件事——
 *  1. 以「媒体播放」类型前台运行，保活进程，避免切后台后被系统回收
 *  2. 展示媒体通知（书名/章节/播放状态 + 上一曲、播放暂停、下一曲、停止）
 *
 * 频道划分（两条不能重名：同一 BinaryMessenger 上同名 MethodChannel 会互相覆盖 handler）：
 *  - `legado/audio_notify`（Dart -> 原生）：start / update / stop，
 *    由 MainActivity 处理，由其调用 startService / stopService 拉起本服务；
 *  - `legado/audio_cmd`（原生 -> Dart）：通知栏按钮产生的命令回传，
 *    只在本服务中注册。
 *
 * 因为 FlutterEngine 由 [EngineHolder] 持有且不随 Activity 销毁，Dart 侧播放器
 * 在播放页关闭后仍能继续播放，通知栏的控制才能真正生效。
 */
class AudioNotifyService : Service() {

    companion object {
        private const val NOTIFY_ID = 18810
        private const val NOTIFY_CHANNEL_ID = "legado_audio_play"

        /** Dart 侧 start/update：服务启动与内容更新 */
        const val ACTION_START = "com.legado.md3.action.AUDIO_START"
        const val ACTION_UPDATE = "com.legado.md3.action.AUDIO_UPDATE"

        /** 通知栏按钮 -> Service 的 action（同时作为发给 Dart 的命令） */
        const val CMD_PLAY = "play"
        const val CMD_PAUSE = "pause"
        const val CMD_PREV = "prev"
        const val CMD_NEXT = "next"
        const val CMD_STOP = "stop"

        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
        const val EXTRA_PLAYING = "playing"

        /** 原生 -> Dart 的命令频道 */
        private const val CMD_CHANNEL = "legado/audio_cmd"

        /** 运行中的服务实例（Activity 销毁后仍可被 MainActivity 更新通知） */
        @Volatile
        var instance: AudioNotifyService? = null
            private set

        @Volatile
        private var channel: MethodChannel? = null

        /** 把通知栏产生的控制命令转发给 Dart 侧 */
        fun sendCommand(cmd: String) {
            try {
                channel?.invokeMethod("onAction", cmd)
            } catch (_: Exception) {
                // Dart 侧尚未接入或已销毁：忽略
            }
        }
    }

    private var title: String = "正在朗读"
    private var subtitle: String = ""
    private var playing: Boolean = false

    // ---- 音频焦点（播放时持有，暂停时释放） ----
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioFocusChangeListener: AudioManager.OnAudioFocusChangeListener? = null
    private var hasAudioFocus: Boolean = false

    /** 拔耳机 / 蓝牙断开：输出即将变为 noisy，暂停播放 */
    private val becomingNoisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                sendCommand(CMD_PAUSE)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        bindChannel()
        // ACTION_AUDIO_BECOMING_NOISY 是系统保护广播，无需声明 exported 标记
        try {
            registerReceiver(becomingNoisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        } catch (_: Exception) {
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ""
        when (action) {
            CMD_PLAY, CMD_PAUSE, CMD_PREV, CMD_NEXT -> {
                // 通知栏按钮：命令由 Intent action 携带，直接透传给 Dart
                if (action == CMD_PLAY) requestAudioFocus()
                sendCommand(action)
                return START_NOT_STICKY
            }

            CMD_STOP -> {
                sendCommand(CMD_STOP)
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }

            else -> {
                // Dart 侧 start / update：先应用内容再前台化
                intent?.let { applyExtras(it) }
                startForegroundCompat()
                // 进程被杀后不重启（Dart 播放器已不在，重启只会留下僵死的通知）
                return START_NOT_STICKY
            }
        }
    }

    /** MainActivity 在服务已运行时直接更新通知（避免后台 startService 被系统拒绝） */
    fun updateFromDart(title: String?, subtitle: String?, playing: Boolean?) {
        if (title != null) this.title = title
        if (subtitle != null) this.subtitle = subtitle
        if (playing != null) {
            this.playing = playing
            applyPlayingState()
        }
        updateNotification()
    }

    private fun applyExtras(intent: Intent) {
        intent.getStringExtra(EXTRA_TITLE)?.let { title = it }
        intent.getStringExtra(EXTRA_SUBTITLE)?.let { subtitle = it }
        if (intent.hasExtra(EXTRA_PLAYING)) {
            playing = intent.getBooleanExtra(EXTRA_PLAYING, playing)
            applyPlayingState()
        }
    }

    /** 播放中持有音频焦点，暂停时释放（避免挡住其它应用的声音） */
    private fun applyPlayingState() {
        if (playing) requestAudioFocus() else abandonAudioFocus()
    }

    /** 被其它音频抢占（来电 / 其它播放器）时暂停，与 legado-E 的 AudioFocusHelper 一致 */
    private fun handleFocusChange(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> sendCommand(CMD_PAUSE)
        }
    }

    /** 获取 AudioManager（兼容 minSdk 21：getSystemService(Class) 需 API 23） */
    private fun audioManager(): AudioManager? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                getSystemService(AudioManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun requestAudioFocus() {
        if (hasAudioFocus) return
        val am = audioManager() ?: return
        val listener = AudioManager.OnAudioFocusChangeListener { handleFocusChange(it) }
        audioFocusChangeListener = listener
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(listener)
                .build()
            audioFocusRequest = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
        hasAudioFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocus() {
        val am = audioManager() ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                audioFocusChangeListener?.let { am.abandonAudioFocus(it) }
            }
        } catch (_: Exception) {
        }
        audioFocusRequest = null
        audioFocusChangeListener = null
        hasAudioFocus = false
    }

    /** 注册与 Dart 通信的命令频道（复用应用级 FlutterEngine） */
    private fun bindChannel() {
        val engine = EngineHolder.engine ?: return
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CMD_CHANNEL)
        // 本频道只用于原生 -> Dart 的 onAction，无需处理 Dart 的调用
        channel = ch
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager() ?: return
        if (manager.getNotificationChannel(NOTIFY_CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            NOTIFY_CHANNEL_ID,
            "音频播放",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "有声书播放控制"
            setShowBadge(false)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(ch)
    }

    /** 获取 NotificationManager（兼容 minSdk 21） */
    private fun notificationManager(): NotificationManager? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                getSystemService(NotificationManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            pendingIntentFlags(),
        )
        fun serviceIntent(cmd: String, requestCode: Int): PendingIntent =
            PendingIntent.getService(
                this,
                requestCode,
                Intent(this, AudioNotifyService::class.java).setAction(cmd),
                pendingIntentFlags(),
            )

        val builder = NotificationCompat.Builder(this, NOTIFY_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setSubText(if (playing) "播放中" else "已暂停")
            .setContentIntent(contentIntent)
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_previous,
                    "上一曲",
                    serviceIntent(CMD_PREV, 1),
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                    if (playing) "暂停" else "播放",
                    serviceIntent(if (playing) CMD_PAUSE else CMD_PLAY, 2),
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    "下一曲",
                    serviceIntent(CMD_NEXT, 3),
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "停止",
                    serviceIntent(CMD_STOP, 4),
                ),
            )
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setShowActionsInCompactView(0, 1, 2),
            )
        return builder.build()
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    private fun startForegroundCompat() {
        val n = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFY_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFY_ID, n)
            }
        } catch (_: Exception) {
            // 部分系统（或低内存场景）拒绝前台服务：通知不可用但不应崩溃
            try {
                stopSelf()
            } catch (_: Exception) {
            }
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
    }

    private fun updateNotification() {
        try {
            val manager = notificationManager()
            manager?.notify(NOTIFY_ID, buildNotification())
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        abandonAudioFocus()
        try {
            unregisterReceiver(becomingNoisyReceiver)
        } catch (_: Exception) {
        }
        channel = null
        if (instance === this) instance = null
        super.onDestroy()
    }
}
