import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/focus/focusable_action_bar.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/fork/update/apk_downloader.dart';
import 'package:plezy/fork/update/fork_release.dart';
import 'package:plezy/fork/update/fork_update_action.dart';
import 'package:plezy/fork/update/fork_update_controller.dart';
import 'package:plezy/fork/update/fork_update_dialog.dart';
import 'package:plezy/fork/update/fork_update_session.dart';
import 'package:plezy/fork/update/sideload_flags.dart';
import 'package:plezy/fork/update/update_files.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/utils/app_version.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import 'fake_sideload_installer.dart';

const _release = ForkRelease(
  version: '0.2.0',
  tag: 'v0.2.0',
  name: 'v0.2.0',
  notes: 'Release notes',
  htmlUrl: 'https://x',
  publishedAt: '2026-01-01T00:00:00Z',
  isPrerelease: true,
  apk: ForkApkAsset(name: 'a.apk', url: 'https://x/a.apk', size: 10, abi: 'armeabi-v7a'),
);

/// Controller whose state is set by the test; never touches the network.
class _TestController extends ForkUpdateController {
  _TestController({super.installer, super.files});

  int ensureCalls = 0;

  @override
  Future<void> ensureChecked() async {
    ensureCalls++;
  }

  void setAvailable(ForkRelease? release) {
    available = release;
    notifyListeners();
  }
}

void main() {
  late Directory tmp;
  late FakeSideloadInstaller installer;
  late _TestController controller;
  late int downAt;

  setUp(() {
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
    tmp = Directory.systemTemp.createTempSync('fork_update_action');
    installer = FakeSideloadInstaller();
    final files = ForkUpdateFiles(root: tmp);
    controller = _TestController(installer: installer, files: files);
    downAt = 0;
    debugSessionFactory = ({release, pending}) => ForkUpdateSession(
      release: release,
      pending: pending,
      controller: controller,
      installer: installer,
      files: files,
      downloader: ForkApkDownloader(),
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

  Future<void> pumpBar(
    WidgetTester tester, {
    ForkUpdateController? provided,
    bool withProvider = true,
    bool alignRight = false,
  }) async {
    Widget plainBar() => Builder(
      builder: (context) => FocusableActionBar(
        onNavigateDown: () => downAt++,
        actions: [
          FocusableAction(debugLabel: 'refresh', onPressed: () {}, child: const SizedBox(width: 40, height: 40)),
          FocusableAction(debugLabel: 'together', onPressed: () {}, child: const SizedBox(width: 40, height: 40)),
          forkUpdateAction(context, iconColor: Colors.white),
          FocusableAction(debugLabel: 'remote', onPressed: () {}, child: const SizedBox(width: 40, height: 40)),
        ],
      ),
    );
    // Like the home app bar: actions at the top right, the remote followed by
    // the user menu (~48 px) and the bar's end margin.
    Widget bar() => alignRight
        ? Align(
            alignment: Alignment.topRight,
            child: Padding(padding: const EdgeInsets.only(right: 64), child: plainBar()),
          )
        : plainBar();
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          home: Scaffold(
            body: withProvider
                ? ChangeNotifierProvider<ForkUpdateController>.value(value: provided ?? controller, child: bar())
                : bar(),
          ),
        ),
      ),
    );
    InputModeTracker.reportNonPointerInput();
    await tester.pump();
  }

  String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  bool onSlot(String label) => focusedLabel()?.contains(label) ?? false;

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  Future<void> focusLabel(WidgetTester tester, String label) async {
    final state = tester.state<FocusableActionBarState>(find.byType(FocusableActionBar));
    final labels = ['refresh', 'together', 'fork_update', 'remote'];
    state.getFocusNode(labels.indexOf(label))!.requestFocus();
    await tester.pumpAndSettle();
  }

  testWidgets('without update: empty slot, Right goes past it (CA2)', (tester) async {
    await pumpBar(tester);
    expect(find.byIcon(Icons.system_update_rounded), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    await focusLabel(tester, 'together');
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(onSlot('remote'), isTrue);
  });

  testWidgets('without provider: empty action, no crash', (tester) async {
    await pumpBar(tester, withProvider: false);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('unsupported build returns the empty action and never checks', (tester) async {
    ForkSideload.debugForceSupported = false;
    controller.available = _release;
    await pumpBar(tester);
    expect(find.byType(IconButton), findsNothing);
    expect(controller.ensureCalls, 0);
  });

  testWidgets('update appearing while the remote is focused keeps the focus on it', (tester) async {
    await pumpBar(tester);
    await focusLabel(tester, 'remote');
    controller.setAvailable(_release);
    await tester.pumpAndSettle();
    expect(find.byType(IconButton), findsOneWidget);
    expect(onSlot('remote'), isTrue);
  });

  testWidgets('with update: Right reaches the button, Left/Right move, Down navigates (CA3)', (tester) async {
    controller.available = _release;
    await pumpBar(tester);
    await focusLabel(tester, 'together');
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(onSlot('fork_update'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(onSlot('together'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(onSlot('fork_update'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(downAt, 1);
  });

  testWidgets('label only when focused, badge always present', (tester) async {
    controller.available = _release;
    await pumpBar(tester);
    expect(find.byKey(const ValueKey('fork_update_badge')), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
    await focusLabel(tester, 'fork_update');
    expect(find.text('Update available'), findsOneWidget);
    await focusLabel(tester, 'remote');
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('OK opens the dialog and focus returns to the button on close (CA7, CA9)', (tester) async {
    controller.available = _release;
    await pumpBar(tester);
    await focusLabel(tester, 'fork_update');
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(onSlot('fork_update'), isTrue);
  });

  testWidgets('touch on the IconButton opens the dialog (CA26)', (tester) async {
    controller.available = _release;
    await pumpBar(tester);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a pending install reopens the dialog once, ready to install', (tester) async {
    installer.canRequestInstallsAnswers.add(true);
    controller.pendingInstall = ForkPendingInstall(
      pending: ForkPendingUpdate(
        version: '0.2.0',
        abi: 'armeabi-v7a',
        versionCode: 2,
        size: 10,
        fileName: 'a.apk',
        createdAt: DateTime.utc(2026),
      ),
      release: _release,
      apkPath: '${tmp.path}/a.apk',
    );
    await pumpBar(tester);
    await tester.pumpAndSettle();
    expect(find.text('Version 0.2.0 ready to install'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
    expect(controller.resumeConsumed, isTrue);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    controller.setAvailable(_release); // forces a rebuild
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('focus label sits right under the button, centred on it', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.available = _release;
    await pumpBar(tester, alignRight: true);
    await focusLabel(tester, 'fork_update');

    final button = tester.getRect(find.byType(IconButton));
    // Measure the label's background, not only its text: a follower given the
    // overlay's tight constraints would stretch it over the whole screen.
    final label = tester.getRect(
      find.ancestor(of: find.text('Update available'), matching: find.byType(Material)).first,
    );
    expect(label.width, lessThan(400));
    expect(label.height, lessThan(60));
    expect(label.top, greaterThanOrEqualTo(button.bottom));
    expect(label.top - button.bottom, lessThan(24));
    expect((label.center.dx - button.center.dx).abs(), lessThan(2));
    expect(label.left, greaterThanOrEqualTo(0));
    expect(label.right, lessThanOrEqualTo(1920));
  });
}
