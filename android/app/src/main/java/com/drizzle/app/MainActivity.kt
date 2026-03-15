package com.drizzle.app

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.*
import androidx.activity.ComponentActivity
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File
import java.net.URL

class MainActivity : ComponentActivity() {

    private lateinit var webView: WebView
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val radarDir: File by lazy {
        File(filesDir, "radar").also { it.mkdirs() }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Edge-to-edge dark background
        window.statusBarColor = 0xFF0D1117.toInt()
        window.navigationBarColor = 0xFF0D1117.toInt()

        webView = WebView(this).apply {
            setBackgroundColor(0xFF0D1117.toInt())
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            settings.cacheMode = WebSettings.LOAD_DEFAULT
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
                return assetLoader.shouldInterceptRequest(request.url)
            }

            override fun onPageFinished(view: WebView, url: String) {
                // Inject shim that maps chrome.webview API to our NativeBridge
                view.evaluateJavascript(BRIDGE_SHIM, null)
            }
        }

        webView.loadUrl("https://app.local/radar-map.html")
    }

    override fun onDestroy() {
        scope.cancel()
        // Clean radar cache on exit
        radarDir.listFiles()?.forEach { it.delete() }
        super.onDestroy()
    }

    @Suppress("unused")
    inner class JsBridge {
        @JavascriptInterface
        fun postMessage(message: String) {
            val parts = message.split("|", limit = 3)
            when (parts[0]) {
                "DOWNLOAD" -> {
                    if (parts.size == 3) {
                        val region = parts[1]
                        val url = parts[2]
                        // Sanitize region
                        if (!region.matches(Regex("^[a-zA-Z0-9]+$"))) return
                        // Whitelist URL
                        if (!url.startsWith("https://sirocco.accuweather.com/")) return
                        scope.launch { downloadRadarGif(region, url) }
                    }
                }
                "CLEARCACHE" -> {
                    radarDir.listFiles()?.forEach { it.delete() }
                    postToWebView("""{"type":"cacheCleared"}""")
                }
                "CACHESIZE" -> {
                    val files = radarDir.listFiles()?.filter { it.extension == "gif" } ?: emptyList()
                    val bytes = files.sumOf { it.length() }
                    postToWebView("""{"type":"cacheSize","bytes":$bytes,"count":${files.size}}""")
                }
            }
        }
    }

    private suspend fun downloadRadarGif(region: String, url: String) {
        try {
            val dest = File(radarDir, "$region.gif")
            URL(url).openStream().use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            if (dest.length() > 5120) {
                postToWebView("""{"type":"radarReady","region":"$region","file":"$region.gif"}""")
            } else {
                dest.delete()
                postToWebView("""{"type":"radarError","region":"$region","error":"Response too small"}""")
            }
        } catch (e: Exception) {
            postToWebView("""{"type":"radarError","region":"$region","error":"Download failed"}""")
        }
    }

    private fun postToWebView(json: String) {
        val escaped = json.replace("\\", "\\\\").replace("'", "\\'")
        runOnUiThread {
            webView.evaluateJavascript(
                "window.chrome.webview._dispatch($escaped)", null
            )
        }
    }

    companion object {
        // Shim that makes the HTML think it's running in WebView2
        private const val BRIDGE_SHIM = """
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
