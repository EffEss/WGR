package com.drizzle.app

import android.annotation.SuppressLint
import android.os.Bundle
import android.os.Looper
import android.webkit.*
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.*
import java.io.DataInputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity() {

    private lateinit var webView: WebView
    private lateinit var insetsController: WindowInsetsControllerCompat
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var backgroundedAtMs: Long = 0L
    private val radarCacheLock = Any()
    private var cacheGeneration = 0

    private val radarDir: File by lazy {
        File(filesDir, "radar").also { it.mkdirs() }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Modern edge-to-edge setup (Android 15+ ready)
        enableEdgeToEdge()

        // Dark bars for transient reveal state
        window.statusBarColor = 0xFF0D1117.toInt()
        window.navigationBarColor = 0xFF0D1117.toInt()

        // Immersive behavior via WindowInsetsControllerCompat (replaces deprecated
        // systemUiVisibility flags)
        insetsController = WindowInsetsControllerCompat(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        hideSystemBars()

        webView = WebView(this).apply {
            setBackgroundColor(0xFF0D1117.toInt())
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            // Keep HTML UI sizing stable across OEM/system accessibility scaling.
            // The page has its own responsive CSS for small screens.
            settings.textZoom = 100
        }
        setContentView(webView)

        // Serve bundled assets from assets/ via https://app.local/
        val assetLoader = WebViewAssetLoader.Builder()
            .setDomain("app.local")
            .addPathHandler("/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        // JS bridge: receives postMessage calls from the HTML
        webView.addJavascriptInterface(JsBridge(), "NativeBridge")

        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView, request: WebResourceRequest
            ): WebResourceResponse? {
                val url = request.url
                if (url.host == "radar-cache.local") {
                    val name = url.lastPathSegment ?: return null
                    if (!name.matches(Regex("^[a-zA-Z0-9_.]+$"))) return null
                    val file = File(radarDir, name)
                    if (file.exists()) {
                        return WebResourceResponse("image/gif", null, file.inputStream())
                    }
                    return null
                }
                // Inject bridge shim into radar-map.html before any page JS runs
                if (url.host == "app.local" && url.path?.contains("radar-map.html") == true) {
                    val html = assets.open("radar-map.html").bufferedReader().readText()
                    val shimScript = "<script>$BRIDGE_SHIM_RAW</script>"
                    val patched = html.replaceFirst("<head>", "<head>$shimScript")
                    return WebResourceResponse(
                        "text/html", "utf-8",
                        patched.byteInputStream(Charsets.UTF_8)
                    )
                }
                return assetLoader.shouldInterceptRequest(request.url)
            }
        }

        webView.loadUrl("https://app.local/radar-map.html")
    }

    override fun onStart() {
        super.onStart()
        val now = System.currentTimeMillis()

        if (backgroundedAtMs > 0L) {
            val elapsed = now - backgroundedAtMs
            if (elapsed >= STALE_BACKGROUND_MS) {
                pruneExpiredRadarGifs(now)
                // Force refresh of whatever region/state is currently selected.
                webView.post {
                    webView.evaluateJavascript(
                        "if (window.refreshCurrent) { window.refreshCurrent(); }",
                        null
                    )
                }
            }
            backgroundedAtMs = 0L
        }
    }

    override fun onStop() {
        super.onStop()
        backgroundedAtMs = System.currentTimeMillis()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    private fun hideSystemBars() {
        insetsController.hide(WindowInsetsCompat.Type.systemBars())
    }

    @Suppress("unused")
    inner class JsBridge {
        @JavascriptInterface
        fun postMessage(message: String) {
            val parts = message.split("|", limit = 4)
            when (parts[0]) {
                "DOWNLOAD" -> {
                    if (parts.size != 4) return
                    val (_, key, legacyKey, url) = parts
                    if (!CACHE_KEY.matches(key) || !LEGACY_KEY.matches(legacyKey)) return
                    if (!url.startsWith(SIROCCO_BASE)) return
                    scope.launch { downloadRadarGif(key, legacyKey, url) }
                }
                "LOOKUPCACHE" -> {
                    val key = parts.getOrNull(1) ?: return
                    if (!CACHE_KEY.matches(key)) return
                    scope.launch {
                        synchronized(radarCacheLock) {
                            pruneExpiredRadarGifs()
                            val file = File(radarDir, "$key.gif")
                            if (file.length() > MIN_GIF_BYTES) {
                                postRadarReady(key, file, cached = true, event = "cacheLookup")
                            } else {
                                postToWebView("""{"type":"cacheLookup","key":"$key"}""")
                            }
                        }
                    }
                }
                "CLEARCACHE" -> {
                    scope.launch {
                        clearAllAppCaches()
                        postToWebView("""{"type":"cacheCleared"}""")
                        postCacheSize()
                    }
                }
                "CACHESIZE" -> postCacheSize()
            }
        }
    }

    private fun downloadRadarGif(key: String, legacyKey: String, url: String) {
        val dest = File(radarDir, "$key.gif")
        var temporary: File? = null
        try {
            val generation = synchronized(radarCacheLock) {
                pruneExpiredRadarGifs()
                val hasLegacyEntry = legacyKey.isNotEmpty() && key.startsWith("radar_") && key.endsWith("_true")
                if (!dest.exists() && hasLegacyEntry) {
                    val legacy = File(radarDir, "$legacyKey.gif")
                    if (legacy.length() > MIN_GIF_BYTES) legacy.renameTo(dest)
                }
                if (dest.length() > MIN_GIF_BYTES) {
                    postRadarReady(key, dest, cached = true)
                    return
                }
                cacheGeneration
            }

            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = NETWORK_TIMEOUT_MS
            connection.readTimeout = NETWORK_TIMEOUT_MS
            try {
                val status = connection.responseCode
                if (status != HttpURLConnection.HTTP_OK) {
                    postRadarError(key, "HTTP $status", status)
                    return
                }
                val download = File.createTempFile("sirocco-", ".tmp", radarDir)
                temporary = download
                connection.inputStream.use { input ->
                    download.outputStream().use { output -> input.copyTo(output) }
                }
                if (download.length() <= MIN_GIF_BYTES || !hasGifHeader(download)) {
                    postRadarError(key, "Invalid GIF response")
                    return
                }
                synchronized(radarCacheLock) {
                    when {
                        generation != cacheGeneration -> postRadarError(key, "Cache cleared")
                        download.renameTo(dest) -> postRadarReady(key, dest, cached = false)
                        else -> postRadarError(key, "Could not cache GIF")
                    }
                }
            } finally {
                connection.disconnect()
            }
        } catch (_: Exception) {
            postRadarError(key, "Download failed")
        } finally {
            temporary?.delete()
        }
    }

    private fun hasGifHeader(file: File): Boolean = DataInputStream(file.inputStream()).use { input ->
        val bytes = ByteArray(6)
        input.readFully(bytes)
        val header = String(bytes, Charsets.US_ASCII)
        header == "GIF87a" || header == "GIF89a"
    }

    private fun postRadarReady(key: String, file: File, cached: Boolean, event: String = "radarReady") {
        postToWebView(
            """{"type":"$event","key":"$key","file":"${file.name}","cached":$cached,"time":${file.lastModified()}}"""
        )
    }

    private fun postRadarError(key: String, error: String, status: Int? = null) {
        postToWebView("""{"type":"radarError","key":"$key","status":$status,"error":"$error"}""")
    }

    private fun clearAllAppCaches() {
        // Radar file cache used by the custom bridge
        clearRadarGifs()

        // WebView runtime caches/storage must be cleared on main thread.
        runWebViewClearOnMainThread()

        // App cache directory (best-effort)
        cacheDir.deleteRecursively()
        cacheDir.mkdirs()
    }

    private fun runWebViewClearOnMainThread() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            webView.clearCache(true)
            webView.clearHistory()
            webView.clearFormData()
            WebStorage.getInstance().deleteAllData()
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
            return
        }

        val latch = CountDownLatch(1)
        runOnUiThread {
            webView.clearCache(true)
            webView.clearHistory()
            webView.clearFormData()
            WebStorage.getInstance().deleteAllData()
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
            latch.countDown()
        }
        latch.await(2, TimeUnit.SECONDS)
    }

    private fun pruneExpiredRadarGifs(nowMs: Long = System.currentTimeMillis()) {
        synchronized(radarCacheLock) {
            radarDir.listFiles()?.forEach { file ->
                if (file.extension == "gif" && nowMs - file.lastModified() >= STALE_BACKGROUND_MS) {
                    file.delete()
                }
            }
        }
    }

    private fun clearRadarGifs() {
        synchronized(radarCacheLock) {
            cacheGeneration++
            radarDir.listFiles()?.filter { it.extension == "gif" }?.forEach { it.delete() }
        }
    }

    private fun postCacheSize() {
        val files = radarDir.listFiles()?.filter { it.extension == "gif" } ?: emptyList()
        val bytes = files.sumOf { it.length() }
        postToWebView("""{"type":"cacheSize","bytes":$bytes,"count":${files.size}}""")
    }

    private fun postToWebView(json: String) {
        val escaped = json.replace("\\", "\\\\").replace("'", "\\'")
        runOnUiThread {
            webView.evaluateJavascript(
                "window.chrome.webview._dispatch('$escaped')", null
            )
        }
    }

    companion object {
        private const val STALE_BACKGROUND_MS = 5 * 60 * 1000L
        private const val NETWORK_TIMEOUT_MS = 15_000
        private const val MIN_GIF_BYTES = 5120L
        private const val SIROCCO_BASE = "https://sirocco.accuweather.com/"
        private val CACHE_KEY = Regex("^(radar|sat_ei|sat_ir)_[a-z0-9]+_?_(true|false)$")
        private val LEGACY_KEY = Regex("^[A-Z0-9]*$")

        // Raw JS shim injected into <head> before any page scripts run
        private const val BRIDGE_SHIM_RAW = """
            (function() {
                var listeners = [];
                window.chrome = window.chrome || {};
                window.chrome.webview = {
                    postMessage: function(msg) { NativeBridge.postMessage(msg); },
                    addEventListener: function(type, fn) { if (type === 'message') listeners.push(fn); },
                    _dispatch: function(data) {
                        var e = { data: typeof data === 'string' ? JSON.parse(data) : data };
                        listeners.forEach(function(fn) { fn(e); });
                    }
                };
            })();
        """
    }
}
