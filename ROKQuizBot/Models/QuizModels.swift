// QuizModels.swift
// Data models for questions and answers
// Made by mpcode

import Foundation

// MARK: - Question Answer Pair
struct QuestionAnswer: Codable, Identifiable, Hashable {
    var id: String { text }
    let text: String
    let answer: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }

    static func == (lhs: QuestionAnswer, rhs: QuestionAnswer) -> Bool {
        lhs.text == rhs.text
    }
}

// MARK: - Unknown Question (needs user to select correct answer)
struct UnknownQuestion: Codable, Identifiable, Hashable {
    let id: UUID
    let questionText: String
    let detectedOptions: [String]
    let timestamp: Date
    var selectedAnswer: String?

    init(questionText: String, detectedOptions: [String] = []) {
        self.id = UUID()
        self.questionText = questionText
        self.detectedOptions = detectedOptions
        self.timestamp = Date()
        self.selectedAnswer = nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: UnknownQuestion, rhs: UnknownQuestion) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - OCR Result
struct OCRResult {
    let fullText: String
    let textBlocks: [TextBlock]

    struct TextBlock {
        let text: String
        let boundingBox: CGRect // Normalised coordinates (0-1)
    }
}

// MARK: - Match Result
struct MatchResult {
    let question: QuestionAnswer
    let confidence: Double
    let matchedText: String
}

// MARK: - Answer Location
struct AnswerLocation {
    let answerText: String
    let screenRect: CGRect
    let clickPoint: CGPoint
}

// MARK: - App Status
enum AppStatus: Equatable {
    case idle
    case selectingArea
    case running
    case paused
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .selectingArea:
            return "Select capture area..."
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
