// AppModel.swift
// Main application state model
// Made by mpcode

import Foundation
import SwiftUI
import AppKit
import Combine

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
    var captureInterval: Double = 2.0 // Seconds between captures
    var clickDelay: Double = 0.3 // Delay before clicking
    var hideCursorDuringCapture: Bool = true
    var soundEnabled: Bool = true
    var autoAddUnknown: Bool = true

    // Services
    private let questionDatabase: QuestionDatabaseService
    private let screenCapture: ScreenCaptureService
    private let ocrService: OCRService
    private let mouseController: MouseController
    private let aiService: AIServiceManager

    // Timer
    private var timer: AnyCancellable?
    private var globalEventMonitor: Any?

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
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Load Questions
    func loadQuestions() {
        questionsLoaded = questionDatabase.questions.count
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

        timer = Timer.publish(every: captureInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.processCapture() }
            }

        // Trigger immediate capture
        Task { await processCapture() }
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        status = .idle
    }

    func pauseMonitoring() {
        if status.isRunning {
            timer?.cancel()
            timer = nil
            status = .paused
        }
    }

    func resumeMonitoring() {
        if case .paused = status {
            startMonitoring()
        }
    }

    // MARK: - Process Capture
    @MainActor
    private func processCapture() async {
        guard let rect = selectedCaptureRect else { return }

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

        for block in ocrResult.textBlocks {
            let blockLower = block.text.lowercased()

            // Check if this block contains the answer
            if blockLower.contains(answerLower) ||
               answerLower.contains(blockLower) ||
               stringSimilarity(blockLower, answerLower) > 0.8 {

                // Convert normalised coordinates to screen coordinates
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
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Command+Shift+Escape to stop
            if event.keyCode == 53 &&
               event.modifierFlags.contains(.command) &&
               event.modifierFlags.contains(.shift) {
                DispatchQueue.main.async {
                    self?.emergencyStop()
                }
            }
        }
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
        questionsLoaded = questionDatabase.questions.count
    }

    func resolveUnknownQuestion(_ unknown: UnknownQuestion, with answer: String) {
        questionDatabase.resolveUnknownQuestion(unknown, with: answer)
        questionsLoaded = questionDatabase.questions.count
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
        return questionDatabase.questions
    }
}
