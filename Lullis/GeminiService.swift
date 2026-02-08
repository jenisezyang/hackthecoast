import Foundation

final class GeminiService {
    static let shared = GeminiService()
    private init() {}

    // Replace this with however you already store your API key
    // (env var, plist, build setting, etc.)
    private var apiKey: String {
        // Example placeholder — you said you already did this part.
        return AIzaSyBoz2Pg3xDHhy5ajAmf9Nv6Xv-mwdbeY2g
    }

    // Gemini REST endpoint (Generative Language API)
    // If you're using a different endpoint already, keep yours.
    private let endpointBase =
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key="

    enum GeminiError: Error {
        case badURL
        case badResponse
        case noText
    }

    /// Returns the model’s text response.
    func generate(prompt: String) async throws -> String {
        guard let url = URL(string: endpointBase + apiKey) else { throw GeminiError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GeminiError.badResponse
        }

        // Parse: candidates[0].content.parts[0].text
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = obj?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.noText
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

