package com.legado.md3

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * 动态桌面图标（对齐 Sigma `help/LauncherIconHelp.kt` + AndroidManifest 7 个
 * Launcher1..7 别名）。通过 PackageManager.setComponentEnabledSetting 启停别名组件
 * 切换 LAUNCHER 入口；DONT_KILL_APP 避免切换时重启进程。
 */
object LauncherIconHelper {

    val ALIASES: List<String> = listOf(
        ".Launcher1", ".Launcher2", ".Launcher3", ".Launcher4",
        ".Launcher5", ".Launcher6", ".Launcher7",
    )

    /**
     * 切换图标。name 支持 "Launcher3" / "3" / "default"（恢复默认）。
     * 返回是否成功执行（setComponentEnabledSetting 未抛异常）。
     */
    fun changeIcon(context: Context, name: String?): Boolean {
        val wanted = normalize(name)
        return try {
            val pm = context.packageManager
            ALIASES.forEach { alias ->
                val cn = ComponentName(context, context.packageName + alias)
                val state = if (alias == wanted) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                }
                pm.setComponentEnabledSetting(cn, state, PackageManager.DONT_KILL_APP)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 当前启用的别名短名，未启用任何别名返回 "default" */
    fun currentIcon(context: Context): String {
        return try {
            val pm = context.packageManager
            ALIASES.firstOrNull { alias ->
                pm.getComponentEnabledSetting(
                    ComponentName(context, context.packageName + alias)
                ) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            }?.substringAfterLast('.') ?: "default"
        } catch (_: Exception) {
            "default"
        }
    }

    fun aliasNames(): List<String> = ALIASES.map { it.substringAfterLast('.') }

    private fun normalize(name: String?): String? {
        val n = name?.trim().orEmpty()
        if (n.isEmpty() || n.equals("default", true) || n.equals("MainActivity", true)) {
            return null
        }
        if (n.length <= 2 && n.all { it.isDigit() }) {
            val idx = n.toInt() - 1
            if (idx in ALIASES.indices) return ALIASES[idx]
        }
        return ALIASES.firstOrNull {
            it.equals(n, true) || it.substringAfterLast('.').equals(n, true)
        }
    }
}
