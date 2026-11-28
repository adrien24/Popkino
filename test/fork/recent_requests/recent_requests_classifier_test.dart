// FORK: demandes-recentes-overseerr — tests of the shelf classifier
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/recent_requests/recent_requests_classifier.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';

MediaLibrary lib(String id, String title, MediaKind kind, {String serverId = 's1'}) =>
    MediaLibrary(id: id, backend: MediaBackend.plex, title: title, kind: kind, serverId: serverId);

void main() {
  group('shelfForLibrary', () {
    test('maps kinds and rejects others', () {
      expect(shelfForLibrary(lib('1', 'Films', MediaKind.movie), animeLibraryGlobalKey: null), ForkRequestShelf.movies);
      expect(shelfForLibrary(lib('2', 'Séries', MediaKind.show), animeLibraryGlobalKey: null), ForkRequestShelf.shows);
      expect(shelfForLibrary(lib('3', 'Musique', MediaKind.artist), animeLibraryGlobalKey: null), isNull);
      expect(shelfForLibrary(lib('4', 'Photos', MediaKind.photo), animeLibraryGlobalKey: null), isNull);
      expect(shelfForLibrary(lib('5', 'Mixte', MediaKind.unknown), animeLibraryGlobalKey: null), isNull);
    });

    test('Anime library wins over its kind', () {
      final anime = lib('6', 'Animés', MediaKind.show);
      expect(shelfForLibrary(anime, animeLibraryGlobalKey: anime.globalKey), ForkRequestShelf.anime);
      expect(
        shelfForLibrary(lib('2', 'Séries', MediaKind.show), animeLibraryGlobalKey: anime.globalKey),
        ForkRequestShelf.shows,
      );
    });
  });

  group('belongsTo', () {
    test('Ghibli movie goes to Anime when a library exists, else Movies', () {
      expect(belongsTo(ForkRequestShelf.anime, MediaKind.movie, true, serverHasAnimeLibrary: true), isTrue);
      expect(belongsTo(ForkRequestShelf.movies, MediaKind.movie, true, serverHasAnimeLibrary: true), isFalse);
      expect(belongsTo(ForkRequestShelf.anime, MediaKind.movie, true, serverHasAnimeLibrary: false), isFalse);
      expect(belongsTo(ForkRequestShelf.movies, MediaKind.movie, true, serverHasAnimeLibrary: false), isTrue);
    });

    test('anime show and non-anime show', () {
      expect(belongsTo(ForkRequestShelf.anime, MediaKind.show, true, serverHasAnimeLibrary: true), isTrue);
      expect(belongsTo(ForkRequestShelf.shows, MediaKind.show, true, serverHasAnimeLibrary: true), isFalse);
      expect(belongsTo(ForkRequestShelf.shows, MediaKind.show, false, serverHasAnimeLibrary: true), isTrue);
      expect(belongsTo(ForkRequestShelf.anime, MediaKind.show, false, serverHasAnimeLibrary: true), isFalse);
      expect(belongsTo(ForkRequestShelf.shows, MediaKind.movie, false, serverHasAnimeLibrary: true), isFalse);
    });
  });

  group('decideAnimeLibrary', () {
    final movies = lib('1', 'Films', MediaKind.movie);
    final shows = lib('2', 'Séries', MediaKind.show);
    final music = lib('9', 'Anime music', MediaKind.artist);

    test('arrived anime library is chosen', () {
      final anime = lib('3', 'Japon', MediaKind.show);
      expect(
        decideAnimeLibrary(
          serverLibraries: [movies, shows, anime],
          arrivedAnimeLibraryId: '3',
          arrivedNonAnimeSameKindLibraryId: '2',
        ),
        anime.globalKey,
      );
    });

    test('mixed library is rejected, then name applies, then null', () {
      final named = lib('4', 'Animés', MediaKind.show);
      expect(
        decideAnimeLibrary(
          serverLibraries: [movies, shows, named],
          arrivedAnimeLibraryId: '2',
          arrivedNonAnimeSameKindLibraryId: '2',
        ),
        named.globalKey,
      );
      expect(
        decideAnimeLibrary(
          serverLibraries: [movies, shows],
          arrivedAnimeLibraryId: '2',
          arrivedNonAnimeSameKindLibraryId: '2',
        ),
        isNull,
      );
    });

    test('vanished voted library falls back to name', () {
      final named = lib('4', 'Anime', MediaKind.show);
      expect(decideAnimeLibrary(serverLibraries: [movies, named], arrivedAnimeLibraryId: '77'), named.globalKey);
    });

    test('name matching variants', () {
      for (final name in ['Animés', 'Anime', 'Animations japonaises', 'ANIME']) {
        final l = lib('5', name, MediaKind.show);
        expect(decideAnimeLibrary(serverLibraries: [movies, l]), l.globalKey, reason: name);
      }
      expect(decideAnimeLibrary(serverLibraries: [movies, shows, music]), isNull);
    });
  });
}
