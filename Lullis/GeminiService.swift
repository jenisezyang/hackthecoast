import Foundation

final class GeminiService {
    static let shared = GeminiService()
    private init() {}

    // Read from Info.plist (Key: GEMINI_API_KEY)
    private var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "AIzaSyBoz2Pg3xDHhy5ajAmf9Nv6Xv-mwdbeY2g") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var endpointURL: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!
    }

    enum GeminiError: LocalizedError {
        case missingAPIKey
        case httpError(code: Int, message: String)
        case apiError(message: String)
        case noText
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Missing GEMINI_API_KEY. Add it to Info.plist."
            case .httpError(let code, let message):
                return "HTTP \(code): \(message)"
            case .apiError(let message):
                return message
            case .noText:
                return "No text returned by Gemini."
            case .badResponse:
                return "Unexpected response from Gemini."
            }
        }
    }

    func generate(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.badResponse
        }

        // Parse JSON once (both success + error use JSON)
        let jsonAny = try? JSONSerialization.jsonObject(with: data)
        let json = jsonAny as? [String: Any]

        // If Google returns an error, it looks like: { "error": { "message": "...", ... } }
        if let err = json?["error"] as? [String: Any],
           let msg = err["message"] as? String {
            // Also include HTTP status for clarity
            throw GeminiError.httpError(code: http.statusCode, message: msg)
        }

        // Non-200 without a structured error
        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "No body"
            throw GeminiError.httpError(code: http.statusCode, message: raw)
        }

        // Success parsing
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.noText
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
