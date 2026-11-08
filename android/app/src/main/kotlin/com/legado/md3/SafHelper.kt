package com.legado.md3

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * SAF（ACTION_OPEN_DOCUMENT_TREE，持久 URI 权限）+ FileProvider 文件分享。
 *
 * 对齐分析 §6.2 / ui_main §6.2：defaultBookTreeUri / backupUri 等目录授权、
 * 以及把本地缓存/书籍文件以 content:// 形式安全地交给外部 App 打开或分享。
 * authority 与 Manifest 的 ${applicationId}.fileProvider 一致。
 */
object SafHelper {

    const val REQ_OPEN_DOCUMENT_TREE = 71021
    const val AUTHORITY_SUFFIX = ".fileProvider"

    @Volatile
    private var pendingResult: MethodChannel.Result? = null

    fun pickDocumentTree(activity: Activity, result: MethodChannel.Result) {
        // 若上一次调用未回调，先释放，避免悬挂
        pendingResult?.let {
            try { it.success(null) } catch (_: Exception) {}
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        try {
            activity.startActivityForResult(intent, REQ_OPEN_DOCUMENT_TREE)
        } catch (_: Exception) {
            pendingResult = null
            result.success(null)
        }
    }

    /** 由 MainActivity.onActivityResult 转发；返回是否由本 helper 消费 */
    fun onActivityResult(context: Context, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_OPEN_DOCUMENT_TREE) return false
        val result = pendingResult ?: return false
        pendingResult = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return true
        }
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            context.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: Exception) {
            // 部分 provider 只授予读权限
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
            }
        }
        result.success(uri.toString())
        return true
    }

    /** 已持久授权的目录 URI 列表 */
    fun persistedTreeUris(context: Context): List<String> = try {
        context.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission || it.isWritePermission }
            .map { it.uri.toString() }
    } catch (_: Exception) {
        emptyList()
    }

    fun releasePermission(context: Context, uri: String): Boolean = try {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        context.contentResolver.releasePersistableUriPermission(Uri.parse(uri), flags)
        true
    } catch (_: Exception) {
        false
    }

    /** 由 FileProvider 把本地路径映射为可授权的 content:// URI */
    fun getUriForFile(context: Context, path: String): String? = try {
        val file = File(path)
        if (!file.exists()) {
            null
        } else {
            FileProvider.getUriForFile(
                context,
                context.packageName + AUTHORITY_SUFFIX,
                file,
            ).toString()
        }
    } catch (_: Exception) {
        null
    }

    fun shareFile(activity: Activity, path: String, mime: String?, title: String?): Boolean {
        val uri = getUriForFile(activity, path)?.let { Uri.parse(it) } ?: return false
        return try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime ?: "*/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, title ?: File(path).name)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(intent, title ?: "分享文件"))
            true
        } catch (_: Exception) {
            false
        }
    }

    fun openFile(activity: Activity, path: String, mime: String?): Boolean {
        val uri = getUriForFile(activity, path)?.let { Uri.parse(it) } ?: return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(intent, "打开文件"))
            true
        } catch (_: Exception) {
            false
        }
    }
}
