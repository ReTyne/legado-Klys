package com.legado.md3

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.UriMatcher
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * ReaderProvider：对齐 Sigma `api/ReaderProvider.kt` 的 16 条 addURI 契约。
 *
 * 与 Sigma 的差异（数据源）：Sigma 直接操作 Room；本项目 DB 在 Dart 侧
 * (`app_database.dart`)，故经 [ReaderProviderBridge] 通过 `legado/reader_provider`
 * 通道向 Dart 查询（原生 -> Dart），Dart 返回统一 ReturnData JSON 字符串，
 * 这里用 MatrixCursor(arrayOf("result"), 1) 包装返回给跨进程调用方。
 * 若 Flutter 引擎尚未就绪，退化为读取 Dart 侧预先通过 `cache` 方法写入的
 * 共享 JSON 文件（见 [ReaderProviderBridge.cache]）。
 *
 * 相对 Sigma 基准三处缺陷（分析 §3.1 N3）的修正：
 *  - 5 条 rss* URI 映射到正确的 Rss* 请求码（Sigma 误映射到 BookSource 码）；
 *  - delete 按请求码分派，不再把 DeleteRssSources 调错控制器；
 *  - SaveBookProgress 能力并入 `book/insert`（json body 携带进度），不留死代码。
 */
class ReaderProvider : ContentProvider() {

    private enum class Code(val path: String, val op: String) {
        SaveBookSource("bookSource/insert", "insert"),
        SaveBookSources("bookSources/insert", "insert"),
        DeleteBookSources("bookSources/delete", "delete"),
        GetBookSource("bookSource/query", "query"),
        GetBookSources("bookSources/query", "query"),
        SaveRssSource("rssSource/insert", "insert"),
        SaveRssSources("rssSources/insert", "insert"),
        DeleteRssSources("rssSources/delete", "delete"),
        GetRssSource("rssSource/query", "query"),
        GetRssSources("rssSources/query", "query"),
        SaveBook("book/insert", "insert"),
        GetBookshelf("books/query", "query"),
        RefreshToc("book/refreshToc/query", "query"),
        GetChapterList("book/chapter/query", "query"),
        GetBookContent("book/content/query", "query"),
        GetBookCover("book/cover/query", "query"),
    }

    private val matcher by lazy {
        UriMatcher(UriMatcher.NO_MATCH).apply {
            // authorities 与 Manifest 的 ${applicationId}.readerProvider 一致
            val authority = "${context?.packageName}.readerProvider"
            Code.values().forEach { addURI(authority, it.path, it.ordinal + 1) }
        }
    }

    override fun onCreate(): Boolean {
        // 对齐 Sigma ReaderProvider.onCreate -> ShortCuts.buildShortCuts 联动
        context?.let { ShortcutHelper.buildShortcuts(it) }
        return true
    }

