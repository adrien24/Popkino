// FORK: demandes-recentes-overseerr — tests of the single status badge of the recent-requests row (T10)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/recent_requests/recent_request.dart';
import 'package:plezy/fork/recent_requests/recent_request_badge.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/models/seerr/seerr_request.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/media_card.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';

const _over = SeerrProduct.overseerr;
const _jelly = SeerrProduct.jellyseerr;

SeerrRequest _q(SeerrRequestStatus status, {bool is4k = false, int id = 1}) =>
    SeerrRequest(id: id, status: status, is4k: is4k);

ForkRecentRequest _r({
  int? status,
  int? status4k,
  List<SeerrRequestStatus> requests = const [],
  bool downloading = false,
  bool downloading4k = false,
}) => ForkRecentRequest(
  downloading: downloading,
  downloading4k: downloading4k,
  latestRequestId: 1,
  kind: MediaKind.movie,
  tmdbId: 1,
  mediaStatusCode: status,
  mediaStatus4kCode: status4k,
  myRequests: [for (final (i, s) in requests.indexed) _q(s, id: i + 1)],
);

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _harness(MediaItem item, {double width = 100}) => MaterialApp(
  theme: monoTheme(MonoPalette.dark),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: 220,
        child: MediaCard(item: item, width: width, height: 150, viewModeOverride: ViewMode.grid, isOffline: true),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));
  tearDown(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  group('forkRequestBadgeFor', () {
    const approved = SeerrRequestStatus.approved;
    const pending = SeerrRequestStatus.pending;
    const failed = SeerrRequestStatus.failed;
    const declined = SeerrRequestStatus.declined;
    const completed = SeerrRequestStatus.completed;

    final cases = <(String, ForkRecentRequest, SeerrProduct, ForkRequestBadge?)>[
      ('5 + approved', _r(status: 5, requests: [approved]), _over, ForkRequestBadge.available),
      ('4 + approved', _r(status: 4, requests: [approved]), _over, ForkRequestBadge.partial),
      ('3 without download', _r(status: 3), _over, ForkRequestBadge.requested),
      ('3 + downloading', _r(status: 3, downloading: true), _over, ForkRequestBadge.processing),
      (
        '3 without download + approved (Invincible)',
        _r(status: 3, requests: [approved]),
        _over,
        ForkRequestBadge.requested,
      ),
      ('3 without download + pending', _r(status: 3, requests: [pending]), _over, ForkRequestBadge.requested),
      (
        'HD 3 + 4K 3 downloading4k',
        _r(status: 3, status4k: 3, downloading4k: true),
        _over,
        ForkRequestBadge.processing,
      ),
      ('3 + downloading4k only', _r(status: 3, downloading4k: true), _over, ForkRequestBadge.requested),
      (
        '3 + failed + downloading',
        _r(status: 3, requests: [failed], downloading: true),
        _over,
        ForkRequestBadge.processing,
      ),
      ('3 + failed without approved', _r(status: 3, requests: [failed]), _over, ForkRequestBadge.failed),
      ('3 + failed + approved', _r(status: 3, requests: [failed, approved]), _over, ForkRequestBadge.requested),
      ('2', _r(status: 2), _over, ForkRequestBadge.requested),
      ('1 + pending', _r(status: 1, requests: [pending]), _over, ForkRequestBadge.pending),
      ('pending + approved', _r(status: 1, requests: [pending, approved]), _over, ForkRequestBadge.requested),
      ('declined alone', _r(status: 1, requests: [declined]), _over, ForkRequestBadge.declined),
      ('4K only available', _r(status: 1, status4k: 5), _over, ForkRequestBadge.available),
      ('Overseerr 6', _r(status: 6), _over, ForkRequestBadge.deleted),
      ('Jellyseerr 7', _r(status: 7), _jelly, ForkRequestBadge.deleted),
      ('Overseerr 6 + approved', _r(status: 6, requests: [approved]), _over, ForkRequestBadge.deleted),
      ('Overseerr 6 + failed', _r(status: 6, requests: [failed]), _over, ForkRequestBadge.deleted),
      ('Overseerr 6 + declined', _r(status: 6, requests: [declined]), _over, ForkRequestBadge.deleted),
      ('Overseerr 6 + pending', _r(status: 6, requests: [pending]), _over, ForkRequestBadge.pending),
      (
        'Overseerr 6 + approved + pending',
        _r(status: 6, requests: [approved, pending]),
        _over,
        ForkRequestBadge.pending,
      ),
      ('HD 6 + 4K 5', _r(status: 6, status4k: 5), _over, ForkRequestBadge.available),
      ('Jellyseerr 6', _r(status: 6), _jelly, ForkRequestBadge.blocked),
      ('Jellyseerr 6 + approved', _r(status: 6, requests: [approved]), _jelly, ForkRequestBadge.blocked),
      ('Jellyseerr 6 + pending', _r(status: 6, requests: [pending]), _jelly, ForkRequestBadge.blocked),
      ('unknown product 6', _r(status: 6), SeerrProduct.unknown, ForkRequestBadge.blocked),
      ('unknown product 7', _r(status: 7), SeerrProduct.unknown, ForkRequestBadge.blocked),
      ('Overseerr 7', _r(status: 7), _over, null),
      ('1 + completed', _r(status: 1, requests: [completed]), _over, null),
      ('nothing', _r(), _over, null),
    ];

    for (final (name, request, product, expected) in cases) {
      test(name, () => expect(forkRequestBadgeFor(request, product), expected));
    }
  });

  group('colors and labels', () {
    test('contrast is at least 4.5:1 and backgrounds are opaque', () {
      for (final b in ForkRequestBadge.values) {
        expect(b.background.a, 1.0, reason: b.name);
        expect(_contrast(b.background, b.foreground), greaterThanOrEqualTo(4.5), reason: b.name);
      }
    });

    test('red is shared, the five other colors are distinct', () {
      final reds = {
        ForkRequestBadge.failed,
        ForkRequestBadge.declined,
        ForkRequestBadge.deleted,
        ForkRequestBadge.blocked,
      }.map((b) => b.background).toSet();
      expect(reds, hasLength(1));
      final others = {
        ForkRequestBadge.available,
        ForkRequestBadge.partial,
        ForkRequestBadge.processing,
        ForkRequestBadge.requested,
        ForkRequestBadge.pending,
      }.map((b) => b.background).toSet();
      expect(others, hasLength(5));
      expect(others.contains(reds.single), isFalse);
    });

    for (final locale in [AppLocale.fr, AppLocale.en]) {
      test('labels are short in ${locale.languageCode}', () async {
        await LocaleSettings.setLocale(locale);
        for (final b in ForkRequestBadge.values) {
          expect(b.label, isNotEmpty);
          expect(b.label, isNot(contains('…')));
          expect(b.label.length, lessThanOrEqualTo(11), reason: b.name);
        }
      });
    }
  });

  group('MediaCard', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    for (final tv in [true, false]) {
      for (final locale in [AppLocale.fr, AppLocale.en]) {
        for (final badge in ForkRequestBadge.values) {
          testWidgets('${badge.name} in ${locale.languageCode}, ${tv ? 'TV' : 'non-TV'}', (tester) async {
            await tester.runAsync(() => LocaleSettings.setLocale(locale));
            TvDetectionService.debugSetAppleTVOverride(tv);
            final item = testMediaItem(
              id: 'catalog:x',
              kind: MediaKind.movie,
              title: 'Film',
              raw: {kForkRequestBadgeRawKey: badge.name},
            );
            await tester.pumpWidget(_harness(item));

            expect(find.byKey(const Key('fork-request-badge')), findsOneWidget);
            expect(find.byKey(const Key('catalog-badges')), findsNothing);
            expect(find.text(badge.label), findsOneWidget);
            final text = tester.widget<Text>(find.text(badge.label));
            expect(text.overflow, isNot(TextOverflow.ellipsis));
          });
        }
      }
    }

    CatalogItem catalog() => CatalogItem(
      source: CatalogSourceId.seerr,
      kind: MediaKind.movie,
      title: 'Server Movie',
      ids: const CatalogItemIds(tmdb: 1),
      serverState: const CatalogServerState(
        availability: CatalogAvailability.available,
        request: CatalogRequestState.approved,
      ),
    );

    testWidgets('same catalog item without the key keeps the upstream stacked badges', (tester) async {
      await tester.pumpWidget(_harness(catalog().toMediaItem(), width: 220));

      expect(find.byKey(const Key('fork-request-badge')), findsNothing);
      final texts = find.descendant(of: find.byKey(const Key('catalog-badges')), matching: find.byType(Text));
      expect(texts, findsNWidgets(2));
      expect(find.text(t.explore.badge.available), findsOneWidget);
      expect(find.text(t.explore.badge.requested), findsOneWidget);
    });

    testWidgets('an unknown key value falls back to upstream', (tester) async {
      final item = catalog().toMediaItem().copyWith(
        raw: {...?catalog().toMediaItem().raw, kForkRequestBadgeRawKey: 'foo'},
      );
      await tester.pumpWidget(_harness(item, width: 220));

      expect(find.byKey(const Key('fork-request-badge')), findsNothing);
      expect(find.byKey(const Key('catalog-badges')), findsOneWidget);
    });
  });

  test('the hook ignores anything but a MediaItem', () {
    expect(forkPosterBadge('not an item'), isNull);
  });
}
