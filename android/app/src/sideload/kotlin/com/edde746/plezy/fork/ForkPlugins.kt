package com.edde746.plezy.fork

import com.edde746.plezy.fork.sideload.SideloadUpdaterPlugin
import io.flutter.embedding.engine.FlutterEngine

/** Fork-only native plugins, sideload (GitHub APK) variant. The store variant registers nothing. */
object ForkPlugins {
  fun register(engine: FlutterEngine) {
    engine.plugins.add(SideloadUpdaterPlugin())
  }
}
