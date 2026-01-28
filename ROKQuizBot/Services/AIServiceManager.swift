// AIServiceManager.swift
// AI Service Manager for future AI integration
// Made by mpcode

import Foundation
import AppKit

// MARK: - AI Provider Enum
enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case claude = "Claude"
    case openAI = "ChatGPT"

    var id: String { rawValue }

    var displayName: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .openAI: return "bubble.left.and.bubble.right"
        }
    }

    var description: String {
        switch self {
        case .claude: return "Anthropic Claude - Excellent at detailed analysis"
        case .openAI: return "OpenAI ChatGPT - Most popular AI"
        }
    }

    var apiKeyPrefix: String {
        switch self {
        case .claude: return "sk-ant-"
        case .openAI: return "sk-"
        }
    }

    var consoleURL: URL {
        switch self {
        case .claude: return URL(string: "https://console.anthropic.com/")!
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        }
    }

    var apiKeyStorageKey: String {
        switch self {
        case .claude: return "claude_api_key"
        case .openAI: return "openai_api_key"
        }
    }
}

// MARK: - AI Service Error
enum AIServiceError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidAPIKey
    case invalidResponse
    case imageProcessingFailed
    case parsingFailed
    case rateLimited
    case quotaExceeded
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API key not configured. Please add your API key in Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidAPIKey:
            return "Invalid API key. Please check your API key."
        case .invalidResponse:
            return "Invalid response from API."
        case .imageProcessingFailed:
            return "Failed to process image."
        case .parsingFailed:
            return "Failed to parse response."
        case .rateLimited:
            return "Rate limited. Please wait a moment and try again."
        case .quotaExceeded:
            return "API quota exceeded. Please check your billing."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        }
    }
}

// MARK: - AI Answer Response
struct AIAnswerResponse: Codable {
    let question: String
    let answer: String
    let confidence: Double
    let explanation: String?
}

// MARK: - Claude API Response Models
struct ClaudeResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }
}

struct ContentBlock: Codable {
    let type: String
    let text: String?
}

struct Usage: Codable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - AI Service Manager
@MainActor
@Observable
final class AIServiceManager {
    static let shared = AIServiceManager()

    private var _selectedProvider: AIProvider
    private var _claudeConfigured: Bool = false
    private var _openAIConfigured: Bool = false

