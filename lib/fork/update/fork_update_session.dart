// FORK: bouton-mise-a-jour — state machine of one update dialog (download, verify, permission, install).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../utils/app_logger.dart';
import 'apk_downloader.dart';
import 'fork_release.dart';
import 'fork_update_controller.dart';
import 'sideload_installer.dart';
import 'update_files.dart';

/// Why an update attempt failed (drives the message and the available buttons).
enum ForkUpdateFailure { network, storage, signature, other }

/// Phase of the update dialog.
sealed class ForkUpdatePhase {
  const ForkUpdatePhase();
}

/// Release notes, before anything is downloaded.
class ForkUpdateDetails extends ForkUpdatePhase {
  const ForkUpdateDetails();
}

class ForkUpdateDownloading extends ForkUpdatePhase {
  const ForkUpdateDownloading(this.fraction);

  /// Between 0 and 1.
  final double fraction;
}

class ForkUpdateVerifying extends ForkUpdatePhase {
  const ForkUpdateVerifying();
}

/// The "install unknown apps" permission is missing. [lastTarget] is the settings
/// screen that was opened (null: none yet).
class ForkUpdateNeedsPermission extends ForkUpdatePhase {
  const ForkUpdateNeedsPermission(this.lastTarget);

  final InstallSettingsTarget? lastTarget;
}

/// The user came back from the settings without granting the permission.
class ForkUpdatePermissionDenied extends ForkUpdatePhase {
  const ForkUpdatePermissionDenied(this.lastTarget);

  final InstallSettingsTarget? lastTarget;
}

class ForkUpdateReadyToInstall extends ForkUpdatePhase {
  const ForkUpdateReadyToInstall();
}

class ForkUpdateInstalling extends ForkUpdatePhase {
  const ForkUpdateInstalling();
}

/// Nothing left to do: the dialog closes itself.
class ForkUpdateDone extends ForkUpdatePhase {
  const ForkUpdateDone();
}

class ForkUpdateFailed extends ForkUpdatePhase {
  const ForkUpdateFailed(this.kind);

  final ForkUpdateFailure kind;
}

/// One session per dialog: owns the download, the verification and the hand-over
/// to the system installer. Progress lives here (not in the global controller) so
/// the home bar is not rebuilt while downloading.
class ForkUpdateSession extends ChangeNotifier {
  /// Starts from a [release] (phase `details`) or from a [pending] install left by a
  /// previous run. For a pending install the phase is `verifying` until the permission
  /// is known (see [initialized]), then `readyToInstall` or `permissionDenied`.
  ForkUpdateSession({
    ForkRelease? release,
    ForkPendingInstall? pending,
    required this.controller,
    required this.installer,
    required this.files,
    required this.downloader,
  }) : assert((release == null) != (pending == null), 'Pass exactly one of release or pending'),
       release = release ?? pending!.release,
       _apkPath = pending?.apkPath {
    _phase = pending == null ? const ForkUpdateDetails() : const ForkUpdateVerifying();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    initialized = pending == null ? Future<void>.value() : _initFromPending();
  }

  /// The installer recopies the APK on the same partition: twice its size, plus a margin.
  static const _spaceMargin = 100 * 1024 * 1024;

  final ForkUpdateController controller;
  final ForkRelease release;
  final SideloadInstaller installer;
  final ForkUpdateFiles files;
  final ForkApkDownloader downloader;

  late final AppLifecycleListener _lifecycle;
  final Completer<void> _abort = Completer<void>();
  late ForkUpdatePhase _phase;
  String? _apkPath;
  bool _closed = false;
  bool _busy = false;
  bool _settingsOpened = false;

  /// Completes once the initial phase is settled (immediately unless built from a pending install).
  late final Future<void> initialized;

  ForkUpdatePhase get phase => _phase;

  void _set(ForkUpdatePhase phase) {
    // After cancel() the dialog is going away: late callbacks must stay silent.
    if (_closed) return;
    _phase = phase;
    notifyListeners();
  }

