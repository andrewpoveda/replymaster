# Vocal glasses ⇄ iPhone protocol (v3, hackathon)

Follows the v3 idea design ("Vocal: Idea Design (v3, ALS focus)"). **Confirm with the glasses dev** — this replaces the `render`/`input` draft in `DESIGN.md` §7.

## Transport

Same transport as Albert's `glasses-hello` caption receiver (PR #1):

- The **glasses app is the server**: plain **TCP on port 8787**, advertised over Bonjour as **`_replymaster._tcp`** (service name `ReplyMaster-Glasses`).
- The **iPhone is the client**. Vocal finds the glasses automatically when the Glasses IP setting is empty, or uses the IP typed in Settings (the glasses screen shows it).
- **One JSON object per line**, terminated by `\n`, in both directions. If a message has a field the receiver doesn't know, the receiver ignores that field.
- Demo network only (no encryption, fictional content). The iPhone and glasses must be on the same Wi-Fi (venue Wi-Fi worked for Albert; an iPhone hotspot is the fallback).
- The iPhone turns on TCP keepalive and reconnects on its own. After reconnecting it sends only the current state. It never replays an old action.

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
{"type":"caption","text":"“Are you ready to order?”\n\n1. One iced latte, please\n2. Can I have a minute?\n3. What do you recommend?\n\nYes · No · Wait · Repeat please · Thank you · Haha","final":true,"rev":42,"state":"listening","caption":"Are you ready to order?","replies":["One iced latte, please","Can I have a minute?","What do you recommend?"],"quick":["Yes","No","Wait","Repeat please","Thank you","Haha"],"tones":["neutral","warm","firm","joking"],"tone":"neutral","said":null,"mic":"listening"}
```

- `type`, `text` and `final` keep **Albert's original receiver working unchanged**. It shows `text`, which is a ready-made plain-text rendering of the whole glasses screen: `Said: …` while speaking, `HELP SENT` during HELP.
- Structured fields for the full v3 screen:
  - `state`: listening | choosing | speaking | help
  - `caption`: one line, the latest thing heard (may be partial)
  - `replies`: up to 3
  - `quick`: the quick phrases
  - `tones` and `tone`: the tone options and the iPhone's default tone. When the glasses send a tone with `select`, that tone wins.
  - `said`: set only while state == speaking. The iPhone holds the speaking state for at least 2 s.
  - `mic`: listening | paused | off | denied | unavailable

### What the glasses should draw (from the v3 design)

| state | glasses |
|---|---|
| listening | one caption line; quick phrases at the bottom (replies too if any) |
| choosing | 3 replies + quick phrases, highlighted item **inverted**, tone tag next to the highlight |
| speaking | `Said: <said>` |
| help | large flashing `HELP SENT`, everything else hidden, center kept clear |

Don't use colour coding: the display may be green-only.

## What `glasses-hello` needs for the full loop

1. Restore the port-8787 receiver and Bonjour advertising from commit `820be59`. The 11:28 standalone rewrite removed them.
2. Draw the v3 screen from the structured fields, or just show `text` to begin with.
3. Map the temple touchpad / ring key events to next/select locally, and write the action lines above back on the same socket. Hold 3 s → `{"action":"help"}`.

## Who does what

- **Glasses:** do next/select locally, show the 3-second HELP countdown, then send `help`.
- **iPhone:** shows "Dana is replying…" on `choosing`. On `select` it speaks the text in the chosen tone. On `help` it repeats "I need help" at full volume until someone cancels, either on the phone or with `help_cancel`.

## Testing without glasses

`tools/mock-glasses.js` is a TCP server on port 8787 that uses only Node's standard library. It acts as the glasses so you can test the iPhone app without them. It doesn't advertise over Bonjour, so type the Mac's IP into Vocal (`127.0.0.1` from the simulator):

```
node tools/mock-glasses.js          # listens on 0.0.0.0:8787
> c                 # send choosing
> s One iced latte, please
> s Haha joking     # last word is the tone if it matches a tone name
> h                 # help
> x                 # help_cancel
```
