import UIKit
import WebKit

class RadarViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {

    private var webView: WKWebView!
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
            img[src$=".gif"], canvas { pointer-events: none !important; }
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

        // Keep storage tight on launch: retain only one latest GIF.
        pruneRadarCacheToLatest(keepRegion: nil)

        // Load bundled HTML via custom scheme
        if let url = URL(string: "app://local/radar-map.html") {
            webView.load(URLRequest(url: url))
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        let parts = body.components(separatedBy: "|")
        guard let command = parts.first else { return }

        switch command {
        case "DOWNLOAD":
            guard parts.count == 3 else { return }
            let region = parts[1]
            let urlString = parts[2]
            // Sanitize region
            guard region.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }
            // Whitelist URL
            guard urlString.hasPrefix("https://sirocco.accuweather.com/") else { return }
            guard let url = URL(string: urlString) else { return }
            downloadRadarGif(region: region, url: url)

        case "CLEARCACHE":
            clearAllCaches {
                self.postToWebView(json: #"{"type":"cacheCleared"}"#)
            }

        case "CACHESIZE":
            let files = (try? FileManager.default.contentsOfDirectory(at: radarDir, includingPropertiesForKeys: [.fileSizeKey]))?.filter { $0.pathExtension == "gif" } ?? []
            let bytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
            postToWebView(json: #"{"type":"cacheSize","bytes":\#(bytes),"count":\#(files.count)}"#)

        default:
            break
        }
    }

    // MARK: - Networking

    private func downloadRadarGif(region: String, url: URL) {
        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self, let tempURL = tempURL, error == nil else {
                self?.postToWebView(json: #"{"type":"radarError","region":"\#(region)","error":"Download failed"}"#)
                return
            }
            let dest = self.radarDir.appendingPathComponent("\(region).gif")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 5120 {
                    self.pruneRadarCacheToLatest(keepRegion: region)
                    self.postToWebView(json: #"{"type":"radarReady","region":"\#(region)","file":"\#(region).gif"}"#)
                } else {
                    try? FileManager.default.removeItem(at: dest)
                    self.postToWebView(json: #"{"type":"radarError","region":"\#(region)","error":"Response too small"}"#)
                }
            } catch {
                self.postToWebView(json: #"{"type":"radarError","region":"\#(region)","error":"Download failed"}"#)
            }
        }.resume()
    }

    private func cleanRadarCache() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: radarDir, includingPropertiesForKeys: nil) {
            files.filter { $0.pathExtension == "gif" }.forEach { try? fm.removeItem(at: $0) }
        }
    }

    private func pruneRadarCacheToLatest(keepRegion: String?) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: radarDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter({ $0.pathExtension.lowercased() == "gif" }) else { return }

        if let keepRegion {
            let keepName = "\(keepRegion).gif"
            files.forEach { if $0.lastPathComponent != keepName { try? fm.removeItem(at: $0) } }
            return
        }

        guard let newest = files.max(by: {
            let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l < r
        }) else { return }

        files.forEach { if $0 != newest { try? fm.removeItem(at: $0) } }
    }

    private func clearAllCaches(completion: @escaping () -> Void) {
        cleanRadarCache()

        URLCache.shared.removeAllCachedResponses()

        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let fromDate = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: allTypes, modifiedSince: fromDate) {
            completion()
        }
    }

    private func postToWebView(json: String) {
        let escaped = json.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript("window.chrome.webview._dispatch('\(escaped)')")
        }
    }

    deinit {
    }

    // MARK: - Bridge shim

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
