# ReplyMaster plan (real-time captions + instant voice replies for deaf/hard-of-hearing and speech-loss users)

Target hardware: MicroLumin M6 AR glasses + iPhone. Phone does speech work; glasses render text.

1. Live captions from mic (ios-livecaptions): on-device SFSpeechRecognizer, partial results, measure first-word latency, test noise/accents. Next: try SpeechAnalyzer/SpeechTranscriber.
2. Caption readability: font size, contrast, dark bg, show last 2-3 lines, speaker labels (later).
3. Instant voice replies: type -> AVSpeechSynthesizer, one-tap quick phrases, AI reply suggestions from last heard sentence (Foundation Models or Claude), Personal Voice.
4. Two-way conversation mode: captions of other person + spoken replies; handle echo/feedback.
5. Glasses link: phone -> glasses text push over BLE/Wi-Fi (Android app in GlassesHello, not included here); measure latency.
6. Reliability: offline, battery, interruptions (calls, Bluetooth).

Hackathon slice: steps 1, 3, 5.

## Status
- ios-hello: done, runs on iPhone.
- ios-livecaptions: built + installed on iPhone; first on-device test pending.

## Signing notes
Team 7AHBG5S4RV, automatic signing. Build: xcodebuild -project X.xcodeproj -scheme X -destination 'id=<UDID>' -allowProvisioningUpdates build; install/launch with xcrun devicectl.