    override fun query(
        uri: Uri, projection: Array<String>?, selection: String?,
        selectionArgs: Array<String>?, sortOrder: String?,
    ): Cursor? {
        val code = resolve(uri) ?: return null
        return SimpleCursor(
            ReaderProviderBridge.dispatch(code.name, queryArgs(uri, code, selection, selectionArgs), context)
        )
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? {
        val code = resolve(uri) ?: return null
        val args = queryArgs(uri, code, null, null)
        values?.getAsString(BODY_KEY)?.let { args["json"] = it }
        ReaderProviderBridge.dispatch(code.name, args, context)
        return null
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int {
        val code = resolve(uri) ?: return -1
        ReaderProviderBridge.dispatch(
            code.name, queryArgs(uri, code, selection, selectionArgs), context
        )
        return 0
    }

    override fun update(
        uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?,
    ): Int = 0

    override fun getType(uri: Uri): String? = null

    private fun resolve(uri: Uri): Code? {
        val match = matcher.match(uri)
        if (match <= 0) return null
        return Code.values().getOrNull(match - 1)
    }

    private fun queryArgs(
        uri: Uri, code: Code, selection: String?, selectionArgs: Array<String>?,
    ): MutableMap<String, Any?> {
        val args = HashMap<String, Any?>()
        args["op"] = code.op
        args["code"] = code.name
        args["uri"] = uri.toString()
        uri.getQueryParameter("url")?.let { args["url"] = it }
        uri.getQueryParameter("index")?.let { args["index"] = it }
        uri.getQueryParameter("path")?.let { args["path"] = it }
        selection?.let { args["selection"] = it }
        selectionArgs?.let { args["selectionArgs"] = it.toList() }
        return args
    }

    /** 对齐 Sigma SimpleCursor：MatrixCursor(arrayOf("result"), 1)，仅 getString(0) 有意义 */
    private class SimpleCursor(json: String) : MatrixCursor(arrayOf("result"), 1) {
        init {
            addRow(arrayOf(json))
        }
    }

    companion object {
        const val CHANNEL = "legado/reader_provider"
        private const val BODY_KEY = "json"
    }
}

/**
 * Provider 与 Dart 数据桥之间的进程内同步桥。
 * ContentProvider 与 MainActivity 默认同进程，可共享 FlutterEngine 的 BinaryMessenger。
 */
object ReaderProviderBridge {

    private const val CACHE_DIR = "reader_provider_cache"
    private const val TIMEOUT_MS = 4000L

    @Volatile var channel: MethodChannel? = null

    /**
     * 同步拿到 Dart 侧返回的 ReturnData JSON 字符串。
     *
     * ContentProvider.query 运行在 Binder 线程，而 MethodChannel 的 Result 回调
     * 在平台主线程。为避免「阻塞主线程导致回调无法执行」的死锁，真正的
     * invokeMethod 与等待都放在独立工作线程，主线程只负责收发消息；调用线程
     * （Binder 线程）仅等待工作线程结束，并有超时保护。
     */
    fun dispatch(method: String, args: Map<String, Any?>, context: Context?): String {
        val ch = channel
        if (ch != null) {
            val json = syncInvoke(ch, method, args)
            if (json != null) return json
        }
        return readCache(context, method) ?: errorJson("Dart 数据桥未就绪，且无缓存数据")
    }

    private fun syncInvoke(ch: MethodChannel, method: String, args: Map<String, Any?>): String? {
        val response = AtomicReference<String?>(null)
        val done = CountDownLatch(1)
        val worker = Thread {
            val latch = CountDownLatch(1)
            NativeChannels.mainHandler.post {
                try {
                    ch.invokeMethod(method, args, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            response.set(result as? String)
                            latch.countDown()
                        }

                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            latch.countDown()
                        }

                        override fun notImplemented() {
                            latch.countDown()
                        }
                    })
                } catch (_: Exception) {
                    latch.countDown()
                }
            }
            try {
                latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
            }
            done.countDown()
        }
        worker.isDaemon = true
        worker.start()
        try {
            done.await(TIMEOUT_MS + 1000L, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
        }
        return response.get()
    }

    /** Dart 侧可预先把 16 类查询结果以 JSON 写入共享文件，供引擎未启动时兜底 */
    fun cache(context: Context?, entries: Map<String, String>) {
        val dir = cacheDir(context) ?: return
        if (!dir.exists()) dir.mkdirs()
        entries.forEach { (k, v) ->
            try {
                val safeKey = k.replace(Regex("[^A-Za-z0-9_]"), "_")
                File(dir, "$safeKey.json").writeText(v)
            } catch (_: Exception) {
            }
        }
    }

    private fun readCache(context: Context?, method: String): String? = try {
        val f = cacheDir(context)?.let { File(it, "$method.json") }
        if (f?.isFile == true) f.readText() else null
    } catch (_: Exception) {
        null
    }

    private fun cacheDir(context: Context?): File? =
        context?.filesDir?.let { File(it, CACHE_DIR) }

    private fun errorJson(msg: String): String {
        val safe = msg.replace("\\", "\\\\").replace("\"", "\\\"")
        return "{\"isSuccess\":false,\"errorMsg\":\"$safe\",\"data\":null}"
    }
}
