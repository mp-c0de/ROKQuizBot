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

// MARK: - Parsed Quiz Question
struct ParsedQuizQuestion {
    let cleanQuestion: String
    let options: [QuizOption]
    let rawText: String
    let parsingError: String?  // nil if parsing succeeded, error message if failed

    var isValid: Bool {
        return options.count == 4 && parsingError == nil
    }

    struct QuizOption: Identifiable {
        let id = UUID()
        let letter: String  // A, B, C, D
        let text: String    // The option text
    }

    /// Parses raw OCR text to extract clean question and options
    /// Smart algorithm: finds question mark, then looks for A, B, C, D sequence AFTER it
    static func parse(from rawText: String) -> ParsedQuizQuestion {
        var text = rawText

        // Remove question number prefix (Q1, Q2, Q3, etc.)
        let questionNumberPattern = #"^Q\d+\s*"#
        if let regex = try? NSRegularExpression(pattern: questionNumberPattern, options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // Remove "X chose this" patterns (e.g., "15 chose this", "1 chose this")
        let choseThisPattern = #"\d+\s*chose\s*this"#
        if let regex = try? NSRegularExpression(pattern: choseThisPattern, options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // Normalize whitespace (replace multiple spaces, newlines, tabs with single space)
        text = text.replacingOccurrences(of: #"[\s\n\r\t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        var options: [QuizOption] = []
        var cleanQuestion = text

        // Find the question mark - options come AFTER the question
        let questionMarkIndex = text.lastIndex(of: "?")
        let searchStartIndex: String.Index

        if let qIndex = questionMarkIndex {
            // Search for options only after the question mark
            searchStartIndex = text.index(after: qIndex)
            cleanQuestion = String(text[..<text.index(after: qIndex)])
        } else {
            // No question mark - search entire text but be more careful
            searchStartIndex = text.startIndex
        }

        // Get the substring after the question mark to search for options
        let optionsText = String(text[searchStartIndex...])
        let optionsStartOffset = text.distance(from: text.startIndex, to: searchStartIndex)

        // Find option markers in sequence: must find A, then B, then C, then D in order
        // Pattern: non-letter followed by A/B/C/D followed by space
        var optionPositions: [(letter: String, globalMatchStart: Int, globalTextStart: Int)] = []

        let letters = ["A", "B", "C", "D"]
        var lastFoundPosition = 0

        for letter in letters {
            // Search for this letter after the last found position
            let searchSubstring = String(optionsText.dropFirst(lastFoundPosition))
            let pattern = #"(?:^|[^a-zA-Z])("# + letter + #")[\s\u00A0]+"#

            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: searchSubstring, options: [], range: NSRange(searchSubstring.startIndex..., in: searchSubstring)),
               Range(match.range(at: 1), in: searchSubstring) != nil {

                let localMatchStart = match.range.location + lastFoundPosition
                let localTextStart = match.range.location + match.range.length + lastFoundPosition
                let globalMatchStart = optionsStartOffset + localMatchStart
                let globalTextStart = optionsStartOffset + localTextStart

                optionPositions.append((letter: letter, globalMatchStart: globalMatchStart, globalTextStart: globalTextStart))
                lastFoundPosition = localTextStart
            }
        }

        // Extract options if we found any
        if !optionPositions.isEmpty {
            // Update cleanQuestion to be everything before first option
            let firstMatchStart = optionPositions[0].globalMatchStart
            cleanQuestion = String(text.prefix(firstMatchStart))

            // Extract each option text
            for (index, opt) in optionPositions.enumerated() {
                let textStartIndex = text.index(text.startIndex, offsetBy: opt.globalTextStart)

                // Option text ends at the next option's match start, or end of string
                let textEndIndex: String.Index
                if index + 1 < optionPositions.count {
                    textEndIndex = text.index(text.startIndex, offsetBy: optionPositions[index + 1].globalMatchStart)
                } else {
                    textEndIndex = text.endIndex
                }

                var optionText = String(text[textStartIndex..<textEndIndex])
                    .trimmingCharacters(in: .whitespaces)

                // Clean up option text - remove trailing numbers
                optionText = optionText.replacingOccurrences(of: #"\s*\d+\s*$"#, with: "", options: .regularExpression)
                optionText = optionText.trimmingCharacters(in: .whitespaces)

                if !optionText.isEmpty {
                    options.append(QuizOption(letter: opt.letter, text: optionText))
                }
            }
        }

        // Clean up the question
        cleanQuestion = cleanQuestion
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        // Validate: must have exactly 4 options (A, B, C, D)
        var parsingError: String? = nil
        if options.count == 0 {
            parsingError = "No options found. OCR may have failed to read the answers."
        } else if options.count < 4 {
            let foundLetters = options.map { $0.letter }.joined(separator: ", ")
            let missingLetters = ["A", "B", "C", "D"].filter { letter in !options.contains { $0.letter == letter } }.joined(separator: ", ")
            parsingError = "Only \(options.count) options found (\(foundLetters)). Missing: \(missingLetters). Check OCR text below."
        }

        return ParsedQuizQuestion(cleanQuestion: cleanQuestion, options: options, rawText: rawText, parsingError: parsingError)
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
