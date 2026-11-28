// FORK: demandes-recentes-sans-saut — end-to-end test of the D-pad focus and of the spotlight area with the grey row
//
// Mounts the shelf with a builder that mirrors the Recommended tab's `_buildTvContent` (real `TvSpotlightScaffold`,
// real `TvBrowseRail`, `TvSpotlightController`) and drives it with D-pad key events. See
// `docs/technique/demandes-recentes-sans-saut/plan.md` (T6).

import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/focus/locked_hub_controller.dart';
import 'package:plezy/fork/recent_requests/recent_requests_repository.dart';
import 'package:plezy/fork/recent_requests/recent_requests_row_sizes.dart';
import 'package:plezy/fork/recent_requests/recent_requests_shelf.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/seerr/seerr_client.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:plezy/widgets/tv_spotlight_scaffold.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

SeerrClient _client() => SeerrClient(
  SeerrSession(
    baseUrl: 'https://seerr.example.com',
    method: SeerrAuthMethod.local,
    identifier: 'a@b.c',
    secret: 'pw',
    cookie: 'cookie',
    userId: 7,
    permissions: SeerrPermission.admin,
    displayName: 'Alice',
    instanceLabel: 'Seerr',
    product: SeerrProduct.unknown,
    createdAt: 0,
  ),
  onSessionInvalidated: () {},
  httpClient: MockClient((_) async => http.Response('{}', 500)),
);

/// Only `seerrSource` is read by the shelf.
class _FakeSources extends ChangeNotifier implements CatalogSourcesProvider {
  _FakeSources(this.seerrSource);

