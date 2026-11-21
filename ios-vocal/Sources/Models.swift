import Foundation
import AVFoundation

/// Voice tone for a reply. Changes rate and pitch only (system voice).
enum Tone: String, CaseIterable, Codable, Identifiable {
    case neutral, warm, firm, joking
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Multipliers on AVSpeechUtteranceDefaultSpeechRate and pitch 1.0.
    var rateFactor: Float {
        switch self {
        case .neutral: return 1.0
        case .warm: return 0.90
        case .firm: return 0.94
        case .joking: return 1.10
        }
    }
    var pitch: Float {
        switch self {
        case .neutral: return 1.0
        case .warm: return 1.12
        case .firm: return 0.82
        case .joking: return 1.28
        }
    }
}

/// Top-level conversation state shared with the glasses.
enum Mode: String, Codable {
    case listening, choosing, speaking, help
}

/// Where a spoken reply plays.
enum SpeakOn: String, CaseIterable, Identifiable, Codable {
    case phone, glasses, both
    var id: String { rawValue }
    var label: String { self == .phone ? "iPhone" : self == .glasses ? "Glasses" : "Both" }
}

enum PhraseSet: String, CaseIterable, Identifiable {
    case everyday, medical
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var phrases: [String] {
        switch self {
        case .everyday: return ["Yes", "No", "Wait", "Repeat please", "Thank you", "Haha"]
        case .medical: return ["I understand you", "Give me time", "Yes", "No", "It hurts", "Please talk to me"]
        }
    }
}

// MARK: - Wire messages (see docs/PROTOCOL.md)

/// glasses → iPhone
struct GlassesAction: Decodable, Equatable {
    enum Kind: String, Decodable { case choosing, select, cancel, help, help_cancel }
    let action: Kind
    let text: String?
    let tone: Tone?

    init(action: Kind, text: String? = nil, tone: Tone? = nil) {
        self.action = action; self.text = text; self.tone = tone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(Kind.self, forKey: .action)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        // Unknown tone strings fall back to nil instead of failing the whole message.
        tone = (try? c.decodeIfPresent(String.self, forKey: .tone)).flatMap { $0.flatMap(Tone.init(rawValue:)) }
    }
    private enum CodingKeys: String, CodingKey { case action, text, tone }
}

/// iPhone → glasses: full snapshot of what the glasses should show, sent as one JSON line.
/// `type`/`text`/`final` match Albert's original caption receiver, so even that receiver shows something sensible:
/// `text` is a ready-to-draw rendering of the whole glasses screen. Newer receivers use the structured fields.
struct GlassesSnapshot: Encodable, Equatable {
    var type = "caption"
    var text: String
    var final: Bool
    var rev: Int
    var state: Mode
    var caption: String
    var replies: [String]
    var quick: [String]
    var tones: [String] = Tone.allCases.map(\.rawValue)
    var tone: Tone
    var said: String?
    var mic: String
    var speakOn: SpeakOn = .phone

    /// Content equality ignoring `rev`, so we only bump rev on real changes.
    func sameContent(as o: GlassesSnapshot) -> Bool {
        var a = self; a.rev = 0
        var b = o; b.rev = 0
        return a == b
    }

    /// Plain-text rendering of the v3 glasses screen (for simple text receivers).
    static func render(state: Mode, caption: String, replies: [String], quick: [String], said: String?) -> String {
        switch state {
        case .help: return "HELP SENT"
        case .speaking: return "Said: \(said ?? "")"
        case .listening, .choosing:
            var lines: [String] = []
            lines.append(caption.isEmpty ? "…" : "\u{201C}\(caption)\u{201D}")
            if !replies.isEmpty { lines.append(""); lines += replies.enumerated().map { "\($0.offset + 1). \($0.element)" } }
            lines.append("")
            lines.append(quick.joined(separator: " · "))
            return lines.joined(separator: "\n")
        }
    }
}

extension String {
    /// Last `max` characters, cut at a word boundary, with a leading ellipsis — for the one-line glasses caption.
    func tail(_ max: Int) -> String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        let cut = String(t.suffix(max))
        if let sp = cut.firstIndex(of: " ") { return "…" + cut[cut.index(after: sp)...] }
        return "…" + cut
    }
}

// MARK: - Question-to-answer race (pitch timing)

/// Where a spoken reply came from. Everything except `.typed` counts as "Vocal" in the race.
enum ReplySource { case reply, quick, glasses, typed, sample }

struct RaceResult: Identifiable, Equatable {
    let id = UUID()
    let typed: Bool          // true = typed on the keyboard, false = picked in Vocal
    let seconds: Double      // partner stopped talking → reply started speaking
    let text: String
}

extension Array where Element == Double {
    var median: Double? {
        guard !isEmpty else { return nil }
        let s = sorted(); let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }
}
