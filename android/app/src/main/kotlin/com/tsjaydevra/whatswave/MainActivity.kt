package com.tsjaydevra.whatswave

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

// FlutterFragmentActivity, not FlutterActivity: local_auth's Android
// implementation shows BiometricPrompt, which is a Fragment and needs a
// FragmentActivity host. With plain FlutterActivity the app builds and runs
// fine and then throws only when the user first tries to unlock.
class MainActivity : FlutterFragmentActivity() {
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
