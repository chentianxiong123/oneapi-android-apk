package com.example.oneapi;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.FileWriter;

public class OneApiService extends Service {
    private static Process process;
    private static StringBuilder logBuffer = new StringBuilder();
    private static boolean running = false;

    public static boolean isRunning() { return running; }
    public static String getLog() { return logBuffer != null ? logBuffer.toString() : null; }

    @Override
    public void onCreate() {
        super.onCreate();
        String channelId = "oneapi_channel";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(channelId, "OneAPI", NotificationManager.IMPORTANCE_LOW);
            getSystemService(NotificationManager.class).createNotificationChannel(ch);
        }
        Notification notification = new NotificationCompat.Builder(this, channelId)
                .setContentTitle("OneAPI")
                .setContentText("运行中")
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .build();
        startForeground(1, notification);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        String port = intent.getStringExtra("port");
        String dns = intent.getStringExtra("dns");
        if (port == null) port = "3000";
        if (dns == null) dns = "8.8.8.8,8.8.4.4";
        final String fPort = port;
        final String fDns = dns;

        new Thread(() -> {
            try {
                startProcess(fPort, fDns);
            } catch (Exception e) {
                Log.e("OneApiService", "Error: " + e.getMessage(), e);
                running = false;
                stopSelf();
            }
        }).start();
        return START_NOT_STICKY;
    }

    private void startProcess(String port, String dns) throws Exception {
        File workDir = getFilesDir();
        File bin = new File(getApplicationInfo().nativeLibraryDir, "liboneapi.so");

        File tokenDir = new File(workDir, "tiktoken");
        tokenDir.mkdirs();
        File tokenFile = new File(tokenDir, "cl100k_base.tiktoken");
        if (!tokenFile.exists()) {
            try (InputStream in = getAssets().open("cl100k_base.tiktoken");
                 FileOutputStream out = new FileOutputStream(tokenFile)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
            }
        }

        File resolvFile = new File(workDir, "resolv.conf");
        try (FileWriter w = new FileWriter(resolvFile)) {
            for (String s : dns.split("[,，\\s]+")) {
                s = s.trim();
                if (!s.isEmpty()) {
                    w.write("nameserver " + s + "\n");
                }
            }
        }

        File hookLib = new File(getApplicationInfo().nativeLibraryDir, "libdns_hook.so");

        ProcessBuilder pb = new ProcessBuilder(bin.getAbsolutePath(), "--port", port);
        pb.directory(workDir);
        pb.redirectErrorStream(true);
        pb.environment().put("TIKTOKEN_CACHE_DIR", tokenDir.getAbsolutePath());
        pb.environment().put("GODEBUG", "netdns=go=1");
        pb.environment().put("CUSTOM_RESOLV_CONF", resolvFile.getAbsolutePath());
        pb.environment().put("LD_PRELOAD", hookLib.getAbsolutePath());

        process = pb.start();
        running = true;

        try (BufferedReader r = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = r.readLine()) != null) {
                Log.i("OneApiOutput", line);
                if (logBuffer != null) {
                    if (logBuffer.length() > 50000) {
                        logBuffer.delete(0, 30000);
                    }
                    logBuffer.append(line).append("\n");
                }
            }
        }
        int exitCode = process.waitFor();
        Log.e("OneApiService", "Process exited with code " + exitCode);
        running = false;
        stopSelf();
    }

    @Override
    public void onDestroy() {
        if (process != null) {
            process.destroy();
            process = null;
        }
        running = false;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}