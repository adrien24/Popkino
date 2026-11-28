// FORK: demandes-recentes-overseerr — tests of the recent requests repository (real SeerrClient over a MockClient)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/fork/recent_requests/recent_request_badge.dart';
import 'package:plezy/fork/recent_requests/recent_requests_repository.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/seerr/seerr_client.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';

import '../../test_helpers/media_items.dart';

const _userId = 7;

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

String _plexUrl(String ratingKey, {String machine = 'srvA'}) =>
    'https://app.plex.tv/desktop/#!/server/$machine/details?key=%2Flibrary%2Fmetadata%2F$ratingKey';

Map<String, dynamic> _req(
  int id,
  String type,
  int tmdb, {
  int status = 2,
  int mediaStatus = 1,
  int userId = _userId,
  String? ratingKey,
  Object? downloadStatus,
}) => {
  'id': id,
  'status': status,
  'type': type,
  'is4k': false,
  'createdAt': '2026-11-27T10:00:00.000Z',
  'requestedBy': {'id': userId},
  'media': {
    'id': id + 100,
    'mediaType': type,
    'tmdbId': tmdb,
    'status': mediaStatus,
    'status4k': 1,
    'downloadStatus': ?downloadStatus,
    if (ratingKey != null) 'plexUrl': _plexUrl(ratingKey),
  },
};

/// Fake Seerr server: counts calls and tracks how many title lookups run at once.
class _Backend {
  Object requestsBody = {'results': <Object>[]};
  Future<http.Response> Function()? requestsHandler;
  Set<int> animeIds = {};
  Set<int> failingDetails = {};
  Set<int> hangingDetails = {};
  Duration detailDelay = Duration.zero;
  bool jellyseerr = false;

  int requestCalls = 0;
  final List<String> detailCalls = [];
  final List<String> detailQueries = [];
  int inFlight = 0;
  int maxInFlight = 0;

  static final _detailPath = RegExp(r'^/api/v1/(movie|tv)/(\d+)$');

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/v1/settings/public') {
      return _json({'initialized': true, if (jellyseerr) 'mediaServerType': 2});
    }
    if (path == '/api/v1/request') {
      requestCalls++;
      final handler = requestsHandler;
      if (handler != null) return handler();
      return _json(requestsBody);
    }
    final match = _detailPath.firstMatch(path);
    if (match != null) {
      final type = match.group(1)!;
      final id = int.parse(match.group(2)!);
      detailCalls.add('$type:$id');
      detailQueries.add(request.url.query);
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      try {
        if (hangingDetails.contains(id)) await Completer<void>().future;
        if (detailDelay != Duration.zero) await Future<void>.delayed(detailDelay);
        if (failingDetails.contains(id)) return _json({'message': 'boom'}, status: 500);
        return _json({
          'id': id,
          if (type == 'movie') 'title': 'Title $id' else 'name': 'Title $id',
          'keywords': animeIds.contains(id)
              ? [
                  {'id': SeerrConstants.animeKeywordId, 'name': 'anime'},
                ]
              : <Object>[],
        });
      } finally {
        inFlight--;
      }
    }
    return _json({'message': 'Not Found'}, status: 404);
  }
}

class _FakeServerClient implements MediaServerClient {
  final Map<String, MediaItem> items;
  final List<String> fetched = [];
  bool throws = false;
  Duration delay = Duration.zero;

  _FakeServerClient(this.items);

