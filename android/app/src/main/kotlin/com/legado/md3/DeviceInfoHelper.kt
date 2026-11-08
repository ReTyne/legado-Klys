package com.legado.md3

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings

/**
 * 真实电量 + 系统亮度 / 窗口亮度（对齐 Sigma TimeBatteryReceiver 与
 * ui_main §6.2「真实系统亮度 SCREEN_BRIGHTNESS + ContentObserver」）。
 */
object DeviceInfoHelper {

    /** 读 ACTION_BATTERY_CHANGED sticky 广播，返回电量明细 */
    fun battery(context: Context): Map<String, Any?> {
        val i = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return mapOf(
                "level" to -1, "scale" to -1, "percent" to -1,
                "status" to -1, "plugged" to 0, "health" to -1,
                "temperature" to -1, "charging" to false,
            )
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val status = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = i.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val health = i.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)
        val temperature = i.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
        val percent = if (scale > 0) level * 100 / scale else -1
        return mapOf(
            "level" to level,
            "scale" to scale,
            "percent" to percent,
            "status" to status,
            "plugged" to plugged,
            "health" to health,
            "temperature" to temperature,
            "charging" to (
                status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL || plugged > 0
                ),
        )
    }

    fun systemBrightness(context: Context): Int = try {
        Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
    } catch (_: Exception) {
        -1
    }

    fun canWriteSettings(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.System.canWrite(context)
        } else {
            true
        }

    fun setSystemBrightness(context: Context, value: Int): Boolean {
        if (!canWriteSettings(context)) return false
        return try {
            Settings.System.putInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                value.coerceIn(0, 255),
            )
            // 关闭自动亮度，否则系统亮度值会被自动模式覆盖
            try {
                Settings.System.putInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL,
                )
            } catch (_: Exception) {
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 打开系统「修改系统设置」授权页（WRITE_SETTINGS 为特殊权限） */
    fun openWriteSettings(context: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val i = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(i)
            true
        } else {
            false
        }
    } catch (_: Exception) {
        false
    }

    /** 当前窗口亮度：-1 表示跟随系统，其余为 0..1 */
    fun windowBrightness(activity: Activity): Double {
        val v = activity.window?.attributes?.screenBrightness ?: return -1.0
        return if (v < 0f) -1.0 else v.toDouble()
    }

    fun setWindowBrightness(activity: Activity, value: Double): Boolean = try {
        val lp = activity.window.attributes
        lp.screenBrightness = if (value < 0) {
            -1f
        } else {
            value.toFloat().coerceIn(0.01f, 1f)
        }
        activity.window.attributes = lp
        true
    } catch (_: Exception) {
        false
    }

    /** 监听系统亮度变化，返回 observer 供反注册 */
    fun registerBrightnessObserver(context: Context, onChange: (Int) -> Unit): ContentObserver? {
        val uri = Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS) ?: return null
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                onChange(systemBrightness(context))
            }
        }
        return try {
            context.contentResolver.registerContentObserver(uri, false, observer)
            observer
        } catch (_: Exception) {
            null
        }
    }
}
