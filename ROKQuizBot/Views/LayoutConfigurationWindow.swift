// LayoutConfigurationWindow.swift
// Overlay window for configuring quiz layout zones
// Made by mpcode

import AppKit

/// A window that displays a captured image and allows the user to drag and resize rectangles
/// to define question and answer zones.
final class LayoutConfigurationWindow: NSWindow, NSWindowDelegate {
    private var overlayView: LayoutConfigurationView!
    private var completion: ((QuizLayoutConfiguration?) -> Void)?

    static func present(
        with image: NSImage,
        captureRect: CGRect,
        existingLayout: QuizLayoutConfiguration?,
        on screen: NSScreen? = NSScreen.main,
        completion: @escaping (QuizLayoutConfiguration?) -> Void
    ) {
        let screen = screen ?? NSScreen.main!
        let window = LayoutConfigurationWindow(
            screen: screen,
            image: image,
            captureRect: captureRect,
            existingLayout: existingLayout,
            completion: completion
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.overlayView)
    }

    convenience init(
        screen: NSScreen,
        image: NSImage,
        captureRect: CGRect,
        existingLayout: QuizLayoutConfiguration?,
        completion: @escaping (QuizLayoutConfiguration?) -> Void
    ) {
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

        // Use existing layout or create a default one with pre-populated zones for convenience
        let layoutToEdit = existingLayout ?? QuizLayoutConfiguration.createDefault()
        let isEditingExisting = existingLayout != nil  // Only true if actually editing a saved layout
        overlayView = LayoutConfigurationView(
            frame: frame,
            image: image,
            captureRect: captureRect,
            existingLayout: layoutToEdit,
            isEditingExisting: isEditingExisting
        )
        contentView = overlayView

        overlayView.onFinish = { [weak self] layout in
            guard let self = self else { return }
            self.orderOut(nil)
            self.completion?(layout)
            self.completion = nil
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowDidResignKey(_ notification: Notification) {
        // Don't auto-cancel when window loses focus - user should explicitly press ESC
        // This prevents accidental cancellation when clicking elsewhere
        // overlayView.cancelConfiguration()
    }
}

// MARK: - Draggable Zone

private class DraggableZone {
    var id: UUID
    var normalizedRect: CGRect
    var label: String
    var zoneType: ZoneType
    var isSelected: Bool = false

    init(from layoutZone: LayoutZone) {
        self.id = layoutZone.id
        self.normalizedRect = layoutZone.normalizedRect
        self.label = layoutZone.label
        self.zoneType = layoutZone.zoneType
    }

    init(id: UUID = UUID(), normalizedRect: CGRect, label: String, zoneType: ZoneType) {
        self.id = id
        self.normalizedRect = normalizedRect
        self.label = label
        self.zoneType = zoneType
    }

    func toLayoutZone() -> LayoutZone {
        return LayoutZone(id: id, normalizedRect: normalizedRect, label: label, zoneType: zoneType)
    }

    var color: NSColor {
        switch zoneType {
        case .question:
            return .systemBlue
        case .answer:
            return .systemGreen
        }
    }
}

// MARK: - Layout Configuration View

final class LayoutConfigurationView: NSView, NSTextFieldDelegate {
    var onFinish: ((QuizLayoutConfiguration?) -> Void)?

    private let backgroundImage: NSImage
    private let imageRect: CGRect  // Where the image is drawn in view coordinates
    private var zones: [DraggableZone] = []
    private var selectedZone: DraggableZone?
    private var dragMode: DragMode = .none
    private var dragStartPoint: CGPoint = .zero
    private var dragStartRect: CGRect = .zero

    private enum DragMode {
        case none
        case move
        case resizeTopLeft
        case resizeTopRight
        case resizeBottomLeft
        case resizeBottomRight
        case resizeTop
        case resizeBottom
        case resizeLeft
        case resizeRight
    }

    private let handleSize: CGFloat = 10
    private var didFinish = false

    // Layout name input
    private var nameTextField: NSTextField!
    private var existingLayoutId: UUID?  // Only set when editing a truly existing saved layout

    init(frame: CGRect, image: NSImage, captureRect: CGRect, existingLayout: QuizLayoutConfiguration, isEditingExisting: Bool) {
        self.backgroundImage = image
        // Only preserve the layout ID if we're actually editing an existing saved layout
        self.existingLayoutId = isEditingExisting ? existingLayout.id : nil

        // Calculate where to draw the image (centred in view, scaled to fit)
        let viewAspect = frame.width / frame.height
        let imageAspect = captureRect.width / captureRect.height

        var imageFrame: CGRect
        if imageAspect > viewAspect {
            // Image is wider - fit to width
            let width = frame.width * 0.8
            let height = width / imageAspect
            imageFrame = CGRect(
                x: (frame.width - width) / 2,
                y: (frame.height - height) / 2,
                width: width,
                height: height
            )
        } else {
            // Image is taller - fit to height
            let height = frame.height * 0.8
            let width = height * imageAspect
            imageFrame = CGRect(
                x: (frame.width - width) / 2,
                y: (frame.height - height) / 2,
                width: width,
                height: height
            )
        }
        self.imageRect = imageFrame

        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.95).cgColor

        // Create name input section with label - positioned prominently at top
        let labelWidth: CGFloat = 400
        let labelHeight: CGFloat = 20
        let textFieldWidth: CGFloat = 400
        let textFieldHeight: CGFloat = 32
        let topMargin: CGFloat = frame.height - 100  // Near the top

        // Label above text field
        let nameLabel = NSTextField(labelWithString: "LAYOUT NAME (required):")
        nameLabel.frame = CGRect(
            x: (frame.width - labelWidth) / 2,
            y: topMargin + textFieldHeight + 8,
            width: labelWidth,
            height: labelHeight
        )
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 14, weight: .bold)
        nameLabel.textColor = .white
        addSubview(nameLabel)

        // Name text field - larger and more prominent
        nameTextField = NSTextField(frame: CGRect(
            x: (frame.width - textFieldWidth) / 2,
            y: topMargin,
            width: textFieldWidth,
            height: textFieldHeight
        ))
        nameTextField.wantsLayer = true
        nameTextField.layer?.cornerRadius = 6
        nameTextField.layer?.borderWidth = 2
        nameTextField.layer?.borderColor = NSColor.systemBlue.cgColor
        // For new layouts, show empty field with placeholder; for existing, show the name
        nameTextField.stringValue = isEditingExisting ? existingLayout.name : ""
        nameTextField.placeholderString = "Enter layout name (e.g., Game1, ROK Quiz)"
        nameTextField.alignment = .center
        nameTextField.font = .systemFont(ofSize: 18, weight: .medium)
        nameTextField.delegate = self
        nameTextField.bezelStyle = .roundedBezel
        nameTextField.focusRingType = .none
        addSubview(nameTextField)

        // Load existing zones
        if let questionZone = existingLayout.questionZone {
            zones.append(DraggableZone(from: questionZone))
        }
        for answerZone in existingLayout.answerZones {
            zones.append(DraggableZone(from: answerZone))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            cancelConfiguration()
        case 36: // Enter/Return
            finishConfiguration()
        case 51: // Delete/Backspace
            deleteSelectedZone()
        case 12: // Q
            addQuestionZone()
        case 0:  // A
            addAnswerZone("A")
        case 11: // B
            addAnswerZone("B")
        case 8:  // C
            addAnswerZone("C")
        case 2:  // D
            addAnswerZone("D")
        default:
            break
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if clicking on a zone
        selectedZone = nil
        for zone in zones {
            zone.isSelected = false
        }

        for zone in zones.reversed() {
            let zoneRect = normalizedToView(zone.normalizedRect)

            // Check resize handles first
            if let mode = hitTestHandles(point: point, rect: zoneRect) {
                selectedZone = zone
                zone.isSelected = true
                dragMode = mode
                dragStartPoint = point
                dragStartRect = zone.normalizedRect
                needsDisplay = true
                return
            }

            // Check if inside zone
            if zoneRect.contains(point) {
                selectedZone = zone
                zone.isSelected = true
                dragMode = .move
                dragStartPoint = point
                dragStartRect = zone.normalizedRect
                needsDisplay = true
                return
            }
        }

        dragMode = .none
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let zone = selectedZone, dragMode != .none else { return }

        let point = convert(event.locationInWindow, from: nil)
        // Note: Negate delta.y because AppKit Y increases upward, but normalised Y increases downward
        let delta = CGPoint(
            x: (point.x - dragStartPoint.x) / imageRect.width,
            y: -(point.y - dragStartPoint.y) / imageRect.height
        )

        var newRect = dragStartRect

        switch dragMode {
        case .move:
            newRect.origin.x = max(0, min(1 - newRect.width, dragStartRect.origin.x + delta.x))
            newRect.origin.y = max(0, min(1 - newRect.height, dragStartRect.origin.y + delta.y))

        case .resizeTopLeft:
            newRect.origin.x = dragStartRect.origin.x + delta.x
            newRect.origin.y = dragStartRect.origin.y + delta.y
            newRect.size.width = dragStartRect.width - delta.x
            newRect.size.height = dragStartRect.height - delta.y

        case .resizeTopRight:
            newRect.origin.y = dragStartRect.origin.y + delta.y
            newRect.size.width = dragStartRect.width + delta.x
            newRect.size.height = dragStartRect.height - delta.y

        case .resizeBottomLeft:
            // Bottom edge (larger Y) + Left edge
            newRect.origin.x = dragStartRect.origin.x + delta.x
            newRect.size.width = dragStartRect.width - delta.x
            newRect.size.height = dragStartRect.height + delta.y

        case .resizeBottomRight:
            // Bottom edge (larger Y) + Right edge
            newRect.size.width = dragStartRect.width + delta.x
            newRect.size.height = dragStartRect.height + delta.y

        case .resizeTop:
            // Top edge (smaller Y = origin.y)
            newRect.origin.y = dragStartRect.origin.y + delta.y
            newRect.size.height = dragStartRect.height - delta.y

        case .resizeBottom:
            // Bottom edge (larger Y = origin.y + height)
            newRect.size.height = dragStartRect.height + delta.y

        case .resizeLeft:
            newRect.origin.x = dragStartRect.origin.x + delta.x
            newRect.size.width = dragStartRect.width - delta.x

        case .resizeRight:
            newRect.size.width = dragStartRect.width + delta.x

        case .none:
            break
        }

        // Enforce minimum size
        if newRect.width >= 0.05 && newRect.height >= 0.05 {
            // Clamp to bounds
            newRect.origin.x = max(0, min(1 - newRect.width, newRect.origin.x))
            newRect.origin.y = max(0, min(1 - newRect.height, newRect.origin.y))
            newRect.size.width = min(1 - newRect.origin.x, newRect.width)
            newRect.size.height = min(1 - newRect.origin.y, newRect.height)

            zone.normalizedRect = newRect
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
    }

    // MARK: - Hit Testing

    private func hitTestHandles(point: CGPoint, rect: CGRect) -> DragMode? {
        let handles: [(CGRect, DragMode)] = [
            (handleRect(at: CGPoint(x: rect.minX, y: rect.maxY)), .resizeTopLeft),
            (handleRect(at: CGPoint(x: rect.maxX, y: rect.maxY)), .resizeTopRight),
            (handleRect(at: CGPoint(x: rect.minX, y: rect.minY)), .resizeBottomLeft),
            (handleRect(at: CGPoint(x: rect.maxX, y: rect.minY)), .resizeBottomRight),
            (handleRect(at: CGPoint(x: rect.midX, y: rect.maxY)), .resizeTop),
            (handleRect(at: CGPoint(x: rect.midX, y: rect.minY)), .resizeBottom),
            (handleRect(at: CGPoint(x: rect.minX, y: rect.midY)), .resizeLeft),
            (handleRect(at: CGPoint(x: rect.maxX, y: rect.midY)), .resizeRight),
        ]

        for (handleRect, mode) in handles {
            if handleRect.contains(point) {
                return mode
            }
        }
        return nil
    }

    private func handleRect(at point: CGPoint) -> CGRect {
        return CGRect(
            x: point.x - handleSize / 2,
            y: point.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
    }

    // MARK: - Coordinate Conversion

    private func normalizedToView(_ normalized: CGRect) -> CGRect {
        return CGRect(
            x: imageRect.origin.x + normalized.origin.x * imageRect.width,
            y: imageRect.origin.y + (1 - normalized.origin.y - normalized.height) * imageRect.height,
            width: normalized.width * imageRect.width,
            height: normalized.height * imageRect.height
        )
    }

    private func viewToNormalized(_ viewRect: CGRect) -> CGRect {
        return CGRect(
            x: (viewRect.origin.x - imageRect.origin.x) / imageRect.width,
            y: 1 - (viewRect.origin.y - imageRect.origin.y + viewRect.height) / imageRect.height,
            width: viewRect.width / imageRect.width,
            height: viewRect.height / imageRect.height
        )
    }

    // MARK: - Zone Management

    private func addQuestionZone() {
        // Remove existing question zone if any
        zones.removeAll { $0.zoneType == .question }

        let newZone = DraggableZone(
            normalizedRect: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.2),
            label: "Question",
            zoneType: .question
        )
        zones.insert(newZone, at: 0)
        selectedZone = newZone
        for zone in zones { zone.isSelected = false }
        newZone.isSelected = true
        needsDisplay = true
    }

    private func addAnswerZone(_ label: String) {
        // Remove existing zone with same label if any
        zones.removeAll { $0.label == label && $0.zoneType == .answer }

        // Calculate position based on label
        let positions: [String: CGRect] = [
            "A": CGRect(x: 0.05, y: 0.35, width: 0.4, height: 0.25),
            "B": CGRect(x: 0.55, y: 0.35, width: 0.4, height: 0.25),
            "C": CGRect(x: 0.05, y: 0.65, width: 0.4, height: 0.25),
            "D": CGRect(x: 0.55, y: 0.65, width: 0.4, height: 0.25),
        ]

        let rect = positions[label] ?? CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.2)
        let newZone = DraggableZone(normalizedRect: rect, label: label, zoneType: .answer)
        zones.append(newZone)

        selectedZone = newZone
        for zone in zones { zone.isSelected = false }
        newZone.isSelected = true
        needsDisplay = true
    }

    private func deleteSelectedZone() {
        guard let zone = selectedZone else { return }
        zones.removeAll { $0.id == zone.id }
        selectedZone = nil
        needsDisplay = true
    }

    // MARK: - Finish/Cancel

    func finishConfiguration() {
        guard !didFinish else { return }

        let questionZone = zones.first { $0.zoneType == .question }?.toLayoutZone()
        let answerZones = zones.filter { $0.zoneType == .answer }.map { $0.toLayoutZone() }

        // Get name from text field - REQUIRE a name for new layouts
        let layoutName = nameTextField.stringValue.trimmingCharacters(in: .whitespaces)
        if layoutName.isEmpty {
            // Shake the text field to indicate name is required
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.duration = 0.4
            animation.values = [-10, 10, -8, 8, -5, 5, -2, 2, 0]
            nameTextField.layer?.add(animation, forKey: "shake")

            // Focus the text field
            window?.makeFirstResponder(nameTextField)
            return  // Don't save without a name
        }

        didFinish = true

        // Preserve the existing layout ID if editing, otherwise create new
        let layoutId = existingLayoutId ?? UUID()

        let layout = QuizLayoutConfiguration(
            id: layoutId,
            name: layoutName,
            questionZone: questionZone,
            answerZones: answerZones
        )

        onFinish?(layout)
    }

    // Handle Enter key in text field - save and close
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            // Enter pressed in text field - save the layout
            finishConfiguration()
            return true
        }
        return false
    }

    func cancelConfiguration() {
        guard !didFinish else { return }
        didFinish = true
        onFinish?(nil)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw background image
        backgroundImage.draw(in: imageRect)

        // Draw semi-transparent overlay
        NSColor(calibratedWhite: 0, alpha: 0.3).setFill()
        NSBezierPath(rect: imageRect).fill()

        // Draw zones
        for zone in zones {
            drawZone(zone)
        }

        // Draw instructions at top
        drawInstructions()
    }

    private func drawZone(_ zone: DraggableZone) {
        let rect = normalizedToView(zone.normalizedRect)
        let path = NSBezierPath(rect: rect)

        // Fill
        zone.color.withAlphaComponent(0.2).setFill()
        path.fill()

        // Stroke
        zone.color.setStroke()
        path.lineWidth = zone.isSelected ? 3 : 2
        path.stroke()

        // Draw label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.white,
            .backgroundColor: zone.color.withAlphaComponent(0.8)
        ]
        let labelSize = zone.label.size(withAttributes: labelAttrs)
        let labelPoint = CGPoint(
            x: rect.origin.x + 5,
            y: rect.maxY - labelSize.height - 5
        )
        zone.label.draw(at: labelPoint, withAttributes: labelAttrs)

        // Draw handles if selected
        if zone.isSelected {
            drawHandles(for: rect)
        }
    }

    private func drawHandles(for rect: CGRect) {
        let handlePoints = [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
        ]

        NSColor.white.setFill()
        for point in handlePoints {
            let handle = handleRect(at: point)
            NSBezierPath(ovalIn: handle).fill()
        }
    }

    private func drawInstructions() {
        let instructions = """
        Q = Question zone | A/B/C/D = Answer zones | Delete = Remove selected | ESC = Cancel
        Drag zones to move, drag handles to resize | Enter name above and press Enter to save
        """

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        var attrsWithPara = attrs
        attrsWithPara[.paragraphStyle] = paragraphStyle

        let size = instructions.size(withAttributes: attrs)
        let point = CGPoint(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - 60
        )
        instructions.draw(at: point, withAttributes: attrsWithPara)
    }
}