  @override
  Future<MediaItem?> fetchItem(String id) async {
    fetched.add(id);
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (throws) throw StateError('server unreachable');
    return items[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SeerrClient _client(_Backend backend, {int userId = _userId, SeerrProduct product = SeerrProduct.unknown}) =>
    SeerrClient(
      SeerrSession(
        baseUrl: 'https://seerr.example.com',
        method: SeerrAuthMethod.local,
        identifier: 'a@b.c',
        secret: 'pw',
        cookie: 'cookie',
        userId: userId,
        permissions: SeerrPermission.admin,
        displayName: 'Alice',
        instanceLabel: 'Seerr',
        product: product,
        createdAt: 0,
      ),
      onSessionInvalidated: () {},
      httpClient: MockClient((request) => backend.handle(request)),
    );

MediaLibrary _lib(String id, String title, MediaKind kind, {String serverId = 'srvA', MediaBackend? backend}) =>
    MediaLibrary(id: id, backend: backend ?? MediaBackend.plex, title: title, kind: kind, serverId: serverId);

class _Setup {
  final _Backend backend;
  final SeerrClient client;
  final ForkRecentRequestsRepository repo;
  final Map<String, _FakeServerClient> servers;
  final List<MediaLibrary> libraries;
  bool online;

  _Setup._(this.backend, this.client, this.repo, this.servers, this.libraries, this.online);

  factory _Setup({
    required List<MediaLibrary> libraries,
    Map<String, _FakeServerClient>? servers,
    bool online = true,
    _Backend? backend,
    int userId = _userId,
    SeerrProduct product = SeerrProduct.unknown,
  }) {
    final b = backend ?? _Backend();
    final client = _client(b, userId: userId, product: product);
    return _Setup._(b, client, ForkRecentRequestsRepository.of(client), servers ?? {}, libraries, online);
  }

  ForkRowContext get ctx => ForkRowContext(
    source: SeerrCatalogSource(client),
    libraries: libraries,
    clientFor: (id) => servers[id],
    isServerOnline: (_) => online,
  );

  Future<ForkRecentRequestsRow?> row(MediaLibrary library) => repo.rowFor(library, ctx);
}

List<int> _tmdbIds(ForkRecentRequestsRow row) => [
  for (final i in row.hub.items) row.entriesByItemId[i.id]!.request.tmdbId,
];

MediaItem _serverItem(String id, String libraryId) => testMediaItem(id: id, libraryId: libraryId, serverId: 'srvA');

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));
  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  final films = _lib('lib1', 'Films', MediaKind.movie);
  final shows = _lib('lib2', 'Séries', MediaKind.show);
  final animes = _lib('lib3', 'Animés', MediaKind.show);

  group('lazy and filtered', () {
    test('nothing is called until rowFor runs, and unsuitable libraries make no call', () async {
      final s = _Setup(libraries: [films]);
      expect(s.backend.requestCalls, 0);
      expect(s.backend.detailCalls, isEmpty);

      final noServer = MediaLibrary(id: 'x', backend: MediaBackend.plex, title: 'Films', kind: MediaKind.movie);
      expect(await s.row(noServer), isNull);
      expect(await s.row(_lib('m', 'Musique', MediaKind.artist)), isNull);
      expect(await s.row(_lib('p', 'Photos', MediaKind.photo)), isNull);
      expect(await s.row(_lib('u', 'Mixte', MediaKind.unknown)), isNull);
      expect(s.backend.requestCalls, 0);
      expect(s.backend.detailCalls, isEmpty);
    });

    test('an empty list gives no row', () async {
      final s = _Setup(libraries: [films]);
      expect(await s.row(films), isNull);
      expect(s.backend.requestCalls, 1);
    });
  });

