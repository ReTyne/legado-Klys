package com.legado.md3

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat

/**
 * 朗读媒体会话：MediaSessionCompat + AudioFocusRequest（对齐 Sigma
 * BaseReadAloudService / AudioPlayService 的媒体会话与音频焦点链路）。
 *
 * 活跃会话通过 setMediaButtonReceiver 把 ACTION_MEDIA_BUTTON 显式路由给
 * [MediaButtonReceiver]；音频焦点被抢占时经 `legado/media_button` 推 "pause"
 * 给 Dart。会话生命周期由 Dart 侧 `activate` / `deactivate` 控制，独立于
 * Activity，因此后台朗读仍可接收媒体键。
 */
object MediaSessionHelper {

    @Volatile
    var active: Boolean = false
        private set

    private var session: MediaSessionCompat? = null
    private var focusRequest: AudioFocusRequest? = null
    private var focusListener: AudioManager.OnAudioFocusChangeListener? = null

    fun activate(context: Context): Boolean {
        if (active) return true
        return try {
            val appCtx = context.applicationContext
            val pi = PendingIntent.getBroadcast(
                appCtx,
                0,
                Intent(appCtx, MediaButtonReceiver::class.java)
                    .setAction(Intent.ACTION_MEDIA_BUTTON),
                pendingFlags(),
            )
            val s = MediaSessionCompat(appCtx, "LegadoReadAloud").apply {
                setFlags(
                    MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                        MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
                )
                setMediaButtonReceiver(pi)
                isActive = true
                setPlaybackState(buildState(false))
            }
            session = s
            requestFocus(appCtx)
            active = true
            true
        } catch (_: Exception) {
            false
        }
    }

    fun setPlaying(playing: Boolean): Boolean {
        val s = session ?: return false
        return try {
            s.setPlaybackState(buildState(playing))
            true
        } catch (_: Exception) {
            false
        }
    }

    fun deactivate(): Boolean {
        return try {
            abandonFocus()
            session?.let {
                it.isActive = false
                it.release()
            }
            session = null
            active = false
            true
        } catch (_: Exception) {
            active = false
            false
        }
    }

    private fun buildState(playing: Boolean): PlaybackStateCompat =
        PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_STOP
            )
            .setState(
                if (playing) PlaybackStateCompat.STATE_PLAYING
                else PlaybackStateCompat.STATE_PAUSED,
                0L,
                if (playing) 1f else 0f,
            )
            .build()

    private fun requestFocus(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        focusContext = context.applicationContext
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            if (change == AudioManager.AUDIOFOCUS_LOSS ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
            ) {
                NativeChannels.emitMediaButton(
                    mapOf("action" to "pause", "keyCode" to 0, "source" to "audioFocus")
                )
            }
        }
        focusListener = listener
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setOnAudioFocusChangeListener(listener)
                .build()
            focusRequest = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
    }

    private fun abandonFocus() {
        val ctx = focusContext
        val manager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        try {
            if (manager != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    focusRequest?.let { manager.abandonAudioFocusRequest(it) }
                } else {
                    @Suppress("DEPRECATION")
                    focusListener?.let { manager.abandonAudioFocus(it) }
                }
            }
        } catch (_: Exception) {
        }
        focusRequest = null
        focusListener = null
        focusContext = null
    }

    @Volatile
    private var focusContext: Context? = null

    private fun pendingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
}
