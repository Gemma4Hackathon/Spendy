import Foundation

// MARK: - Shared Gemini HTTP helper
struct GeminiAPI {

    struct Response: Decodable {
        let candidates: [Candidate]
        struct Candidate: Decodable {
            let content: Content
            struct Content: Decodable {
                let parts: [Part]
                struct Part: Decodable {
                    let text: String?
                }
            }
        }
    }

    /// Send a text-only prompt to Gemini and return the raw response text.
    static func textComplete(prompt: String) async throws -> String {
        guard APIConfig.hasAPIKey else {
            throw ServiceError.notImplemented("No Gemini API key. Set it in Profile → Gemini API Key.")
        }
        let urlStr = "\(APIConfig.geminiTextURL)?key=\(APIConfig.geminiAPIKey)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 1024
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.notImplemented("Gemini API error: \(msg)")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text ?? ""
    }

    /// Send a multimodal prompt (text + base64 image) to Gemini Vision.
    static func visionComplete(prompt: String, imageData: Data) async throws -> String {
        guard APIConfig.hasAPIKey else {
            throw ServiceError.notImplemented("No Gemini API key. Set it in Profile → Gemini API Key.")
        }
        let urlStr = "\(APIConfig.geminiVisionURL)?key=\(APIConfig.geminiAPIKey)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let base64 = imageData.base64EncodedString()
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 2048
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.notImplemented("Gemini Vision error: \(msg)")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text ?? ""
    }

    /// Generate an image from a text prompt. Returns raw image Data (PNG/JPEG).
    static func imageGenerate(prompt: String) async throws -> Data {
        guard APIConfig.hasAPIKey else {
            throw ServiceError.notImplemented("No API key. Set it in Profile.")
        }
        let urlStr = "\(APIConfig.geminiImageURL)?key=\(APIConfig.geminiAPIKey)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["responseModalities": ["IMAGE", "TEXT"]]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ServiceError.notImplemented("Image generation error: \(msg)")
        }

        // Find the inlineData image part in the response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            for part in parts {
                if let inline = part["inlineData"] as? [String: String],
                   let b64 = inline["data"],
                   let imageData = Data(base64Encoded: b64) {
                    return imageData
                }
            }
        }
        throw ServiceError.notImplemented("No image found in response")
    }
}
