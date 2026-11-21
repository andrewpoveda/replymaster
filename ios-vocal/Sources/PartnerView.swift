import SwiftUI
import Combine

/// Partner-facing screen: "Dana is replying…" while she chooses, then the spoken reply in large text.
struct PartnerView: View {
    @EnvironmentObject var m: VocalModel
    @State private var dots = 0
    private let tick = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.06, green: 0.09, blue: 0.2).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                if m.mode == .speaking, let said = m.said {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 56)).foregroundStyle(.white.opacity(0.8))
                    Text(said)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.white)
                    Text("— \(m.userName)").font(.title2).foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("\(m.userName) is replying" + String(repeating: ".", count: dots + 1))
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                    Text("Please give \(m.userName) a moment.")
                        .font(.title).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                if m.mode == .speaking {
                    Button { m.stopSpeaking() } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BigButton(color: .orange))
                }
            }
            .padding(24)

            Button { m.showPartnerScreen = false } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .accessibilityLabel("Hide partner screen")
        }
        .onReceive(tick) { _ in dots = (dots + 1) % 3 }
        .accessibilityElement(children: .contain)
    }
}

/// HELP: loud, flashing, impossible to miss. Repeats "I need help" until cancelled.
struct HelpView: View {
    @EnvironmentObject var m: VocalModel
    @State private var flash = false

    var body: some View {
        ZStack {
            (flash ? Color.red : Color(red: 0.45, green: 0, blue: 0)).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 90))
                Text("I NEED HELP").font(.system(size: 64, weight: .black)).minimumScaleFactor(0.5)
                Text("\(m.userName) triggered a HELP alert from the glasses.")
                    .font(.title3).multilineTextAlignment(.center).opacity(0.9)
                Spacer()
                Button { m.cancelHelp() } label: {
                    Text("I'm here — cancel alert").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButton(color: .black.opacity(0.6)))
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { flash = true }
        }
    }
}
