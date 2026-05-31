import SwiftUI

struct ContentView: View {

	enum Selection: Equatable {
		case usa
		case region(String)
		case state(String)
	}

	private let service = RadarService.shared
	private let hitMapper = RadarHitMapper.shared
	private let primaryRegions = RadarService.regionKeys.filter { $0 != "USA" }

	@State private var selection: Selection = .usa
	@State private var radarURL: URL?
	@State private var status = "Ready"
	@State private var isLoading = false
	@State private var cacheText = ""
	@State private var showingRegionSelector = false

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 8) {
					radarView

					Button {
						showingRegionSelector = true
					} label: {
						VStack(spacing: 2) {
							Text("Radar Level")
								.font(.caption)
								.foregroundStyle(.secondary)
							Text(selectionTitle)
								.font(.headline)
								.lineLimit(1)
								.minimumScaleFactor(0.72)
						}
						.frame(maxWidth: .infinity)
						.padding(.vertical, 10)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
						.overlay(alignment: .trailing) {
							Image(systemName: "chevron.right")
								.font(.footnote.weight(.semibold))
								.foregroundStyle(.secondary)
								.padding(.trailing, 10)
						}
					}
					.buttonStyle(.plain)

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
		.sheet(isPresented: $showingRegionSelector) {
			regionSelectorSheet
		}
		.task { load(force: false) }
	}

	private var selectionTitle: String {
		switch selection {
		case .usa:
			return RadarService.displayName(for: "USA")
		case .region(let key):
			return RadarService.displayName(for: key)
		case .state(let code):
			return RadarService.displayState(code)
		}
	}

	private var regionSelectorSheet: some View {
		NavigationStack {
			List {
				Section("Zoom") {
					navRow(title: RadarService.displayName(for: "USA"), selected: selection == .usa) {
						selectUSA()
						showingRegionSelector = false
					}
					ForEach(primaryRegions, id: \.self) { key in
						navRow(title: RadarService.displayName(for: key), selected: selection == .region(key)) {
							selectRegion(key)
						}
					}
				}

				Section(statesSectionTitle) {
					if statesForCurrentLevel.isEmpty {
						Text("Choose a region above, then pick a state.")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else {
						ForEach(statesForCurrentLevel, id: \.self) { code in
							Button {
								selectState(code)
								showingRegionSelector = false
							} label: {
								HStack {
									VStack(alignment: .leading, spacing: 2) {
										Text(RadarService.displayState(code))
											.font(.headline)
										if let fb = stateFallbackLabel(code) {
											Text(fb)
												.font(.caption2)
												.foregroundStyle(.secondary)
										}
									}
									Spacer()
									if selection == .state(code) {
										Image(systemName: "checkmark")
											.foregroundStyle(.blue)
									}
								}
								.padding(.vertical, 6)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			.navigationTitle("USA → Region → State")
		}
	}

	private func navRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack {
				Text(title)
					.font(.headline)
				Spacer()
				if selected {
					Image(systemName: "checkmark")
						.foregroundStyle(.blue)
				}
			}
			.padding(.vertical, 8)
		}
		.buttonStyle(.plain)
	}

	private var statesSectionTitle: String {
		if let region = focusedRegion {
			return "States in \(RadarService.displayName(for: region))"
		}
		return "Select a region to browse states"
	}

	private var focusedRegion: String? {
		switch selection {
		case .region(let region):
			return region
		case .state(let state):
			let navRegion = RadarService.navigationRegion(forState: state)
			return primaryRegions.contains(navRegion ?? "") ? navRegion : nil
		case .usa:
			return nil
		}
	}

	private var statesForCurrentLevel: [String] {
		guard let region = focusedRegion else { return [] }
		return RadarService.regionStates[region] ?? []
	}

	private func stateFallbackLabel(_ state: String) -> String? {
		let key = RadarService.resolvedKey(forState: state)
		guard key != state else { return nil }
		return "Shows \(RadarService.displayName(for: key))"
	}

	@ViewBuilder
	private var radarView: some View {
		GeometryReader { geo in
			ZStack {
				Color(red: 13/255, green: 17/255, blue: 23/255)
				if let radarURL {
					GIFImage(fileURL: radarURL)
				}

				Color.clear
					.contentShape(Rectangle())
					.gesture(
						DragGesture(minimumDistance: 0)
							.onEnded { value in
								let x = max(0, min(1, value.location.x / max(1, geo.size.width)))
								let y = max(0, min(1, value.location.y / max(1, geo.size.height)))
								handleMapTap(x: x, y: y)
							}
					)

				Button {
					selectUSA()
				} label: {
					Text("USA")
						.font(.caption2.bold())
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(.ultraThinMaterial, in: Capsule())
				}
				.buttonStyle(.plain)
				.padding(6)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

				if isLoading {
					ProgressView()
				}
			}
		}
		.aspectRatio(4.0 / 3.0, contentMode: .fit)
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private func handleMapTap(x: CGFloat, y: CGFloat) {
		switch selection {
		case .usa:
			if let key = hitMapper.stateForTap(normalizedX: x, normalizedY: y, mode: .usa),
			   let region = RadarService.navigationRegion(forKey: key),
			   primaryRegions.contains(region) {
				selectRegion(region)
			}
		case .region(let region):
			let allowed = Set(RadarService.regionStates[region] ?? [])
			if let key = hitMapper.stateForTap(normalizedX: x, normalizedY: y, mode: .region(region), allowedStates: allowed) {
				if RadarService.stateNames[key] != nil {
					selectState(key)
				} else if let navRegion = RadarService.navigationRegion(forKey: key), primaryRegions.contains(navRegion) {
					selectRegion(navRegion)
				}
			}
		case .state(let code):
			let mode = RadarHitMapper.ProjectionMode.state(RadarService.resolvedKey(forState: code))
			if let key = hitMapper.stateForTap(normalizedX: x, normalizedY: y, mode: mode) {
				if RadarService.stateNames[key] != nil {
					selectState(key)
				} else if let navRegion = RadarService.navigationRegion(forKey: key), primaryRegions.contains(navRegion) {
					selectRegion(navRegion)
				}
			}
		}
	}

	private func selectUSA() {
		selection = .usa
		load(force: false)
	}

	private func selectRegion(_ newRegion: String) {
		selection = .region(newRegion)
		load(force: false)
	}

	private func selectState(_ code: String) {
		selection = .state(code)
		load(force: false)
	}

	private func currentLoadKey() -> String {
		switch selection {
		case .usa:
			return "USA"
		case .region(let key):
			return key
		case .state(let code):
			return RadarService.resolvedKey(forState: code)
		}
	}

	private func statusLabel() -> String {
		switch selection {
		case .usa:
			return RadarService.displayName(for: "USA")
		case .region(let key):
			return RadarService.displayName(for: key)
		case .state(let code):
			return RadarService.resolvedLabel(forState: code)
		}
	}

	private func load(force: Bool) {
		let key = currentLoadKey()
		let label = statusLabel()
		isLoading = true
		status = "Loading \(label)…"
		service.fetchRadarGif(region: key) { result in
			DispatchQueue.main.async {
				guard key == currentLoadKey() else { return }
				switch result {
				case .success(let url):
					isLoading = false
					radarURL = url
					status = "\(label) · \(timeStamp())"
					updateCacheText()
				case .failure:
					// Mirror HTML loadStateRadar: if a state's own GIF is
					// unavailable, fall back to its containing region GIF.
					if case .state(let code) = selection {
						loadStateFallback(forState: code, label: label)
					} else {
						isLoading = false
						status = "Radar unavailable"
					}
				}
			}
		}
	}

	private func loadStateFallback(forState code: String, label: String) {
		let region = RadarService.fallbackRegion(forState: code)
		let regionName = RadarService.displayName(for: region)
		service.fetchRadarGif(region: region) { result in
			DispatchQueue.main.async {
				guard case .state(code) = selection else { return }
				isLoading = false
				switch result {
				case .success(let url):
					radarURL = url
					status = "\(label) → \(regionName) · \(timeStamp())"
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
