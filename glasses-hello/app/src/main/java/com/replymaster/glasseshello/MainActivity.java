package com.replymaster.glasseshello;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.provider.MediaStore;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Locale;

public final class MainActivity extends Activity implements TextToSpeech.OnInitListener {
    private static final int REQUEST_PERMISSIONS = 10;
    private static final int REQUEST_CAMERA = 11;
    private TextView status;
    private EditText reply;
    private SpeechRecognizer recognizer;
    private TextToSpeech speaker;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        buildView();
        speaker = new TextToSpeech(this, this);
        requestPermissionsIfNeeded();
    }

    private void buildView() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(36, 24, 36, 24);
        root.setBackgroundColor(Color.BLACK);

        TextView title = new TextView(this);
        title.setText("Vocal Standalone");
        title.setTextColor(Color.WHITE);
        title.setTextSize(28);
        title.setGravity(Gravity.CENTER);
        root.addView(title, fullWidth());

        status = new TextView(this);
        status.setText("Ready on glasses");
        status.setTextColor(Color.GREEN);
        status.setTextSize(20);
        status.setGravity(Gravity.CENTER);
        root.addView(status, fullWidth());

        reply = new EditText(this);
        reply.setHint("Type a reply");
        reply.setHintTextColor(Color.GRAY);
        reply.setTextColor(Color.WHITE);
        reply.setTextSize(24);
        root.addView(reply, fullWidth());

        Button listen = button("Listen");
        listen.setOnClickListener(view -> listen());
        root.addView(listen, fullWidth());

        Button speak = button("Speak Reply");
        speak.setOnClickListener(view -> speak(reply.getText().toString()));
        root.addView(speak, fullWidth());

        Button camera = button("Take Photo");
        camera.setOnClickListener(view -> takePhoto());
        root.addView(camera, fullWidth());

        setContentView(root);
    }

    private LinearLayout.LayoutParams fullWidth() {
        return new LinearLayout.LayoutParams(-1, LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private Button button(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextSize(20);
        return button;
    }

    private void requestPermissionsIfNeeded() {
        if (android.os.Build.VERSION.SDK_INT >= 23) {
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA}, REQUEST_PERMISSIONS);
        }
    }

    private void listen() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            status.setText("Speech recognition unavailable");
            return;
        }
        if (recognizer != null) recognizer.destroy();
        recognizer = SpeechRecognizer.createSpeechRecognizer(this);
        recognizer.setRecognitionListener(new RecognitionListener() {
            @Override public void onReadyForSpeech(Bundle params) { status.setText("Listening…"); }
            @Override public void onBeginningOfSpeech() { }
            @Override public void onRmsChanged(float rmsdB) { }
            @Override public void onBufferReceived(byte[] buffer) { }
            @Override public void onEndOfSpeech() { status.setText("Processing…"); }
            @Override public void onError(int error) { status.setText("Speech error: " + error); }
            @Override public void onResults(Bundle results) {
                ArrayList<String> values = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                if (values != null && !values.isEmpty()) {
                    reply.setText(values.get(0));
                    status.setText("Heard it");
                }
            }
            @Override public void onPartialResults(Bundle results) { }
            @Override public void onEvent(int eventType, Bundle params) { }
        });
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US.toLanguageTag());
        intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
        recognizer.startListening(intent);
    }

    private void speak(String text) {
        if (text.trim().isEmpty()) {
            status.setText("Enter or say a reply first");
            return;
        }
        status.setText("Speaking…");
        speaker.speak(text, TextToSpeech.QUEUE_FLUSH, null, "reply");
    }

    private void takePhoto() {
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        if (intent.resolveActivity(getPackageManager()) == null) {
            status.setText("Camera unavailable");
            return;
        }
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

    @Override
    public void onInit(int result) {
        if (result == TextToSpeech.SUCCESS) speaker.setLanguage(Locale.US);
    }

    @Override
    protected void onDestroy() {
        if (recognizer != null) recognizer.destroy();
        if (speaker != null) { speaker.stop(); speaker.shutdown(); }
        super.onDestroy();
    }
}
