package com.legado.md3

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

/**
 * 应用级共享的 FlutterEngine。
 *
 * 音频后台播放需要 Dart 侧的播放器在播放页 Activity 销毁后继续运行，
 * 因此引擎不能随宿主销毁：MainActivity 通过 [provideFlutterEngine] 返回
 * 这里的实例，并让 [shouldDestroyEngineWithHost] 返回 false。
 * AudioNotifyService 也复用同一个引擎的 BinaryMessenger 与 Dart 通信。
 */
object EngineHolder {
    @Volatile
    var engine: FlutterEngine? = null

    fun obtain(context: Context): FlutterEngine {
        engine?.let { return it }
        synchronized(this) {
            engine?.let { return it }
            val created = FlutterEngine(context.applicationContext)
            engine = created
            return created
        }
    }
}
