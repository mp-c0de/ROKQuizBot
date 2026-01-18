// MouseController.swift
// Service for controlling mouse position and clicks
// Made by mpcode

import Foundation
import AppKit

final class MouseController {

    /// Moves the mouse cursor to the specified screen position.
    /// - Parameter point: The target position in screen coordinates (origin top-left).
    func moveTo(_ point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    /// Performs a mouse click at the specified screen position.
    /// - Parameter point: The position to click in screen coordinates (origin top-left).
    func click(at point: CGPoint) {
        // Move to position first
        moveTo(point)

        // Create mouse down event
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        // Create mouse up event
        guard let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        // Post the events
        mouseDown.post(tap: .cghidEventTap)

        // Small delay between down and up
        usleep(50000) // 50ms

        mouseUp.post(tap: .cghidEventTap)
    }

    /// Performs a double click at the specified screen position.
    /// - Parameter point: The position to double-click in screen coordinates.
    func doubleClick(at point: CGPoint) {
        click(at: point)
        usleep(100000) // 100ms delay
        click(at: point)
    }

    /// Gets the current mouse cursor position.
    /// - Returns: The current cursor position in screen coordinates.
    func currentPosition() -> CGPoint {
        return NSEvent.mouseLocation
    }

    /// Hides the mouse cursor.
    func hideCursor() {
        NSCursor.hide()
    }

    /// Shows the mouse cursor.
    func showCursor() {
        NSCursor.unhide()
    }
}
