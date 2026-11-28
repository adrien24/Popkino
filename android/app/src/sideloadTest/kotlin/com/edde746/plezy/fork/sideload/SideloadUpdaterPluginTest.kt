package com.edde746.plezy.fork.sideload

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.reflect.Proxy
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class SideloadUpdaterPluginTest {
  private val context = RuntimeEnvironment.getApplication()
  private lateinit var apk: File
  private var inspection = ApkInspection(ApkStatus.Ok, "1.0.0", 6)
  private val inspected = mutableListOf<File>()

  @Before
  fun setUp() {
    val dir = File(context.cacheDir, UpdatesPath.DIR_NAME).also { it.mkdirs() }
    apk = File(dir, "popkino-1.0.0-armeabi-v7a.apk").also { it.writeText("x") }
  }

  private fun newPlugin(attachActivity: Activity? = Robolectric.buildActivity(Activity::class.java).get()): Pair<SideloadUpdaterPlugin, Activity?> {
    val plugin = SideloadUpdaterPlugin(
      Dispatchers.Unconfined,
      Dispatchers.Unconfined,
      inspect = { _, file ->
        inspected += file
        inspection
      },
      contentUriFor = { context, file -> Uri.parse("content://${context.packageName}.fileprovider/cache/updates/${file.name}") }
    )
    plugin.onAttachedToEngine(pluginBinding())
    if (attachActivity != null) plugin.onAttachedToActivity(activityBinding(attachActivity))
    return plugin to attachActivity
  }

  private fun call(plugin: SideloadUpdaterPlugin, method: String, path: String? = apk.path): Recorded {
    val result = Recorded()
    plugin.onMethodCall(MethodCall(method, path?.let { mapOf("path" to it) }), result)
    return result
  }

  @Test
  fun unknownMethodIsNotImplemented() {
    val (plugin, _) = newPlugin()
    assertTrue(call(plugin, "nope").notImplemented)
  }

  @Test
  fun inspectApkReportsTheInspectionAndRefusesForeignPaths() {
    val (plugin, _) = newPlugin()
    inspection = ApkInspection(ApkStatus.SignatureMismatch, "1.0.0", 6)
    val ok = call(plugin, "inspectApk")
    assertEquals(mapOf("status" to "signatureMismatch", "versionName" to "1.0.0", "versionCode" to 6L), ok.value)

    val foreign = call(plugin, "inspectApk", path = File(context.cacheDir, "x.apk").path)
    assertEquals(mapOf("status" to "invalid"), foreign.value)
    assertEquals(listOf(apk.canonicalFile), inspected)
  }

  @Test
  fun installOutsideTheUpdatesFolderIsRejectedWithoutInspecting() {
    val (plugin, _) = newPlugin()
    assertEquals("invalidPath", call(plugin, "install", path = "/system/app/x.apk").value)
    assertEquals("invalidPath", call(plugin, "install", path = null).value)
    assertTrue(inspected.isEmpty())
  }

  @Test
  fun failedInspectionIsReturnedAsIs() {
    val (plugin, activity) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)
    for (status in listOf(ApkStatus.Invalid, ApkStatus.SignatureMismatch, ApkStatus.NotNewer)) {
      inspection = ApkInspection(status)
      assertEquals(status.wire, call(plugin, "install").value)
    }
    inspection = ApkInspection(ApkStatus.WrongPackage)
    assertEquals("failed:wrongPackage", call(plugin, "install").value)
    assertNull(shadowOf(activity).nextStartedActivityForResult)
  }

  @Test
  fun missingPermissionIsReportedBeforeTheInstallerStarts() {
    val (plugin, activity) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(false)
    assertEquals("permissionRequired", call(plugin, "install").value)
    assertNull(shadowOf(activity).nextStartedActivityForResult)
  }

  @Test
  fun installWithoutAnActivityIsUnavailable() {
    val (plugin, _) = newPlugin(attachActivity = null)
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)
    assertEquals("installerUnavailable", call(plugin, "install").value)
  }

  @Test
  fun installerIsStartedWithTheExpectedIntentAndAnswersOnActivityResult() {
    val (plugin, activity) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)

    val result = call(plugin, "install")
    assertTrue("answer must wait for the installer", !result.answered)

    val started = shadowOf(activity).nextStartedActivityForResult
    @Suppress("DEPRECATION")
    val installAction = Intent.ACTION_INSTALL_PACKAGE
    assertEquals(installAction, started.intent.action)
    assertEquals(InstallResults.REQUEST_CODE, started.requestCode)
    assertTrue(started.intent.getBooleanExtra(Intent.EXTRA_RETURN_RESULT, false))
    assertTrue(started.intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
    assertEquals("content", started.intent.data?.scheme)
    assertEquals("${context.packageName}.fileprovider", started.intent.data?.authority)

    assertEquals(false, plugin.onActivityResult(7461, Activity.RESULT_OK, null))
    assertTrue(!result.answered)
    assertEquals(true, plugin.onActivityResult(InstallResults.REQUEST_CODE, Activity.RESULT_CANCELED, null))
    assertEquals("cancelled", result.value)
  }

  @Test
  fun secondInstallWhileTheFirstIsPendingIsBusy() {
    val (plugin, _) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)

    val first = call(plugin, "install")
    assertEquals("busy", call(plugin, "install").value)
    assertTrue(!first.answered)

    plugin.onActivityResult(InstallResults.REQUEST_CODE, Activity.RESULT_CANCELED, null)
    assertEquals("cancelled", first.value)
    // The slot is free again.
    val third = call(plugin, "install")
    assertTrue(!third.answered)
  }

  @Test
  fun detachingTheActivityFailsThePendingInstall() {
    val (plugin, _) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)
    val pending = call(plugin, "install")

    plugin.onDetachedFromActivity()

    assertEquals("ACTIVITY_DESTROYED", pending.errorCode)
    // A later result is not routed to anyone and the next install can start (without activity here).
    assertEquals("installerUnavailable", call(plugin, "install").value)
  }

  @Test
  fun configChangeKeepsThePendingInstall() {
    val (plugin, _) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)
    val pending = call(plugin, "install")

    plugin.onDetachedFromActivityForConfigChanges()
    plugin.onReattachedToActivityForConfigChanges(activityBinding(Robolectric.buildActivity(Activity::class.java).get()))
    plugin.onActivityResult(InstallResults.REQUEST_CODE, Activity.RESULT_OK, null)

    assertEquals("installed", pending.value)
  }

  @Test
  fun detachingTheEngineFailsThePendingInstallAndRefusesNewCalls() {
    val (plugin, _) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)
    val pending = call(plugin, "install")

    plugin.onDetachedFromEngine(pluginBinding())

    assertEquals("ACTIVITY_DESTROYED", pending.errorCode)
    assertEquals("DETACHED", call(plugin, "canRequestInstalls").errorCode)
  }

  @Test
  fun permissionAndStorageQueriesAnswerDirectly() {
    val (plugin, _) = newPlugin()
    shadowOf(context.packageManager).setCanRequestPackageInstalls(true)
    assertEquals(true, call(plugin, "canRequestInstalls", path = null).value)
    assertTrue((call(plugin, "availableBytes", path = null).value as Long) >= 0)
    assertTrue(call(plugin, "openInstallSettings", path = null).value is String)
  }

  private class Recorded : MethodChannel.Result {
    var answered = false
    var value: Any? = null
    var errorCode: String? = null
    var notImplemented = false

    override fun success(result: Any?) {
      answered = true
      value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
      answered = true
      this.errorCode = errorCode
    }

    override fun notImplemented() {
      answered = true
      notImplemented = true
    }
  }

  private fun pluginBinding(): FlutterPlugin.FlutterPluginBinding {
    val messenger = Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader, arrayOf(BinaryMessenger::class.java)) { _, _, _ ->
      null
    } as BinaryMessenger
    val constructor = FlutterPlugin.FlutterPluginBinding::class.java.constructors.single()
    val arguments = constructor.parameterTypes.map { type ->
      when {
        Context::class.java.isAssignableFrom(type) -> context
        BinaryMessenger::class.java.isAssignableFrom(type) -> messenger
        else -> null
      }
    }.toTypedArray()
    return constructor.newInstance(*arguments) as FlutterPlugin.FlutterPluginBinding
  }

  private fun activityBinding(activity: Activity): ActivityPluginBinding = Proxy.newProxyInstance(
    ActivityPluginBinding::class.java.classLoader,
    arrayOf(ActivityPluginBinding::class.java)
  ) { _, method, _ -> if (method.name == "getActivity") activity else null } as ActivityPluginBinding
}
