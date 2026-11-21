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
                    TextField("Glasses IP (empty = find automatically)", text: $m.glassesHost)
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
                    Text("The glasses app (glasses-hello) is the server on port 8787, same Wi-Fi as this iPhone. Leave the IP empty to find the glasses automatically, or type the IP the glasses show. To test without glasses, run tools/mock-glasses.js on a Mac and enter the Mac's IP.")
                }

                Section("You") {
                    TextField("Name shown to partner", text: $m.userName)
                    Toggle("Show partner screen while replying", isOn: $m.showPartnerScreen)
                    LabeledContent("Voice", value: m.speech.voiceName)
                    Picker("Speak replies on", selection: $m.speakOn) {
                        ForEach(SpeakOn.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Use my Personal Voice", isOn: $m.usePersonalVoice)
                    switch m.speech.personalVoiceStatus {
                    case .authorized:
                        if !m.speech.usingPersonalVoice && m.usePersonalVoice {
                            Text("Access allowed, but no Personal Voice was found. On your iPhone open Settings → Accessibility → Personal Voice → Create a Personal Voice. When it says it's ready, come back to Vocal.")
                                .font(.footnote).foregroundStyle(.orange)
                            openSettingsButton
                        }
                    case .denied:
                        Text("Vocal isn't allowed to use your Personal Voice. Open Settings → Accessibility → Personal Voice, turn on \"Allow Apps to Request to Use\", and make sure Vocal is switched on in the list below it. Then come back to Vocal.")
                            .font(.footnote).foregroundStyle(.orange)
                        openSettingsButton
                    case .unsupported:
                        Text("Personal Voice isn't supported on this iPhone (needs iOS 17 or later on a supported model). Replies use the system voice.")
                            .font(.footnote).foregroundStyle(.gray)
                    default:
                        Text("Not asked yet. Tap below and choose Allow. If no prompt appears, first turn on Settings → Accessibility → Personal Voice → Allow Apps to Request to Use.")
                            .font(.footnote).foregroundStyle(.gray)
                        Button("Allow Vocal to use my Personal Voice") { m.speech.requestPersonalVoice() }
                    }
                    Button("Play sample") { m.say("Hi, this is how I sound.", source: .sample) ; dismiss() }
                } header: { Text("Personal Voice") } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Replies use your Personal Voice when it's available; otherwise the system voice. HELP always uses the system voice so the alarm stays clear.")
                        if m.speech.usingPersonalVoice {
                            Text("Tones change speed with your Personal Voice; iOS may ignore the pitch change for it.")
                        }
                        if m.speech.personalVoiceRenderBlocked {
                            Text("iOS didn't let Vocal turn your Personal Voice into audio for the glasses, so replies play from the iPhone speaker instead. Choose the system voice (turn off the toggle above) to hear replies on the glasses.")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    ForEach(m.quick, id: \.self) { phrase in
                        HStack {
                            Text(phrase)
                            Spacer()
                            if m.speech.recordingPhrase == phrase {
                                Button("Stop") { m.stopRecording() }.foregroundStyle(.red)
                            } else {
                                if m.speech.hasRecording(phrase) {
                                    Button("Play") { m.say(phrase, source: .sample) }
                                    Button(role: .destructive) { m.speech.deleteRecording(phrase) } label: { Image(systemName: "trash") }
                                }
                                Button(m.speech.hasRecording(phrase) ? "Redo" : "Record") { m.startRecording(phrase) }
                                    .disabled(m.speech.recordingPhrase != nil)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .id(m.speech.recordingsVersion)
                } header: { Text("My recordings") } footer: {
                    Text("Record yourself saying each quick phrase (up to 10 s). When a reply matches a recorded phrase exactly, Vocal plays your recording on the iPhone and the glasses instead of the synthetic voice. Tones don't change recordings.")
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

    private var openSettingsButton: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
    }
}
