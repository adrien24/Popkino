// FORK: bouton-mise-a-jour — build flag for the sideload self-update feature.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// True only in builds made with `--dart-define=ENABLE_UPDATE_CHECK=true`.
///
/// Every entry point of the update code tests this constant (through
/// [ForkSideload.isSupported]) first. When the define is absent the value is a
/// compile-time `false`, so the AOT compiler eliminates `lib/fork/update/` from
/// the binary (store builds must not carry any self-install code).
const bool kForkSideloadUpdates = bool.fromEnvironment('ENABLE_UPDATE_CHECK');

abstract final class ForkSideload {
  /// Test-only switch, honoured in debug mode only.
  @visibleForTesting
  static bool debugForceSupported = false;

  /// Test-only platform override.
  @visibleForTesting
  static bool? debugIsAndroid;

  static bool get isSupported =>
      (kForkSideloadUpdates || (kDebugMode && debugForceSupported)) && (debugIsAndroid ?? Platform.isAndroid);
}
