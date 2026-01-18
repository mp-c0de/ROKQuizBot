// ContentView.swift
// Main application view
// Made by mpcode

import SwiftUI

struct ContentView: View {
    @State private var appModel = AppModel()
    @State private var showingSettings = false
    @State private var showingUnknownQuestions = false
    @State private var showingQuestionDatabase = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            sidebarView
        } detail: {
            // Main content
            mainContentView
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(width: 500, height: 400)
        }
        .sheet(isPresented: $showingUnknownQuestions) {
            UnknownQuestionsView(appModel: appModel)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: $showingQuestionDatabase) {
            QuestionDatabaseView(appModel: appModel)
                .frame(minWidth: 700, minHeight: 500)
        }
    }

    // MARK: - Sidebar
    private var sidebarView: some View {
        List {
            Section("Status") {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(appModel.status.description)
                        .font(.headline)
                }

                LabeledContent("Questions Loaded", value: "\(appModel.questionsLoaded)")
                LabeledContent("Answered", value: "\(appModel.answeredCount)")
                LabeledContent("Unknown", value: "\(appModel.unknownCount)")
            }

            Section("Controls") {
                Button(action: { appModel.beginAreaSelection() }) {
                    Label("Select Capture Area", systemImage: "rectangle.dashed")
                }
                .disabled(appModel.status.isRunning)

                Button(action: { appModel.toggleMonitoring() }) {
                    Label(
                        appModel.status.isRunning ? "Stop" : "Start",
                        systemImage: appModel.status.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .disabled(appModel.selectedCaptureRect == nil)
                .keyboardShortcut(.space, modifiers: [])
            }

            Section("Settings") {
                HStack {
                    Text("Interval")
                    Spacer()
                    TextField("", value: $appModel.captureInterval, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text("sec")
                }

                Toggle("Hide Cursor During Capture", isOn: $appModel.hideCursorDuringCapture)
                Toggle("Sound Effects", isOn: $appModel.soundEnabled)
                Toggle("Auto-add Unknown Questions", isOn: $appModel.autoAddUnknown)
            }

            Section("Data") {
                Button(action: { showingUnknownQuestions = true }) {
                    Label("Unknown Questions (\(appModel.unknownCount))", systemImage: "questionmark.circle")
                }

                Button(action: { showingQuestionDatabase = true }) {
                    Label("Question Database", systemImage: "list.bullet.rectangle")
                }

                Button(action: { showingSettings = true }) {
                    Label("AI Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 250)
    }

    // MARK: - Main Content
    private var mainContentView: some View {
        VStack(spacing: 20) {
            // Capture area info
            if let rect = appModel.selectedCaptureRect {
                GroupBox("Capture Area") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Position: (\(Int(rect.origin.x)), \(Int(rect.origin.y)))")
                        Text("Size: \(Int(rect.width)) × \(Int(rect.height))")
                    }
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Capture Area Selected",
                    systemImage: "rectangle.dashed",
                    description: Text("Click 'Select Capture Area' to choose the screen region to monitor.")
                )
            }

            // Last capture preview
            if let capture = appModel.lastCapture {
                GroupBox("Last Capture") {
                    Image(nsImage: capture)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .border(Color.gray.opacity(0.3), width: 1)
                }
            }

            // OCR Result
            if !appModel.lastOCRText.isEmpty {
                GroupBox("Detected Text") {
                    ScrollView {
                        Text(appModel.lastOCRText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                }
            }

            // Match Result
            if let match = appModel.lastMatchedQuestion {
                GroupBox("Matched Question") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(match.text)
                            .font(.headline)
                        HStack {
                            Text("Answer:")
                                .foregroundColor(.secondary)
                            Text(match.answer)
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        if let clicked = appModel.lastClickedAnswer {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Clicked: \(clicked)")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }

            Spacer()

            // Hotkey hint
            Text("Press ⌘⇧Esc to emergency stop")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Status Color
    private var statusColor: Color {
        switch appModel.status {
        case .idle:
            return .gray
        case .selectingArea:
            return .blue
        case .running:
            return .green
        case .paused:
            return .orange
        case .error:
            return .red
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
