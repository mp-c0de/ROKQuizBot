// CaptureAreaOverlay.swift
// Visual overlay showing capture area borders on screen
// Made by mpcode

import AppKit

/// A transparent panel that displays red borders around the capture area
/// Uses NSPanel so it doesn't prevent app termination
final class CaptureAreaOverlay: NSPanel {
    private static var shared: CaptureAreaOverlay?
    private var borderView: BorderView!

    static func show(rect: CGRect) {
        // Create on main thread
        DispatchQueue.main.async {
            if shared == nil {
                shared = CaptureAreaOverlay()
            }

            guard let overlay = shared else { return }

            // Convert from Quartz coordinates (origin top-left) to Cocoa coordinates (origin bottom-left)
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height

            // In Quartz: Y=0 at top, increases downward
            // In Cocoa: Y=0 at bottom, increases upward
            let cocoaY = screenHeight - rect.origin.y - rect.height

            let cocoaRect = CGRect(
                x: rect.origin.x,
                y: cocoaY,
                width: rect.width,
                height: rect.height
            )

            // Position the window to cover just the capture area with some padding for the border
            let borderWidth: CGFloat = 3
            let expandedRect = cocoaRect.insetBy(dx: -borderWidth, dy: -borderWidth)

            overlay.setFrame(expandedRect, display: true)
            overlay.borderView.frame = overlay.contentView?.bounds ?? expandedRect
            overlay.borderView.captureRect = CGRect(
                x: borderWidth,
                y: borderWidth,
                width: rect.width,
                height: rect.height
            )
            overlay.borderView.needsDisplay = true
            overlay.orderFront(nil)
        }
    }

    static func hide() {
        DispatchQueue.main.async {
            shared?.orderOut(nil)
        }
    }

    /// Completely closes and destroys the overlay window
    static func close() {
        DispatchQueue.main.async {
            shared?.orderOut(nil)
            shared?.close()
            shared = nil
        }
    }

    static func update(rect: CGRect) {
        show(rect: rect)
    }

    private init() {
        let initialFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true  // Click-through
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hasShadow = false
        hidesOnDeactivate = false

        // Important: Don't count this window for app termination
        isReleasedWhenClosed = false

        borderView = BorderView(frame: initialFrame)
        contentView = borderView
    }
}

// MARK: - Border View

private final class BorderView: NSView {
    var captureRect: CGRect = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw red border
        let borderPath = NSBezierPath(rect: captureRect)
        borderPath.lineWidth = 3
        NSColor.systemRed.withAlphaComponent(0.8).setStroke()
        borderPath.stroke()

        // Draw corner markers for better visibility
        let markerLength: CGFloat = 20
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // Top-left
            (CGPoint(x: captureRect.minX, y: captureRect.maxY - markerLength),
             CGPoint(x: captureRect.minX, y: captureRect.maxY),
             CGPoint(x: captureRect.minX + markerLength, y: captureRect.maxY)),
            // Top-right
            (CGPoint(x: captureRect.maxX - markerLength, y: captureRect.maxY),
             CGPoint(x: captureRect.maxX, y: captureRect.maxY),
             CGPoint(x: captureRect.maxX, y: captureRect.maxY - markerLength)),
            // Bottom-left
            (CGPoint(x: captureRect.minX, y: captureRect.minY + markerLength),
             CGPoint(x: captureRect.minX, y: captureRect.minY),
             CGPoint(x: captureRect.minX + markerLength, y: captureRect.minY)),
            // Bottom-right
            (CGPoint(x: captureRect.maxX - markerLength, y: captureRect.minY),
             CGPoint(x: captureRect.maxX, y: captureRect.minY),
             CGPoint(x: captureRect.maxX, y: captureRect.minY + markerLength)),
        ]

        NSColor.systemRed.setStroke()
        for (p1, p2, p3) in corners {
            let path = NSBezierPath()
            path.lineWidth = 4
            path.move(to: p1)
            path.line(to: p2)
            path.line(to: p3)
            path.stroke()
        }
    }
}
