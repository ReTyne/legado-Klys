package com.legado.md3

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Web 服务前台保活与原生能力边界。
 *
 * HTTP / WebSocket 服务本身在 Dart 侧（shelf）运行，本类只负责原生侧能力：
 *  - 以 dataSync 类型前台运行，避免切后台后进程被回收；
 *  - 展示访问地址通知，提供「复制地址 / 停止」按钮；
 *  - 持有 PARTIAL_WAKE_LOCK 与高性能 WiFi 锁，保证后台网络访问不被挂起。
 *
 * Dart 侧通过 MethodChannel('legado/web_service') 下发的 7 个方法由
 * [WebServiceController] 统一承接；通知栏按钮产生的动作以 Service action 回传。
 */
class WebService : Service() {

    override fun onCreate() {
        super.onCreate()
        WebServiceController.instance = this
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_COPY -> {
                WebServiceController.copyHostAddress(
                    this,
                    intent.getStringExtra(EXTRA_HOST) ?: WebServiceController.hostAddress,
                )
            }
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
            }
            else -> {
                // Dart 侧 startForeground：先应用契约再前台化
                applyStartExtras(intent)
                startForegroundCompat()
            }
        }
        return START_NOT_STICKY
    }

    private fun applyStartExtras(intent: Intent?) {
        if (intent == null) return
        intent.getStringArrayListExtra(EXTRA_LINES)?.let {
            WebServiceController.lines = it.toList()
        }
        intent.getStringExtra(EXTRA_HOST)?.let { WebServiceController.hostAddress = it }
    }

    /** 创建一个低重要性的常驻通知渠道（渠道 ID 由 Dart 契约下发）。 */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager() ?: return
        val id = WebServiceController.channelId
        if (manager.getNotificationChannel(id) != null) return
        val channel = NotificationChannel(
            id,
            "Web 服务",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Web 服务后台保活与访问地址"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    /** 通知栏：点击正文复制地址，附带「复制地址 / 停止」两个动作。 */
    private fun buildNotification(): Notification {
        val copyIntent = Intent(this, WebService::class.java)
            .setAction(ACTION_COPY)
            .putExtra(EXTRA_HOST, WebServiceController.hostAddress)
        val copyPending = PendingIntent.getService(this, 1, copyIntent, pendingIntentFlags())
        val stopIntent = Intent(this, WebService::class.java).setAction(ACTION_STOP)
        val stopPending = PendingIntent.getService(this, 2, stopIntent, pendingIntentFlags())

        val lines = WebServiceController.lines.ifEmpty { listOf("Web 服务运行中") }
        val text = lines.joinToString("\n")
        return NotificationCompat.Builder(this, WebServiceController.channelId)
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setContentTitle("Web 服务")
            .setContentText(lines.first())
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(copyPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(android.R.drawable.ic_menu_share, "复制地址", copyPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPending)
            .build()
    }

    /** 供服务已运行时由 Dart 侧 updateNotification 直接刷新通知。 */
    fun updateNotification() {
        try {
            notificationManager()?.notify(WebServiceController.notificationId, buildNotification())
        } catch (_: Exception) {
        }
    }

    private fun startForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    WebServiceController.notificationId,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(WebServiceController.notificationId, buildNotification())
            }
        } catch (_: Exception) {
            // 系统拒绝前台服务（后台启动限制 / 类型权限缺失）：不留僵死通知
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

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

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

    override fun onDestroy() {
        WebServiceController.instance = null
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.legado.md3.action.WEB_START"
        const val ACTION_COPY = "com.legado.md3.action.WEB_COPY"
        const val ACTION_STOP = "com.legado.md3.action.WEB_STOP"

        const val EXTRA_LINES = "lines"
        const val EXTRA_HOST = "hostAddress"
    }
}

/**
 * Web 服务的单例状态与原生能力控制器。
 *
 * 不依赖 Service 生命周期持有锁与契约数据：Dart 侧 onStarted / onStopped
 * 分别调用 startForeground + acquireLocks、stopForeground + releaseLocks，
 * 锁的申请与释放由本对象独立完成，通知栏按钮则通过 [WebService] 的 action 回传。
 */
