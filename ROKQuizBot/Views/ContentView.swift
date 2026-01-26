// ContentView.swift
// Main application view
// Made by mpcode

import SwiftUI

struct ContentView: View {
    @State private var appModel = AppModel()
    @State private var showingSettings = false
    @State private var showingUnknownQuestions = false
    @State private var showingQuestionDatabase = false
    @State private var showingLayoutManager = false
    @State private var newLayoutName = ""
    @State private var showingSaveAsDialog = false
    @State private var layoutToRename: QuizLayoutConfiguration? = nil
    @State private var renameText = ""

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
                .frame(width: 900, height: 700)
        }
        .sheet(isPresented: $showingQuestionDatabase) {
            QuestionDatabaseView(appModel: appModel)
                .frame(minWidth: 700, minHeight: 500)
        }
        .alert("Save Layout As", isPresented: $showingSaveAsDialog) {
            TextField("Layout Name", text: $newLayoutName)
            Button("Save") {
                if !newLayoutName.isEmpty {
                    appModel.saveLayoutAs(name: newLayoutName)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for the new layout")
        }
        .alert("Rename Layout", isPresented: Binding(
            get: { layoutToRename != nil },
            set: { if !$0 { layoutToRename = nil } }
        )) {
            TextField("Layout Name", text: $renameText)
            Button("Rename") {
                if let layout = layoutToRename, !renameText.isEmpty {
                    appModel.renameLayout(layout.id, to: renameText)
                }
                layoutToRename = nil
            }
            Button("Cancel", role: .cancel) {
                layoutToRename = nil
            }
        } message: {
            Text("Enter a new name for the layout")
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
                .disabled(appModel.status.isRunning || appModel.isConfiguringLayout)

                Button(action: { appModel.beginLayoutConfiguration() }) {
                    Label("Configure Quiz Layout", systemImage: "rectangle.split.2x2")
                }
                .disabled(appModel.selectedCaptureRect == nil || appModel.status.isRunning || appModel.isConfiguringLayout)

                Button(action: { appModel.captureAndAnswer() }) {
                    Label(
                        appModel.status.isRunning ? "Processing..." : "Capture & Answer",
                        systemImage: appModel.status.isRunning ? "hourglass" : "sparkle.magnifyingglass"
                    )
                }
                .disabled(appModel.selectedCaptureRect == nil || appModel.status.isRunning || appModel.isConfiguringLayout)
            }

            Section("Hotkey") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("0")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Press 0 key (no modifiers)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Captures screen, finds answer, clicks it")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Settings") {
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

                // Layout configuration status
                GroupBox("Quiz Layout") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Layout picker
                        if !appModel.savedLayouts.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Select Game Layout")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("Layout", selection: Binding(
                                    get: { appModel.layoutConfiguration?.id },
                                    set: { id in
                                        if let id = id {
                                            appModel.selectLayout(id)
                                        } else {
                                            appModel.clearLayoutConfiguration()
                                        }
                                    }
                                )) {
                                    Text("None").tag(nil as UUID?)
                                    ForEach(appModel.savedLayouts) { layout in
                                        Text(layout.name).tag(layout.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        // Current layout info
                        if let layout = appModel.layoutConfiguration {
                            Divider()
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(layout.name)
                                    .font(.headline)
                            }
                            if layout.questionZone != nil {
                                Text("Question zone: Configured")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("Answer zones: \(layout.answerZones.count) (\(layout.answerZones.map { $0.label }.joined(separator: ", ")))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Action buttons
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    appModel.beginLayoutConfiguration()
                                }
                                .buttonStyle(.bordered)

                                Button("Rename") {
                                    renameText = layout.name
                                    layoutToRename = layout
                                }
                                .buttonStyle(.bordered)

                                Button("Delete") {
                                    appModel.deleteLayout(layout.id)
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                            .padding(.top, 4)

                            // Save as new layout
                            HStack {
                                Button("Save as New...") {
                                    newLayoutName = layout.name + " Copy"
                                    showingSaveAsDialog = true
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            if appModel.savedLayouts.isEmpty {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("No Layouts Saved")
                                        .font(.headline)
                                }
                                Text("Create a layout for precise zone-based OCR")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Button("Create New Layout") {
                                appModel.beginLayoutConfiguration()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
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
