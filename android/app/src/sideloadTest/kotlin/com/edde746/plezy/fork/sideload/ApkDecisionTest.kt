package com.edde746.plezy.fork.sideload

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ApkDecisionTest {
  private val installed = PackageFacts("app.pkg", versionCode = 5, versionName = "0.2.0", signers = setOf("aa"))

  private fun archive(
    packageName: String = "app.pkg",
    versionCode: Long = 6,
    signers: Set<String> = setOf("aa"),
    history: Set<String> = emptySet()
  ) = PackageFacts(packageName, versionCode, "1.0.0", signers, history)

  @Test
  fun unreadableArchiveIsInvalid() {
    assertEquals(ApkStatus.Invalid, ApkDecision.decide(null, installed).status)
  }

  @Test
  fun wrongPackageComesBeforeEveryOtherCheck() {
    val other = archive(packageName = "other.pkg", versionCode = 1, signers = setOf("zz"))
    assertEquals(ApkStatus.WrongPackage, ApkDecision.decide(other, installed).status)
  }

  @Test
  fun signatureMismatchComesBeforeNotNewer() {
    val debugKeyToFinalKey = archive(versionCode = 1, signers = setOf("bb"))
    assertEquals(ApkStatus.SignatureMismatch, ApkDecision.decide(debugKeyToFinalKey, installed).status)
  }

  @Test
  fun sameOrLowerVersionCodeIsNotNewer() {
    assertEquals(ApkStatus.NotNewer, ApkDecision.decide(archive(versionCode = 5), installed).status)
    assertEquals(ApkStatus.NotNewer, ApkDecision.decide(archive(versionCode = 4), installed).status)
  }

  @Test
  fun matchingSignerAndHigherVersionIsOkAndReportsTheArchiveVersion() {
    val result = ApkDecision.decide(archive(versionCode = 6), installed)
    assertEquals(ApkStatus.Ok, result.status)
    assertEquals("1.0.0", result.versionName)
    assertEquals(6L, result.versionCode)
  }

  @Test
  fun rotatedKeyIsAcceptedThroughTheSigningHistory() {
    val rotated = archive(signers = setOf("bb"), history = setOf("aa", "bb"))
    assertEquals(ApkStatus.Ok, ApkDecision.decide(rotated, installed).status)
  }

  @Test
  fun everyInstalledSignerMustBePresent() {
    val twoSigners = PackageFacts("app.pkg", 5, "0.2.0", setOf("aa", "cc"))
    assertEquals(ApkStatus.SignatureMismatch, ApkDecision.decide(archive(signers = setOf("aa")), twoSigners).status)
    assertEquals(ApkStatus.Ok, ApkDecision.decide(archive(signers = setOf("aa", "cc", "dd")), twoSigners).status)
  }

  @Test
  fun installedAppWithoutReadableSignersIsRefused() {
    val blind = PackageFacts("app.pkg", 5, "0.2.0", emptySet())
    assertEquals(ApkStatus.SignatureMismatch, ApkDecision.decide(archive(), blind).status)
  }

  @Test
  fun invalidResultCarriesNoVersion() {
    val map = ApkDecision.decide(null, installed).toMap()
    assertEquals("invalid", map["status"])
    assertNull(map["versionName"])
    assertNull(map["versionCode"])
  }
}
