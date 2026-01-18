// ScreenCaptureService.swift
// Service for capturing screen regions using ScreenCaptureKit with persistent stream
// Made by mpcode

import AppKit
import ScreenCaptureKit
import CoreVideo
import CoreImage

@MainActor
final class ScreenCaptureService {

    private var stream: SCStream?
    private var streamOutput: PersistentStreamOutput?
    private var isRunning = false

    // MARK: - Permission Checks

    /// Checks if screen recording permission is granted.
    nonisolated static func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests screen recording permission from the user.
    /// This will show the system permission dialog if not already granted.
    @discardableResult
    nonisolated static func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    // MARK: - Stream Management

    /// Starts the persistent capture stream. Call this once before capturing.
    func startStream() async throws {
        guard !isRunning else { return }

        // Get shareable content - this is the only call that might trigger permission
        // It should only be called once when starting the stream
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let mainDisplay = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            throw CaptureError.noDisplayFound
        }

        // Configure stream for full display
        let config = SCStreamConfiguration()
        config.width = mainDisplay.width
        config.height = mainDisplay.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS max for faster first frame

        // Create filter and stream
        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)

        // Create persistent output handler
        let output = PersistentStreamOutput()
        try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive))

        // Start the stream
        try await newStream.startCapture()

        self.stream = newStream
        self.streamOutput = output
        self.isRunning = true

        // Wait for the first frame to be available (up to 500ms)
        for _ in 0..<50 {
            if output.latestFrame != nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    /// Stops the persistent capture stream.
    func stopStream() async {
        guard isRunning, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("Error stopping stream: \(error)")
        }

        self.stream = nil
        self.streamOutput = nil
        self.isRunning = false
    }

    // MARK: - Capture

    /// Captures a portion of the screen as a CGImage.
    /// The stream must be started first with startStream().
    /// - Parameter rect: The rectangle in screen coordinates to capture.
    /// - Returns: A CGImage containing the captured area, or nil if not available.
    func capture(rect: CGRect) async throws -> CGImage? {
        // Auto-start stream if not running
        if !isRunning {
            try await startStream()
        }

        guard let output = streamOutput else {
            throw CaptureError.streamNotRunning
        }

        // Get the latest frame from the persistent output
        guard let fullImage = output.latestFrame else {
            return nil
        }

        // Crop to the requested rect
        return fullImage.cropping(to: rect)
    }

    // MARK: - Errors

    enum CaptureError: LocalizedError {
        case noDisplayFound
        case streamNotRunning

        var errorDescription: String? {
            switch self {
            case .noDisplayFound:
                return "No display found for screen capture."
            case .streamNotRunning:
                return "Screen capture stream is not running."
            }
        }
    }
}

// MARK: - Persistent Stream Output

/// Keeps the latest frame available for on-demand capture
private final class PersistentStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var _latestFrame: CGImage?

    var latestFrame: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return _latestFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        // Convert to CGImage
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            lock.lock()
            _latestFrame = cgImage
            lock.unlock()
        }
    }
}
