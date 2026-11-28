import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/fork/update/apk_downloader.dart';
import 'package:plezy/fork/update/fork_release.dart';
import 'package:plezy/fork/update/fork_update_controller.dart';
import 'package:plezy/fork/update/fork_update_dialog.dart';
import 'package:plezy/fork/update/fork_update_session.dart';
import 'package:plezy/fork/update/sideload_flags.dart';
import 'package:plezy/fork/update/sideload_installer.dart';
import 'package:plezy/fork/update/update_files.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/update_service.dart';
import 'package:plezy/utils/app_version.dart';

import '../../test_helpers/prefs.dart';
import 'fake_sideload_installer.dart';

const _size = 10;
const _mb = 1024 * 1024;

ForkRelease _release() => const ForkRelease(
  version: '0.2.0',
  tag: 'v0.2.0',
  name: 'v0.2.0',
  notes: 'Release notes',
  htmlUrl: 'https://x',
  publishedAt: '2026-01-01T00:00:00Z',
  isPrerelease: true,
  apk: ForkApkAsset(name: 'a.apk', url: 'https://x/a.apk', size: _size, abi: 'armeabi-v7a'),
);

/// Downloader that writes a valid APK, optionally blocking until aborted.
class _FakeDownloader extends ForkApkDownloader {
  int calls = 0;
  bool block = false;
  ForkDownloadFailure? failWith;

  @override
  Future<void> download(
    ForkApkAsset asset,
    File partFile,
    File apkFile, {
    required void Function(int received, int total) onProgress,
    required Future<void> abortTrigger,
  }) async {
    calls++;
    await partFile.writeAsBytes(List.filled(asset.size ~/ 2, 1));
    onProgress(asset.size ~/ 2, asset.size);
    if (block) {
      await abortTrigger;
      await partFile.delete();
      throw const ForkDownloadException(ForkDownloadFailure.cancelled);
    }
    final failure = failWith;
    if (failure != null) {
      await partFile.delete();
      throw ForkDownloadException(failure);
    }
    await partFile.writeAsBytes(List.filled(asset.size, 1));
    await partFile.rename(apkFile.path);
  }
}

