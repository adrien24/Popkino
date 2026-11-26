import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/fork_trackers.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/seerr_account_provider.dart';
import 'package:plezy/providers/trackers_provider.dart';
import 'package:plezy/screens/settings/services_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/trackers/simkl/simkl_constants.dart';
import 'package:plezy/services/trackers/tracker_constants.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  tearDown(() {
    ForkTrackers.debugCredentialsOverride = null;
  });

  ForkTrackerCredentials creds({String trakt = '', String traktSecret = '', String simkl = '', String mdblist = ''}) =>
      ForkTrackerCredentials(
        traktClientId: trakt,
        traktClientSecret: traktSecret,
        simklClientId: simkl,
        mdblistClientId: mdblist,
      );

  test('MAL et AniList ne sont jamais proposés', () {
    ForkTrackers.debugCredentialsOverride = creds(trakt: 'a', traktSecret: 'b', simkl: 'c', mdblist: 'd');
    expect(ForkTrackers.isOffered(TrackerService.mal), isFalse);
    expect(ForkTrackers.isOffered(TrackerService.anilist), isFalse);
  });

  test('Trakt exige l\'identifiant et le secret', () {
    ForkTrackers.debugCredentialsOverride = creds(trakt: 'a', traktSecret: 'b');
    expect(ForkTrackers.isOffered(TrackerService.trakt), isTrue);

    ForkTrackers.debugCredentialsOverride = creds(trakt: 'a');
    expect(ForkTrackers.isOffered(TrackerService.trakt), isFalse);

    ForkTrackers.debugCredentialsOverride = creds(traktSecret: 'b');
    expect(ForkTrackers.isOffered(TrackerService.trakt), isFalse);

    ForkTrackers.debugCredentialsOverride = creds();
    expect(ForkTrackers.isOffered(TrackerService.trakt), isFalse);
  });

  test('Simkl dépend de son identifiant seul', () {
    ForkTrackers.debugCredentialsOverride = creds(simkl: 'c');
    expect(ForkTrackers.isOffered(TrackerService.simkl), isTrue);

    ForkTrackers.debugCredentialsOverride = creds();
    expect(ForkTrackers.isOffered(TrackerService.simkl), isFalse);
  });

  test('MDBList dépend de son identifiant seul', () {
    ForkTrackers.debugCredentialsOverride = creds(mdblist: 'd');
    expect(ForkTrackers.isOffered(TrackerService.mdblist), isTrue);

    ForkTrackers.debugCredentialsOverride = creds();
    expect(ForkTrackers.isOffered(TrackerService.mdblist), isFalse);
  });

  test('Simkl : l\'identifiant historique est celui de V2', () {
    expect(SimklConstants.legacyClientId, SimklConstants.v2ClientId);
  });

  group('ServicesSettingsScreen', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    Future<void> pumpHub(WidgetTester tester) async {
      final trackers = TrackersProvider();
      final seerr = SeerrAccountProvider();
      addTearDown(trackers.dispose);
      addTearDown(seerr.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TrackersProvider>.value(value: trackers),
            ChangeNotifierProvider<SeerrAccountProvider>.value(value: seerr),
          ],
          child: MaterialApp(theme: monoTheme(MonoPalette.dark), home: const ServicesSettingsScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('affiche chaque tracker selon ses identifiants, jamais MAL ni AniList', (tester) async {
      ForkTrackers.debugCredentialsOverride = creds(trakt: 'a', traktSecret: 'b', simkl: 'c', mdblist: 'd');
      await pumpHub(tester);
      expect(find.text(t.trakt.title), findsOneWidget);
      expect(find.text(t.services.names.simkl), findsOneWidget);
      expect(find.text(t.services.names.mdblist), findsOneWidget);
      expect(find.text(t.services.names.mal), findsNothing);
      expect(find.text(t.services.names.anilist), findsNothing);
      expect(find.text(t.services.names.seerr), findsOneWidget);
    });

    testWidgets('masque les trackers sans identifiants, garde Seerr', (tester) async {
      ForkTrackers.debugCredentialsOverride = creds();
      await pumpHub(tester);
      expect(find.text(t.trakt.title), findsNothing);
      expect(find.text(t.services.names.simkl), findsNothing);
      expect(find.text(t.services.names.mdblist), findsNothing);
      expect(find.text(t.services.names.seerr), findsOneWidget);
    });
  });
}