  group('caching', () {
    test('Films, Séries then Animés share one /request; reopening reads no title', () async {
      final backend = _Backend()
        ..animeIds = {22}
        ..requestsBody = {
          'results': [
            _req(4, 'tv', 22, mediaStatus: 5, ratingKey: '22'),
            _req(3, 'tv', 21, mediaStatus: 5, ratingKey: '21'),
            _req(2, 'movie', 12),
            _req(1, 'movie', 11, mediaStatus: 5, ratingKey: '11'),
          ],
        };
      final server = _FakeServerClient({'22': _serverItem('22', 'lib3'), '21': _serverItem('21', 'lib2')});
      final s = _Setup(libraries: [films, shows, animes], servers: {'srvA': server}, backend: backend);

      final filmsRow = await s.row(films);
      final showsRow = await s.row(shows);
      final animeRow = await s.row(animes);

      expect(_tmdbIds(filmsRow!), [12, 11]);
      expect(_tmdbIds(showsRow!), [21]);
      expect(_tmdbIds(animeRow!), [22]);
      expect(backend.requestCalls, 1);
      expect(backend.detailCalls.toSet().length, backend.detailCalls.length, reason: 'each title read once');
      expect(server.fetched.length, lessThanOrEqualTo(2), reason: 'at most 2 fetchItem per server');
      final detailsBefore = backend.detailCalls.length;

      expect(_tmdbIds((await s.row(films))!), [12, 11]);
      expect(_tmdbIds((await s.row(shows))!), [21]);
      expect(backend.requestCalls, 1);
      expect(backend.detailCalls.length, detailsBefore);
      expect(server.fetched.length, lessThanOrEqualTo(2));
    });

    test('Films never reads a series title', () async {
      final backend = _Backend()
        ..requestsBody = {
          'results': [_req(3, 'tv', 21), _req(2, 'movie', 12), _req(1, 'movie', 11)],
        };
      final s = _Setup(libraries: [films], backend: backend);
      expect(_tmdbIds((await s.row(films))!), [12, 11]);
      expect(backend.detailCalls.where((c) => c.startsWith('tv:')), isEmpty);
    });

    test('a language change reads the titles again', () async {
      final backend = _Backend()
        ..requestsBody = {
          'results': [_req(1, 'movie', 11)],
        };
      final s = _Setup(libraries: [films], backend: backend);
      await s.row(films);
      expect(backend.detailCalls, ['movie:11']);

      await LocaleSettings.setLocale(AppLocale.fr);
      await s.row(films);
      expect(backend.detailCalls, ['movie:11', 'movie:11']);
      expect(backend.detailQueries.first, contains('language=en'));
      expect(backend.detailQueries.last, contains('language=fr'));
      expect(backend.requestCalls, 1, reason: 'the list is still fresh');
    });

    test('a new SeerrClient shares nothing with the previous one', () async {
      final backendA = _Backend()
        ..requestsBody = {
          'results': [_req(1, 'movie', 11)],
        };
      final backendB = _Backend()
        ..requestsBody = {
          'results': [_req(1, 'movie', 99, userId: 8), _req(2, 'movie', 12, userId: 8)],
        };
      final a = _Setup(libraries: [films], backend: backendA);
      final b = _Setup(libraries: [films], backend: backendB, userId: 8);

      expect(identical(ForkRecentRequestsRepository.of(a.client), a.repo), isTrue);
      expect(identical(a.repo, b.repo), isFalse);
      expect(_tmdbIds((await a.row(films))!), [11]);
      expect(_tmdbIds((await b.row(films))!), [99, 12]);
      expect(backendB.detailCalls, ['movie:99', 'movie:12']);
    });
  });

  group('limits and concurrency', () {
    test('never more than 4 title lookups in flight, even across libraries', () async {
      final backend = _Backend()
        ..detailDelay = const Duration(milliseconds: 15)
        ..requestsBody = {
          'results': [
            for (var i = 0; i < 12; i++) _req(100 + i, 'movie', 200 + i),
            for (var i = 0; i < 12; i++) _req(200 + i, 'tv', 300 + i),
          ],
        };
      final s = _Setup(libraries: [films, shows], backend: backend);
      await Future.wait([s.row(films), s.row(shows)]);
      expect(backend.maxInFlight, lessThanOrEqualTo(4));
      expect(backend.maxInFlight, greaterThan(1));
    });

    test('the row is limited to 20 titles, in the order received, and stops reading early', () async {
      final backend = _Backend()
        ..requestsBody = {
          'results': [for (var i = 0; i < 30; i++) _req(100 - i, 'movie', 1000 + i)],
        };
      final s = _Setup(libraries: [films], backend: backend);
      final row = (await s.row(films))!;
      expect(_tmdbIds(row), [for (var i = 0; i < 20; i++) 1000 + i]);
      expect(row.hub.size, 20);
      expect(backend.detailCalls.length, lessThan(30));
    });

    test('two show libraries get the same titles (CA5b)', () async {
      final shows2 = _lib('lib9', 'Séries 4K', MediaKind.show);
      final backend = _Backend()
        ..requestsBody = {
          'results': [_req(2, 'tv', 21), _req(1, 'tv', 22)],
        };
      final s = _Setup(libraries: [shows, shows2], backend: backend);
      final a = (await s.row(shows))!;
      final b = (await s.row(shows2))!;
      expect(_tmdbIds(a), [21, 22]);
      expect(_tmdbIds(b), [21, 22]);
      expect(a.hub.id, isNot(b.hub.id));
      expect(a.hub.id, startsWith(kRecentRequestsHubIdPrefix));
      expect(a.hub.identifier, kRecentRequestsHubIdentifier);
      expect(a.hub.type, 'mixed');
      expect(a.hub.serverId, isNull);
      expect(a.hub.more, isFalse);
    });

    test('a title whose lookup fails is skipped without failing the row', () async {
      final backend = _Backend()
        ..failingDetails = {12}
        ..requestsBody = {
          'results': [_req(3, 'movie', 13), _req(2, 'movie', 12), _req(1, 'movie', 11)],
        };
      final s = _Setup(libraries: [films], backend: backend);
      expect(_tmdbIds((await s.row(films))!), [13, 11]);
      // The failure is not cached: the next opening tries that title again.
      backend.failingDetails = {};
      expect(_tmdbIds((await s.row(films))!), [13, 12, 11]);
    });
  });

