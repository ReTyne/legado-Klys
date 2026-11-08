package com.legado.md3

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.Collections

/**
 * 原生 -> Dart 的通道集中持有处 + Flutter 引擎未就绪时的事件缓存。
 *
 * MethodChannel 的 invokeMethod / setMethodCallHandler 必须在 Flutter platform
 * thread（主线程）执行；这里统一用 [mainHandler] 投递，避免从 BroadcastReceiver /
 * NetworkCallback / Binder 线程直接调用导致错线程或死锁。
 */
object NativeChannels {

    val mainHandler: Handler = Handler(Looper.getMainLooper())

    @Volatile var mediaButton: MethodChannel? = null
    @Volatile var network: MethodChannel? = null
    @Volatile var processText: MethodChannel? = null
    @Volatile var shortcut: MethodChannel? = null
    @Volatile var pip: MethodChannel? = null
    @Volatile var battery: MethodChannel? = null
    @Volatile var brightness: MethodChannel? = null

    /** 引擎未就绪时缓存，供 Dart 侧 getInitialText / getInitialShortcut / drain 取走 */
    @Volatile var pendingProcessText: String? = null
    @Volatile var pendingShortcut: String? = null

    private val pendingMediaButtons: MutableList<Map<String, Any?>> =
        Collections.synchronizedList(ArrayList())

    private fun invoke(channel: MethodChannel?, method: String, args: Any?) {
        val ch = channel ?: return
        mainHandler.post {
            try {
                ch.invokeMethod(method, args)
            } catch (_: Exception) {
                // Dart 侧 handler 尚未注册 / 引擎已销毁：忽略，避免崩溃
            }
        }
    }

    fun emitMediaButton(event: Map<String, Any?>) {
        if (mediaButton == null) {
            pendingMediaButtons.add(event)
            return
        }
        // 先把引擎就绪前积压的事件补发
        drainMediaButtons().forEach { invoke(mediaButton, "onMediaButton", it) }
        invoke(mediaButton, "onMediaButton", event)
    }

    fun drainMediaButtons(): List<Map<String, Any?>> {
        val copy = ArrayList<Map<String, Any?>>(pendingMediaButtons)
        pendingMediaButtons.clear()
        return copy
    }

    fun emitNetworkChanged(state: Map<String, Any?>) =
        invoke(network, "onNetworkChanged", state)

    fun emitProcessText(text: String) {
        if (processText == null) pendingProcessText = text
        else invoke(processText, "onProcessText", text)
    }

    fun emitShortcut(id: String) {
        if (shortcut == null) pendingShortcut = id
        else invoke(shortcut, "onShortcut", id)
    }

    fun emitPipModeChanged(inPip: Boolean) =
        invoke(pip, "onPipModeChanged", inPip)

    fun emitBatteryChanged(state: Map<String, Any?>) =
        invoke(battery, "onBatteryChanged", state)

    fun emitTimeTick() = invoke(battery, "onTimeTick", null)

    fun emitBrightnessChanged(state: Map<String, Any?>) =
        invoke(brightness, "onBrightnessChanged", state)
}
