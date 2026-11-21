# Vocal glasses ⇄ iPhone protocol (v3, hackathon)

Follows the v3 idea design ("Vocal: Idea Design (v3, ALS focus)"). **Confirm with the glasses dev** — this replaces the `render`/`input` draft in `DESIGN.md` §7.

## Transport

- The **glasses app is the WebSocket server**, port **8765**, path `/`. Plain `ws://` (demo network only — fictional content, no secrets).
- The **iPhone is the client**. You type the glasses' IP into the iPhone app's settings (on the iPhone's personal hotspot this is usually `172.20.10.x`).
- Every message is one JSON text frame. If a frame has a field the receiver doesn't know, the receiver ignores that field.
- The iPhone pings every 2 s and reconnects on its own. After reconnecting it sends only the current state. It never replays an old action.

## glasses → iPhone

```json
{"action":"choosing"}                                    // user started scanning (first next/swipe)
{"action":"select","text":"One iced latte, please"}      // user pressed select on a reply or quick phrase
{"action":"select","text":"Haha","tone":"joking"}        // optional tone: neutral | warm | firm | joking
{"action":"cancel"}                                      // optional: user backed out of choosing
{"action":"help"}                                        // touchpad held 3 s (the glasses show the countdown)
{"action":"help_cancel"}                                 // optional: cancel HELP from the glasses
```

`text` must be one of the strings the iPhone sent in `replies`, `quick` or `tones`. The iPhone speaks whatever text it receives.

## iPhone → glasses

The iPhone sends a full snapshot every time something changes. The glasses draw whatever the latest snapshot says.

```json
{
  "type": "state",
  "rev": 42,
  "state": "listening",          // listening | choosing | speaking | help
  "caption": "Are you ready to order?",   // one line: latest thing heard (may be partial)
  "replies": ["One iced latte, please", "Can I have a minute?", "What do you recommend?"],
  "quick": ["Yes", "No", "Wait", "Repeat please", "Thank you", "Haha"],
  "tones": ["neutral", "warm", "firm", "joking"],
  "tone": "neutral",            // the iPhone's default tone. When the glasses send a tone with select, that tone wins.
  "said": null,                  // set while state == speaking: show "Said: …" (the iPhone keeps this state ≥ 2 s)
  "mic": "listening"             // listening | paused | off | denied | unavailable
}
```

### What the glasses should draw (from the v3 design)

| state | glasses |
|---|---|
| listening | one caption line; quick phrases at the bottom (replies too if any) |
| choosing | 3 replies + quick phrases, highlighted item **inverted**, tone tag next to the highlight |
| speaking | `Said: <said>` |
| help | large flashing `HELP SENT`, everything else hidden, center kept clear |

Don't use colour coding: the display may be green-only.

## Who does what

- **Glasses:** do next/select locally, show the 3-second HELP countdown, then send `help`.
- **iPhone:** shows "Dana is replying…" on `choosing`. On `select` it speaks the text in the chosen tone. On `help` it repeats "I need help" at full volume until someone cancels, either on the phone or with `help_cancel`.

## Testing without glasses

`tools/mock-glasses.js` is a WebSocket server that uses only Node's standard library. It acts as the glasses so you can test the iPhone app without them:

```
node tools/mock-glasses.js          # listens on 0.0.0.0:8765
> c                 # send choosing
> s One iced latte, please
> s Haha joking     # last word is the tone if it matches a tone name
> h                 # help
> x                 # help_cancel
```
