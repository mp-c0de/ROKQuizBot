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

    // OCR Settings (user-tunable)
    var ocrSettings: OCRSettings = .default {
        didSet { applyOCRSettings() }
    }

    // Layout configuration
    var layoutConfiguration: QuizLayoutConfiguration? = nil
    var isConfiguringLayout: Bool = false

    // Services
    private let questionDatabase: QuestionDatabaseService
    private let layoutService: LayoutConfigurationService
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
        self.layoutService = LayoutConfigurationService()
        self.screenCapture = ScreenCaptureService()
        self.ocrService = OCRService()
        self.mouseController = MouseController()
        self.aiService = AIServiceManager.shared

        loadQuestions()
        loadLayoutConfiguration()
        loadSavedCaptureArea()
        loadOCRSettings()
        setupGlobalHotkey()
    }

    // MARK: - OCR Settings Persistence
    private let ocrSettingsKey = "savedOCRSettings"

    private func loadOCRSettings() {
        if let data = UserDefaults.standard.data(forKey: ocrSettingsKey),
           let settings = try? JSONDecoder().decode(OCRSettings.self, from: data) {
            ocrSettings = settings
            applyOCRSettings()
            print("[AppModel] Loaded saved OCR settings")
        }
    }

    func saveOCRSettings() {
        if let data = try? JSONEncoder().encode(ocrSettings) {
            UserDefaults.standard.set(data, forKey: ocrSettingsKey)
            print("[AppModel] Saved OCR settings")
        }
    }

    private func applyOCRSettings() {
        ocrService.settings = ocrSettings
    }

    /// Applies a preset OCR configuration
    func applyOCRPreset(_ preset: OCRPreset) {
        switch preset {
        case .default:
            ocrSettings = .default
        case .gameText:
            ocrSettings = .gameText
        case .lightOnDark:
            ocrSettings = .lightOnDark
        }
        saveOCRSettings()
    }

    // MARK: - Capture Area Persistence
    private let captureAreaKey = "savedCaptureArea"

    private func loadSavedCaptureArea() {
        if let data = UserDefaults.standard.data(forKey: captureAreaKey),
           let rect = try? JSONDecoder().decode(CodableRect.self, from: data) {
            selectedCaptureRect = rect.cgRect
            print("[AppModel] Loaded saved capture area: \(rect.cgRect)")
        }
    }

    private func saveCaptureArea() {
        guard let rect = selectedCaptureRect else {
            UserDefaults.standard.removeObject(forKey: captureAreaKey)
            return
        }
        let codableRect = CodableRect(cgRect: rect)
        if let data = try? JSONEncoder().encode(codableRect) {
            UserDefaults.standard.set(data, forKey: captureAreaKey)
            print("[AppModel] Saved capture area: \(rect)")
        }
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

    // MARK: - Layout Configuration
    private func loadLayoutConfiguration() {
        layoutConfiguration = layoutService.activeLayout
    }

    /// Opens the layout configuration window to set up question/answer zones
    func beginLayoutConfiguration() {
        guard let rect = selectedCaptureRect else {
            status = .error("Please select a capture area first")
            return
        }

        isConfiguringLayout = true

        // Take a screenshot of the capture area
        Task {
            do {
                try await screenCapture.startStream()
                guard let cgImage = try await screenCapture.capture(rect: rect) else {
                    await screenCapture.stopStream()
                    isConfiguringLayout = false
                    return
                }
                await screenCapture.stopStream()

                let nsImage = NSImage(cgImage: cgImage, size: rect.size)

                // Present the layout configuration window
                let existingLayout = self.layoutConfiguration
                LayoutConfigurationWindow.present(
                    with: nsImage,
                    captureRect: rect,
                    existingLayout: existingLayout
                ) { [weak self] layout in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.isConfiguringLayout = false
                        if let layout = layout {
                            self.layoutConfiguration = layout

                            // Check if this is an update to an existing layout or a new one
                            if existingLayout != nil && self.layoutService.getLayout(layout.id) != nil {
                                self.layoutService.updateLayout(layout)
                                print("[AppModel] Updated layout: \(layout.name)")
                            } else {
                                self.layoutService.addLayout(layout, setActive: true)
                                print("[AppModel] Created new layout: \(layout.name)")
                            }
                        }
                    }
                }
            } catch {
                isConfiguringLayout = false
                print("[AppModel] Failed to capture for layout config: \(error)")
            }
        }
    }

    /// Clears the current layout configuration
    func clearLayoutConfiguration() {
        layoutConfiguration = nil
        layoutService.clearActiveLayout()
    }

    /// Returns all saved layouts
    var savedLayouts: [QuizLayoutConfiguration] {
        return layoutService.layouts
    }

    /// Switches to a different saved layout
    func selectLayout(_ id: UUID) {
        layoutService.setActiveLayout(id)
        layoutConfiguration = layoutService.activeLayout
        print("[AppModel] Switched to layout: \(layoutConfiguration?.name ?? "none")")
    }

    /// Deletes a saved layout
    func deleteLayout(_ id: UUID) {
        layoutService.deleteLayout(id)
        if layoutConfiguration?.id == id {
            layoutConfiguration = nil
        }
    }

    /// Renames a layout
    func renameLayout(_ id: UUID, to newName: String) {
        guard var layout = layoutService.getLayout(id) else { return }
        layout.name = newName
        layoutService.updateLayout(layout)
        if layoutConfiguration?.id == id {
            layoutConfiguration = layout
        }
    }

    /// Saves the current layout with a new name (creates a copy)
    func saveLayoutAs(name: String) {
        guard let current = layoutConfiguration else { return }
        let newLayout = QuizLayoutConfiguration(
            name: name,
            questionZone: current.questionZone,
            answerZones: current.answerZones
        )
        layoutService.addLayout(newLayout, setActive: true)
        layoutConfiguration = layoutService.activeLayout
    }

    // MARK: - Area Selection
    func beginAreaSelection() {
        status = .selectingArea
        SelectionOverlayWindow.present { [weak self] rect in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let rect = rect {
                    self.selectedCaptureRect = rect
                    self.saveCaptureArea()
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

            // Use layout-based OCR if configured, otherwise fall back to full-area OCR
            if let layout = layoutConfiguration, layout.isValid {
                await processWithLayout(cgImage: cgImage, layout: layout, captureRect: rect)
            } else {
                await processWithFullAreaOCR(cgImage: cgImage, captureRect: rect)
            }

        } catch {
            print("Capture error: \(error)")
        }
    }

    /// Processes capture using zone-based OCR with the configured layout
    @MainActor
    private func processWithLayout(cgImage: CGImage, layout: QuizLayoutConfiguration, captureRect: CGRect) async {
        do {
            // OCR each zone separately
            let zoneResults = try await ocrService.recogniseZones(in: cgImage, layout: layout)

            let questionText = cleanQuestionText(zoneResults.question)

            // Clean answer texts - remove leading letter prefix if OCR picked it up (e.g., "A Rune buffs" -> "Rune buffs")
            var cleanedAnswers: [String: String] = [:]
            for (label, text) in zoneResults.answers {
                cleanedAnswers[label] = cleanAnswerText(text, label: label)
            }

            // Display text - sorted by label (A, B, C, D)
            let sortedLabels = ["A", "B", "C", "D"].filter { cleanedAnswers[$0] != nil }
            lastOCRText = "Q: \(questionText)\n" + sortedLabels.map { "\($0): \(cleanedAnswers[$0] ?? "")" }.joined(separator: "\n")

            // Try to match question
            if let match = questionDatabase.findBestMatch(for: questionText) {
                lastMatchedQuestion = match.question

                // Find which answer zone matches the correct answer
                if let matchingZone = findMatchingAnswerZone(
                    correctAnswer: match.question.answer,
                    detectedAnswers: cleanedAnswers,
                    layout: layout
                ) {
                    // Click the centre of the matching answer zone
                    try await Task.sleep(nanoseconds: UInt64(clickDelay * 1_000_000_000))

                    let clickPoint = matchingZone.clickPoint(in: captureRect)
                    mouseController.click(at: clickPoint)

                    // Display the answer - include detected text if answer is a letter
                    let answerUpper = match.question.answer.uppercased()
                    if ["A", "B", "C", "D"].contains(answerUpper),
                       let detectedText = cleanedAnswers[answerUpper], !detectedText.isEmpty {
                        lastClickedAnswer = "\(answerUpper) (\(detectedText))"
                    } else {
                        lastClickedAnswer = match.question.answer
                    }
                    answeredCount += 1

                    if soundEnabled {
                        NSSound(named: NSSound.Name("Pop"))?.play()
                    }
                }
            } else {
                // Question not found - add to unknown
                if autoAddUnknown && !questionText.isEmpty {
                    // Store options in sorted order (A, B, C, D)
                    let sortedOptions = sortedLabels.compactMap { cleanedAnswers[$0] }
                    questionDatabase.addUnknownQuestion(
                        questionText: questionText,
                        options: sortedOptions
                    )
                    unknownCount = questionDatabase.unknownQuestions.count
                }
                lastMatchedQuestion = nil
                lastClickedAnswer = nil
            }
        } catch {
            print("Layout OCR error: \(error)")
        }
    }

    /// Cleans up question text - removes leading "Q1", "Q2", etc.
    private func cleanQuestionText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove leading Q followed by number (e.g., "Q4 Which..." -> "Which...")
        if let range = cleaned.range(of: #"^Q\d+\s*"#, options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...])
        }
        return cleaned
    }

    /// Cleans up answer text - removes leading letter prefix if OCR picked it up
    private func cleanAnswerText(_ text: String, label: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove leading letter that matches the label (e.g., "A Rune buffs" -> "Rune buffs" for label "A")
        let prefixPattern = "^\(label)\\s+"
        if let range = cleaned.range(of: prefixPattern, options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...])
        }
        return cleaned
    }

    /// Finds the layout zone that matches the correct answer
    private func findMatchingAnswerZone(
        correctAnswer: String,
        detectedAnswers: [String: String],
        layout: QuizLayoutConfiguration
    ) -> LayoutZone? {
        let answerTrimmed = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let answerUpper = answerTrimmed.uppercased()

        // First check: if the answer is a zone label (A, B, C, D), return that zone directly
        if ["A", "B", "C", "D"].contains(answerUpper) {
            return layout.answerZones.first { $0.label == answerUpper }
        }

        // Second check: match by text content
        let answerNormalised = normaliseForComparison(answerTrimmed.lowercased())

        // Find the best matching answer zone
        var bestMatch: (zone: LayoutZone, score: Double)?

        for zone in layout.answerZones {
            guard let detectedText = detectedAnswers[zone.label] else { continue }
            let detectedNormalised = normaliseForComparison(detectedText.lowercased())

            // Check for exact match
            if detectedNormalised == answerNormalised {
                return zone
            }

            // Check similarity
            let similarity = stringSimilarity(detectedNormalised, answerNormalised)
            if similarity > 0.75 {
                if bestMatch == nil || similarity > bestMatch!.score {
                    bestMatch = (zone, similarity)
                }
            }
        }

        return bestMatch?.zone
    }

    /// Processes capture using full-area OCR (fallback when no layout configured)
    @MainActor
    private func processWithFullAreaOCR(cgImage: CGImage, captureRect: CGRect) async {
        do {
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
                    captureRect: captureRect
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
            print("Full-area OCR error: \(error)")
        }
    }

    // MARK: - Find Answer Location
    private func findAnswerLocation(
        answer: String,
        in ocrResult: OCRResult,
        captureRect: CGRect
    ) -> AnswerLocation? {
        let answerLower = answer.lowercased()
        // Normalise: replace "and" with "," for matching (e.g., "USA and USSR" -> "USA, USSR")
        let answerNormalised = normaliseForComparison(answerLower)

        // Score all blocks and find the best match
        var bestMatch: (block: OCRResult.TextBlock, score: Double, optionText: String?)? = nil

        for block in ocrResult.textBlocks {
            let blockLower = block.text.lowercased().trimmingCharacters(in: .whitespaces)
            let blockNormalised = normaliseForComparison(blockLower)

            var score: Double = 0
            var matchedOptionText: String? = nil

            // Check for exact match (highest priority)
            if blockNormalised == answerNormalised {
                score = 1.0
            }
            // Check for high similarity match
            else {
                let similarity = stringSimilarity(blockNormalised, answerNormalised)
                if similarity > 0.85 {
                    score = similarity
                }
            }

            // Check for "[A-D] Answer" format (like "B USA, USSR")
            if score < 0.85 {
                let optionPattern = "^[abcd]\\s+(.+)$"
                if let regex = try? NSRegularExpression(pattern: optionPattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: blockLower, range: NSRange(blockLower.startIndex..., in: blockLower)),
                   match.numberOfRanges > 1,
                   let optionTextRange = Range(match.range(at: 1), in: blockLower) {
                    let optionText = String(blockLower[optionTextRange])
                    let optionNormalised = normaliseForComparison(optionText)

                    if optionNormalised == answerNormalised {
                        score = 0.99  // Slightly less than exact block match
                        matchedOptionText = optionText
                    } else {
                        let similarity = stringSimilarity(optionNormalised, answerNormalised)
                        if similarity > score && similarity > 0.85 {
                            score = similarity
                            matchedOptionText = optionText
                        }
                    }
                }
            }

            // Update best match if this is better
            if score > 0, bestMatch == nil || score > bestMatch!.score {
                bestMatch = (block, score, matchedOptionText)
            }
        }

        // If we found a good match (score > 0.8), return it
        if let match = bestMatch, match.score > 0.8 {
            return createAnswerLocation(from: match.block, captureRect: captureRect)
        }

        // Pass 2: Look for blocks containing the normalised answer
        for block in ocrResult.textBlocks {
            let blockLower = block.text.lowercased()
            let blockNormalised = normaliseForComparison(blockLower)

            // Try to find the normalised answer within the block
            if let range = blockNormalised.range(of: answerNormalised) {
                // Calculate where within the block text the answer appears (0.0 to 1.0)
                let startIndex = blockNormalised.distance(from: blockNormalised.startIndex, to: range.lowerBound)
                let endIndex = blockNormalised.distance(from: blockNormalised.startIndex, to: range.upperBound)
                let midIndex = (startIndex + endIndex) / 2
                let totalLength = blockNormalised.count

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

        // Pass 3: Fuzzy match - but be careful with partial matches
        // Only match if the block text is at least 70% of the answer length
        // This prevents matching "USA" when looking for "USA and USSR"
        for block in ocrResult.textBlocks {
            let blockLower = block.text.lowercased()
            let blockNormalised = normaliseForComparison(blockLower)

            // Block must be at least 70% of answer length to be considered
            let lengthRatio = Double(blockNormalised.count) / Double(answerNormalised.count)
            guard lengthRatio >= 0.7 else { continue }

            let similarity = stringSimilarity(blockNormalised, answerNormalised)
            if similarity > 0.75 {
                return createAnswerLocation(from: block, captureRect: captureRect)
            }
        }

        return nil
    }

    /// Normalises text for comparison by replacing common variations
    private func normaliseForComparison(_ text: String) -> String {
        return text
            .replacingOccurrences(of: " and ", with: ", ")
            .replacingOccurrences(of: " & ", with: ", ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Creates an AnswerLocation from a text block
    private func createAnswerLocation(from block: OCRResult.TextBlock, captureRect: CGRect) -> AnswerLocation {
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
        // Just 0 key to capture and answer (no modifiers required)
        // keyCode 29 = 0
        // Only trigger if no modifiers are pressed (except for Fn/NumLock)
        let significantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let hasModifiers = !event.modifierFlags.intersection(significantModifiers).isEmpty

        if event.keyCode == 29 && !hasModifiers {
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
