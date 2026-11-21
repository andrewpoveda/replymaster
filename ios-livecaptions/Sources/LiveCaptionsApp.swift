import SwiftUI
import Speech
import AVFoundation

final class Captioner: ObservableObject {
    @Published var text = "Tap Start and speak"
    @Published var running = false
    @Published var latencyMs: Int? = nil
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startedAt = Date()
    private var gotFirst = false

    func toggle() { running ? stop() : request_permissions() }

    private func request_permissions() {
        SFSpeechRecognizer.requestAuthorization { s in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                DispatchQueue.main.async {
                    if s == .authorized && ok { self.start() } else { self.text = "Permission denied" }
                }
            }
        }
    }

    private func start() {
        do {
            let a = AVAudioSession.sharedInstance()
            try a.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try a.setActive(true)
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true { r.requiresOnDeviceRecognition = true }
            request = r
            gotFirst = false; startedAt = Date(); text = "Listening…"
            task = recognizer?.recognitionTask(with: r) { [weak self] res, err in
                guard let self = self else { return }
                if let res = res {
                    DispatchQueue.main.async {
                        if !self.gotFirst { self.gotFirst = true; self.latencyMs = Int(Date().timeIntervalSince(self.startedAt) * 1000) }
                        self.text = res.bestTranscription.formattedString
                    }
                }
                if err != nil || res?.isFinal == true { DispatchQueue.main.async { if self.running { self.restart() } } }
            }
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in r.append(buf) }
            engine.prepare(); try engine.start()
            running = true
        } catch { text = "Error: \(error.localizedDescription)" }
    }

    private func restart() { teardown(); start() }
    private func teardown() {
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel(); request = nil; task = nil
    }
    func stop() { teardown(); running = false }
}

@main
struct LiveCaptionsApp: App {
    @StateObject private var c = Captioner()
    @State private var size: Double = 44
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                ScrollView {
                    Text(c.text).font(.system(size: size, weight: .bold))
                        .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let l = c.latencyMs { Text("first-word latency: \(l) ms").font(.caption).foregroundColor(.gray) }
                Slider(value: $size, in: 20...90)
                Button(c.running ? "Stop" : "Start") { c.toggle() }
                    .font(.title2.bold()).padding().frame(maxWidth: .infinity)
                    .background(c.running ? Color.red : Color.green).foregroundColor(.white).cornerRadius(12)
            }
            .padding().background(Color.black.ignoresSafeArea())
        }
    }
}
