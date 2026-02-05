// ContentView.swift
// Main application view
// Made by mpcode

import SwiftUI

struct ContentView: View {
    @Bindable private var appModel = AppModel.shared
    @State private var showingSettings = false
    @State private var showingUnknownQuestions = false
    @State private var showingQuestionDatabase = false
    @State private var showingLayoutManager = false
    @State private var newLayoutName = ""
    @State private var showingSaveAsDialog = false
    @State private var layoutToRename: QuizLayoutConfiguration? = nil
    @State private var renameText = ""

    // Computed properties to avoid inline observable checks in .disabled()
    private var hasCaptureArea: Bool {
        appModel.selectedCaptureRect != nil
    }

    private var canConfigureLayout: Bool {
        hasCaptureArea && !appModel.status.isRunning && !appModel.isConfiguringLayout
    }

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
        .onDisappear {
            // Clean up overlay when view disappears
            CaptureAreaOverlay.close()
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

            // Show saved layouts in sidebar for quick selection on launch
            if !appModel.savedLayouts.isEmpty {
                Section("Game Layout") {
                    Picker("Select Game", selection: Binding(
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

                    if let layout = appModel.layoutConfiguration {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(layout.name)
                                .font(.caption)
                        }
                    }
                }
            }

            Section("Controls") {
                Button(action: { appModel.beginAreaSelection() }) {
                    Label("Select Capture Area", systemImage: "rectangle.dashed")
                }
                .disabled(appModel.status.isRunning || appModel.isConfiguringLayout)

                Button(action: { appModel.beginLayoutConfiguration() }) {
                    Label("Configure Quiz Layout", systemImage: "rectangle.split.2x2")
                }
                .disabled(!canConfigureLayout)

                Button(action: { appModel.captureAndAnswer() }) {
                    Label(
                        appModel.status.isRunning ? "Processing..." : "Capture & Answer",
                        systemImage: appModel.status.isRunning ? "hourglass" : "sparkle.magnifyingglass"
                    )
                }
                .disabled(!canConfigureLayout)
            }

            Section("Hotkeys") {
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

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("9")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        if appModel.isAIProcessing {
                            ProgressView()
                                .controlSize(.small)
                            Text("AI thinking...")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    Text("Press 9 key (no modifiers)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Ask AI for answer (when no match)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Settings") {
                Toggle("Auto-Click Answer", isOn: $appModel.autoClickEnabled)
                Toggle("Hide Cursor During Capture", isOn: $appModel.hideCursorDuringCapture)
                Toggle("Sound Effects", isOn: $appModel.soundEnabled)
                Toggle("Auto-add Unknown Questions", isOn: $appModel.autoAddUnknown)
                Toggle("Show Capture Area Border", isOn: $appModel.showCaptureOverlay)
                    .disabled(!hasCaptureArea)
                    .task(id: appModel.showCaptureOverlay) {
                        // Runs AFTER render - no cycle
                        appModel.saveCaptureOverlaySetting()
                        appModel.setOverlayEnabled(appModel.showCaptureOverlay)
                    }
            }

            Section("Capture Quality") {
                Picker("Quality", selection: $appModel.captureQuality) {
                    ForEach(CaptureQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .task(id: appModel.captureQuality) {
                    appModel.saveCaptureQuality()
                }

                Text(appModel.captureQuality.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Debug") {
                Toggle("Debug OCR (next capture)", isOn: $appModel.ocrDebugMode)
                    .help("Saves 7 image variants per answer zone with OCR results")

                if let path = appModel.lastDebugOutputPath {
                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }) {
                        Label("Open Debug Folder", systemImage: "folder")
                    }
                    .font(.caption)
                }
            }

            Section("OCR Settings") {
                Picker("Preset", selection: Binding(
                    get: { currentOCRPreset },
                    set: { appModel.applyOCRPreset($0) }
                )) {
                    ForEach(OCRPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                DisclosureGroup("Fine Tuning") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Contrast: \(appModel.ocrSettings.contrast, specifier: "%.1f")")
                                .font(.caption)
                            Slider(value: $appModel.ocrSettings.contrast, in: 0.5...4.0, step: 0.1)
                        }
                        HStack {
                            Text("Brightness: \(appModel.ocrSettings.brightness, specifier: "%.2f")")
                                .font(.caption)
                            Slider(value: $appModel.ocrSettings.brightness, in: -0.5...0.5, step: 0.05)
                        }
                        HStack {
                            Text("Scale: \(appModel.ocrSettings.scaleFactor, specifier: "%.1f")x")
                                .font(.caption)
                            Slider(value: $appModel.ocrSettings.scaleFactor, in: 1.0...4.0, step: 0.5)
                        }
                        Toggle("Grayscale", isOn: $appModel.ocrSettings.grayscaleEnabled)
                            .font(.caption)
                        Toggle("Sharpening", isOn: $appModel.ocrSettings.sharpeningEnabled)
                            .font(.caption)
                        Toggle("Invert Colors", isOn: $appModel.ocrSettings.invertColors)
                            .font(.caption)

                        Button("Save Settings") {
                            appModel.saveOCRSettings()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
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
        .frame(minWidth: 280)
        .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 350)
    }

    // MARK: - Main Content
    private var mainContentView: some View {
        VStack(spacing: 20) {
            // Capture area info
            if let rect = appModel.selectedCaptureRect {
                GroupBox("Capture Area") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Position: (\(Int(rect.origin.x)), \(Int(rect.origin.y)))")
                            Spacer()
                            if appModel.hasUnsavedCaptureArea {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("Unsaved")
                                        .foregroundColor(.orange)
                                }
                                .font(.caption)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Saved")
                                        .foregroundColor(.green)
                                }
                                .font(.caption)
                            }
                        }
                        Text("Size: \(Int(rect.width)) × \(Int(rect.height))")

                        if appModel.hasUnsavedCaptureArea {
                            Text("Save a layout to persist this capture area")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

            // Debug output info
            if let debugPath = appModel.lastDebugOutputPath {
                GroupBox("Debug Output") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "ant.circle.fill")
                                .foregroundColor(.orange)
                            Text("Debug images saved")
                                .font(.headline)
                        }
                        Text(debugPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Open in Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: debugPath))
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
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

    // MARK: - OCR Preset Detection
    private var currentOCRPreset: OCRPreset {
        let settings = appModel.ocrSettings
        if settings == .gameText { return .gameText }
        if settings == .lightOnDark { return .lightOnDark }
        return .default
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
