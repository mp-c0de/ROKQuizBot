// QuestionDatabaseView.swift
// View for browsing and managing the question database
// Made by mpcode

import SwiftUI
import UniformTypeIdentifiers

struct QuestionDatabaseView: View {
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var showingAddQuestion = false
    @State private var newQuestionText: String = ""
    @State private var newAnswerText: String = ""
    @State private var selectedTab: DatabaseTab = .all
    @State private var editingQuestion: QuestionAnswer?
    @State private var editQuestionText: String = ""
    @State private var editAnswerText: String = ""
    @State private var showingImportDialog = false
    @State private var importResult: String = ""
    @State private var showingImportResult = false

    enum DatabaseTab: String, CaseIterable {
        case all = "All Questions"
        case userOnly = "User Added"
    }

    var filteredQuestions: [QuestionAnswer] {
        let questions: [QuestionAnswer]
        switch selectedTab {
        case .all:
            questions = appModel.getAllQuestions()
        case .userOnly:
            questions = appModel.getUserQuestions()
        }

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

                    Button(action: { showingImportDialog = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }

                    Button(action: { showingAddQuestion = true }) {
                        Label("Add", systemImage: "plus")
                    }

                    Button("Done") {
                        dismiss()
                    }
                }
                .padding()

                // Tabs
                Picker("View", selection: $selectedTab) {
                    ForEach(DatabaseTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

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
                            (selectedTab == .userOnly ? "No user-added questions yet." : "The question database is empty.") :
                            "No questions match your search.")
                    )
                } else {
                    List(filteredQuestions) { question in
                        HStack {
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

                            Spacer()

                            // Edit/Delete buttons for user questions only
                            if appModel.isUserQuestion(question.text) {
                                Button(action: {
                                    editQuestionText = question.text
                                    editAnswerText = question.answer
                                    editingQuestion = question
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    appModel.deleteUserQuestion(text: question.text)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Stats
                HStack {
                    if selectedTab == .userOnly {
                        Text("\(filteredQuestions.count) of \(appModel.userQuestionCount) user questions")
                    } else {
                        Text("\(filteredQuestions.count) of \(appModel.getAllQuestions().count) questions (\(appModel.userQuestionCount) user-added)")
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
            }
        }
        .sheet(isPresented: $showingAddQuestion) {
            addQuestionSheet
        }
        .sheet(item: $editingQuestion) { question in
            editQuestionSheet(original: question)
        }
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert("Import Result", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importResult)
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

    private func editQuestionSheet(original: QuestionAnswer) -> some View {
        VStack(spacing: 20) {
            Text("Edit Question")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.headline)
                TextEditor(text: $editQuestionText)
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3), width: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Answer")
                    .font(.headline)
                TextField("Enter the correct answer...", text: $editAnswerText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    editingQuestion = nil
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    appModel.deleteUserQuestion(text: original.text)
                    editingQuestion = nil
                }
                .foregroundColor(.red)

                Button("Save Changes") {
                    if !editQuestionText.isEmpty && !editAnswerText.isEmpty {
                        appModel.updateUserQuestion(
                            oldText: original.text,
                            newText: editQuestionText.trimmingCharacters(in: .whitespacesAndNewlines),
                            newAnswer: editAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        editingQuestion = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(editQuestionText.isEmpty || editAnswerText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importResult = "No file selected."
                showingImportResult = true
                return
            }

            do {
                // Start accessing the security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    importResult = "Could not access the selected file."
                    showingImportResult = true
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url)

                // Try to parse as dictionary format [question: answer]
                if let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                    var imported = 0
                    for (question, answer) in dict {
                        appModel.addQuestionManually(question: question, answer: answer)
                        imported += 1
                    }
                    importResult = "Successfully imported \(imported) questions."
                }
                // Try to parse as array of objects [{question: "", answer: ""}]
                else if let array = try? JSONDecoder().decode([[String: String]].self, from: data) {
                    var imported = 0
                    for item in array {
                        if let question = item["question"] ?? item["text"],
                           let answer = item["answer"] {
                            appModel.addQuestionManually(question: question, answer: answer)
                            imported += 1
                        }
                    }
                    importResult = "Successfully imported \(imported) questions."
                } else {
                    importResult = "Invalid JSON format. Expected either:\n- {\"question\": \"answer\", ...}\n- [{\"question\": \"...\", \"answer\": \"...\"}]"
                }
                showingImportResult = true
            } catch {
                importResult = "Error reading file: \(error.localizedDescription)"
                showingImportResult = true
            }

        case .failure(let error):
            importResult = "Error: \(error.localizedDescription)"
            showingImportResult = true
        }
    }
}

#Preview {
    QuestionDatabaseView(appModel: AppModel.shared)
        .frame(width: 700, height: 500)
}
