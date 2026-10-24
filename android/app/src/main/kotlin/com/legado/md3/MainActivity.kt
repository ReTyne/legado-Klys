package com.legado.md3

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "legado/file_intent"
    private val wakeChannelName = "legado/wakelock"

    /** 音频前台服务控制频道（见 AudioNotifyService） */
    private val audioChannelName = "legado/audio_notify"

    /** legado:// 深链 / 系统分享文本 导入频道 */
    private val deepLinkChannelName = "legado/deep_link"
    private var pendingPath: String? = null
    private var channel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null

    /** 待 Dart 取走的深链/分享链接（Dart 未就绪时缓存） */
    private var pendingLink: String? = null
    private var deepLinkChannel: MethodChannel? = null

    /**
     * 复用应用级共享引擎：这样播放页关闭后 Dart 侧播放器仍随引擎存活，
     * AudioNotifyService 也能通过同一个 BinaryMessenger 控制播放。
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        EngineHolder.obtain(context)

    /** 引擎不随宿主销毁（后台播放需要） */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingPath = resolveIntent(intent)
        pendingLink = handleDeepLinkIntent(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                val p = pendingPath
                pendingPath = null
                result.success(p)
            } else {
                result.notImplemented()
            }
        }
        // legado:// 深链 / 系统分享文本：Dart 主动取初始链接，运行中再经 onLink 推送
        deepLinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deepLinkChannelName)
        deepLinkChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                val link = pendingLink
                pendingLink = null
                result.success(link)
            } else {
                result.notImplemented()
            }
        }
        // 屏幕常亮控制
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wakeChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    enableWakeLock()
                    result.success(null)
                }
                "disable" -> {
                    disableWakeLock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // 音频前台服务 + 媒体通知栏控制
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    // 播放开始：拉起前台服务（此时应用一定在前台）
                    val i = Intent(this, AudioNotifyService::class.java)
                        .setAction(AudioNotifyService.ACTION_START)
                    i.putExtra(AudioNotifyService.EXTRA_TITLE, call.argument<String>("title"))
                    i.putExtra(AudioNotifyService.EXTRA_SUBTITLE, call.argument<String>("subtitle"))
                    i.putExtra(
                        AudioNotifyService.EXTRA_PLAYING,
                        call.argument<Boolean>("playing") ?: false,
                    )
                    try {
                        startService(i)
                    } catch (_: Exception) {
                        // 系统拒绝（后台启动限制）：通知不可用但不崩溃
                    }
                    result.success(null)
                }
                "update" -> {
                    val svc = AudioNotifyService.instance
                    if (svc != null) {
                        // 服务已在运行：直接更新，避免后台 startService 被系统拒绝
                        svc.updateFromDart(
                            call.argument<String>("title"),
                            call.argument<String>("subtitle"),
                            call.argument<Boolean>("playing"),
                        )
                    }
                    // 服务不在运行（用户从通知栏停止 / 已被系统回收）：
                    // 不重新拉起，否则「停止」后会被随后的 pause 事件又拉起来
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, AudioNotifyService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enableWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE, "legado:reading")
        wakeLock?.acquire()
    }

    private fun disableWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    override fun onDestroy() {
        disableWakeLock()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val p = resolveIntent(intent)
        if (p != null) {
            pendingPath = p
            channel?.invokeMethod("onFileOpened", p)
        }
        // 深链/分享：singleTop 复用模式下新 Intent 走这里
        val link = handleDeepLinkIntent(intent)
        if (link != null) {
            pendingLink = link
            try {
                deepLinkChannel?.invokeMethod("onLink", link)
            } catch (_: Exception) {
                // Dart 侧 handler 未就绪：缓存待 getInitialLink 取走
            }
        }
    }

    /**
     * 解析深链 / 分享 Intent，返回统一格式的链接字符串（无匹配返回 null）：
     *  - legado://import?url=... / legado://import?type=bookSource&json=...：原样透传
     *  - ACTION_SEND 文本（URL 或 JSON）：包装为 share://text?content=<encoded>
     */
    private fun handleDeepLinkIntent(intent: Intent?): String? {
        if (intent == null) return null
        return try {
            when (intent.action) {
                Intent.ACTION_VIEW -> {
                    val uri: Uri = intent.data ?: return null
                    if (uri.scheme == "legado") uri.toString() else null
                }
                Intent.ACTION_SEND -> {
                    if (intent.type?.startsWith("text/plain") != true) return null
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
                    if (text.isNullOrEmpty()) {
                        null
                    } else {
                        "share://text?content=${Uri.encode(text)}"
                    }
                }
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun resolveIntent(intent: Intent?): String? {
        val uri: Uri = intent?.data ?: return null
        return try {
            when (uri.scheme) {
                "file" -> uri.path
                "content" -> {
                    val name = uri.lastPathSegment ?: "opened_${System.currentTimeMillis()}"
                    val out = File(cacheDir, sanitize(name))
                    contentResolver.openInputStream(uri)?.use { input ->
                        out.outputStream().use { o -> input.copyTo(o) }
                    }
                    out.absolutePath
                }
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun sanitize(name: String): String {
        val base = name.substringAfterLast('/')
        return if (base.contains('.')) base else "$base.txt"
    }
}
