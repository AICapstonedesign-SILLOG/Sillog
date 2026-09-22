import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// 연속 녹화가 아니라 필요한 순간의 스틸 한 장 (SCScreenshotManager). 메뉴바의 보라색 녹화 표시가 뜨지 않는다.
public struct ScreenCapturer: Sendable {
    public init() {}

    public func capture(excluding privacy: PrivacyFilter, maxWidth: Int = 1600) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mainID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else { return nil }
            let hidden = content.applications.filter { privacy.isExcluded(bundle: $0.bundleIdentifier) }
            let filter = SCContentFilter(display: display, excludingApplications: hidden, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = min(1.0, Double(maxWidth) / Double(max(display.width, 1)))
            config.width = max(2, Int(Double(display.width) * scale) / 2 * 2)
            config.height = max(2, Int(Double(display.height) * scale) / 2 * 2)
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    @discardableResult
    public func saveJPEG(_ image: CGImage, to url: URL, quality: Double = 0.6) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// 9x8 회색조 차이 해시. 두 해시의 해밍 거리가 작으면 화면이 거의 안 바뀐 것이다.
    public static func differenceHash(_ image: CGImage) -> UInt64 {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                hash <<= 1
                if pixels[y * width + x] > pixels[y * width + x + 1] { hash |= 1 }
            }
        }
        return hash
    }

    public static func isSimilar(_ a: UInt64, _ b: UInt64, maxDistance: Int = 4) -> Bool {
        (a ^ b).nonzeroBitCount <= maxDistance
    }
}
