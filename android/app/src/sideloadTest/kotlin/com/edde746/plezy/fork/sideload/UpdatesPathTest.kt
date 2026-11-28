package com.edde746.plezy.fork.sideload

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class UpdatesPathTest {
  @get:Rule
  val tmp = TemporaryFolder()

  private val cacheDir: File by lazy { tmp.newFolder("cache") }
  private val updates: File by lazy { File(cacheDir, "updates").also { it.mkdirs() } }

  private fun apk(name: String = "popkino-1.0.0-armeabi-v7a.apk") = File(updates, name).also { it.writeText("x") }

  @Test
  fun apkInsideTheUpdatesFolderIsAccepted() {
    val file = apk()
    assertEquals(file.canonicalFile, UpdatesPath.resolve(cacheDir, file.path))
  }

  @Test
  fun nullOrEmptyPathIsRefused() {
    assertNull(UpdatesPath.resolve(cacheDir, null))
    assertNull(UpdatesPath.resolve(cacheDir, ""))
  }

  @Test
  fun otherExtensionsAreRefused() {
    assertNull(UpdatesPath.resolve(cacheDir, apk("a.part").path))
    assertNull(UpdatesPath.resolve(cacheDir, apk("a.APK").path))
    assertNull(UpdatesPath.resolve(cacheDir, apk(".apk").path))
  }

  @Test
  fun filesOutsideTheUpdatesFolderAreRefused() {
    val sibling = File(cacheDir, "other.apk").also { it.writeText("x") }
    assertNull(UpdatesPath.resolve(cacheDir, sibling.path))
    assertNull(UpdatesPath.resolve(cacheDir, updates.path + ".apk"))
    // A sibling folder sharing the prefix must not pass a naive startsWith check.
    val lookalike = File(cacheDir, "updates-evil").also { it.mkdirs() }
    assertNull(UpdatesPath.resolve(cacheDir, File(lookalike, "a.apk").path))
  }

  @Test
  fun parentSegmentsAreRefusedEvenWhenTheyStayInside() {
    apk()
    assertNull(UpdatesPath.resolve(cacheDir, "${updates.path}/../updates/popkino-1.0.0-armeabi-v7a.apk"))
    assertNull(UpdatesPath.resolve(cacheDir, "${updates.path}/../other.apk"))
  }

  @Test
  fun symlinkLeavingTheFolderIsRefused() {
    val target = File(cacheDir, "secret.apk").also { it.writeText("x") }
    val link = File(updates, "link.apk")
    Files.createSymbolicLink(link.toPath(), target.toPath())
    assertNull(UpdatesPath.resolve(cacheDir, link.path))
  }

  @Test
  fun symlinkedCacheDirStillWorks() {
    val real = apk()
    val linkedCache = File(tmp.root, "cache-link")
    Files.createSymbolicLink(linkedCache.toPath(), cacheDir.toPath())
    assertEquals(real.canonicalFile, UpdatesPath.resolve(linkedCache, File(linkedCache, "updates/${real.name}").path))
  }
}
