import Foundation

@MainActor
final class GeminiService {

    static let shared = GeminiService()

    // 👇 THIS IS WHERE IT GOES
    private let apiKey = "AIzaSyBXETev_Jvwhb95QbcIZQI_0mvchem7Gag"

    private init() {
        if apiKey.isEmpty {
            fatalError("Missing Gemini API key")
        }
    }

    func generate(prompt: String) async throws -> String {
        let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=\(apiKey)"
        )!

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, _) = try await URLSession.shared.data(for: request)

        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String

        return text ?? "No explanation available."
    }
}

