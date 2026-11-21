import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: VocalModel
    @Environment(\.dismiss) private var dismiss
    @State private var portText = ""
    @State private var testLine = "Are you ready to order?"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Glasses IP (e.g. 172.20.10.2)", text: $m.glassesHost)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                        .onChange(of: portText) { _, v in if let p = Int(v), (1...65535).contains(p) { m.glassesPort = p } }
                    Button(m.glasses.status == .off ? "Connect" : "Reconnect") { m.connectGlasses() }
                    if m.glasses.status != .off {
                        Button("Disconnect", role: .destructive) { m.glasses.disconnect() }
                    }
                    LabeledContent("Status", value: m.glasses.status.label)
                    if let e = m.glasses.lastError, m.glasses.status != .connected {
                        Text(e).font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Glasses link")
                } footer: {
                    Text("The glasses app is the WebSocket server (port 8765). Put the glasses on this iPhone's Personal Hotspot and enter their IP. For testing without glasses, run tools/mock-glasses.js on a Mac on the same network.")
                }

                Section("You") {
                    TextField("Name shown to partner", text: $m.userName)
                    Toggle("Show partner screen while replying", isOn: $m.showPartnerScreen)
                    LabeledContent("Voice", value: m.speech.voiceName)
                }

                Section {
                    Toggle("Use my Personal Voice", isOn: $m.usePersonalVoice)
                    switch m.speech.personalVoiceStatus {
                    case .authorized:
                        if !m.speech.usingPersonalVoice && m.usePersonalVoice {
                            Text("Allowed, but no Personal Voice found on this iPhone yet. Create one in Settings → Accessibility → Personal Voice, then come back.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    case .denied:
                        Text("Access denied. Turn it on in Settings → Accessibility → Personal Voice → Allow Apps to Request to Use.")
                            .font(.footnote).foregroundStyle(.orange)
                    case .unsupported:
                        Text("Personal Voice isn't supported on this device.").font(.footnote).foregroundStyle(.gray)
                    default:
                        Button("Allow Vocal to use my Personal Voice") { m.speech.requestPersonalVoice() }
                    }
                    Button("Play sample") { m.say("Hi, this is how I sound.", source: .sample) ; dismiss() }
                } header: { Text("Personal Voice") } footer: {
                    Text("Replies use your Personal Voice when it's available; otherwise the system voice. HELP always uses the system voice so the alarm stays clear.")
                }

                Section {
                    Toggle("On-device captions only", isOn: $m.onDeviceOnly)
                } header: { Text("Captions") } footer: {
                    Text("When on, captions never use Apple's servers; if this iPhone can't caption on device, captions show as unavailable instead of silently switching.")
                }

                Section {
                    TextField("https://…/suggest (optional)", text: $m.suggestionURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("AI replies") } footer: {
                    Text("Empty = built-in instant replies only. With a URL, the app POSTs {heard, context, user, max_words} and expects {replies:[3]} within 1.5 s; built-in replies show first.")
                }

                Section("Demo / test") {
                    TextField("Partner says…", text: $testLine)
                    Button("Simulate partner line") { m.simulatePartner(testLine); dismiss() }
                    Button("Simulate glasses: choosing") { m.handle(.init(action: .choosing)); dismiss() }
                    Button("Simulate glasses: select first reply") {
                        if let r = m.replies.first ?? m.quick.first { m.handle(.init(action: .select, text: r)) }
                        dismiss()
                    }
                    Button("Clear transcript") { m.captions.clearTranscript() }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { portText = String(m.glassesPort) }
        }
    }
}
