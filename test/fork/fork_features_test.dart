// FORK: les services du projet Plezy restent coupés dans Popkino
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/focus/focusable_action_bar.dart';
import 'package:plezy/fork/fork_features.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/providers/theme_provider.dart';
import 'package:plezy/screens/settings/logs_screen.dart';
import 'package:plezy/screens/settings/theme_settings_screen.dart';
import 'package:plezy/services/app_exit_service.dart';
import 'package:plezy/services/app_icon/app_icon_service.dart';
import 'package:plezy/services/discord_rpc_service.dart';
import 'package:plezy/services/donation_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/startup_diagnostics.dart';
import 'package:plezy/services/supporter/supporter_mode.dart';
import 'package:plezy/services/supporter/supporter_service.dart';
import 'package:plezy/services/trackers/mdblist/mdblist_tracker.dart';
import 'package:plezy/services/trackers/simkl/simkl_tracker.dart';
import 'package:plezy/services/trackers/trakt/trakt_tracker.dart';
import 'package:plezy/utils/app_logger.dart';
import 'package:plezy/widgets/startup_failure_view.dart';
import 'package:provider/provider.dart';

import '../test_helpers/app_icon_fakes.dart';
import '../test_helpers/discord_rpc_fakes.dart';
import '../test_helpers/prefs.dart';

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('Discord', () {
    test('presence is unavailable and connecting does nothing', () async {
      expect(DiscordRPCService.isAvailable, isFalse);

      final clients = <FakeDiscordRPC>[];
      final service = DiscordRPCService.forTesting(
        rpcFactory: () {
          final client = FakeDiscordRPC();
          clients.add(client);
          return client;
        },
      );

      await service.setEnabled(true);

      expect(clients, isEmpty);
    });
  });

  group('donations and supporter mode', () {
    test('the donation tile is inactive', () {
      expect(DonationService.isEnabled, isFalse);
    });

    test('the build is in unlocked supporter mode', () {
      expect(supporterBuildMode, SupporterMode.unlocked);
    });

    test('SupporterService is unlocked without a store', () {
      final service = SupporterService();
      addTearDown(service.dispose);

      expect(service.availability, SupporterAvailability.free);
      expect(service.isUnlocked, isTrue);
    });
  });

  group('trackers', () {
    test('no tracker needs the Fribb anime mappings', () {
      expect(TraktTracker.instance.needsFribb, isFalse);
      expect(SimklTracker.instance.needsFribb, isFalse);
      expect(MdblistTracker.instance.needsFribb, isFalse);
    });
  });

  group('LogsScreen', () {
    testWidgets('offers copy and clear but no upload action', (tester) async {
      MemoryLogOutput.clearLogs();
      addTearDown(MemoryLogOutput.clearLogs);
      appLogger.i('fork features seed');
      PackageInfo.setMockInitialValues(
        appName: 'Popkino',
        packageName: 'io.github.adrien24.popkino',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: InputModeTracker(child: MaterialApp(home: const LogsScreen())),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<FocusableActionBar>(find.byType(FocusableActionBar));
      final tooltips = bar.actions.map((action) => action.tooltip).toList();
      expect(tooltips, containsAll([t.logs.copyLogs, t.logs.clearLogs]));
      expect(tooltips, isNot(contains(t.logs.uploadLogs)));
    });
  });

  group('StartupFailureView', () {
    testWidgets('has copy but no upload button', (tester) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: Scaffold(
              body: StartupFailureView(
                failure: StartupFailureRecord(
                  phase: StartupPhase.preferences,
                  errorType: 'Error',
                  message: 'boom',
                  stackTrace: null,
                  timestamp: DateTime.utc(2026),
                  appVersion: '1.0.0',
                  platform: 'android',
                  repairable: false,
                ),
                restartRequired: false,
                onRetry: () {},
                onRepair: null,
                requestExit: ({AppExitApplication? exitApplicationForTesting}) async => false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(startupFailureCopyKey), findsOneWidget);
      expect(find.byKey(startupFailureUploadKey), findsNothing);
    });
  });

  group('theme screen', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    testWidgets('shows no lock and no price', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final supporter = SupporterService();
      addTearDown(supporter.dispose);
      final theme = ThemeProvider(supporter: supporter);
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        InputModeTracker(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<SupporterService>.value(value: supporter),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ],
            child: Consumer<ThemeProvider>(
              builder: (_, provider, _) => MaterialApp(
                theme: provider.lightTheme,
                darkTheme: provider.darkTheme,
                themeMode: provider.materialThemeMode,
                home: const ThemeSettingsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Symbols.lock_rounded), findsNothing);
      expect(supporter.storeState.value.price, isNull);
    });
  });

  group('alternate app icons', () {
    test('the service reports no support and never asks the platform', () async {
      expect(ForkFeatures.alternateAppIcons, isFalse);

      final platform = FakeAppIconPlatform()..install();
      addTearDown(platform.uninstall);
      final supporter = SupporterService.forTesting(availability: SupporterAvailability.free);
      addTearDown(supporter.dispose);
      final service = AppIconService(supporter: supporter);
      addTearDown(service.dispose);

      await service.refresh();

      expect(service.isSupported, isFalse);
      await expectLater(service.setIcon('midnight'), throwsA(isA<AppIconException>()));
    });
  });

  group('legacy desktop database', () {
    test('an existing source is left in place', () async {
      final tempDir = await Directory.systemTemp.createTemp('fork_legacy_migration_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final source = File('${tempDir.path}/Documents/plezy_downloads.db');
      final target = File('${tempDir.path}/AppData/popkino_downloads.db');
      await source.parent.create(recursive: true);
      await target.parent.create(recursive: true);
      await source.writeAsBytes([1, 2, 3]);

      await migrateLegacyDesktopDatabase(sourceOverride: source, target: target);

      expect(await source.exists(), isTrue);
      expect(await target.exists(), isFalse);
    });
  });
}
