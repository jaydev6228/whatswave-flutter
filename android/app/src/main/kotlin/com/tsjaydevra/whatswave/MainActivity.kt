package com.tsjaydevra.whatswave

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
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
