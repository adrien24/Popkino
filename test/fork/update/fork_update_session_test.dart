import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plezy/fork/update/apk_downloader.dart';
import 'package:plezy/fork/update/fork_release.dart';
import 'package:plezy/fork/update/fork_update_controller.dart';
import 'package:plezy/fork/update/fork_update_session.dart';
import 'package:plezy/fork/update/sideload_installer.dart';
import 'package:plezy/fork/update/update_files.dart';

import 'fake_sideload_installer.dart';

const _size = 10;
const _mb = 1024 * 1024;

ForkRelease _release({String version = '0.2.0'}) => ForkRelease(
  version: version,
  tag: 'v$version',
  name: 'v$version',
  notes: 'notes',
  htmlUrl: 'https://x',
  publishedAt: '2026-01-01T00:00:00Z',
  isPrerelease: true,
  apk: const ForkApkAsset(name: 'a.apk', url: 'https://x/a.apk', size: _size, abi: 'armeabi-v7a'),
);

/// Downloader that writes a valid-sized APK, or fails / blocks on demand.
class _FakeDownloader extends ForkApkDownloader {
  _FakeDownloader();

  int calls = 0;
  ForkDownloadFailure? failWith;

  /// When set, the download waits on it (then on the abort trigger).
  Completer<void>? gate;
  bool aborted = false;
  final List<(int, int)> progress = [];

  @override
  Future<void> download(
    ForkApkAsset asset,
    File partFile,
    File apkFile, {
    required void Function(int received, int total) onProgress,
    required Future<void> abortTrigger,
  }) async {
    calls++;
    unawaited(abortTrigger.then((_) => aborted = true));
    await partFile.writeAsBytes(List.filled(asset.size ~/ 2, 1));
    onProgress(asset.size ~/ 2, asset.size);
    progress.add((asset.size ~/ 2, asset.size));
    if (gate != null) {
      await Future.any([gate!.future, abortTrigger]);
      if (aborted) {
        await partFile.delete();
        throw const ForkDownloadException(ForkDownloadFailure.cancelled);
      }
    }
    final failure = failWith;
    if (failure != null) {
      await partFile.delete();
      throw ForkDownloadException(failure);
    }
    await partFile.writeAsBytes(List.filled(asset.size, 1));
    onProgress(asset.size, asset.size);
    await partFile.rename(apkFile.path);
  }
}

/// Installer whose `install` blocks until [installGate] completes.
class _GatedInstaller extends FakeSideloadInstaller {
  final installGate = Completer<InstallOutcome>();

  @override
  Future<InstallOutcome> install(String path) async {
    calls.add('install:$path');
    return installGate.future;
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'condition never became true');
}

