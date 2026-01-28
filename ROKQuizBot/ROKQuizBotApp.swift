// ROKQuizBotApp.swift
// ROK Quiz Bot - Auto-answer Rise of Kingdoms quiz questions
// Made by mpcode

import SwiftUI

@main
struct ROKQuizBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ROK Quiz Bot") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "ROK Quiz Bot",
                            .applicationVersion: "1.0.0",
                            .credits: NSAttributedString(
                                string: "Made by mpcode\nAuto-answer Rise of Kingdoms quiz questions",
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 11),
                                    .foregroundColor: NSColor.secondaryLabelColor
                                ]
                            )
                        ]
                    )
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't request permissions on launch - wait until user tries to use features
        // This avoids the repeated permission dialogs during development
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // NSPanel (overlay) doesn't count as a regular window, so this works correctly
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check for unsaved capture area
        let appModel = AppModel.shared
        if appModel.checkForUnsavedChanges() {
            // Show confirmation dialog
            let alert = NSAlert()
            alert.messageText = "Unsaved Capture Area"
            alert.informativeText = "You have selected a capture area that hasn't been saved to a layout. If you quit now, this capture area will be lost.\n\nWould you like to save it first?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Don't Save - proceed with quit
                return .terminateNow
            case .alertSecondButtonReturn:
                // Cancel - don't quit
                return .terminateCancel
            default:
                return .terminateNow
            }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up the overlay window before app terminates
        CaptureAreaOverlay.close()
    }
}
