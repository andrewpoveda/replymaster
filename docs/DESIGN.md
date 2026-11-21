# Vocal — Design Doc

**Status:** Draft v0.2 (Nov 21, 2026) · iPhone hub app in `ios-vocal/`, glasses app in `glasses-hello/`, wire protocol in [`PROTOCOL.md`](PROTOCOL.md)

> **Team decision (Idea Design v4, Nov 21):** the primary user is now **Deaf and hard-of-hearing people** in face-to-face conversation; ALS and speech loss move to "another user" in what's next. Sections 2–6 below still describe the earlier ALS-first concept and are kept for reference. Where this doc and `PROTOCOL.md` disagree, `PROTOCOL.md` wins.
**Working repo name:** replymaster

> **One line:** Vocal is a pair of smart glasses plus an iPhone app that carries one turn of a conversation for you. It hears the other person, shows what they said in your view, suggests what you might say back, and speaks your choice in your own voice.

---

## 1. Problem

Conversation is fast. People who cannot speak, or cannot hear, are forced into a slower lane:

- **People with ALS or other speech loss** usually hear and understand perfectly, but typing a reply on an AAC (augmentative and alternative communication) device is far slower than speech, so the conversation moves on before they finish. As ALS progresses, the hand movement needed to type disappears too.
- **Deaf and hard-of-hearing people** miss what is being said, especially in noisy or group settings, and looking down at a phone for captions breaks eye contact.

Both groups lose the same thing: the ability to keep up with a live, face-to-face conversation.

## 2. Users

| | Hears the other person | Says something back | What Vocal adds |
|---|---|---|---|
| **Primary: ALS / speech loss** | Usually fine | **Blocked.** Cannot speak; motor control declines over time | Reply suggestions, one-switch selection, speech in their own voice |
| **Secondary: Deaf / hard of hearing** | **Blocked.** Needs captions | Many can speak; some prefer not to | Glanceable captions; optional quick replies |

We design for the primary user first. The secondary user gets the same engine with a different emphasis (captions first, replies optional). The story for the pitch: *we designed for one person, and it turned out to fit another.*

### Persona (primary)

**Dana, 52, diagnosed with ALS two years ago.** Still walks, but speech is now hard to understand and typing on her phone is getting slow. She banked her voice soon after diagnosis. She wants to order her own coffee and answer her doctor without her husband speaking for her.

## 3. Design principles

1. **The user decides what is said.** Vocal suggests; it never speaks on its own. Agency is the point.
2. **Sounds like me.** Replies use the user's own words, phrasing and banked voice, not generic AI text.
3. **Fast enough to stay in the conversation.** Something useful appears within ~1 s; smarter suggestions fill in after.
4. **One switch is enough.** Every action must be possible with a single button, so the product keeps working as motor control declines.
5. **Heads-up, not heads-down.** Information appears in the glasses so eye contact is kept.
6. **Private by default.** Transcribe, do not record. Raw audio is not stored.

## 4. The core loop

```
 ┌──────────┐    ┌──────────────┐    ┌──────────────────┐    ┌──────────────┐    ┌──────────────┐
 │  LISTEN  │ →  │   CAPTION    │ →  │     SUGGEST      │ →  │    CHOOSE    │ →  │    SPEAK     │
 │ iPhone   │    │ last 1–2     │    │ 3 replies +      │    │ switch scan  │    │ banked voice │
 │ mic      │    │ lines in     │    │ quick phrases    │    │ (tap / ring  │    │ from iPhone  │
 │          │    │ glasses      │    │ in glasses       │    │ / head nod)  │    │ speaker      │
 └──────────┘    └──────────────┘    └──────────────────┘    └──────────────┘    └──────────────┘
```

Primary mode (ALS): all five steps.
Caption mode (Deaf / HoH): LISTEN → CAPTION, with SUGGEST/CHOOSE/SPEAK available on demand (reply can be spoken or shown as text on the iPhone screen for the other person).

## 5. Features

### MVP (first demo)

