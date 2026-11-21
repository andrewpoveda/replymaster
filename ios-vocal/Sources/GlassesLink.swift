import Foundation

/// WebSocket client to the glasses app (the glasses are the server; see docs/PROTOCOL.md).
/// Keeps reconnecting while `connect` is active and always re-sends the latest snapshot after (re)connecting.
@MainActor
final class GlassesLink: ObservableObject {
    enum Status: Equatable {
        case off, connecting, connected
        var label: String {
            switch self {
            case .off: return "Glasses off"
            case .connecting: return "Connecting…"
            case .connected: return "Glasses connected"
            }
        }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var lastError: String?
    @Published private(set) var endpoint: String = ""

    /// Called on the main actor for every valid action from the glasses.
    var onAction: ((GlassesAction) -> Void)?

    private let session = URLSession(configuration: .ephemeral)
    private var task: URLSessionWebSocketTask?
    private var url: URL?
    private var generation = 0           // invalidates callbacks from old sockets
    private var latest: Data?            // last snapshot, re-sent on connect
    private var pingTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private static let maxInbound = 16 * 1024

    func connect(host: String, port: Int) {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, let u = URL(string: "ws://\(h):\(port)/") else {
            lastError = "Enter the glasses IP address"; return
        }
        url = u
        endpoint = "\(h):\(port)"
        open()
    }

    func disconnect() {
        url = nil
        teardown()
        status = .off
    }

    func send(_ snapshot: GlassesSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        latest = data
        if status == .connected { transmit(data) }
    }

    // MARK: - Internals

    private func open() {
        teardown()
        guard let url else { return }
        generation += 1
        let gen = generation
        status = .connecting
        let t = session.webSocketTask(with: url)
        t.maximumMessageSize = Self.maxInbound
        task = t
        t.resume()
        receive(gen)
        // A successful ping is our "open" signal (URLSessionWebSocketTask has no open callback without a delegate).
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.ping(gen)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func ping(_ gen: Int) async {
        guard let task, gen == generation else { return }
        let ok: Bool = await withCheckedContinuation { cont in
            task.sendPing { err in cont.resume(returning: err == nil) }
        }
        guard gen == generation else { return }
        if ok {
            if status != .connected {
                status = .connected
                lastError = nil
                if let latest { transmit(latest) }
            }
        } else {
            fail(gen, "No answer from glasses at \(endpoint)")
        }
    }

    private func receive(_ gen: Int) {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch result {
                case .success(let msg):
                    self.handle(msg)
                    self.receive(gen)
                case .failure(let err):
                    self.fail(gen, err.localizedDescription)
                }
            }
        }
    }

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        let data: Data
        switch msg {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard data.count <= Self.maxInbound,
              let action = try? JSONDecoder().decode(GlassesAction.self, from: data) else { return }
        onAction?(action)
    }

    private func transmit(_ data: Data) {
        guard let s = String(data: data, encoding: .utf8) else { return }
        let gen = generation
        task?.send(.string(s)) { [weak self] err in
            guard let err else { return }
            Task { @MainActor in self?.fail(gen, err.localizedDescription) }
        }
    }

    private func fail(_ gen: Int, _ reason: String) {
        guard gen == generation, url != nil else { return }
        lastError = reason
        teardown()
        status = .connecting
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    private func teardown() {
        generation += 1
        pingTask?.cancel(); pingTask = nil
        retryTask?.cancel(); retryTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