  group('failures', () {
    for (final entry in {
      'a non-JSON 200': () => http.Response('<html>proxy</html>', 200, headers: {'content-type': 'text/html'}),
      'a JSON array 200': () => http.Response('[]', 200, headers: {'content-type': 'application/json'}),
      'a 500': () => http.Response('{"message":"x"}', 500, headers: {'content-type': 'application/json'}),
    }.entries) {
      test('${entry.key} gives null, starts the negative cache and throws nothing', () async {
        final backend = _Backend()..requestsHandler = () async => entry.value();
        final s = _Setup(libraries: [films], backend: backend);
        expect(await s.row(films), isNull);
        expect(await s.row(films), isNull);
        expect(backend.requestCalls, 1, reason: 'negative cache');
      });
    }

    test('no answer: null after 8 s, retry blocked for 60 s, then allowed', () {
      fakeAsync((async) {
        final backend = _Backend();
        var first = true;
        backend.requestsHandler = () {
          if (first) {
            first = false;
            return Completer<http.Response>().future;
          }
          return Future.value(
            _json({
              'results': [_req(1, 'movie', 11)],
            }),
          );
        };
        final s = _Setup(libraries: [films], backend: backend);

        ForkRecentRequestsRow? result;
        var done = false;
        unawaited(
          s.row(films).then((r) {
            result = r;
            done = true;
          }),
        );
        async.elapse(const Duration(seconds: 7));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(done, isTrue);
        expect(result, isNull);
        expect(backend.requestCalls, 1);

        // Inside the 60 s negative cache: no new call.
        done = false;
        unawaited(
          s.row(films).then((r) {
            result = r;
            done = true;
          }),
        );
        async.elapse(const Duration(seconds: 30));
        expect(done, isTrue);
        expect(result, isNull);
        expect(backend.requestCalls, 1);

        // After it: a new call is made and succeeds.
        async.elapse(const Duration(seconds: 30));
        done = false;
        unawaited(
          s.row(films).then((r) {
            result = r;
            done = true;
          }),
        );
        async.elapse(const Duration(seconds: 1));
        expect(backend.requestCalls, 2);
        expect(done, isTrue);
        expect(_tmdbIds(result!), [11]);
      });
    });

    test('the 15 s budget returns the titles already retained, at least one, else null', () {
      fakeAsync((async) {
        final backend = _Backend()
          ..hangingDetails = {for (var i = 12; i < 24; i++) i}
          ..requestsBody = {
            'results': [for (var i = 11; i < 24; i++) _req(i, 'movie', i)],
          };
        final s = _Setup(libraries: [films], backend: backend);
        ForkRecentRequestsRow? result;
        var done = false;
        unawaited(
          s.row(films).then((r) {
            result = r;
            done = true;
          }),
        );
        async.elapse(const Duration(seconds: 14));
        expect(done, isFalse, reason: 'slow lookups are still pending before the budget ends');
        async.elapse(const Duration(seconds: 2));
        expect(done, isTrue);
        expect(_tmdbIds(result!), [11]);
      });
    });

    test('the 15 s budget with nothing retained gives null', () {
      fakeAsync((async) {
        final backend = _Backend()
          ..hangingDetails = {for (var i = 11; i < 24; i++) i}
          ..requestsBody = {
            'results': [for (var i = 11; i < 24; i++) _req(i, 'movie', i)],
          };
        final s = _Setup(libraries: [films], backend: backend);
        ForkRecentRequestsRow? result;
        var done = false;
        unawaited(
          s.row(films).then((r) {
            result = r;
            done = true;
          }),
        );
        async.elapse(const Duration(seconds: 16));
        expect(done, isTrue);
        expect(result, isNull);
      });
    });
  });

