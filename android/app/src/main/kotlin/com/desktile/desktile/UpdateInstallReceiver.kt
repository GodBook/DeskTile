package com.desktile.desktile

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageInstaller
import android.os.Build
import android.widget.Toast

internal enum class InstallStatusKind { CONFIRMATION_REQUIRED, SUCCESS, FAILURE }

internal fun classifyInstallStatus(status: Int): InstallStatusKind = when (status) {
  PackageInstaller.STATUS_PENDING_USER_ACTION -> InstallStatusKind.CONFIRMATION_REQUIRED
  PackageInstaller.STATUS_SUCCESS -> InstallStatusKind.SUCCESS
  else -> InstallStatusKind.FAILURE
}

class UpdateInstallReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != INSTALL_STATUS_ACTION) return

    val status = intent.getIntExtra(
        PackageInstaller.EXTRA_STATUS,
        PackageInstaller.STATUS_FAILURE,
    )
    when (classifyInstallStatus(status)) {
      InstallStatusKind.CONFIRMATION_REQUIRED -> openConfirmation(context, intent)
      InstallStatusKind.SUCCESS -> Unit
      InstallStatusKind.FAILURE -> showFailure(context, status)
    }
  }

  private fun openConfirmation(context: Context, callback: Intent) {
    val confirmation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      callback.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
    } else {
      @Suppress("DEPRECATION")
      callback.getParcelableExtra(Intent.EXTRA_INTENT)
    }
    if (confirmation == null) {
      showToast(context, "系统没有返回安装确认界面，请重新尝试更新")
      return
    }

    runCatching {
      confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(confirmation)
    }.onFailure {
      showToast(context, "无法打开系统安装确认界面，请重新尝试更新")
    }
  }

  private fun showFailure(context: Context, status: Int) {
    val message = when (status) {
      PackageInstaller.STATUS_FAILURE_ABORTED -> "安装已取消"
      PackageInstaller.STATUS_FAILURE_BLOCKED -> "系统已阻止安装，请检查安装未知应用权限"
      PackageInstaller.STATUS_FAILURE_CONFLICT -> "安装包与当前应用不兼容"
      PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "安装包不支持当前设备"
      PackageInstaller.STATUS_FAILURE_INVALID -> "安装包无效，请重新下载"
      PackageInstaller.STATUS_FAILURE_STORAGE -> "存储空间不足，无法完成更新"
      else -> "系统安装失败，请重新尝试更新"
    }
    showToast(context, message)
  }

  private fun showToast(context: Context, message: String) {
    Toast.makeText(context, message, Toast.LENGTH_LONG).show()
  }

  companion object {
    private const val INSTALL_STATUS_ACTION =
        "com.desktile.desktile.action.UPDATE_INSTALL_STATUS"

    fun intentSender(context: Context, sessionId: Int): IntentSender {
      val callback = Intent(context, UpdateInstallReceiver::class.java).apply {
        action = INSTALL_STATUS_ACTION
      }
      val flags = PendingIntent.FLAG_UPDATE_CURRENT or
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
          } else {
            0
          }
      return PendingIntent.getBroadcast(context, sessionId, callback, flags).intentSender
    }
  }
}
