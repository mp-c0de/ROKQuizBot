// OCRService.swift
// Service for performing OCR using Vision framework
// Made by mpcode

import Foundation
import Vision
import AppKit
import CoreImage

@MainActor
final class OCRService {
    private let ciContext = CIContext()

    /// Current OCR settings - can be adjusted by user
    var settings: OCRSettings = .default

    /// When true, saves debug images and OCR results for each zone to disk
    var debugMode: Bool = false

    /// Path where debug images were last saved
    private(set) var lastDebugOutputPath: String?

    /// Configures a VNRecognizeTextRequest with optimal settings for game quiz text.
    private func configureRequest(_ request: VNRecognizeTextRequest, useLanguageCorrection: Bool = true) {
        request.recognitionLevel = .accurate
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLanguages = ["en-GB", "en-US"]
        request.usesLanguageCorrection = useLanguageCorrection
        request.minimumTextHeight = 0.01
        request.customWords = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
    }

    /// Picks the best candidate from an observation by checking multiple candidates.
    private func bestCandidate(from observation: VNRecognizedTextObservation) -> VNRecognizedText? {
        let candidates = observation.topCandidates(3)
        return candidates.max(by: { $0.confidence < $1.confidence })
    }

    /// Runs OCR on a CGImage with the given configuration.
    private func performOCR(on image: CGImage, useLanguageCorrection: Bool) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations.compactMap { self.bestCandidate(from: $0)?.string }.joined(separator: " ")
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            self.configureRequest(request, useLanguageCorrection: useLanguageCorrection)

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Inverts the colours of a CGImage (white-on-gold → dark-on-blue).
    private func invertImage(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorInvert") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    /// Preprocesses an image to improve OCR accuracy based on current settings.
    private func preprocessImage(_ image: CGImage, forRegion isSmallRegion: Bool = false) -> CGImage {
        var ciImage = CIImage(cgImage: image)

        // Step 1: Scale up small regions
        if isSmallRegion && settings.scaleFactor > 1.0 {
            let scale = CGAffineTransform(scaleX: settings.scaleFactor, y: settings.scaleFactor)
            ciImage = ciImage.transformed(by: scale)
        }

        // Step 2: Invert colors if enabled (for light text on dark backgrounds)
        if settings.invertColors {
            if let filter = CIFilter(name: "CIColorInvert") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = filter.outputImage {
                    ciImage = output
                }
            }
        }

        // Step 3: Convert to grayscale if enabled
        if settings.grayscaleEnabled {
            if let filter = CIFilter(name: "CIColorMonochrome") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: "inputColor")
                filter.setValue(1.0, forKey: "inputIntensity")
                if let output = filter.outputImage {
                    ciImage = output
                }
            }
        }

        // Step 4: Apply contrast and brightness
        if settings.contrast != 1.0 || settings.brightness != 0.0 {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
                filter.setValue(settings.brightness, forKey: kCIInputBrightnessKey)
                filter.setValue(settings.grayscaleEnabled ? 0.0 : 1.0, forKey: kCIInputSaturationKey)
                if let output = filter.outputImage {
                    ciImage = output
                }
            }
        }

        // Step 5: Apply sharpening if enabled
        if settings.sharpeningEnabled && settings.sharpnessIntensity > 0 {
            if let filter = CIFilter(name: "CISharpenLuminance") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(settings.sharpnessIntensity, forKey: kCIInputSharpnessKey)
                if let output = filter.outputImage {
                    ciImage = output
                }
            }
        }

        // Step 6: Apply binarization (threshold to black/white) if enabled
        if settings.binarizationEnabled {
            if let filter = CIFilter(name: "CIColorThreshold") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(settings.binarizationThreshold, forKey: "inputThreshold")
                if let output = filter.outputImage {
                    ciImage = output
                }
            }
        }

        // Convert back to CGImage
        if let result = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            return result
        }

        return image
    }

    /// Recognises text in the given image using Vision framework.
    /// - Parameter image: The CGImage to process.
    /// - Returns: OCRResult containing the full text and individual text blocks with their positions.
    func recogniseText(in image: CGImage) async throws -> OCRResult {
        // Preprocess image for better OCR accuracy
        let processedImage = preprocessImage(image)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(fullText: "", textBlocks: []))
                    return
                }

                var textBlocks: [OCRResult.TextBlock] = []
                var fullTextParts: [String] = []

                for observation in observations {
                    guard let candidate = self.bestCandidate(from: observation) else { continue }

                    let text = candidate.string
                    fullTextParts.append(text)

                    // Bounding box is in normalised coordinates (0-1), origin at bottom-left
                    let boundingBox = observation.boundingBox

                    textBlocks.append(OCRResult.TextBlock(
                        text: text,
                        boundingBox: boundingBox
                    ))
                }

                let fullText = fullTextParts.joined(separator: " ")
                continuation.resume(returning: OCRResult(fullText: fullText, textBlocks: textBlocks))
            }

            self.configureRequest(request)

            let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Recognises text from an NSImage.
    func recogniseText(in nsImage: NSImage) async throws -> OCRResult {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return OCRResult(fullText: "", textBlocks: [])
        }
        return try await recogniseText(in: cgImage)
    }

    // MARK: - Zone-Specific OCR

    /// Recognises text in a specific normalised region of the image.
    func recogniseTextInRegion(of image: CGImage, normalizedRegion: CGRect) async throws -> String {
        let processedImage = cropAndPreprocess(image: image, normalizedRegion: normalizedRegion)
        guard let processedImage else { return "" }
        return try await performOCR(on: processedImage, useLanguageCorrection: true)
    }

    /// Crops and preprocesses a region of the image.
    private func cropAndPreprocess(image: CGImage, normalizedRegion: CGRect) -> CGImage? {
        guard let cropped = cropRegion(image: image, normalizedRegion: normalizedRegion) else { return nil }
        let pixelWidth = Int(normalizedRegion.width * CGFloat(image.width))
        let pixelHeight = Int(normalizedRegion.height * CGFloat(image.height))
        let isSmallRegion = pixelWidth < settings.minRegionSize || pixelHeight < settings.minRegionSize
        return preprocessImage(cropped, forRegion: isSmallRegion)
    }

    /// Crops a region without any preprocessing (raw pixel data).
    private func cropRegion(image: CGImage, normalizedRegion: CGRect) -> CGImage? {
        let pixelX = Int(normalizedRegion.origin.x * CGFloat(image.width))
        let pixelY = Int(normalizedRegion.origin.y * CGFloat(image.height))
        let pixelWidth = Int(normalizedRegion.width * CGFloat(image.width))
        let pixelHeight = Int(normalizedRegion.height * CGFloat(image.height))

        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
        return image.cropping(to: cropRect)
    }

    /// Recognises text in all zones defined by the layout configuration.
    /// Uses a three-pass approach for answer zones:
    /// 1. Normal preprocessed image with language correction
    /// 2. Inverted raw image for zones that fail
    /// 3. Inverted + binarized for zones still failing (best for low-contrast left-side zones)
    func recogniseZones(in image: CGImage, layout: QuizLayoutConfiguration) async throws -> (question: String, answers: [String: String]) {
        var questionText = ""
        var answers: [String: String] = [:]

        // OCR the question zone
        if let questionZone = layout.questionZone {
            questionText = try await recogniseTextInRegion(of: image, normalizedRegion: questionZone.normalizedRect)
        }

        // Pass 1: OCR each answer zone concurrently (preprocessed + language correction ON)
        await withTaskGroup(of: (String, String).self) { group in
            for zone in layout.answerZones {
                group.addTask {
                    do {
                        let text = try await self.recogniseTextInRegion(of: image, normalizedRegion: zone.normalizedRect)
                        return (zone.label, text)
                    } catch {
                        return (zone.label, "")
                    }
                }
            }

            for await (label, text) in group {
                answers[label] = text
            }
        }

        // Pass 2: For suspicious zones, retry with inverted raw image.
        // Vision struggles with white/light text on coloured backgrounds but reads
        // inverted (dark text on light background) much more reliably.
        let pass2Zones = suspiciousZones(from: layout.answerZones, answers: answers)

        if !pass2Zones.isEmpty {
            var invertedZones: [(label: String, invertedImage: CGImage)] = []
            for zone in pass2Zones {
                if let rawImg = cropRegion(image: image, normalizedRegion: zone.normalizedRect),
                   let inverted = invertImage(rawImg) {
                    invertedZones.append((zone.label, inverted))
                }
            }

            if !invertedZones.isEmpty {
                await withTaskGroup(of: (String, String)?.self) { group in
                    for (label, invertedImage) in invertedZones {
                        group.addTask {
                            do {
                                let text = try await self.performOCR(on: invertedImage, useLanguageCorrection: true)
                                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !cleaned.isEmpty && cleaned.caseInsensitiveCompare(label) != .orderedSame {
                                    return (label, text)
                                }
                            } catch {}
                            return nil
                        }
                    }

                    for await result in group {
                        if let (label, text) = result {
                            answers[label] = text
                        }
                    }
                }
            }
        }

        // Pass 3: For zones STILL suspicious, try inverted + binarized.
        // Uses aggressive contrast/brightness to wash out background texture before
        // binarizing, then strips OCR artefacts from the result.
        let pass3Zones = suspiciousZones(from: layout.answerZones, answers: answers)

        if !pass3Zones.isEmpty {
            var invertedBinarizedZones: [(label: String, processedImage: CGImage)] = []
            for zone in pass3Zones {
                if let rawImg = cropRegion(image: image, normalizedRegion: zone.normalizedRect),
                   let inverted = invertImage(rawImg) {
                    let pixelWidth = Int(zone.normalizedRect.width * CGFloat(image.width))
                    let pixelHeight = Int(zone.normalizedRect.height * CGFloat(image.height))
                    let isSmall = pixelWidth < settings.minRegionSize || pixelHeight < settings.minRegionSize
                    let scale = isSmall ? settings.scaleFactor : 1.0

                    // Aggressive settings: high contrast + brightness to nuke background texture
                    if let processed = applyFilters(inverted, grayscale: true, contrast: 3.5, brightness: 0.3, binarize: true, threshold: 0.6, scaleFactor: scale) {
                        invertedBinarizedZones.append((zone.label, processed))
                    }
                }
            }

            if !invertedBinarizedZones.isEmpty {
                await withTaskGroup(of: (String, String)?.self) { group in
                    for (label, processedImage) in invertedBinarizedZones {
                        group.addTask {
                            do {
                                // Language correction ON — with aggressive image processing it
                                // produces clean results (e.g. "3" not ",на•. 3 Ti...")
                                let text = try await self.performOCR(on: processedImage, useLanguageCorrection: true)
                                let cleaned = self.cleanPass3Result(text, label: label)
                                if !cleaned.isEmpty && cleaned.caseInsensitiveCompare(label) != .orderedSame {
                                    return (label, cleaned)
                                }
                            } catch {}
                            return nil
                        }
                    }

                    for await result in group {
                        if let (label, text) = result {
                            answers[label] = text
                        }
                    }
                }
            }
        }

        // Save debug images if enabled
        if debugMode {
            await saveDebugImages(for: layout.answerZones, from: image)
        }

        return (question: questionText, answers: answers)
    }

    /// Returns answer zones whose OCR result is empty or just the label letter.
    private func suspiciousZones(from zones: [LayoutZone], answers: [String: String]) -> [LayoutZone] {
        zones.filter { zone in
            let text = answers[zone.label] ?? ""
            let cleaned = stripLabelPrefix(text, label: zone.label)
            return cleaned.isEmpty || cleaned.caseInsensitiveCompare(zone.label) == .orderedSame
        }
    }

    /// Cleans OCR output from pass 3 (inverted+binarized) which often contains
    /// artefact characters from background texture being binarized.
    /// e.g. "3 •557..." → "3", "5 i detests" → "5"
    nonisolated private func cleanPass3Result(_ text: String, label: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip the label prefix first (e.g. "A 3" → "3")
        cleaned = stripLabelPrefix(cleaned, label: label)

        // Remove bullet characters and common OCR noise symbols
        let noiseChars = CharacterSet(charactersIn: "•·○●◦▪▸►◆■□△▽※†‡§¶~`|\\")
        cleaned = cleaned.components(separatedBy: noiseChars).joined()

        // Remove sequences of 2+ dots/periods
        cleaned = cleaned.replacingOccurrences(of: #"\.{2,}"#, with: "", options: .regularExpression)

        // Remove trailing noise: anything after and including a lone dot/bullet sequence
        // This catches patterns like "3 557" from "3 •557..."
        // Strategy: keep text up to the first suspicious break
        // A "suspicious break" is a space followed by characters that don't look like real answer text
        // (e.g., strings of digits with no letters, or gibberish)

        // Split into words and keep only the leading meaningful portion
        let words = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var meaningful: [String] = []
        for word in words {
            let alphanumeric = word.filter { $0.isLetter || $0.isNumber }
            // Skip words that are empty after removing noise
            if alphanumeric.isEmpty { continue }
            // Skip single-character words that aren't real (but allow "a", "I", and digits)
            if alphanumeric.count == 1 {
                let ch = alphanumeric.lowercased()
                if ch == "a" || ch == "i" || alphanumeric.first?.isNumber == true {
                    meaningful.append(alphanumeric)
                    continue
                }
                // Single noise letter — stop here, rest is likely artefacts
                break
            }
            // Skip words that are mostly digits mixed with letters (e.g. "557T", "7drit")
            // but allow pure numbers and pure words
            let digitCount = alphanumeric.filter { $0.isNumber }.count
            let letterCount = alphanumeric.filter { $0.isLetter }.count
            if digitCount > 0 && letterCount > 0 && alphanumeric.count <= 5 {
                // Mixed short gibberish — likely noise, stop
                break
            }
            meaningful.append(word)
        }

        cleaned = meaningful.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    /// Strips a leading label prefix from OCR text (e.g., "D 3" → "3" for label "D").
    nonisolated private func stripLabelPrefix(_ text: String, label: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPattern = "^\(label)\\s+"
        if let range = cleaned.range(of: prefixPattern, options: [.regularExpression, .caseInsensitive]) {
            cleaned = String(cleaned[range.upperBound...])
        }
        return cleaned
    }

    // MARK: - Debug Image Saving

    /// Saves multiple processed image variants and OCR results for each answer zone.
    /// Creates ~/Documents/ROKQuizBot/debug/ with images and a text report.
    private func saveDebugImages(for zones: [LayoutZone], from image: CGImage) async {
        let debugDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/ROKQuizBot/debug")

        // Clear previous debug output
        try? FileManager.default.removeItem(at: debugDir)
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)

        var report = "OCR Debug Report\n"
        report += "Generated: \(Date())\n"
        report += "Image size: \(image.width) x \(image.height)\n"
        report += "Current settings: contrast=\(settings.contrast), brightness=\(settings.brightness), "
        report += "grayscale=\(settings.grayscaleEnabled), invert=\(settings.invertColors), "
        report += "scale=\(settings.scaleFactor), binarize=\(settings.binarizationEnabled) (threshold=\(settings.binarizationThreshold))\n"
        report += String(repeating: "=", count: 80) + "\n\n"

        for zone in zones {
            let label = zone.label
            report += "Zone \(label):\n"
            report += "  Normalised rect: \(zone.normalizedRect)\n"

            guard let rawCropped = cropRegion(image: image, normalizedRegion: zone.normalizedRect) else {
                report += "  ERROR: Failed to crop region\n\n"
                continue
            }

            let pixelWidth = Int(zone.normalizedRect.width * CGFloat(image.width))
            let pixelHeight = Int(zone.normalizedRect.height * CGFloat(image.height))
            report += "  Pixel size: \(pixelWidth) x \(pixelHeight)\n\n"

            // Generate all 7 image variants
            let variants: [(name: String, image: CGImage)] = generateVariants(
                rawCropped: rawCropped,
                label: label,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )

            // Save each variant and run OCR
            for (name, variantImage) in variants {
                let filename = "\(label)_\(name).png"
                savePNG(variantImage, to: debugDir.appendingPathComponent(filename))

                // Run OCR with and without language correction
                let ocrWithLC = (try? await performOCR(on: variantImage, useLanguageCorrection: true)) ?? "(error)"
                let ocrNoLC = (try? await performOCR(on: variantImage, useLanguageCorrection: false)) ?? "(error)"

                report += "  \(filename):\n"
                report += "    With lang correction:    \"\(ocrWithLC)\"\n"
                report += "    Without lang correction:  \"\(ocrNoLC)\"\n"
            }

            report += "\n"
        }

        // Write report
        let reportURL = debugDir.appendingPathComponent("debug_results.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)

        lastDebugOutputPath = debugDir.path
        print("[OCRService] Debug output saved to: \(debugDir.path)")
    }

    /// Generates 7 image variants for a raw cropped zone image.
    private func generateVariants(rawCropped: CGImage, label: String, pixelWidth: Int, pixelHeight: Int) -> [(name: String, image: CGImage)] {
        var variants: [(String, CGImage)] = []

        // 1. Raw cropped, no processing
        variants.append(("1_raw", rawCropped))

        // 2. Current settings pipeline (preprocessImage)
        let isSmall = pixelWidth < settings.minRegionSize || pixelHeight < settings.minRegionSize
        let preprocessed = preprocessImage(rawCropped, forRegion: isSmall)
        variants.append(("2_preprocessed", preprocessed))

        // 3. Just colour inversion on raw crop
        if let inverted = invertImage(rawCropped) {
            variants.append(("3_inverted_raw", inverted))
        }

        // 4. Inversion then full pipeline
        if let inverted = invertImage(rawCropped) {
            let invertedPreprocessed = preprocessImage(inverted, forRegion: isSmall)
            variants.append(("4_inverted_preprocessed", invertedPreprocessed))
        }

        // 5. High contrast: grayscale + contrast 3.0 + brightness 0.2
        if let highContrast = applyFilters(rawCropped, grayscale: true, contrast: 3.0, brightness: 0.2, scaleFactor: isSmall ? settings.scaleFactor : 1.0) {
            variants.append(("5_highcontrast", highContrast))
        }

        // 6. Binarized at 0.5 threshold
        if let binarized = applyFilters(rawCropped, grayscale: true, contrast: 2.0, brightness: 0.1, binarize: true, threshold: 0.5, scaleFactor: isSmall ? settings.scaleFactor : 1.0) {
            variants.append(("6_binarized", binarized))
        }

        // 7. Inverted then binarized (old: contrast 2.0, brightness 0.1, threshold 0.5)
        if let inverted = invertImage(rawCropped),
           let invertedBinarized = applyFilters(inverted, grayscale: true, contrast: 2.0, brightness: 0.1, binarize: true, threshold: 0.5, scaleFactor: isSmall ? settings.scaleFactor : 1.0) {
            variants.append(("7_inverted_binarized_old", invertedBinarized))
        }

        // 8. Inverted then binarized AGGRESSIVE (pass 3 settings: contrast 3.5, brightness 0.3, threshold 0.6)
        if let inverted = invertImage(rawCropped),
           let invertedBinarizedAggressive = applyFilters(inverted, grayscale: true, contrast: 3.5, brightness: 0.3, binarize: true, threshold: 0.6, scaleFactor: isSmall ? settings.scaleFactor : 1.0) {
            variants.append(("8_inverted_binarized_aggressive", invertedBinarizedAggressive))
        }

        return variants
    }

    /// Applies a custom set of CIFilters to a CGImage and returns the result.
    private func applyFilters(
        _ image: CGImage,
        grayscale: Bool = false,
        contrast: Double = 1.0,
        brightness: Double = 0.0,
        binarize: Bool = false,
        threshold: Double = 0.5,
        scaleFactor: Double = 1.0
    ) -> CGImage? {
        var ci = CIImage(cgImage: image)

        // Scale
        if scaleFactor > 1.0 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        }

        // Grayscale
        if grayscale {
            if let f = CIFilter(name: "CIColorMonochrome") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: "inputColor")
                f.setValue(1.0, forKey: "inputIntensity")
                if let out = f.outputImage { ci = out }
            }
        }

        // Contrast + brightness
        if contrast != 1.0 || brightness != 0.0 {
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(contrast, forKey: kCIInputContrastKey)
                f.setValue(brightness, forKey: kCIInputBrightnessKey)
                f.setValue(grayscale ? 0.0 : 1.0, forKey: kCIInputSaturationKey)
                if let out = f.outputImage { ci = out }
            }
        }

        // Binarize
        if binarize {
            if let f = CIFilter(name: "CIColorThreshold") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(threshold, forKey: "inputThreshold")
                if let out = f.outputImage { ci = out }
            }
        }

        return ciContext.createCGImage(ci, from: ci.extent)
    }

    /// Saves a CGImage as PNG to disk.
    private func savePNG(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
