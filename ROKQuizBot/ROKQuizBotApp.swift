// ROKQuizBotApp.swift
// ROK Quiz Bot - Auto-answer Rise of Kingdoms quiz questions
// Made by mpcode

import SwiftUI
import ScreenCaptureKit

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
        // Request screen recording permission on launch
        Task {
            await checkScreenRecordingPermission()
        }
        // Request accessibility permission for mouse control
        checkAccessibilityPermission()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func checkScreenRecordingPermission() async {
        // Trigger the permission dialog by attempting to get shareable content
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            print("Screen recording permission needed: \(error)")
        }
    }

    private nonisolated func checkAccessibilityPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