    var selectedProvider: AIProvider {
        get { _selectedProvider }
        set {
            _selectedProvider = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "selected_ai_provider")
        }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: "selected_ai_provider"),
           let provider = AIProvider(rawValue: stored) {
            _selectedProvider = provider
        } else {
            _selectedProvider = .claude
        }

        refreshConfigurationStatus()
    }

    func refreshConfigurationStatus() {
        _claudeConfigured = !(UserDefaults.standard.string(forKey: AIProvider.claude.apiKeyStorageKey) ?? "").isEmpty
        _openAIConfigured = !(UserDefaults.standard.string(forKey: AIProvider.openAI.apiKeyStorageKey) ?? "").isEmpty
    }

    var isConfigured: Bool {
        switch selectedProvider {
        case .claude: return _claudeConfigured
        case .openAI: return _openAIConfigured
        }
    }

    func getAPIKey(for provider: AIProvider) -> String {
        UserDefaults.standard.string(forKey: provider.apiKeyStorageKey) ?? ""
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        UserDefaults.standard.set(key, forKey: provider.apiKeyStorageKey)
        switch provider {
        case .claude: _claudeConfigured = !key.isEmpty
        case .openAI: _openAIConfigured = !key.isEmpty
        }
    }

    func isConfigured(provider: AIProvider) -> Bool {
        switch provider {
        case .claude: return _claudeConfigured
        case .openAI: return _openAIConfigured
        }
    }

    // MARK: - Ask AI for Answer
    /// Sends a screenshot to the AI and asks it to identify the question and correct answer.
    /// - Parameter image: The screenshot containing the question and answer options.
    /// - Returns: The AI's response with the question, answer, and confidence.
    func askForAnswer(image: NSImage) async throws -> AIAnswerResponse {
        guard isConfigured else {
            throw AIServiceError.notConfigured
        }

        switch selectedProvider {
        case .claude:
            return try await askClaudeForAnswer(image: image)
        case .openAI:
            return try await askOpenAIForAnswer(image: image)
        }
    }

    // MARK: - Claude Implementation
    private func askClaudeForAnswer(image: NSImage) async throws -> AIAnswerResponse {
        let apiKey = getAPIKey(for: .claude)
        guard !apiKey.isEmpty else {
            throw AIServiceError.notConfigured
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw AIServiceError.imageProcessingFailed
        }

        let base64Image = imageData.base64EncodedString()

        let systemPrompt = """
        You are a quiz answer assistant. The user will show you a screenshot of a quiz question from the game Rise of Kingdoms.
        Your task is to:
        1. Read the question text from the image
        2. Identify all answer options visible
        3. Determine the correct answer

        Return ONLY a valid JSON object with these fields:
        {
            "question": "the question text you read",
            "answer": "the correct answer text",
            "confidence": number between 0 and 1,
            "explanation": "brief explanation why this is correct" or null
        }

        If you cannot read the question clearly, set confidence lower.
        If you're unsure of the answer, still provide your best guess with appropriate confidence.
        """

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "What is the correct answer to this quiz question?"
                        ]
                    ]
                ]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AIServiceError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textContent = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw AIServiceError.parsingFailed
        }

        // Extract JSON from response
        let jsonString = extractJSON(from: text)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIServiceError.parsingFailed
        }

        return try JSONDecoder().decode(AIAnswerResponse.self, from: jsonData)
    }

    // MARK: - OpenAI Implementation (Placeholder)
    private func askOpenAIForAnswer(image: NSImage) async throws -> AIAnswerResponse {
        let apiKey = getAPIKey(for: .openAI)
        guard !apiKey.isEmpty else {
            throw AIServiceError.notConfigured
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw AIServiceError.imageProcessingFailed
        }

        let base64Image = imageData.base64EncodedString()

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are a quiz answer assistant. The user will show you a screenshot of a quiz question from the game Rise of Kingdoms.
                    Your task is to:
                    1. Read the question text from the image
                    2. Identify all answer options visible
                    3. Determine the correct answer

                    IMPORTANT: Return the FULL TEXT of the correct answer, NOT just the letter (A, B, C, D).
                    For example, if option B says "Julius Caesar", return "Julius Caesar" as the answer, NOT "B".

                    Return ONLY a valid JSON object with these fields:
                    {
                        "question": "the question text you read",
                        "answer": "the full text of the correct answer (not the letter)",
                        "confidence": number between 0 and 1,
                        "explanation": "brief explanation why this is correct" or null
                    }

                    If you cannot read the question clearly, set confidence lower.
                    If you're unsure of the answer, still provide your best guess with appropriate confidence.
                    """
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "What is the correct answer to this quiz question? Remember to return the FULL answer text, not just the letter."
                        ]
                    ]
                ]
            ]
        ]

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AIServiceError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.parsingFailed
        }

        let jsonString = extractJSON(from: content)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIServiceError.parsingFailed
        }

        return try JSONDecoder().decode(AIAnswerResponse.self, from: jsonData)
    }

    // MARK: - Test Connection
    /// Tests the API connection for the specified provider
    func testConnection(provider: AIProvider) async throws -> String {
        switch provider {
        case .claude:
            return try await testClaudeConnection()
        case .openAI:
            return try await testOpenAIConnection()
        }
    }

    private func testClaudeConnection() async throws -> String {
        let apiKey = getAPIKey(for: .claude)
        guard !apiKey.isEmpty else {
            throw AIServiceError.notConfigured
        }

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 10,
            "messages": [
                ["role": "user", "content": "Say OK"]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AIServiceError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return "Claude API connection successful!"
    }

    private func testOpenAIConnection() async throws -> String {
        let apiKey = getAPIKey(for: .openAI)
        guard !apiKey.isEmpty else {
            throw AIServiceError.notConfigured
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": 10,
            "messages": [
                ["role": "user", "content": "Say OK"]
            ]
        ]

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AIServiceError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return "OpenAI API connection successful!"
    }

    // MARK: - Helpers
    private func extractJSON(from text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIndex = cleaned.firstIndex(of: "{"),
           let endIndex = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIndex...endIndex])
        }

        return cleaned
    }
}
