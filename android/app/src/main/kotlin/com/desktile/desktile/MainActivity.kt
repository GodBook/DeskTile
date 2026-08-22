package com.desktile.desktile

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.desktile.desktile/system_settings",
    ).setMethodCallHandler { call, result ->
      if (call.method != "openAppDetails") {
        result.notImplemented()
        return@setMethodCallHandler
      }

      runCatching {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
              data = Uri.parse("package:$packageName")
            },
        )
      }.onSuccess {
        result.success(true)
      }.onFailure { error ->
        result.error("OPEN_SETTINGS_FAILED", error.message, null)
      }
    }
  }
}
