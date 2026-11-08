package com.legado.md3

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * 动态快捷方式（对齐 Sigma `api/ShortCuts.kt` 的 ShortcutInfoCompat/IconCompat/setIntents
 * 回退栈思路，按本轮要求扩展为 4 个：书架 / 搜索 / 发现 / 继续阅读）。
 *
 * 所有快捷方式都指向唯一的 MainActivity，用 extra [EXTRA_SHORTCUT] 携带动作 id，
 * MainActivity 经 `legado/shortcut` 通道推给 Dart 侧路由；「继续阅读」用
 * setIntents 构造 [书架 -> 阅读] 的返回栈。
 */
object ShortcutHelper {

    const val EXTRA_SHORTCUT = "shortcut"
    const val ID_BOOKSHELF = "bookshelf"
    const val ID_SEARCH = "search"
    const val ID_DISCOVER = "discover"
    const val ID_LAST_READ = "lastRead"

    private fun intent(context: Context, id: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(EXTRA_SHORTCUT, id)
        }

    private fun icon(context: Context): IconCompat =
        IconCompat.createWithResource(context, R.mipmap.ic_launcher)

    private fun builder(context: Context, id: String, label: String): ShortcutInfoCompat.Builder =
        ShortcutInfoCompat.Builder(context, id)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(icon(context))

    /** 注册 4 个动态快捷方式，返回成功注册的数量 */
    fun buildShortcuts(context: Context): Int {
        val list = listOf(
            builder(context, ID_BOOKSHELF, "书架")
                .setIntent(intent(context, ID_BOOKSHELF))
                .build(),
            builder(context, ID_SEARCH, "搜索")
                .setIntent(intent(context, ID_SEARCH))
                .build(),
            builder(context, ID_DISCOVER, "发现")
                .setIntent(intent(context, ID_DISCOVER))
                .build(),
            // 继续阅读：返回栈 = 书架 -> 阅读（对齐 Sigma lastRead 的 setIntents）
            builder(context, ID_LAST_READ, "继续阅读")
                .setIntents(
                    arrayOf(
                        intent(context, ID_BOOKSHELF),
                        intent(context, ID_LAST_READ),
                    )
                )
                .build(),
        )
        return try {
            if (ShortcutManagerCompat.setDynamicShortcuts(context, list)) list.size else 0
        } catch (_: Exception) {
            0
        }
    }

    fun removeShortcuts(context: Context): Boolean = try {
        ShortcutManagerCompat.removeAllDynamicShortcuts(context)
        true
    } catch (_: Exception) {
        false
    }

    fun ids(): List<String> = listOf(ID_BOOKSHELF, ID_SEARCH, ID_DISCOVER, ID_LAST_READ)
}
