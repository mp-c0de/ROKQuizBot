// UnknownQuestionsView.swift
// View for managing unknown questions that need answers
// Made by mpcode

import SwiftUI

struct UnknownQuestionsView: View {
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestion: UnknownQuestion?
    @State private var answerText: String = ""
    @State private var editedQuestionText: String = ""  // Editable question text
    @State private var isAskingAI = false
    @State private var aiError: String?

    var body: some View {
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
                // Side by side layout: list on left, answer panel on right
                HSplitView {
                    // Question list on left
                    List(appModel.getUnknownQuestions(), selection: $selectedQuestion) { question in
                        let parsed = ParsedQuizQuestion.parse(from: question.questionText)
                        let hasDirectOptions = !question.detectedOptions.isEmpty
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(parsed.cleanQuestion)
                                    .font(.headline)
                                    .lineLimit(3)

                                if hasDirectOptions {
                                    Text("\(question.detectedOptions.count) options detected")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else if parsed.isValid {
                                    Text("4 options detected")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text(parsed.parsingError ?? "Parsing issue")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            if !hasDirectOptions && !parsed.isValid {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(question)
                    }
                    .frame(minWidth: 280, idealWidth: 320)

                    // Answer panel on right
                    if let question = selectedQuestion {
                        ScrollView {
                            answerPanelView(for: question)
                        }
                        .frame(minWidth: 400)
                    } else {
                        VStack {
                            Spacer()
                            Text("Select a question to answer")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(minWidth: 400)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func answerPanelView(for question: UnknownQuestion) -> some View {
        let parsed = ParsedQuizQuestion.parse(from: question.questionText)
        let hasDirectOptions = !question.detectedOptions.isEmpty

        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Question")
                .font(.headline)

            // Editable question text
            TextField("Question text...", text: $editedQuestionText, axis: .vertical)
                .font(.body)
                .textFieldStyle(.plain)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .lineLimit(3...6)
                .onAppear {
                    // Initialize with parsed clean question
                    if editedQuestionText.isEmpty {
                        editedQuestionText = parsed.cleanQuestion
                    }
                }

            // Show parsing error only if no direct options available
            if !hasDirectOptions, let error = parsed.parsingError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.orange)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)

                // Show raw OCR text for debugging
                DisclosureGroup("Raw OCR Text (for debugging)") {
                    Text(parsed.rawText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }

            // Use direct options from layout OCR if available, otherwise use parsed options
            if hasDirectOptions {
                Text("Select the correct answer:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Display direct options from layout OCR
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(question.detectedOptions.enumerated()), id: \.offset) { index, optionText in
                        let letter = ["A", "B", "C", "D", "E", "F"][safe: index] ?? "\(index + 1)"
                        Button(action: {
                            answerText = optionText
                        }) {
                            HStack {
                                Text(letter)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(answerText == optionText ? Color.green : Color.gray)
                                    .clipShape(Circle())

                                Text(optionText)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)

                                Spacer()

                                if answerText == optionText {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(answerText == optionText ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !parsed.options.isEmpty {
                // Fallback to parsed options
                Text(parsed.isValid ? "Select the correct answer:" : "Partially parsed options (may be incorrect):")
                    .font(.subheadline)
                    .foregroundColor(parsed.isValid ? .secondary : .orange)

                // Use 2-column grid for options
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(parsed.options) { option in
                        Button(action: {
                            answerText = option.text
                        }) {
                            HStack {
                                Text(option.letter)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(answerText == option.text ? Color.green : Color.gray)
                                    .clipShape(Circle())

                                Text(option.text)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)

                                Spacer()

                                if answerText == option.text {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(answerText == option.text ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Manual answer entry
            HStack {
                TextField("Or enter answer manually...", text: $answerText)
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
                    appModel.deleteUnknownQuestion(question)
                    selectedQuestion = nil
                    answerText = ""
                }
                .foregroundColor(.red)

                Spacer()

                if !answerText.isEmpty {
                    Text("Will save: \(answerText)")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Spacer()

                Button("Save Answer") {
                    // Save with edited question text (user can fix OCR errors)
                    appModel.resolveUnknownQuestion(question, withCleanQuestion: editedQuestionText, answer: answerText)
                    selectedQuestion = nil
                    answerText = ""
                    editedQuestionText = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(answerText.isEmpty || editedQuestionText.isEmpty)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selectedQuestion) { _, newValue in
            // Reset edited text when selection changes
            if let newQuestion = newValue {
                let parsed = ParsedQuizQuestion.parse(from: newQuestion.questionText)
                editedQuestionText = parsed.cleanQuestion
            } else {
                editedQuestionText = ""
            }
            answerText = ""
        }
    }

    private func askAIForAnswer() async {
        guard let _ = selectedQuestion,
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

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    UnknownQuestionsView(appModel: AppModel())
        .frame(width: 900, height: 700)
}
