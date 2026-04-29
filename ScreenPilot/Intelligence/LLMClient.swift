import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

actor LLMClient {
    private let session: URLSession
    private let apiEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    struct AnalysisRequest {
        let image: CGImage
        let systemPrompt: String
        let contextHistory: [String]
        let recentNudges: [ContextWindow.NudgeEntry]
        let model: String
    }

    struct FollowUpRequest {
        let image: CGImage
        let systemPrompt: String
        let conversationHistory: [(question: String, answer: String)]
        let question: String
        let model: String
    }

    init() {
        self.session = URLSession.shared
    }

    func analyze(_ request: AnalysisRequest) async throws -> LLMResponse {
        guard let apiKey = await MainActor.run(body: { KeychainHelper.loadAPIKey() }),
              !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        let base64Image = try encodeImage(request.image)

        var contextParts: [String] = []

        if !request.contextHistory.isEmpty {
            contextParts.append("Recent activity:\n" + request.contextHistory.joined(separator: "\n"))
        }

        if !request.recentNudges.isEmpty {
            var nudgeLines: [String] = []
            let nudges = request.recentNudges
            for (index, nudge) in nudges.enumerated().reversed() {
                if index == nudges.count - 1 {
                    nudgeLines.append("- \(nudge.title): \(nudge.body)")
                } else {
                    nudgeLines.append("- \(nudge.title)")
                }
            }
            contextParts.append("Recent suggestions already shown to user (DO NOT repeat these topics):\n" + nudgeLines.joined(separator: "\n"))
        }

        let contextText = contextParts.isEmpty ? "No recent context." : contextParts.joined(separator: "\n\n")

        let body: [String: Any] = [
            "model": request.model,
            "max_tokens": 1024,
            "system": request.systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image,
                            ],
                        ],
                        [
                            "type": "text",
                            "text": contextText,
                        ],
                    ],
                ]
            ],
        ]

        var urlRequest = URLRequest(url: apiEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw LLMError.noTextContent
        }

        return LLMResponse(rawText: text)
    }

    func followUp(_ request: FollowUpRequest) async throws -> LLMResponse {
        guard let apiKey = await MainActor.run(body: { KeychainHelper.loadAPIKey() }),
              !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        let base64Image = try encodeImage(request.image)

        // Build multi-turn conversation: image first, then history, then new question
        var messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64Image,
                        ],
                    ],
                    [
                        "type": "text",
                        "text": request.conversationHistory.isEmpty
                            ? request.question
                            : request.conversationHistory.first!.question,
                    ],
                ],
            ]
        ]

        // Add prior follow-up history as alternating assistant/user turns
        for (index, entry) in request.conversationHistory.enumerated() {
            messages.append(["role": "assistant", "content": entry.answer])
            if index < request.conversationHistory.count - 1 {
                messages.append(["role": "user", "content": request.conversationHistory[index + 1].question])
            }
        }

        // Add the new question if there's history (otherwise it was already included above)
        if !request.conversationHistory.isEmpty {
            messages.append(["role": "user", "content": request.question])
        }

        let body: [String: Any] = [
            "model": request.model,
            "max_tokens": 2048,
            "system": request.systemPrompt,
            "messages": messages,
        ]

        var urlRequest = URLRequest(url: apiEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw LLMError.noTextContent
        }

        return LLMResponse(rawText: text)
    }

    // MARK: - Image Encoding

    private func encodeImage(_ image: CGImage) throws -> String {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LLMError.imageEncodingFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.7
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw LLMError.imageEncodingFailed
        }

        return (mutableData as Data).base64EncodedString()
    }
}

// MARK: - Types

struct LLMResponse {
    let rawText: String
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noTextContent
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No API key configured. Add your Anthropic API key in Settings."
        case .invalidResponse: "Invalid response from API."
        case .apiError(let code, let msg): "API error (\(code)): \(msg)"
        case .noTextContent: "No text content in API response."
        case .imageEncodingFailed: "Failed to encode screenshot."
        }
    }
}

// MARK: - Anthropic API Response Model

struct AnthropicResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}
