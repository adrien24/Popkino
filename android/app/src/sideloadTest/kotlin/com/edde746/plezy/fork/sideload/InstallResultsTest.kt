package com.edde746.plezy.fork.sideload

import android.app.Activity
import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class InstallResultsTest {
  private fun failure(code: Int?) = Intent().apply { if (code != null) putExtra(InstallResults.EXTRA_INSTALL_RESULT, code) }

  @Test
  fun cancelledIsReportedWhateverTheExtras() {
    assertEquals("cancelled", InstallResults.fromActivityResult(Activity.RESULT_CANCELED, null))
    assertEquals("cancelled", InstallResults.fromActivityResult(Activity.RESULT_CANCELED, failure(-115)))
  }

  @Test
  fun okMeansInstalled() {
    assertEquals("installed", InstallResults.fromActivityResult(Activity.RESULT_OK, null))
  }

  @Test
  fun knownInstallFailuresAreMapped() {
    assertEquals("signatureMismatch", InstallResults.fromActivityResult(Activity.RESULT_FIRST_USER, failure(-7)))
    assertEquals("notNewer", InstallResults.fromActivityResult(Activity.RESULT_FIRST_USER, failure(-25)))
    assertEquals("insufficientStorage", InstallResults.fromActivityResult(Activity.RESULT_FIRST_USER, failure(-4)))
  }

  @Test
  fun otherCodesKeepTheirValue() {
    assertEquals("failed:-2", InstallResults.fromActivityResult(Activity.RESULT_FIRST_USER, failure(-2)))
    assertEquals("failed:0", InstallResults.fromActivityResult(Activity.RESULT_FIRST_USER, failure(null)))
    assertEquals("failed:0", InstallResults.fromActivityResult(Activity.RESULT_FIRST_USER, null))
  }

  @Test
  fun requestCodeDiffersFromTheExternalPlayerOne() {
    assertNotEquals(7461, InstallResults.REQUEST_CODE)
  }
}
