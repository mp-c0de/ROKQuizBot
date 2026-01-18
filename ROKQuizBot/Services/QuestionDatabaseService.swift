// QuestionDatabaseService.swift
// Service for managing the question/answer database
// Made by mpcode

import Foundation

final class QuestionDatabaseService {
    // MARK: - Properties
    private(set) var questions: [QuestionAnswer] = []
    private(set) var unknownQuestions: [UnknownQuestion] = []

    private let questionsFileURL: URL
    private let unknownQuestionsFileURL: URL

    // MARK: - Init
    init() {
        // Get documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent("ROKQuizBot", isDirectory: true)

        // Create app folder if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        questionsFileURL = appFolder.appendingPathComponent("questions.json")
        unknownQuestionsFileURL = appFolder.appendingPathComponent("unknown_questions.json")

        loadQuestions()
        loadUnknownQuestions()
    }

    // MARK: - Load Questions
    private func loadQuestions() {
        // First try to load from documents directory
        if FileManager.default.fileExists(atPath: questionsFileURL.path) {
            do {
                let data = try Data(contentsOf: questionsFileURL)
                questions = try JSONDecoder().decode([QuestionAnswer].self, from: data)
                print("Loaded \(questions.count) questions from documents")
                return
            } catch {
                print("Error loading questions from documents: \(error)")
            }
        }

        // Fall back to bundle
        if let bundlePath = Bundle.main.path(forResource: "questions", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: bundlePath))
                questions = try JSONDecoder().decode([QuestionAnswer].self, from: data)
                print("Loaded \(questions.count) questions from bundle")
                // Copy to documents for future updates
                saveQuestions()
                return
            } catch {
                print("Error loading questions from bundle: \(error)")
            }
        }

        print("No questions file found")
    }

    private func loadUnknownQuestions() {
        guard FileManager.default.fileExists(atPath: unknownQuestionsFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: unknownQuestionsFileURL)
            unknownQuestions = try JSONDecoder().decode([UnknownQuestion].self, from: data)
        } catch {
            print("Error loading unknown questions: \(error)")
        }
    }

    // MARK: - Save
    func saveQuestions() {
        do {
            let data = try JSONEncoder().encode(questions)
            try data.write(to: questionsFileURL)
        } catch {
            print("Error saving questions: \(error)")
        }
    }

    private func saveUnknownQuestions() {
        do {
            let data = try JSONEncoder().encode(unknownQuestions)
            try data.write(to: unknownQuestionsFileURL)
        } catch {
            print("Error saving unknown questions: \(error)")
        }
    }

    // MARK: - Find Best Match
    func findBestMatch(for text: String) -> MatchResult? {
        let textLower = text.lowercased()
        var bestMatch: (question: QuestionAnswer, confidence: Double, matchedText: String)?

        for question in questions {
            let questionLower = question.text.lowercased()

            // Check if the OCR text contains this question
            if textLower.contains(questionLower) {
                let confidence = 1.0
                if bestMatch == nil || confidence > bestMatch!.confidence {
                    bestMatch = (question, confidence, question.text)
                }
                continue
            }

            // Check fuzzy match
            let similarity = stringSimilarity(questionLower, textLower)
            if similarity > 0.7 {
                if bestMatch == nil || similarity > bestMatch!.confidence {
                    bestMatch = (question, similarity, question.text)
                }
                continue
            }

            // Check if question keywords are present
            let keywords = extractKeywords(from: questionLower)
            let matchedKeywords = keywords.filter { textLower.contains($0) }
            if matchedKeywords.count > keywords.count / 2 {
                let keywordConfidence = Double(matchedKeywords.count) / Double(keywords.count) * 0.8
                if bestMatch == nil || keywordConfidence > bestMatch!.confidence {
                    bestMatch = (question, keywordConfidence, question.text)
                }
            }
        }

        guard let match = bestMatch, match.confidence >= 0.6 else {
            return nil
        }

        return MatchResult(
            question: match.question,
            confidence: match.confidence,
            matchedText: match.matchedText
        )
    }

    // MARK: - Add Question
    func addQuestion(_ question: QuestionAnswer) {
        // Check for duplicates
        if !questions.contains(where: { $0.text.lowercased() == question.text.lowercased() }) {
            questions.append(question)
            saveQuestions()
        }
    }

    // MARK: - Unknown Questions
    func addUnknownQuestion(questionText: String, options: [String] = []) {
        // Don't add if already unknown or if we have an answer
        let textLower = questionText.lowercased()

        if unknownQuestions.contains(where: { stringSimilarity($0.questionText.lowercased(), textLower) > 0.8 }) {
            return
        }

        if questions.contains(where: { stringSimilarity($0.text.lowercased(), textLower) > 0.8 }) {
            return
        }

        let unknown = UnknownQuestion(questionText: questionText, detectedOptions: options)
        unknownQuestions.append(unknown)
        saveUnknownQuestions()
    }

    func resolveUnknownQuestion(_ unknown: UnknownQuestion, with answer: String) {
        // Add to main database
        let newQuestion = QuestionAnswer(text: unknown.questionText, answer: answer)
        addQuestion(newQuestion)

        // Remove from unknown
        unknownQuestions.removeAll { $0.id == unknown.id }
        saveUnknownQuestions()
    }

    func deleteUnknownQuestion(_ unknown: UnknownQuestion) {
        unknownQuestions.removeAll { $0.id == unknown.id }
        saveUnknownQuestions()
    }

    // MARK: - Helpers
    private func extractKeywords(from text: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "of", "in", "to", "for", "on", "with", "at", "by", "from", "which", "what", "who", "how", "when", "where", "that", "this", "it"])

        return text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let len1 = s1.count
        let len2 = s2.count

        if len1 == 0 && len2 == 0 { return 1.0 }
        if len1 == 0 || len2 == 0 { return 0.0 }

        // For very different lengths, check if one contains the other
        if len1 > len2 * 2 {
            if s1.contains(s2) { return 0.85 }
        } else if len2 > len1 * 2 {
            if s2.contains(s1) { return 0.85 }
        }

        let s1Array = Array(s1)
        let s2Array = Array(s2)

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: len2 + 1), count: len1 + 1)

        for i in 0...len1 { matrix[i][0] = i }
        for j in 0...len2 { matrix[0][j] = j }

        for i in 1...len1 {
            for j in 1...len2 {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        let distance = Double(matrix[len1][len2])
        let maxLen = Double(max(len1, len2))
        return 1.0 - (distance / maxLen)
    }
}
