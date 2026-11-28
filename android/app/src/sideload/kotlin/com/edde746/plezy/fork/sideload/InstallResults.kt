package com.edde746.plezy.fork.sideload

import android.app.Activity
import android.content.Intent

/** Maps the system installer's `startActivityForResult` outcome to the Dart contract strings. */
internal object InstallResults {
  /** Request code of the installer intent; distinct from ExternalPlayerChannel's 7461. */
  const val REQUEST_CODE = 7462

  const val EXTRA_INSTALL_RESULT = "android.intent.extra.INSTALL_RESULT"

  private const val INSTALL_FAILED_INSUFFICIENT_STORAGE = -4
  private const val INSTALL_FAILED_UPDATE_INCOMPATIBLE = -7
  private const val INSTALL_FAILED_VERSION_DOWNGRADE = -25

  fun fromActivityResult(resultCode: Int, data: Intent?): String = when (resultCode) {
    Activity.RESULT_CANCELED -> "cancelled"
    Activity.RESULT_OK -> "installed"
    else -> when (val code = data?.getIntExtra(EXTRA_INSTALL_RESULT, 0) ?: 0) {
      INSTALL_FAILED_UPDATE_INCOMPATIBLE -> "signatureMismatch"
      INSTALL_FAILED_VERSION_DOWNGRADE -> "notNewer"
      INSTALL_FAILED_INSUFFICIENT_STORAGE -> "insufficientStorage"
      else -> "failed:$code"
    }
  }
}
