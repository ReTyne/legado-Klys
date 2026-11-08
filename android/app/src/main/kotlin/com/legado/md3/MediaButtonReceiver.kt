package com.legado.md3

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.view.KeyEvent

/**
 * ACTION_MEDIA_BUTTON 耳机/蓝牙/锁屏媒体键接收（对齐 Sigma receiver/MediaButtonReceiver.kt）。
 *
 * Sigma 在原生直接判 `mediaButtonPerNext` 决定切章/切段落；本项目把按键语义
 * 完整解析后经 `legado/media_button` 通道转发给 Dart，由 Dart 侧（含该开关）
 * 决定切章、切朗读段落或播放/暂停，从而真实连通朗读控制。
 */
class MediaButtonReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return
        @Suppress("DEPRECATION")
        val keyEvent = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return
        if (keyEvent.action != KeyEvent.ACTION_DOWN) return

        val action = when (keyEvent.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
            KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK -> "playPause"
            KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "prev"
            KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "fastForward"
            KeyEvent.KEYCODE_MEDIA_REWIND -> "rewind"
            else -> "unknown"
        }

        NativeChannels.emitMediaButton(
            mapOf(
                "action" to action,
                "keyCode" to keyEvent.keyCode,
                "repeatCount" to keyEvent.repeatCount,
                "source" to "receiver",
            )
        )
        if (isOrderedBroadcast) abortBroadcast()
    }

    companion object {
        const val CHANNEL = "legado/media_button"
    }
}
