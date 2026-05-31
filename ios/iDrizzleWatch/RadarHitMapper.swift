import Foundation
import CoreGraphics

final class RadarHitMapper {

	static let shared = RadarHitMapper()

	private let imageWidth: Double = 640
	private let imageHeight: Double = 480
	private let sphereRadius: Double = 6_371_200

	private struct LCCParams {
		let lat0: Double
		let lon0: Double
		let lat1: Double
		let lat2: Double
	}

	private struct RegionCalibration {
		let lat0: Double
		let lon0: Double
		let lat1: Double
		let lat2: Double
		let rotation: Double
		let left: Double
		let right: Double
		let top: Double
		let bottom: Double
		let scale: Double
		let offX: Double
		let offY: Double
	}

	private struct StateCalibration {
		let scale: Double
		let offX: Double
		let offY: Double
	}

	private struct GeoBounds {
		let minLat: Double
		let maxLat: Double
		let minLng: Double
		let maxLng: Double

		var centerLat: Double { (minLat + maxLat) / 2 }
		var centerLng: Double { (minLng + maxLng) / 2 }
	}

	private struct StatePolygon {
		let outer: [CGPoint]
		let holes: [[CGPoint]]
	}

	private struct StateShape {
		let code: String
		let polygons: [StatePolygon]
		let bounds: GeoBounds
	}

	enum ProjectionMode {
		case usa
		case region(String)
		case state(String)
	}

	private let usaParams = LCCParams(lat0: 37.8, lon0: -97.4, lat1: 89.0, lat2: 89.0)
	private let usaRotation: Double = 0.7
	private let usaLeft: Double = -3_780_000
	private let usaRight: Double = 3_750_000
	private let usaTop: Double = 3_135_000
	private let usaBottom: Double = -2_585_000

	private lazy var regionCalibration: [String: RegionCalibration] = [
		"NORTHCENTRAL": RegionCalibration(lat0: 34.8, lon0: -97.4, lat1: 85.5, lat2: 35, rotation: -0.6, left: -3_290_000, right: 3_360_000, top: 2_965_000, bottom: -2_205_000, scale: 2.26, offX: 6, offY: -156),
		"NORTHEAST": RegionCalibration(lat0: 38.4, lon0: -98.9, lat1: 89, lat2: 42.2, rotation: 0.3, left: -4_125_000, right: 3_265_000, top: 3_170_000, bottom: -2_700_000, scale: 2.34, offX: -381, offY: -125),
		"NORTHWEST": RegionCalibration(lat0: 36.8, lon0: -106.5, lat1: 59.5, lat2: 89, rotation: -8.75, left: -4_890_000, right: 2_360_000, top: 3_590_000, bottom: -2_370_000, scale: 2.34, offX: -94, offY: -156),
		"SOUTHCENTRAL": RegionCalibration(lat0: 37.8, lon0: -97.4, lat1: 89, lat2: 44.7, rotation: -0.15, left: -3_780_000, right: 3_700_000, top: 3_210_000, bottom: -2_605_000, scale: 2.65, offX: -12, offY: 194),
		"SOUTHEAST": RegionCalibration(lat0: 37.8, lon0: -97.4, lat1: 56, lat2: 89, rotation: 0.7, left: -3_430_000, right: 3_415_000, top: 2_925_000, bottom: -2_370_000, scale: 2.28, offX: -231, offY: 188),
		"SOUTHWEST": RegionCalibration(lat0: 36.6, lon0: -87, lat1: 15, lat2: 82.3, rotation: 7.25, left: -3_755_000, right: 3_620_000, top: 4_000_000, bottom: -2_310_000, scale: 3.28, offX: 538, offY: 175)
	]

