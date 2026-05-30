import Foundation
import WebKit

/// Serves bundled assets via app://local/ and radar cache via app://radar-cache.local/
class AppSchemeHandler: NSObject, WKURLSchemeHandler {

    private let radarDir: URL

    init(radarDir: URL) {
        self.radarDir = radarDir
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if host == "radar-cache.local" {
            // Serve cached radar GIFs from disk
            guard path.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }) else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }
            let file = radarDir.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: file.path),
                  let data = try? Data(contentsOf: file) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let response = URLResponse(url: url, mimeType: "image/gif", expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }

        // Serve bundled assets from the app bundle
        guard !path.contains("..") else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        if path == "radar-map.html" {
            guard let htmlURL = Bundle.main.url(forResource: "radar-map", withExtension: "html"),
                  let html = try? String(contentsOf: htmlURL, encoding: .utf8),
                  let geoURL = Bundle.main.url(forResource: "us-states.geo", withExtension: "json"),
                  let geoJSON = try? String(contentsOf: geoURL, encoding: .utf8) else {
                urlSchemeTask.didFailWithError(URLError(.cannotOpenFile))
                return
            }

            let escapedGeoJSON = geoJSON.replacingOccurrences(of: "</script", with: "<\\/script")
            let injection = "<script>window.__US_STATES_GEOJSON__ = \(escapedGeoJSON);</script>"
            let patchedHTML: String
            if html.contains("</head>") {
                patchedHTML = html.replacingOccurrences(of: "</head>", with: "\(injection)</head>")
            } else {
                patchedHTML = injection + html
            }

            guard let data = patchedHTML.data(using: .utf8) else {
                urlSchemeTask.didFailWithError(URLError(.cannotDecodeContentData))
                return
            }

            let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }

        let name = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        guard let fileURL = Bundle.main.url(forResource: name, withExtension: ext) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.cannotOpenFile))
            return
        }

        let mimeType: String
        if path.hasSuffix(".html") { mimeType = "text/html" }
        else if path.hasSuffix(".json") { mimeType = "application/json" }
        else { mimeType = "application/octet-stream" }

        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count,
                                   textEncodingName: path.hasSuffix(".html") ? "utf-8" : nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op; downloads are synchronous from disk
    }
}