| # | Feature | Description |
|---|---|---|
| F1 | **Live captions** | On-device speech recognition on iPhone. Glasses show the latest 1–2 lines, large, high contrast. |
| F2 | **Context replies** | After the other person stops talking, show 3 suggested replies based on what they said, the setting, and the user's profile. |
| F3 | **Quick phrases** | Always-available fixed set: *Yes · No · Wait a moment · Please repeat · Thank you.* Shown instantly, before AI suggestions arrive. |
| F4 | **One-switch selection** | Options are highlighted one by one (scanning); one press selects. Long press = back / more. |
| F5 | **Speak in my voice** | Selected reply is spoken through the iPhone speaker using the user's Apple Personal Voice (falls back to a system voice). |
| F6 | **Phrase bank** | User (or caregiver) adds personal phrases, names, places and preferences in the iPhone app. Used by F2. |

### Later

- **Learns my style:** suggestions adapt to replies the user picks and edits over time.
- **Scene context:** use the glasses camera (M6) to read a menu or sign and tailor suggestions.
- **Speaker labels:** who said what in group conversations.
- **Text reply mode:** show the reply in large text on the iPhone for the other person (for Deaf users who prefer not to voice).
- **Conversation recap:** short summary after a doctor visit, saved only if the user chooses.
- **Multilingual:** the glasses already advertise 15-language translation; captions + replies across languages.

### Out of scope (for now)

- Eye-gaze or blink input (none of the target glasses have an inward-facing camera; see §8).
- Replacing clinical AAC devices. Vocal is a companion for everyday conversation.

## 6. Interaction design

### 6.1 Glasses view

Display budget is small: **640×480, 30° field of view, often monochrome green.** Rules:

- Max **2 caption lines** + **3 reply options**, nothing else.
- Large type, no thin weights; one accent (brightness), no color coding that green-only displays cannot show.
- Selection is shown by a bracket/inversion, not by color.

```
 ┌────────────────────────────────────────┐
 │  "Are you ready to order?"             │   ← caption (other person)
 │                                        │
 │  ▶ One iced latte, please              │   ← highlighted option
 │    Can I have a minute?                │
 │    What do you recommend?              │
 │  ─────────────────────────────────     │
 │    yes · no · wait · repeat · thanks   │   ← quick phrases
 └────────────────────────────────────────┘
```

### 6.2 Input ladder

Input must change as the disease progresses. Each step uses the same two actions: **next** and **select**.

| Stage | Input | Hardware basis | Confidence |
|---|---|---|---|
| Early | iPhone touch, glasses temple touch | Temple touch on M5/M6 | Depends on SDK |
| Middle | **Bluetooth ring** (one finger click) | Ring control advertised for M6 | Depends on SDK |
| Middle (fallback) | Off-the-shelf Bluetooth switch / clicker paired to iPhone | Standard BLE HID | High; works without vendor SDK |
| Late | **Head nod / tilt** | 6-axis IMU in L5 AI | Depends on SDK |
| Beyond | Eye gaze, blink | Not available on these glasses | Out of scope; integrate with existing AAC tools |

### 6.3 Audio output

The glasses speakers are designed to be **leak-proof** (private to the wearer). That is the opposite of what we need for speaking to someone else. **Speech is played from the iPhone speaker** (or a small external speaker). Glasses audio can be used for private cues to the wearer.

## 7. System architecture

**The iPhone is the hub. The glasses are a display and an input device.**

> **Update (v0.2, after the hackathon kit):** the phone-side glasses SDK drives the glasses' built-in apps but cannot draw our own text. So Vocal ships **two apps**: the iPhone app (listening, suggestions, voice) and a small **glasses app** (`glasses-hello/`, plain Android) that renders the screen and reads the temple touchpad / ring as key events. They talk over **TCP port 8787 with one JSON object per line**; the glasses app is the server and advertises itself over Bonjour (`_replymaster._tcp`). Full spec: [`PROTOCOL.md`](PROTOCOL.md). The glasses SDK is still used on the iPhone for pairing and joining the glasses to Wi‑Fi.

