import UIKit
import WebKit

class RadarViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {

    private var webView: WKWebView!
    private var backgroundedAt: Date?
    private var cacheGeneration = 0
    private let radarDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("radar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 13/255, green: 17/255, blue: 23/255, alpha: 1)

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "bridge")

        // Inject shim that maps chrome.webview → our bridge
        let shim = WKUserScript(source: Self.bridgeShim, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(shim)

        let cssInjection = """
        (function(){try{
          var style = document.createElement('style');
          style.textContent = `
            .leaflet-radar-pane img, .leaflet-world-base-pane canvas { pointer-events: none !important; }
            .leaflet-hit-pane canvas { pointer-events: auto !important; }
            svg, svg * { pointer-events: auto !important; }
          `;
          document.documentElement.appendChild(style);
        } catch(e) {}}
        )();
        """
        let cssScript = WKUserScript(source: cssInjection, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(cssScript)

        let layeringFix = """
        (function(){
          try {
            function looksLikeRadar(bg) {
              if (!bg) return false;
              bg = String(bg).toLowerCase();
              return bg.includes('.gif') || bg.includes('accuweather') || bg.includes('radar');
            }
            function patchNode(el) {
              try {
                // If it's an IMG that looks like radar, disable hit-testing
                if (el.tagName === 'IMG') {
                  var src = (el.getAttribute('src') || '').toLowerCase();
                  if (src.includes('.gif') || src.includes('accuweather') || src.includes('radar')) {
                    el.style.pointerEvents = 'none';
                  }
                }
                // If it has a radar-looking background, disable hit-testing
                var cs = window.getComputedStyle(el);
                if (cs && looksLikeRadar(cs.backgroundImage)) {
                  el.style.pointerEvents = 'none';
                }
                // Ensure SVG overlays are clickable and above
                if (el instanceof SVGElement || (el.querySelector && el.querySelector('svg'))) {
                  var svgs = (el instanceof SVGElement) ? [el] : el.querySelectorAll('svg');
                  svgs.forEach(function(svg){
                    svg.style.pointerEvents = 'auto';
                    svg.style.position = 'relative';
                    svg.style.zIndex = '1000';
                    svg.style.touchAction = 'manipulation';
                    svg.querySelectorAll('*').forEach(function(n){ n.style.pointerEvents = 'auto'; });
                  });
                }
              } catch (_) {}
            }
            // Initial pass over existing nodes
            Array.prototype.forEach.call(document.querySelectorAll('*'), patchNode);
            // Observe future DOM changes
            var observer = new MutationObserver(function(muts){
              muts.forEach(function(m){
                if (m.addedNodes) {
                  m.addedNodes.forEach(function(n){
                    if (n && n.nodeType === 1) {
                      patchNode(n);
                      if (n.querySelectorAll) Array.prototype.forEach.call(n.querySelectorAll('*'), patchNode);
                    }
                  });
                }
              });
            });
            observer.observe(document.documentElement, { childList: true, subtree: true });
          } catch (e) {}
        })();
        """
        let layeringScript = WKUserScript(source: layeringFix, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        controller.addUserScript(layeringScript)

        config.userContentController = controller

        // Register custom scheme handler for app.local and radar-cache.local
        config.setURLSchemeHandler(AppSchemeHandler(radarDir: radarDir), forURLScheme: "app")

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.navigationDelegate = self
        view.addSubview(webView)

        // Load bundled HTML via custom scheme
        if let url = URL(string: "app://local/radar-map.html") {
            webView.load(URLRequest(url: url))
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? String else { return }
        let parts = body.components(separatedBy: "|")
        guard let command = parts.first else { return }

        switch command {
        case "DOWNLOAD":
            guard parts.count == 4, isCacheKey(parts[1]) else { return }
            let key = parts[1]
            let legacyKey = parts[2]
            guard legacyKey.range(of: #"\A[A-Z0-9]*\z"#, options: .regularExpression) != nil,
                  let url = URL(string: parts[3]),
                  url.scheme == "https", url.host == "sirocco.accuweather.com",
                  url.user == nil, url.password == nil, url.port == nil,
                  url.path.hasSuffix(".gif") else {
                postRadarError(key: key, error: "Invalid download request")
                return
            }
            downloadRadarGif(key: key, legacyKey: legacyKey, url: url)

        case "LOOKUPCACHE":
            guard parts.count == 2, isCacheKey(parts[1]) else { return }
            let key = parts[1]
            pruneExpiredRadarGifs()
            let file = radarDir.appendingPathComponent("\(key).gif")
            if let time = cachedGifDate(file) {
                postRadarReady(key: key, file: file, cached: true, time: time, event: "cacheLookup")
            } else {
                postToWebView(["type": "cacheLookup", "key": key])
            }

        case "CLEARCACHE":
            clearAllCaches {
                self.postToWebView(["type": "cacheCleared"])
            }

        case "CACHESIZE":
            let files = (try? FileManager.default.contentsOfDirectory(at: radarDir, includingPropertiesForKeys: [.fileSizeKey]))?.filter { $0.pathExtension == "gif" } ?? []
            let bytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
            postToWebView(["type": "cacheSize", "bytes": bytes, "count": files.count])

        default:
            break
        }
    }

    // MARK: - Networking

    private func isCacheKey(_ key: String) -> Bool {
        key.range(of: #"\A(radar|sat_ei|sat_ir)_[a-z0-9]+_?_(true|false)\z"#,
                  options: .regularExpression) != nil
    }

    private func downloadRadarGif(key: String, legacyKey: String, url: URL) {
        pruneExpiredRadarGifs()

        let dest = radarDir.appendingPathComponent("\(key).gif")
        let files = FileManager.default
        if !files.fileExists(atPath: dest.path), !legacyKey.isEmpty,
           key.hasPrefix("radar_"), key.hasSuffix("_true") {
            let legacy = radarDir.appendingPathComponent("\(legacyKey).gif")
            if cachedGifDate(legacy) != nil {
                try? files.moveItem(at: legacy, to: dest)
            }
        }
        if let time = cachedGifDate(dest) {
            postRadarReady(key: key, file: dest, cached: true, time: time)
            return
        }

        let generation = cacheGeneration
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard generation == self.cacheGeneration else {
                    self.postRadarError(key: key, error: "Cache cleared")
                    return
                }
                guard error == nil, let status = (response as? HTTPURLResponse)?.statusCode else {
                    self.postRadarError(key: key, error: "Download failed")
                    return
                }
                guard status == 200 else {
                    self.postRadarError(key: key, error: "HTTP \(status)", status: status)
                    return
                }
                guard let data, data.count > self.minimumGifBytes,
                      data.starts(with: "GIF87a".utf8) || data.starts(with: "GIF89a".utf8) else {
                    self.postRadarError(key: key, error: "Invalid GIF response")
                    return
                }
                do {
                    try FileManager.default.createDirectory(at: self.radarDir, withIntermediateDirectories: true)
                    try data.write(to: dest, options: .atomic)
                    let time = self.cachedGifDate(dest) ?? Date()
                    self.postRadarReady(key: key, file: dest, cached: false, time: time)
                } catch {
                    self.postRadarError(key: key, error: "Could not cache GIF")
                }
            }
        }.resume()
    }

    private func postRadarReady(key: String, file: URL, cached: Bool, time: Date, event: String = "radarReady") {
        postToWebView([
            "type": event, "key": key, "file": file.lastPathComponent,
            "cached": cached, "time": Int64(time.timeIntervalSince1970 * 1000)
        ])
    }

    private func postRadarError(key: String, error: String, status: Int? = nil) {
        var event: [String: Any] = ["type": "radarError", "key": key, "error": error]
        if let status { event["status"] = status }
        postToWebView(event)
    }

    private func cleanRadarCache() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: radarDir, includingPropertiesForKeys: nil) {
            files.filter { $0.pathExtension == "gif" }.forEach { try? fm.removeItem(at: $0) }
        }
    }

