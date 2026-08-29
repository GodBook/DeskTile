package com.desktile.desktile

import android.content.pm.PackageInstaller
import org.junit.Assert.assertEquals
import org.junit.Test

class UpdateInstallReceiverTest {
  @Test
  fun pendingUserActionRequestsConfirmation() {
    assertEquals(
        InstallStatusKind.CONFIRMATION_REQUIRED,
        classifyInstallStatus(PackageInstaller.STATUS_PENDING_USER_ACTION),
    )
  }

  @Test
  fun successfulInstallNeedsNoFurtherAction() {
    assertEquals(
        InstallStatusKind.SUCCESS,
        classifyInstallStatus(PackageInstaller.STATUS_SUCCESS),
    )
  }

  @Test
  fun installerErrorsAreFailures() {
    assertEquals(
        InstallStatusKind.FAILURE,
        classifyInstallStatus(PackageInstaller.STATUS_FAILURE_INVALID),
    )
  }
}
