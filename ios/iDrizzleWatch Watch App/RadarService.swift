import Foundation

/// Ports the radar download/cache/region logic from the iOS app (RadarViewController.swift)
/// and the shared Assets/radar-map.html so the watch shows identical AccuWeather mosaics.
final class RadarService {

	static let shared = RadarService()

	private init() {
		pruneCacheToLatest(keepRegion: nil)
	}

	// MARK: - Endpoint + region tables (mirrors Assets/radar-map.html)

	static let radarBase = "https://sirocco.accuweather.com/nx_mosaic_640x480_public/sir/"

	static let regionFiles: [String: String] = [
		"NORCAL": "inmasirCAn.gif", "CENTRALCAL": "inmasirCAc.gif", "SOCAL": "inmasirCAs.gif",
		"TXW": "inmasirTXw.gif", "TXE": "inmasirTXe.gif", "TXS": "inmasirTXs.gif",
		"NORTHEAST": "inmasirne.gif", "NORTHCENTRAL": "inmasirnc.gif", "NORTHWEST": "inmasirnw.gif",
		"SOUTHEAST": "inmasirse.gif", "SOUTHCENTRAL": "inmasirsc.gif", "SOUTHWEST": "inmasirsw.gif",
		"USA": "inmasirus_.gif"
	]

	/// Regions surfaced in the watch hierarchy (same primary set as the phone bottom bar).
	static let regionKeys = ["USA", "NORTHWEST", "NORTHCENTRAL", "NORTHEAST",
							 "SOUTHWEST", "SOUTHCENTRAL", "SOUTHEAST"]

	static let regionDisplay: [String: String] = [
		"USA": "🌎 USA", "NORTHWEST": "Northwest", "NORTHCENTRAL": "North Central",
		"NORTHEAST": "Northeast", "SOUTHWEST": "Southwest", "SOUTHCENTRAL": "South Central",
		"SOUTHEAST": "Southeast",
		"NORCAL": "N. California", "CENTRALCAL": "C. California", "SOCAL": "S. California",
		"TXW": "Texas West", "TXE": "Texas East", "TXS": "Texas South"
	]

	/// Direct state-name map from radar-map.html.
	static let stateNames: [String: String] = [
		"AL":"Alabama", "AZ":"Arizona", "AR":"Arkansas", "CA":"California", "CO":"Colorado",
		"CT":"Connecticut", "DE":"Delaware", "FL":"Florida", "GA":"Georgia",
		"ID":"Idaho", "IL":"Illinois", "IN":"Indiana", "IA":"Iowa", "KS":"Kansas", "KY":"Kentucky",
		"LA":"Louisiana", "ME":"Maine", "MD":"Maryland", "MA":"Massachusetts", "MI":"Michigan", "MN":"Minnesota",
		"MS":"Mississippi", "MO":"Missouri", "MT":"Montana", "NE":"Nebraska", "NV":"Nevada", "NH":"New Hampshire",
		"NJ":"New Jersey", "NM":"New Mexico", "NY":"New York", "NC":"North Carolina", "ND":"North Dakota",
		"OH":"Ohio", "OK":"Oklahoma", "OR":"Oregon", "PA":"Pennsylvania", "RI":"Rhode Island", "SC":"South Carolina",
		"SD":"South Dakota", "TN":"Tennessee", "TX":"Texas", "UT":"Utah", "VT":"Vermont", "VA":"Virginia",
		"WA":"Washington", "WV":"West Virginia", "WI":"Wisconsin", "WY":"Wyoming", "DC":"District of Columbia"
	]

	/// Fallback map from radar-map.html (plus DC -> NORTHEAST).
	/// Used only when loading a state that does not have its own GIF.
	static let stateFallbackRegion: [String: String] = [
		"ME":"NORTHEAST", "VT":"NORTHEAST", "NH":"NORTHEAST", "MA":"NORTHEAST", "CT":"NORTHEAST", "RI":"NORTHEAST",
		"NY":"NORTHEAST", "NJ":"NORTHEAST", "PA":"NORTHEAST", "DE":"NORTHEAST", "MD":"NORTHEAST", "DC":"NORTHEAST",
		"WA":"NORTHWEST", "OR":"NORTHWEST", "ID":"NORTHWEST", "MT":"NORTHWEST", "WY":"NORTHWEST",
		"MN":"NORTHCENTRAL", "WI":"NORTHCENTRAL", "MI":"NORTHCENTRAL", "ND":"NORTHCENTRAL", "SD":"NORTHCENTRAL",
		"NE":"NORTHCENTRAL", "IA":"NORTHCENTRAL",
		"VA":"SOUTHEAST", "WV":"SOUTHEAST", "NC":"SOUTHEAST", "SC":"SOUTHEAST", "GA":"SOUTHEAST",
		"FL":"SOUTHEAST", "KY":"SOUTHEAST", "TN":"SOUTHEAST",
		"TX":"SOUTHCENTRAL", "OK":"SOUTHCENTRAL", "AR":"SOUTHCENTRAL", "LA":"SOUTHCENTRAL", "MO":"SOUTHCENTRAL",
		"KS":"SOUTHCENTRAL", "MS":"SOUTHCENTRAL", "AL":"SOUTHCENTRAL",
		"CA":"SOCAL",
		"NV":"SOUTHWEST", "UT":"SOUTHWEST", "CO":"SOUTHWEST", "AZ":"SOUTHWEST", "NM":"SOUTHWEST"
	]

