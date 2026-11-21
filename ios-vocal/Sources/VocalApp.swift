import SwiftUI

@main
struct VocalApp: App {
    @StateObject private var model = VocalModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, p in if p == .active { model.speech.refreshVoice() } }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var m: VocalModel

    var body: some View {
        ZStack {
            HubView()
            if m.showPartnerScreen && (m.mode == .choosing || m.mode == .speaking) {
                PartnerView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            if m.mode == .help {
                HelpView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: m.mode)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }
}
