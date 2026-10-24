package com.legado.md3

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Web 服务快捷开关磁贴（对齐 legado-E service/WebTileService.kt）。
 *
 * 磁贴点击经 MethodChannel('legado/web_tile') 转发给 Dart 侧切换 WebService，
 * Dart 切换完成后回传 updateState 刷新激活态。Dart 引擎未就绪时点击无副作用
 * （下次 onStartListening 会按静态 running 状态刷新）。
 */
@RequiresApi(Build.VERSION_CODES.N)
class WebTileService : TileService() {

    companion object {
        const val CHANNEL = "legado/web_tile"

        /** 当前 Web 服务运行态（Dart 侧 updateState 同步） */
        @Volatile
        var running: Boolean = false
    }

    private var channel: MethodChannel? = null

    override fun onStartListening() {
        super.onStartListening()
        bindChannel()
        refreshTile()
    }

    override fun onStopListening() {
        channel?.setMethodCallHandler(null)
        channel = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val engine: FlutterEngine = EngineHolder.engine ?: return
        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("toggle", null)
        } catch (_: Exception) {
            // Dart 侧未就绪：忽略本次点击
        }
    }

    private fun bindChannel() {
        val engine: FlutterEngine = EngineHolder.engine ?: return
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateState" -> {
                        running = call.argument<Boolean>("running") ?: false
                        refreshTile()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun refreshTile() {
        qsTile?.run {
            state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            updateTile()
        }
    }
}