	private lazy var stateCalibration: [String: StateCalibration] = [
		"AL": .init(scale: 1.55, offX: -22, offY: -37), "AR": .init(scale: 1.31, offX: 16, offY: 30), "AZ": .init(scale: 1.62, offX: -20, offY: -22),
		"CENTRALCAL": .init(scale: 2.68, offX: 91, offY: -53), "CO": .init(scale: 1.14, offX: -3, offY: 25), "CT": .init(scale: 0.58, offX: 70, offY: 13),
		"FL": .init(scale: 1.55, offX: 38, offY: 6), "GA": .init(scale: 1.41, offX: 3, offY: 20), "IA": .init(scale: 1.21, offX: -11, offY: 17),
		"ID": .init(scale: 1.71, offX: 42, offY: 41), "IL": .init(scale: 1.78, offX: -25, offY: -56), "IN": .init(scale: 1.44, offX: 27, offY: 22),
		"KS": .init(scale: 1.41, offX: 25, offY: 22), "KY": .init(scale: 1.55, offX: 23, offY: 8), "LA": .init(scale: 1.60, offX: -8, offY: -5),
		"MA": .init(scale: 0.50, offX: 152, offY: -11), "MD": .init(scale: 0.50, offX: 28, offY: -198), "ME": .init(scale: 0.54, offX: 164, offY: 88),
		"MI": .init(scale: 2.16, offX: -102, offY: 100), "MN": .init(scale: 1.79, offX: 42, offY: 39), "MO": .init(scale: 1.57, offX: 36, offY: 11),
		"MS": .init(scale: 1.57, offX: -27, offY: 2), "MT": .init(scale: 1.33, offX: -20, offY: -39), "NC": .init(scale: 0.62, offX: 153, offY: 138),
		"ND": .init(scale: 1.06, offX: -3, offY: -30), "NE": .init(scale: 1.32, offX: -5, offY: 13), "NH": .init(scale: 0.85, offX: -100, offY: -33),
		"NM": .init(scale: 1.41, offX: -22, offY: -5), "NORCAL": .init(scale: 2.78, offX: 13, offY: -166), "NV": .init(scale: 1.68, offX: -31, offY: 28),
		"NY": .init(scale: 1.60, offX: 0, offY: -8), "OH": .init(scale: 1.13, offX: -14, offY: -19), "OK": .init(scale: 1.29, offX: 5, offY: 2),
		"OR": .init(scale: 1.03, offX: -17, offY: 8), "PA": .init(scale: 1.39, offX: -14, offY: 9), "SC": .init(scale: 0.87, offX: -95, offY: -89),
		"SD": .init(scale: 1.27, offX: -3, offY: -11), "SOCAL": .init(scale: 3.00, offX: -122, offY: 114),
		"SOUTHCENTRAL": .init(scale: 1.0, offX: 0, offY: 0), "TN": .init(scale: 1.59, offX: 27, offY: 22), "TX": .init(scale: 1.39, offX: -69, offY: -44),
		"TXE": .init(scale: 2.66, offX: -83, offY: -52), "TXS": .init(scale: 2.59, offX: -86, offY: 186), "TXW": .init(scale: 2.40, offX: 48, offY: -91),
		"UT": .init(scale: 1.56, offX: -8, offY: 23), "VA": .init(scale: 1.61, offX: -3, offY: -14), "WA": .init(scale: 1.22, offX: -28, offY: 80),
		"WI": .init(scale: 1.39, offX: -22, offY: -31), "WY": .init(scale: 0.97, offX: -5, offY: 27)
	]

	private let stateRedirect: [String: String] = [
		"CT": "NY", "DE": "VA", "MA": "NY", "MD": "VA", "ME": "NH",
		"NC": "SC", "NJ": "PA", "RI": "NY", "VT": "NY", "WV": "VA"
	]

	private lazy var shapes: [StateShape] = loadShapes()

	private init() {}

	func stateForTap(normalizedX: CGFloat,
					 normalizedY: CGFloat,
					 mode: ProjectionMode,
					 allowedStates: Set<String>? = nil) -> String? {
		let point = CGPoint(x: normalizedX * imageWidth, y: normalizedY * imageHeight)

		for shape in shapes {
			if let allowedStates, !allowedStates.contains(shape.code) { continue }
			let projected = projectedPolygons(for: shape, mode: mode)
			if contains(point: point, in: projected) {
				if shape.code == "CA" {
					return californiaSubregion(point: point, polygons: projected)
				}
				if shape.code == "TX" {
					return texasSubregion(point: point, polygons: projected)
				}
				if let redir = stateRedirect[shape.code] {
					return redir
				}
				return shape.code
			}
		}
		return nil
	}

	private func californiaSubregion(point: CGPoint, polygons: [StatePolygon]) -> String {
		guard let box = bounds(of: polygons) else { return "CA" }
		let rx = (point.x - box.minX) / max(1, box.width)
		let ry = (point.y - box.minY) / max(1, box.height)
		if ry > 0.60 { return "NORCAL" }
		if ry > 0.30 { return "CENTRALCAL" }
		return "SOCAL"
	}

	private func texasSubregion(point: CGPoint, polygons: [StatePolygon]) -> String {
		guard let box = bounds(of: polygons) else { return "TX" }
		let rx = (point.x - box.minX) / max(1, box.width)
		let ry = (point.y - box.minY) / max(1, box.height)
		if ry < 0.35 { return "TXS" }
		if rx < 0.50 { return "TXW" }
		return "TXE"
	}

