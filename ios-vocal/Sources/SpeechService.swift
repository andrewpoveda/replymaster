import Foundation
import AVFoundation

/// One shared audio session: record for captions, play replies loudly through the iPhone speaker (partner-facing).
@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private var active = false

    func activate() {
        guard !active else { return }
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try s.setActive(true)
            active = true
        } catch {
            print("Audio session error: \(error)")
        }
    }
}

/// Speaks replies in a tone, and runs the HELP alarm ("I need help" on repeat at full volume until cancelled).
@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var speaking = false
    @Published private(set) var helpActive = false
    @Published private(set) var voiceName = ""
    @Published private(set) var usingPersonalVoice = false
    @Published private(set) var personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus

    /// User preference: speak replies in their Apple Personal Voice when one is available and authorized.
    var preferPersonalVoice = true { didSet { refreshVoice() } }

    /// Called once per finished or cancelled reply (not for HELP repeats).
    var onReplyFinished: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var replyUtterance: AVSpeechUtterance?
    private var helpUtterance: AVSpeechUtterance?
    /// Voice for replies (Personal Voice if available, else system).
    private var voice: AVSpeechSynthesisVoice?
    /// HELP always uses the clear system voice so the alarm is reliable and recognisable.
    private let systemVoice: AVSpeechSynthesisVoice?

    static let helpText = "I need help."

    override init() {
        // Best downloaded en-US voice: premium > enhanced > default.
        let en = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        systemVoice = en.first { $0.quality == .premium } ?? en.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        super.init()
        synth.delegate = self
        refreshVoice()
    }

    /// Ask iOS for permission to use the user's Personal Voice. Shows the system prompt once.
    func requestPersonalVoice() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
            Task { @MainActor in
                self.personalVoiceStatus = status
                self.refreshVoice()
            }
        }
    }

    /// Re-pick the reply voice (call on launch and when the app returns to the foreground —
    /// the user may have just finished creating a Personal Voice in Settings).
    func refreshVoice() {
        personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        let personal = personalVoiceStatus == .authorized
            ? AVSpeechSynthesisVoice.speechVoices().first { $0.voiceTraits.contains(.isPersonalVoice) }
            : nil
        if preferPersonalVoice, let personal {
            voice = personal
            usingPersonalVoice = true
            voiceName = "\(personal.name) (Personal Voice)"
        } else {
            voice = systemVoice
            usingPersonalVoice = false
            voiceName = systemVoice.map { "\($0.name) (\($0.quality == .default ? "default" : $0.quality == .enhanced ? "enhanced" : "premium"))" } ?? "System"
        }
    }

    private let renderSynth = AVSpeechSynthesizer()

    /// Render `text` in the reply voice + tone to mono 16-bit PCM (for playback on the glasses).
    func renderPCM(_ text: String, tone: Tone) async -> (pcm: Data, rate: Int)? {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * tone.rateFactor)
        u.pitchMultiplier = tone.pitch
        return await withCheckedContinuation { cont in
            var out = Data()
            var rate = 22050
            var done = false
            renderSynth.write(u) { buffer in
                guard !done else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    done = true
                    cont.resume(returning: out.isEmpty ? nil : (out, rate))
                    return
                }
                rate = Int(pcm.format.sampleRate)
                let n = Int(pcm.frameLength)
                if let f = pcm.floatChannelData?[0] {
                    var samples = [Int16](repeating: 0, count: n)
                    for i in 0..<n { samples[i] = Int16(max(-1, min(1, f[i])) * 32767) }
                    samples.withUnsafeBytes { out.append(contentsOf: $0) }
                } else if let i16 = pcm.int16ChannelData?[0] {
                    out.append(Data(bytes: i16, count: n * 2))
                }
            }
        }
    }

    /// Speak exactly `text`. Ignored while already speaking or during HELP (one press = one utterance).
    func speak(_ text: String, tone: Tone) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !speaking, !helpActive else { return }
        AudioSessionManager.shared.activate()
        let u = AVSpeechUtterance(string: t)
        u.voice = voice
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * tone.rateFactor)
        u.pitchMultiplier = tone.pitch
        u.volume = 1.0
        replyUtterance = u
        speaking = true
        synth.speak(u)
    }

    func stop() {
        guard speaking else { return }
        synth.stopSpeaking(at: .immediate)   // delegate didCancel → finish
    }

    func startHelp() {
        guard !helpActive else { return }
        AudioSessionManager.shared.activate()
        helpActive = true
        if speaking { replyUtterance = nil; speaking = false; synth.stopSpeaking(at: .immediate); onReplyFinished?() }
        speakHelp()
    }

    func stopHelp() {
        guard helpActive else { return }
        helpActive = false
        synth.stopSpeaking(at: .immediate)
    }

    private func speakHelp() {
        guard helpActive else { return }
        let u = AVSpeechUtterance(string: Self.helpText)
        u.voice = systemVoice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        u.pitchMultiplier = 1.1
        u.volume = 1.0
        u.postUtteranceDelay = 0.6
        helpUtterance = u
        synth.speak(u)
    }

    fileprivate func finished(_ u: AVSpeechUtterance) {
        if u === replyUtterance {
            replyUtterance = nil
            speaking = false
            onReplyFinished?()
        } else if u === helpUtterance, helpActive {
            speakHelp()
        }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.finished(u) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.finished(u) }
    }
}
