package com.legado.md3

import android.content.Intent
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.util.Rational

class MainActivity : FlutterActivity() {

    private val channelName = "legado/file_intent"
    private val wakeChannelName = "legado/wakelock"

    /** 音频前台服务控制频道（见 AudioNotifyService） */
    private val audioChannelName = "legado/audio_notify"

    /** legado:// 深链 / 系统分享文本 导入频道 */
    private val deepLinkChannelName = "legado/deep_link"

    /** 书源 java.openVideoPlayer 的原生视频播放频道（对齐 legado-E openVideoPlayer） */
    private val videoChannelName = "legado/video"

    /** 网络类型判断频道：供 cover_onlyWifi 精确区分 WiFi / 移动数据 */
    private val networkChannelName = "legado/network"

    // ---- 第十轮新增通道（严格使用约定字符串，现有 9 通道行为不变） ----
    private val readerProviderChannelName = "legado/reader_provider"
    private val shortcutChannelName = "legado/shortcut"
    private val mediaButtonChannelName = "legado/media_button"
    private val pipChannelName = "legado/pip"
    private val pdfCoverChannelName = "legado/pdf_cover"
    private val mobiHuffChannelName = "legado/mobi_huff"
    private val launcherIconChannelName = "legado/launcher_icon"
    private val batteryChannelName = "legado/battery"
    private val brightnessChannelName = "legado/brightness"
    private val processTextChannelName = "legado/process_text"
    private val safChannelName = "legado/saf"

