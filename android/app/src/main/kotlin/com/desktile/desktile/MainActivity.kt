package com.desktile.desktile

import android.content.ClipData
import android.content.pm.PackageInfo
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.desktile.desktile/app_update",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "getAppVersion" -> result.success(appVersionPayload())
        "installApk" -> installApk(call.argument<String>("path"), result)
        else -> result.notImplemented()
      }
    }
  }

  private fun appVersionPayload(): Map<String, Any> {
    val info: PackageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      packageManager.getPackageInfo(
          packageName,
          android.content.pm.PackageManager.PackageInfoFlags.of(0),
      )
    } else {
      @Suppress("DEPRECATION")
      packageManager.getPackageInfo(packageName, 0)
    }
    val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      info.longVersionCode
    } else {
      @Suppress("DEPRECATION")
      info.versionCode.toLong()
    }
    return mapOf("name" to (info.versionName ?: ""), "code" to code)
  }

  private fun installApk(path: String?, result: MethodChannel.Result) {
    if (path.isNullOrBlank()) {
      result.error("APK_NOT_FOUND", "更新文件路径为空", null)
      return
    }
    val apk = File(path)
    if (!apk.isFile) {
      result.error("APK_NOT_FOUND", "更新文件不存在或已被清理", null)
      return
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        !packageManager.canRequestPackageInstalls()) {
      runCatching {
        startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
              data = Uri.parse("package:$packageName")
            },
        )
      }.onFailure { error ->
        result.error("UNKNOWN_SOURCE_SETTINGS_FAILED", error.message, null)
        return
      }
      result.success("permission_required")
      return
    }

    runCatching {
      val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
      startActivity(
          Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            type = "application/vnd.android.package-archive"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            clipData = ClipData.newRawUri("DeskTile APK", uri)
          },
      )
    }.onSuccess {
      result.success("started")
    }.onFailure { error ->
      result.error("INSTALLER_START_FAILED", error.message, null)
    }
  }
}
