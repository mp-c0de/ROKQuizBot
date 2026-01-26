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
    @State private var isTesting = false
    @State private var testResult: TestResult?

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
                        ForEach(AIProvider.allCases) { provider in
                            HStack {
                                Image(systemName: provider.iconName)
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
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

                        Link("Get API Key", destination: AIProvider.claude.consoleURL)
                            .font(.caption)
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

                        Link("Get API Key", destination: AIProvider.openAI.consoleURL)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Button("Save API Keys") {
                            saveAPIKeys()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Test API Connection") {
                            Task { await testAPIConnection() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTesting || !aiManager.isConfigured)
                    }

                    if isTesting {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing connection...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let result = testResult {
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
                            }
                            .font(.caption)
                        }
                    }
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

    private func loadAPIKeys() {
        claudeAPIKey = aiManager.getAPIKey(for: .claude)
        openAIAPIKey = aiManager.getAPIKey(for: .openAI)
    }

    private func saveAPIKeys() {
        aiManager.setAPIKey(claudeAPIKey, for: .claude)
        aiManager.setAPIKey(openAIAPIKey, for: .openAI)
        testResult = nil
    }

    private func testAPIConnection() async {
        isTesting = true
        testResult = nil

        do {
            let result = try await aiManager.testConnection()
            await MainActor.run {
                testResult = .success(result)
                isTesting = false
            }
        } catch {
            await MainActor.run {
                testResult = .failure(error.localizedDescription)
                isTesting = false
            }
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 500, height: 500)
}