  group('Anime library', () {
    final backend0 = {
      'results': [
        _req(4, 'tv', 22, mediaStatus: 5, ratingKey: '22'),
        _req(3, 'tv', 21, mediaStatus: 5, ratingKey: '21'),
      ],
    };

    test('anime arrived in the Animés library: recognised, kept out of Séries', () async {
      final backend = _Backend()
        ..animeIds = {22}
        ..requestsBody = backend0;
      final server = _FakeServerClient({'22': _serverItem('22', 'lib3'), '21': _serverItem('21', 'lib2')});
      final s = _Setup(libraries: [shows, animes], servers: {'srvA': server}, backend: backend);
      expect(_tmdbIds((await s.row(shows))!), [21]);
      expect(_tmdbIds((await s.row(animes))!), [22]);
      expect(server.fetched, unorderedEquals(['22', '21']));
    });

    test('anime and non-anime arrived in the same library: rejected, falls back to the name (CA3e)', () async {
      final backend = _Backend()
        ..animeIds = {22}
        ..requestsBody = backend0;
      final server = _FakeServerClient({'22': _serverItem('22', 'lib2'), '21': _serverItem('21', 'lib2')});
      final animation = _lib('lib3', 'Animation', MediaKind.show);
      final s = _Setup(libraries: [shows, animation], servers: {'srvA': server}, backend: backend);
      expect(_tmdbIds((await s.row(shows))!), [21]);
      expect(_tmdbIds((await s.row(animation))!), [22]);
    });

    test('mixed library and no "anim" library: anime stays in Séries (CA3c)', () async {
      final backend = _Backend()
        ..animeIds = {22}
        ..requestsBody = backend0;
      final server = _FakeServerClient({'22': _serverItem('22', 'lib2'), '21': _serverItem('21', 'lib2')});
      final s = _Setup(libraries: [shows], servers: {'srvA': server}, backend: backend);
      expect(_tmdbIds((await s.row(shows))!), [22, 21]);
    });

    test('an offline server makes no fetchItem and falls back to the name', () async {
      final backend = _Backend()
        ..animeIds = {22}
        ..requestsBody = backend0;
      final server = _FakeServerClient({'22': _serverItem('22', 'lib3'), '21': _serverItem('21', 'lib2')});
      final s = _Setup(libraries: [shows, animes], servers: {'srvA': server}, backend: backend, online: false);
      expect(_tmdbIds((await s.row(animes))!), [22]);
      expect(server.fetched, isEmpty);
    });

    test('a link to another server is not asked of this one', () async {
      final backend = _Backend()
        ..animeIds = {22}
        ..requestsBody = {
          'results': [
            {
              ..._req(4, 'tv', 22, mediaStatus: 5),
              'media': {
                ...(_req(4, 'tv', 22, mediaStatus: 5)['media'] as Map<String, dynamic>),
                'plexUrl': _plexUrl('22', machine: 'otherMachine'),
              },
            },
            _req(3, 'tv', 21, mediaStatus: 5, ratingKey: '21'),
          ],
        };
      final server = _FakeServerClient({'22': _serverItem('22', 'lib3'), '21': _serverItem('21', 'lib2')});
      final s = _Setup(libraries: [shows, animes], servers: {'srvA': server}, backend: backend);
      await s.row(shows);
      expect(server.fetched, ['21']);
    });
  });

