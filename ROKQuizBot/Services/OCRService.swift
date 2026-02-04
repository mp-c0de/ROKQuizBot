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
    /// Uses a two-pass approach for answer zones:
    /// 1. Normal preprocessed image with language correction
    /// 2. Inverted raw image for zones that fail (Vision reads dark-on-light text much better)
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
        var invertedZones: [(label: String, invertedImage: CGImage)] = []
        for zone in layout.answerZones {
            let text = answers[zone.label] ?? ""
            let cleaned = stripLabelPrefix(text, label: zone.label)
            let isSuspicious = cleaned.isEmpty
                || cleaned.caseInsensitiveCompare(zone.label) == .orderedSame

            if isSuspicious,
               let rawImg = cropRegion(image: image, normalizedRegion: zone.normalizedRect),
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

        return (question: questionText, answers: answers)
    }

    /// Strips a leading label prefix from OCR text (e.g., "D 3" → "3" for label "D").
    private func stripLabelPrefix(_ text: String, label: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPattern = "^\(label)\\s+"
        if let range = cleaned.range(of: prefixPattern, options: [.regularExpression, .caseInsensitive]) {
            cleaned = String(cleaned[range.upperBound...])
        }
        return cleaned
    }
}
