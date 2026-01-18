// SelectionOverlayWindow.swift
// Overlay window for selecting screen capture area
// Made by mpcode

import AppKit

/// A full-screen transparent window that lets the user drag to select a rectangle.
/// Calls the completion with the selected rect in global screen coordinates (Quartz space).
final class SelectionOverlayWindow: NSWindow, NSWindowDelegate {
    private var overlayView: SelectionOverlayView!
    private var completion: ((CGRect?) -> Void)?

    static func present(on screen: NSScreen? = NSScreen.main, completion: @escaping (CGRect?) -> Void) {
        let screen = screen ?? NSScreen.main!
        let window = SelectionOverlayWindow(screen: screen, completion: completion)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Make the overlay view first responder AFTER window is shown (for ESC key)
        window.makeFirstResponder(window.overlayView)
    }

    convenience init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        let frame = screen.frame
        self.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.completion = completion
        isOpaque = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        alphaValue = 1.0
        delegate = self

        overlayView = SelectionOverlayView(frame: frame)
        contentView = overlayView

        overlayView.onFinish = { [weak self] rect in
            guard let self = self else { return }
            self.orderOut(nil)
            self.completion?(rect)
            self.completion = nil
        }
    }

    // Borderless windows need this to become key and receive keyboard events
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowDidResignKey(_ notification: Notification) {
        overlayView.cancelSelection()
    }
}

final class SelectionOverlayView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var didFinish = false  // Prevent double-calling onFinish

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.15).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            cancelSelection()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !didFinish else { return }

        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true

        guard let start = startPoint, let end = currentPoint else {
            finishSelection(with: nil)
            return
        }

        // Create rect in AppKit coordinates (origin bottom-left)
        let rectAppKit = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        // Minimum size check - prevent accidental tiny selections
        guard rectAppKit.width > 10 && rectAppKit.height > 10 else {
            finishSelection(with: nil)
            return
        }

        // Convert to Quartz/CG coordinates (origin top-left)
        guard let screen = self.window?.screen else {
            finishSelection(with: rectAppKit)
            return
        }

        let screenHeight = screen.frame.height
        let cgRect = CGRect(
            x: rectAppKit.origin.x,
            y: screenHeight - rectAppKit.origin.y - rectAppKit.height,
            width: rectAppKit.width,
            height: rectAppKit.height
        )

        finishSelection(with: cgRect)
    }

    private func finishSelection(with rect: CGRect?) {
        guard !didFinish else { return }
        didFinish = true
        onFinish?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw instructions
        let instructions = "Click and drag to select capture area. Press ESC to cancel."
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = instructions.size(withAttributes: attrs)
        let point = CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 60)
        instructions.draw(at: point, withAttributes: attrs)

        guard let start = startPoint, let current = currentPoint else { return }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Draw selection rectangle
        let path = NSBezierPath(rect: rect)
        NSColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.stroke()

        // Dim area outside selection
        let outside = NSBezierPath(rect: bounds)
        outside.appendRect(rect)
        outside.windingRule = .evenOdd
        NSColor(calibratedWhite: 0, alpha: 0.35).setFill()
        outside.fill()

        // Show dimensions
        let dimensionText = "\(Int(rect.width)) × \(Int(rect.height))"
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        let dimSize = dimensionText.size(withAttributes: dimAttrs)
        let dimPoint = CGPoint(
            x: rect.midX - dimSize.width / 2,
            y: rect.midY - dimSize.height / 2
        )
        dimensionText.draw(at: dimPoint, withAttributes: dimAttrs)
    }

    func cancelSelection() {
        finishSelection(with: nil)
    }
}
