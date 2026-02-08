import Foundation

final class GeminiService {
    static let shared = GeminiService()
    private init() {}

    // ✅ API key lives HERE
    private let apiKey = "AIzaSyBo2zPg3xDHhy5ajAmf9Nv6Xv-mwdbey2g"

    private var endpointURL: URL {
        URL(string:
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)"
        )!
    }

    enum GeminiError: Error {
        case badResponse
        case noText
    }

    func generate(prompt: String) async throws -> String {
        var request = URLRequest(url: endpointURL)
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

        let (data, _) = try await URLSession.shared.data(for: request)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String

        guard let text else { throw GeminiError.noText }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

