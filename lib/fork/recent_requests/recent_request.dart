// FORK: demandes-recentes-overseerr — the user's recent Overseerr/Seerr requests, read from the raw JSON
//
// `GET /request` carries fields the shared Seerr models omit (`createdAt`, `plexUrl`, `mediaUrl`, `ratingKey`…), so
// the list is parsed here. See `docs/technique/demandes-recentes-overseerr/plan.md`.

import '../../media/media_kind.dart';
import '../../models/seerr/seerr_media.dart';
import '../../models/seerr/seerr_request.dart';
import 'server_link.dart';

class ForkRecentRequest {
  final int latestRequestId;
  final DateTime? createdAt;
  final MediaKind kind;
  final int tmdbId;
  final int? tvdbId;
  final int? mediaStatusCode;
  final int? mediaStatus4kCode;

  /// Seerr's `media.downloadStatus` / `downloadStatus4k` hold a non-empty list: a real download is running.
  final bool downloading;
  final bool downloading4k;
  final List<SeerrSeasonInfo> seasons;

  /// The user's own requests for this title, most recent first.
  final List<SeerrRequest> myRequests;
  final ForkServerLink? link;
  final ForkServerLink? link4k;

  const ForkRecentRequest({
    required this.latestRequestId,
    this.createdAt,
    required this.kind,
    required this.tmdbId,
    this.tvdbId,
    this.mediaStatusCode,
    this.mediaStatus4kCode,
    this.downloading = false,
    this.downloading4k = false,
    this.seasons = const [],
    this.myRequests = const [],
    this.link,
    this.link4k,
  });

  SeerrMediaInfo get mediaInfo => SeerrMediaInfo(
    tmdbId: tmdbId,
    tvdbId: tvdbId,
    statusCode: mediaStatusCode,
    status4kCode: mediaStatus4kCode,
    seasons: seasons,
    requests: myRequests,
  );
}

/// Parses a `GET /request` page, keeping the requests made by [userId], one entry per title, most recent first.
/// Malformed elements are skipped, never thrown.
List<ForkRecentRequest> parseRecentRequests(Object? json, {required int userId}) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return const [];

  final order = <(MediaKind, int)>[];
  final byTitle = <(MediaKind, int), ForkRecentRequest>{};

  for (final raw in results) {
    try {
      final parsed = _parseOne(raw, userId);
      if (parsed == null) continue;
      final key = (parsed.kind, parsed.tmdbId);
      final existing = byTitle[key];
      if (existing == null) {
        order.add(key);
        byTitle[key] = parsed;
      } else {
        byTitle[key] = ForkRecentRequest(
          latestRequestId: existing.latestRequestId,
          createdAt: existing.createdAt,
          kind: existing.kind,
          tmdbId: existing.tmdbId,
          tvdbId: existing.tvdbId ?? parsed.tvdbId,
          mediaStatusCode: existing.mediaStatusCode,
          mediaStatus4kCode: existing.mediaStatus4kCode,
          downloading: existing.downloading,
          downloading4k: existing.downloading4k,
          seasons: existing.seasons.isNotEmpty ? existing.seasons : parsed.seasons,
          myRequests: [...existing.myRequests, ...parsed.myRequests],
          link: existing.link ?? parsed.link,
          link4k: existing.link4k ?? parsed.link4k,
        );
      }
    } catch (_) {
      continue;
    }
  }
  return [for (final k in order) byTitle[k]!];
}

ForkRecentRequest? _parseOne(Object? raw, int userId) {
  if (raw is! Map) return null;
  final requestedBy = raw['requestedBy'];
  if (requestedBy is! Map || _int(requestedBy['id']) != userId) return null;
  final media = raw['media'];
  if (media is! Map) return null;
  final tmdbId = _int(media['tmdbId']);
  if (tmdbId == null) return null;
  final id = _int(raw['id']);
  if (id == null) return null;

  final kind = _kindOf(media['mediaType']) ?? _kindOf(raw['type']);
  if (kind == null) return null;
  return _build(raw, media, id, tmdbId, kind);
}

MediaKind? _kindOf(Object? type) => switch (type) {
  'movie' => MediaKind.movie,
  'tv' => MediaKind.show,
  _ => null,
};

ForkRecentRequest _build(Map raw, Map media, int id, int tmdbId, MediaKind kind) {
  final mediaJson = media.cast<String, dynamic>();
  final seasons = <SeerrSeasonInfo>[];
  final rawSeasons = media['seasons'];
  if (rawSeasons is List) {
    for (final s in rawSeasons) {
      if (s is Map && _int(s['seasonNumber']) != null) {
        seasons.add(
          SeerrSeasonInfo(
            seasonNumber: _int(s['seasonNumber'])!,
            statusCode: _int(s['status']),
            status4kCode: _int(s['status4k']),
          ),
        );
      }
    }
  }
  final requestSeasons = <SeerrRequestSeason>[];
  final rawRequestSeasons = raw['seasons'];
  if (rawRequestSeasons is List) {
    for (final s in rawRequestSeasons) {
      final n = s is Map ? _int(s['seasonNumber']) : null;
      if (n != null) requestSeasons.add(SeerrRequestSeason(seasonNumber: n));
    }
  }
  return ForkRecentRequest(
    latestRequestId: id,
    createdAt: raw['createdAt'] is String ? DateTime.tryParse(raw['createdAt'] as String) : null,
    kind: kind,
    tmdbId: tmdbId,
    tvdbId: _int(media['tvdbId']),
    mediaStatusCode: _int(media['status']),
    mediaStatus4kCode: _int(media['status4k']),
    downloading: _nonEmptyList(media['downloadStatus']),
    downloading4k: _nonEmptyList(media['downloadStatus4k']),
    seasons: seasons,
    myRequests: [
      SeerrRequest(
        id: id,
        status: SeerrRequestStatus.fromCode(_int(raw['status'])),
        is4k: raw['is4k'] is bool ? raw['is4k'] as bool : null,
        seasons: requestSeasons.isEmpty ? null : requestSeasons,
      ),
    ],
    link: parseServerLink(mediaJson),
    link4k: parseServerLink(mediaJson, is4k: true),
  );
}

bool _nonEmptyList(Object? v) => v is List && v.isNotEmpty;

int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