  Future<void> _initFromPending() async {
    var granted = false;
    try {
      granted = await installer.canRequestInstalls();
    } catch (e, st) {
      appLogger.w('Update: permission check failed', error: e, stackTrace: st);
    }
    _set(granted ? const ForkUpdateReadyToInstall() : const ForkUpdatePermissionDenied(null));
  }

  /// Removes the downloaded files and the pending record.
  Future<void> _discard() async {
    try {
      await files.deleteAll();
    } catch (e, st) {
      appLogger.w('Update: cleanup failed', error: e, stackTrace: st);
    }
    controller.clearPending();
  }

  Future<void> startDownload() async {
    if (_closed || _busy) return;
    _busy = true;
    try {
      await _download();
    } finally {
      _busy = false;
    }
  }

  Future<void> _download() async {
    final asset = release.apk;
    final available = await installer.availableBytes();
    if (_closed) return;
    if (available != null && available < 2 * asset.size + _spaceMargin) {
      _set(const ForkUpdateFailed(ForkUpdateFailure.storage));
      return;
    }

    _set(const ForkUpdateDownloading(0));
    final apk = await files.apkFile(release);
    final part = await files.partFile(release);
    _apkPath = apk.path;
    try {
      await downloader.download(
        asset,
        part,
        apk,
        onProgress: (received, total) {
          if (_closed) return;
          _set(ForkUpdateDownloading(total > 0 ? (received / total).clamp(0.0, 1.0) : 0));
        },
        abortTrigger: _abort.future,
      );
    } on ForkDownloadException catch (e) {
      if (await _closedCleanup()) return;
      _set(
        ForkUpdateFailed(
          e.failure == ForkDownloadFailure.storage ? ForkUpdateFailure.storage : ForkUpdateFailure.network,
        ),
      );
      return;
    } catch (e, st) {
      appLogger.w('Update: download failed', error: e, stackTrace: st);
      if (await _closedCleanup()) return;
      _set(const ForkUpdateFailed(ForkUpdateFailure.network));
      return;
    }
    if (await _closedCleanup()) return;

    _set(const ForkUpdateVerifying());
    final ApkInspection check;
    try {
      check = await installer.inspectApk(apk.path);
    } catch (e, st) {
      appLogger.w('Update: inspection failed', error: e, stackTrace: st);
      if (await _closedCleanup()) return;
      await _fail(ForkUpdateFailure.other);
      return;
    }
    if (await _closedCleanup()) return;

    switch (check.status) {
      case ApkCheck.ok:
        await files.writePending(
          version: release.version,
          abi: asset.abi,
          versionCode: check.versionCode ?? 0,
          size: asset.size,
          fileName: p.basename(apk.path),
        );
        // A cancel during the write must not leave the record behind.
        if (await _closedCleanup()) return;
        await _afterVerified();
      case ApkCheck.invalid:
        await _fail(ForkUpdateFailure.network);
      case ApkCheck.signatureMismatch:
        await _fail(ForkUpdateFailure.signature);
      case ApkCheck.notNewer:
        controller.markRefused(release.tag);
        await _fail(ForkUpdateFailure.other);
      case ApkCheck.wrongPackage:
      case ApkCheck.unavailable:
        await _fail(ForkUpdateFailure.other);
    }
  }

  /// When the session was cancelled while an operation was in flight, that operation may
  /// have created files after [cancel] cleaned up: clean again. Returns true if closed.
  Future<bool> _closedCleanup() async {
    if (!_closed) return false;
    if (_phase is! ForkUpdateInstalling) await _discard();
    return true;
  }

  Future<void> _fail(ForkUpdateFailure kind) async {
    await _discard();
    _set(ForkUpdateFailed(kind));
  }

  Future<void> _afterVerified() async {
    var granted = false;
    try {
      granted = await installer.canRequestInstalls();
    } catch (e, st) {
      appLogger.w('Update: permission check failed', error: e, stackTrace: st);
    }
    if (_closed) return;
    if (granted) {
      await install();
    } else {
      _set(const ForkUpdateNeedsPermission(null));
    }
  }

