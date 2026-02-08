import Foundation

enum GeminiError: Error {
    case invalidURL
    case invalidResponse
    case apiError(String)
}

@MainActor
final class GeminiService {
    static let shared = GeminiService()

    // 🔴 PUT YOUR API KEY HERE
    private let apiKey = "PASTE_YOUR_API_KEY_HERE"

    private init() {}

    func generate(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("Missing API key")
        }

        let urlString =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(raw)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String

        guard let text else {
            throw GeminiError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
