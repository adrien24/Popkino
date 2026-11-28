package com.edde746.plezy.fork.sideload

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.StatFs
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Native half of the in-app update (GitHub APK builds only, see `ForkPlugins`): permission state,
 * APK inspection and hand-over to the system installer. The Dart contract lives in
 * `lib/fork/update/sideload_installer.dart`.
 *
 * Coroutines run on [mainDispatcher] (method results must be answered on the platform thread); the
 * heavy APK read hops to [ioDispatcher].
 */
internal class SideloadUpdaterPlugin(
  private val mainDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
  private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
  private val inspect: (Context, File) -> ApkInspection = { context, file -> ApkInspector.inspect(context, file) },
  // The FileProvider is declared in the merged manifest, which unit tests do not load.
  private val contentUriFor: (Context, File) -> Uri = { context, file ->
    FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
  }
) : FlutterPlugin,
  ActivityAware,
  PluginRegistry.ActivityResultListener,
  MethodChannel.MethodCallHandler {

  companion object {
    const val CHANNEL = "popkino/sideload_updater"
  }

  private var context: Context? = null
  private var channel: MethodChannel? = null
  private var scope: CoroutineScope? = null
  private var activity: Activity? = null
  private var activityBinding: ActivityPluginBinding? = null

  // Answered by onActivityResult, or earlier by an inspection/permission failure. Also marks an install as in flight.
  private var pendingInstall: MethodChannel.Result? = null
  private var installJob: Job? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    scope = CoroutineScope(SupervisorJob() + mainDispatcher)
    channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    scope?.cancel()
    scope = null
    failPendingInstall("Engine detached while the installer was active")
    context = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding)

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attach(binding)

  // The installer result is still delivered to the recreated activity, so a pending install is kept.
  override fun onDetachedFromActivityForConfigChanges() = detach()

  override fun onDetachedFromActivity() {
    detach()
    failPendingInstall("Activity was destroyed while the installer was active")
  }

  private fun attach(binding: ActivityPluginBinding) {
    detach()
    activity = binding.activity
    activityBinding = binding
    binding.addActivityResultListener(this)
  }

  private fun detach() {
    activityBinding?.removeActivityResultListener(this)
    activityBinding = null
    activity = null
  }

  private fun failPendingInstall(message: String) {
    installJob?.cancel()
    installJob = null
    val pending = pendingInstall
    pendingInstall = null
    pending?.error("ACTIVITY_DESTROYED", message, null)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val context = context
    val scope = scope
    if (context == null || scope == null) {
      result.error("DETACHED", "Updater plugin is not attached to an engine", null)
      return
    }
    when (call.method) {
      "canRequestInstalls" -> result.success(InstallPermission(context).canRequestInstalls())
      "openInstallSettings" -> result.success(openInstallSettings(context).wire)
      "availableBytes" -> result.success(availableBytes(context))
      "inspectApk" -> inspectApk(context, scope, call, result)
      "install" -> install(context, scope, call, result)
      else -> result.notImplemented()
    }
  }

  private fun openInstallSettings(context: Context): SettingsTarget {
    val activity = activity ?: return SettingsTarget.None
    return InstallPermission(context).openInstallSettings { activity.startActivity(it) }
  }

  private fun availableBytes(context: Context): Long? = try {
    StatFs(context.cacheDir.path).availableBytes
  } catch (_: IllegalArgumentException) {
    null
  }

  private fun inspectApk(context: Context, scope: CoroutineScope, call: MethodCall, result: MethodChannel.Result) {
    val file = UpdatesPath.resolve(context.cacheDir, call.argument<String>("path"))
    if (file == null) {
      result.success(ApkInspection(ApkStatus.Invalid).toMap())
      return
    }
    scope.launch {
      val inspection = withContext(ioDispatcher) { inspect(context, file) }
      result.success(inspection.toMap())
    }
  }

  private fun install(context: Context, scope: CoroutineScope, call: MethodCall, result: MethodChannel.Result) {
    if (pendingInstall != null) {
      result.success("busy")
      return
    }
    val file = UpdatesPath.resolve(context.cacheDir, call.argument<String>("path"))
    if (file == null) {
      result.success("invalidPath")
      return
    }
    pendingInstall = result
    installJob = scope.launch {
      val inspection = withContext(ioDispatcher) { inspect(context, file) }
      when (inspection.status) {
        ApkStatus.Ok -> Unit
        ApkStatus.WrongPackage -> return@launch finishInstall("failed:wrongPackage")
        else -> return@launch finishInstall(inspection.status.wire)
      }
      if (!InstallPermission(context).canRequestInstalls()) return@launch finishInstall("permissionRequired")
      startInstaller(context, file)
    }
  }

  private fun startInstaller(context: Context, file: File) {
    val activity = activity ?: return finishInstall("installerUnavailable")
    try {
      val uri = contentUriFor(activity, file)
      // Deprecated since API 29 in favour of PackageInstaller, but still the simplest hand-over with a result.
      @Suppress("DEPRECATION")
      val intent = Intent(Intent.ACTION_INSTALL_PACKAGE)
        .setData(uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        .putExtra(Intent.EXTRA_RETURN_RESULT, true)
      @Suppress("DEPRECATION")
      activity.startActivityForResult(intent, InstallResults.REQUEST_CODE)
      // On success the system kills this process while installing: the answer comes in onActivityResult, or never.
    } catch (_: ActivityNotFoundException) {
      finishInstall("installerUnavailable")
    } catch (_: IllegalArgumentException) {
      // FileProvider could not map the file to a content:// URI.
      finishInstall("failed:fileProvider")
    }
  }

  private fun finishInstall(value: String) {
    val pending = pendingInstall
    pendingInstall = null
    installJob = null
    pending?.success(value)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != InstallResults.REQUEST_CODE) return false
    finishInstall(InstallResults.fromActivityResult(resultCode, data))
    return true
  }
}
