import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/recent_requests/recent_request.dart';
import 'package:plezy/fork/recent_requests/server_link.dart';
import 'package:plezy/fork/recent_requests/title_summary.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/seerr/seerr_details.dart';
import 'package:plezy/models/seerr/seerr_media.dart';
import 'package:plezy/models/seerr/seerr_request.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';

Object? fixture(String name) => jsonDecode(File('test/fork/recent_requests/fixtures/$name').readAsStringSync());

Map<String, Object?> _rawRequest(int id, Map<String, Object?> mediaExtra) => {
  'id': id,
  'status': 2,
  'type': 'movie',
  'is4k': false,
  'requestedBy': {'id': 7},
  'media': {'mediaType': 'movie', 'tmdbId': 5, 'status': 3, 'status4k': 3, ...mediaExtra},
};

void main() {
  group('download flags (CA7g)', () {
    ForkRecentRequest one(Map<String, Object?> extra) => parseRecentRequests({
      'results': [_rawRequest(1, extra)],
    }, userId: 7).single;

    test('a non-empty list means downloading', () {
      final r = one({
        'downloadStatus': [
          {'title': 'x'},
        ],
        'downloadStatus4k': [
          {'title': 'y'},
        ],
      });
      expect(r.downloading, isTrue);
      expect(r.downloading4k, isTrue);
    });

    test('empty, absent, null, object or string means not downloading', () {
      for (final value in <Object?>[
        <Object>[],
        null,
        {'a': 1},
        'x',
        3,
      ]) {
        final r = one({'downloadStatus': value, 'downloadStatus4k': value});
        expect(r.downloading, isFalse, reason: '$value');
        expect(r.downloading4k, isFalse, reason: '$value');
      }
      final absent = one({});
      expect(absent.downloading, isFalse);
      expect(absent.downloading4k, isFalse);
    });

    test('merging two requests of a title keeps the most recent values', () {
      final merged = parseRecentRequests({
        'results': [
          _rawRequest(2, {
            'downloadStatus': [1],
          }),
          _rawRequest(1, {
            'downloadStatus4k': [1],
          }),
        ],
      }, userId: 7).single;
      expect(merged.downloading, isTrue);
      expect(merged.downloading4k, isFalse);
    });
  });

  group('parseRecentRequests (Overseerr)', () {
    final json = fixture('overseerr_requests.json');
    final parsed = parseRecentRequests(json, userId: 7);

    test('keeps only the user requests, one entry per title, in received order', () {
      expect(parsed.map((r) => r.tmdbId), [11, 1399, 1400, 13, 14, 1401, 16]);
      expect(parsed.any((r) => r.tmdbId == 12), isFalse, reason: 'other user');
      expect(parsed.any((r) => r.tmdbId == 15), isFalse, reason: 'no media');
    });

    test('groups season requests and keeps the latest position', () {
      final show = parsed.firstWhere((r) => r.tmdbId == 1400);
      expect(show.kind, MediaKind.show);
      expect(show.latestRequestId, 8);
      expect(show.myRequests.map((r) => r.id), [8, 7]);
      expect(show.myRequests.first.seasons!.single.seasonNumber, 2);
      expect(show.seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(show.createdAt, DateTime.utc(2026, 11, 25, 10));
    });

    test('statuses and 4K link', () {
      final declined = parsed.firstWhere((r) => r.tmdbId == 1399);
      expect(declined.myRequests.single.status, SeerrRequestStatus.declined);
      expect(declined.mediaStatusCode, 1);
      expect(declined.tvdbId, 121361);
      expect(parsed.firstWhere((r) => r.tmdbId == 13).myRequests.single.status, SeerrRequestStatus.failed);

      final both = parsed.firstWhere((r) => r.tmdbId == 14);
      expect(both.mediaStatusCode, 5);
      expect(both.mediaStatus4kCode, 5);
      expect(both.link?.itemId, '1004');
      expect(both.link4k?.itemId, '1005');
      expect(both.link?.serverId, 'abc123machine');
      expect(both.myRequests.single.is4k, isTrue);
    });

    test('mediaInfo is rebuilt from the parsed fields', () {
      final show = parsed.firstWhere((r) => r.tmdbId == 1400);
      final info = show.mediaInfo;
      expect(info.tmdbId, 1400);
      expect(info.statusCode, 5);
      expect(info.requests, hasLength(2));
      expect(info.seasons, hasLength(2));
    });

    test('type falls back on the request type when mediaType is missing', () {
      final out = parseRecentRequests({
        'results': [
          {
            'id': 1,
            'status': 2,
            'type': 'tv',
            'requestedBy': {'id': 7},
            'media': {'tmdbId': 5, 'status': 3},
          },
        ],
      }, userId: 7);
      expect(out.single.kind, MediaKind.show);
    });

    test('malformed elements never throw', () {
      final out = parseRecentRequests({
        'results': [
          null,
          'x',
          42,
          {'id': 'a'},
          {'id': 1, 'requestedBy': 'nope', 'media': {}},
          {
            'id': 2,
            'requestedBy': {'id': 7},
            'media': {'tmdbId': 'zz', 'mediaType': 'movie'},
          },
          {
            'id': 3,
            'requestedBy': {'id': 7},
            'media': {'tmdbId': 9, 'mediaType': 'game'},
            'type': 'game',
          },
          {
            'id': 4,
            'status': 2,
            'requestedBy': {'id': 7},
            'media': {'tmdbId': 10, 'mediaType': 'movie', 'seasons': 'bad'},
            'createdAt': 12,
          },
        ],
      }, userId: 7);
      expect(out.map((r) => r.tmdbId), [10]);
      expect(out.single.createdAt, isNull);
      expect(parseRecentRequests(null, userId: 7), isEmpty);
      expect(parseRecentRequests({'results': 'x'}, userId: 7), isEmpty);
    });
  });

  group('parseRecentRequests (Seerr / Jellyseerr)', () {
    final parsed = parseRecentRequests(fixture('seerr_requests.json'), userId: 3);

    test('filters by user and groups', () {
      expect(parsed.map((r) => r.tmdbId), [21, 22, 23, 24, 26, 27]);
      expect(parsed.firstWhere((r) => r.tmdbId == 27).myRequests.map((r) => r.id), [4, 3]);
    });

    test('links in Plex and Jellyfin forms', () {
      expect(
        parsed[0].link,
        const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'abc123machine', itemId: '500'),
      );
      expect(
        parsed[1].link,
        const ForkServerLink(backend: ForkServerLinkBackend.jellyfin, serverId: 'srvJ', itemId: 'jf22'),
      );
      expect(parsed[2].link, const ForkServerLink(backend: ForkServerLinkBackend.jellyfin, itemId: 'jf23'));
      expect(parsed[3].link4k?.itemId, 'jf24k');
      expect(
        parsed.firstWhere((r) => r.tmdbId == 27).link,
        const ForkServerLink(backend: ForkServerLinkBackend.plex, itemId: '777'),
      );
      expect(parsed.firstWhere((r) => r.tmdbId == 26).link, isNull);
    });
  });

  group('ForkTitleSummary', () {
    SeerrDetails details({List<SeerrNamedValue>? keywords}) => SeerrDetails(
      id: 1396,
      title: null,
      name: 'Les Simpson',
      originalName: 'The Simpsons',
      overview: 'o',
      posterPath: '/p.jpg',
      firstAirDate: '1989-12-17',
      voteAverage: 8.0,
      keywords: keywords,
      externalIds: const SeerrExternalIds(imdbId: 'tt0096697', tvdbId: 71663),
      mediaInfo: const SeerrMediaInfo(tmdbId: 1396, statusCode: 5),
    );

    test('isAnime with the anime keyword', () {
      final s = ForkTitleSummary.fromDetails(
        details(
          keywords: [const SeerrNamedValue(id: SeerrConstants.animeKeywordId, name: 'anime')],
        ),
        MediaKind.show,
      );
      expect(s.isAnime, isTrue);
    });

    test('not anime without it (Les Simpson)', () {
      expect(
        ForkTitleSummary.fromDetails(
          details(keywords: [const SeerrNamedValue(id: 1, name: 'x')]),
          MediaKind.show,
        ).isAnime,
        isFalse,
      );
      expect(ForkTitleSummary.fromDetails(details(), MediaKind.show).isAnime, isFalse);
    });

    test('copies fields', () {
      final s = ForkTitleSummary.fromDetails(details(), MediaKind.show);
      expect(s.tmdbId, 1396);
      expect(s.name, 'Les Simpson');
      expect(s.imdbId, 'tt0096697');
      expect(s.tvdbId, 71663);
    });

    test('toDetails keeps the given mediaInfo', () {
      final s = ForkTitleSummary.fromDetails(details(), MediaKind.show);
      const info = SeerrMediaInfo(tmdbId: 1396, statusCode: 4, requests: []);
      final d = s.toDetails(info);
      expect(identical(d.mediaInfo, info), isTrue);
      expect(d.id, 1396);
      expect(d.displayTitle, 'Les Simpson');
      expect(d.externalIds?.tvdbId, 71663);
      expect(d.imdbId, 'tt0096697');
    });
  });
}
