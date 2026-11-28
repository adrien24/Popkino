package com.edde746.plezy.fork.sideload

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [25, 30])
class InstallPermissionTest {
  private val context = RuntimeEnvironment.getApplication()
  private val permission = InstallPermission(context)
  private val atLeastO = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

  @Suppress("DEPRECATION")
  private fun grant(granted: Boolean) {
    if (atLeastO) {
      shadowOf(context.packageManager).setCanRequestPackageInstalls(granted)
    } else {
      Settings.Secure.putInt(context.contentResolver, Settings.Secure.INSTALL_NON_MARKET_APPS, if (granted) 1 else 0)
    }
  }

  @Test
  fun permissionStateFollowsTheApiLevel() {
    grant(false)
    assertEquals(false, permission.canRequestInstalls())
    grant(true)
    assertEquals(true, permission.canRequestInstalls())
  }

  @Test
  fun candidatesAreTriedInTheDocumentedOrder() {
    val candidates = permission.candidates()
    val expected = if (atLeastO) {
      listOf(
        SettingsTarget.AppPermission,
        SettingsTarget.UnknownAppsList,
        SettingsTarget.DeveloperOptions,
        SettingsTarget.Security,
        SettingsTarget.Settings
      )
    } else {
      listOf(SettingsTarget.DeveloperOptions, SettingsTarget.Security, SettingsTarget.Settings)
    }
    assertEquals(expected, candidates.map { it.first })
    val actions = candidates.associate { it.first to it.second }
    if (atLeastO) {
      assertEquals(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, actions.getValue(SettingsTarget.AppPermission).action)
      assertEquals("package:${context.packageName}", actions.getValue(SettingsTarget.AppPermission).dataString)
      assertEquals(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, actions.getValue(SettingsTarget.UnknownAppsList).action)
      assertNull(actions.getValue(SettingsTarget.UnknownAppsList).data)
    }
    assertEquals(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS, actions.getValue(SettingsTarget.DeveloperOptions).action)
    assertEquals(Settings.ACTION_SECURITY_SETTINGS, actions.getValue(SettingsTarget.Security).action)
    assertEquals(Settings.ACTION_SETTINGS, actions.getValue(SettingsTarget.Settings).action)
  }

  @Test
  fun firstScreenThatStartsWinsAndNothingElseIsTried() {
    val started = mutableListOf<Intent>()
    val target = permission.openInstallSettings { started += it }
    assertEquals(permission.candidates().first().first, target)
    assertEquals(1, started.size)
  }

  @Test
  fun missingScreensFallBackToTheNextOne() {
    val all = permission.candidates()
    val started = mutableListOf<String?>()
    // Everything but the last candidate is missing (or refuses us).
    val target = permission.openInstallSettings { intent ->
      started += intent.action
      if (started.size < all.size) {
        if (started.size % 2 == 0) throw SecurityException("not exported") else throw ActivityNotFoundException()
      }
    }
    assertEquals(SettingsTarget.Settings, target)
    assertEquals(all.map { it.second.action }, started)
  }

  @Test
  fun noScreenAtAllReportsNone() {
    val target = permission.openInstallSettings { throw ActivityNotFoundException() }
    assertEquals(SettingsTarget.None, target)
  }
}
