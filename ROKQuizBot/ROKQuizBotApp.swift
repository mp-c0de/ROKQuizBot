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
        return true
    }
}