	/// Region membership for navigation (USA -> region -> state), including direct-state GIF states.
	static let stateNavigationRegion: [String: String] = [
		"WA":"NORTHWEST", "OR":"NORTHWEST", "ID":"NORTHWEST", "MT":"NORTHWEST", "WY":"NORTHWEST",
		"ND":"NORTHCENTRAL", "SD":"NORTHCENTRAL", "NE":"NORTHCENTRAL", "KS":"NORTHCENTRAL", "MN":"NORTHCENTRAL",
		"IA":"NORTHCENTRAL", "MO":"NORTHCENTRAL", "WI":"NORTHCENTRAL", "IL":"NORTHCENTRAL", "MI":"NORTHCENTRAL",
		"IN":"NORTHCENTRAL", "OH":"NORTHCENTRAL",
		"ME":"NORTHEAST", "VT":"NORTHEAST", "NH":"NORTHEAST", "MA":"NORTHEAST", "RI":"NORTHEAST", "CT":"NORTHEAST",
		"NY":"NORTHEAST", "PA":"NORTHEAST", "NJ":"NORTHEAST", "DE":"NORTHEAST", "MD":"NORTHEAST", "DC":"NORTHEAST",
		"VA":"SOUTHEAST", "WV":"SOUTHEAST", "NC":"SOUTHEAST", "SC":"SOUTHEAST", "GA":"SOUTHEAST", "FL":"SOUTHEAST",
		"KY":"SOUTHEAST", "TN":"SOUTHEAST", "AL":"SOUTHEAST", "MS":"SOUTHEAST",
		"AZ":"SOUTHWEST", "NM":"SOUTHWEST", "CO":"SOUTHWEST", "UT":"SOUTHWEST", "NV":"SOUTHWEST", "CA":"SOUTHWEST",
		"TX":"SOUTHCENTRAL", "OK":"SOUTHCENTRAL", "AR":"SOUTHCENTRAL", "LA":"SOUTHCENTRAL"
	]

	/// Same redirect behavior as radar-map.html handleStateClick.
	static let stateRedirect: [String: String] = [
		"CT": "NY", "DE": "VA", "MA": "NY", "MD": "VA", "ME": "NH",
		"NC": "SC", "NJ": "PA", "RI": "NY", "VT": "NY", "WV": "VA"
	]

	/// Region -> states for hierarchical browsing.
	static let regionStates: [String: [String]] = {
		var grouped: [String: [String]] = [:]
		for (state, region) in stateNavigationRegion {
			grouped[region, default: []].append(state)
		}
		for key in grouped.keys {
			grouped[key]?.sort { displayState($0) < displayState($1) }
		}
		return grouped
	}()

	static func displayName(for region: String) -> String {
		regionDisplay[region] ?? stateNames[region] ?? region
	}

	static func displayState(_ code: String) -> String {
		displayName(for: code)
	}

	static func navigationRegion(forState state: String) -> String? {
		stateNavigationRegion[state]
	}

	static func navigationRegion(forKey key: String) -> String? {
		if regionKeys.contains(key) { return key }
		if ["NORCAL", "CENTRALCAL", "SOCAL"].contains(key) { return "SOUTHWEST" }
		if ["TXW", "TXE", "TXS"].contains(key) { return "SOUTHCENTRAL" }
		return stateNavigationRegion[key]
	}

	/// Returns the key that should actually be downloaded for a chosen state.
	/// Mirrors HTML handleStateClick: redirect states load the redirect target's
	/// state GIF, every other state loads its OWN GIF (inmasir<abbrev>_.gif).
	/// Region fallback only happens if that download fails (see fallbackRegion).
	static func resolvedKey(forState state: String) -> String {
		if let redir = stateRedirect[state] { return redir }
		return state
	}

	/// Region GIF to load if a state's own GIF download fails.
	/// Mirrors HTML getRegionFallback (defaults to USA when unmapped).
	static func fallbackRegion(forState state: String) -> String {
		stateFallbackRegion[state] ?? "USA"
	}

	static func resolvedLabel(forState state: String) -> String {
		if let redir = stateRedirect[state] {
			let target = displayName(for: redir)
			return "\(displayState(state)) → \(target)"
		}
		let key = resolvedKey(forState: state)
		if key != state {
			return "\(displayState(state)) → \(displayName(for: key))"
		}
		return displayState(state)
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

	/// Downloads the radar GIF for a region/state key, caches it on disk, and returns the local file URL.
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
					self.pruneCacheToLatest(keepRegion: region)
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

	private func pruneCacheToLatest(keepRegion: String?) {
		let fm = FileManager.default
		let files = cachedGifs()
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
}
