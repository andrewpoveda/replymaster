import SwiftUI
import Speech
import AVFoundation
import Network

final class CaptionLink: ObservableObject {
    @Published var host = ""
    @Published private(set) var status = "Searching for glasses…"

    private var connection: NWConnection?
    private var browser: NWBrowser?
    private var resolver: NWConnection?
    private var discoveredEndpoint: NWEndpoint?
    private let queue = DispatchQueue(label: "com.replymaster.caption-link")

    init() { discover() }

    private func discover() {
        let browser = NWBrowser(for: .bonjour(type: "_replymaster._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let result = results.first else { return }
            DispatchQueue.main.async {
                self?.discoveredEndpoint = result.endpoint
                if self?.connection == nil { self?.status = "Ready to connect" }
            }
            self?.resolve(result.endpoint)
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                DispatchQueue.main.async { self?.status = "Glasses not found" }
            }
        }
        browser.start(queue: queue)
    }

    private func resolve(_ endpoint: NWEndpoint) {
        resolver?.cancel()
        let resolver = NWConnection(to: endpoint, using: .tcp)
        self.resolver = resolver
        resolver.stateUpdateHandler = { [weak self, weak resolver] state in
            guard state == .ready else { return }
            if case .hostPort(let host, _) = resolver?.currentPath?.remoteEndpoint {
                DispatchQueue.main.async { self?.host = host.debugDescription }
            }
            resolver?.cancel()
        }
        resolver.start(queue: queue)
    }

    func connect() {
        disconnect()
        guard let port = NWEndpoint.Port(rawValue: 8787) else { return }
        let manualHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint: NWEndpoint = manualHost.isEmpty
            ? (discoveredEndpoint ?? .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: port))
            : .hostPort(host: NWEndpoint.Host(manualHost), port: port)
        let newConnection = NWConnection(to: endpoint, using: .tcp)
        connection = newConnection
        status = "Connecting…"
        newConnection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready: self?.status = "Connected"
                case .failed(let error): self?.status = "Connection failed: \(error.localizedDescription)"
                case .cancelled: self?.status = "Not connected"
                default: break
                }
            }
        }
        newConnection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        status = "Not connected"
    }

    func sendCaption(_ text: String, isFinal: Bool) {
        guard let connection, !text.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: [
                "type": "caption", "text": text, "final": isFinal
              ]) else { return }
        var line = json
        line.append(0x0A)
        connection.send(content: line, completion: .contentProcessed { _ in })
    }
}

final class Captioner: ObservableObject {
    @Published var text = "Tap Start and speak"
    @Published var running = false
    @Published var latencyMs: Int? = nil
    let link: CaptionLink

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startedAt = Date()
    private var gotFirst = false

    init(link: CaptionLink) { self.link = link }

    func toggle() {
        if running { stop() } else { requestPermissions() }
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    if status == .authorized && allowed { self.start() }
                    else { self.text = "Permission denied" }
                }
            }
        }
    }

    private func start() {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement)
            try audio.setActive(true)
            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true { newRequest.requiresOnDeviceRecognition = true }
            request = newRequest
            gotFirst = false
            startedAt = Date()
            text = "Listening…"
            task = recognizer?.recognitionTask(with: newRequest) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    DispatchQueue.main.async {
                        if !self.gotFirst {
                            self.gotFirst = true
                            self.latencyMs = Int(Date().timeIntervalSince(self.startedAt) * 1000)
                        }
                        self.text = result.bestTranscription.formattedString
                        self.link.sendCaption(self.text, isFinal: result.isFinal)
                    }
                }
                if error != nil || result?.isFinal == true {
                    DispatchQueue.main.async { if self.running { self.restart() } }
                }
            }
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
                buffer, _ in newRequest.append(buffer)
            }
            engine.prepare()
            try engine.start()
            running = true
        } catch { text = "Error: \(error.localizedDescription)" }
    }

    private func restart() { teardown(); start() }
    private func teardown() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    func stop() {
        running = false
        teardown()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        text = "Stopped"
    }
}

@main
struct LiveCaptionsApp: App {
    @StateObject private var link: CaptionLink
    @StateObject private var captioner: Captioner
    @StateObject private var camera = CameraInsight()
    @State private var size: Double = 44
    @State private var showingCamera = false

    init() {
        let link = CaptionLink()
        _link = StateObject(wrappedValue: link)
        _captioner = StateObject(wrappedValue: Captioner(link: link))
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                HStack {
                    TextField("Glasses IP address", text: $link.host)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                    Button(link.status == "Connected" ? "Disconnect" : "Connect") {
                        link.status == "Connected" ? link.disconnect() : link.connect()
                    }
                }
                Text("Glasses: \(link.status)")
                    .font(.caption)
                    .foregroundColor(link.status == "Connected" ? .green : .gray)
                Button("Camera: Capture or Select Image") { showingCamera = true }
                    .font(.headline)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .buttonStyle(.plain)
                if !camera.result.isEmpty {
                    Text(camera.result)
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4)
                }
                Text(camera.status)
                    .font(.caption)
                    .foregroundColor(.gray)
                ScrollView {
                    Text(captioner.text)
                        .font(.system(size: size, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let latency = captioner.latencyMs {
                    Text("first-word latency: \(latency) ms")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Slider(value: $size, in: 20...90)
                Button(captioner.running ? "Stop" : "Start") { captioner.toggle() }
                    .font(.title2.bold())
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(captioner.running ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .buttonStyle(.plain)
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .sheet(isPresented: $showingCamera) {
                CameraPicker { image in
                    showingCamera = false
                    camera.process(image: image)
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void

        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { }
    }
}
