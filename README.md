# Vocal (replymaster)

Smart glasses + iPhone app that help people with ALS or speech loss keep up with face-to-face conversation: live captions in the glasses, suggested replies, and one-switch selection spoken in the user's own voice. Deaf and hard-of-hearing users get the same captions with optional quick replies.

- **Design doc:** [docs/DESIGN.md](docs/DESIGN.md)
- **Hardware brochures:** `docs/*.pdf` (MLVISION M5, M6, L5 series)

## Current demo

The current demo has two apps:

- `ios-livecaptions/`: Swift iPhone app that transcribes speech and sends caption messages over TCP.
- `glasses-hello/`: standalone Android proof-of-concept for the M6 glasses. It can listen, hold a reply, speak it, and launch the glasses camera. It also retains the caption receiver on port `8787`.

The glasses-side app is installed with `adb`; the iPhone app is installed with Xcode. The iPhone and glasses must be on the same Wi-Fi network for caption transport. The iPhone discovers the glasses automatically with Bonjour, while still allowing manual IP entry.

### Run standalone on the glasses

The glasses app does not require the iPhone for its basic proof-of-concept controls. Open `Vocal Standalone` on the glasses, tap **Listen** and speak, tap **Speak Reply** to speak the recognized text, or tap **Take Photo** to launch the glasses camera. Camera understanding/OCR still needs a vision model or the vendor camera/file SDK.

### Run on the glasses

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

### Run on the iPhone

Open `ios-livecaptions/LiveCaptions.xcodeproj` in Xcode, select the `LiveCaptions` target, and choose your Apple Team under **Signing & Capabilities**. Connect the physical iPhone, select it as the destination, and press **Run**. The Simulator is not suitable because microphone and device networking are required.

In the app, wait for the glasses to be found or enter the IP shown on the glasses, tap **Connect**, allow local-network and microphone access, then tap **Start**. Spoken words should appear on the glasses.

For a compile-only check when signing is not configured:

```bash
xcodebuild -project ios-livecaptions/LiveCaptions.xcodeproj \
  -scheme LiveCaptions -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

### Camera track

The **Camera** button in `Vocal Captions` captures/selects an image, runs local OCR, and speaks the result. The remaining integration is to trigger the M6 camera and feed a synced glasses photo into `CameraInsight`; the vendor `MLVisionM6SDK` integration currently lives in the separate `MLDemo` package.