	private func bounds(of polygons: [StatePolygon]) -> CGRect? {
		var minX = CGFloat.greatestFiniteMagnitude
		var minY = CGFloat.greatestFiniteMagnitude
		var maxX = -CGFloat.greatestFiniteMagnitude
		var maxY = -CGFloat.greatestFiniteMagnitude

		for poly in polygons {
			for p in poly.outer {
				minX = min(minX, p.x)
				minY = min(minY, p.y)
				maxX = max(maxX, p.x)
				maxY = max(maxY, p.y)
			}
		}

		guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
		return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
	}

	private func projectedPolygons(for shape: StateShape, mode: ProjectionMode) -> [StatePolygon] {
		switch mode {
		case .usa:
			return shape.polygons.map { polygon in
				StatePolygon(
					outer: polygon.outer.map { projectUSA(lng: Double($0.x), lat: Double($0.y)) },
					holes: polygon.holes.map { ring in ring.map { projectUSA(lng: Double($0.x), lat: Double($0.y)) } }
				)
			}

		case .region(let key):
			return shape.polygons.map { polygon in
				StatePolygon(
					outer: polygon.outer.map { projectRegion(lng: Double($0.x), lat: Double($0.y), region: key) },
					holes: polygon.holes.map { ring in ring.map { projectRegion(lng: Double($0.x), lat: Double($0.y), region: key) } }
				)
			}

		case .state(let key):
			return shape.polygons.map { polygon in
				StatePolygon(
					outer: polygon.outer.map { projectState(lng: Double($0.x), lat: Double($0.y), stateKey: key, bounds: shape.bounds) },
					holes: polygon.holes.map { ring in ring.map { projectState(lng: Double($0.x), lat: Double($0.y), stateKey: key, bounds: shape.bounds) } }
				)
			}
		}
	}

	private func projectUSA(lng: Double, lat: Double) -> CGPoint {
		let (x0, y0) = forwardLCC(lng: lng, lat: lat, params: usaParams)

		let cx = (usaLeft + usaRight) / 2
		let cy = (usaTop + usaBottom) / 2
		let rad = usaRotation * .pi / 180
		let dx = x0 - cx
		let dy = y0 - cy
		let x = cx + dx * cos(rad) - dy * sin(rad)
		let y = cy + dx * sin(rad) + dy * cos(rad)

		let px = (x - usaLeft) / (usaRight - usaLeft) * imageWidth
		let py = (y - usaBottom) / (usaTop - usaBottom) * imageHeight
		return CGPoint(x: px, y: py)
	}

	private func projectRegion(lng: Double, lat: Double, region: String) -> CGPoint {
		guard let c = regionCalibration[region] else {
			return projectUSA(lng: lng, lat: lat)
		}

		let params = LCCParams(lat0: c.lat0, lon0: c.lon0, lat1: c.lat1, lat2: c.lat2)
		let (x0, y0) = forwardLCC(lng: lng, lat: lat, params: params)

		let cx = (c.left + c.right) / 2
		let cy = (c.top + c.bottom) / 2
		let rad = c.rotation * .pi / 180
		let dx = x0 - cx
		let dy = y0 - cy
		let x = cx + dx * cos(rad) - dy * sin(rad)
		let y = cy + dx * sin(rad) + dy * cos(rad)

		var px = (x - c.left) / (c.right - c.left) * imageWidth
		var py = (y - c.bottom) / (c.top - c.bottom) * imageHeight

		px = (px - imageWidth / 2) * c.scale + imageWidth / 2 + c.offX
		py = (py - imageHeight / 2) * c.scale + imageHeight / 2 + c.offY
		return CGPoint(x: px, y: py)
	}

	private func projectState(lng: Double, lat: Double, stateKey: String, bounds: GeoBounds) -> CGPoint {
		let centerLat = bounds.centerLat
		let centerLng = bounds.centerLng
		let cosLat = cos(centerLat * .pi / 180)

		let geoW = (bounds.maxLng - bounds.minLng) * cosLat * 2.3
		let geoH = (bounds.maxLat - bounds.minLat) * 2.3
		let baseScale = imageHeight / ((geoW / geoH > 4.0 / 3.0) ? (geoW * 3.0 / 4.0) : geoH)

		let calib = stateCalibration[stateKey] ?? .init(scale: 1.0, offX: 0, offY: 0)
		let scale = baseScale * calib.scale

		let x = (lng - centerLng) * scale * cosLat + imageWidth / 2 + calib.offX
		let y = (lat - centerLat) * scale + imageHeight / 2 + calib.offY
		return CGPoint(x: x, y: y)
	}

