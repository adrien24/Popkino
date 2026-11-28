// FORK: demandes-recentes-overseerr — server title link carried by an Overseerr/Seerr media object
//
// Pure parsing of the link Overseerr (`plexUrl`) or Seerr/Jellyseerr (`mediaUrl`) gives for a title already on the
// media server, with `ratingKey` / `jellyfinMediaId` as last resorts. See `docs/technique/demandes-recentes-overseerr/plan.md`.

enum ForkServerLinkBackend { plex, jellyfin }

class ForkServerLink {
  final ForkServerLinkBackend backend;

  /// Plex `machineIdentifier` or Jellyfin server id; null when the link only carries an item id.
  final String? serverId;
  final String itemId;

  const ForkServerLink({required this.backend, this.serverId, required this.itemId});

  @override
  bool operator ==(Object other) =>
      other is ForkServerLink && other.backend == backend && other.serverId == serverId && other.itemId == itemId;

  @override
  int get hashCode => Object.hash(backend, serverId, itemId);

  @override
  String toString() => 'ForkServerLink($backend, $serverId, $itemId)';
}

final _plexServerPath = RegExp(r'/server/([^/?#]+)/details\?(.*)$');
final _plexRatingKey = RegExp(r'/library/metadata/([^/?#&]+)');

/// Reads the server title link from a Seerr `MediaInfo` JSON object; null when nothing usable is present.
ForkServerLink? parseServerLink(Map<String, dynamic> media, {bool is4k = false}) {
  final suffix = is4k ? '4k' : '';

  final plexUrl = _string(media['plexUrl$suffix']);
  if (plexUrl != null) {
    final link = _fromUrl(plexUrl);
    if (link != null) return link;
  }

  final mediaUrl = _string(media['mediaUrl$suffix']);
  if (mediaUrl != null) {
    final link = _fromUrl(mediaUrl);
    if (link != null) return link;
  }

  final ratingKey = _string(media['ratingKey$suffix']);
  if (ratingKey != null) return ForkServerLink(backend: ForkServerLinkBackend.plex, itemId: ratingKey);

  final jellyfinId = _string(media['jellyfinMediaId$suffix']);
  if (jellyfinId != null) return ForkServerLink(backend: ForkServerLinkBackend.jellyfin, itemId: jellyfinId);

  return null;
}

String? _string(Object? v) {
  if (v is String) return v.trim().isEmpty ? null : v.trim();
  if (v is num) return v.toString();
  return null;
}

String _decode(String s) {
  try {
    return Uri.decodeComponent(s);
  } on ArgumentError {
    return s;
  }
}

ForkServerLink? _fromUrl(String url) {
  // Plex web: `…#!/server/<machineId>/details?key=%2Flibrary%2Fmetadata%2F<ratingKey>`.
  final plex = _plexServerPath.firstMatch(url);
  if (plex != null) {
    final params = _query(plex.group(2)!);
    final key = params['key'];
    final rating = key == null ? null : _plexRatingKey.firstMatch(_decode(key));
    if (rating != null) {
      return ForkServerLink(
        backend: ForkServerLinkBackend.plex,
        serverId: _decode(plex.group(1)!),
        itemId: rating.group(1)!,
      );
    }
  }

  // Jellyfin web: `…#!/details?id=<id>&context=home&serverId=<serverId>`.
  final detailsAt = url.indexOf('details?');
  if (detailsAt >= 0) {
    final params = _query(url.substring(detailsAt + 'details?'.length));
    final id = params['id'];
    if (id != null && id.isNotEmpty) {
      final serverId = params['serverId'];
      return ForkServerLink(
        backend: ForkServerLinkBackend.jellyfin,
        serverId: serverId == null || serverId.isEmpty ? null : serverId,
        itemId: id,
      );
    }
  }
  return null;
}

Map<String, String> _query(String q) {
  final out = <String, String>{};
  for (final part in q.split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    out.putIfAbsent(_decode(part.substring(0, eq)), () => part.substring(eq + 1));
  }
  return out;
}
