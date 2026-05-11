import Foundation

// MARK: - API Config
enum APIConfig {

    // MARK: - API Key (stored in UserDefaults)
    static var geminiAPIKey: String {
        get { UserDefaults.standard.string(forKey: "spendy.geminiAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "spendy.geminiAPIKey") }
    }

    static var hasAPIKey: Bool { !geminiAPIKey.isEmpty }

    // MARK: - Model Names
    // Phase A (API testing) → gemini-2.0-flash (confirmed working, get new key if quota exhausted)
    // Phase B (on-device)   → Real Gemma 4 GGUF via Cactus (no API needed)
    static let gemmaTextModel   = "gemini-2.0-flash"
    static let gemmaVisionModel = "gemini-2.0-flash"
    static let geminiImageModel = "gemini-2.0-flash-preview-image-generation"

    // MARK: - Endpoints
    static func textURL(_ model: String) -> String {
        "https://generativelanguage.googleapis.com/v1/models/\(model):generateContent"
    }

    // Convenience shorthands
    static var geminiTextURL:   String { textURL(gemmaTextModel) }
    static var geminiVisionURL: String { textURL(gemmaVisionModel) }
    static var geminiImageURL:  String { textURL(geminiImageModel) }

    // MARK: - Ping (validate key)
    /// Sends a tiny request to verify the API key works. Returns nil on success, error message on failure.
    static func validateKey(_ key: String) async -> String? {
        let url = textURL(gemmaTextModel) + "?key=\(key)"
        guard let requestURL = URL(string: url) else { return "Invalid URL" }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": "Hi"]]]],
            "generationConfig": ["maxOutputTokens": 5]
        ]
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 200 { return nil }  // success
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                return msg ?? "HTTP \(http.statusCode)"
            }
        } catch {
            return error.localizedDescription
        }
        return "Unknown error"
    }
}