  @override
  final SeerrCatalogSource? seerrSource;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo extends ForkRecentRequestsRepository {
  _FakeRepo(super.client);

  Future<ForkRowResult> Function(MediaLibrary library) resultHandler = (_) => Completer<ForkRowResult>().future;

  @override
  Future<ForkRowResult> rowResultFor(MediaLibrary library, ForkRowContext ctx) => resultHandler(library);

  @override
  ForkRecentRequestsRow? recentRowFor(MediaLibrary library) => null;
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.pushed);
  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

MediaLibrary _lib() =>
    MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Lib 1', kind: MediaKind.movie, serverId: 'srvA');

MediaHub _upstream(String id, {int count = 3}) => MediaHub(
  id: id,
  title: id,
  type: 'movie',
  items: [for (var i = 1; i <= count; i++) testMediaItem(id: '$id-$i', title: '$id $i')],
  size: count,
);

ForkRecentRequestsRow _row(MediaLibrary library, DateTime fetchedAt, int count) => ForkRecentRequestsRow(
  hub: MediaHub(
    id: '$kRecentRequestsHubIdPrefix${library.globalKey}',
    title: 'Requests',
    type: 'movie',
    items: [for (var i = 1; i <= count; i++) testMediaItem(id: 'tmdb-$i', title: 'Requested $i')],
    size: count,
  ),
  entriesByItemId: const {},
  fetchedAt: fetchedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SeerrClient client;
  late _FakeRepo repo;
  late Directory memoryDir;
  late MediaLibrary lib;
  late String forkId;
  late _FakeSources sources;
  late HubFocusMemory focusMemory;
  late TvSpotlightController spotlight;
  late GlobalKey railKey;
  final focused = <(String, String)>[];
  final resolved = <MediaItem?>[];
  final pushed = <Route<dynamic>>[];
  final now = DateTime(2026, 11, 28, 12);

  setUp(() async {
    memoryDir = Directory.systemTemp.createTempSync('popkino_tv_focus_test');
    ForkRowSizeMemory.debugDirectory = () async => memoryDir;
    ForkRowSizeMemory.debugReset();
    forkDebugResetOpenedAt();
    Provider.debugCheckInvalidValueType = null;
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    client = _client();
    repo = _FakeRepo(client);
    ForkRecentRequestsRepository.debugOverride = (_) => repo;
    sources = _FakeSources(SeerrCatalogSource(client));
    lib = _lib();
    forkId = '$kRecentRequestsHubIdPrefix${lib.globalKey}';
    focusMemory = HubFocusMemory();
    spotlight = TvSpotlightController();
    railKey = GlobalKey();
    focused.clear();
    resolved.clear();
    pushed.clear();
  });

  tearDown(() {
    spotlight.dispose();
    ForkRecentRequestsRepository.debugOverride = null;
    ForkRowSizeMemory.debugDirectory = null;
    ForkRowSizeMemory.debugReset();
    try {
      memoryDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Mirrors the Recommended tab's `_buildTvContent`.
  Widget tvContent(BuildContext context, List<MediaHub> items, ForkRequestActivator fork) {
    final tvHubs = items.where((hub) => hub.items.isNotEmpty).toList();
    return TvSpotlightScaffold(
      hubs: tvHubs,
      spotlightListenable: spotlight,
      resolveSpotlight: () {
        final item = spotlight.resolve(forkSpotlightHubs(tvHubs));
        resolved.add(item);
        return item;
      },
      resolveClient: (_) => null,
      foreground: tvHubs.isEmpty
          ? const SizedBox.shrink()
          : Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TvBrowseRail(
                key: railKey,
                hubs: tvHubs,
                focusMemory: focusMemory,
                iconForHub: (hub, _) => fork.iconFor(hub) ?? Icons.tv_rounded,
                onActivateItem: (hub, item) => fork.activate(context, hub, item),
                onFocusedItemChanged: (item) {
                  if (!forkIsSkeletonItem(item)) spotlight.select(item);
                },
                onFocusedHubItemChanged: (hub, item) => focused.add((hub.id, item.id)),
                isContinueWatchingHub: (hub) => hub.isContinueWatchingHub,
                usesContinueWatchingAction: (hub) => hub.usesContinueWatchingAction,
                tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
                widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
              ),
            ),
    );
  }

  Widget host(List<MediaHub> hubs) => MultiProvider(
    providers: [
      Provider<CatalogSourcesProvider?>.value(value: sources),
      ChangeNotifierProvider<MultiServerProvider>(create: (_) => testMultiServerProvider(MultiServerManager())),
    ],
    child: MaterialApp(
      theme: monoTheme(MonoPalette.dark),
      navigatorObservers: [_PushObserver(pushed)],
      home: ForkRecentRequestsShelf(library: lib, hubs: hubs, builder: tvContent),
    ),
  );

  /// Remembers [n] posters for the library, then mounts the shelf and focuses the rail.
  Future<void> open(WidgetTester tester, List<MediaHub> hubs, {int n = 6}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await ForkRowSizeMemory.instance.ensureLoaded();
      await ForkRowSizeMemory.instance.remember(client.session, lib, n);
    });
    await tester.pumpWidget(host(hubs));
    await tester.pump();
    (railKey.currentState! as TvBrowseRailState).requestFocus();
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  /// Lets the spotlight controller's debouncer fire.
  Future<void> settleSpotlight(WidgetTester tester) => tester.pump(const Duration(milliseconds: 400));

  Future<void> down(WidgetTester tester) => press(tester, LogicalKeyboardKey.arrowDown);
  Future<void> right(WidgetTester tester) => press(tester, LogicalKeyboardKey.arrowRight);

  /// The server answers [count] posters; settles the frames that follow.
  Future<void> answer(WidgetTester tester, Completer<ForkRowResult> pending, int count) async {
    pending.complete((row: _row(lib, now, count), conclusive: true));
    await tester.pumpAndSettle();
    // `remember` writes through a future created outside the fake zone: let the real event loop run.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }

  /// The 10 s placeholder window runs out: one poster is left, then none.
  Future<void> timeOut(WidgetTester tester) async {
    await tester.pump(kRecentRequestsPlaceholderTimeout);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Completer<ForkRowResult> pendingAnswer() {
    final pending = Completer<ForkRowResult>();
    repo.resultHandler = (_) => pending.future;
    return pending;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('CA10: D-pad walks through the grey row; OK on a grey poster navigates nowhere', (tester) async {
    await withClock(Clock(() => now), () async {
      pendingAnswer();
      await open(tester, [_upstream('home.continue'), _upstream('recent')]);
      expect(focused.last, ('home.continue', 'home.continue-1'));

      await down(tester);
      expect(focused.last, (forkId, 'popkino.recentRequests.skeleton:0'), reason: 'Down: grey row, column 0');
      await right(tester);
      expect(focused.last, (forkId, 'popkino.recentRequests.skeleton:1'), reason: 'Right: column 1');

      final routes = pushed.length;
      await press(tester, LogicalKeyboardKey.select);
      expect(pushed.length, routes, reason: 'OK on a grey poster does not navigate');
      expect(focused.last.$1, forkId);

      await down(tester);
      expect(focused.last.$1, 'recent', reason: 'Down: next row');
      await unmount(tester);
    });
  });

  for (final (focusedColumn, realCount, expectedId) in [(2, 2, 'tmdb-2'), (1, 5, 'tmdb-2')]) {
    testWidgets('CA10b: grey column $focusedColumn, $realCount real posters: focus on $expectedId', (tester) async {
      await withClock(Clock(() => now), () async {
        final pending = pendingAnswer();
        await open(tester, [_upstream('home.continue'), _upstream('recent')]);
        await down(tester);
        for (var i = 0; i < focusedColumn; i++) {
          await right(tester);
        }
        expect(focused.last, (forkId, 'popkino.recentRequests.skeleton:$focusedColumn'));

        await answer(tester, pending, realCount);
        expect(focused.last, (forkId, expectedId));
        await unmount(tester);
      });
    });
  }

  testWidgets('CA10b: removing the row hands the focus to the next row', (tester) async {
    await withClock(Clock(() => now), () async {
      pendingAnswer();
      await open(tester, [_upstream('home.continue'), _upstream('recent')]);
      await down(tester);
      await right(tester);
      await right(tester);
      expect(focused.last, (forkId, 'popkino.recentRequests.skeleton:2'));

      await timeOut(tester);
      expect(focused.last, ('recent', 'recent-1'), reason: 'first poster of the next row');
      await unmount(tester);
    });
  });

  testWidgets('CA10b: removing the last row hands the focus to the previous row', (tester) async {
    await withClock(Clock(() => now), () async {
      pendingAnswer();
      await open(tester, [_upstream('home.continue')]);
      await down(tester);
      await right(tester);
      await right(tester);
      expect(focused.last, (forkId, 'popkino.recentRequests.skeleton:2'));

      await timeOut(tester);
      expect(focused.last, ('home.continue', 'home.continue-1'), reason: 'first poster of the previous row');
      await unmount(tester);
    });
  });

  testWidgets('CA10c: focus on the row below stays on the same poster when the row is removed', (tester) async {
    await withClock(Clock(() => now), () async {
      pendingAnswer();
      await open(tester, [_upstream('home.continue'), _upstream('recent')]);
      await down(tester);
      await down(tester);
      await right(tester);
      expect(focused.last, ('recent', 'recent-2'));

      await timeOut(tester);
      expect(focused.last, ('recent', 'recent-2'));
      await unmount(tester);
    });
  });

  testWidgets('CA10c: focus above stays on the same poster when the row is replaced', (tester) async {
    await withClock(Clock(() => now), () async {
      final pending = pendingAnswer();
      await open(tester, [_upstream('home.continue'), _upstream('recent')]);
      await right(tester);
      expect(focused.last, ('home.continue', 'home.continue-2'));

      await answer(tester, pending, 4);
      expect(focused.last, ('home.continue', 'home.continue-2'));
      await unmount(tester);
    });
  });

  testWidgets('CA14: the spotlight area never shows a grey poster', (tester) async {
    await withClock(Clock(() => now), () async {
      // Without Continue Watching, the grey row is at index 0: the opening spotlight is the next row's first poster.
      final pending = pendingAnswer();
      await open(tester, [_upstream('recent')]);
      expect(resolved, isNotEmpty);
      expect(resolved.last?.id, 'recent-1', reason: 'never a grey item');
      expect(resolved.every((i) => i == null || !forkIsSkeletonItem(i)), isTrue);
      expect(focused.first, (forkId, 'popkino.recentRequests.skeleton:0'), reason: 'focus starts on the grey row');
      expect(spotlight.value, isNull, reason: 'a grey poster never reaches the controller');
      await unmount(tester);

      // With a real title shown and the focus on a grey poster, the area keeps the last real title.
      focused.clear();
      resolved.clear();
      focusMemory = HubFocusMemory();
      railKey = GlobalKey();
      final pending2 = pendingAnswer();
      await open(tester, [_upstream('home.continue'), _upstream('recent')]);
      await settleSpotlight(tester);
      expect(spotlight.value?.id, 'home.continue-1');
      await down(tester);
      await settleSpotlight(tester);
      expect(focused.last, (forkId, 'popkino.recentRequests.skeleton:0'));
      expect(spotlight.value?.id, 'home.continue-1', reason: 'last real title kept');
      expect(resolved.last?.id, 'home.continue-1');

      // The real poster arrives under the focus: the area switches to its title.
      await answer(tester, pending2, 3);
      await settleSpotlight(tester);
      expect(focused.last, (forkId, 'tmdb-1'));
      expect(spotlight.value?.id, 'tmdb-1');
      expect(resolved.last?.id, 'tmdb-1');
      pending.complete(_emptyAnswer);
      await unmount(tester);
    });
  });
}

const ForkRowResult _emptyAnswer = (row: null, conclusive: true);
