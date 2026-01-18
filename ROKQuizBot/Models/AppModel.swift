// AppModel.swift
// Main application state model
// Made by mpcode

import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
@Observable
final class AppModel {
    // MARK: - Published State
    var status: AppStatus = .idle
    var selectedCaptureRect: CGRect? = nil
    var lastCapture: NSImage? = nil
    var lastOCRText: String = ""
    var lastMatchedQuestion: QuestionAnswer? = nil
    var lastClickedAnswer: String? = nil
    var questionsLoaded: Int = 0
    var answeredCount: Int = 0
    var unknownCount: Int = 0

    // Settings
    var clickDelay: Double = 0.1 // Delay before clicking (reduced for faster response)
    var hideCursorDuringCapture: Bool = true
    var soundEnabled: Bool = true
    var autoAddUnknown: Bool = true

    // Services
    private let questionDatabase: QuestionDatabaseService
    private let screenCapture: ScreenCaptureService
    private let ocrService: OCRService
    private let mouseController: MouseController
    private let aiService: AIServiceManager

    // Hotkey monitors
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var isProcessingCapture = false  // Prevent double-triggering
    private var isAutoAnswering = false  // Toggle for continuous auto-answer loop

    // MARK: - Init
    init() {
        self.questionDatabase = QuestionDatabaseService()
        self.screenCapture = ScreenCaptureService()
        self.ocrService = OCRService()
        self.mouseController = MouseController()
        self.aiService = AIServiceManager.shared

        loadQuestions()
        setupGlobalHotkey()
    }