    private func clearAllCaches(completion: @escaping () -> Void) {
        cacheGeneration += 1
        cleanRadarCache()

        URLCache.shared.removeAllCachedResponses()

        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let fromDate = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: allTypes, modifiedSince: fromDate) {
            completion()
        }
    }

    @objc private func appDidEnterBackground() {
        backgroundedAt = Date()
    }

    @objc private func appWillEnterForeground() {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil

        if Date().timeIntervalSince(backgroundedAt) >= staleBackgroundSeconds {
            pruneExpiredRadarGifs()
            webView.evaluateJavaScript(
                "if (window.refreshCurrent) { window.refreshCurrent(); }",
                completionHandler: nil
            )
        }
    }

    private func pruneExpiredRadarGifs(now: Date = Date()) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: radarDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where file.pathExtension.lowercased() == "gif" {
            if cachedGifDate(file, now: now) == nil {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func cachedGifDate(_ file: URL, now: Date = Date()) -> Date? {
        guard let info = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = info.contentModificationDate,
              let size = info.fileSize, size > minimumGifBytes,
              now.timeIntervalSince(modified) < staleBackgroundSeconds else { return nil }
        return modified
    }

    private func postToWebView(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript("window.chrome.webview._dispatch(\(json))")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Bridge shim

    private let staleBackgroundSeconds: TimeInterval = 5 * 60
    private let minimumGifBytes = 5120

    static let bridgeShim = """
    (function() {
        var listeners = [];
        window.RADAR_CACHE_PREFIX = 'app://radar-cache.local/';
        window.chrome = window.chrome || {};
        window.chrome.webview = {
            postMessage: function(msg) { window.webkit.messageHandlers.bridge.postMessage(msg); },
            addEventListener: function(type, fn) { if (type === 'message') listeners.push(fn); },
            _dispatch: function(data) {
                if (typeof data === 'string') data = JSON.parse(data);
                var e = { data: data };
                listeners.forEach(function(fn) { fn(e); });
            }
        };
    })();
    """
}
