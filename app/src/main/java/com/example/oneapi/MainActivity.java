package com.example.oneapi;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {
    private EditText portInput, dnsInput;
    private Button startStopBtn, openWebBtn;
    private TextView statusText, logText;
    private SharedPreferences prefs;
    private boolean running = false;
    private Handler handler = new Handler(Looper.getMainLooper());
    private Runnable logPoller;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        prefs = getSharedPreferences("oneapi_config", MODE_PRIVATE);

        portInput = findViewById(R.id.port_input);
        dnsInput = findViewById(R.id.dns_input);
        startStopBtn = findViewById(R.id.start_stop_btn);
        openWebBtn = findViewById(R.id.open_webview_btn);
        statusText = findViewById(R.id.status_text);
        logText = findViewById(R.id.log_text);
        logText.setMovementMethod(new ScrollingMovementMethod());

        portInput.setText(prefs.getString("port", "3000"));
        dnsInput.setText(prefs.getString("dns", "8.8.8.8, 8.8.4.4"));

        startStopBtn.setOnClickListener(v -> {
            if (running) {
                stopService(new Intent(this, OneApiService.class));
                startStopBtn.setText("启动");
                running = false;
                statusText.setText("状态: 已停止");
                openWebBtn.setEnabled(false);
                stopLogPoller();
            } else {
                String port = portInput.getText().toString().trim();
                String dns = dnsInput.getText().toString().trim();
                prefs.edit().putString("port", port).putString("dns", dns).apply();

                Intent intent = new Intent(this, OneApiService.class);
                intent.putExtra("port", port.isEmpty() ? "3000" : port);
                intent.putExtra("dns", dns.isEmpty() ? "8.8.8.8,8.8.4.4" : dns);
                startForegroundService(intent);

                startStopBtn.setText("停止");
                running = true;
                statusText.setText("状态: 启动中...");
                startLogPoller();
            }
        });

        openWebBtn.setOnClickListener(v -> {
            String port = portInput.getText().toString().trim();
            Intent intent = new Intent(this, WebViewActivity.class);
            intent.putExtra("port", port.isEmpty() ? "3000" : port);
            startActivity(intent);
        });
    }

    private void startLogPoller() {
        logPoller = new Runnable() {
            @Override
            public void run() {
                String log = OneApiService.getLog();
                if (log != null) {
                    logText.setText(log);
                    handler.postDelayed(this, 500);
                }
            }
        };
        handler.postDelayed(logPoller, 500);

        new android.os.Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (OneApiService.isRunning()) {
                statusText.setText("状态: 运行中");
                openWebBtn.setEnabled(true);
            } else {
                statusText.setText("状态: 已停止");
                startStopBtn.setText("启动");
                running = false;
                openWebBtn.setEnabled(false);
            }
        }, 3000);
    }

    private void stopLogPoller() {
        if (logPoller != null) {
            handler.removeCallbacks(logPoller);
            logPoller = null;
        }
    }

    @Override
    protected void onDestroy() {
        stopLogPoller();
        super.onDestroy();
    }
}