import Foundation

/// Produces three short context replies for what the partner just said.
///
/// - `localReplies` is instant and offline (keyword rules), so the glasses always have something within ~0 ms.
/// - If a suggestion URL is configured (AI dev's endpoint), `remoteReplies` asks it with a 1.5 s budget.
///
/// Remote contract (POST, JSON):
///   request  {"heard": "Are you ready to order?", "context": ["…earlier lines…"], "user": "Dana", "max_words": 8}
///   response {"replies": ["One iced latte, please", "Can I have a minute?", "What do you recommend?"]}
struct SuggestionService {
    var endpoint: URL?
    var userName: String = "Dana"
    var timeout: TimeInterval = 1.5

    func remoteReplies(heard: String, context: [String]) async -> [String]? {
        guard let endpoint else { return nil }
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["heard": heard, "context": Array(context.suffix(6)), "user": userName, "max_words": 8]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct R: Decodable { let replies: [String] }
            let r = try JSONDecoder().decode(R.self, from: data)
            let clean = r.replies
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 80 }
            return clean.isEmpty ? nil : Array(clean.prefix(3))
        } catch {
            return nil
        }
    }

    /// Instant keyword-based replies. Always returns exactly three.
    static func localReplies(heard raw: String) -> [String] {
        let h = raw.lowercased()
        func has(_ words: String...) -> Bool { words.contains { h.contains($0) } }

        if has("pain", "hurt", "one to ten", "1 to 10", "scale") {
            return ["About a 3", "About a 6", "It's an 8, it's bad"]
        }
        if has("order", "get for you", "drink", "coffee", "what can i get", "what would you like", "ready to") {
            return ["One iced latte, please", "Can I have a minute?", "What do you recommend?"]
        }
        if has("name") {
            return ["It's Dana", "Dana, D-A-N-A", "Can you repeat that?"]
        }
        if has("how are you", "how's it going", "how are things", "how do you feel", "feeling") {
            return ["I'm doing well, thanks", "A bit tired today", "Not great, honestly"]
        }
        if has("size", "small", "medium", "large") {
            return ["Medium, please", "Large, please", "Small is fine"]
        }
        if has("anything else", "something else") {
            return ["That's all, thanks", "Yes, one more thing", "Let me think"]
        }
        if has("card", "cash", "pay", "total") {
            return ["Card, please", "Here you go", "Can I tap my phone?"]
        }
        if has("understand", "make sense", "any questions", "questions") {
            return ["I understand", "Can you explain again?", "I have a question"]
        }
        if has("medication", "medicine", "pills", "taking") {
            return ["Yes, every day", "I missed some doses", "Can you write it down?"]
        }
        if has("when", "what time") {
            return ["Later today", "Tomorrow works", "I'm not sure yet"]
        }
        let firstWord = h.split(separator: " ").first.map(String.init) ?? ""
        let yesNoStarters: Set = ["do", "does", "did", "is", "are", "was", "can", "could", "would", "will", "should", "have", "want"]
        if h.hasSuffix("?") || yesNoStarters.contains(firstWord) {
            return ["Yes, please", "No, thank you", "I'm not sure"]
        }
        return ["Sounds good", "Could you say that again?", "Give me a moment"]
    }
}
