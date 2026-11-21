import Foundation
import Network

/// Link to the glasses app (`glasses-hello`, the server). Same transport as Albert's caption receiver:
/// plain TCP on port 8787, one JSON object per line ("\n"), glasses advertised over Bonjour as `_replymaster._tcp`.
/// See docs/PROTOCOL.md.
///
/// - Leave the host empty to auto-discover the glasses; or type the IP shown on the glasses.
/// - Keeps reconnecting while enabled and always re-sends the latest snapshot after (re)connecting.
@MainActor
final class GlassesLink: ObservableObject {
    enum Status: Equatable {
        case off, searching, connecting, connected
        var label: String {
            switch self {
            case .off: return "Glasses off"
            case .searching: return "Looking for glasses…"
            case .connecting: return "Connecting…"
            case .connected: return "Glasses connected"
            }
        }
    }

    static let defaultPort = 8787
    static let bonjourType = "_replymaster._tcp"

    @Published private(set) var status: Status = .off
    @Published private(set) var lastError: String?
    @Published private(set) var endpoint: String = ""

    /// Called on the main actor for every valid action from the glasses.
    var onAction: ((GlassesAction) -> Void)?

    private let queue = DispatchQueue(label: "vocal.glasses-link")
    private var connection: NWConnection?
    private var browser: NWBrowser?
    private var target: NWEndpoint?          // what we connect to (manual host:port or Bonjour service)
    private var manual = false
    private var enabled = false
    private var generation = 0               // invalidates callbacks from old connections
    private var latest: Data?                // last snapshot line, re-sent on connect
    private var inbox = Data()
    private var retryTask: Task<Void, Never>?
    private static let maxLine = 16 * 1024

    /// Connect to a typed IP, or auto-discover when `host` is empty.
    func connect(host: String, port: Int) {
        enabled = true
        teardownConnection()
        stopBrowsing()
        let h = host.trimmingCharacters(in: .whitespaces)
        if h.isEmpty {
            manual = false
            target = nil
            startBrowsing()
        } else {
            guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { lastError = "Bad port"; return }
            manual = true
            target = .hostPort(host: NWEndpoint.Host(h), port: p)
            endpoint = "\(h):\(port)"
            open()
        }
    }

    func disconnect() {
        enabled = false
        retryTask?.cancel(); retryTask = nil
        stopBrowsing()
        teardownConnection()
        status = .off
    }

    func send(_ snapshot: GlassesSnapshot) {
        guard var data = try? JSONEncoder().encode(snapshot) else { return }
        data.append(0x0A)
        latest = data
        if status == .connected { transmit(data) }
    }

    /// Send a spoken reply as audio for the glasses to play (one line: base64 16-bit mono PCM).
    func sendAudio(pcm: Data, rate: Int) {
        guard status == .connected else { return }
        let obj: [String: Any] = ["type": "audio", "rate": rate, "pcm16": pcm.base64EncodedString()]
        guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        transmit(data)
    }

    // MARK: - Discovery

    private func startBrowsing() {
        status = .searching
        endpoint = ""
        let b = NWBrowser(for: .bonjour(type: Self.bonjourType, domain: nil), using: .tcp)
        browser = b
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let first = results.first else { return }
            Task { @MainActor in
                guard let self, self.enabled, !self.manual, self.connection == nil else { return }
                if case .service(let name, _, _, _) = first.endpoint { self.endpoint = name }
                self.target = first.endpoint
                self.open()
            }
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                Task { @MainActor in self?.lastError = "Discovery failed: \(err.localizedDescription). Enter the IP shown on the glasses." }
            }
        }
        b.start(queue: queue)
    }

    private func stopBrowsing() {
        browser?.cancel(); browser = nil
    }

    // MARK: - Connection

    private func open() {
        teardownConnection()
        guard enabled, let target else { return }
        generation += 1
        let gen = generation
        status = .connecting
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 2
            tcp.keepaliveInterval = 1
            tcp.keepaliveCount = 3
            tcp.noDelay = true
            tcp.connectionTimeout = 4
        }
        let c = NWConnection(to: target, using: params)
        connection = c
        inbox.removeAll()
        c.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state, gen) }
        }
        c.start(queue: queue)
    }

    private func handle(_ state: NWConnection.State, _ gen: Int) {
        guard gen == generation else { return }
        switch state {
        case .ready:
            status = .connected
            lastError = nil
            if case .hostPort(let h, let p) = connection?.currentPath?.remoteEndpoint { endpoint = "\(h):\(p)" }
            receive(gen)
            if let latest { transmit(latest) }
        case .waiting(let err):
            fail(gen, err.localizedDescription)
        case .failed(let err):
            fail(gen, err.localizedDescription)
        case .cancelled:
            break
        default:
            break
        }
    }

    private func receive(_ gen: Int) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if let data, !data.isEmpty { self.consume(data) }
                if let err { self.fail(gen, err.localizedDescription); return }
                if done { self.fail(gen, "Glasses closed the connection"); return }
                self.receive(gen)
            }
        }
    }

    /// Split the byte stream into lines and decode each as a glasses action.
    private func consume(_ data: Data) {
        inbox.append(data)
        while let nl = inbox.firstIndex(of: 0x0A) {
            let line = inbox[inbox.startIndex..<nl]
            inbox.removeSubrange(inbox.startIndex...nl)
            guard !line.isEmpty, line.count <= Self.maxLine,
                  let action = try? JSONDecoder().decode(GlassesAction.self, from: Data(line)) else { continue }
            onAction?(action)
        }
        if inbox.count > Self.maxLine { inbox.removeAll() }   // garbage without newlines
    }

    private func transmit(_ data: Data) {
        let gen = generation
        connection?.send(content: data, completion: .contentProcessed { [weak self] err in
            guard let err else { return }
            Task { @MainActor in self?.fail(gen, err.localizedDescription) }
        })
    }

    private func fail(_ gen: Int, _ reason: String) {
        guard gen == generation, enabled else { return }
        lastError = reason
        teardownConnection()
        status = manual ? .connecting : .searching
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self, self.enabled else { return }
            if self.target != nil { self.open() } else if self.browser == nil { self.startBrowsing() }
        }
    }

    private func teardownConnection() {
        generation += 1
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
}
