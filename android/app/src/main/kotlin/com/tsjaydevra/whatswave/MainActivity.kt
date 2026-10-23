package com.tsjaydevra.whatswave

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

// FlutterFragmentActivity, not FlutterActivity: local_auth's Android
// implementation shows BiometricPrompt, which is a Fragment and needs a
// FragmentActivity host. With plain FlutterActivity the app builds and runs
// fine and then throws only when the user first tries to unlock.
class MainActivity : FlutterFragmentActivity() {
    // Android 8+ drops any notification whose channel does not exist, with
    // no error anywhere -- the push simply never appears. The id must match
    // the manifest meta-data and functions/index.js.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "messages",
                "Messages",
                NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "New message notifications"
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "whatswave/app_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "deviceRegionCode" -> result.success(Locale.getDefault().country)
                else -> result.notImplemented()
            }
        }
    }
}
