package com.edde746.plezy.fork.sideload

import java.io.File

/**
 * Only APKs inside `cacheDir/updates/` (where Dart downloads them) may be inspected or installed.
 * Canonicalising both sides also rejects `..` segments and symlinks that leave the folder.
 */
internal object UpdatesPath {
  const val DIR_NAME = "updates"
  private const val EXTENSION = ".apk"

  fun resolve(cacheDir: File, path: String?): File? {
    if (path.isNullOrEmpty()) return null
    if (path.split('/', '\\').any { it == ".." }) return null
    return try {
      val dir = File(cacheDir, DIR_NAME).canonicalFile
      val file = File(path).canonicalFile
      val insideDir = file.path.startsWith(dir.path + File.separator)
      if (insideDir && file.name.length > EXTENSION.length && file.name.endsWith(EXTENSION)) file else null
    } catch (_: java.io.IOException) {
      null
    }
  }
}
