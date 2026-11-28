// FORK: demandes-recentes-overseerr — tests for the Seerr hooks used by the recent requests shelf.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/models/seerr/seerr_details.dart';
import 'package:plezy/models/seerr/seerr_media.dart';
import 'package:plezy/models/seerr/seerr_request.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/seerr/seerr_auth_service.dart';
import 'package:plezy/services/seerr/seerr_client.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';

SeerrSession _session() => const SeerrSession(
  baseUrl: 'https://seerr.example.com',
  method: SeerrAuthMethod.jellyfin,
  identifier: 'alice',
  secret: 'hunter2',
  cookie: 'old-cookie',
  userId: 7,
  permissions: 2,
  displayName: 'Alice',
  instanceLabel: 'Seerr',
  product: SeerrProduct.unknown,
  createdAt: 0,
);

http.Response _json(Object body, {int status = 200, Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...?headers});

http.Response _sessionGone() =>
    _json({'status': 403, 'error': 'You do not have permission to access this endpoint'}, status: 403);

Map<String, dynamic> _user() => {'id': 7, 'displayName': 'Alice', 'permissions': 2, 'avatar': '/a.png'};

void main() {
  group('SeerrClient.getRequestsJson', () {
    test('requests the raw page on /api/v1/request with the expected query, and no filter', () async {
      late Uri seen;
      final mock = MockClient((request) async {
        seen = request.url;
        return _json({'pageInfo': {}, 'results': []});
      });
      final client = SeerrClient(
        _session(),
        onSessionInvalidated: () => fail('must not invalidate'),
        authService: SeerrAuthService(httpClientFactory: () => mock),
        httpClient: mock,
      );
      addTearDown(client.dispose);

      final json = await client.getRequestsJson(take: 100, requestedBy: 7);
      expect(json, containsPair('results', <dynamic>[]));
      expect(seen.path, '/api/v1/request');
      expect(seen.queryParameters, {'take': '100', 'skip': '0', 'sort': 'added', 'requestedBy': '7'});
      expect(seen.queryParameters.containsKey('filter'), isFalse);
    });

    test('a Seerr 403 on the request list triggers one re-login, then a retry', () async {
      var listCalls = 0;
      var loginCalls = 0;
      final mock = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/jellyfin') {
          loginCalls++;
          return _json(_user(), headers: {'set-cookie': '${SeerrConstants.sessionCookieName}=fresh'});
        }
        if (request.url.path == '/api/v1/auth/me') {
          return request.headers['Cookie'] == '${SeerrConstants.sessionCookieName}=fresh'
              ? _json(_user())
              : _sessionGone();
        }
        expect(request.url.path, '/api/v1/request');
        listCalls++;
        if (request.headers['Cookie'] != '${SeerrConstants.sessionCookieName}=fresh') return _sessionGone();
        return _json({'results': []});
      });
      final client = SeerrClient(
        _session(),
        onSessionInvalidated: () => fail('must not invalidate'),
        authService: SeerrAuthService(httpClientFactory: () => mock),
        httpClient: mock,
      );
      addTearDown(client.dispose);

      await client.getRequestsJson(take: 100, requestedBy: 7);
      expect(loginCalls, 1);
      expect(listCalls, 2, reason: 'the rejected call and the retry');
    });
  });

  group('SeerrCatalogSource.catalogItemFromDetailsForFork', () {
    test('a declined request yields serverState.request == declined', () async {
      final mock = MockClient((request) async => _json({'message': 'Not Found'}, status: 404));
      final client = SeerrClient(
        _session(),
        onSessionInvalidated: () => fail('must not invalidate'),
        authService: SeerrAuthService(httpClientFactory: () => mock),
        httpClient: mock,
      );
      addTearDown(client.dispose);
      final source = SeerrCatalogSource(client);

      final item = await source.catalogItemFromDetailsForFork(
        const SeerrDetails(
          id: 42,
          title: 'Declined',
          mediaInfo: SeerrMediaInfo(
            tmdbId: 42,
            statusCode: 1,
            requests: [SeerrRequest(id: 1, status: SeerrRequestStatus.declined)],
          ),
        ),
        MediaKind.movie,
      );
      expect(item.serverState?.request, CatalogRequestState.declined);
    });

    test('media status 5 yields availability available', () async {
      final mock = MockClient((request) async => _json({'message': 'Not Found'}, status: 404));
      final client = SeerrClient(
        _session(),
        onSessionInvalidated: () => fail('must not invalidate'),
        authService: SeerrAuthService(httpClientFactory: () => mock),
        httpClient: mock,
      );
      addTearDown(client.dispose);
      final source = SeerrCatalogSource(client);

      final item = await source.catalogItemFromDetailsForFork(
        const SeerrDetails(id: 43, title: 'Available', mediaInfo: SeerrMediaInfo(tmdbId: 43, statusCode: 5)),
        MediaKind.movie,
      );
      expect(item.serverState?.availability, CatalogAvailability.available);
    });
  });

  test('the two FORK hooks are present in their upstream files', () {
    const marker = 'FORK: demandes-recentes-overseerr';
    final clientSrc = File('lib/services/seerr/seerr_client.dart').readAsStringSync();
    final sourceSrc = File('lib/services/catalog/seerr_catalog_source.dart').readAsStringSync();
    expect(clientSrc, contains(marker));
    expect(clientSrc, contains('getRequestsJson'));
    expect(sourceSrc, contains(marker));
    expect(sourceSrc, contains('catalogItemFromDetailsForFork'));
  });
}
