import SwiftUI
import ImageIO
import UIKit

/// Decodes an animated GIF on disk into frames and plays them back in SwiftUI.
/// watchOS has no WKWebView, so the iOS WebView-based GIF playback is replaced
/// with manual ImageIO frame decoding driven by a TimelineView clock.
struct GIFImage: View {
	let fileURL: URL

	@State private var frames: [UIImage] = []
	@State private var frameDelays: [Double] = []
	@State private var totalDuration: Double = 0

	var body: some View {
		Group {
			if frames.isEmpty {
				Color.black
			} else if frames.count == 1 {
				Image(uiImage: frames[0])
					.resizable()
					.scaledToFit()
			} else {
				TimelineView(.animation) { context in
					Image(uiImage: frame(at: context.date))
						.resizable()
						.scaledToFit()
				}
			}
		}
		.task(id: fileURL) { await load() }
	}

	private func frame(at date: Date) -> UIImage {
		guard totalDuration > 0, !frames.isEmpty else {
			return frames.first ?? UIImage()
		}
		let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
		var acc = 0.0
		for (index, delay) in frameDelays.enumerated() {
			acc += delay
			if elapsed < acc { return frames[index] }
		}
		return frames.last ?? UIImage()
	}

	private func load() async {
		let result = await Task.detached(priority: .userInitiated) {
			Self.decode(fileURL: fileURL)
		}.value

		frames = result.frames
		frameDelays = result.delays
		totalDuration = result.delays.reduce(0, +)
	}

	private static func decode(fileURL: URL) -> (frames: [UIImage], delays: [Double]) {
		guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
			return ([], [])
		}
		let count = CGImageSourceGetCount(source)
		var images: [UIImage] = []
		var delays: [Double] = []
		for i in 0..<count {
			guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
			images.append(UIImage(cgImage: cg))
			delays.append(frameDelay(source: source, index: i))
		}
		return (images, delays)
	}

	private static func frameDelay(source: CGImageSource, index: Int) -> Double {
		guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
			  let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
			return 0.1
		}
		let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
		let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
		let delay = unclamped ?? clamped ?? 0.1
		return delay < 0.02 ? 0.1 : delay
	}
}
