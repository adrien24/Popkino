package com.edde746.plezy.fork.sideload

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.content.pm.PackageInfoCompat
import java.io.File
import java.security.MessageDigest

internal enum class ApkStatus(val wire: String) {
  Ok("ok"),
  Invalid("invalid"),
  WrongPackage("wrongPackage"),
  SignatureMismatch("signatureMismatch"),
  NotNewer("notNewer")
}

internal data class ApkInspection(val status: ApkStatus, val versionName: String? = null, val versionCode: Long? = null) {
  fun toMap(): Map<String, Any?> = buildMap {
    put("status", status.wire)
    versionName?.let { put("versionName", it) }
    versionCode?.let { put("versionCode", it) }
  }
}

/**
 * What the decision needs to know about a package. Signers are SHA-256 fingerprints (hex) of the
 * certificates currently in use; [rotationHistory] holds the older certificates of a key rotation lineage.
 */
internal class PackageFacts(
  val packageName: String,
  val versionCode: Long,
  val versionName: String?,
  val signers: Set<String>,
  val rotationHistory: Set<String> = emptySet()
)

internal object ApkDecision {
  /**
   * Pure decision, in this order: invalid, wrong package, signature mismatch (checked before the version
   * so a key change is reported as such even when the build number also went down), not newer, ok.
   */
  fun decide(archive: PackageFacts?, installed: PackageFacts): ApkInspection {
    if (archive == null) return ApkInspection(ApkStatus.Invalid)
    fun result(status: ApkStatus) = ApkInspection(status, archive.versionName, archive.versionCode)
    if (archive.packageName != installed.packageName) return result(ApkStatus.WrongPackage)
    val accepted = archive.signers + archive.rotationHistory
    // An installed app without readable signers cannot be proven identical: refuse rather than guess.
    if (installed.signers.isEmpty() || !accepted.containsAll(installed.signers)) return result(ApkStatus.SignatureMismatch)
    if (archive.versionCode <= installed.versionCode) return result(ApkStatus.NotNewer)
    return result(ApkStatus.Ok)
  }
}

/** Reads the downloaded APK and the installed app through [PackageManager], then applies [ApkDecision]. */
internal object ApkInspector {
  /** Blocking (verifying the v2/v3 signature reads the whole file): call it off the main thread. */
  fun inspect(context: Context, apk: File): ApkInspection {
    if (!apk.isFile) return ApkInspection(ApkStatus.Invalid)
    return try {
      val pm = context.packageManager
      val archive = readFacts { flags -> archiveInfo(pm, apk.path, flags) }
      val installed = readFacts { flags -> installedInfo(pm, context.packageName, flags) }
        ?: return ApkInspection(ApkStatus.Invalid)
      ApkDecision.decide(archive, installed)
    } catch (_: Exception) {
      ApkInspection(ApkStatus.Invalid)
    }
  }

  @Suppress("DEPRECATION")
  private fun archiveInfo(pm: PackageManager, path: String, flags: Int): PackageInfo? = pm.getPackageArchiveInfo(path, flags)

  @Suppress("DEPRECATION")
  private fun installedInfo(pm: PackageManager, packageName: String, flags: Int): PackageInfo? = try {
    pm.getPackageInfo(packageName, flags)
  } catch (_: PackageManager.NameNotFoundException) {
    null
  }

  @Suppress("DEPRECATION")
  private fun readFacts(query: (Int) -> PackageInfo?): PackageFacts? {
    var info = query(
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    ) ?: return null
    val sdk28 = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
    if (sdk28 && signingInfoMissing(info)) info = query(PackageManager.GET_SIGNATURES) ?: return null

    var signers: Set<String> = emptySet()
    var history: Set<String> = emptySet()
    if (sdk28 && !signingInfoMissing(info)) {
      val (current, lineage) = signingCertificates(info)
      signers = current
      history = lineage
    } else {
      signers = info.signatures.orEmpty().map { sha256Hex(it.toByteArray()) }.toSet()
    }
    return PackageFacts(
      packageName = info.packageName,
      versionCode = PackageInfoCompat.getLongVersionCode(info),
      versionName = info.versionName,
      signers = signers,
      rotationHistory = history
    )
  }

  private fun signingInfoMissing(info: PackageInfo): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.P || signingInfoOf(info) == null

  @RequiresApi(Build.VERSION_CODES.P)
  private fun signingInfoOf(info: PackageInfo) = info.signingInfo

  @RequiresApi(Build.VERSION_CODES.P)
  private fun signingCertificates(info: PackageInfo): Pair<Set<String>, Set<String>> {
    val signing = info.signingInfo!!
    val current = signing.apkContentsSigners.orEmpty().map { sha256Hex(it.toByteArray()) }.toSet()
    val lineage = if (signing.hasMultipleSigners()) {
      emptySet()
    } else {
      signing.signingCertificateHistory.orEmpty().map { sha256Hex(it.toByteArray()) }.toSet()
    }
    return current to lineage
  }

  private fun sha256Hex(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
