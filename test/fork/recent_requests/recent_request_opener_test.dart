// FORK: demandes-recentes-overseerr — tests for resolving and opening a recent request
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/recent_requests/recent_request.dart';
import 'package:plezy/fork/recent_requests/recent_request_opener.dart';
import 'package:plezy/fork/recent_requests/server_link.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/media_items.dart';

class _FakeClient implements MediaServerClient {
  final Map<String, MediaItem> items;
  final int tmdb;
  final Duration delay;
  final List<String> fetched = [];

  _FakeClient({this.items = const {}, this.tmdb = 42, this.delay = Duration.zero});

  @override
  Future<MediaItem?> fetchItem(String id) async {
    fetched.add(id);
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    return items[id];
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ExternalIds(tmdb: tmdb);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _library = MediaLibrary(
  id: 'lib1',
  backend: MediaBackend.plex,
  title: 'Series',
  kind: MediaKind.show,
  serverId: 'srvA',
);
const _catalogItem = CatalogItem(
  source: CatalogSourceId.seerr,
  kind: MediaKind.show,
  title: 'Show',
  ids: CatalogItemIds(tmdb: 42),
);

ForkRecentRequest _request({ForkServerLink? link, MediaKind kind = MediaKind.show, int tmdbId = 42}) =>
    ForkRecentRequest(latestRequestId: 1, kind: kind, tmdbId: tmdbId, mediaStatusCode: 5, link: link);

MediaItem _item(String id, {MediaKind kind = MediaKind.show, String? serverId, String? libraryId}) =>
    testMediaItem(id: id, kind: kind, serverId: serverId, libraryId: libraryId);

void main() {
  group('resolveServerItem', () {
    test('plexUrl link with an online server returns the item', () async {
      final client = _FakeClient(items: {'10': _item('10')});
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'srvA', itemId: '10'),
        ),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (_) => client,
        isServerOnline: (_) => true,
      );
      expect(result?.id, '10');
    });

    test('offline server: null and no fetchItem', () async {
      final client = _FakeClient(items: {'10': _item('10')});
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'srvA', itemId: '10'),
        ),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (_) => client,
        isServerOnline: (_) => false,
      );
      expect(result, isNull);
      expect(client.fetched, isEmpty);
    });

    test('bare ratingKey with a wrong tmdbId is rejected', () async {
      final client = _FakeClient(items: {'10': _item('10')}, tmdb: 999);
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.plex, itemId: '10'),
        ),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (_) => client,
        isServerOnline: (_) => true,
      );
      expect(result, isNull);
    });

    test('bare ratingKey with the right tmdbId is accepted', () async {
      final client = _FakeClient(items: {'10': _item('10')});
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.plex, itemId: '10'),
        ),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (_) => client,
        isServerOnline: (_) => true,
      );
      expect(result?.id, '10');
    });

    test('Jellyfin link is resolved like a Plex one', () async {
      final client = _FakeClient(items: {'jf-1': _item('jf-1')});
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.jellyfin, serverId: 'jfSrv', itemId: 'jf-1'),
        ),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (id) => id == 'jfSrv' ? client : null,
        isServerOnline: (_) => true,
      );
      expect(result?.id, 'jf-1');
    });

    test('item of the wrong kind is rejected', () async {
      final client = _FakeClient(items: {'10': _item('10', kind: MediaKind.movie)});
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'srvA', itemId: '10'),
        ),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (_) => client,
        isServerOnline: (_) => true,
      );
      expect(result, isNull);
    });

    test('not available: null without any call', () async {
      final client = _FakeClient(items: {'10': _item('10')});
      var matched = 0;
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'srvA', itemId: '10'),
        ),
        item: _catalogItem,
        isAvailable: false,
        library: _library,
        clientFor: (_) => client,
        isServerOnline: (_) => true,
        matchLibraries: (_) async {
          matched++;
          return [_item('x')];
        },
      );
      expect(result, isNull);
      expect(client.fetched, isEmpty);
      expect(matched, 0);
    });

    test('budget exceeded returns null', () {
      fakeAsync((async) {
        final client = _FakeClient(items: {'10': _item('10')}, delay: const Duration(seconds: 10));
        MediaItem? result = _item('sentinel');
        var done = false;
        resolveServerItem(
          request: _request(
            link: const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'srvA', itemId: '10'),
          ),
          item: _catalogItem,
          isAvailable: true,
          library: _library,
          clientFor: (_) => client,
          isServerOnline: (_) => true,
        ).then((v) {
          result = v;
          done = true;
        });
        async.elapse(const Duration(milliseconds: 2400));
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 200));
        expect(done, isTrue);
        expect(result, isNull);
      });
    });

    test('an exception yields null', () async {
      final result = await resolveServerItem(
        request: _request(
          link: const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'srvA', itemId: '10'),
        ),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (_) => throw StateError('boom'),
        isServerOnline: (_) => true,
      );
      expect(result, isNull);
    });

    group('library matcher fallback', () {
      Future<MediaItem?> run(List<MediaItem> copies) => resolveServerItem(
        request: _request(),
        item: _catalogItem,
        isAvailable: true,
        library: _library,
        clientFor: (_) => null,
        isServerOnline: (_) => true,
        matchLibraries: (_) async => copies,
      );

      test('prefers same server and same library', () async {
        final r = await run([
          _item('a', serverId: 'srvB', libraryId: 'lib1'),
          _item('b', serverId: 'srvA', libraryId: 'other'),
          _item('c', serverId: 'srvA', libraryId: 'lib1'),
        ]);
        expect(r?.id, 'c');
      });

      test('then same server', () async {
        final r = await run([
          _item('a', serverId: 'srvB', libraryId: 'lib1'),
          _item('b', serverId: 'srvA', libraryId: 'other'),
        ]);
        expect(r?.id, 'b');
      });

      test('then the first one', () async {
        final r = await run([_item('a', serverId: 'srvB'), _item('b', serverId: 'srvC')]);
        expect(r?.id, 'a');
      });

      test('no copy: null', () async {
        expect(await run(const []), isNull);
      });
    });
  });

  group('openRecentRequest', () {
    Widget host(void Function(BuildContext) onReady) => MaterialApp(
      home: Builder(
        builder: (context) => TextButton(onPressed: () => onReady(context), child: const Text('go')),
      ),
    );

    testWidgets('opens the server item when found', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        host((context) {
          openRecentRequest(
            context,
            _request(),
            _catalogItem,
            _library,
            resolver: () async => _item('srv-item'),
            openServerItem: (_, i) async => opened.add('server:${i.id}'),
            openCatalog: (_, i) async => opened.add('catalog:${i.title}'),
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(opened, ['server:srv-item']);
    });

    testWidgets('falls back to Explorer when nothing is found', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        host((context) {
          openRecentRequest(
            context,
            _request(),
            _catalogItem,
            _library,
            resolver: () async => null,
            openServerItem: (_, i) async => opened.add('server:${i.id}'),
            openCatalog: (_, i) async => opened.add('catalog:${i.title}'),
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(opened, ['catalog:Show']);
    });

    testWidgets('spinner after 300 ms, second OK ignored, spinner removed', (tester) async {
      final completer = Completer<MediaItem?>();
      var resolverCalls = 0;
      final opened = <String>[];
      await tester.pumpWidget(
        host((context) {
          openRecentRequest(
            context,
            _request(),
            _catalogItem,
            _library,
            resolver: () {
              resolverCalls++;
              return completer.future;
            },
            openServerItem: (_, i) async => opened.add('server:${i.id}'),
            openCatalog: (_, i) async => opened.add('catalog'),
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('go'), warnIfMissed: false);
      expect(resolverCalls, 1);

      completer.complete(_item('x'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(opened, ['server:x']);
    });
  });
}
