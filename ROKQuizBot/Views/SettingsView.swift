// SettingsView.swift
// Settings view for AI configuration
// Made by mpcode

import SwiftUI

struct SettingsView: View {
    @State private var aiManager = AIServiceManager.shared
    @State private var claudeAPIKey: String = ""
    @State private var openAIAPIKey: String = ""
    @State private var showingClaudeKey = false
    @State private var showingOpenAIKey = false

    var body: some View {
        Form {
            Section {
                Text("AI Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Configure AI providers for automatic answer detection when questions aren't in the database.")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }

            Section("Selected Provider") {
                Picker("AI Provider", selection: $aiManager.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        HStack {
                            Image(systemName: provider.iconName)
                            Text(provider.displayName)
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                Text(aiManager.selectedProvider.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Claude API Key") {
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

            Section("OpenAI API Key") {
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
        .padding()
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
    }
}

#Preview {
    SettingsView()
        .frame(width: 500, height: 400)
}
