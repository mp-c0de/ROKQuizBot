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

    /// Preprocesses an image to improve OCR accuracy.
    /// Converts to grayscale and increases contrast.
    private func preprocessImage(_ image: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: image)

        // Convert to grayscale using CIColorMonochrome
        guard let grayscaleFilter = CIFilter(name: "CIColorMonochrome") else {
            return image
        }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: "inputColor")
        grayscaleFilter.setValue(1.0, forKey: "inputIntensity")

        guard let grayscaleOutput = grayscaleFilter.outputImage else {
            return image
        }

        // Increase contrast using CIColorControls
        guard let contrastFilter = CIFilter(name: "CIColorControls") else {
            // Return grayscale if contrast filter fails
            if let result = ciContext.createCGImage(grayscaleOutput, from: grayscaleOutput.extent) {
                return result
            }
            return image
        }
        contrastFilter.setValue(grayscaleOutput, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.3, forKey: kCIInputContrastKey)  // Boost contrast
        contrastFilter.setValue(0.05, forKey: kCIInputBrightnessKey)  // Slight brightness boost
        contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey)

        guard let contrastOutput = contrastFilter.outputImage,
              let result = ciContext.createCGImage(contrastOutput, from: contrastOutput.extent) else {
            // Return grayscale if final conversion fails
            if let result = ciContext.createCGImage(grayscaleOutput, from: grayscaleOutput.extent) {
                return result
            }
            return image
        }

        return result
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

        let result = try await recogniseText(in: croppedImage)
        return result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
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