    /** 判断当前活跃网络是否为 WiFi（对齐 legado-E NetworkUtils.isWifi）。 */
    private fun isWifi(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = cm.activeNetwork ?: return false
                val caps = cm.getNetworkCapabilities(network) ?: return false
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            } else {
                @Suppress("DEPRECATION")
                val info = cm.activeNetworkInfo ?: return false
                info.isConnected && info.type == ConnectivityManager.TYPE_WIFI
            }
        } catch (_: Exception) {
            false
        }
    }
    private var pendingPath: String? = null
    private var channel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null

    /** 电量/时间广播与系统亮度 ContentObserver（onDestroy 注销） */
    private var batteryReceiver: BroadcastReceiver? = null
    private var brightnessObserver: ContentObserver? = null

    /** 待 Dart 取走的深链/分享链接（Dart 未就绪时缓存） */
    private var pendingLink: String? = null
    private var deepLinkChannel: MethodChannel? = null

    /**
     * 复用应用级共享引擎：这样播放页关闭后 Dart 侧播放器仍随引擎存活，
     * AudioNotifyService 也能通过同一个 BinaryMessenger 控制播放。
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        EngineHolder.obtain(context)

    /** 引擎不随宿主销毁（后台播放需要） */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 7z/rar 原生解压（Dart 侧 ArchiveNative，书源 java.un7zFile/unrarFile 等）
        flutterEngine.plugins.add(ArchivePlugin())
        pendingPath = resolveIntent(intent)
        pendingLink = handleDeepLinkIntent(intent)
        // 第十轮：启动期缓存 PROCESS_TEXT 选中文本 / 快捷方式动作，Dart 就绪后取走
        NativeChannels.pendingProcessText = resolveProcessText(intent)
        NativeChannels.pendingShortcut = resolveShortcut(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                val p = pendingPath
                pendingPath = null
                result.success(p)
            } else {
                result.notImplemented()
            }
        }
        // legado:// 深链 / 系统分享文本：Dart 主动取初始链接，运行中再经 onLink 推送
        deepLinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deepLinkChannelName)
        deepLinkChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                val link = pendingLink
                pendingLink = null
                result.success(link)
            } else {
                result.notImplemented()
            }
        }
        // 书源 java.openVideoPlayer：用系统原生视频播放器打开（K 风格原生实现）。
        // Dart 侧 legado://video 协议 handler 会 invokeMethod('open', {url, title})。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url")
                    val title = call.argument<String>("title") ?: "视频播放"
                    if (url.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        val ok = try {
                            // 交给系统/已安装的视频播放器：ACTION_VIEW + video/*，
                            // 支持 http(s)/content/file 等书源常见视频地址，无需额外依赖。
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse(url), "video/*")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                putExtra(Intent.EXTRA_TITLE, title)
                            }
                            startActivity(Intent.createChooser(intent, title))
                            true
                        } catch (_: Exception) {
                            // 无可用播放器 / bad URI：静默失败，Dart 侧降级到内置播放页
                            false
                        }
                        result.success(ok)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 网络类型判断（cover_onlyWifi）：保留 isWifi；第十轮扩展为事件化回调。
        val networkCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannelName)
        NativeChannels.network = networkCh
        networkCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "isWifi" -> result.success(isWifi())
                "getState" -> result.success(NetworkCallbackHelper.currentState(this))
                "startWatch" -> {
                    NetworkCallbackHelper.register(this)
                    result.success(true)
                }
                "stopWatch" -> {
                    NetworkCallbackHelper.unregister()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // 屏幕常亮控制
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wakeChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    enableWakeLock()
                    result.success(null)
                }
                "disable" -> {
                    disableWakeLock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // 音频前台服务 + 媒体通知栏控制
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    // 播放开始：拉起前台服务（此时应用一定在前台）
                    val i = Intent(this, AudioNotifyService::class.java)
                        .setAction(AudioNotifyService.ACTION_START)
                    i.putExtra(AudioNotifyService.EXTRA_TITLE, call.argument<String>("title"))
                    i.putExtra(AudioNotifyService.EXTRA_SUBTITLE, call.argument<String>("subtitle"))
                    i.putExtra(
                        AudioNotifyService.EXTRA_PLAYING,
                        call.argument<Boolean>("playing") ?: false,
                    )
                    try {
                        startService(i)
                    } catch (_: Exception) {
                        // 系统拒绝（后台启动限制）：通知不可用但不崩溃
                    }
                    result.success(null)
                }
                "update" -> {
                    val svc = AudioNotifyService.instance
                    if (svc != null) {
                        // 服务已在运行：直接更新，避免后台 startService 被系统拒绝
                        svc.updateFromDart(
                            call.argument<String>("title"),
                            call.argument<String>("subtitle"),
                            call.argument<Boolean>("playing"),
                        )
                    }
                    // 服务不在运行（用户从通知栏停止 / 已被系统回收）：
                    // 不重新拉起，否则「停止」后会被随后的 pause 事件又拉起来
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, AudioNotifyService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ==================== 第十轮：原生 Android 能力域（按现有风格追加） ====================
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 1) ReaderProvider 数据桥：Provider 的 16 条 URI 查询经此通道原生 -> Dart，
        //    Dart -> 原生仅用 cache 预置共享 JSON 兜底文件。
        val readerCh = MethodChannel(messenger, readerProviderChannelName)
        ReaderProviderBridge.channel = readerCh
        readerCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "cache" -> {
                    val entries = HashMap<String, String>()
                    (call.arguments as? Map<*, *>)?.forEach { (k, v) ->
                        if (k is String && v is String) entries[k] = v
                    }
                    ReaderProviderBridge.cache(this, entries)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 2) 动态快捷方式（书架/搜索/发现/继续阅读）
        val shortcutCh = MethodChannel(messenger, shortcutChannelName)
        NativeChannels.shortcut = shortcutCh
        shortcutCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "setShortcuts" -> result.success(ShortcutHelper.buildShortcuts(this))
                "removeShortcuts" -> result.success(ShortcutHelper.removeShortcuts(this))
                "getInitialShortcut" -> {
                    val id = NativeChannels.pendingShortcut
                    NativeChannels.pendingShortcut = null
                    result.success(id)
                }
                else -> result.notImplemented()
            }
        }

        // 3) 媒体按键 + MediaSessionCompat / AudioFocusRequest
        val mediaCh = MethodChannel(messenger, mediaButtonChannelName)
        NativeChannels.mediaButton = mediaCh
        mediaCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "activate" -> result.success(MediaSessionHelper.activate(this))
                "deactivate" -> result.success(MediaSessionHelper.deactivate())
                "setPlaybackState" -> result.success(
                    MediaSessionHelper.setPlaying(call.argument<Boolean>("playing") ?: false)
                )
                "drain" -> result.success(NativeChannels.drainMediaButtons())
                "getActive" -> result.success(MediaSessionHelper.active)
                else -> result.notImplemented()
            }
        }

        // 4) 系统 PiP
        val pipCh = MethodChannel(messenger, pipChannelName)
        NativeChannels.pip = pipCh
        pipCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> result.success(
                    enterPip(
                        call.argument<Int>("aspectWidth"),
                        call.argument<Int>("aspectHeight"),
                        call.argument<Boolean>("autoEnter") ?: false,
                    )
                )
                "isSupported" -> result.success(isPipSupported())
                "isInPip" -> result.success(isInPip())
                else -> result.notImplemented()
            }
        }

        // 5) PdfRenderer 首页封面
        MethodChannel(messenger, pdfCoverChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "render" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        result.success(
                            PdfCoverRenderer.render(
                                this,
                                path,
                                call.argument<Int>("width") ?: 480,
                                call.argument<Int>("height") ?: 720,
                            )
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 6) MOBI HUFF/CDIC 纯 Kotlin 解压
        MethodChannel(messenger, mobiHuffChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "decompress" -> {
                    val huff = call.argument<ByteArray>("huff")
                    val data = call.argument<ByteArray>("data")
                    if (huff == null || data == null) {
                        result.error("ARG", "huff/data required", null)
                    } else {
                        val cdics = (call.argument<List<*>>("cdics") ?: emptyList<Any?>())
                            .mapNotNull { it as? ByteArray }
                        try {
                            result.success(MobiHuffDecompressor.decompress(huff, cdics, data))
                        } catch (e: Exception) {
                            result.error("HUFF_ERROR", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 7) 动态桌面图标（7 个 activity-alias 启停）
        MethodChannel(messenger, launcherIconChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> result.success(
                    LauncherIconHelper.changeIcon(this, call.argument<String>("name"))
                )
                "getIcon" -> result.success(LauncherIconHelper.currentIcon(this))
                "getAliases" -> result.success(LauncherIconHelper.aliasNames())
                else -> result.notImplemented()
            }
        }

        // 8a) 真实电量 + ACTION_TIME_TICK / ACTION_BATTERY_CHANGED 事件
        val batteryCh = MethodChannel(messenger, batteryChannelName)
        NativeChannels.battery = batteryCh
        batteryCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLevel" -> result.success(DeviceInfoHelper.battery(this))
                "startWatch" -> {
                    registerBatteryReceiver()
                    result.success(true)
                }
                "stopWatch" -> {
                    unregisterBatteryReceiver()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 8b) 系统亮度（Settings.System）/ 窗口亮度 + ContentObserver
        val brightnessCh = MethodChannel(messenger, brightnessChannelName)
        NativeChannels.brightness = brightnessCh
        brightnessCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystem" -> result.success(DeviceInfoHelper.systemBrightness(this))
                "setSystem" -> {
                    val v = call.argument<Int>("value")
                    result.success(
                        if (v == null) false else DeviceInfoHelper.setSystemBrightness(this, v)
                    )
                }
                "canWrite" -> result.success(DeviceInfoHelper.canWriteSettings(this))
                "openWriteSettings" -> result.success(DeviceInfoHelper.openWriteSettings(this))
                "getWindow" -> result.success(DeviceInfoHelper.windowBrightness(this))
                "setWindow" -> {
                    val raw = call.argument<Any>("value")
                    val v = when (raw) {
                        is Double -> raw
                        is Int -> raw.toDouble()
                        else -> -1.0
                    }
                    result.success(DeviceInfoHelper.setWindowBrightness(this, v))
                }
                "startWatch" -> {
                    registerBrightnessObserver()
                    result.success(true)
                }
                "stopWatch" -> {
                    unregisterBrightnessObserver()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 10a) ACTION_PROCESS_TEXT：选中文本送 Dart（与现有 deep_link 通道并存）
        val processTextCh = MethodChannel(messenger, processTextChannelName)
        NativeChannels.processText = processTextCh
        processTextCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialText" -> {
                    val t = NativeChannels.pendingProcessText
                    NativeChannels.pendingProcessText = null
                    result.success(t)
                }
                else -> result.notImplemented()
            }
        }

        // 10b) SAF（ACTION_OPEN_DOCUMENT_TREE 持久权限）+ FileProvider
        MethodChannel(messenger, safChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDocumentTree" -> SafHelper.pickDocumentTree(this, result)
                "getPersistedUris" -> result.success(SafHelper.persistedTreeUris(this))
                "releasePermission" -> {
                    val uri = call.argument<String>("uri")
                    result.success(
                        if (uri.isNullOrEmpty()) false else SafHelper.releasePermission(this, uri)
                    )
                }
                "getUriForFile" -> {
                    val p = call.argument<String>("path")
                    result.success(if (p.isNullOrEmpty()) null else SafHelper.getUriForFile(this, p))
                }
                "shareFile" -> {
                    val p = call.argument<String>("path")
                    result.success(
                        if (p.isNullOrEmpty()) false
                        else SafHelper.shareFile(
                            this, p, call.argument<String>("mime"), call.argument<String>("title")
                        )
                    )
                }
                "openFile" -> {
                    val p = call.argument<String>("path")
                    result.success(
                        if (p.isNullOrEmpty()) false
                        else SafHelper.openFile(this, p, call.argument<String>("mime"))
                    )
                }
                else -> result.notImplemented()
            }
        }

        // 默认启动网络事件化与系统亮度观察（Dart 可用 startWatch/stopWatch 再控制）
        NetworkCallbackHelper.register(this)
        registerBrightnessObserver()
    }

    private fun enableWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE, "legado:reading")
        wakeLock?.acquire()
    }

    private fun disableWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    override fun onDestroy() {
        disableWakeLock()
        unregisterBatteryReceiver()
        unregisterBrightnessObserver()
        NetworkCallbackHelper.unregister()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val p = resolveIntent(intent)
        if (p != null) {
            pendingPath = p
            channel?.invokeMethod("onFileOpened", p)
        }
        // 深链/分享：singleTop 复用模式下新 Intent 走这里
        val link = handleDeepLinkIntent(intent)
        if (link != null) {
            pendingLink = link
            try {
                deepLinkChannel?.invokeMethod("onLink", link)
            } catch (_: Exception) {
                // Dart 侧 handler 未就绪：缓存待 getInitialLink 取走
            }
        }
        // 第十轮：运行中收到新的 PROCESS_TEXT / 快捷方式动作，主动推给 Dart
        resolveProcessText(intent)?.let { NativeChannels.emitProcessText(it) }
        resolveShortcut(intent)?.let { NativeChannels.emitShortcut(it) }
    }

    /**
     * 解析深链 / 分享 Intent，返回统一格式的链接字符串（无匹配返回 null）：
     *  - legado://import?url=... / legado://import?type=bookSource&json=...：原样透传
     *  - ACTION_SEND 文本（URL 或 JSON）：包装为 share://text?content=<encoded>
     */
    private fun handleDeepLinkIntent(intent: Intent?): String? {
        if (intent == null) return null
        return try {
            when (intent.action) {
                Intent.ACTION_VIEW -> {
                    val uri: Uri = intent.data ?: return null
                    if (uri.scheme == "legado") uri.toString() else null
                }
                Intent.ACTION_SEND -> {
                    if (intent.type?.startsWith("text/plain") != true) return null
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
                    if (text.isNullOrEmpty()) {
                        null
                    } else {
                        "share://text?content=${Uri.encode(text)}"
                    }
                }
                // 系统文本选择菜单（选中文本后弹出本应用入口，对齐 E process_text）
                Intent.ACTION_PROCESS_TEXT -> {
                    if (intent.type?.startsWith("text/plain") != true) return null
                    val text = intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)?.trim()
                    if (text.isNullOrEmpty()) {
                        null
                    } else {
                        "share://text?content=${Uri.encode(text)}"
                    }
                }
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun resolveIntent(intent: Intent?): String? {
        val uri: Uri = intent?.data ?: return null
        return try {
            when (uri.scheme) {
                "file" -> uri.path
                "content" -> {
                    val name = uri.lastPathSegment ?: "opened_${System.currentTimeMillis()}"
                    val out = File(cacheDir, sanitize(name))
                    contentResolver.openInputStream(uri)?.use { input ->
                        out.outputStream().use { o -> input.copyTo(o) }
                    }
                    out.absolutePath
                }
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun sanitize(name: String): String {
        val base = name.substringAfterLast('/')
        return if (base.contains('.')) base else "$base.txt"
    }

    // -------------------- 第十轮：辅助实现 --------------------

    /** PiP 可用性：API >= O 且设备声明支持 */
    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun isInPip(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode

    /** enterPictureInPictureMode + PictureInPictureParams.Builder（API >= O 保护） */
    private fun enterPip(width: Int?, height: Int?, autoEnter: Boolean): Boolean {
        if (!isPipSupported()) return false
        return try {
            val builder = PictureInPictureParams.Builder()
            if (width != null && height != null && width > 0 && height > 0) {
                builder.setAspectRatio(Rational(width, height))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(autoEnter)
            }
            enterPictureInPictureMode(builder.build())
        } catch (_: Exception) {
            false
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        NativeChannels.emitPipModeChanged(isInPictureInPictureMode)
    }

    /** SAF ACTION_OPEN_DOCUMENT_TREE 结果回传（同时保留 super 给 Flutter 插件） */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        SafHelper.onActivityResult(this, requestCode, resultCode, data)
    }

    private fun resolveProcessText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_PROCESS_TEXT) return null
        return intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun resolveShortcut(intent: Intent?): String? =
        intent?.getStringExtra(ShortcutHelper.EXTRA_SHORTCUT)?.trim()?.takeIf { it.isNotEmpty() }

    private fun registerBatteryReceiver() {
        if (batteryReceiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) {
                when (i?.action) {
                    Intent.ACTION_BATTERY_CHANGED ->
                        NativeChannels.emitBatteryChanged(DeviceInfoHelper.battery(this@MainActivity))
                    Intent.ACTION_TIME_TICK -> NativeChannels.emitTimeTick()
                }
            }
        }
        batteryReceiver = r
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
                addAction(Intent.ACTION_TIME_TICK)
            }
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(r, filter)
        } catch (_: Exception) {
            batteryReceiver = null
        }
    }

    private fun unregisterBatteryReceiver() {
        batteryReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        batteryReceiver = null
    }

    private fun registerBrightnessObserver() {
        if (brightnessObserver != null) return
        brightnessObserver = DeviceInfoHelper.registerBrightnessObserver(this) { value ->
            NativeChannels.emitBrightnessChanged(mapOf("value" to value))
        }
    }

    private fun unregisterBrightnessObserver() {
        brightnessObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {
            }
        }
        brightnessObserver = null
    }
}