  group('Anime library lookup retry', () {
    // "Japon" has no "anim" in its name: only the vote (library of the arrived titles) can find it.
    final japon = _lib('lib3', 'Japon', MediaKind.show);
    final request = {
      'results': [
        _req(4, 'tv', 22, mediaStatus: 5, ratingKey: '22'),
        _req(3, 'tv', 21, mediaStatus: 5, ratingKey: '21'),
      ],
    };

    ({_Setup setup, _FakeServerClient server}) make({Map<String, MediaItem>? items, bool online = true}) {
      final backend = _Backend()
        ..animeIds = {22}
        ..requestsBody = request;
      final server = _FakeServerClient(items ?? {'22': _serverItem('22', 'lib3'), '21': _serverItem('21', 'lib2')});
      final setup = _Setup(libraries: [shows, japon], servers: {'srvA': server}, backend: backend, online: online);
      return (setup: setup, server: server);
    }

    ForkRecentRequestsRow? runRow(FakeAsync async, _Setup s, MediaLibrary library) {
      ForkRecentRequestsRow? result;
      unawaited(s.row(library).then((r) => result = r));
      async.elapse(const Duration(seconds: 4));
      return result;
    }

    test('offline at first: name fallback with no fetchItem, vote 61 s after back online, then memoized', () {
      fakeAsync((async) {
        final (:setup, :server) = make(online: false);
        expect(_tmdbIds(runRow(async, setup, shows)!), [22, 21], reason: 'no "anim" name, no vote: anime stays here');
        expect(server.fetched, isEmpty);

        setup.online = true;
        async.elapse(const Duration(seconds: 30));
        expect(_tmdbIds(runRow(async, setup, shows)!), [22, 21]);
        expect(server.fetched, isEmpty, reason: 'less than 60 s since the attempt: fallback reused');

        async.elapse(const Duration(seconds: 61));
        expect(_tmdbIds(runRow(async, setup, shows)!), [21]);
        expect(server.fetched, unorderedEquals(['22', '21']));
        expect(_tmdbIds(runRow(async, setup, japon)!), [22]);

        async.elapse(const Duration(seconds: 120));
        expect(_tmdbIds(runRow(async, setup, shows)!), [21]);
        expect(server.fetched.length, 2, reason: 'conclusive result is memoized');
      });
    });

    test('a failing fetchItem is not retried before 60 s, then is', () {
      fakeAsync((async) {
        final (:setup, :server) = make();
        server.throws = true;
        expect(_tmdbIds(runRow(async, setup, shows)!), [22, 21]);
        expect(server.fetched.length, 2);

        async.elapse(const Duration(seconds: 30));
        runRow(async, setup, shows);
        expect(server.fetched.length, 2, reason: '30 s later: no new call');

        server.throws = false;
        async.elapse(const Duration(seconds: 31));
        expect(_tmdbIds(runRow(async, setup, shows)!), [21]);
        expect(server.fetched.length, 4, reason: '61 s later: a new attempt');

        async.elapse(const Duration(seconds: 120));
        runRow(async, setup, shows);
        expect(server.fetched.length, 4);
      });
    });

    test('an absent item or an item without libraryId is conclusive', () {
      fakeAsync((async) {
        final (:setup, :server) = make(items: {});
        expect(_tmdbIds(runRow(async, setup, shows)!), [22, 21]);
        expect(server.fetched.length, 2);

        async.elapse(const Duration(seconds: 120));
        runRow(async, setup, shows);
        expect(server.fetched.length, 2, reason: 'memoized, never retried');
      });
    });

    test('a fetchItem slower than 2.5 s is inconclusive', () {
      fakeAsync((async) {
        final (:setup, :server) = make();
        server.delay = const Duration(seconds: 3);
        expect(_tmdbIds(runRow(async, setup, shows)!), [22, 21]);
        expect(server.fetched.length, 2);

        server.delay = Duration.zero;
        async.elapse(const Duration(seconds: 61));
        expect(_tmdbIds(runRow(async, setup, shows)!), [21]);
        expect(server.fetched.length, 4);
      });
    });

    test('concurrent rowFor calls share one lookup', () async {
      final (:setup, :server) = make();
      await Future.wait([setup.row(shows), setup.row(japon)]);
      expect(server.fetched.length, 2);
    });
  });

  group('badges', () {
    test('a declined request is "declined" (CA7b) and media status 5 is "available" (CA13)', () async {
      final backend = _Backend()
        ..requestsBody = {
          'results': [_req(2, 'movie', 12, status: 3), _req(1, 'movie', 11, mediaStatus: 5, ratingKey: '11')],
        };
      final s = _Setup(libraries: [films], backend: backend);
      final row = (await s.row(films))!;
      final byTmdb = {for (final e in row.entriesByItemId.values) e.request.tmdbId: e.catalogItem};
      expect(byTmdb[12]!.serverState?.request, CatalogRequestState.declined);
      expect(byTmdb[11]!.serverState?.availability, CatalogAvailability.available);
    });
  });

