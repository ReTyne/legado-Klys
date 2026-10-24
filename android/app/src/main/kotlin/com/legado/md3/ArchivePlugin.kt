package com.legado.md3

import com.github.junrar.Archive
import com.github.junrar.rarfile.FileHeader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.Base64

/**
 * 7z / rar 压缩包原生解压（Flutter 侧无对应 Dart 解码器）。
 *
 * 对应 legado-E 的 LibArchiveUtils（libarchive）能力：
 *  - extractEntry：读取包内指定文件内容（书源 java.get7zStringContent / getRarStringContent）
 *  - extractAll：整包解压，返回 [{name, data(base64)}] 列表（java.un7zFile / unrarFile）
 *
 * 依赖：
 *  - org.apache.commons:commons-compress（7z，纯 Java）
 *  - com.github.junrar:junrar（rar，纯 Java）
 *
 * MethodChannel('legado/archive')：
 *  - ping -> Boolean
 *  - extractEntry {kind, data(base64), entry} -> base64 或 null
 *  - extractAll {kind, data(base64)} -> [{name, data(base64)}] 或 null
 */
class ArchivePlugin : FlutterPlugin {

    companion object {
        const val CHANNEL = "legado/archive"
        private const val MAX_ENTRIES = 5000
        private const val MAX_TOTAL_BYTES = 512L * 1024 * 1024
        private const val BUF = 64 * 1024
    }

    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> result.success(true)
            "extractEntry" -> {
                val kind = (call.argument<String>("kind") ?: "").lowercase()
                val bytes = decodeB64(call.argument<String>("data") ?: "")
                val entry = call.argument<String>("entry") ?: ""
                if (bytes == null || entry.isEmpty()) {
                    result.success(null)
                    return
                }
                try {
                    val content = when (kind) {
                        "7z" -> read7zEntry(bytes, entry)
                        "rar" -> readRarEntry(bytes, entry)
                        else -> null
                    }
                    result.success(content?.let { encodeB64(it) })
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            "extractAll" -> {
                val kind = (call.argument<String>("kind") ?: "").lowercase()
                val bytes = decodeB64(call.argument<String>("data") ?: "")
                if (bytes == null) {
                    result.success(null)
                    return
                }
                try {
                    val entries = when (kind) {
                        "7z" -> read7zAll(bytes)
                        "rar" -> readRarAll(bytes)
                        else -> null
                    }
                    result.success(entries)
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    // ---------- 7z ----------

    private fun read7zEntry(bytes: ByteArray, entry: String): ByteArray? {
        SevenZFile(ByteArrayInputStream(bytes)).use { z ->
            var e: SevenZArchiveEntry? = z.nextEntry
            while (e != null) {
                if (!e.isDirectory && (e.name == entry || e.name.endsWith("/$entry"))) {
                    return readAll(z)
                }
                e = z.nextEntry
            }
        }
        return null
    }

    private fun read7zAll(bytes: ByteArray): List<Map<String, String>> {
        val out = ArrayList<Map<String, String>>()
        var total = 0L
        SevenZFile(ByteArrayInputStream(bytes)).use { z ->
            var e: SevenZArchiveEntry? = z.nextEntry
            while (e != null && out.size < MAX_ENTRIES && total < MAX_TOTAL_BYTES) {
                if (!e.isDirectory) {
                    val data = readAll(z)
                    total += data.size
                    out.add(mapOf("name" to e.name, "data" to encodeB64(data)))
                }
                e = z.nextEntry
            }
        }
        return out
    }

    // ---------- rar ----------

    private fun readRarEntry(bytes: ByteArray, entry: String): ByteArray? {
        Archive(ByteArrayInputStream(bytes)).use { archive ->
            var header: FileHeader? = archive.nextFileHeader()
            while (header != null) {
                if (!header.isDirectory &&
                    (header.fileName == entry || header.fileName.endsWith("/$entry"))
                ) {
                    val os = ByteArrayOutputStream()
                    archive.extractFile(header, os)
                    return os.toByteArray()
                }
                header = archive.nextFileHeader()
            }
        }
        return null
    }

    private fun readRarAll(bytes: ByteArray): List<Map<String, String>> {
        val out = ArrayList<Map<String, String>>()
        var total = 0L
        Archive(ByteArrayInputStream(bytes)).use { archive ->
            var header: FileHeader? = archive.nextFileHeader()
            while (header != null && out.size < MAX_ENTRIES && total < MAX_TOTAL_BYTES) {
                if (!header.isDirectory) {
                    val os = ByteArrayOutputStream()
                    archive.extractFile(header, os)
                    val data = os.toByteArray()
                    total += data.size
                    out.add(mapOf("name" to header.fileName, "data" to encodeB64(data)))
                }
                header = archive.nextFileHeader()
            }
        }
        return out
    }

    // ---------- 工具 ----------

    /** commons-compress 的 SevenZFile 无 readBytes()，手动循环读取当前条目。 */
    private fun readAll(z: SevenZFile): ByteArray {
        val buf = ByteArrayOutputStream()
        val tmp = ByteArray(BUF)
        while (true) {
            val n = z.read(tmp, 0, tmp.size)
            if (n <= 0) break
            buf.write(tmp, 0, n)
        }
        return buf.toByteArray()
    }

    private fun decodeB64(s: String): ByteArray? =
        if (s.isEmpty()) null else try {
            Base64.getDecoder().decode(s)
        } catch (e: Exception) {
            null
        }

    private fun encodeB64(bytes: ByteArray): String =
        Base64.getEncoder().encodeToString(bytes)
}
