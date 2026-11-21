import Foundation
import Speech
import AVFoundation

/// Live captions from the iPhone mic. Evolved from ios-livecaptions:
/// - each partner utterance is one *segment*; partials revise the current segment instead of appending
/// - a segment is finalised after `silenceSeconds` with no change (or when the recogniser says final),
///   then recognition restarts so the next segment starts empty
/// - `pause()` while the phone is speaking so Vocal doesn't caption itself
@MainActor
final class CaptionService: ObservableObject {
    enum Status: Equatable {
        case off, listening, paused, denied, unavailable(String)
        var wire: String {
            switch self {
            case .off: return "off"
            case .listening: return "listening"
            case .paused: return "paused"
            case .denied: return "denied"
            case .unavailable: return "unavailable"
            }
        }
        var label: String {
            switch self {
            case .off: return "Mic off"
            case .listening: return "Listening"
            case .paused: return "Paused while speaking"
            case .denied: return "Mic permission denied"
            case .unavailable(let why): return why
            }
        }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var partial = ""
    @Published private(set) var lines: [String] = []      // finalised segments, newest last (max 10)
    @Published private(set) var onDevice = false

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var silenceSeconds: Double = 1.0
    var onDeviceOnly = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var silenceTimer: Timer?
    private var wanted = false           // user wants captions on
    private var pausedForSpeech = false

    var isOn: Bool { wanted }

    func toggle() { wanted ? stop() : start() }

    func start() {
        wanted = true
        SFSpeechRecognizer.requestAuthorization { s in
            AVAudioApplication.requestRecordPermission { ok in
                Task { @MainActor in
                    guard self.wanted else { return }
                    guard s == .authorized, ok else { self.status = .denied; self.wanted = false; return }
                    if !self.pausedForSpeech { self.startEngine() } else { self.status = .paused }
                }
            }
        }
    }

    func stop() {
        wanted = false
        finalizeSegment()
        stopEngine()
        status = .off
    }

    /// Pause recognition (phone is speaking). Drops the in-flight partial rather than captioning our own voice.
    func pause() {
        pausedForSpeech = true
        guard wanted else { return }
        partial = ""
        stopEngine()
        status = .paused
    }

    func resume() {
        pausedForSpeech = false
        guard wanted, status == .paused else { return }
        startEngine()
    }

    func clearTranscript() { lines.removeAll(); partial = "" }

    // MARK: - Engine

    private func startEngine() {
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Speech recognition unavailable"); return
        }
        if onDeviceOnly && !recognizer.supportsOnDeviceRecognition {
            status = .unavailable("On-device captions not supported"); return
        }
        do {
            AudioSessionManager.shared.activate()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { status = .unavailable("No microphone input"); return }
            input.removeTap(onBus: 0)
            let box = self.box
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in box.append(buf) }
            engine.prepare()
            try engine.start()
            startTask()
            status = .listening
        } catch {
            status = .unavailable("Mic error: \(error.localizedDescription)")
        }
    }

    private func stopEngine() {
        silenceTimer?.invalidate(); silenceTimer = nil
        generation += 1
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        box.swap(nil)?.endAudio()
        task?.cancel(); task = nil
    }

    private func startTask() {
        guard let recognizer else { return }
        generation += 1
        let gen = generation
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.taskHint = .dictation
        let local = recognizer.supportsOnDeviceRecognition
        r.requiresOnDeviceRecognition = local      // prefer on device; server only when the device can't (and allowed)
        onDevice = local
        box.swap(r)?.endAudio()
        task?.cancel()
        task = recognizer.recognitionTask(with: r) { [weak self] res, err in
            let text = res?.bestTranscription.formattedString
            let final = res?.isFinal ?? false
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if let text, !text.isEmpty, text != self.partial {
                    self.partial = text
                    self.onPartial?(text)
                    self.armSilenceTimer()
                }
                if final || err != nil {
                    self.finalizeSegment()
                    guard self.status == .listening else { return }
                    if err != nil {
                        // Recogniser errors (e.g. long silence) — back off briefly so we never hot-loop.
                        self.generation += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if self.status == .listening { self.startTask() }
                        }
                    } else {
                        self.startTask()
                    }
                }
            }
        }
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.status == .listening else { return }
                self.finalizeSegment()
                self.startTask()   // fresh segment; avoids re-reporting the old sentence
            }
        }
    }

    private func finalizeSegment() {
        silenceTimer?.invalidate(); silenceTimer = nil
        let t = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        guard !t.isEmpty else { return }
        lines.append(t)
        if lines.count > 10 { lines.removeFirst(lines.count - 10) }
        onFinal?(t)
    }
}

/// Thread-safe holder so the audio tap (audio thread) can feed whichever request is current.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func append(_ b: AVAudioPCMBuffer) { lock.lock(); request?.append(b); lock.unlock() }
    @discardableResult
    func swap(_ r: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        let old = request; request = r; return old
    }
}
