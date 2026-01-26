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
            // Use CIColorThresholdOtsu for automatic threshold, or manual threshold
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
                    guard let candidate = observation.topCandidates(1).first else { continue }

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

            // Configure recognition - use accurate mode for better text recognition
            // Preprocessing helps with speed, so we can afford accurate mode
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-GB", "en-US"]
            request.usesLanguageCorrection = true  // Helps with character recognition

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
    /// - Parameters:
    ///   - image: The full CGImage to process.
    ///   - normalizedRegion: The region to OCR, in normalised coordinates (0-1).
    /// - Returns: The recognised text from that region.
    func recogniseTextInRegion(of image: CGImage, normalizedRegion: CGRect) async throws -> String {
        // Crop the image to the specified region
        let pixelX = Int(normalizedRegion.origin.x * CGFloat(image.width))
        let pixelY = Int(normalizedRegion.origin.y * CGFloat(image.height))
        let pixelWidth = Int(normalizedRegion.width * CGFloat(image.width))
        let pixelHeight = Int(normalizedRegion.height * CGFloat(image.height))

        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)

        guard let croppedImage = image.cropping(to: cropRect) else {
            return ""
        }

        // Determine if this is a small region that should be scaled up
        let isSmallRegion = pixelWidth < settings.minRegionSize || pixelHeight < settings.minRegionSize

        // Preprocess with scaling for small regions
        let processedImage = preprocessImage(croppedImage, forRegion: isSmallRegion)

        // Perform OCR on the preprocessed cropped image
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

                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-GB", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Recognises text in all zones defined by the layout configuration.
    /// - Parameters:
    ///   - image: The full CGImage to process.
    ///   - layout: The quiz layout configuration defining zones.
    /// - Returns: A tuple containing the question text and a dictionary of answer labels to their text.
    func recogniseZones(in image: CGImage, layout: QuizLayoutConfiguration) async throws -> (question: String, answers: [String: String]) {
        var questionText = ""
        var answers: [String: String] = [:]

        // OCR the question zone
        if let questionZone = layout.questionZone {
            questionText = try await recogniseTextInRegion(of: image, normalizedRegion: questionZone.normalizedRect)
        }

        // OCR each answer zone concurrently
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

        return (question: questionText, answers: answers)
    }
}
