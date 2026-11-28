// FORK: demandes-recentes-overseerr — tests of the recent requests row widget and its TV behaviour

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
import 'package:plezy/fork/recent_requests/recent_requests_skeleton.dart';
import 'package:plezy/fork/recent_requests/recent_requests_shelf.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/seerr/seerr_client.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

SeerrClient _client({SeerrProduct product = SeerrProduct.unknown}) => SeerrClient(
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
    product: product,
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

/// Only `isOffline` is read by the shelf.
class _FakeOffline extends ChangeNotifier implements OfflineModeProvider {
  _FakeOffline(this.isOffline);

  @override
  final bool isOffline;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo extends ForkRecentRequestsRepository {
  _FakeRepo(super.client, this.handler);

  /// Simple answers: a row is conclusive, null is not. [resultHandler] takes over when set.
  Future<ForkRecentRequestsRow?> Function(MediaLibrary library) handler;
  Future<ForkRowResult> Function(MediaLibrary library)? resultHandler;

  /// What [recentRowFor] answers, per library global key.
  final Map<String, ForkRecentRequestsRow> recent = {};
  final List<MediaLibrary> calls = [];

  @override
  Future<ForkRowResult> rowResultFor(MediaLibrary library, ForkRowContext ctx) async {
    calls.add(library);
    final custom = resultHandler;
    if (custom != null) return custom(library);
    final row = await handler(library);
    return (row: row, conclusive: row != null);
  }

  @override
  ForkRecentRequestsRow? recentRowFor(MediaLibrary library) => recent[library.globalKey];
}

const ForkRowResult _inconclusive = (row: null, conclusive: false);
const ForkRowResult _emptyAnswer = (row: null, conclusive: true);

MediaLibrary _lib(String id, {MediaKind kind = MediaKind.movie, MediaBackend backend = MediaBackend.plex}) =>
    MediaLibrary(id: id, backend: backend, title: 'Lib $id', kind: kind, serverId: 'srvA');

MediaHub _upstream(String id) => MediaHub(
  id: id,
  title: id,
  type: 'movie',
  items: [testMediaItem(id: '$id-1', title: id)],
  size: 1,
);

ForkRecentRequestsRow _row(MediaLibrary library, DateTime fetchedAt, {int count = 1}) => ForkRecentRequestsRow(
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
  var now = DateTime(2026, 11, 28, 12);

  setUp(() async {
    memoryDir = Directory.systemTemp.createTempSync('popkino_shelf_test');
    ForkRowSizeMemory.debugDirectory = () async => memoryDir;
    ForkRowSizeMemory.debugReset();
    forkDebugResetOpenedAt();
    // The fake provider is a ChangeNotifier supplied by value.
    Provider.debugCheckInvalidValueType = null;
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    client = _client();
    now = DateTime(2026, 11, 28, 12);
    repo = _FakeRepo(client, (library) async => _row(library, now));
    ForkRecentRequestsRepository.debugOverride = (_) => repo;
  });

  tearDown(() {
    ForkRecentRequestsRepository.debugOverride = null;
    ForkRowSizeMemory.debugDirectory = null;
    ForkRowSizeMemory.debugReset();
    try {
      memoryDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget host({
    required MediaLibrary library,
    required List<MediaHub> hubs,
    required List<List<String>> seen,
    SeerrCatalogSource? source,
  }) {
    return Provider<CatalogSourcesProvider?>.value(
      value: source == null ? null : _FakeSources(source),
      child: MaterialApp(
        home: ForkRecentRequestsShelf(
          library: library,
          hubs: hubs,
          builder: (context, hubs, fork) {
            seen.add([for (final h in hubs) h.id]);
            return Column(children: [for (final h in hubs) Text(h.id)]);
          },
        ),
      ),
    );
  }

  group('ForkRecentRequestsShelf', () {
    testWidgets('inserts the row after Continue Watching (CA1)', (tester) async {
      await withClock(Clock(() => now), () async {
        final lib = _lib('1');
        final seen = <List<String>>[];
        final source = SeerrCatalogSource(client);
        final hubs = [_upstream('home.continue'), _upstream('recent')];
        await tester.pumpWidget(host(library: lib, hubs: hubs, seen: seen, source: source));
        expect(seen.first, ['home.continue', 'recent']);
        await tester.pump();
        expect(seen.last, ['home.continue', '$kRecentRequestsHubIdPrefix${lib.globalKey}', 'recent']);
        expect(hubs.map((h) => h.id), ['home.continue', 'recent'], reason: 'received list untouched');
      });
    });

    testWidgets('inserts the row first without Continue Watching (CA4)', (tester) async {
      await withClock(Clock(() => now), () async {
        final lib = _lib('1', kind: MediaKind.show);
        final seen = <List<String>>[];
        await tester.pumpWidget(
          host(library: lib, hubs: [_upstream('recent')], seen: seen, source: SeerrCatalogSource(client)),
        );
        await tester.pump();
        expect(seen.last, ['$kRecentRequestsHubIdPrefix${lib.globalKey}', 'recent']);
      });
    });

    testWidgets('no Seerr provider: list unchanged and no call (CA15)', (tester) async {
      final seen = <List<String>>[];
      await tester.pumpWidget(host(library: _lib('1'), hubs: [_upstream('recent')], seen: seen));
      await tester.pump();
      expect(seen.every((s) => s.length == 1 && s.first == 'recent'), isTrue);
      expect(repo.calls, isEmpty);
    });

    testWidgets('music library: no call (CA18)', (tester) async {
      final seen = <List<String>>[];
      await tester.pumpWidget(
        host(
          library: _lib('1', kind: MediaKind.artist),
          hubs: [_upstream('recent')],
          seen: seen,
          source: SeerrCatalogSource(client),
        ),
      );
      await tester.pump();
      expect(repo.calls, isEmpty);
      expect(seen.last, ['recent']);
    });

    testWidgets('pending rowFor: upstream hubs on first frame (CA17); error: no row', (tester) async {
      final seen = <List<String>>[];
      final never = Completer<ForkRecentRequestsRow?>();
      repo.handler = (_) => never.future;
      await tester.pumpWidget(
        host(library: _lib('1'), hubs: [_upstream('recent')], seen: seen, source: SeerrCatalogSource(client)),
      );
      expect(seen.first, ['recent']);
      await tester.pump(const Duration(seconds: 5));
      expect(seen.last, ['recent']);

      final failing = <List<String>>[];
      repo.handler = (_) async => throw StateError('boom');
      await tester.pumpWidget(
        host(library: _lib('2'), hubs: [_upstream('recent')], seen: failing, source: SeerrCatalogSource(client)),
      );
      await tester.pump();
      expect(failing.last, ['recent']);
    });

    testWidgets('library change clears the row at once; late answer of the old library is ignored', (tester) async {
      await withClock(Clock(() => now), () async {
        final first = _lib('1');
        final second = _lib('2');
        final source = SeerrCatalogSource(client);
        final lateAnswer = Completer<ForkRecentRequestsRow?>();
        final seen = <List<String>>[];
        final sources = _FakeSources(source);

        Widget build(MediaLibrary lib, List<MediaHub> hubs) => Provider<CatalogSourcesProvider?>.value(
          value: sources,
          child: MaterialApp(
            home: ForkRecentRequestsShelf(
              library: lib,
              hubs: hubs,
              builder: (context, hubs, fork) {
                seen.add([for (final h in hubs) h.id]);
                return const SizedBox();
              },
            ),
          ),
        );

        await tester.pumpWidget(build(first, [_upstream('recent')]));
        await tester.pump();
        expect(seen.last, contains('$kRecentRequestsHubIdPrefix${first.globalKey}'));

        repo.handler = (_) => lateAnswer.future;
        await tester.pumpWidget(build(second, [_upstream('recent')]));
        expect(seen.last, ['recent'], reason: 'previous row dropped immediately');

        // The first library's answer arrives after the switch.
        lateAnswer.complete(_row(first, now));
        await tester.pump();
        expect(seen.last, ['recent']);
        expect(repo.calls.last.globalKey, second.globalKey);
      });
    });

    testWidgets('failed refresh keeps the row; beyond 5 minutes it is dropped', (tester) async {
      await withClock(Clock(() => now), () async {
        final lib = _lib('1');
        final source = SeerrCatalogSource(client);
        final sources = _FakeSources(source);
        final seen = <List<String>>[];

        Widget build(List<MediaHub> hubs) => Provider<CatalogSourcesProvider?>.value(
          value: sources,
          child: MaterialApp(
            home: ForkRecentRequestsShelf(
              library: lib,
              hubs: hubs,
              builder: (context, hubs, fork) {
                seen.add([for (final h in hubs) h.id]);
                return const SizedBox();
              },
            ),
          ),
        );

        await tester.pumpWidget(build([_upstream('recent')]));
        await tester.pump();
        final withRow = ['$kRecentRequestsHubIdPrefix${lib.globalKey}', 'recent'];
        expect(seen.last, withRow);

        repo.handler = (_) async => null;
        now = now.add(const Duration(minutes: 2));
        await tester.pumpWidget(build([_upstream('recent')]));
        await tester.pump();
        expect(seen.last, withRow, reason: 'failed refresh keeps the displayed row');

        now = now.add(const Duration(minutes: 4));
        await tester.pumpWidget(build([_upstream('recent')]));
        await tester.pump();
        expect(seen.last, ['recent'], reason: 'last answer older than 5 minutes');
      });
    });

    test('activator: foreign hub answers false / null', () {
      final hub = _upstream('recent');
      expect(ForkRequestActivator.none.iconFor(hub), isNull);
      expect(ForkRequestActivator.none.tapFor(_FakeContext(), hub), isNull);
      expect(ForkRequestActivator.none.activate(_FakeContext(), hub, hub.items.first), false);
    });
  });

  group('ForkRecentRequestsShelf placeholder row', () {
    late _FakeSources sources;

    setUp(() => sources = _FakeSources(SeerrCatalogSource(client)));

    Future<void> clocked(Future<void> Function() body) => withClock(Clock(() => now), body);

    Widget placeholderHost({
      required MediaLibrary library,
      required List<MediaHub> hubs,
      required List<List<MediaHub>> seen,
      required _FakeSources? sources,
      OfflineModeProvider? offline,
      bool tickers = true,
    }) {
      return MultiProvider(
        providers: [
          Provider<CatalogSourcesProvider?>.value(value: sources),
          Provider<OfflineModeProvider?>.value(value: offline),
        ],
        child: MaterialApp(
          home: TickerMode(
            enabled: tickers,
            child: ForkRecentRequestsShelf(
              library: library,
              hubs: hubs,
              builder: (context, hubs, fork) {
                seen.add(List.of(hubs));
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    }

    /// Loads the memory from the (temporary) disk and stores [sizes], on the real event loop.
    Future<void> seed(WidgetTester tester, Map<MediaLibrary, int> sizes, {SeerrClient? owner}) async {
      await tester.runAsync(
        () => withClock(Clock(() => now), () async {
          await ForkRowSizeMemory.instance.ensureLoaded();
          for (final e in sizes.entries) {
            await ForkRowSizeMemory.instance.remember((owner ?? client).session, e.key, e.value);
          }
        }),
      );
    }

    /// Runs the tab's preloading line with a real context under the same providers.
    Future<void> warmUp(
      WidgetTester tester,
      MediaLibrary library, {
      required _FakeSources? sources,
      OfflineModeProvider? offline,
    }) async {
      late BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<CatalogSourcesProvider?>.value(value: sources),
            Provider<OfflineModeProvider?>.value(value: offline),
          ],
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.runAsync(() => withClock(Clock(() => now), () => forkWarmUpRecentRequestCounts(context, library)));
    }

    Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

    /// `remember` and `forget` wait on a future created outside the fake zone: let the real event loop run first.
    Future<void> settle(WidgetTester tester) => tester.runAsync(() => Future<void>.delayed(Duration.zero));

    bool isGrey(MediaHub hub) => hub.items.isNotEmpty && hub.items.every(forkIsSkeletonItem);
    MediaHub? greyHub(List<MediaHub> hubs) => hubs.where(isGrey).firstOrNull;
    String forkId(MediaLibrary lib) => '$kRecentRequestsHubIdPrefix${lib.globalKey}';
    int? sizeOf(MediaLibrary lib, [SeerrClient? owner]) =>
        ForkRowSizeMemory.instance.sizeFor((owner ?? client).session, lib);

    testWidgets('CA1: remembered size gives the grey row on the first build, at the right index', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        final pending = Completer<ForkRowResult>();
        repo.resultHandler = (_) => pending.future;

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(
            library: lib,
            hubs: [_upstream('home.continue'), _upstream('recent')],
            seen: seen,
            sources: sources,
          ),
        );
        expect([for (final h in seen.first) h.id], ['home.continue', forkId(lib), 'recent']);
        final grey = seen.first[1];
        expect(isGrey(grey), isTrue);
        expect(grey.items, hasLength(7));
        expect(grey.identifier, kRecentRequestsHubIdentifier);

        seen.clear();
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(seen.first.first.id, forkId(lib), reason: 'index 0 without Continue Watching');
        await unmount(tester);
      });
    });

    testWidgets('CA1: the grey row never has more posters than the visible cap', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 15});
        await warmUp(tester, lib, sources: sources);
        repo.resultHandler = (_) => Completer<ForkRowResult>().future;
        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(greyHub(seen.first)!.items.length, lessThan(15));
        expect(greyHub(seen.first)!.items.length, inInclusiveRange(1, 8));
        await unmount(tester);
      });
    });

    testWidgets('CA7: memory not loaded, or no size: no grey row, and none inserted later', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        final pending = Completer<ForkRowResult>();
        repo.resultHandler = (_) => pending.future;

        // Memory not loaded at the first build.
        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(seen.every((h) => greyHub(h) == null), isTrue);
        // The loading ends afterwards: still nothing grey.
        await seed(tester, {_lib('9'): 5});
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(seen.every((h) => greyHub(h) == null), isTrue);
        await unmount(tester);

        // Loaded, but no size for this library (and a zero is no size either).
        final other = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: other, sources: sources),
        );
        expect(other.every((h) => greyHub(h) == null), isTrue);
        await unmount(tester);
      });
    });

    testWidgets('CA8: no Seerr, offline or music library: no grey row and no disk access', (tester) async {
      await clocked(() async {
        final movies = _lib('1');
        final music = _lib('2', kind: MediaKind.artist);
        repo.resultHandler = (_) => Completer<ForkRowResult>().future;

        for (final (lib, src, offline) in [
          (movies, null, null),
          (movies, sources, _FakeOffline(true)),
          (music, sources, null),
        ]) {
          await warmUp(tester, lib, sources: src, offline: offline);
          expect(ForkRowSizeMemory.instance.isLoaded, isFalse, reason: 'warm-up must not read the file');
          final seen = <List<MediaHub>>[];
          await tester.pumpWidget(
            placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: src, offline: offline),
          );
          await tester.pump();
          expect(seen.every((h) => greyHub(h) == null), isTrue);
          expect(ForkRowSizeMemory.instance.isLoaded, isFalse);
          await unmount(tester);
        }
        expect(repo.calls, isEmpty);

        // Even with a loaded memory, offline and music libraries stay without grey row.
        await seed(tester, {movies: 7, music: 7});
        for (final (lib, offline) in [(movies, _FakeOffline(true)), (music, null)]) {
          final seen = <List<MediaHub>>[];
          await tester.pumpWidget(
            placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources, offline: offline),
          );
          expect(seen.every((h) => greyHub(h) == null), isTrue);
          await unmount(tester);
        }
      });
    });

    testWidgets('CA9: a recent row of the repository is shown at once, without grey row', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        repo.recent[lib.globalKey] = _row(lib, now, count: 2);
        repo.resultHandler = (_) => Completer<ForkRowResult>().future;

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(seen.first.first.id, forkId(lib));
        expect(seen.every((h) => greyHub(h) == null), isTrue);
        expect(seen.first.first.items, hasLength(2));
        await unmount(tester);
      });
    });

    testWidgets('CA3: the fresh answer replaces the grey row in place and updates the memory', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        final pending = Completer<ForkRowResult>();
        repo.resultHandler = (_) => pending.future;

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(
            library: lib,
            hubs: [_upstream('home.continue'), _upstream('recent')],
            seen: seen,
            sources: sources,
          ),
        );
        expect(isGrey(seen.last[1]), isTrue);

        pending.complete((row: _row(lib, now, count: 3), conclusive: true));
        await tester.pump();
        expect([for (final h in seen.last) h.id], ['home.continue', forkId(lib), 'recent']);
        expect(isGrey(seen.last[1]), isFalse);
        expect(seen.last[1].items, hasLength(3));
        await settle(tester);
        expect(sizeOf(lib), 3, reason: 'remember(…, 3)');

        // The timer is gone: nothing happens after 10 s.
        final builds = seen.length;
        await tester.pump(const Duration(seconds: 12));
        expect(seen.length, builds);
        await unmount(tester);
      });
    });

    testWidgets('CA5: a conclusive empty answer forgets the size and drops the row in two frames', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        final pending = Completer<ForkRowResult>();
        repo.resultHandler = (_) => pending.future;

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(greyHub(seen.last)!.items, hasLength(7));

        pending.complete(_emptyAnswer);
        await tester.pump();
        expect(greyHub(seen.last)!.items, hasLength(1), reason: 'first frame: one grey poster');
        await settle(tester);
        expect(sizeOf(lib), 0, reason: 'forget');

        await tester.pump();
        expect(seen.last.map((h) => h.id), ['recent'], reason: 'second frame: no row');
        await tester.pump(const Duration(seconds: 12));
        await unmount(tester);
      });
    });

    testWidgets('CA6: without answer the grey row is removed at 10 s, in two frames, memory kept', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        repo.resultHandler = (_) => Completer<ForkRowResult>().future;

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        await tester.pump(const Duration(milliseconds: 9999));
        expect(greyHub(seen.last)!.items, hasLength(7));

        await tester.pump(const Duration(milliseconds: 1));
        expect(greyHub(seen.last)!.items, hasLength(1));
        await tester.pump();
        expect(seen.last.map((h) => h.id), ['recent']);
        await settle(tester);
        expect(sizeOf(lib), 7, reason: 'no forget on a timeout');
        await unmount(tester);
      });
    });

    testWidgets('CA6: the 10 s run from the opening noted by the warm-up', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        repo.resultHandler = (_) => Completer<ForkRowResult>().future;
        now = now.add(const Duration(seconds: 3));

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        await tester.pump(const Duration(milliseconds: 6999));
        expect(greyHub(seen.last)!.items, hasLength(7));
        await tester.pump(const Duration(milliseconds: 1));
        expect(greyHub(seen.last)!.items, hasLength(1), reason: '7 s after the first build');
        await tester.pump();
        expect(greyHub(seen.last), isNull);
        await unmount(tester);
      });
    });

    testWidgets('CA6: a row appearing after more than 10 s gets no grey row', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        repo.resultHandler = (_) => Completer<ForkRowResult>().future;
        now = now.add(const Duration(seconds: 11));

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(seen.every((h) => greyHub(h) == null), isTrue);
        await unmount(tester);
      });
    });

    testWidgets('CA6b: after the timeout, reloaded hubs and a fresh answer show no row, but update the memory', (
      tester,
    ) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        var call = 0;
        repo.resultHandler = (library) async {
          call++;
          return call == 1 ? _inconclusive : (row: _row(library, now, count: 3), conclusive: true);
        };

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(greyHub(seen.last), isNotNull);
        await tester.pump(const Duration(seconds: 10));
        await tester.pump();
        expect(greyHub(seen.last), isNull);

        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        await tester.pump();
        expect(call, 2, reason: 'the reload asked the repository again');
        expect(seen.last.map((h) => h.id), ['recent'], reason: 'visit closed: the row is not shown');
        await settle(tester);
        expect(sizeOf(lib), 3, reason: 'the memory is still updated');
        await unmount(tester);
      });
    });

    testWidgets('CA6b: the tab hidden then visible again starts a new visit', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);
        final pending = Completer<ForkRowResult>();
        repo.resultHandler = (_) => pending.future;

        final seen = <List<MediaHub>>[];
        Widget host({required bool visible}) =>
            placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources, tickers: visible);
        await tester.pumpWidget(host(visible: true));
        await tester.pump(const Duration(seconds: 10));
        await tester.pump();
        expect(greyHub(seen.last), isNull, reason: 'visit closed');

        // Back in the foreground: grey row again, from the memory.
        await tester.pumpWidget(host(visible: false));
        await tester.pumpWidget(host(visible: true));
        await tester.pump();
        expect(greyHub(seen.last)!.items, hasLength(7));
        await tester.pump(const Duration(seconds: 10));
        await tester.pump();
        expect(greyHub(seen.last), isNull, reason: 'the new visit has its own 10 s');

        // And again, this time the repository now has a recent row (CA9).
        repo.recent[lib.globalKey] = _row(lib, now, count: 2);
        await tester.pumpWidget(host(visible: false));
        await tester.pumpWidget(host(visible: true));
        await tester.pump();
        expect(seen.last.first.id, forkId(lib));
        expect(isGrey(seen.last.first), isFalse);
        await unmount(tester);
      });
    });

    testWidgets('a late answer of the previous library is ignored (generation)', (tester) async {
      await clocked(() async {
        final first = _lib('1');
        final second = _lib('2');
        await seed(tester, {first: 7});
        await warmUp(tester, first, sources: sources);
        final late = Completer<ForkRowResult>();
        repo.resultHandler = (library) => library.id == '1' ? late.future : Completer<ForkRowResult>().future;

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: first, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(greyHub(seen.last), isNotNull);

        await tester.pumpWidget(
          placeholderHost(library: second, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(seen.last.map((h) => h.id), ['recent'], reason: 'no memory for the second library');

        late.complete((row: _row(first, now, count: 2), conclusive: true));
        await tester.pump();
        expect(seen.last.map((h) => h.id), ['recent']);
        await settle(tester);
        expect(sizeOf(first), 7, reason: 'an ignored answer does not touch the memory');
        await unmount(tester);
      });
    });

    testWidgets('the timer is cancelled on dispose and on library change', (tester) async {
      await clocked(() async {
        final first = _lib('1');
        final second = _lib('2');
        await seed(tester, {first: 7, second: 4});
        repo.resultHandler = (_) => Completer<ForkRowResult>().future;

        // Library change: the first library's timer (10 s) must not close the second library's visit (15 s).
        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: first, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpWidget(
          placeholderHost(library: second, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        expect(greyHub(seen.last)!.items, hasLength(4));
        await tester.pump(const Duration(seconds: 7));
        expect(greyHub(seen.last)!.items, hasLength(4), reason: 'second library still waiting at +7 s');
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(greyHub(seen.last), isNull, reason: 'its own 10 s are over');

        // Dispose: no timer left, no setState afterwards.
        await tester.pumpWidget(
          placeholderHost(library: first, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        await tester.pumpWidget(
          placeholderHost(library: second, hubs: [_upstream('recent')], seen: seen, sources: sources),
        );
        await unmount(tester);
        await tester.pump(const Duration(seconds: 30));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('CA13: a failure or an inconclusive answer neither remembers nor forgets', (tester) async {
      await clocked(() async {
        final lib = _lib('1');
        await seed(tester, {lib: 7});
        await warmUp(tester, lib, sources: sources);

        for (final Future<ForkRowResult> Function() answer in [
          () async => _inconclusive,
          () async => throw StateError('boom'),
        ]) {
          repo.resultHandler = (_) => answer();
          final seen = <List<MediaHub>>[];
          await tester.pumpWidget(
            placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: sources),
          );
          await tester.pump();
          await settle(tester);
          expect(sizeOf(lib), 7);
          expect(greyHub(seen.last)!.items, hasLength(7), reason: 'grey row stays until the timer');
          await unmount(tester);
        }
      });
    });

    testWidgets('CA12: a Jellyfin library with a Jellyseerr session', (tester) async {
      await clocked(() async {
        final jellyClient = _client(product: SeerrProduct.jellyseerr);
        final jellySources = _FakeSources(SeerrCatalogSource(jellyClient));
        final lib = _lib('1', kind: MediaKind.show, backend: MediaBackend.jellyfin);
        await seed(tester, {lib: 5}, owner: jellyClient);
        await warmUp(tester, lib, sources: jellySources);
        final pending = Completer<ForkRowResult>();
        repo.resultHandler = (_) => pending.future;

        final seen = <List<MediaHub>>[];
        await tester.pumpWidget(
          placeholderHost(library: lib, hubs: [_upstream('recent')], seen: seen, sources: jellySources),
        );
        final grey = greyHub(seen.last)!;
        expect(grey.items, hasLength(5));
        expect(grey.items.every((i) => i.backend == MediaBackend.jellyfin), isTrue);
        expect(grey.id, forkId(lib));

        pending.complete((row: _row(lib, now, count: 2), conclusive: true));
        await tester.pump();
        expect(seen.last.first.id, forkId(lib));
        expect(isGrey(seen.last.first), isFalse);
        await settle(tester);
        expect(sizeOf(lib, jellyClient), 2);
        await unmount(tester);
      });
    });

    test('forkSpotlightHubs drops the hubs made of grey items only', () {
      final lib = _lib('1');
      final grey = forkRecentRequestsHub(lib, forkSkeletonItems(lib, 3));
      final real = _upstream('recent');
      final empty = MediaHub(id: 'empty', title: 'Empty', type: 'movie', items: const [], size: 0);
      expect(forkSpotlightHubs([grey, real, empty]).map((h) => h.id), ['recent', 'empty']);
    });
  });

  group('TvBrowseRail with the fork hub', () {
    late HubFocusMemory focusMemory;
    final activeHubIds = <String>[];
    final activated = <String>[];
    final pushed = <Route<dynamic>>[];

    MediaHub forkHub() => MediaHub(
      id: '${kRecentRequestsHubIdPrefix}srvA:1',
      title: 'Requests',
      type: 'movie',
      items: [
        testMediaItem(id: 'tmdb-1', title: 'Requested'),
        testMediaItem(id: 'tmdb-2', title: 'Requested 2'),
      ],
      size: 2,
    );

    Widget rail(List<MediaHub> hubs) => ChangeNotifierProvider<MultiServerProvider>(
      create: (_) => testMultiServerProvider(MultiServerManager()),
      child: MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        navigatorObservers: [_PushObserver(pushed)],
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 720,
            child: TvBrowseRail(
              focusMemory: focusMemory,
              key: const ValueKey('rail'),
              hubs: hubs,
              autofocus: true,
              iconForHub: (_, _) => Icons.tv_rounded,
              onActiveHubChanged: (hub, _) => activeHubIds.add(hub.id),
              onActivateItem: (hub, item) {
                if (!hub.id.startsWith(kRecentRequestsHubIdPrefix)) return false;
                activated.add(item.id);
                return true;
              },
            ),
          ),
        ),
      ),
    );

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
    }

    setUp(() {
      focusMemory = HubFocusMemory();
      activeHubIds.clear();
      activated.clear();
      pushed.clear();
    });

    testWidgets('Down, Up, Down never loses the focus (CA14); OK activates the fork', (tester) async {
      final hubs = [_upstream('home.continue'), forkHub(), _upstream('recent')];
      await tester.pumpWidget(rail(hubs));
      await tester.pump();
      tester.state<TvBrowseRailState>(find.byType(TvBrowseRail)).requestFocus();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNotNull);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(activeHubIds.last, hubs[1].id);
      expect(FocusManager.instance.primaryFocus, isNotNull);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(activeHubIds.last, 'home.continue');
      expect(FocusManager.instance.primaryFocus, isNotNull);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(activeHubIds.last, hubs[1].id);
      expect(FocusManager.instance.primaryFocus, isNotNull);

      final routesBefore = pushed.length;
      await press(tester, LogicalKeyboardKey.select);
      expect(activated, ['tmdb-1']);
      expect(pushed.length, routesBefore, reason: 'no navigateToMediaItem for the fork hub');
    });

    testWidgets('late arrival of the row keeps the focus on the same hub', (tester) async {
      final continueHub = _upstream('home.continue');
      final third = _upstream('recent');
      await tester.pumpWidget(rail([continueHub, third]));
      await tester.pump();
      tester.state<TvBrowseRailState>(find.byType(TvBrowseRail)).requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(activeHubIds.last, 'recent');

      await tester.pumpWidget(rail([continueHub, forkHub(), third]));
      await tester.pumpAndSettle();

      expect(activeHubIds.last, 'recent');
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });
  });
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.pushed);
  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

class _FakeContext extends Fake implements BuildContext {}
