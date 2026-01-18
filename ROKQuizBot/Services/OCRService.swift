// OCRService.swift
// Service for performing OCR using Vision framework
// Made by mpcode

import Foundation
import Vision
import AppKit

@MainActor
final class OCRService {
    /// Recognises text in the given image using Vision framework.
    /// - Parameter image: The CGImage to process.
    /// - Returns: OCRResult containing the full text and individual text blocks with their positions.
    func recogniseText(in image: CGImage) async throws -> OCRResult {
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

            // Configure recognition
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-GB", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

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
}
