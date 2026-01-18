// QuestionDatabaseView.swift
// View for browsing and managing the question database
// Made by mpcode

import SwiftUI

struct QuestionDatabaseView: View {
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var showingAddQuestion = false
    @State private var newQuestionText: String = ""
    @State private var newAnswerText: String = ""

    var filteredQuestions: [QuestionAnswer] {
        let questions = appModel.getAllQuestions()
        if searchText.isEmpty {
            return questions
        }
        return questions.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) ||
            $0.answer.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Question Database")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: { showingAddQuestion = true }) {
                        Label("Add Question", systemImage: "plus")
                    }

                    Button("Done") {
                        dismiss()
                    }
                }
                .padding()

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search questions...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom)

                Divider()

                // Question list
                if filteredQuestions.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Questions" : "No Results",
                        systemImage: searchText.isEmpty ? "list.bullet.rectangle" : "magnifyingglass",
                        description: Text(searchText.isEmpty ?
                            "The question database is empty." :
                            "No questions match your search.")
                    )
                } else {
                    List(filteredQuestions) { question in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.text)
                                .font(.headline)

                            HStack {
                                Text("Answer:")
                                    .foregroundColor(.secondary)
                                Text(question.answer)
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Stats
                HStack {
                    Text("\(filteredQuestions.count) of \(appModel.getAllQuestions().count) questions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingAddQuestion) {
            addQuestionSheet
        }
    }

    private var addQuestionSheet: some View {
        VStack(spacing: 20) {
            Text("Add New Question")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.headline)
                TextEditor(text: $newQuestionText)
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3), width: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Answer")
                    .font(.headline)
                TextField("Enter the correct answer...", text: $newAnswerText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    newQuestionText = ""
                    newAnswerText = ""
                    showingAddQuestion = false
                }

                Spacer()

                Button("Add Question") {
                    if !newQuestionText.isEmpty && !newAnswerText.isEmpty {
                        appModel.addQuestionManually(
                            question: newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines),
                            answer: newAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        newQuestionText = ""
                        newAnswerText = ""
                        showingAddQuestion = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newQuestionText.isEmpty || newAnswerText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
    }
}

#Preview {
    QuestionDatabaseView(appModel: AppModel())
        .frame(width: 700, height: 500)
}