```
          ┌─────────────────────────── iPhone (Vocal app, Swift) ───────────────────────────┐
  voice → │ Mic → Speech recognition (on-device) → Conversation state                      │
          │                                         │                                       │
          │                         Suggestion engine ──→ Backend (LLM, keys server-side)  │
          │                                         │                                       │
          │ Phrase bank / profile (on device)       ▼                                       │
          │                                   Reply options                                 │
          │                                         │                                       │
          │ Personal Voice TTS ← selection ── Input manager ← switch / ring / touch / IMU   │
          │        │                                │                                       │
          └────────┼────────────────────────────────┼───────────────────────────────────────┘
                   ▼                                ▼  GlassesLink (BLE or Wi‑Fi)
          iPhone speaker → other person      Smart glasses: render captions + options,
                                             send button / ring / IMU events back
```

### Components

| Component | Responsibility | Candidate tech |
|---|---|---|
| **iOS app** | Main app, settings, phrase bank, onboarding | Swift, SwiftUI |
| **Speech recognition** | Live captions, on device where possible | Apple Speech framework |
| **Suggestion engine** | Build prompt from transcript + setting + profile; return 3 short replies; merge with quick phrases | iPhone → our backend → LLM API |
| **Backend** | Holds API keys, calls the LLM, no conversation storage | Small server (e.g. Node/TS) |
| **TTS** | Speak the chosen reply in the user's voice | AVSpeechSynthesizer with Apple Personal Voice (iOS 17+), system voice fallback |
| **Input manager** | Normalize all inputs to `next` / `select` / `back`; scanning timer | CoreBluetooth, on-screen controls |
| **GlassesLink** | Send screen snapshots to the glasses, receive actions | TCP client → glasses app on port 8787, newline-delimited JSON ([`PROTOCOL.md`](PROTOCOL.md)) |
| **Glasses app** | Draw caption, replies and quick phrases; turn touchpad / ring into next / select locally; send `choosing` / `select` / `help` back | `glasses-hello/`, plain Android (API 28), TCP server + Bonjour |
| **Glasses simulator** | 640×480 green preview so we can build and demo without hardware | In-app view or small web page |

### GlassesLink contract

Superseded by [`PROTOCOL.md`](PROTOCOL.md). Summary:

```
iPhone → glasses   (full snapshot on every change)
  {"type":"caption","text":"...","final":true,"rev":42,"state":"listening|choosing|speaking|help",
   "caption":"...","replies":[≤3],"quick":[...],"tones":[...],"tone":"neutral","said":null,"mic":"listening"}

glasses → iPhone
  {"action":"choosing"} · {"action":"select","text":"...","tone":"warm"} · {"action":"cancel"}
  {"action":"help"} · {"action":"help_cancel"}
```

### Latency budget (target)

| Step | Target |
|---|---|
| Speech end → caption shown | < 300 ms |
| Speech end → quick phrases shown | instant |
| Speech end → AI suggestions shown | < 1.5 s |
| Select → voice starts | < 300 ms |

## 8. Hardware

Three MLVISION (Microlumin) models are documented in `docs/` (product brochures only; no developer documentation).

| | **M5** | **M6** | **L5 AI** |
|---|---|---|---|
| Form | AR clip-on for any glasses | All-in-one AR glasses | Audio AI glasses, no display (M5 snaps on to add one) |
| Weight | 25.8 g | 36.8 g (Air) · 48 g (Display) · 52 g (Display Pro) | 38 g |
| Display | Mono green Micro-LED, 640×480, FOV 30°, 1500 nits, 30 Hz | Full color or mono green, 640×480, FOV 30°, 1800 nits | None |
| Camera | None | Sony IMX681 12 MP, 110°, 1080p30 | None |
| Mics / speakers | 2 mics + noise reduction | 3+1 mics; leak-proof directional speakers | 6 mics; dual speakers, anti-leakage |
| Chip / memory | BES2700 · 20 MB RAM · 16 MB ROM | Unisoc W517 · 2 GB RAM · 64 GB ROM | BES2710Y |
| OS | Not stated | **Android 9.0 Go** | Hongyan WinAI OS |
| Connectivity | BT 5.3 | Wi‑Fi 2.4/5 GHz · BT 5.0 | BT 5.4 (BT/BLE dual mode) |
| Battery | 60 mAh | 240 mAh + charging case (1800 mAh) | 160 mAh × 2 |
| Input | Touch, voice | Voice, Bluetooth ring, temple touch, phone app | Voice wake-up |
| Sensors | — | — | 6-axis IMU, wear detection |