  /// Opens the system settings where the user can grant the permission, then waits for
  /// the app to be resumed.
  Future<void> openSettings() async {
    if (_closed) return;
    final denied = _phase is ForkUpdatePermissionDenied;
    final target = await installer.openInstallSettings();
    if (_closed) return;
    _settingsOpened = true;
    // `none`: nothing could be opened, the full path is displayed and the user goes there by hand.
    _set(denied ? ForkUpdatePermissionDenied(target) : ForkUpdateNeedsPermission(target));
  }

  Future<void> _onResume() async {
    final phase = _phase;
    final InstallSettingsTarget? target;
    switch (phase) {
      case ForkUpdateNeedsPermission(:final lastTarget):
        // Resumed without having visited the settings: nothing to decide yet.
        if (!_settingsOpened) return;
        target = lastTarget;
      case ForkUpdatePermissionDenied(:final lastTarget):
        target = lastTarget;
      default:
        return;
    }
    var granted = false;
    try {
      granted = await installer.canRequestInstalls();
    } catch (e, st) {
      appLogger.w('Update: permission check failed', error: e, stackTrace: st);
    }
    // The phase may have moved on (retry, cancel) while waiting.
    if (_closed || !identical(_phase, phase)) return;
    _set(granted ? const ForkUpdateReadyToInstall() : ForkUpdatePermissionDenied(target));
  }

  /// Hands the verified APK to the system installer. On success the process is killed
  /// by the system, so a result only comes back on cancellation or failure.
  Future<void> install() async {
    if (_closed || _phase is ForkUpdateInstalling) return;
    final path = _apkPath;
    if (path == null) {
      await _fail(ForkUpdateFailure.other);
      return;
    }
    _set(const ForkUpdateInstalling());
    InstallOutcome outcome;
    try {
      outcome = await installer.install(path);
    } catch (e, st) {
      appLogger.w('Update: install failed', error: e, stackTrace: st);
      outcome = InstallOutcome.failed;
    }
    // The session may have been cancelled while installing ("close only"): the cleanup
    // below still applies, but nothing is displayed any more.
    switch (outcome) {
      case InstallOutcome.cancelled:
      case InstallOutcome.installed:
        await _discard();
        _set(const ForkUpdateDone());
      case InstallOutcome.permissionRequired:
        _set(const ForkUpdateNeedsPermission(null));
      case InstallOutcome.signatureMismatch:
        await _fail(ForkUpdateFailure.signature);
      case InstallOutcome.notNewer:
        controller.markRefused(release.tag);
        await _fail(ForkUpdateFailure.other);
      case InstallOutcome.insufficientStorage:
        await _fail(ForkUpdateFailure.storage);
      case InstallOutcome.invalid:
        await _fail(ForkUpdateFailure.network);
      case InstallOutcome.unavailable:
      case InstallOutcome.failed:
        await _fail(ForkUpdateFailure.other);
    }
  }

  /// "Retry" after a failure or a refused permission.
  Future<void> retry() async {
    switch (_phase) {
      case ForkUpdateFailed(:final kind) when kind == ForkUpdateFailure.network || kind == ForkUpdateFailure.storage:
        await startDownload();
      case ForkUpdatePermissionDenied():
        await openSettings();
      default:
        return;
    }
  }

  /// Back, "Cancel", "Later" or closing the dialog. Aborts the download and removes the
  /// files and the pending record, except while installing, where it only closes.
  /// Idempotent.
  Future<void> cancel() async {
    if (_closed) return;
    final installing = _phase is ForkUpdateInstalling;
    _closed = true;
    if (!_abort.isCompleted) _abort.complete();
    if (installing) return;
    await _discard();
  }

  @override
  void dispose() {
    unawaited(cancel());
    _lifecycle.dispose();
    super.dispose();
  }
}