ApkInspection _inspect(ApkCheck status) => (status: status, versionName: '0.2.0', versionCode: 2002);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FakeSideloadInstaller installer;
  late _FakeDownloader downloader;
  late ForkUpdateFiles files;
  late ForkUpdateController controller;
  late ForkUpdateSession session;
  late List<ForkUpdatePhase> phases;

  ForkUpdateSession build({ForkRelease? release, ForkPendingInstall? pending, FakeSideloadInstaller? withInstaller}) {
    session = ForkUpdateSession(
      release: pending == null ? (release ?? _release()) : null,
      pending: pending,
      controller: controller,
      installer: withInstaller ?? installer,
      files: files,
      downloader: downloader,
    );
    phases = [];
    session.addListener(() => phases.add(session.phase));
    return session;
  }

  List<String> dirContents() => tmp.listSync().map((e) => p.basename(e.path)).toList()..sort();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fork_update_session');
    installer = FakeSideloadInstaller();
    downloader = _FakeDownloader();
    files = ForkUpdateFiles(root: tmp);
    controller = ForkUpdateController(installer: installer, files: files);
  });

  tearDown(() async {
    session.dispose();
    // Let the asynchronous cleanup started by dispose finish before removing the folder.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('download', () {
    test('starts in details and reports progress then verification', () async {
      installer.availableBytesAnswers.add(1000 * _mb);
      installer.canRequestInstallsAnswers.add(false);
      build();
      expect(session.phase, isA<ForkUpdateDetails>());

      await session.startDownload();

      expect(phases[0], isA<ForkUpdateDownloading>());
      expect(phases.whereType<ForkUpdateDownloading>().map((e) => e.fraction), containsAllInOrder([0.0, 0.5, 1.0]));
      expect(phases.whereType<ForkUpdateVerifying>(), hasLength(1));
      expect(session.phase, isA<ForkUpdateNeedsPermission>());
      expect((session.phase as ForkUpdateNeedsPermission).lastTarget, isNull);
    });

    test('pending.json is written only after a successful inspection', () async {
      installer.inspectApkAnswers.add(_inspect(ApkCheck.invalid));
      build();
      await session.startDownload();
      expect(await files.readPending(), isNull);

      session.dispose();
      build();
      installer.inspectApkAnswers.add(_inspect(ApkCheck.ok));
      installer.canRequestInstallsAnswers.add(false);
      await session.startDownload();
      final pending = await files.readPending();
      expect(pending, isNotNull);
      expect(pending!.version, '0.2.0');
      expect(pending.versionCode, 2002);
      expect(pending.size, _size);
      expect(dirContents(), contains(pending.fileName));
    });

    test('refuses to download without 2 x size + 100 MB free', () async {
      installer.availableBytesAnswers.add(2 * _size + 100 * _mb - 1);
      build();
      await session.startDownload();
      expect(session.phase, isA<ForkUpdateFailed>().having((f) => f.kind, 'kind', ForkUpdateFailure.storage));
      expect(downloader.calls, 0);
    });

    test('downloads when the free space is exactly enough or unknown', () async {
      installer.availableBytesAnswers.add(2 * _size + 100 * _mb);
      installer.canRequestInstallsAnswers.add(false);
      build();
      await session.startDownload();
      expect(downloader.calls, 1);
    });

    test('downloads when the free space is unknown', () async {
      installer.availableBytesAnswers.add(null);
      installer.canRequestInstallsAnswers.add(false);
      build();
      await session.startDownload();
      expect(downloader.calls, 1);
    });

    test('download failures map to network and storage', () async {
      downloader.failWith = ForkDownloadFailure.network;
      build();
      await session.startDownload();
      expect(session.phase, isA<ForkUpdateFailed>().having((f) => f.kind, 'kind', ForkUpdateFailure.network));
      expect(dirContents(), isEmpty);

      downloader.failWith = ForkDownloadFailure.storage;
      await session.retry();
      expect(session.phase, isA<ForkUpdateFailed>().having((f) => f.kind, 'kind', ForkUpdateFailure.storage));
      expect(downloader.calls, 2);
    });

    test('retry after a network failure downloads again', () async {
      downloader.failWith = ForkDownloadFailure.network;
      build();
      await session.startDownload();

      downloader.failWith = null;
      installer.canRequestInstallsAnswers.add(false);
      await session.retry();
      expect(downloader.calls, 2);
      expect(session.phase, isA<ForkUpdateNeedsPermission>());
    });
  });

  group('verification', () {
    final cases = <ApkCheck, ForkUpdateFailure>{
      ApkCheck.invalid: ForkUpdateFailure.network,
      ApkCheck.signatureMismatch: ForkUpdateFailure.signature,
      ApkCheck.wrongPackage: ForkUpdateFailure.other,
      ApkCheck.notNewer: ForkUpdateFailure.other,
      ApkCheck.unavailable: ForkUpdateFailure.other,
    };
    for (final entry in cases.entries) {
      test('${entry.key.name} -> failed(${entry.value.name}), files removed, no install', () async {
        installer.inspectApkAnswers.add(_inspect(entry.key));
        build();
        await session.startDownload();
        expect(session.phase, isA<ForkUpdateFailed>().having((f) => f.kind, 'kind', entry.value));
        expect(dirContents(), isEmpty);
        expect(installer.calls.where((c) => c.startsWith('install:')), isEmpty);
      });
    }

    test('notNewer marks the release as refused', () async {
      controller.available = _release();
      installer.inspectApkAnswers.add(_inspect(ApkCheck.notNewer));
      build();
      await session.startDownload();
      expect(controller.available, isNull);
    });
  });

  group('install', () {
    test('goes straight to install when the permission is already granted', () async {
      installer.canRequestInstallsAnswers.add(true);
      installer.installAnswers.add(InstallOutcome.installed);
      build();
      await session.startDownload();

      expect(phases.whereType<ForkUpdateInstalling>(), hasLength(1));
      expect(installer.calls.where((c) => c.startsWith('install:')), hasLength(1));
      expect(session.phase, isA<ForkUpdateDone>());
      expect(dirContents(), isEmpty);
    });

    test('cancelled by the user removes everything and finishes', () async {
      installer.canRequestInstallsAnswers.add(true);
      installer.installAnswers.add(InstallOutcome.cancelled);
      controller.pendingInstall = null;
      build();
      await session.startDownload();
      expect(session.phase, isA<ForkUpdateDone>());
      expect(dirContents(), isEmpty);
      expect(await files.readPending(), isNull);
    });

    final failures = <InstallOutcome, ForkUpdateFailure>{
      InstallOutcome.signatureMismatch: ForkUpdateFailure.signature,
      InstallOutcome.notNewer: ForkUpdateFailure.other,
      InstallOutcome.insufficientStorage: ForkUpdateFailure.storage,
      InstallOutcome.invalid: ForkUpdateFailure.network,
      InstallOutcome.failed: ForkUpdateFailure.other,
      InstallOutcome.unavailable: ForkUpdateFailure.other,
    };
    for (final entry in failures.entries) {
      test('${entry.key.name} -> failed(${entry.value.name}) and files removed', () async {
        installer.canRequestInstallsAnswers.add(true);
        installer.installAnswers.add(entry.key);
        build();
        await session.startDownload();
        expect(session.phase, isA<ForkUpdateFailed>().having((f) => f.kind, 'kind', entry.value));
        expect(dirContents(), isEmpty);
      });
    }

    test('notNewer from the installer marks the release as refused', () async {
      controller.available = _release();
      installer.canRequestInstallsAnswers.add(true);
      installer.installAnswers.add(InstallOutcome.notNewer);
      build();
      await session.startDownload();
      expect(controller.available, isNull);
    });

    test('permissionRequired goes back to needsPermission and keeps the files', () async {
      installer.canRequestInstallsAnswers.add(true);
      installer.installAnswers.add(InstallOutcome.permissionRequired);
      build();
      await session.startDownload();
      expect(session.phase, isA<ForkUpdateNeedsPermission>());
      expect(dirContents(), hasLength(2)); // apk + pending.json
    });

    test('failed(signature) offers no retry', () async {
      installer.canRequestInstallsAnswers.add(true);
      installer.installAnswers.add(InstallOutcome.signatureMismatch);
      build();
      await session.startDownload();
      final before = session.phase;
      await session.retry();
      expect(session.phase, same(before));
      expect(downloader.calls, 1);
    });
  });

  group('permission', () {
    Future<void> toNeedsPermission() async {
      installer.canRequestInstallsAnswers.add(false);
      build();
      await session.startDownload();
      expect(session.phase, isA<ForkUpdateNeedsPermission>());
    }

    Future<void> resume() async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    test('openSettings remembers the target, resume with permission -> readyToInstall', () async {
      await toNeedsPermission();
      installer.openInstallSettingsAnswers.add(InstallSettingsTarget.appPermission);
      await session.openSettings();
      expect((session.phase as ForkUpdateNeedsPermission).lastTarget, InstallSettingsTarget.appPermission);

      installer.canRequestInstallsAnswers.add(true);
      await resume();
      await _until(() => session.phase is ForkUpdateReadyToInstall);
    });

    test('resume without permission -> permissionDenied, retry reopens the settings', () async {
      await toNeedsPermission();
      installer.openInstallSettingsAnswers.add(InstallSettingsTarget.developerOptions);
      await session.openSettings();

      installer.canRequestInstallsAnswers.add(false);
      await resume();
      await _until(() => session.phase is ForkUpdatePermissionDenied);
      expect((session.phase as ForkUpdatePermissionDenied).lastTarget, InstallSettingsTarget.developerOptions);

      installer.openInstallSettingsAnswers.add(InstallSettingsTarget.unknownAppsList);
      await session.retry();
      expect(session.phase, isA<ForkUpdatePermissionDenied>());
      expect((session.phase as ForkUpdatePermissionDenied).lastTarget, InstallSettingsTarget.unknownAppsList);

      installer.canRequestInstallsAnswers.add(true);
      await resume();
      await _until(() => session.phase is ForkUpdateReadyToInstall);
    });

    test('target none stays in needsPermission(none)', () async {
      await toNeedsPermission();
      installer.openInstallSettingsAnswers.add(InstallSettingsTarget.none);
      await session.openSettings();
      expect(session.phase, isA<ForkUpdateNeedsPermission>());
      expect((session.phase as ForkUpdateNeedsPermission).lastTarget, InstallSettingsTarget.none);
    });

    test('a resume before the settings were opened is ignored', () async {
      await toNeedsPermission();
      final before = session.phase;
      final callsBefore = installer.calls.length;
      await resume();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(session.phase, same(before));
      expect(installer.calls.length, callsBefore);
    });

    test('install from readyToInstall hands the APK over', () async {
      await toNeedsPermission();
      installer.openInstallSettingsAnswers.add(InstallSettingsTarget.appPermission);
      await session.openSettings();
      installer.canRequestInstallsAnswers.add(true);
      await resume();
      await _until(() => session.phase is ForkUpdateReadyToInstall);

      installer.installAnswers.add(InstallOutcome.installed);
      await session.install();
      expect(session.phase, isA<ForkUpdateDone>());
      expect(installer.calls.where((c) => c.startsWith('install:')), hasLength(1));
    });
  });

  group('cancel', () {
    test('during the download aborts it and leaves no file', () async {
      downloader.gate = Completer<void>();
      build();
      final download = session.startDownload();
      await _until(() => downloader.calls == 1 && phases.isNotEmpty);

      await session.cancel();
      await download;

      expect(downloader.aborted, isTrue);
      expect(dirContents(), isEmpty);
      expect(await files.readPending(), isNull);
      // No phase change after the cancellation.
      expect(session.phase, isA<ForkUpdateDownloading>());
    });

    test('removes the verified files and the pending record', () async {
      installer.canRequestInstallsAnswers.add(false);
      build();
      await session.startDownload();
      expect(dirContents(), hasLength(2));

      await session.cancel();
      expect(dirContents(), isEmpty);
    });

    test('while installing only closes: files stay, late result is silent', () async {
      final gated = _GatedInstaller();
      gated.canRequestInstallsAnswers.add(true);
      build(withInstaller: gated);
      final download = session.startDownload();
      await _until(() => session.phase is ForkUpdateInstalling);

      await session.cancel();
      expect(dirContents(), hasLength(2));

      final seen = phases.length;
      gated.installGate.complete(InstallOutcome.permissionRequired);
      await download;
      expect(phases.length, seen);
      expect(dirContents(), hasLength(2));
    });

    test('is idempotent', () async {
      build();
      await session.cancel();
      await session.cancel();
      expect(dirContents(), isEmpty);
    });

    test('dispose cancels and stays silent', () async {
      downloader.gate = Completer<void>();
      build();
      final download = session.startDownload();
      await _until(() => downloader.calls == 1 && phases.isNotEmpty);

      session.dispose();
      await download;
      expect(downloader.aborted, isTrue);
      expect(dirContents(), isEmpty);
      // tearDown disposes again: a second dispose of the notifier is tolerated by building a fresh one.
      build();
    });

    test('startDownload after cancel does nothing', () async {
      build();
      await session.cancel();
      await session.startDownload();
      expect(downloader.calls, 0);
    });
  });

  group('built from a pending install', () {
    Future<ForkPendingInstall> pendingOnDisk() async {
      final release = _release();
      final apk = await files.apkFile(release);
      await apk.writeAsBytes(List.filled(_size, 1));
      final record = await files.writePending(
        version: release.version,
        abi: release.apk.abi,
        versionCode: 2002,
        size: _size,
        fileName: p.basename(apk.path),
      );
      return ForkPendingInstall(pending: record, release: release, apkPath: apk.path);
    }

    test('permission granted -> readyToInstall', () async {
      final pending = await pendingOnDisk();
      installer.canRequestInstallsAnswers.add(true);
      build(pending: pending);
      expect(session.phase, isA<ForkUpdateVerifying>());
      await session.initialized;
      expect(session.phase, isA<ForkUpdateReadyToInstall>());
    });

    test('permission refused -> permissionDenied(null)', () async {
      final pending = await pendingOnDisk();
      installer.canRequestInstallsAnswers.add(false);
      build(pending: pending);
      await session.initialized;
      expect(session.phase, isA<ForkUpdatePermissionDenied>());
      expect((session.phase as ForkUpdatePermissionDenied).lastTarget, isNull);
    });

    test('install uses the stored APK without downloading', () async {
      final pending = await pendingOnDisk();
      installer.canRequestInstallsAnswers.add(true);
      installer.installAnswers.add(InstallOutcome.cancelled);
      build(pending: pending);
      await session.initialized;

      await session.install();
      expect(installer.calls, contains('install:${pending.apkPath}'));
      expect(downloader.calls, 0);
      expect(session.phase, isA<ForkUpdateDone>());
      expect(dirContents(), isEmpty);
    });

    test('Later removes the pending files', () async {
      final pending = await pendingOnDisk();
      installer.canRequestInstallsAnswers.add(true);
      build(pending: pending);
      await session.initialized;
      await session.cancel();
      expect(dirContents(), isEmpty);
    });
  });
}
