package com.legado.md3

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/**
 * PdfRenderer 首页封面（对齐 Sigma / 分析 §6.2 PdfRenderer + ParcelFileDescriptor + Bitmap）。
 *
 * 渲染 PDF 第 0 页为 PNG 存入 cacheDir/pdf_covers，返回绝对路径供 Dart 侧
 * 作为本地书封面显示。支持普通文件路径与 content:// URI。
 */
object PdfCoverRenderer {

    fun render(context: Context, path: String, maxWidth: Int, maxHeight: Int): String? {
        // PdfRenderer 自 API 21 提供
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        val wLimit = if (maxWidth > 0) maxWidth.coerceAtMost(2048) else 480
        val hLimit = if (maxHeight > 0) maxHeight.coerceAtMost(2048) else 720

        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null
        var bitmap: Bitmap? = null
        return try {
            val descriptor = openParcel(context, path) ?: return null
            pfd = descriptor
            val r = PdfRenderer(descriptor)
            renderer = r
            if (r.pageCount <= 0) return null
            val p = r.openPage(0)
            page = p
            val pw = p.width.coerceAtLeast(1)
            val ph = p.height.coerceAtLeast(1)
            val (tw, th) = fit(pw, ph, wLimit, hLimit)
            val bmp = Bitmap.createBitmap(tw, th, Bitmap.Config.ARGB_8888)
            bitmap = bmp
            bmp.eraseColor(Color.WHITE)
            p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

            val dir = File(context.cacheDir, "pdf_covers")
            if (!dir.exists()) dir.mkdirs()
            val out = File(dir, "${key(path)}.png")
            FileOutputStream(out).use { fos ->
                bmp.compress(Bitmap.CompressFormat.PNG, 90, fos)
            }
            out.absolutePath
        } catch (_: Exception) {
            null
        } finally {
            try { page?.close() } catch (_: Exception) {}
            try { renderer?.close() } catch (_: Exception) {}
            try { pfd?.close() } catch (_: Exception) {}
            bitmap?.recycle()
        }
    }

    /** 等比缩放，限制在 maxW x maxH 内 */
    private fun fit(w: Int, h: Int, maxW: Int, maxH: Int): Pair<Int, Int> {
        val ratio = w.toFloat() / h.toFloat()
        return if (ratio >= maxW.toFloat() / maxH.toFloat()) {
            Pair(maxW, (maxW / ratio).toInt().coerceAtLeast(1))
        } else {
            Pair((maxH * ratio).toInt().coerceAtLeast(1), maxH)
        }
    }

    private fun openParcel(context: Context, path: String): ParcelFileDescriptor? =
        try {
            if (path.startsWith("content://")) {
                context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
            } else {
                val f = File(path)
                if (f.isFile) ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
                else null
            }
        } catch (_: Exception) {
            null
        }

    private fun key(s: String): String = try {
        MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    } catch (_: Exception) {
        s.hashCode().toString()
    }
}