    deinit {
        MainActor.assumeIsolated {
            if let monitor = globalEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    // MARK: - Load Questions
    func loadQuestions() {
        questionsLoaded = questionDatabase.totalQuestionCount
        unknownCount = questionDatabase.unknownQuestions.count
    }

    // MARK: - Area Selection
    func beginAreaSelection() {
        status = .selectingArea
        SelectionOverlayWindow.present { [weak self] rect in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let rect = rect {
                    self.selectedCaptureRect = rect
                    self.status = .idle
                } else {
                    self.status = .idle
                }
            }
        }
    }

    // MARK: - Start/Stop Monitoring
    func toggleMonitoring() {
        if status.isRunning {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard selectedCaptureRect != nil else {
            status = .error("Please select a capture area first")
            return
        }

        status = .running
        answeredCount = 0

        // Start the screen capture stream once (keeps it ready for instant captures)
        Task {
            do {
                try await screenCapture.startStream()
                print("[AppModel] Stream ready - press Command+Space to capture and answer")
            } catch {
                print("Failed to start capture stream: \(error)")
                status = .error("Failed to start screen capture")
            }
        }
    }

    func stopMonitoring() {
        status = .idle

        // Stop the screen capture stream
        Task {
            await screenCapture.stopStream()
        }
    }

    /// One-shot capture and answer (called by hotkey ⌘⌃0)
    /// Captures screen, finds answer, clicks it, done.
    func captureAndAnswer() {
        guard selectedCaptureRect != nil else {
            status = .error("Please select a capture area first")
            return
        }
        guard !isProcessingCapture else { return }

        Task {
            status = .running

            // Start stream if needed
            do {
                try await screenCapture.startStream()
            } catch {
                status = .error("Failed to start screen capture")
                return
            }

            // Process capture
            await processCapture()

            // Stop stream and reset status
            await screenCapture.stopStream()
            status = .idle
        }
    }

    // MARK: - Process Capture
    @MainActor
    private func processCapture() async {
        guard let rect = selectedCaptureRect else { return }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        // Hide cursor if enabled
        if hideCursorDuringCapture {
            NSCursor.hide()
        }

        defer {
            if hideCursorDuringCapture {
                NSCursor.unhide()
            }
        }

        do {
            // Capture screen area
            guard let cgImage = try await screenCapture.capture(rect: rect) else {
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: rect.size)
            lastCapture = nsImage

            // Perform OCR
            let ocrResult = try await ocrService.recogniseText(in: cgImage)
            lastOCRText = ocrResult.fullText

            // Try to match question
            if let match = questionDatabase.findBestMatch(for: ocrResult.fullText) {
                lastMatchedQuestion = match.question

                // Find answer location on screen
                if let answerLocation = findAnswerLocation(
                    answer: match.question.answer,
                    in: ocrResult,
                    captureRect: rect
                ) {
                    // Click on the answer
                    try await Task.sleep(nanoseconds: UInt64(clickDelay * 1_000_000_000))

                    mouseController.click(at: answerLocation.clickPoint)
                    lastClickedAnswer = match.question.answer
                    answeredCount += 1

                    if soundEnabled {
                        NSSound(named: NSSound.Name("Pop"))?.play()
                    }
                }
            } else {
                // Question not found - add to unknown
                if autoAddUnknown && !ocrResult.fullText.isEmpty {
                    let options = extractPossibleAnswers(from: ocrResult)
                    questionDatabase.addUnknownQuestion(
                        questionText: ocrResult.fullText,
                        options: options
                    )
                    unknownCount = questionDatabase.unknownQuestions.count
                }
                lastMatchedQuestion = nil
                lastClickedAnswer = nil
            }

        } catch {
            print("Capture error: \(error)")
        }
    }

    // MARK: - Find Answer Location
    private func findAnswerLocation(
        answer: String,
        in ocrResult: OCRResult,
        captureRect: CGRect
    ) -> AnswerLocation? {
        let answerLower = answer.lowercased()

        // Pass 1: Look for EXACT match (block text equals or nearly equals the answer)
        for block in ocrResult.textBlocks {
            let blockLower = block.text.lowercased().trimmingCharacters(in: .whitespaces)

            // Check for exact match
            if blockLower == answerLower || stringSimilarity(blockLower, answerLower) > 0.9 {
                let screenX = captureRect.origin.x + (block.boundingBox.midX * captureRect.width)
                let screenY = captureRect.origin.y + ((1 - block.boundingBox.midY) * captureRect.height)

                return AnswerLocation(
                    answerText: block.text,
                    screenRect: CGRect(
                        x: captureRect.origin.x + (block.boundingBox.origin.x * captureRect.width),
                        y: captureRect.origin.y + ((1 - block.boundingBox.maxY) * captureRect.height),
                        width: block.boundingBox.width * captureRect.width,
                        height: block.boundingBox.height * captureRect.height
                    ),
                    clickPoint: CGPoint(x: screenX, y: screenY)
                )
            }

            // Check for "[A-D] Answer" format (like "B Taoism")
            let optionPattern = "^[abcd]\\s+(.+)$"
            if let regex = try? NSRegularExpression(pattern: optionPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: blockLower, range: NSRange(blockLower.startIndex..., in: blockLower)),
               match.numberOfRanges > 1,
               let optionTextRange = Range(match.range(at: 1), in: blockLower) {
                let optionText = String(blockLower[optionTextRange])
                if optionText == answerLower || stringSimilarity(optionText, answerLower) > 0.85 {
                    let screenX = captureRect.origin.x + (block.boundingBox.midX * captureRect.width)
                    let screenY = captureRect.origin.y + ((1 - block.boundingBox.midY) * captureRect.height)

                    return AnswerLocation(
                        answerText: block.text,
                        screenRect: CGRect(
                            x: captureRect.origin.x + (block.boundingBox.origin.x * captureRect.width),
                            y: captureRect.origin.y + ((1 - block.boundingBox.maxY) * captureRect.height),
                            width: block.boundingBox.width * captureRect.width,
                            height: block.boundingBox.height * captureRect.height
                        ),
                        clickPoint: CGPoint(x: screenX, y: screenY)
                    )
                }
            }
        }

        // Pass 2: Look for blocks containing the answer and estimate position within block
        for block in ocrResult.textBlocks {
            let blockLower = block.text.lowercased()

            if let range = blockLower.range(of: answerLower) {
                // Calculate where within the block text the answer appears (0.0 to 1.0)
                let startIndex = blockLower.distance(from: blockLower.startIndex, to: range.lowerBound)
                let endIndex = blockLower.distance(from: blockLower.startIndex, to: range.upperBound)
                let midIndex = (startIndex + endIndex) / 2
                let totalLength = blockLower.count

                // Estimate horizontal position based on character position
                let relativeX = totalLength > 0 ? Double(midIndex) / Double(totalLength) : 0.5

                // Calculate adjusted X coordinate within the block's bounding box
                let blockLeft = block.boundingBox.minX
                let blockWidth = block.boundingBox.width
                let adjustedX = blockLeft + (blockWidth * relativeX)

                let screenX = captureRect.origin.x + (adjustedX * captureRect.width)
                let screenY = captureRect.origin.y + ((1 - block.boundingBox.midY) * captureRect.height)

                return AnswerLocation(
                    answerText: answer,
                    screenRect: CGRect(
                        x: captureRect.origin.x + (block.boundingBox.origin.x * captureRect.width),
                        y: captureRect.origin.y + ((1 - block.boundingBox.maxY) * captureRect.height),
                        width: block.boundingBox.width * captureRect.width,
                        height: block.boundingBox.height * captureRect.height
                    ),
                    clickPoint: CGPoint(x: screenX, y: screenY)
                )
            }
        }

        // Pass 3: Fuzzy match as fallback
        for block in ocrResult.textBlocks {
            let blockLower = block.text.lowercased()

            if answerLower.contains(blockLower) || stringSimilarity(blockLower, answerLower) > 0.8 {
                let screenX = captureRect.origin.x + (block.boundingBox.midX * captureRect.width)
                let screenY = captureRect.origin.y + ((1 - block.boundingBox.midY) * captureRect.height)

                return AnswerLocation(
                    answerText: block.text,
                    screenRect: CGRect(
                        x: captureRect.origin.x + (block.boundingBox.origin.x * captureRect.width),
                        y: captureRect.origin.y + ((1 - block.boundingBox.maxY) * captureRect.height),
                        width: block.boundingBox.width * captureRect.width,
                        height: block.boundingBox.height * captureRect.height
                    ),
                    clickPoint: CGPoint(x: screenX, y: screenY)
                )
            }
        }

        return nil
    }

    // MARK: - Extract Possible Answers
    private func extractPossibleAnswers(from ocrResult: OCRResult) -> [String] {
        // Simple heuristic: take text blocks that could be answer options
        return ocrResult.textBlocks
            .map { $0.text }
            .filter { $0.count > 2 && $0.count < 100 }
    }

    // MARK: - String Similarity (Levenshtein-based)
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let len1 = s1.count
        let len2 = s2.count

        if len1 == 0 && len2 == 0 { return 1.0 }
        if len1 == 0 || len2 == 0 { return 0.0 }

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

    // MARK: - Global Hotkey
    private func setupGlobalHotkey() {
        // Check and request accessibility permission for global hotkey
        let options = [("AXTrustedCheckOptionPrompt" as CFString): true] as CFDictionary
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if accessibilityEnabled {
            // Global monitor for when app is not focused
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleHotkey(event)
            }
        } else {
            print("Accessibility permission not granted - hotkeys will only work when app is focused")
        }

        // Local monitor for when app is focused (always works)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleHotkey(event) == true {
                return nil // Consume the event
            }
            return event
        }
    }

    @discardableResult
    private func handleHotkey(_ event: NSEvent) -> Bool {
        // Command+Control+0 to capture and answer
        // keyCode 29 = 0
        if event.keyCode == 29 &&
           event.modifierFlags.contains(.command) &&
           event.modifierFlags.contains(.control) {
            DispatchQueue.main.async { [weak self] in
                self?.captureAndAnswer()
            }
            return true
        }
        return false
    }

    private func emergencyStop() {
        stopMonitoring()
        if soundEnabled {
            NSSound.beep()
        }
    }

    // MARK: - Manual Question Management
    func addQuestionManually(question: String, answer: String) {
        questionDatabase.addQuestion(QuestionAnswer(text: question, answer: answer))
        questionsLoaded = questionDatabase.totalQuestionCount
    }

    func resolveUnknownQuestion(_ unknown: UnknownQuestion, with answer: String) {
        questionDatabase.resolveUnknownQuestion(unknown, with: answer)
        questionsLoaded = questionDatabase.totalQuestionCount
        unknownCount = questionDatabase.unknownQuestions.count
    }

    /// Resolves an unknown question with a clean (parsed) question text and answer
    func resolveUnknownQuestion(_ unknown: UnknownQuestion, withCleanQuestion cleanQuestion: String, answer: String) {
        questionDatabase.resolveUnknownQuestionWithCleanText(unknown, cleanQuestion: cleanQuestion, answer: answer)
        questionsLoaded = questionDatabase.totalQuestionCount
        unknownCount = questionDatabase.unknownQuestions.count
    }

    func deleteUnknownQuestion(_ unknown: UnknownQuestion) {
        questionDatabase.deleteUnknownQuestion(unknown)
        unknownCount = questionDatabase.unknownQuestions.count
    }

    func getUnknownQuestions() -> [UnknownQuestion] {
        return questionDatabase.unknownQuestions
    }

    func getAllQuestions() -> [QuestionAnswer] {
        return questionDatabase.getAllQuestions()
    }
}
