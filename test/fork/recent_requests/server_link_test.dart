import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/recent_requests/server_link.dart';

void main() {
  group('parseServerLink', () {
    test('Overseerr plexUrl, encoded key', () {
      final link = parseServerLink({
        'plexUrl': 'https://app.plex.tv/desktop/#!/server/abc123/details?key=%2Flibrary%2Fmetadata%2F1001',
        'ratingKey': '999',
      });
      expect(link, const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'abc123', itemId: '1001'));
    });

    test('plexUrl with a plain slash key', () {
      final link = parseServerLink({
        'plexUrl': 'https://app.plex.tv/desktop#!/server/abc123/details?key=/library/metadata/42',
      });
      expect(link, const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'abc123', itemId: '42'));
    });

    test('plexUrl4k only with is4k', () {
      final media = {
        'plexUrl': 'https://app.plex.tv/desktop#!/server/s/details?key=%2Flibrary%2Fmetadata%2F1',
        'plexUrl4k': 'https://app.plex.tv/desktop#!/server/s/details?key=%2Flibrary%2Fmetadata%2F2',
      };
      expect(parseServerLink(media)?.itemId, '1');
      expect(parseServerLink(media, is4k: true)?.itemId, '2');
      expect(parseServerLink({'plexUrl': media['plexUrl']}, is4k: true), isNull);
    });

    test('Seerr mediaUrl, Plex form', () {
      final link = parseServerLink({
        'mediaUrl': 'https://app.plex.tv/desktop#!/server/m1/details?key=%2Flibrary%2Fmetadata%2F500',
      });
      expect(link, const ForkServerLink(backend: ForkServerLinkBackend.plex, serverId: 'm1', itemId: '500'));
    });

    test('Seerr mediaUrl, Jellyfin form', () {
      final link = parseServerLink({
        'mediaUrl': 'http://jf.local:8096/web/index.html#!/details?id=jf22&context=home&serverId=srvJ',
      });
      expect(link, const ForkServerLink(backend: ForkServerLinkBackend.jellyfin, serverId: 'srvJ', itemId: 'jf22'));
    });

    test('ratingKey alone, string or number', () {
      expect(
        parseServerLink({'ratingKey': '777'}),
        const ForkServerLink(backend: ForkServerLinkBackend.plex, itemId: '777'),
      );
      expect(parseServerLink({'ratingKey': 778})?.itemId, '778');
      expect(parseServerLink({'ratingKey4k': '5'}, is4k: true)?.itemId, '5');
    });

    test('jellyfinMediaId alone', () {
      expect(
        parseServerLink({'jellyfinMediaId': 'jf23'}),
        const ForkServerLink(backend: ForkServerLinkBackend.jellyfin, itemId: 'jf23'),
      );
      expect(parseServerLink({'jellyfinMediaId4k': 'k'}, is4k: true)?.itemId, 'k');
    });

    test('nothing usable gives null', () {
      expect(parseServerLink({}), isNull);
      expect(parseServerLink({'plexUrl': 'https://example.com', 'ratingKey': ''}), isNull);
      expect(parseServerLink({'plexUrl': null}), isNull);
    });
  });
}