object WebServiceController {

    /** 渠道 ID / 通知 ID 与 Dart 侧 web_service_contract.dart 常量一致。 */
    @Volatile
    var channelId: String = "channel_web"
    @Volatile
    var notificationId: Int = 105
    @Volatile
    var lines: List<String> = emptyList()
    @Volatile
    var hostAddress: String = ""

    @Volatile
    var instance: WebService? = null

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    /** 承接 Dart startForeground 的通知契约并拉起前台服务。 */
    fun startForeground(
        context: Context,
        channelId: String?,
        notificationId: Int?,
        lines: List<String>,
        hostAddress: String,
    ) {
        if (!channelId.isNullOrEmpty()) this.channelId = channelId
        if (notificationId != null && notificationId > 0) this.notificationId = notificationId
        this.lines = lines
        this.hostAddress = hostAddress

        val intent = Intent(context, WebService::class.java).setAction(WebService.ACTION_START)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (_: Exception) {
            try {
                context.startService(intent)
            } catch (_: Exception) {
            }
        }
    }

    /** 承接 Dart updateNotification：更新状态并通知运行中的服务刷新。 */
    fun updateNotification(lines: List<String>, hostAddress: String) {
        this.lines = lines
        if (hostAddress.isNotEmpty()) this.hostAddress = hostAddress
        val service = instance
        if (service != null) {
            service.updateNotification()
            return
        }
        // 服务不在运行（已被系统回收）：按当前契约重新前台化
        serviceContext?.let { ctx ->
            startForeground(ctx, channelId, notificationId, lines, hostAddress)
        }
    }

    /** 停止前台服务并移除通知。 */
    fun stopForeground(context: Context) {
        try {
            context.stopService(Intent(context, WebService::class.java))
        } catch (_: Exception) {
        }
    }

    /**
     * 申请后台保活锁。锁类型按 Dart 契约创建：PARTIAL_WAKE_LOCK +
     * WIFI_MODE_FULL_HIGH_PERF，且默认非引用计数。
     */
    @SuppressLint("WakelockTimeout")
    @Suppress("DEPRECATION")
    fun acquireLocks(
        context: Context,
        wakeLockTag: String,
        wifiLockTag: String,
        referenceCounted: Boolean,
    ) {
        releaseLocks()
        val app = context.applicationContext
        try {
            val powerManager = app.getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = powerManager
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "legado:$wakeLockTag")
                ?.apply {
                    setReferenceCounted(referenceCounted)
                    acquire()
                }
        } catch (_: Exception) {
            wakeLock = null
        }
        try {
            val wifiManager = app.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            wifiLock = wifiManager
                ?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "legado:$wifiLockTag")
                ?.apply {
                    setReferenceCounted(referenceCounted)
                    acquire()
                }
        } catch (_: Exception) {
            wifiLock = null
        }
    }

    /** 每次请求到达时续锁（非引用计数锁重复 acquire 不累积计数）。 */
    @SuppressLint("WakelockTimeout")
    fun renewLocks() {
        try {
            wakeLock?.acquire()
        } catch (_: Exception) {
        }
        try {
            wifiLock?.acquire()
        } catch (_: Exception) {
        }
    }

    /** 释放全部保活锁，可重复调用。 */
    fun releaseLocks() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        try {
            wifiLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        wifiLock = null
    }

    /** 把访问地址写入系统剪贴板。 */
    fun copyHostAddress(context: Context, hostAddress: String) {
        if (hostAddress.isBlank()) return
        try {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                ?: return
            clipboard.setPrimaryClip(ClipData.newPlainText("hostAddress", hostAddress))
        } catch (_: Exception) {
        }
    }

    /** 记录最近使用的应用上下文，供服务被回收后重建通知使用。 */
    @Volatile
    private var serviceContext: Context? = null

    fun rememberContext(context: Context) {
        serviceContext = context.applicationContext
    }
}
