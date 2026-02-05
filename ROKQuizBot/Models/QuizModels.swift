// QuizModels.swift
// Data models for questions and answers
// Made by mpcode

import Foundation
import CoreGraphics

// MARK: - Question Answer Pair
struct QuestionAnswer: Codable, Identifiable, Hashable {
    var id: String { text }
    let text: String
    let answer: String

    /// All answers split by `|` separator, trimmed. For single answers this returns a one-element array.
    var allAnswers: [String] {
        answer.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The first (primary) answer, used for display purposes.
    var primaryAnswer: String {
        allAnswers.first ?? answer
    }

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

        // Remove stray option markers at the start (e.g., "A C" or "A B C D" before the question)
        // This happens when OCR reads option markers from a 2x2 grid before the question text
        let strayMarkersPattern = #"^(?:[A-D]\s+)+"#
        if let regex = try? NSRegularExpression(pattern: strayMarkersPattern, options: .caseInsensitive) {
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

        // Find ALL option markers (A, B, C, D) in the text, not just in strict sequence
        // This handles 2x2 grid layouts where OCR may read "A ... B ... C ... D ..."
        // Pattern: non-letter or start, followed by A/B/C/D, followed by space or non-letter
        var optionPositions: [(letter: String, globalMatchStart: Int, globalTextStart: Int)] = []

        let letters = ["A", "B", "C", "D"]

        for letter in letters {
            // Search for this letter anywhere in the options text
            // More flexible pattern: allows optional space after letter, handles various OCR outputs
            let patterns = [
                #"(?:^|[^a-zA-Z])("# + letter + #")[\s\u00A0]+"#,           // Standard: "A " or " A "
                #"(?:^|[^a-zA-Z])("# + letter + #")(?=[A-Z][a-z])"#,        // No space but followed by word: "ATropic"
                #"(?:^|\s)("# + letter + #")\s+"#,                           // Simple: whitespace + letter + whitespace
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: optionsText, options: [], range: NSRange(optionsText.startIndex..., in: optionsText)),
                   Range(match.range(at: 1), in: optionsText) != nil {

                    let localMatchStart = match.range.location
                    let localTextStart = match.range.location + match.range.length
                    let globalMatchStart = optionsStartOffset + localMatchStart
                    let globalTextStart = optionsStartOffset + localTextStart

                    // Only add if we haven't found this letter yet
                    if !optionPositions.contains(where: { $0.letter == letter }) {
                        optionPositions.append((letter: letter, globalMatchStart: globalMatchStart, globalTextStart: globalTextStart))
                    }
                    break // Found this letter, move to next
                }
            }
        }

        // Sort by position in text (important for correct text extraction)
        optionPositions.sort { $0.globalMatchStart < $1.globalMatchStart }

        // Extract options if we found any
        if !optionPositions.isEmpty {
            // Update cleanQuestion to be everything before first option
            let firstMatchStart = optionPositions[0].globalMatchStart
            cleanQuestion = String(text.prefix(firstMatchStart))

            // Extract each option text
            for (index, opt) in optionPositions.enumerated() {
                // Safety check: ensure offset is within bounds
                guard opt.globalTextStart <= text.count else { continue }
                let textStartIndex = text.index(text.startIndex, offsetBy: opt.globalTextStart)

                // Option text ends at the next option's match start, or end of string
                let textEndIndex: String.Index
                if index + 1 < optionPositions.count {
                    let nextMatchStart = optionPositions[index + 1].globalMatchStart
                    // Safety check: ensure we don't create an invalid range
                    if nextMatchStart <= opt.globalTextStart {
                        continue  // Skip this option if range would be invalid
                    }
                    textEndIndex = text.index(text.startIndex, offsetBy: min(nextMatchStart, text.count))
                } else {
                    textEndIndex = text.endIndex
                }

                // Final safety check before creating range
                guard textStartIndex <= textEndIndex else { continue }

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

        // FALLBACK 1: Handle 2x2 grid where OCR missed B and D markers
        // If we only found A and C, try to split their text to recover B and D
        if options.count == 2 {
            let foundLetters = options.map { $0.letter }
            if foundLetters == ["A", "C"] {
                var newOptions: [QuizOption] = []

                for opt in options {
                    let parts = splitIntoTwoParts(opt.text)
                    if parts.count == 2 {
                        if opt.letter == "A" {
                            newOptions.append(QuizOption(letter: "A", text: parts[0]))
                            newOptions.append(QuizOption(letter: "B", text: parts[1]))
                        } else if opt.letter == "C" {
                            newOptions.append(QuizOption(letter: "C", text: parts[0]))
                            newOptions.append(QuizOption(letter: "D", text: parts[1]))
                        }
                    } else {
                        // Couldn't split, keep original
                        newOptions.append(opt)
                    }
                }

                if newOptions.count == 4 {
                    options = newOptions
                }
            }
            // FALLBACK 2: Handle 2x2 grid where OCR missed A and C markers
            // If we only found B and D, infer A and C from the gaps
            // Text structure: "Question? [A's text] B [B+C text] D [D's text]"
            else if foundLetters == ["B", "D"] {
                var newOptions: [QuizOption] = []

                // Find where B starts in the original text (after question mark)
                if let qIndex = text.lastIndex(of: "?"),
                   let bOption = options.first(where: { $0.letter == "B" }),
                   let dOption = options.first(where: { $0.letter == "D" }) {

                    // Text after question mark, before B marker
                    let afterQuestion = String(text[text.index(after: qIndex)...])

                    // Find where B marker appears in afterQuestion
                    let bPattern = #"(?:^|[^a-zA-Z])B[\s\u00A0]+"#
                    if let bRegex = try? NSRegularExpression(pattern: bPattern, options: .caseInsensitive),
                       let bMatch = bRegex.firstMatch(in: afterQuestion, options: [], range: NSRange(afterQuestion.startIndex..., in: afterQuestion)) {

                        // Option A is the text before the B marker
                        let aTextEndIndex = afterQuestion.index(afterQuestion.startIndex, offsetBy: bMatch.range.location)
                        let aText = String(afterQuestion[..<aTextEndIndex]).trimmingCharacters(in: .whitespaces)

                        if !aText.isEmpty {
                            newOptions.append(QuizOption(letter: "A", text: aText))
                        }

                        // Try to split B's text to recover C
                        let bParts = splitIntoTwoParts(bOption.text)
                        if bParts.count == 2 {
                            newOptions.append(QuizOption(letter: "B", text: bParts[0]))
                            newOptions.append(QuizOption(letter: "C", text: bParts[1]))
                        } else {
                            newOptions.append(QuizOption(letter: "B", text: bOption.text))
                        }

                        newOptions.append(QuizOption(letter: "D", text: dOption.text))

                        if newOptions.count == 4 {
                            options = newOptions
                        }
                    }
                }
            }
        }

        // FALLBACK 3: Handle case where A is missing but B, C, D are found
        // A's text is likely between the question mark and the B marker (included in cleanQuestion)
        if options.count == 3 {
            let foundLetters = options.map { $0.letter }
            if !foundLetters.contains("A") && foundLetters.contains("B") {
                // A's text is at the end of cleanQuestion (after the "?")
                if let qIndex = cleanQuestion.lastIndex(of: "?") {
                    let afterQuestion = String(cleanQuestion[cleanQuestion.index(after: qIndex)...])
                        .trimmingCharacters(in: .whitespaces)

                    if !afterQuestion.isEmpty {
                        // Remove A's text from cleanQuestion
                        cleanQuestion = String(cleanQuestion[...qIndex])

                        // Add A as the first option
                        var newOptions = [QuizOption(letter: "A", text: afterQuestion)]
                        newOptions.append(contentsOf: options)
                        options = newOptions
                    }
                }
            }
            // FALLBACK 3b: Handle case where C is missing but A, B, D are found
            // C's text is likely combined with B's text
            else if !foundLetters.contains("C") && foundLetters.contains("A") && foundLetters.contains("B") && foundLetters.contains("D") {
                if let bIndex = options.firstIndex(where: { $0.letter == "B" }) {
                    let bOption = options[bIndex]
                    let bParts = splitIntoTwoParts(bOption.text)
                    if bParts.count == 2 {
                        // Replace B with split parts
                        var newOptions: [QuizOption] = []
                        for opt in options {
                            if opt.letter == "B" {
                                newOptions.append(QuizOption(letter: "B", text: bParts[0]))
                                newOptions.append(QuizOption(letter: "C", text: bParts[1]))
                            } else {
                                newOptions.append(opt)
                            }
                        }
                        options = newOptions
                    }
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

    /// Attempts to split a combined text into two parts (for 2x2 grid recovery)
    /// e.g., "Tropic of Cancer Tropic of Capricorn" -> ["Tropic of Cancer", "Tropic of Capricorn"]
    private static func splitIntoTwoParts(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let words = trimmed.split(separator: " ").map(String.init)

        guard words.count >= 2 else { return [] }

        // Strategy 1: Look for repeated starting word pattern
        // e.g., "Tropic of Cancer Tropic of Capricorn" - "Tropic" appears twice
        let firstWord = words[0]
        for i in 1..<words.count {
            if words[i] == firstWord {
                let part1 = words[0..<i].joined(separator: " ")
                let part2 = words[i...].joined(separator: " ")
                if !part1.isEmpty && !part2.isEmpty {
                    return [part1, part2]
                }
            }
        }

        // Strategy 2: Look for capital letter starting a new phrase mid-text
        // e.g., "Arctic Circle Equator" -> find where "Equator" starts (capital after lowercase)
        var splitIndex: Int? = nil
        for i in 1..<words.count {
            let prevWord = words[i - 1]
            let currWord = words[i]

            // Check if previous word ends with lowercase and current starts with uppercase
            // This suggests a new phrase/option starting
            if let lastChar = prevWord.last, lastChar.isLowercase,
               let firstChar = currWord.first, firstChar.isUppercase {
                // Prefer splits closer to the middle
                let distFromMiddle = abs(i - words.count / 2)
                if splitIndex == nil || distFromMiddle < abs(splitIndex! - words.count / 2) {
                    splitIndex = i
                }
            }
        }

        if let idx = splitIndex {
            let part1 = words[0..<idx].joined(separator: " ")
            let part2 = words[idx...].joined(separator: " ")
            if !part1.isEmpty && !part2.isEmpty {
                return [part1, part2]
            }
        }

        // Strategy 3: Simple middle split as last resort (if even number of words)
        if words.count >= 4 && words.count % 2 == 0 {
            let mid = words.count / 2
            let part1 = words[0..<mid].joined(separator: " ")
            let part2 = words[mid...].joined(separator: " ")
            return [part1, part2]
        }

        return [] // Couldn't split
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

// MARK: - Codable Rect Helper
struct CodableRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(cgRect: CGRect) {
        self.x = cgRect.origin.x
        self.y = cgRect.origin.y
        self.width = cgRect.width
        self.height = cgRect.height
    }
}

// MARK: - Zone Type
enum ZoneType: String, Codable, Equatable {
    case question
    case answer
}

// MARK: - Layout Zone
struct LayoutZone: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String           // "Question", "A", "B", "C", "D"
    var zoneType: ZoneType

    // Store CGRect as individual values for Codable
    var rectX: Double
    var rectY: Double
    var rectWidth: Double
    var rectHeight: Double

    /// Computed property for normalised rect (0-1 relative to capture area)
    var normalizedRect: CGRect {
        get { CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight) }
        set {
            rectX = newValue.origin.x
            rectY = newValue.origin.y
            rectWidth = newValue.width
            rectHeight = newValue.height
        }
    }

    init(id: UUID = UUID(), normalizedRect: CGRect, label: String, zoneType: ZoneType) {
        self.id = id
        self.rectX = normalizedRect.origin.x
        self.rectY = normalizedRect.origin.y
        self.rectWidth = normalizedRect.width
        self.rectHeight = normalizedRect.height
        self.label = label
        self.zoneType = zoneType
    }

    /// Returns the centre point of this zone in screen coordinates
    func clickPoint(in captureRect: CGRect) -> CGPoint {
        let centerX = captureRect.origin.x + (CGFloat(rectX + rectWidth / 2) * captureRect.width)
        let centerY = captureRect.origin.y + (CGFloat(rectY + rectHeight / 2) * captureRect.height)
        return CGPoint(x: centerX, y: centerY)
    }

    /// Returns the absolute rect in screen coordinates
    func absoluteRect(in captureRect: CGRect) -> CGRect {
        return CGRect(
            x: captureRect.origin.x + (CGFloat(rectX) * captureRect.width),
            y: captureRect.origin.y + (CGFloat(rectY) * captureRect.height),
            width: CGFloat(rectWidth) * captureRect.width,
            height: CGFloat(rectHeight) * captureRect.height
        )
    }
}

// MARK: - Quiz Layout Configuration
struct QuizLayoutConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var questionZone: LayoutZone?
    var answerZones: [LayoutZone]  // 2-4 answers
    var captureRect: CodableRect?  // The capture area for this layout
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String = "Default Layout", questionZone: LayoutZone? = nil, answerZones: [LayoutZone] = [], captureRect: CGRect? = nil) {
        self.id = id
        self.name = name
        self.questionZone = questionZone
        self.answerZones = answerZones
        self.captureRect = captureRect.map { CodableRect(cgRect: $0) }
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Creates a default layout with a question zone at the top and 4 answer zones in a 2x2 grid
    static func createDefault() -> QuizLayoutConfiguration {
        let questionZone = LayoutZone(
            normalizedRect: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.25),
            label: "Question",
            zoneType: .question
        )

        // 2x2 grid for answers in the lower portion
        let answerA = LayoutZone(
            normalizedRect: CGRect(x: 0.05, y: 0.35, width: 0.42, height: 0.28),
            label: "A",
            zoneType: .answer
        )
        let answerB = LayoutZone(
            normalizedRect: CGRect(x: 0.53, y: 0.35, width: 0.42, height: 0.28),
            label: "B",
            zoneType: .answer
        )
        let answerC = LayoutZone(
            normalizedRect: CGRect(x: 0.05, y: 0.67, width: 0.42, height: 0.28),
            label: "C",
            zoneType: .answer
        )
        let answerD = LayoutZone(
            normalizedRect: CGRect(x: 0.53, y: 0.67, width: 0.42, height: 0.28),
            label: "D",
            zoneType: .answer
        )

        return QuizLayoutConfiguration(
            name: "Default 2x2 Layout",
            questionZone: questionZone,
            answerZones: [answerA, answerB, answerC, answerD]
        )
    }

    /// Returns whether this layout is valid for use (has question zone and at least 2 answers)
    var isValid: Bool {
        return questionZone != nil && answerZones.count >= 2
    }
}

// MARK: - OCR Settings
struct OCRSettings: Codable, Equatable {
    /// Contrast multiplier (1.0 = no change, 2.0 = double contrast)
    var contrast: Double = 2.0

    /// Brightness adjustment (-1.0 to 1.0, 0.0 = no change)
    var brightness: Double = 0.1

    /// Whether to convert to grayscale before OCR
    var grayscaleEnabled: Bool = true

    /// Whether to apply sharpening (can help with blurry text)
    var sharpeningEnabled: Bool = true

    /// Sharpness intensity (0.0 to 2.0)
    var sharpnessIntensity: Double = 0.5

    /// Scale factor for small regions (1.0 = no scaling, 2.0 = double size)
    /// Upscaling small regions can improve OCR accuracy
    var scaleFactor: Double = 2.0

    /// Minimum region size (in pixels) below which scaling is applied
    var minRegionSize: Int = 100

    /// Whether to apply binarization (convert to pure black/white)
    var binarizationEnabled: Bool = false

    /// Binarization threshold (0.0 to 1.0, pixels above = white, below = black)
    var binarizationThreshold: Double = 0.5

    /// Whether to invert colors (useful for light text on dark backgrounds)
    var invertColors: Bool = false

    static var `default`: OCRSettings { OCRSettings() }
}

// MARK: - OCR Presets
enum OCRPreset: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case gameText = "Game Text (High Contrast)"
    case lightOnDark = "Light on Dark"

    var id: String { rawValue }
}

extension OCRSettings {
    /// Preset for game text with low contrast
    static var gameText: OCRSettings {
        var settings = OCRSettings()
        settings.contrast = 2.5
        settings.brightness = 0.15
        settings.sharpeningEnabled = true
        settings.sharpnessIntensity = 0.7
        settings.scaleFactor = 2.5
        return settings
    }

    /// Preset for light text on dark backgrounds
    static var lightOnDark: OCRSettings {
        var settings = OCRSettings()
        settings.contrast = 2.0
        settings.invertColors = true
        settings.binarizationEnabled = true
        settings.binarizationThreshold = 0.4
        return settings
    }
}

// MARK: - Capture Quality
enum CaptureQuality: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case best = "Best (Retina)"

    var id: String { rawValue }

    /// Scale factor for capture resolution
    var scale: CGFloat {
        switch self {
        case .low: return 0.5      // Half resolution - faster
        case .medium: return 1.0   // Standard resolution
        case .best: return 2.0     // Native Retina - best quality for OCR
        }
    }

    var description: String {
        switch self {
        case .low: return "Faster capture, lower OCR accuracy"
        case .medium: return "Balanced speed and quality"
        case .best: return "Best OCR accuracy, recommended"
        }
    }
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
