// FORK: demandes-recentes-overseerr — tests of the recent requests row widget and its TV behaviour

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/focus/locked_hub_controller.dart';
import 'package:plezy/fork/recent_requests/recent_requests_repository.dart';
import 'package:plezy/fork/recent_requests/recent_requests_shelf.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
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
  _FakeRepo(super.client, this.handler);

  Future<ForkRecentRequestsRow?> Function(MediaLibrary library) handler;
  final List<MediaLibrary> calls = [];

  @override
  Future<ForkRecentRequestsRow?> rowFor(MediaLibrary library, ForkRowContext ctx) {
    calls.add(library);
    return handler(library);
  }
}

MediaLibrary _lib(String id, {MediaKind kind = MediaKind.movie}) =>
    MediaLibrary(id: id, backend: MediaBackend.plex, title: 'Lib $id', kind: kind, serverId: 'srvA');

MediaHub _upstream(String id) => MediaHub(
  id: id,
  title: id,
  type: 'movie',
  items: [testMediaItem(id: '$id-1', title: id)],
  size: 1,
);

ForkRecentRequestsRow _row(MediaLibrary library, DateTime fetchedAt) => ForkRecentRequestsRow(
  hub: MediaHub(
    id: '$kRecentRequestsHubIdPrefix${library.globalKey}',
    title: 'Requests',
    type: 'movie',
    items: [testMediaItem(id: 'tmdb-1', title: 'Requested')],
    size: 1,
  ),
  entriesByItemId: const {},
  fetchedAt: fetchedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SeerrClient client;
  late _FakeRepo repo;
  var now = DateTime(2026, 11, 28, 12);

  setUp(() async {
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

  tearDown(() => ForkRecentRequestsRepository.debugOverride = null);

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
