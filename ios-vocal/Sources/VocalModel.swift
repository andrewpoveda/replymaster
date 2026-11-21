import Foundation
import SwiftUI
import AVFoundation
import Combine

/// The hub. Owns conversation state and wires captions → suggestions → glasses → speech.
///
/// Core loop (v3 design):
/// 1. Partner speaks → caption line + 3 replies sent to glasses.
/// 2. Glasses send `choosing` → phone shows "Dana is replying…".
/// 3. Glasses send `select` (+ optional tone) → phone speaks it; glasses show "Said: …" ≥ 2 s.
/// 4. Glasses send `help` (3 s hold) → phone repeats "I need help" until cancelled.
///
/// Speech only ever starts from a `select` or a local tap — never from captions, reconnects or launch.
@MainActor
final class VocalModel: ObservableObject {
    // Conversation state
    @Published private(set) var mode: Mode = .listening
    @Published private(set) var caption = ""          // latest heard (partial or final)
    @Published private(set) var heard = ""            // last finalised partner utterance
    @Published private(set) var replies: [String] = []
    @Published private(set) var said: String?
    @Published var tone: Tone = .neutral { didSet { publish() } }
    @Published private(set) var results: [RaceResult] = []
    /// Monotonic time the partner last stopped talking, while waiting for an answer (nil = no open question).
    @Published private(set) var questionEndedAt: TimeInterval?
    private var lastPartialAt: TimeInterval?
    @Published var showPartnerScreen = true           // partner overlay during choosing/speaking

    // Settings (persisted)
    @Published var userName: String { didSet { save(userName, "userName") } }
    @Published var glassesHost: String { didSet { save(glassesHost, "glassesHost") } }
    @Published var glassesPort: Int { didSet { save(glassesPort, "glassesPort") } }
    @Published var suggestionURL: String { didSet { save(suggestionURL, "suggestionURL") } }
    @Published var phraseSet: PhraseSet { didSet { save(phraseSet.rawValue, "phraseSet"); publish() } }
    @Published var usePersonalVoice: Bool { didSet { save(usePersonalVoice, "usePersonalVoice"); speech.preferPersonalVoice = usePersonalVoice } }
    @Published var onDeviceOnly: Bool { didSet { save(onDeviceOnly, "onDeviceOnly"); captions.onDeviceOnly = onDeviceOnly } }

    private func save(_ v: Any, _ k: String) { UserDefaults.standard.set(v, forKey: k) }

    let captions = CaptionService()
    let speech = SpeechService()
    let glasses = GlassesLink()

    var quick: [String] { phraseSet.phrases }

    private var rev = 0
    private var lastSnapshot: GlassesSnapshot?
    private var heardRevision = 0
    private var speakStartedAt = Date.distantPast
    private var choosingTimeout: Task<Void, Never>?
    private var publishScheduled = false
    private var observers: [NSObjectProtocol] = []

    private var bag = Set<AnyCancellable>()

    init() {
        let d = UserDefaults.standard
        userName = d.string(forKey: "userName") ?? "Dana"
        glassesHost = d.string(forKey: "glassesHost") ?? ""
        glassesPort = (d.object(forKey: "glassesPort") as? Int) ?? 8765
        suggestionURL = d.string(forKey: "suggestionURL") ?? ""
        phraseSet = PhraseSet(rawValue: d.string(forKey: "phraseSet") ?? "") ?? .everyday
        onDeviceOnly = d.bool(forKey: "onDeviceOnly")
        usePersonalVoice = (d.object(forKey: "usePersonalVoice") as? Bool) ?? true

        captions.onDeviceOnly = onDeviceOnly
        speech.preferPersonalVoice = usePersonalVoice
        captions.onPartial = { [weak self] text in self?.partnerPartial(text) }
        captions.onFinal = { [weak self] text in self?.partnerFinished(text) }
        speech.onReplyFinished = { [weak self] in self?.replyFinished() }
        glasses.onAction = { [weak self] action in self?.handle(action) }

        // Re-publish when sub-service state changes (mic status, etc.)
        captions.objectWillChange.sink { [weak self] in self?.schedulePublish() }.store(in: &bag)
        glasses.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        speech.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        captions.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)

