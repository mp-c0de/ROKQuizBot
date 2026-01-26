// SettingsView.swift
// Settings view for AI configuration
// Made by mpcode

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var aiManager = AIServiceManager.shared
    @State private var claudeAPIKey: String = ""
    @State private var openAIAPIKey: String = ""
    @State private var showingClaudeKey = false
    @State private var showingOpenAIKey = false
    @State private var isTestingClaude = false
    @State private var isTestingOpenAI = false
    @State private var claudeTestResult: TestResult?
    @State private var openAITestResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with Done button
            HStack {
                Text("AI Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                Section {
                    Text("Configure AI providers for automatic answer detection when questions aren't in the database.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                }

                Section("Active Provider") {
                    Picker("Use for AI Answers", selection: $aiManager.selectedProvider) {
                        Text("Claude").tag(AIProvider.claude)
                        Text("ChatGPT").tag(AIProvider.openAI)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        if aiManager.isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(aiManager.selectedProvider.displayName) is ready")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Configure \(aiManager.selectedProvider.displayName) API key below")
                                .foregroundColor(.orange)
                        }
                    }
                    .font(.caption)
                }

                Section("Claude API Key (Anthropic)") {
                    HStack {
                        if showingClaudeKey {
                            TextField("sk-ant-...", text: $claudeAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-ant-...", text: $claudeAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showingClaudeKey.toggle() }) {
                            Image(systemName: showingClaudeKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        if aiManager.isConfigured(provider: .claude) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Configured")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                            Text("Not configured")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Test") {
                            Task { await testClaudeConnection() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTestingClaude || claudeAPIKey.isEmpty)

                        Link("Get API Key", destination: AIProvider.claude.consoleURL)
                            .font(.caption)
                    }

                    if isTestingClaude {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing Claude...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let result = claudeTestResult {
                        testResultView(result)
                    }
                }

                Section("OpenAI API Key (ChatGPT)") {
                    HStack {
                        if showingOpenAIKey {
                            TextField("sk-...", text: $openAIAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $openAIAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showingOpenAIKey.toggle() }) {
                            Image(systemName: showingOpenAIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        if aiManager.isConfigured(provider: .openAI) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Configured")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                            Text("Not configured")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Test") {
                            Task { await testOpenAIConnection() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTestingOpenAI || openAIAPIKey.isEmpty)

                        Link("Get API Key", destination: AIProvider.openAI.consoleURL)
                            .font(.caption)
                    }

                    if isTestingOpenAI {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing OpenAI...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let result = openAITestResult {
                        testResultView(result)
                    }
                }

                Section {
                    Button("Save API Keys") {
                        saveAPIKeys()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section {
                    Text("Made by mpcode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            loadAPIKeys()
        }
    }

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .success(let message):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(message)
                    .foregroundColor(.green)
            }
            .font(.caption)
        case .failure(let message):
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            .font(.caption)
        }
    }

    private func loadAPIKeys() {
        claudeAPIKey = aiManager.getAPIKey(for: .claude)
        openAIAPIKey = aiManager.getAPIKey(for: .openAI)
    }

    private func saveAPIKeys() {
        aiManager.setAPIKey(claudeAPIKey, for: .claude)
        aiManager.setAPIKey(openAIAPIKey, for: .openAI)
        claudeTestResult = nil
        openAITestResult = nil
    }

    private func testClaudeConnection() async {
        // Save first to test the current value
        aiManager.setAPIKey(claudeAPIKey, for: .claude)

        isTestingClaude = true
        claudeTestResult = nil

        do {
            let result = try await aiManager.testConnection(provider: .claude)
            await MainActor.run {
                claudeTestResult = .success(result)
                isTestingClaude = false
            }
        } catch {
            await MainActor.run {
                claudeTestResult = .failure(error.localizedDescription)
                isTestingClaude = false
            }
        }
    }

    private func testOpenAIConnection() async {
        // Save first to test the current value
        aiManager.setAPIKey(openAIAPIKey, for: .openAI)

        isTestingOpenAI = true
        openAITestResult = nil

        do {
            let result = try await aiManager.testConnection(provider: .openAI)
            await MainActor.run {
                openAITestResult = .success(result)
                isTestingOpenAI = false
            }
        } catch {
            await MainActor.run {
                openAITestResult = .failure(error.localizedDescription)
                isTestingOpenAI = false
            }
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 500, height: 550)
}
