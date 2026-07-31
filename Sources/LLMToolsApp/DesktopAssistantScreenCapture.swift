import AppKit
import CryptoKit
import ImageIO
import LLMToolsCore
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
enum DesktopAssistantScreenCapture {
    static func captureFrontmostWindow() async throws -> (
        image: OCRImageInput,
        bundleID: String,
        processIdentifier: pid_t,
        windowID: CGWindowID,
        capturedAt: Date
    )? {
        // 所有调用者最终都经过这里，避免未来新增入口绕过权限预检后直接触发系统弹窗。
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = application.bundleIdentifier else { return nil }

        let content = try await SCShareableContent.current
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == application.processIdentifier
                && $0.frame.width >= 160
                && $0.frame.height >= 120
        }
        guard let frontWindowID = frontmostWindowID(processIdentifier: application.processIdentifier),
              let window = candidates.first(where: { $0.windowID == frontWindowID }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        // ponytail: 1600px 足够识别桌面语义；只有小字识别实测不足时再提高上限。
        let scale = min(1, 1_600 / max(window.frame.width, window.frame.height))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let capturedAt = Date.now
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        let png = data as Data
        let hash = perceptualHash(of: image)
        return (
            OCRImageInput(
                data: png,
                mimeType: UTType.png.preferredMIMEType ?? "image/png",
                pixelWidth: image.width,
                pixelHeight: image.height,
                contentHash: hash,
                sourceDescription: "Foreground window snapshot"
            ),
            bundleID,
            application.processIdentifier,
            window.windowID,
            capturedAt
        )
    }

    static func frontmostWindowID(processIdentifier: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        // CGWindow 列表按屏幕层级返回，先定位真正位于最前面的普通窗口，再交给 ScreenCaptureKit 取图。
        return windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }).flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    private static func perceptualHash(of image: CGImage) -> String {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        // 低四位量化可忽略光标闪烁和轻微抗锯齿变化，明显页面变化仍会得到新指纹。
        let quantized = Data(pixels.map { $0 & 0xF0 })
        return SHA256.hash(data: quantized).map { String(format: "%02x", $0) }.joined()
    }
}
