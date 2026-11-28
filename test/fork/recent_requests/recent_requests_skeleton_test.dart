// FORK: demandes-recentes-sans-saut — tests of the grey placeholder card of the recent-requests row (T3)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/recent_requests/recent_requests_skeleton.dart';
import 'package:plezy/focus/card_focus_scope.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/focus/locked_hub_controller.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

const _library = MediaLibrary(
  id: 'lib1',
  backend: MediaBackend.plex,
  title: 'Series',
  kind: MediaKind.show,
  serverId: 'srvA',
);

const _rowId = 'popkino.recentRequests:srvA:lib1';
const _rowTitle = 'Demandes récentes';

MediaHub _hub(List<MediaItem> items) =>
    MediaHub(id: _rowId, title: _rowTitle, type: 'mixed', items: items, size: items.length);

List<MediaItem> _realItems(int n) => [
  for (var i = 0; i < n; i++)
    CatalogItem(
      source: CatalogSourceId.seerr,
      kind: MediaKind.movie,
      title: 'Movie $i',
      ids: CatalogItemIds(tmdb: i + 1),
    ).toMediaItem(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('forkSkeletonItems', () {
    test('builds n anonymous portrait items flagged as skeletons', () {
      final items = forkSkeletonItems(_library, 3);
      expect(items, hasLength(3));
      for (final item in items) {
        expect(forkIsSkeletonItem(item), isTrue);
        expect(item.kind, MediaKind.movie);
        expect(item.backend, MediaBackend.plex);
        expect(item.title, isNull);
        expect(item.serverId, isNull);
      }
      expect({for (final i in items) i.id}, hasLength(3));
      expect(forkIsSkeletonItem(_realItems(1).single), isFalse);
      expect(forkIsSkeletonItem('not an item'), isFalse);
    });
  });

  Widget harness(Widget child) => ChangeNotifierProvider<MultiServerProvider>(
    create: (_) => testMultiServerProvider(MultiServerManager()),
    child: InputModeTracker(
      child: MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(body: child),
      ),
    ),
  );

  group('geometry against the real row inside TvBrowseRail', () {
    const sizes = [Size(960, 540), Size(1280, 720), Size(1920, 1080)];

    for (final size in sizes) {
      for (final fullCard in [false, true]) {
        testWidgets('same section height, same next-row position, no overflow at $size fullCard=$fullCard', (
          tester,
        ) async {
          TvDetectionService.debugSetAppleTVOverride(true);
          await SettingsService.instanceOrNull!.write(SettingsService.tvFullCardLayout, fullCard);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);

          final next = MediaHub(
            id: 'next',
            title: 'Next row',
            type: 'movie',
            items: [testMediaItem(id: 'n1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Next movie')],
            size: 1,
          );

          Future<({Size section, Offset nextTitle, Size card})> measure(List<MediaItem> items) async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              harness(
                SizedBox(
                  width: size.width,
                  height: size.height,
                  child: TvBrowseRail(
                    focusMemory: HubFocusMemory(),
                    hubs: [_hub(items), next],
                    iconForHub: (_, _) => Icons.movie_rounded,
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull);

            final section = find
                .ancestor(
                  of: find.text(_rowTitle),
                  matching: find.byWidgetPredicate((w) => w is SizedBox && w.key is GlobalKey),
                )
                .first;
            return (
              section: tester.getSize(section),
              nextTitle: tester.getTopLeft(find.text('Next row')),
              card: tester.getSize(find.byType(MediaCard).first),
            );
          }

          final grey = await measure(forkSkeletonItems(_library, 5));
          final real = await measure(_realItems(5));

          expect(grey.section, real.section, reason: 'section height');
          expect(grey.nextTitle, real.nextTitle, reason: 'next row position');
          // The two grey strokes are 3 logical px shorter than the real caption band: never taller (no overflow),
          // and the section and the next row, which decide the jump, are identical.
          expect(grey.card.width, real.card.width, reason: 'card width');
          expect(grey.card.height, lessThanOrEqualTo(real.card.height), reason: 'card height');
          expect(real.card.height - grey.card.height, lessThan(4), reason: 'card height gap');
        });
      }
    }
  });

  testWidgets('a skeleton card shows no text (CA4)', (tester) async {
    await tester.pumpWidget(
      harness(Center(child: MediaCard(item: forkSkeletonItems(_library, 1).single, width: 150, height: 225))),
    );

    expect(find.descendant(of: find.byType(MediaCard), matching: find.byType(Text)), findsNothing);
    expect(find.byType(SkeletonLoader), findsWidgets);
  });

  testWidgets('a skeleton card draws the focus border through CardFocusBorder (CA10c)', (tester) async {
    await tester.pumpWidget(
      harness(
        Center(
          child: CardFocusScope(
            showFocus: true,
            child: MediaCard(item: forkSkeletonItems(_library, 1).single, width: 150, height: 225),
          ),
        ),
      ),
    );

    final border = find.descendant(of: find.byType(MediaCard), matching: find.byType(CardFocusBorder));
    expect(border, findsOneWidget);
    final container = tester.widget<AnimatedContainer>(
      find.descendant(of: border, matching: find.byType(AnimatedContainer)).first,
    );
    expect(container.foregroundDecoration, isNotNull);
  });

  testWidgets('showContextMenu on a skeleton card does nothing (CA10)', (tester) async {
    final observer = _RouteCounter();
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>(
        create: (_) => testMultiServerProvider(MultiServerManager()),
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark),
          navigatorObservers: [observer],
          home: Scaffold(
            body: Center(child: MediaCard(item: forkSkeletonItems(_library, 1).single, width: 150, height: 225)),
          ),
        ),
      ),
    );
    final pushedBefore = observer.pushed;

    tester.state<MediaCardState>(find.byType(MediaCard)).showContextMenu();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(observer.pushed, pushedBefore);
  });

  group('forkSkeletonVisibleCap', () {
    Future<int> cap(WidgetTester tester, Size size, int density) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await SettingsService.instanceOrNull!.write(SettingsService.libraryDensity, density);
      late int result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = forkSkeletonVisibleCap(context, _hub(forkSkeletonItems(_library, 1)));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('is 8 off TV', (tester) async {
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      TvDetectionService.debugSetAppleTVOverride(false);
      expect(await cap(tester, const Size(1920, 1080), 3), 8);
    });

    testWidgets('is 6 to 10 at 1920x1080 and decreases with the density', (tester) async {
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      TvDetectionService.debugSetAppleTVOverride(true);
      final caps = [
        for (final d in [1, 3, 5]) await cap(tester, const Size(1920, 1080), d),
      ];

      for (final c in caps) {
        expect(c, inInclusiveRange(6, 10), reason: '$caps');
      }
      expect(caps[0], greaterThanOrEqualTo(caps[1]), reason: '$caps');
      expect(caps[1], greaterThanOrEqualTo(caps[2]), reason: '$caps');
    });

    testWidgets('strictly decreases with the density where the card width is not clamped (960x540)', (tester) async {
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      TvDetectionService.debugSetAppleTVOverride(true);
      final caps = [
        for (final d in [1, 3, 5]) await cap(tester, const Size(960, 540), d),
      ];

      expect(caps[0], greaterThan(caps[2]), reason: '$caps');
      expect(caps[0], greaterThanOrEqualTo(caps[1]), reason: '$caps');
      expect(caps[1], greaterThanOrEqualTo(caps[2]), reason: '$caps');
    });
  });
}

class _RouteCounter extends NavigatorObserver {
  int pushed = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed++;
}
