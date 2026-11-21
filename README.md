# Vocal (replymaster)

Smart glasses + iPhone app that help people with ALS keep up with face-to-face conversation. What was said appears in the glasses with three ready replies; one press on the glasses speaks the reply from the iPhone, in the tone she picks. Built for the Worn hackathon, track 03 Natural Interaction.

- **Current plan:** "Vocal: Idea Design (v3, ALS focus)" (team PDF)
- **Glasses ⇄ iPhone messages:** [docs/PROTOCOL.md](docs/PROTOCOL.md)
- **Earlier design doc:** [docs/DESIGN.md](docs/DESIGN.md) (v0.1, superseded by v3 where they differ)
- **Hardware brochures:** `docs/*.pdf` (MLVISION M5, M6, L5 series)

## Repo layout

| Path | What it is |
|---|---|
| `ios-vocal/` | **The iPhone app (hub).** Listens, captions, suggests replies, speaks, talks to the glasses. |
| `tools/mock-glasses.js` | Stand-in for the glasses app (WebSocket server, no dependencies) for testing without hardware. |
| `ios-hello/` | Hello-world used to set up signing. |
| `glasses-hello/` | Android app for the M6 glasses (Albert). Must implement `docs/PROTOCOL.md` for the Vocal loop. |

## Run the iPhone app

1. `open ios-vocal/Vocal.xcodeproj`
2. Pick the **Vocal** scheme and your iPhone (or a simulator) as the destination, then press **⌘R**.
   - Real iPhone: Developer Mode on (Settings → Privacy & Security → Developer Mode). Free Apple accounts allow 3 sideloaded apps per phone; delete an old test app if install fails with "maximum number of installed apps".
3. In the app tap **Listen** and allow microphone + speech recognition.

No glasses needed: the green **Glasses preview** box shows what the glasses would draw, and **Settings → Demo / test** fakes a partner line or glasses actions.

### Connect to the glasses

The glasses app is the WebSocket server (port 8765). Put the glasses on the iPhone's Personal Hotspot, then in Vocal: **Settings → Glasses IP** → Connect. To test the link without glasses, run `node tools/mock-glasses.js` on a Mac on the same network and enter the Mac's IP (simulator: `127.0.0.1`).

## What the iPhone app does

| Feature (v3 plan) | Status |
|---|---|
| Live captions from the iPhone mic, one segment per partner utterance (on-device when supported) | Built; on-phone QA in progress |
| Three context replies the moment the partner stops (built-in rules, instant, offline) | Built |
| Hook for the AI dev's reply endpoint (POST `{heard, context}` → `{replies:[3]}`, 1.5 s budget, built-in replies shown first) | Built; endpoint not connected yet |
| Quick phrases (Everyday + Medical sets: "I understand you", "Give me time", …) | Built |
| Tone per reply: neutral / warm / firm / joking (rate + pitch) | Built |
| Partner-facing "Dana is replying…" screen, then the spoken reply in large text | Built |
| HELP: 3-second hold (phone or glasses) → "I need help" repeats at full volume until cancelled | Built |
| Pauses captions while speaking so Vocal doesn't caption itself | Built |
| Type a reply (say something no suggestion covered) | Built |
| Question → answer race timer (Vocal vs typing, median, copy summary) | Built |
| Personal Voice: replies use the user's Apple Personal Voice when one exists and is allowed | Built; not yet tried with a real Personal Voice |
| WebSocket link to the glasses app, auto-reconnect, full state snapshots | Built; tested only against the mock |

**Not built today (from the v3 cut list):** environmental sound alerts, Deaf caption mode, caregiver text/call on HELP, head-nod and eye-gaze input, learning the user's style.

## Code map (`ios-vocal/Sources`)

- `VocalModel.swift`: the hub; conversation state (listening → choosing → speaking / help), glasses actions, race timing
- `CaptionService.swift`: speech recognition, partial/final segments, pause/resume
- `SpeechService.swift`: text-to-speech with tones, Personal Voice, HELP alarm
- `SuggestionService.swift`: built-in replies + remote AI hook
- `GlassesLink.swift`: WebSocket client to the glasses
- `Models.swift`: tones, phrase sets, wire messages
- Views: `HubView`, `PartnerView` (+ HELP screen), `GlassesPreview`, `RaceView`, `SettingsView`

## Glasses app

`glasses-hello/` is the Android app installed directly on the M6 glasses. It includes standalone listen, reply, speech, and camera proof-of-concept controls. The current Vocal protocol integration is documented in [docs/PROTOCOL.md](docs/PROTOCOL.md).

#### Run standalone on the glasses

The glasses app does not require the iPhone for its basic proof-of-concept controls. Open `Vocal Standalone` on the glasses, tap **Listen** and speak, tap **Speak Reply** to speak the recognized text, or tap **Take Photo** to launch the glasses camera. Camera understanding/OCR still needs a vision model or the vendor camera/file SDK.

#### Run on the glasses

Enable Developer Mode in `MLDemo`, connect the glasses to the Mac by USB, and verify the device:

```bash
adb devices -l
```

Build with the Android SDK and Java 17 configured:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
~/Downloads/Microlumin_Ship/02_Android_SDK/mainapp-main-sdk-oversea/gradlew \
  -p glasses-hello assembleDebug
adb install -r glasses-hello/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.replymaster.glasseshello/.MainActivity
```

The glasses screen shows its Wi-Fi address. The current test device displays a caption server such as `10.3.225.6:8787`.


## Submission draft: "What We Built"

> Android app on the MicroLumin M6 that shows the last thing heard, three replies and quick phrases, with temple-touchpad selection and a 3-second HELP hold. iPhone app (SwiftUI) that captions the conversation on device, suggests three replies within moments of the partner finishing, and speaks the chosen reply in the user's tone (warm, firm, joking) or Personal Voice. While she chooses, the phone shows the partner "Dana is replying…"; HELP makes the phone call out "I need help" until someone responds. The two connect over Wi-Fi with a small JSON protocol. In our timed question-to-answer test, picking a reply in Vocal took a median of [X] s against [Y] s for typing the same answer ([N] trials each).

Fill in the brackets from the in-app race screen ("Copy summary for the deck"). Before submitting, check every claim against what actually ran on the glasses; remove the M6 sentence's details if the glasses app ended up different.
