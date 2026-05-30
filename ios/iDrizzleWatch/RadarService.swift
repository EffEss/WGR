import Foundation

/// Ports the radar download/cache/region logic from the iOS app (RadarViewController.swift)
/// and the shared Assets/radar-map.html so the watch shows identical AccuWeather mosaics.
final class RadarService {

	static let shared = RadarService()

	// MARK: - Endpoint + region tables (mirrors Assets/radar-map.html)

	static let radarBase = "https://sirocco.accuweather.com/nx_mosaic_640x480_public/sir/"

	static let regionFiles: [String: String] = [
		"NORCAL": "inmasirCAn.gif", "CENTRALCAL": "inmasirCAc.gif", "SOCAL": "inmasirCAs.gif",
		"TXW": "inmasirTXw.gif", "TXE": "inmasirTXe.gif", "TXS": "inmasirTXs.gif",
		"NORTHEAST": "inmasirne.gif", "NORTHCENTRAL": "inmasirnc.gif", "NORTHWEST": "inmasirnw.gif",
		"SOUTHEAST": "inmasirse.gif", "SOUTHCENTRAL": "inmasirsc.gif", "SOUTHWEST": "inmasirsw.gif",
		"USA": "inmasirus_.gif"
	]

	/// Regions surfaced in the watch picker (same primary set as the phone bottom bar).
	static let regionKeys = ["USA", "NORTHWEST", "NORTHCENTRAL", "NORTHEAST",
							 "SOUTHWEST", "SOUTHCENTRAL", "SOUTHEAST"]

	static let regionDisplay: [String: String] = [
		"USA": "🌎 USA", "NORTHWEST": "Northwest", "NORTHCENTRAL": "North Central",
		"NORTHEAST": "Northeast", "SOUTHWEST": "Southwest", "SOUTHCENTRAL": "South Central",
		"SOUTHEAST": "Southeast",
		"NORCAL": "N. California", "CENTRALCAL": "C. California", "SOCAL": "S. California"
	]

	static func displayName(for region: String) -> String {
		regionDisplay[region] ?? region
	}

	// MARK: - Cache directory

	let radarDir: URL = {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("radar")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}()

	// MARK: - URL resolution (mirrors resolveRadarUrl in radar-map.html)

	func resolveRadarUrl(region: String) -> URL? {
		if let file = Self.regionFiles[region] {
			return URL(string: Self.radarBase + file)
		}
		return URL(string: Self.radarBase + "inmasir" + region.lowercased() + "_.gif")
	}

	// MARK: - Download + cache

	enum RadarError: Error {
		case badRegion
		case downloadFailed
		case responseTooSmall
	}

	/// Downloads the radar GIF for a region, caches it on disk, and returns the local file URL.
	func fetchRadarGif(region: String,
					   completion: @escaping (Result<URL, Error>) -> Void) {
		// Sanitize region the same way the iOS bridge does.
		guard region.allSatisfy({ $0.isLetter || $0.isNumber }),
			  let url = resolveRadarUrl(region: region),
			  url.absoluteString.hasPrefix("https://sirocco.accuweather.com/") else {
			completion(.failure(RadarError.badRegion))
			return
		}

		URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
			guard let self = self, let tempURL = tempURL, error == nil else {
				completion(.failure(RadarError.downloadFailed))
				return
			}
			let dest = self.radarDir.appendingPathComponent("\(region).gif")
			try? FileManager.default.removeItem(at: dest)
			do {
				try FileManager.default.moveItem(at: tempURL, to: dest)
				let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
				if size > 5120 {
					completion(.success(dest))
				} else {
					try? FileManager.default.removeItem(at: dest)
					completion(.failure(RadarError.responseTooSmall))
				}
			} catch {
				completion(.failure(RadarError.downloadFailed))
			}
		}.resume()
	}

	// MARK: - Cache maintenance

	func cachedGifs() -> [URL] {
		let files = (try? FileManager.default.contentsOfDirectory(
			at: radarDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
		return files.filter { $0.pathExtension == "gif" }
	}

	func cacheSize() -> (count: Int, bytes: Int) {
		let files = cachedGifs()
		let bytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
			.reduce(0, +)
		return (files.count, bytes)
	}

	func clearCache() {
		let fm = FileManager.default
		cachedGifs().forEach { try? fm.removeItem(at: $0) }
	}
}
