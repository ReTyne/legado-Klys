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
    private var pendingPath: String? = null
    private var channel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingPath = resolveIntent(intent)
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
