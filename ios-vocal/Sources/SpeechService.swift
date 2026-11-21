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

    /// Set when iOS refused to render the Personal Voice to a buffer (`write`), so glasses playback
    /// falls back to the phone speaker. Cleared when the voice changes.
    @Published private(set) var personalVoiceRenderBlocked = false

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

    // MARK: My recordings — the user's own recorded clips for exact phrases (played instead of TTS).
    @Published private(set) var recordingPhrase: String?
    @Published private(set) var recordingsVersion = 0
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private static let clipRate = 22050.0

    private static var clipsDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("recordings")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func clipURL(_ text: String) -> URL {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " }.replacingOccurrences(of: " ", with: "_")
        return clipsDir.appendingPathComponent((key.isEmpty ? "clip" : key) + ".wav")
    }
    func hasRecording(_ text: String) -> Bool { FileManager.default.fileExists(atPath: Self.clipURL(text).path) }

    func startRecording(_ text: String) {
        guard recordingPhrase == nil, !speaking, !helpActive else { return }
        AudioSessionManager.shared.activate()
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.clipRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        do {
            let r = try AVAudioRecorder(url: Self.clipURL(text), settings: settings)
            guard r.record(forDuration: 10) else { return }
            recorder = r
            recordingPhrase = text
        } catch { print("Record error: \(error)") }
    }
    func stopRecording() {
        recorder?.stop(); recorder = nil
        recordingPhrase = nil
        recordingsVersion += 1
    }
    func deleteRecording(_ text: String) {
        try? FileManager.default.removeItem(at: Self.clipURL(text))
        recordingsVersion += 1
    }

    /// Mono 16-bit PCM of the user's clip for `text`, if recorded.
    func clipPCM(_ text: String) -> (pcm: Data, rate: Int)? {
        guard hasRecording(text),
              let f = try? AVAudioFile(forReading: Self.clipURL(text), commonFormat: .pcmFormatInt16, interleaved: true),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: buf)) != nil, buf.frameLength > 0, let i16 = buf.int16ChannelData?[0] else { return nil }
        let ch = Int(f.processingFormat.channelCount)
        let n = Int(buf.frameLength)
        if ch == 1 { return (Data(bytes: i16, count: n * 2), Int(f.processingFormat.sampleRate)) }
        var mono = [Int16](repeating: 0, count: n)
        for i in 0..<n { mono[i] = i16[i * ch] }
        return (mono.withUnsafeBytes { Data($0) }, Int(f.processingFormat.sampleRate))
    }

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
        guard AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .notDetermined else { refreshVoice(); return }
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
            if voice?.identifier != personal.identifier { personalVoiceRenderBlocked = false }
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
    /// Returns nil if iOS gives no audio (e.g. it refuses to render a Personal Voice) or takes too long;
    /// the caller then speaks on the phone so a reply never goes silent.
    func renderPCM(_ text: String, tone: Tone) async -> (pcm: Data, rate: Int)? {
        if let clip = clipPCM(text) { return clip }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * tone.rateFactor)
        u.pitchMultiplier = tone.pitch
        let personal = usingPersonalVoice
        let synth = renderSynth
        let result: (pcm: Data, rate: Int)? = await withCheckedContinuation { cont in
            var out = Data()
            var rate = 22050
            var done = false
            let finish: () -> Void = {
                guard !done else { return }
                done = true
                cont.resume(returning: out.isEmpty ? nil : (out, rate))
            }
            // Safety net: if iOS never ends the stream, give up and let the phone speak.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if !done { synth.stopSpeaking(at: .immediate); out = Data(); finish() }
            }
            synth.write(u) { buffer in
                // Copy samples here (iOS may reuse the buffer), then hand them to the main actor.
                var chunk: Data?
                var chunkRate = 22050
                if let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 {
                    chunkRate = Int(pcm.format.sampleRate)
                    let n = Int(pcm.frameLength)
                    if let f = pcm.floatChannelData?[0] {
                        var samples = [Int16](repeating: 0, count: n)
                        for i in 0..<n { samples[i] = Int16(max(-1, min(1, f[i])) * 32767) }
                        chunk = samples.withUnsafeBytes { Data($0) }
                    } else if let i16 = pcm.int16ChannelData?[0] {
                        chunk = Data(bytes: i16, count: n * 2)
                    }
                }
                DispatchQueue.main.async {
                    guard !done else { return }
                    guard let chunk else { finish(); return }   // empty buffer = end of stream
                    rate = chunkRate
                    out.append(chunk)
                }
            }
        }
        if personal { personalVoiceRenderBlocked = (result == nil) }
        return result
    }

    /// Speak exactly `text`. Ignored while already speaking or during HELP (one press = one utterance).
    func speak(_ text: String, tone: Tone) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !speaking, !helpActive else { return }
        AudioSessionManager.shared.activate()
        if hasRecording(t), let p = try? AVAudioPlayer(contentsOf: Self.clipURL(t)) {
            p.delegate = self
            p.volume = 1.0
            if p.play() { player = p; speaking = true; return }
        }
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
        if let p = player { p.stop(); clipFinished(p); return }
        synth.stopSpeaking(at: .immediate)   // delegate didCancel → finish
    }

    func startHelp() {
        guard !helpActive else { return }
        AudioSessionManager.shared.activate()
        helpActive = true
        if let p = player { p.stop(); player = nil }
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

    fileprivate func clipFinished(_ p: AVAudioPlayer) {
        guard p === player else { return }
        player = nil
        speaking = false
        onReplyFinished?()
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

extension SpeechService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.clipFinished(p) }
    }
}