        observeInterruptions()
        if !glassesHost.isEmpty { glasses.connect(host: glassesHost, port: glassesPort) }
        publish()
    }

    // MARK: - Glasses actions

    func handle(_ a: GlassesAction) {
        switch a.action {
        case .choosing:
            startChoosing()
        case .select:
            guard let text = a.text else { return }
            say(text, tone: a.tone ?? tone, source: .glasses)
        case .cancel:
            if mode == .choosing { setMode(.listening) }
        case .help:
            triggerHelp()
        case .help_cancel:
            cancelHelp()
        }
    }

    func startChoosing() {
        guard mode == .listening else { return }
        setMode(.choosing)
        choosingTimeout?.cancel()
        choosingTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, self.mode == .choosing else { return }
            self.setMode(.listening)
        }
    }

    /// Speak a reply. One call → at most one utterance.
    func say(_ text: String, tone t: Tone? = nil, source: ReplySource = .reply) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, mode != .help, mode != .speaking else { return }
        choosingTimeout?.cancel()
        recordRace(text: text, source: source)
        said = text
        speakStartedAt = Date()
        setMode(.speaking)
        captions.pause()
        speech.speak(text, tone: t ?? tone)
    }

    func stopSpeaking() { speech.stop() }

    private func replyFinished() {
        // Glasses show "Said: …" for at least 2 s.
        let remaining = max(0, 2.0 - Date().timeIntervalSince(speakStartedAt))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard let self, self.mode == .speaking else { return }
            self.said = nil
            self.replies = []            // answered; wait for the partner's next line
            self.setMode(.listening)
            try? await Task.sleep(nanoseconds: 300_000_000)   // short cooldown so we don't catch our own tail
            if self.mode != .help { self.captions.resume() }
        }
    }

    // MARK: - Race timing

    private func recordRace(text: String, source: ReplySource) {
        guard source != .sample, let q = questionEndedAt else { return }
        questionEndedAt = nil   // one answer per question
        let secs = ProcessInfo.processInfo.systemUptime - q
        results.append(RaceResult(typed: source == .typed, seconds: secs, text: text))
    }

    var vocalTimes: [Double] { results.filter { !$0.typed }.map(\.seconds) }
    var typedTimes: [Double] { results.filter { $0.typed }.map(\.seconds) }

    func clearResults() { results.removeAll(); questionEndedAt = nil }

    /// Plain-text summary to paste into the deck or form.
    var resultsSummary: String {
        func line(_ name: String, _ t: [Double]) -> String {
            guard let m = t.median else { return "\(name): no trials" }
            return String(format: "\(name): median %.1f s over %d trials (min %.1f, max %.1f)", m, t.count, t.min()!, t.max()!)
        }
        var out = [line("Vocal (pick a reply)", vocalTimes), line("Typing", typedTimes)]
        if let v = vocalTimes.median, let ty = typedTimes.median, v > 0 {
            out.append(String(format: "Vocal was %.1f× faster (question end → reply starts speaking).", ty / v))
        }
        out.append("Measured on iPhone, same questions, timed from the partner's last word to the reply starting.")
        return out.joined(separator: "\n")
    }

    // MARK: - HELP

    func triggerHelp() {
        guard mode != .help else { return }
        choosingTimeout?.cancel()
        said = nil
        setMode(.help)
        captions.pause()
        speech.startHelp()
    }

    func cancelHelp() {
        guard mode == .help else { return }
        speech.stopHelp()
        setMode(.listening)
        captions.resume()
    }

    // MARK: - Captions

    private func partnerPartial(_ text: String) {
        lastPartialAt = ProcessInfo.processInfo.systemUptime
        caption = text
        schedulePublish()
    }

    private func partnerFinished(_ text: String) {
        // The question "ends" at the last word heard, not when the silence timer fires.
        questionEndedAt = lastPartialAt ?? ProcessInfo.processInfo.systemUptime
        lastPartialAt = nil
        caption = text
        heard = text
        heardRevision += 1
        // Don't swap replies out from under the user while they're choosing or speaking.
        guard mode == .listening else { schedulePublish(); return }
        replies = SuggestionService.localReplies(heard: text)
        schedulePublish()
        fetchRemote(for: text, revision: heardRevision)
    }

    private func fetchRemote(for text: String, revision: Int) {
        let svc = SuggestionService(endpoint: URL(string: suggestionURL.trimmingCharacters(in: .whitespaces)), userName: userName)
        guard svc.endpoint != nil else { return }
        let context = captions.lines
        Task { [weak self] in
            guard let r = await svc.remoteReplies(heard: text, context: context) else { return }
            guard let self, revision == self.heardRevision, self.mode == .listening else { return }
            self.replies = r
            self.schedulePublish()
        }
    }

    /// For demos without a partner: pretend the partner said `text`.
    func simulatePartner(_ text: String) { partnerFinished(text) }

    // MARK: - Glasses connection

    func connectGlasses() {
        if glassesHost.isEmpty { glasses.disconnect() } else { glasses.connect(host: glassesHost, port: glassesPort) }
    }

    // MARK: - Snapshot

    private func setMode(_ m: Mode) {
        mode = m
        publish()   // state changes go out immediately
    }

    private func schedulePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        // Coalesce bursts of partial captions (~60 ms).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.publishScheduled = false
            self?.publish()
        }
    }

    var snapshot: GlassesSnapshot {
        GlassesSnapshot(rev: rev, state: mode, caption: caption.tail(70), replies: replies,
                        quick: quick, tone: tone, said: mode == .speaking ? said : nil, mic: captions.status.wire)
    }

    func publish() {
        var s = snapshot
        if let last = lastSnapshot, last.sameContent(as: s) { return }
        rev += 1
        s.rev = rev
        lastSnapshot = s
        glasses.send(s)
    }

    // MARK: - Interruptions (calls, Siri): stop speaking, never auto-replay

    private func observeInterruptions() {
        let o = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.speech.stop() }
        }
        observers.append(o)
    }
}