void main() {
  late Directory tmp;
  late FakeSideloadInstaller installer;
  late _FakeDownloader downloader;
  late ForkUpdateController controller;

  setUp(() async {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    PackageInfo.setMockInitialValues(
      appName: 'Popkino',
      packageName: 'io.github.adrien24.popkino',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    AppVersion.resetForTesting();
    ForkSideload.debugForceSupported = true;
    ForkSideload.debugIsAndroid = true;
    tmp = Directory.systemTemp.createTempSync('fork_update_dialog');
    installer = FakeSideloadInstaller()..availableBytesAnswers.add(1000 * _mb);
    downloader = _FakeDownloader();
    final files = ForkUpdateFiles(root: tmp);
    controller = ForkUpdateController(installer: installer, files: files);
    debugSessionFactory = ({release, pending}) => ForkUpdateSession(
      release: release,
      pending: pending,
      controller: controller,
      installer: installer,
      files: files,
      downloader: downloader,
    );
  });

  tearDown(() {
    debugSessionFactory = null;
    debugResetForkUpdateDialogGuard();
    ForkSideload.debugForceSupported = false;
    ForkSideload.debugIsAndroid = null;
    controller.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pumpOpen(WidgetTester tester, {bool showSkipVersion = false, ForkRelease? release}) async {
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showForkUpdateDialog(context, release: release ?? _release(), showSkipVersion: showSkipVersion),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    InputModeTracker.reportNonPointerInput();
    await tester.pumpAndSettle();
  }

  /// True when the primary focus sits on (or inside) the button labelled [label].
  bool focused(WidgetTester tester, String label) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    var found = false;
    void visit(Element e) {
      if (e.widget is Text && (e.widget as Text).data == label) found = true;
      if (!found) e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    if (found) return true;
    // The node may belong to a Focus below the button: check the ancestors for the label button.
    var inButton = false;
    context.visitAncestorElements((a) {
      if (a.widget is ButtonStyleButton) {
        a.visitChildren(visit);
        inButton = found;
        return false;
      }
      return true;
    });
    return inButton;
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  testWidgets('initial focus is on "Download and install"', (tester) async {
    await pumpOpen(tester);
    expect(find.text('Version 0.2.0 is available'), findsOneWidget);
    expect(find.text('Installed version: 0.1.0'), findsOneWidget);
    expect(find.text('Release notes'), findsOneWidget);
    expect(focused(tester, 'Download and install'), isTrue);
  });

  testWidgets('arrow down scrolls the notes and keeps the focus on the buttons', (tester) async {
    final release = ForkRelease(
      version: '0.2.0',
      tag: 'v0.2.0',
      name: 'v0.2.0',
      notes: List.generate(200, (i) => 'line $i').join('\n'),
      htmlUrl: 'https://x',
      publishedAt: '2026-01-01T00:00:00Z',
      isPrerelease: true,
      apk: const ForkApkAsset(name: 'a.apk', url: 'https://x/a.apk', size: _size, abi: 'armeabi-v7a'),
    );
    await pumpOpen(tester, release: release);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.pixels, 0);

    await key(tester, LogicalKeyboardKey.arrowDown);

    expect(scrollable.position.pixels, greaterThan(0));
    expect(focused(tester, 'Download and install'), isTrue);
  });

  testWidgets('"Later" closes without touching the installer', (tester) async {
    await pumpOpen(tester);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(installer.calls, isEmpty);
  });

  testWidgets('Back closes without touching the installer', (tester) async {
    await pumpOpen(tester);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AlertDialog), findsNothing);
    expect(installer.calls, isEmpty);
  });

  testWidgets('showSkipVersion adds a third button and writes the preference', (tester) async {
    await pumpOpen(tester, showSkipVersion: true);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Skip This Version'), findsOneWidget);
    expect(find.text('Download and install'), findsOneWidget);

    await tester.tap(find.text('Skip This Version'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(await UpdateService.getSkippedVersion(), '0.2.0');
  });

  testWidgets('download shows progress, Cancel closes and leaves no file', (tester) async {
    downloader.block = true;
    await pumpOpen(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download and install'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
    expect(focused(tester, 'Cancel'), isTrue);

    await tester.tap(find.text('Cancel'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(tmp.listSync(), isEmpty);
  });

  testWidgets('permission flow: needs permission, resume, then Install at the focus', (tester) async {
    installer.canRequestInstallsAnswers.addAll([false, true]);
    installer.openInstallSettingsAnswers.add(InstallSettingsTarget.appPermission);
    await pumpOpen(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download and install'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('To install the update, allow Popkino to install apps.'), findsOneWidget);
    expect(focused(tester, 'Open settings'), isTrue);

    await tester.runAsync(() async {
      await tester.tap(find.text('Open settings'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();

    expect(find.text('Version 0.2.0 ready to install'), findsOneWidget);
    expect(focused(tester, 'Install'), isTrue);
  });

  testWidgets('developerOptions target displays the settings path', (tester) async {
    installer.canRequestInstallsAnswers.add(false);
    installer.openInstallSettingsAnswers.add(InstallSettingsTarget.developerOptions);
    await pumpOpen(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download and install'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text(t.fork.update.permissionPathDeveloper), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('Open settings'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text(t.fork.update.permissionPathDeveloper), findsOneWidget);
  });

  testWidgets('signature mismatch shows the CA19 message with a single Close button', (tester) async {
    installer.inspectApkAnswers.add((status: ApkCheck.signatureMismatch, versionName: null, versionCode: null));
    await pumpOpen(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download and install'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text(t.fork.update.signatureConflict), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(focused(tester, 'Close'), isTrue);
  });

  testWidgets('network failure then Retry starts the download again', (tester) async {
    downloader.failWith = ForkDownloadFailure.network;
    await pumpOpen(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download and install'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text(t.fork.update.downloadFailed), findsOneWidget);
    expect(downloader.calls, 1);
    expect(focused(tester, 'Retry'), isTrue);

    installer.availableBytesAnswers.add(1000 * _mb);
    await tester.runAsync(() async {
      await tester.tap(find.text('Retry'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(downloader.calls, 2);
  });

  testWidgets('a second call while a window is open does nothing', (tester) async {
    await pumpOpen(tester);
    final context = tester.element(find.byType(Scaffold));
    await showForkUpdateDialog(context, release: _release());
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