	private func forwardLCC(lng: Double, lat: Double, params: LCCParams) -> (Double, Double) {
		let phi = degToRad(lat)
		let lambda = degToRad(lng)
		let phi0 = degToRad(params.lat0)
		let lambda0 = degToRad(params.lon0)
		let phi1 = degToRad(params.lat1)
		let phi2 = degToRad(params.lat2)

		let n: Double
		if abs(phi1 - phi2) < 1e-10 {
			n = sin(phi1)
		} else {
			n = log(cos(phi1) / cos(phi2)) / log(tan(.pi / 4 + phi2 / 2) / tan(.pi / 4 + phi1 / 2))
		}

		let f = cos(phi1) * pow(tan(.pi / 4 + phi1 / 2), n) / n
		let rho = sphereRadius * f * pow(tan(.pi / 4 + phi / 2), -n)
		let rho0 = sphereRadius * f * pow(tan(.pi / 4 + phi0 / 2), -n)

		let theta = n * (lambda - lambda0)
		let x = rho * sin(theta)
		let y = rho0 - rho * cos(theta)
		return (x, y)
	}

	private func contains(point: CGPoint, in polygons: [StatePolygon]) -> Bool {
		for poly in polygons {
			if pointInRing(point, ring: poly.outer) {
				let inHole = poly.holes.contains { pointInRing(point, ring: $0) }
				if !inHole { return true }
			}
		}
		return false
	}

	private func pointInRing(_ point: CGPoint, ring: [CGPoint]) -> Bool {
		guard ring.count > 2 else { return false }
		var inside = false
		var j = ring.count - 1
		for i in 0..<ring.count {
			let xi = ring[i].x, yi = ring[i].y
			let xj = ring[j].x, yj = ring[j].y
			let intersects = ((yi > point.y) != (yj > point.y)) &&
				(point.x < (xj - xi) * (point.y - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi)
			if intersects { inside.toggle() }
			j = i
		}
		return inside
	}

	private func degToRad(_ value: Double) -> Double { value * .pi / 180 }

	private func loadShapes() -> [StateShape] {
		guard let url = Bundle.main.url(forResource: "us-states", withExtension: "geo.json"),
			  let data = try? Data(contentsOf: url),
			  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let features = root["features"] as? [[String: Any]] else {
			return []
		}

		let nameToCode = Dictionary(uniqueKeysWithValues: RadarService.stateNames.map { ($1, $0) })

		var result: [StateShape] = []

		for feature in features {
			guard let geometry = feature["geometry"] as? [String: Any],
				  let type = geometry["type"] as? String,
				  let properties = feature["properties"] as? [String: Any] else { continue }

			var code = (properties["STUSPS"] as? String) ?? ""
			if code.isEmpty, let name = (properties["name"] as? String) ?? (properties["NAME"] as? String) {
				code = nameToCode[name] ?? ""
			}
			guard !code.isEmpty else { continue }

			let polygons: [StatePolygon]
			if type == "Polygon", let coords = geometry["coordinates"] as? [Any] {
				guard let poly = makePolygon(from: coords) else { continue }
				polygons = [poly]
			} else if type == "MultiPolygon", let coords = geometry["coordinates"] as? [Any] {
				let polys = coords.compactMap { makePolygon(from: $0) }
				guard !polys.isEmpty else { continue }
				polygons = polys
			} else {
				continue
			}

			var minLat = Double.greatestFiniteMagnitude
			var maxLat = -Double.greatestFiniteMagnitude
			var minLng = Double.greatestFiniteMagnitude
			var maxLng = -Double.greatestFiniteMagnitude

			for p in polygons {
				for pt in p.outer {
					minLng = min(minLng, Double(pt.x))
					maxLng = max(maxLng, Double(pt.x))
					minLat = min(minLat, Double(pt.y))
					maxLat = max(maxLat, Double(pt.y))
				}
			}

			guard minLat.isFinite, maxLat.isFinite, minLng.isFinite, maxLng.isFinite else { continue }

			result.append(StateShape(
				code: code,
				polygons: polygons,
				bounds: GeoBounds(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng)
			))
		}

		return result
	}

	private func makePolygon(from raw: Any) -> StatePolygon? {
		guard let rings = raw as? [Any], !rings.isEmpty else { return nil }

		func asDouble(_ value: Any) -> Double? {
			if let d = value as? Double { return d }
			if let i = value as? Int { return Double(i) }
			if let n = value as? NSNumber { return n.doubleValue }
			return nil
		}

		func convert(_ ringRaw: Any) -> [CGPoint] {
			guard let ring = ringRaw as? [Any] else { return [] }
			return ring.compactMap { item in
				guard let pair = item as? [Any], pair.count >= 2,
					  let lng = asDouble(pair[0]),
					  let lat = asDouble(pair[1]) else { return nil }
				return CGPoint(x: lng, y: lat)
			}
		}

		let outer = convert(rings[0])
		if outer.count < 3 { return nil }
		let holes = rings.dropFirst().map(convert).filter { $0.count >= 3 }
		return StatePolygon(outer: outer, holes: holes)
	}
}
