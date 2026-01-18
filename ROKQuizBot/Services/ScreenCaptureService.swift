// ScreenCaptureService.swift
// Service for capturing screen regions using ScreenCaptureKit
// Made by mpcode

import AppKit
import ScreenCaptureKit
import CoreVideo
import CoreImage

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

        // Create the stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        // Create a frame handler
        let frameHandler = StreamFrameHandler(rect: rect)

        // Start the stream
        try await stream.startCapture()
        defer { stream.stopCapture() }

        // Wait for a frame
        guard let cgImage = await frameHandler.nextImage(from: stream) else {
            return nil
        }

        return cgImage
    }
}

// MARK: - Stream Frame Handler
private final class StreamFrameHandler: NSObject, SCStreamOutput, @unchecked Sendable {
    let rect: CGRect
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private let queue = DispatchQueue(label: "ROKQuizBot.StreamFrameHandler.queue")

    init(rect: CGRect) {
        self.rect = rect
    }

    func nextImage(from stream: SCStream) async -> CGImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.continuation = continuation
            }
            Task { @MainActor in
                try? stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            }
        }
    }

    @objc func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let imageBuffer = sampleBuffer.imageBuffer else {
            queue.async {
                self.continuation?.resume(returning: nil)
                self.continuation = nil
            }
            return
        }

        // Crop and convert the buffer to CGImage
        let ciImage = CIImage(cvPixelBuffer: imageBuffer).cropped(to: rect)
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)

        queue.async {
            self.continuation?.resume(returning: cgImage)
            self.continuation = nil
        }
    }
}
