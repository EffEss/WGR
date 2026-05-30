import SwiftUI

struct ContentView: View {

	private let service = RadarService.shared

	@State private var region = "USA"
	@State private var radarURL: URL?
	@State private var status = "Ready"
	@State private var isLoading = false
	@State private var cacheText = ""

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 8) {
					radarView

					Picker("Region", selection: $region) {
						ForEach(RadarService.regionKeys, id: \.self) { key in
							Text(RadarService.displayName(for: key)).tag(key)
						}
					}
					.onChange(of: region) { _, _ in load(force: false) }

					HStack {
						Button {
							load(force: true)
						} label: {
							Label("Refresh", systemImage: "arrow.clockwise")
						}
						.disabled(isLoading)

						Button(role: .destructive) {
							clearCache()
						} label: {
							Label("Cache", systemImage: "trash")
						}
					}
					.font(.footnote)

					Text(status)
						.font(.caption2)
						.foregroundStyle(.secondary)
					if !cacheText.isEmpty {
						Text(cacheText)
							.font(.caption2)
							.foregroundStyle(.tertiary)
					}
				}
				.padding(.horizontal, 4)
			}
			.navigationTitle("iDrizzle")
			.background(Color(red: 13/255, green: 17/255, blue: 23/255))
		}
		.task { load(force: false) }
	}

	@ViewBuilder
	private var radarView: some View {
		ZStack {
			Color(red: 13/255, green: 17/255, blue: 23/255)
			if let radarURL {
				GIFImage(fileURL: radarURL)
			}
			if isLoading {
				ProgressView()
			}
		}
		.aspectRatio(4.0 / 3.0, contentMode: .fit)
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private func load(force: Bool) {
		let target = region
		isLoading = true
		status = "Loading \(RadarService.displayName(for: target))…"
		service.fetchRadarGif(region: target) { result in
			DispatchQueue.main.async {
				guard target == region else { return }
				isLoading = false
				switch result {
				case .success(let url):
					radarURL = url
					status = "\(RadarService.displayName(for: target)) · \(timeStamp())"
					updateCacheText()
				case .failure:
					status = "Radar unavailable"
				}
			}
		}
	}

	private func clearCache() {
		service.clearCache()
		radarURL = nil
		status = "Cache cleared"
		updateCacheText()
	}

	private func updateCacheText() {
		let info = service.cacheSize()
		let kb = String(format: "%.1f", Double(info.bytes) / 1024)
		cacheText = info.count == 0 ? "" : "\(info.count) GIF\(info.count == 1 ? "" : "s") · \(kb) KB"
	}

	private func timeStamp() -> String {
		let f = DateFormatter()
		f.timeStyle = .short
		return f.string(from: Date())
	}
}

#Preview {
	ContentView()
}
