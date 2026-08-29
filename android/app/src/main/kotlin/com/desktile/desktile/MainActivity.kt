package com.desktile.desktile

import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

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

    updateInstallerExecutor.execute {
      val installer = packageManager.packageInstaller
      var sessionId: Int? = null
      try {
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
          setAppPackageName(packageName)
          setSize(apk.length())
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setPackageSource(PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE)
          }
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
          }
        }
        sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
          apk.inputStream().buffered().use { input ->
            session.openWrite("desktile-update.apk", 0, apk.length()).use { output ->
              input.copyTo(output)
              session.fsync(output)
            }
          }
          session.commit(UpdateInstallReceiver.intentSender(this, sessionId))
        }
        runOnUiThread { result.success("started") }
      } catch (error: Exception) {
        sessionId?.let { id -> runCatching { installer.abandonSession(id) } }
        runOnUiThread {
          result.error(
              "INSTALLER_START_FAILED",
              "无法创建系统安装会话",
              error.message,
          )
        }
      }
    }
  }

  companion object {
    private val updateInstallerExecutor = Executors.newSingleThreadExecutor { runnable ->
      Thread(runnable, "desktile-update-installer")
    }
  }
}
