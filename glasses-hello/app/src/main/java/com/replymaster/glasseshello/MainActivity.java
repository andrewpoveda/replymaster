package com.replymaster.glasseshello;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.Locale;

/**
 * Vocal glasses app (M6).
 *
 * - No iPhone connected: Albert's standalone proof-of-concept (listen, type/hold a reply, speak, photo).
 * - iPhone (Vocal) connected: the v3 glasses screen — one caption line, 3 replies + quick phrases,
 *   highlighted item inverted, tone tag, "Said: …", flashing "HELP SENT".
 *
 * Link (docs/PROTOCOL.md): TCP server on 8787, Bonjour "_replymaster._tcp", one JSON object per line.
 * Input: two actions only. next = swipe / DPAD / TAB / scroll; select = tap / ENTER / DPAD_CENTER.
 * Hold select 3 s = HELP (countdown shown). Unknown key codes are shown in the footer to help map the
 * real temple touchpad and ring.
 */
public final class MainActivity extends Activity implements TextToSpeech.OnInitListener {
    private static final int PORT = 8787;
    private static final int REQUEST_PERMISSIONS = 10;
    private static final int REQUEST_CAMERA = 11;
    private static final long HELP_HOLD_MS = 3000;
    private static final int GREEN = Color.rgb(0, 255, 120);
    private static final String[] TONES = {"neutral", "warm", "firm", "joking"};

    private final Handler ui = new Handler(Looper.getMainLooper());

    // Standalone panel
    private View standalonePanel;
    private TextView status;
    private EditText reply;
    private SpeechRecognizer recognizer;
    private TextToSpeech speaker;

    // Vocal panel
    private FrameLayout vocalPanel;
    private LinearLayout listPanel;
    private TextView captionView, bigView, footerView, countdownView;
    private final List<TextView> itemViews = new ArrayList<>();

    // Vocal state (from the iPhone)
    private String state = "listening", caption = "", said = "", mic = "off";
    private final List<String> replies = new ArrayList<>();
    private final List<String> quick = new ArrayList<>();
    private int toneIndex = 0;          // tone the wearer picked on the glasses
    private int highlight = -1;         // -1 = not scanning yet
    private int lastRev = -1;
    private boolean flashOn = true;

    // Link
    private NsdManager nsd;
    private NsdManager.RegistrationListener nsdListener;
    private volatile OutputStream phoneOut;
    private volatile boolean running = true;
    private ServerSocket serverSocket;

