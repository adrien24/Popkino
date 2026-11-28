// FORK: bouton-mise-a-jour — single entry point used by `UpdateService`.
import 'package:flutter/foundation.dart';

import 'package:flutter/widgets.dart' show BuildContext;

import '../../services/update_service.dart';
import 'fork_release.dart';
import 'fork_update_controller.dart';
import 'fork_update_dialog.dart';
import 'sideload_flags.dart';

abstract final class ForkUpdateHooks {
  /// Test-only controller override.
  @visibleForTesting
  static ForkUpdateController? debugController;

  /// Returns `null` when the fork does not handle the check (upstream path),
  /// otherwise a future with the update info map (or `null` for "no update").
  static Future<Map<String, dynamic>?>? performCheck(String currentVersion, {required bool startup}) {
    if (!ForkSideload.isSupported) return null;
    return _check(currentVersion, startup: startup);
  }

  /// Returns `null` when the fork does not handle the dialog (upstream path).
  static Future<void>? showDialog(BuildContext context, Map<String, dynamic> info, {required bool showSkipVersion}) {
    if (!ForkSideload.isSupported) return null;
    final release = info['forkRelease'];
    if (release is! ForkRelease) return null;
    return showForkUpdateDialog(context, release: release, showSkipVersion: showSkipVersion);
  }

  static Future<Map<String, dynamic>?> _check(String currentVersion, {required bool startup}) async {
    final controller = debugController ?? ForkUpdateController.instance;
    if (startup) {
      await controller.ensureChecked();
    } else {
      await controller.refresh(throwOnFailure: true);
    }

    final release = controller.available;
    if (release == null) return null;
    // Only the automatic dialog honours "skip this version" (manual check: CA21).
    if (startup && release.version == await UpdateService.getSkippedVersion()) return null;

    return {
      'hasUpdate': true,
      'currentVersion': currentVersion,
      'latestVersion': release.version,
      'releaseUrl': release.htmlUrl,
      'releaseName': release.name,
      'releaseNotes': release.notes,
      'publishedAt': release.publishedAt,
      'forkRelease': release,
    };
  }
}
