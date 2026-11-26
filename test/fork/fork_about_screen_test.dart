import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/fork/fork_identity.dart';
import 'package:plezy/fork/screens/fork_about_screen.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/licenses_screen.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

/// Pumps a "Settings" page that pushes the About screen, so Back can be checked.
Future<void> _pumpAbout(WidgetTester tester) async {
  await tester.pumpWidget(
    InputModeTracker(
      child: MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ForkAboutScreen())),
              child: const Text('open about'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open about'));
  // The tap switched the tracker to pointer mode; a remote user is in keyboard mode, which is what
  // makes the scaffold hand the initial focus to the first entry.
  InputModeTracker.reportNonPointerInput();
  await tester.pumpAndSettle();
}

/// The tile row of the entry titled [title].
Finder _tile(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));

bool _hasFocus(WidgetTester tester, String title) {
  final tile = tester.widget<ListTile>(_tile(title));
  return tile.focusNode?.hasPrimaryFocus ?? false;
}

void main() {
  final launched = <MethodCall>[];

  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    PackageInfo.setMockInitialValues(
      appName: 'Popkino',
      packageName: 'io.github.adrien24.popkino',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_urlLauncherChannel, (
      call,
    ) async {
      launched.add(call);
      return true;
    });
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _urlLauncherChannel,
      null,
    );
  });

  testWidgets('shows the logo, name, version, notice, licence and source address', (tester) async {
    await _pumpAbout(tester);

    expect(
      find.byWidgetPredicate((w) => w is Image && (w.image as AssetImage).assetName == 'assets/plezy.png'),
      findsOneWidget,
    );
    expect(find.text(ForkIdentity.appName), findsOneWidget);
    expect(find.text(t.about.versionLabel(version: '1.0.0')), findsOneWidget);
    expect(find.text(t.fork.about.basedOn), findsOneWidget);
    expect(t.fork.about.basedOn, contains(ForkIdentity.upstreamName));
    expect(find.text(ForkIdentity.licenseName), findsOneWidget);
    expect(find.text(ForkIdentity.sourceCodeUrl), findsOneWidget);
    expect(find.text(t.about.openSourceLicenses), findsOneWidget);
  });

  testWidgets('D-pad: initial focus on Source code, down reaches Open source licenses', (tester) async {
    await _pumpAbout(tester);

    expect(_hasFocus(tester, t.fork.about.sourceCode), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_hasFocus(tester, t.fork.about.license), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_hasFocus(tester, t.about.openSourceLicenses), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_hasFocus(tester, t.about.openSourceLicenses), isTrue, reason: 'last entry');
  });

  testWidgets('the licence entry opens the licenses screen', (tester) async {
    await _pumpAbout(tester);
    await tester.tap(_tile(t.fork.about.license));
    await tester.pumpAndSettle();
    expect(find.byType(LicensesScreen), findsOneWidget);
  });

  testWidgets('TV: OK on Source code opens the QR dialog, Back closes it and refocuses Source code', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    await _pumpAbout(tester);
    expect(_hasFocus(tester, t.fork.about.sourceCode), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(t.fork.about.sourceCodeQrHint), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(ForkIdentity.sourceCodeUrl)),
      findsOneWidget,
    );
    expect(launched, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
    expect(_hasFocus(tester, t.fork.about.sourceCode), isTrue);

    // Back from the screen itself returns to the previous page.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ForkAboutScreen), findsNothing);
  });

  testWidgets('without TV: Source code opens the URL instead of the QR dialog', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    await _pumpAbout(tester);

    await tester.tap(_tile(t.fork.about.sourceCode));
    await tester.pumpAndSettle();

    expect(launched, isNotEmpty);
    expect(launched.first.arguments.toString(), contains(ForkIdentity.sourceCodeUrl));
    expect(find.byType(QrImageView), findsNothing);
  });
}
