import SwiftUI

/// The wearer/operator screen: status, glasses preview, transcript, replies, quick phrases, tone.
struct HubView: View {
    @EnvironmentObject var m: VocalModel
    @State private var showSettings = false
    @State private var showRace = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(showSettings: $showSettings, showRace: $showRace)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassesPreview(snapshot: m.snapshot)
                    TranscriptCard()
                    RepliesSection()
                    QuickSection()
                    TypeReplySection()
                    ToneSection()
                    HelpHoldButton { m.triggerHelp() }
                }
                .padding(16)
            }
            ListenBar()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(m) }
        .sheet(isPresented: $showRace) { RaceView().environmentObject(m) }
    }
}

// MARK: - Status

struct StatusBar: View {
    @EnvironmentObject var m: VocalModel
    @Binding var showSettings: Bool
    @Binding var showRace: Bool

    var body: some View {
        HStack(spacing: 8) {
            Pill(text: m.glasses.status.label, on: m.glasses.status == .connected,
                 icon: "eyeglasses", pulsing: m.glasses.status == .connecting)
                .onTapGesture { showSettings = true }
            Pill(text: m.captions.status.label + (m.captions.status == .listening ? (m.captions.onDevice ? " · on-device" : " · server") : ""),
                 on: m.captions.status == .listening, icon: "mic.fill", pulsing: false)
            Spacer(minLength: 0)
            Button { showRace = true } label: {
                RaceChip()
            }
            .accessibilityLabel("Question-to-answer timer")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.title3).foregroundStyle(.gray)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct Pill: View {
    let text: String
    let on: Bool
    let icon: String
    let pulsing: Bool
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Color.green.opacity(0.22) : Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(on ? Color.green : Color.gray)
            .opacity(pulsing ? 0.6 : 1)
    }
}

// MARK: - Transcript

struct TranscriptCard: View {
    @EnvironmentObject var m: VocalModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Heard")
            if m.captions.lines.isEmpty && m.captions.partial.isEmpty {
                Text(m.captions.isOn ? "Waiting for someone to speak…" : "Tap Listen to start captions.")
                    .foregroundStyle(.gray)
            }
            ForEach(Array(m.captions.lines.suffix(4).enumerated()), id: \.offset) { i, line in
                Text(line)
                    .foregroundStyle(i == m.captions.lines.suffix(4).count - 1 && m.captions.partial.isEmpty ? .white : .gray)
            }
            if !m.captions.partial.isEmpty {
                Text(m.captions.partial).foregroundStyle(.white).italic()
            }
        }
        .font(.title3.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Replies / quick / tone

struct RepliesSection: View {
    @EnvironmentObject var m: VocalModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Replies")
            if m.replies.isEmpty {
                Text("Replies appear after the other person speaks.").foregroundStyle(.gray)
            }
            ForEach(m.replies, id: \.self) { r in
                Button { m.say(r) } label: {
                    Text(r).font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(m.mode == .speaking || m.mode == .help)
            }
        }
    }
}

struct QuickSection: View {
    @EnvironmentObject var m: VocalModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Quick phrases")
                Spacer()
                Picker("Set", selection: $m.phraseSet) {
                    ForEach(PhraseSet.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 190)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(m.quick, id: \.self) { q in
                    Button { m.say(q, source: .quick) } label: {
                        Text(q).font(.body.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10).padding(.vertical, 10)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(m.mode == .speaking || m.mode == .help)
                }
            }
        }
    }
}

struct ToneSection: View {
    @EnvironmentObject var m: VocalModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Tone")
            Picker("Tone", selection: $m.tone) {
                ForEach(Tone.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SectionTitle: View {
    let t: String
    init(_ t: String) { self.t = t }
    var body: some View {
        Text(t.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.gray).tracking(1)
    }
}

// MARK: - Bottom bar

struct ListenBar: View {
    @EnvironmentObject var m: VocalModel
    var body: some View {
        HStack(spacing: 10) {
            if m.mode == .speaking {
                Button { m.stopSpeaking() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButton(color: .orange))
            }
            Button { m.captions.toggle() } label: {
                Label(m.captions.isOn ? "Stop listening" : "Listen",
                      systemImage: m.captions.isOn ? "mic.slash.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButton(color: m.captions.isOn ? .red : .green))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.black)
    }
}

struct BigButton: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }
}

// MARK: - HELP hold button (3 s, visible countdown, hard to trigger by accident)

struct HelpHoldButton: View {
    let action: () -> Void
    @State private var progress: Double = 0
    @State private var holding = false
    @State private var timer: Timer?
    private let duration = 3.0

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.18))
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 14).fill(Color.red)
                    .frame(width: g.size.width * progress)
            }
            Text(holding ? "Keep holding… \(Int(ceil(duration * (1 - progress))))" : "Hold 3 s for HELP")
                .font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 54)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !holding { begin() } }
                .onEnded { _ in cancel() }
        )
        .accessibilityLabel("Hold for three seconds to call for help")
    }

    private func begin() {
        holding = true
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            let p = Date().timeIntervalSince(start) / duration
            progress = min(1, p)
            if p >= 1 { t.invalidate(); timer = nil; holding = false; progress = 0; action() }
        }
    }

    private func cancel() {
        timer?.invalidate(); timer = nil
        holding = false
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

