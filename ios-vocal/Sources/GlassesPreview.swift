import SwiftUI

/// 640×480 green-on-black preview of what we're sending to the glasses. Follows the v3 screen rules:
/// no colour coding, one caption line, inversion for highlight, HELP hides everything else.
/// Development aid only — real-hardware rendering is the glasses app's job.
struct GlassesPreview: View {
    let snapshot: GlassesSnapshot
    @State private var flash = false
    private let green = Color(red: 0, green: 1, blue: 0.47)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Glasses preview · rev \(snapshot.rev)")
            GeometryReader { g in
                let s = g.size.width / 640    // scale factor from glasses pixels
                ZStack {
                    Color.black
                    content(s)
                        .padding(18 * s)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15)))
            }
            .aspectRatio(4/3, contentMode: .fit)
        }
    }

    @ViewBuilder
    private func content(_ s: CGFloat) -> some View {
        switch snapshot.state {
        case .help:
            Text("HELP SENT")
                .font(.system(size: 96 * s, weight: .black))
                .foregroundStyle(green.opacity(flash ? 1 : 0.15))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear { withAnimation(.easeInOut(duration: 0.35).repeatForever()) { flash = true } }
                .onDisappear { flash = false }
        case .speaking:
            Text("Said: \(snapshot.said ?? "")")
                .font(.system(size: 36 * s, weight: .bold))
                .foregroundStyle(green)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .listening, .choosing:
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(snapshot.caption.isEmpty ? " " : "“\(snapshot.caption)”")
                    .font(.system(size: 28 * s, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(green.opacity(0.85))
                // Same column as the glasses: replies, then quick phrases, then the tone item, one per row.
                let items = snapshot.replies + snapshot.quick + ["Tone: \(snapshot.tone.rawValue)"]
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let reply = i < snapshot.replies.count
                    let tone = i == items.count - 1
                    // Preview highlights the first item while choosing (real highlight lives on the glasses).
                    let hl = snapshot.state == .choosing && i == 0
                    Text(hl && !tone ? "\(item)   [\(snapshot.tone.rawValue)]" : item)
                        .font(.system(size: (reply ? 28 : tone ? 20 : 22) * s, weight: reply ? .bold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10 * s).padding(.vertical, 2 * s)
                        .foregroundStyle(hl ? Color.black : green)
                        .background(hl ? green : .clear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