  group('row badge (T10)', () {
    test('items carry the badge key, none without a recognizable state (CA7f), entries stay intact', () async {
      final backend = _Backend()
        ..requestsBody = {
          'results': [
            _req(4, 'movie', 14, status: 2, mediaStatus: 6),
            _req(3, 'movie', 13, status: 5, mediaStatus: 1),
            _req(2, 'movie', 12, status: 2, mediaStatus: 5, ratingKey: '12'),
            _req(1, 'movie', 11, status: 3),
          ],
        };
      final s = _Setup(libraries: [films], backend: backend);
      final row = (await s.row(films))!;
      expect(row.hub.items, hasLength(4));
      final byTmdb = {for (final i in row.hub.items) row.entriesByItemId[i.id]!.request.tmdbId: i};
      expect(byTmdb[12]!.raw?[kForkRequestBadgeRawKey], ForkRequestBadge.available.name);
      expect(byTmdb[11]!.raw?[kForkRequestBadgeRawKey], ForkRequestBadge.declined.name);
      expect(byTmdb[13]!.raw?.containsKey(kForkRequestBadgeRawKey), isFalse);
      expect(row.entriesByItemId[byTmdb[12]!.id]!.catalogItem.serverState?.availability, CatalogAvailability.available);
      expect(row.entriesByItemId[byTmdb[11]!.id]!.catalogItem.serverState?.request, CatalogRequestState.declined);
      expect(row.entriesByItemId[byTmdb[13]!.id]!.catalogItem.serverState?.request, isNull);
    });

    test('status 3 is "requested" without a download and "processing" with one (CA7g)', () async {
      final backend = _Backend()
        ..requestsBody = {
          'results': [
            _req(
              2,
              'movie',
              12,
              mediaStatus: 3,
              downloadStatus: [
                {'title': 'x'},
              ],
            ),
            _req(1, 'movie', 11, mediaStatus: 3, downloadStatus: <Object>[]),
          ],
        };
      final s = _Setup(libraries: [films], backend: backend);
      final row = (await s.row(films))!;
      final byTmdb = {for (final i in row.hub.items) row.entriesByItemId[i.id]!.request.tmdbId: i};
      expect(byTmdb[11]!.raw?[kForkRequestBadgeRawKey], 'requested');
      expect(byTmdb[12]!.raw?[kForkRequestBadgeRawKey], 'processing');
    });

    test('Overseerr code 6 with an approved request is "deleted"', () async {
      final backend = _Backend()
        ..requestsBody = {
          'results': [_req(1, 'movie', 11, status: 2, mediaStatus: 6)],
        };
      backend.jellyseerr = false;
      final s = _Setup(libraries: [films], backend: backend, product: SeerrProduct.overseerr);
      final row = (await s.row(films))!;
      expect(row.hub.items.single.raw?[kForkRequestBadgeRawKey], ForkRequestBadge.deleted.name);
    });
  });

  group('Overseerr and Seerr fixtures (CA19)', () {
    Object fixture(String name) =>
        jsonDecode(File('test/fork/recent_requests/fixtures/$name').readAsStringSync()) as Object;

    test('Overseerr fixture: the user\'s series, one entry per title', () async {
      final backend = _Backend()..requestsBody = fixture('overseerr_requests.json');
      final s = _Setup(libraries: [shows], backend: backend);
      expect(_tmdbIds((await s.row(shows))!), [1399, 1400, 1401]);
    });

    test('Seerr/Jellyfin fixture is treated the same way', () async {
      final backend = _Backend()
        ..jellyseerr = true
        ..requestsBody = fixture('seerr_requests.json');
      final jelly = _lib('jf1', 'Shows', MediaKind.show, serverId: 'srvJ', backend: MediaBackend.jellyfin);
      final s = _Setup(libraries: [jelly], backend: backend, userId: 3);
      final row = (await s.row(jelly))!;
      expect(_tmdbIds(row), [22, 24, 27]);
      expect(row.hub.id, '$kRecentRequestsHubIdPrefix${jelly.globalKey}');
    });
  });
}
