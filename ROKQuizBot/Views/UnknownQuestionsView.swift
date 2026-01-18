// UnknownQuestionsView.swift
// View for managing unknown questions that need answers
// Made by mpcode

import SwiftUI

struct UnknownQuestionsView: View {
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestion: UnknownQuestion?
    @State private var answerText: String = ""
    @State private var isAskingAI = false
    @State private var aiError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Unknown Questions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                }
                .padding()

                Divider()

                if appModel.getUnknownQuestions().isEmpty {
                    ContentUnavailableView(
                        "No Unknown Questions",
                        systemImage: "checkmark.circle",
                        description: Text("All questions have been answered or resolved.")
                    )
                } else {
                    // Question list
                    List(appModel.getUnknownQuestions(), selection: $selectedQuestion) { question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.questionText)
                                .font(.headline)
                                .lineLimit(2)

                            HStack {
                                Text(question.timestamp, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if !question.detectedOptions.isEmpty {
                                    Text("• \(question.detectedOptions.count) options detected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(question)
                    }
                }

                // Answer panel
                if let question = selectedQuestion {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selected Question")
                            .font(.headline)

                        Text(question.questionText)
                            .font(.body)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)

                        if !question.detectedOptions.isEmpty {
                            Text("Detected Options:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ForEach(question.detectedOptions, id: \.self) { option in
                                Button(action: {
                                    answerText = option
                                }) {
                                    HStack {
                                        Text(option)
                                        Spacer()
                                        if answerText == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(answerText == option ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(4)
                            }
                        }

                        HStack {
                            TextField("Enter correct answer...", text: $answerText)
                                .textFieldStyle(.roundedBorder)

                            Button("Ask AI") {
                                Task { await askAIForAnswer() }
                            }
                            .disabled(!AIServiceManager.shared.isConfigured || isAskingAI)
                        }

                        if let error = aiError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        HStack {
                            Button("Delete Question") {
                                if let q = selectedQuestion {
                                    appModel.deleteUnknownQuestion(q)
                                    selectedQuestion = nil
                                    answerText = ""
                                }
                            }
                            .foregroundColor(.red)

                            Spacer()

                            Button("Save Answer") {
                                if let q = selectedQuestion, !answerText.isEmpty {
                                    appModel.resolveUnknownQuestion(q, with: answerText)
                                    selectedQuestion = nil
                                    answerText = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(answerText.isEmpty)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
    }

    private func askAIForAnswer() async {
        guard let question = selectedQuestion,
              let capture = appModel.lastCapture else {
            aiError = "No capture available"
            return
        }

        isAskingAI = true
        aiError = nil

        do {
            let response = try await AIServiceManager.shared.askForAnswer(image: capture)
            await MainActor.run {
                answerText = response.answer
                isAskingAI = false
            }
        } catch {
            await MainActor.run {
                aiError = error.localizedDescription
                isAskingAI = false
            }
        }
    }
}

#Preview {
    UnknownQuestionsView(appModel: AppModel())
        .frame(width: 600, height: 500)
}
