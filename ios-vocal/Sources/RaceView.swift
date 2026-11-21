import SwiftUI

/// Free-text reply: Dana can say something no suggestion covered. Also the "typing" side of the race.
struct TypeReplySection: View {
    @EnvironmentObject var m: VocalModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Type a reply")
            HStack(spacing: 8) {
                TextField("Type what you want to say…", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(12)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                Button(action: send) {
                    Image(systemName: "speaker.wave.2.fill").font(.title3)
                        .frame(width: 50, height: 46)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.mode == .speaking || m.mode == .help)
                .accessibilityLabel("Speak typed reply")
            }
        }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, m.mode != .speaking, m.mode != .help else { return }
        m.say(t, source: .typed)
        text = ""
        focused = false
    }
}

/// Status-bar chip: live seconds since the partner's last word while a question is open.
struct RaceChip: View {
    @EnvironmentObject var m: VocalModel
    var body: some View {
        if let q = m.questionEndedAt {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let s = ProcessInfo.processInfo.systemUptime - q
                Label(String(format: "%.1fs", s), systemImage: "stopwatch")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.2), in: Capsule())
                    .foregroundStyle(.yellow)
            }
        } else {
            Image(systemName: "stopwatch").font(.title3).foregroundStyle(.gray)
        }
    }
}

/// Question-to-answer race results for the pitch (Vocal vs typing).
struct RaceView: View {
    @EnvironmentObject var m: VocalModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        stat("Vocal", m.vocalTimes)
                        stat("Typing", m.typedTimes)
                    }
                    .listRowBackground(Color.clear)
                    if let v = m.vocalTimes.median, let t = m.typedTimes.median, v > 0 {
                        Text(String(format: "Vocal is %.1f× faster", t / v))
                            .font(.title2.bold()).frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text("Timed from the partner's last word to the reply starting to speak. Vocal = tapping a suggested reply or quick phrase (or selecting on the glasses). Typing = the Type a reply box.")
                }

                Section("How to run the race") {
                    Text("1. Tap Listen. Partner asks a question.")
                    Text("2. Vocal trial: answer by tapping a reply.")
                    Text("3. Typing trial: partner asks again; type the same answer in “Type a reply” and press speak.")
                    Text("4. Alternate Vocal/typing for 5+ questions each.")
                }
                .font(.callout)

                Section("Trials (\(m.results.count))") {
                    if m.results.isEmpty { Text("No trials yet.").foregroundStyle(.gray) }
                    ForEach(m.results.reversed()) { r in
                        HStack {
                            Text(r.typed ? "Typing" : "Vocal")
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background((r.typed ? Color.orange : Color.green).opacity(0.25), in: Capsule())
                            Text(r.text).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f s", r.seconds)).monospacedDigit().bold()
                        }
                    }
                }

                Section {
                    Button(copied ? "Copied" : "Copy summary for the deck") {
                        UIPasteboard.general.string = m.resultsSummary
                        copied = true
                    }
                    .disabled(m.results.isEmpty)
                    Button("Clear all trials", role: .destructive) { m.clearResults() }
                        .disabled(m.results.isEmpty)
                }
            }
            .navigationTitle("Question → answer")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func stat(_ name: String, _ t: [Double]) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.caption.bold()).foregroundStyle(.gray)
            Text(t.median.map { String(format: "%.1f s", $0) } ?? "—")
                .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
            Text("median · \(t.count) trial\(t.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
