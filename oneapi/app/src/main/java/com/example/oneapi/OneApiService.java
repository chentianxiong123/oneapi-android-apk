package com.example.oneapi;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import androidx.core.app.NotificationCompat;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.FileWriter;
import java.io.FileReader;

public class OneApiService extends Service {
    private static boolean running = false;

    public static boolean isRunning() {
        File pidFile = new File("/data/data/com.example.oneapi/files/oneapi.pid");
        if (!pidFile.exists()) return false;
        try (BufferedReader r = new BufferedReader(new FileReader(pidFile))) {
            String pid = r.readLine();
            if (pid == null || pid.isEmpty()) return false;
            Process p = Runtime.getRuntime().exec(new String[]{"sh", "-c", "kill -0 " + pid + " 2>/dev/null && echo alive"});
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String result = br.readLine();
            p.waitFor();
            return "alive".equals(result);
        } catch (Exception e) {
            return false;
        }
    }

    public static String getLog() {
        File logFile = new File("/data/data/com.example.oneapi/files/oneapi.log");
        if (!logFile.exists()) return null;
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"sh", "-c", "tail -200 " + logFile.getAbsolutePath()});
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line).append("\n");
            }
            p.waitFor();
            return sb.toString();
        } catch (Exception e) {
            return "Error reading log: " + e.getMessage();
        }
    }

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
                android.util.Log.e("OneApiService", "Error: " + e.getMessage(), e);
                running = false;
                stopSelf();
            }
        }).start();
        return START_NOT_STICKY;
    }

    private void startProcess(String port, String dns) throws Exception {
        File workDir = getFilesDir();
        File pidFile = new File(workDir, "oneapi.pid");
        File logFile = new File(workDir, "oneapi.log");
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

        String cmd = "cd " + workDir.getAbsolutePath() + " && " +
                     "export TIKTOKEN_CACHE_DIR=" + tokenDir.getAbsolutePath() + " && " +
                     "export GODEBUG=netdns=go=1 && " +
                     "export CUSTOM_RESOLV_CONF=" + resolvFile.getAbsolutePath() + " && " +
                     "export LD_PRELOAD=" + hookLib.getAbsolutePath() + " && " +
                     "setsid " + bin.getAbsolutePath() + " --port " + port +
                     " > " + logFile.getAbsolutePath() + " 2>&1 & echo $!";

        Process p = Runtime.getRuntime().exec(new String[]{"sh", "-c", cmd});
        String pid = new BufferedReader(new InputStreamReader(p.getInputStream())).readLine();
        p.waitFor();

        if (pid != null && !pid.isEmpty()) {
            try (FileWriter w = new FileWriter(pidFile)) {
                w.write(pid);
            }
            running = true;
            android.util.Log.i("OneApiService", "Started with PID: " + pid);
        }
    }

    public static void stopProcess() {
        File pidFile = new File("/data/data/com.example.oneapi/files/oneapi.pid");
        if (pidFile.exists()) {
            try (BufferedReader r = new BufferedReader(new FileReader(pidFile))) {
                String pid = r.readLine();
                if (pid != null && !pid.isEmpty()) {
                    Runtime.getRuntime().exec(new String[]{"sh", "-c", "kill " + pid + " 2>/dev/null"});
                }
            } catch (Exception e) {
                android.util.Log.e("OneApiService", "Error stopping: " + e.getMessage());
            }
            pidFile.delete();
        }
        running = false;
    }

    @Override
    public void onDestroy() {
        running = false;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}