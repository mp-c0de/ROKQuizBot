// QuestionDatabaseService.swift
// Service for managing the question/answer database with fast O(1) lookup
// Made by mpcode

import Foundation

final class QuestionDatabaseService {
    // MARK: - Properties

    /// User-added questions (stored in JSON, separate from built-in)
    private var userQuestions: [String: String] = [:]  // normalized question -> answer

    /// Unknown questions pending answers
    private(set) var unknownQuestions: [UnknownQuestion] = []

    private let userQuestionsFileURL: URL
    private let unknownQuestionsFileURL: URL

    /// Total question count (built-in + user-added)
    var totalQuestionCount: Int {
        return BuiltInQuestions.count + userQuestions.count
    }

    // MARK: - Init
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent("ROKQuizBot", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        userQuestionsFileURL = appFolder.appendingPathComponent("user_questions.json")
        unknownQuestionsFileURL = appFolder.appendingPathComponent("unknown_questions.json")

        loadUserQuestions()
        loadUnknownQuestions()

        print("[QuestionDB] Loaded \(BuiltInQuestions.count) built-in + \(userQuestions.count) user questions = \(totalQuestionCount) total")
    }

    // MARK: - Load/Save User Questions
    private func loadUserQuestions() {
        guard FileManager.default.fileExists(atPath: userQuestionsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: userQuestionsFileURL)
            userQuestions = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("[QuestionDB] Error loading user questions: \(error)")
        }
    }

    private func saveUserQuestions() {
        do {
            let data = try JSONEncoder().encode(userQuestions)
            try data.write(to: userQuestionsFileURL)
        } catch {
            print("[QuestionDB] Error saving user questions: \(error)")
        }
    }

    private func loadUnknownQuestions() {
        guard FileManager.default.fileExists(atPath: unknownQuestionsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: unknownQuestionsFileURL)
            unknownQuestions = try JSONDecoder().decode([UnknownQuestion].self, from: data)
        } catch {
            print("[QuestionDB] Error loading unknown questions: \(error)")
        }
    }

    private func saveUnknownQuestions() {
        do {
            let data = try JSONEncoder().encode(unknownQuestions)
            try data.write(to: unknownQuestionsFileURL)
        } catch {
            print("[QuestionDB] Error saving unknown questions: \(error)")
        }
    }

    // MARK: - Fast Lookup (O(1) for exact match)

    /// Primary lookup method - tries fast exact match first, then fuzzy matching
    func findBestMatch(for text: String) -> MatchResult? {
        // Simple text cleaning - no complex parsing needed with zone-based OCR
        let cleanQuestion = simpleCleanQuestion(text)
        let normalized = cleanQuestion.lowercased().trimmingCharacters(in: .whitespaces)

        // Skip if too short
        guard normalized.count > 10 else { return nil }

        // 1. FAST PATH: O(1) exact match in built-in questions
        if let answer = BuiltInQuestions.getAnswer(for: normalized) {
            return MatchResult(
                question: QuestionAnswer(text: cleanQuestion, answer: answer),
                confidence: 1.0,
                matchedText: cleanQuestion
            )
        }

        // 2. FAST PATH: O(1) exact match in user questions
        if let answer = userQuestions[normalized] {
            return MatchResult(
                question: QuestionAnswer(text: cleanQuestion, answer: answer),
                confidence: 1.0,
                matchedText: cleanQuestion
            )
        }

        // 3. FAST PATH: Check if OCR text contains a known question (substring match)
        if let result = findSubstringMatch(in: normalized) {
            return result
        }

        // 4. SLOW PATH: Fuzzy matching (only if exact match fails)
        return findFuzzyMatch(for: normalized, originalQuestion: cleanQuestion)
    }

    /// Fast substring matching - checks if the OCR text contains any known question
    private func findSubstringMatch(in normalizedText: String) -> MatchResult? {
        // Check built-in questions
        for (question, answer) in BuiltInQuestions.dictionary {
            if normalizedText.contains(question) || question.contains(normalizedText) {
                return MatchResult(
                    question: QuestionAnswer(text: question, answer: answer),
                    confidence: 0.95,
                    matchedText: question
                )
            }
        }

        // Check user questions
        for (question, answer) in userQuestions {
            if normalizedText.contains(question) || question.contains(normalizedText) {
                return MatchResult(
                    question: QuestionAnswer(text: question, answer: answer),
                    confidence: 0.95,
                    matchedText: question
                )
            }
        }

        return nil
    }

    /// Fuzzy matching fallback using Levenshtein distance
    private func findFuzzyMatch(for normalized: String, originalQuestion: String) -> MatchResult? {
        var bestMatch: (question: String, answer: String, confidence: Double)?

        // Check built-in questions
        for (question, answer) in BuiltInQuestions.dictionary {
            let similarity = stringSimilarity(question, normalized)
            if similarity > 0.75 {
                if bestMatch == nil || similarity > bestMatch!.confidence {
                    bestMatch = (question, answer, similarity)
                }
            }
        }

        // Check user questions
        for (question, answer) in userQuestions {
            let similarity = stringSimilarity(question, normalized)
            if similarity > 0.75 {
                if bestMatch == nil || similarity > bestMatch!.confidence {
                    bestMatch = (question, answer, similarity)
                }
            }
        }

        guard let match = bestMatch, match.confidence >= 0.65 else {
            return nil
        }

        return MatchResult(
            question: QuestionAnswer(text: match.question, answer: match.answer),
            confidence: match.confidence,
            matchedText: match.question
        )
    }

    /// Simple question text cleaning - removes Q prefix and normalizes whitespace.
    /// Used instead of complex ParsedQuizQuestion parsing since we now have zone-based OCR.
    private func simpleCleanQuestion(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading Q followed by number (e.g., "Q4 Which..." -> "Which...")
        if let range = cleaned.range(of: #"^Q\d+\s*"#, options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...])
        }

        // Normalize whitespace (replace multiple spaces with single space)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Add Question (user-added only)

    func addQuestion(_ question: QuestionAnswer) {
        let normalized = question.text.lowercased().trimmingCharacters(in: .whitespaces)

        // Don't add if already exists in built-in or user questions
        if BuiltInQuestions.contains(normalized) { return }
        if userQuestions[normalized] != nil { return }

        userQuestions[normalized] = question.answer
        saveUserQuestions()
        print("[QuestionDB] Added user question: \(question.text.prefix(50))...")
    }

    // MARK: - Unknown Questions

    func addUnknownQuestion(questionText: String, options: [String] = []) {
        let normalized = questionText.lowercased().trimmingCharacters(in: .whitespaces)

        // Don't add if already known
        if BuiltInQuestions.contains(normalized) { return }
        if userQuestions[normalized] != nil { return }

        // Don't add if already in unknown list (use similarity check for OCR variations)
        if unknownQuestions.contains(where: { stringSimilarity($0.questionText.lowercased(), normalized) > 0.8 }) {
            return
        }

        let unknown = UnknownQuestion(questionText: questionText, detectedOptions: options)
        unknownQuestions.append(unknown)
        saveUnknownQuestions()
    }

    func resolveUnknownQuestion(_ unknown: UnknownQuestion, with answer: String) {
        let newQuestion = QuestionAnswer(text: unknown.questionText, answer: answer)
        addQuestion(newQuestion)
        unknownQuestions.removeAll { $0.id == unknown.id }
        saveUnknownQuestions()
    }

    func resolveUnknownQuestionWithCleanText(_ unknown: UnknownQuestion, cleanQuestion: String, answer: String) {
        let newQuestion = QuestionAnswer(text: cleanQuestion, answer: answer)
        addQuestion(newQuestion)
        unknownQuestions.removeAll { $0.id == unknown.id }
        saveUnknownQuestions()
    }

    func deleteUnknownQuestion(_ unknown: UnknownQuestion) {
        unknownQuestions.removeAll { $0.id == unknown.id }
        saveUnknownQuestions()
    }

    // MARK: - For UI (get all questions for display)

    func getAllQuestions() -> [QuestionAnswer] {
        var all: [QuestionAnswer] = []

        // Add built-in questions
        for (question, answer) in BuiltInQuestions.dictionary {
            all.append(QuestionAnswer(text: question, answer: answer))
        }

        // Add user questions
        for (question, answer) in userQuestions {
            all.append(QuestionAnswer(text: question, answer: answer))
        }

        return all.sorted { $0.text < $1.text }
    }

    /// Get only user-added questions (editable)
    func getUserQuestions() -> [QuestionAnswer] {
        return userQuestions.map { QuestionAnswer(text: $0.key, answer: $0.value) }
            .sorted { $0.text < $1.text }
    }

    /// Get user questions count
    var userQuestionCount: Int {
        return userQuestions.count
    }

    // MARK: - Edit/Delete User Questions

    /// Update an existing user question
    func updateUserQuestion(oldText: String, newText: String, newAnswer: String) {
        let oldNormalized = oldText.lowercased().trimmingCharacters(in: .whitespaces)
        let newNormalized = newText.lowercased().trimmingCharacters(in: .whitespaces)

        // Remove old entry
        userQuestions.removeValue(forKey: oldNormalized)

        // Add updated entry (if not already in built-in)
        if !BuiltInQuestions.contains(newNormalized) {
            userQuestions[newNormalized] = newAnswer
        }

        saveUserQuestions()
        print("[QuestionDB] Updated user question: \(newText.prefix(50))...")
    }

    /// Delete a user question
    func deleteUserQuestion(text: String) {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespaces)
        userQuestions.removeValue(forKey: normalized)
        saveUserQuestions()
        print("[QuestionDB] Deleted user question: \(text.prefix(50))...")
    }

    /// Check if a question is user-added (editable)
    func isUserQuestion(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespaces)
        return userQuestions[normalized] != nil
    }

    // MARK: - Helpers

    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let len1 = s1.count
        let len2 = s2.count

        if len1 == 0 && len2 == 0 { return 1.0 }
        if len1 == 0 || len2 == 0 { return 0.0 }

        // Quick check for containment
        if len1 > len2 * 2 {
            if s1.contains(s2) { return 0.85 }
        } else if len2 > len1 * 2 {
            if s2.contains(s1) { return 0.85 }
        }

        // Levenshtein distance
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
