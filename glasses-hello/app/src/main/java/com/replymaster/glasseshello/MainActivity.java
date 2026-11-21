package com.replymaster.glasseshello;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.Inet4Address;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Enumeration;

import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;

public final class MainActivity extends Activity {
    private static final int PORT = 8787;
    private TextView message;
    private NsdManager nsdManager;
    private NsdManager.RegistrationListener registrationListener;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        message = new TextView(this);
        message.setText("Glasses Hello\n\nCaption server: " + localAddress() + ":" + PORT + "\nWaiting for iPhone…");
        message.setTextColor(Color.WHITE);
        message.setTextSize(24);
        message.setGravity(Gravity.CENTER);
        message.setBackgroundColor(Color.BLACK);
        setContentView(message);
        registerService();
        startCaptionServer();
    }

    private void registerService() {
        nsdManager = (NsdManager) getSystemService(NSD_SERVICE);
        NsdServiceInfo service = new NsdServiceInfo();
        service.setServiceName("ReplyMaster-Glasses");
        service.setServiceType("_replymaster._tcp");
        service.setPort(PORT);
        registrationListener = new NsdManager.RegistrationListener() {
            @Override public void onServiceRegistered(NsdServiceInfo info) { }
            @Override public void onRegistrationFailed(NsdServiceInfo info, int errorCode) { }
            @Override public void onServiceUnregistered(NsdServiceInfo info) { }
            @Override public void onUnregistrationFailed(NsdServiceInfo info, int errorCode) { }
        };
        nsdManager.registerService(service, NsdManager.PROTOCOL_DNS_SD, registrationListener);
    }

    @Override
    protected void onDestroy() {
        if (nsdManager != null && registrationListener != null) {
            nsdManager.unregisterService(registrationListener);
        }
        super.onDestroy();
    }

    private void startCaptionServer() {
        Thread serverThread = new Thread(() -> {
            try (ServerSocket server = new ServerSocket(PORT)) {
                while (!isFinishing()) {
                    try (Socket client = server.accept();
                         BufferedReader reader = new BufferedReader(new InputStreamReader(client.getInputStream()))) {
                        updateText("Connected to iPhone\n\nListening…");
                        String line;
                        while ((line = reader.readLine()) != null) {
                            JSONObject payload = new JSONObject(line);
                            if ("caption".equals(payload.optString("type"))) {
                                updateText(payload.optString("text", ""));
                            }
                        }
                    } catch (Exception ignored) {
                        updateText("Caption connection ended\n\nWaiting for iPhone…");
                    }
                }
            } catch (Exception error) {
                updateText("Caption server error\n\n" + error.getMessage());
            }
        });
        serverThread.start();
    }

    private void updateText(String text) {
        runOnUiThread(() -> message.setText(text));
    }

    private String localAddress() {
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces.hasMoreElements()) {
                Enumeration<java.net.InetAddress> addresses = interfaces.nextElement().getInetAddresses();
                while (addresses.hasMoreElements()) {
                    java.net.InetAddress address = addresses.nextElement();
                    if (!address.isLoopbackAddress() && address instanceof Inet4Address) {
                        return address.getHostAddress();
                    }
                }
            }
        } catch (Exception ignored) {
        }
        return "unknown IP";
    }
}