**Fit for Vocal**

- **M6** is the best fit: display + camera + Wi‑Fi + Android means we may be able to run a thin receiver app and talk to the iPhone over the local network.
- **M5** (alone or on L5 AI) is a display accessory over Bluetooth; workable if the BLE display protocol is available.
- **L5 AI** alone has no display but has the IMU we want for head-nod input.

### Questions for the vendor (status after the hackathon kit)

Answered by the hackathon kit: custom text needs our own glasses app (Q2); the touchpad and ring arrive in that app as Android key events (Q3); glasses apps install over `adb` in Developer Mode (Q4). Still open: Q5 and IMU access.

1. Which model(s) will we get, and how many units?
2. Is there a developer SDK or documented BLE/Wi‑Fi protocol to **draw text** on the display from a third-party iPhone app?
3. Can we **receive input events** (temple touch, ring, IMU) in our app?
4. M6: can we sideload an APK? Any restrictions on background apps, mic or network?
5. Can the built-in voice assistant and translation features be turned off, so they do not compete with our app?


## 9. Data and privacy

- Audio is processed for transcription and **not stored**.
- Transcripts stay on the phone and are discarded after the conversation unless the user saves a recap.
- Only the last few turns of transcript + the user's chosen profile fields are sent to the backend to generate suggestions. No account data, no contacts.
- API keys live only on the backend.
- A visible indicator (in-app and, if possible, on the glasses LED) shows when Vocal is listening, so people nearby can know.

## 10. Demo script (2 minutes)

1. **Café.** Barista: *"Are you ready to order?"* → caption appears in the glasses → three replies, top one is the user's usual order → one ring click → iPhone speaks *"One iced latte, please"* in her voice.
2. **Doctor.** Doctor: *"How bad is the pain today, from 1 to 10?"* → Vocal offers a number scale → user picks *6* with a head nod.
3. **Switch user.** Same glasses in caption mode for a Deaf user: captions lead; a reply is shown as large text on the iPhone for the other person.

Show one number: **time from question to spoken answer**, Vocal vs typing on a phone. Measure it ourselves.

## 11. Success metrics

- Median time from end of the partner's question to the user's spoken reply.
- Share of replies chosen from suggestions without editing.
- Caption accuracy in a café-noise test.
- Qualitative: does the user feel the reply "sounds like me"?

## 12. Risks

| Risk | Mitigation |
|---|---|
| No vendor SDK, cannot drive the display | Build on `SimulatorLink`; demo with simulator mirrored next to the glasses; push vendor early |
| Suggestion latency | Quick phrases first; stream AI suggestions; short prompts |
| Wrong or awkward suggestions | Never auto-speak; easy "more options"; learn from choices |
| Noisy environments | Use the glasses' mic array if accessible, otherwise iPhone mic; show confidence |
| Privacy concerns from people nearby | No recording, listening indicator, clear policy in the app |
| Building without real users | Talk to at least one person with ALS or a speech-language pathologist, and one Deaf/HoH person, before the demo |

## 13. Open decisions

- [ ] Primary user confirmed as ALS / speech loss?
- [ ] Which LLM provider for suggestions?
- [ ] Which glasses model is available to us?
- [ ] Team roles (iOS app · backend + suggestions · glasses link + simulator + design)
- [ ] Deadline and demo format

## 14. Next steps

1. Answer the open decisions above.
2. Contact the vendor with the §8 questions.
3. Build the iOS app skeleton with `SimulatorLink`, captions (F1) and quick phrases (F3).
4. Add suggestion backend (F2) and Personal Voice output (F5).
5. Replace the simulator with the real glasses link once the SDK is confirmed.