    // Input
    private long pressStart = 0;
    private float downX, downY;
    private boolean helpFired = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        // Never pop the (full-screen, landscape) keyboard on launch; it hides the whole display.
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        root.setFocusableInTouchMode(true);   // take initial focus away from the reply box
        standalonePanel = buildStandalone();
        vocalPanel = buildVocal();
        root.addView(standalonePanel);
        root.addView(vocalPanel);
        vocalPanel.setVisibility(View.GONE);
        setContentView(root);
        root.requestFocus();
        speaker = new TextToSpeech(this, this);
        requestPermissionsIfNeeded();
        registerService();
        startServer();
        // Demo shortcut (from a Mac over USB, no effect on the iPhone link):
        //   adb shell am broadcast -a com.replymaster.glasseshello.DEMO
        registerReceiver(new android.content.BroadcastReceiver() {
            @Override public void onReceive(android.content.Context c, Intent i) {
                String caption = i.getStringExtra("caption");
                if (caption == null) caption = "Do you want some water?";
                try {
                    JSONObject o = new JSONObject();
                    o.put("state", "listening");
                    o.put("caption", caption);
                    o.put("mic", "listening");
                    o.put("replies", new org.json.JSONArray(java.util.Arrays.asList("Yes, please", "Not right now", "Maybe later")));
                    o.put("quick", new org.json.JSONArray(java.util.Arrays.asList("Yes", "No", "Wait", "Repeat please", "Thank you", "Haha")));
                    standalonePanel.setVisibility(View.GONE);
                    vocalPanel.setVisibility(View.VISIBLE);
                    apply(o.toString());
                } catch (Exception ignored) { }
            }
        }, new android.content.IntentFilter("com.replymaster.glasseshello.DEMO"));
        ui.post(flasher);
    }

    // ---------------------------------------------------------------- standalone (Albert's PoC)

    private View buildStandalone() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(36, 24, 36, 24);
        root.setBackgroundColor(Color.BLACK);

        TextView title = text("Vocal Standalone", 28, Color.WHITE);
        title.setGravity(Gravity.CENTER);
        root.addView(title, fullWidth());

        status = text("Ready on glasses\nVocal link: " + localAddress() + ":" + PORT, 18, GREEN);
        status.setGravity(Gravity.CENTER);
        root.addView(status, fullWidth());

        reply = new EditText(this);
        reply.setHint("Type a reply");
        reply.setHintTextColor(Color.GRAY);
        reply.setTextColor(Color.WHITE);
        reply.setTextSize(24);
        reply.setImeOptions(EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN);
        root.addView(reply, fullWidth());

        Button listen = button("Listen");
        listen.setOnClickListener(v -> listen());
        root.addView(listen, fullWidth());

        Button speak = button("Speak Reply");
        speak.setOnClickListener(v -> speak(reply.getText().toString()));
        root.addView(speak, fullWidth());

        Button camera = button("Take Photo");
        camera.setOnClickListener(v -> takePhoto());
        root.addView(camera, fullWidth());
        return root;
    }

    private void listen() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) { status.setText("Speech recognition unavailable"); return; }
        if (recognizer != null) recognizer.destroy();
        recognizer = SpeechRecognizer.createSpeechRecognizer(this);
        recognizer.setRecognitionListener(new RecognitionListener() {
            @Override public void onReadyForSpeech(Bundle p) { status.setText("Listening…"); }
            @Override public void onBeginningOfSpeech() { }
            @Override public void onRmsChanged(float r) { }
            @Override public void onBufferReceived(byte[] b) { }
            @Override public void onEndOfSpeech() { status.setText("Processing…"); }
            @Override public void onError(int e) { status.setText("Speech error: " + e); }
            @Override public void onResults(Bundle results) {
                ArrayList<String> v = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                if (v != null && !v.isEmpty()) { reply.setText(v.get(0)); status.setText("Heard it"); }
            }
            @Override public void onPartialResults(Bundle r) { }
            @Override public void onEvent(int t, Bundle p) { }
        });
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US.toLanguageTag());
        intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
        recognizer.startListening(intent);
    }

    private void speak(String t) {
        if (t.trim().isEmpty()) { status.setText("Enter or say a reply first"); return; }
        status.setText("Speaking…");
        speaker.speak(t, TextToSpeech.QUEUE_FLUSH, null, "reply");
    }

    private void takePhoto() {
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        if (intent.resolveActivity(getPackageManager()) == null) { status.setText("Camera unavailable"); return; }
        launchingOwnActivity = true;   // our own photo capture: don't bounce back from it
        startActivityForResult(intent, REQUEST_CAMERA);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_CAMERA && resultCode == RESULT_OK) {
            Bitmap image = data == null ? null : (Bitmap) data.getParcelableExtra("data");
            status.setText(image == null ? "Photo captured" : "Photo captured: " + image.getWidth() + "×" + image.getHeight());
        }
    }

    // ---------------------------------------------------------------- Vocal panel (v3 screen)

    private FrameLayout buildVocal() {
        FrameLayout frame = new FrameLayout(this);
        frame.setBackgroundColor(Color.BLACK);

        listPanel = new LinearLayout(this);
        listPanel.setOrientation(LinearLayout.VERTICAL);
        listPanel.setPadding(24, 16, 24, 12);
        captionView = text("", 24, GREEN);
        captionView.setSingleLine(true);
        captionView.setEllipsize(TextUtils.TruncateAt.START);
        listPanel.addView(captionView, fullWidth());
        View spacer = new View(this);
        listPanel.addView(spacer, new LinearLayout.LayoutParams(-1, 14));
        frame.addView(listPanel, new FrameLayout.LayoutParams(-1, -1));

        bigView = text("", 40, GREEN);
        bigView.setTypeface(Typeface.DEFAULT_BOLD);
        bigView.setGravity(Gravity.CENTER_HORIZONTAL | Gravity.TOP);
        bigView.setPadding(24, 40, 24, 24);
        frame.addView(bigView, new FrameLayout.LayoutParams(-1, -1));

        countdownView = text("", 44, Color.BLACK);
        countdownView.setTypeface(Typeface.DEFAULT_BOLD);
        countdownView.setBackgroundColor(GREEN);
        countdownView.setGravity(Gravity.CENTER);
        countdownView.setVisibility(View.GONE);
        frame.addView(countdownView, new FrameLayout.LayoutParams(-1, 120, Gravity.TOP));

        footerView = text("", 14, Color.GRAY);
        frame.addView(footerView, new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.END));
        return frame;
    }

    /** Scan list = replies, then quick phrases, then the tone item. */
    private int itemCount() { return replies.size() + quick.size() + 1; }
    private boolean isToneItem(int i) { return i == replies.size() + quick.size(); }
    private String itemText(int i) {
        if (i < replies.size()) return replies.get(i);
        if (i < replies.size() + quick.size()) return quick.get(i - replies.size());
        return "Tone: " + TONES[toneIndex];
    }

    private void renderVocal() {
        boolean special = state.equals("speaking") || state.equals("help");
        listPanel.setVisibility(special ? View.GONE : View.VISIBLE);
        bigView.setVisibility(special ? View.VISIBLE : View.GONE);
        if (state.equals("help")) {
            bigView.setTextSize(64);
            bigView.setText("\nHELP SENT");
            bigView.setTextColor(flashOn ? GREEN : Color.rgb(0, 70, 30));
            return;
        }
        if (state.equals("speaking")) {
            bigView.setTextSize(40);
            bigView.setTextColor(GREEN);
            bigView.setText("Said: " + said);
            return;
        }
        captionView.setText(caption.isEmpty() ? (mic.equals("listening") ? "Listening…" : "Mic " + mic) : "“" + caption + "”");

        // Rebuild rows if the count changed.
        int n = itemCount();
        while (itemViews.size() > n) listPanel.removeView(itemViews.remove(itemViews.size() - 1));
        while (itemViews.size() < n) {
            TextView row = text("", 26, GREEN);
            row.setSingleLine(true);
            row.setEllipsize(TextUtils.TruncateAt.END);
            row.setPadding(10, 2, 10, 2);
            itemViews.add(row);
            listPanel.addView(row, fullWidth());
        }
        if (highlight >= n) highlight = n - 1;
        for (int i = 0; i < n; i++) {
            TextView row = itemViews.get(i);
            boolean hl = i == highlight;
            boolean reply = i < replies.size();
            String label = itemText(i);
            if (hl && !isToneItem(i)) label = label + "   [" + TONES[toneIndex] + "]";
            row.setText(label);
            row.setTextSize(reply ? 28 : (isToneItem(i) ? 20 : 22));
            row.setTypeface(reply ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT);
            row.setTextColor(hl ? Color.BLACK : GREEN);          // inversion, not colour coding
            row.setBackgroundColor(hl ? GREEN : Color.BLACK);
        }
    }

    private final Runnable flasher = new Runnable() {
        @Override public void run() {
            flashOn = !flashOn;
            if (vocalPanel.getVisibility() == View.VISIBLE && state.equals("help")) renderVocal();
            ui.postDelayed(this, 400);
        }
    };

    // ---------------------------------------------------------------- input: next / select / hold-for-HELP

    private void next() {
        if (!isVocal() || state.equals("help") || state.equals("speaking")) return;
        if (highlight < 0) { highlight = 0; send("{\"action\":\"choosing\"}"); }
        else highlight = (highlight + 1) % itemCount();
        renderVocal();
        ui.removeCallbacks(autoScan);
        ui.postDelayed(autoScan, SCAN_MS);
    }

    /** One-switch scanning: once scanning starts, the highlight steps on by itself; one press selects. */
    private static final long SCAN_MS = 1400;
    private final Runnable autoScan = new Runnable() {
        @Override public void run() {
            if (!isVocal() || highlight < 0 || state.equals("help") || state.equals("speaking")) return;
            highlight = (highlight + 1) % itemCount();
            renderVocal();
            ui.postDelayed(this, SCAN_MS);
        }
    };

    // The M6 system opens its camera app ~0.3 s after the action button is released. While the iPhone is
    // linked (Vocal screen showing), always come straight back so an accidental press never hides the replies.
    private long lastActionButtonAt = 0;
    private boolean launchingOwnActivity = false;

    @Override
    protected void onResume() {
        super.onResume();
        launchingOwnActivity = false;
    }

    @Override
    protected void onPause() {
        super.onPause();
        boolean recentAction = System.currentTimeMillis() - lastActionButtonAt < 2500;
        if (!isFinishing() && !launchingOwnActivity && (isVocal() || recentAction)) {
            ui.postDelayed(() -> {
                if (isFinishing()) return;
                Intent back = new Intent(this, MainActivity.class);
                back.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(back);
            }, 700);
        }
    }

    private void select() {
        if (!isVocal() || state.equals("speaking")) return;
        if (state.equals("help")) { send("{\"action\":\"help_cancel\"}"); return; }
        if (highlight < 0) { next(); return; }            // first press starts scanning
        if (isToneItem(highlight)) { toneIndex = (toneIndex + 1) % TONES.length; renderVocal(); return; }
        try {
            JSONObject o = new JSONObject();
            o.put("action", "select");
            o.put("text", itemText(highlight));
            o.put("tone", TONES[toneIndex]);
            send(o.toString());
        } catch (Exception ignored) { }
        highlight = -1;
        renderVocal();
    }

    private void beginHold() {
        pressStart = System.currentTimeMillis();
        helpFired = false;
        ui.removeCallbacks(holdTick);
        ui.postDelayed(holdTick, 600);                    // short taps never show the countdown
    }

    /** Returns true if the hold turned into HELP (so the release must not also select). */
    private boolean endHold() {
        ui.removeCallbacks(holdTick);
        countdownView.setVisibility(View.GONE);
        return helpFired;
    }

    private final Runnable holdTick = new Runnable() {
        @Override public void run() {
            if (!isVocal() || state.equals("help")) return;
            long held = System.currentTimeMillis() - pressStart;
            if (held >= HELP_HOLD_MS) {
                helpFired = true;
                countdownView.setVisibility(View.GONE);
                send("{\"action\":\"help\"}");
                return;
            }
            long left = (HELP_HOLD_MS - held + 999) / 1000;
            countdownView.setText("HELP in " + left + "…");
            countdownView.setVisibility(View.VISIBLE);
            ui.postDelayed(this, 100);
        }
    };

    private boolean isNextKey(int k) {
        return k == KeyEvent.KEYCODE_DPAD_RIGHT || k == KeyEvent.KEYCODE_DPAD_DOWN || k == KeyEvent.KEYCODE_TAB
                || k == KeyEvent.KEYCODE_DPAD_LEFT || k == KeyEvent.KEYCODE_DPAD_UP || k == KeyEvent.KEYCODE_PAGE_DOWN
                || k == KeyEvent.KEYCODE_MEDIA_NEXT || k == KeyEvent.KEYCODE_VOLUME_DOWN;
    }

    private boolean isSelectKey(int k) {
        return k == KeyEvent.KEYCODE_ENTER || k == KeyEvent.KEYCODE_DPAD_CENTER || k == KeyEvent.KEYCODE_NUMPAD_ENTER
                || k == KeyEvent.KEYCODE_SPACE || k == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || k == KeyEvent.KEYCODE_HEADSETHOOK
                || k == KeyEvent.KEYCODE_BUTTON_A || k == KeyEvent.KEYCODE_VOLUME_UP
                || k == KeyEvent.KEYCODE_MENU;   // 139 = M6 action button (system also opens the camera on it)
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        if (!isVocal()) return super.dispatchKeyEvent(e);
        int k = e.getKeyCode();
        footerView.setText("key " + KeyEvent.keyCodeToString(k));
        android.util.Log.d("VocalGlasses", "key " + k + " action=" + e.getAction());
        if (k == KeyEvent.KEYCODE_MENU) lastActionButtonAt = System.currentTimeMillis();
        // M6 temple touchpad gestures arrive as these vendor key codes (seen in logcat: F11, F12, O, E, M, L).
        // With auto-scan, any touchpad gesture acts as the single switch: start scanning / select.
        if (k == KeyEvent.KEYCODE_F11 || k == KeyEvent.KEYCODE_F12 || k == KeyEvent.KEYCODE_O
                || k == KeyEvent.KEYCODE_E || k == KeyEvent.KEYCODE_M || k == KeyEvent.KEYCODE_L) {
            if (e.getAction() == KeyEvent.ACTION_UP) select();
            return true;
        }
        if (k == KeyEvent.KEYCODE_BACK) {       // don't let a touchpad gesture close the app; it stops scanning
            if (e.getAction() == KeyEvent.ACTION_UP && highlight >= 0) {
                highlight = -1; ui.removeCallbacks(autoScan); send("{\"action\":\"cancel\"}"); renderVocal();
            }
            return true;
        }
        if (isSelectKey(k)) {
            if (e.getAction() == KeyEvent.ACTION_DOWN && e.getRepeatCount() == 0) beginHold();
            if (e.getAction() == KeyEvent.ACTION_UP && !endHold()) select();
            return true;
        }
        if (isNextKey(k)) {
            if (e.getAction() == KeyEvent.ACTION_DOWN) next();
            return true;
        }
        return super.dispatchKeyEvent(e);
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent e) {
        if (!isVocal()) return super.dispatchTouchEvent(e);
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downX = e.getX(); downY = e.getY();
                beginHold();
                return true;
            case MotionEvent.ACTION_UP: {
                float dx = e.getX() - downX, dy = e.getY() - downY;
                boolean help = endHold();
                footerView.setText(String.format(Locale.US, "touch dx=%.0f dy=%.0f", dx, dy));
                if (help) return true;
                if (Math.abs(dx) > 60 || Math.abs(dy) > 60) next(); else select();
                return true;
            }
            case MotionEvent.ACTION_CANCEL:
                endHold();
                return true;
            default:
                return true;
        }
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent e) {
        if (isVocal() && e.getActionMasked() == MotionEvent.ACTION_SCROLL) {
            footerView.setText("scroll");
            next();
            return true;
        }
        return super.dispatchGenericMotionEvent(e);
    }

    // ---------------------------------------------------------------- link to the iPhone

    private boolean isVocal() { return vocalPanel.getVisibility() == View.VISIBLE; }

    private void registerService() {
        try {
            nsd = (NsdManager) getSystemService(NSD_SERVICE);
            NsdServiceInfo service = new NsdServiceInfo();
            service.setServiceName("ReplyMaster-Glasses");
            service.setServiceType("_replymaster._tcp");
            service.setPort(PORT);
            nsdListener = new NsdManager.RegistrationListener() {
                @Override public void onServiceRegistered(NsdServiceInfo i) { }
                @Override public void onRegistrationFailed(NsdServiceInfo i, int c) { }
                @Override public void onServiceUnregistered(NsdServiceInfo i) { }
                @Override public void onUnregistrationFailed(NsdServiceInfo i, int c) { }
            };
            nsd.registerService(service, NsdManager.PROTOCOL_DNS_SD, nsdListener);
        } catch (Exception ignored) { }
    }

    private volatile Socket currentClient;

    /** Listen forever: retry if the port can't be bound yet, and let a new phone connection replace a stale one. */
    private void startServer() {
        new Thread(() -> {
            while (running) {
                try (ServerSocket server = new ServerSocket()) {
                    server.setReuseAddress(true);
                    server.bind(new java.net.InetSocketAddress(PORT));
                    serverSocket = server;
                    while (running) {
                        Socket client = server.accept();
                        client.setTcpNoDelay(true);
                        client.setKeepAlive(true);
                        Socket old = currentClient;
                        currentClient = client;
                        if (old != null) { try { old.close(); } catch (Exception ignored) { } }
                        new Thread(() -> handleClient(client), "vocal-client").start();
                    }
                } catch (Exception e) {
                    if (!running) return;
                    ui.post(() -> status.setText("Vocal link restarting… " + e.getMessage()));
                    try { Thread.sleep(1000); } catch (InterruptedException ie) { return; }
                }
            }
        }, "vocal-server").start();
    }

    private void handleClient(Socket client) {
        try (Socket c = client;
             BufferedReader in = new BufferedReader(new InputStreamReader(c.getInputStream(), StandardCharsets.UTF_8))) {
            phoneOut = c.getOutputStream();
            lastRev = -1;
            ui.post(() -> { hideKeyboard(); highlight = -1; standalonePanel.setVisibility(View.GONE); vocalPanel.setVisibility(View.VISIBLE); renderVocal(); });
            String line;
            while ((line = in.readLine()) != null) {
                if (line.length() > 4_000_000 || (line.length() > 16384 && !line.contains("\"audio\""))) continue;
                final String l = line;
                ui.post(() -> apply(l));
            }
        } catch (Exception ignored) {
        } finally {
            if (client != currentClient) return;   // replaced by a newer phone connection; leave its screen alone
            phoneOut = null;
            ui.post(() -> {
                endHold();
                vocalPanel.setVisibility(View.GONE);
                standalonePanel.setVisibility(View.VISIBLE);
                status.setText("iPhone disconnected\nVocal link: " + localAddress() + ":" + PORT);
            });
        }
    }

    /** Apply one snapshot line from the iPhone. */
    private void apply(String line) {
        try {
            JSONObject o = new JSONObject(line);
            if ("audio".equals(o.optString("type"))) { playPcm(o.optString("pcm16", ""), o.optInt("rate", 22050)); return; }
            if (o.has("rev")) {
                int rev = o.optInt("rev", -1);
                if (rev >= 0 && rev <= lastRev) return;      // stale / out of order
                lastRev = rev;
            }
            if (!o.has("state")) {                            // plain caption sender (e.g. Vocal Captions app)
                caption = o.optString("text", "");
                state = "listening";
                renderVocal();
                return;
            }
            String newState = o.optString("state", "listening");
            caption = o.optString("caption", "");
            String newSaid = o.isNull("said") ? "" : o.optString("said", "");
            said = newSaid;
            mic = o.optString("mic", "off");
            List<String> newReplies = strings(o.optJSONArray("replies"));
            boolean repliesChanged = !newReplies.equals(replies);
            replies.clear(); replies.addAll(newReplies);
            quick.clear(); quick.addAll(strings(o.optJSONArray("quick")));
            // Leave scanning when the phone moves on (spoke, HELP, or new replies arrived while listening).
            if (!newState.equals("choosing") && (!newState.equals(state) || repliesChanged)) highlight = -1;
            state = newState;
            renderVocal();
        } catch (Exception ignored) { }
    }

    private android.media.AudioTrack track;

    /** Play a spoken reply rendered on the iPhone (base64 16-bit mono PCM) through the glasses speakers. */
    private void playPcm(String b64, int rate) {
        if (b64.isEmpty()) return;
        try {
            byte[] pcm = android.util.Base64.decode(b64, android.util.Base64.DEFAULT);
            android.media.AudioManager am = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
            if (am != null) am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC,
                    am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC), 0);
            if (track != null) { try { track.stop(); } catch (Exception ignored) { } track.release(); }
            track = new android.media.AudioTrack(android.media.AudioManager.STREAM_MUSIC, rate,
                    android.media.AudioFormat.CHANNEL_OUT_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT,
                    pcm.length, android.media.AudioTrack.MODE_STATIC);
            track.write(pcm, 0, pcm.length);
            track.play();
            android.util.Log.d("VocalGlasses", "playing " + pcm.length + " bytes @" + rate);
        } catch (Exception e) {
            android.util.Log.e("VocalGlasses", "audio failed", e);
        }
    }

    private static List<String> strings(JSONArray a) {
        List<String> out = new ArrayList<>();
        if (a == null) return out;
        for (int i = 0; i < a.length(); i++) out.add(a.optString(i));
        return out;
    }

    private void send(String json) {
        final OutputStream out = phoneOut;
        footerView.setText(json.length() > 40 ? json.substring(0, 40) + "…" : json);
        if (out == null) return;
        new Thread(() -> {
            try {
                synchronized (MainActivity.this) {
                    out.write((json + "\n").getBytes(StandardCharsets.UTF_8));
                    out.flush();
                }
            } catch (Exception ignored) { }
        }).start();
    }

    // ---------------------------------------------------------------- helpers / lifecycle

    private void hideKeyboard() {
        InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
        if (imm != null && reply != null) imm.hideSoftInputFromWindow(reply.getWindowToken(), 0);
        reply.clearFocus();
    }

    private TextView text(String s, int sp, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(color);
        return t;
    }

    private LinearLayout.LayoutParams fullWidth() {
        return new LinearLayout.LayoutParams(-1, LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private Button button(String label) {
        Button b = new Button(this);
        b.setText(label);
        b.setTextSize(20);
        return b;
    }

    private void requestPermissionsIfNeeded() {
        if (android.os.Build.VERSION.SDK_INT >= 23) {
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA}, REQUEST_PERMISSIONS);
        }
    }

    private String localAddress() {
        try {
            Enumeration<NetworkInterface> ifs = NetworkInterface.getNetworkInterfaces();
            while (ifs.hasMoreElements()) {
                Enumeration<java.net.InetAddress> as = ifs.nextElement().getInetAddresses();
                while (as.hasMoreElements()) {
                    java.net.InetAddress a = as.nextElement();
                    if (!a.isLoopbackAddress() && a instanceof Inet4Address) return a.getHostAddress();
                }
            }
        } catch (Exception ignored) { }
        return "no Wi-Fi";
    }

    @Override
    public void onInit(int result) {
        if (result == TextToSpeech.SUCCESS) speaker.setLanguage(Locale.US);
    }

    @Override
    protected void onDestroy() {
        running = false;
        ui.removeCallbacksAndMessages(null);
        try { if (serverSocket != null) serverSocket.close(); } catch (Exception ignored) { }
        if (nsd != null && nsdListener != null) { try { nsd.unregisterService(nsdListener); } catch (Exception ignored) { } }
        if (recognizer != null) recognizer.destroy();
        if (speaker != null) { speaker.stop(); speaker.shutdown(); }
        super.onDestroy();
    }
}
