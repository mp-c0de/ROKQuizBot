// ScreenCaptureService.swift
// Service for capturing screen regions using ScreenCaptureKit
// Made by mpcode

import AppKit
import ScreenCaptureKit
import CoreVideo
import CoreImage

@MainActor
final class ScreenCaptureService {
    /// Captures a portion of the main display as a CGImage using ScreenCaptureKit.
    /// - Parameter rect: The rectangle in screen coordinates to capture.
    /// - Returns: A CGImage containing the captured area, or nil if capture fails.
    func capture(rect: CGRect) async throws -> CGImage? {
        // Fetch the list of available displays
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let mainDisplay = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            return nil
        }

        // Configure the stream to match the display size
        let config = SCStreamConfiguration()
        config.width = mainDisplay.width
        config.height = mainDisplay.height
        config.pixelFormat = kCVPixelFormatType_32BGRA

        // Create content filter
        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])

        // Use the screenshot API for single frame capture
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Crop to the requested rect
        // The rect is in screen coordinates, need to adjust for the image
        let scale = CGFloat(mainDisplay.width) / mainDisplay.frame.width
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        return cgImage.cropping(to: scaledRect)
    }
}
