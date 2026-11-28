package com.edde746.plezy.fork.sideload

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

/** Which settings screen [InstallPermission.openInstallSettings] actually opened. */
internal enum class SettingsTarget(val wire: String) {
  AppPermission("appPermission"),
  UnknownAppsList("unknownAppsList"),
  DeveloperOptions("developerOptions"),
  Security("security"),
  Settings("settings"),
  None("none")
}

/** The "install unknown apps" permission: state and the screens where the user grants it. */
internal class InstallPermission(private val context: Context) {
  @Suppress("DEPRECATION")
  fun canRequestInstalls(): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    context.packageManager.canRequestPackageInstalls()
  } else {
    // API 25 (Fire OS 6): a single global "unknown sources" switch.
    android.provider.Settings.Secure.getInt(context.contentResolver, android.provider.Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1
  }

  /** Intents tried by [openInstallSettings], in order. No `resolveActivity`, so no `<queries>` is needed. */
  fun candidates(): List<Pair<SettingsTarget, Intent>> = buildList {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      add(
        SettingsTarget.AppPermission to
          Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
      )
      add(SettingsTarget.UnknownAppsList to Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
    }
    add(SettingsTarget.DeveloperOptions to Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
    add(SettingsTarget.Security to Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS))
    add(SettingsTarget.Settings to Intent(android.provider.Settings.ACTION_SETTINGS))
  }

  /** Starts the first candidate that [start] accepts and returns it; [SettingsTarget.None] if none starts. */
  fun openInstallSettings(start: (Intent) -> Unit): SettingsTarget {
    for ((target, intent) in candidates()) {
      try {
        start(intent)
        return target
      } catch (_: ActivityNotFoundException) {
        // Not handled on this device: try the next screen.
      } catch (_: SecurityException) {
        // Screen not exported to us: same.
      }
    }
    return SettingsTarget.None
  }
}
