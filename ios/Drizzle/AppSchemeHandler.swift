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

        guard let fileURL = Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "Assets") else {
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
