// FORK: demandes-recentes-overseerr — shelf classification and Anime library choice (pure functions)
//
// Decides which recent-request titles belong to which library shelf (Movies / Shows / Anime) and which library of a
// server is its Anime library. See `docs/technique/demandes-recentes-overseerr/plan.md`.

import '../../media/media_kind.dart';
import '../../media/media_library.dart';

/// Maximum number of titles in a recent-requests row.
const int kRecentRequestsRowLimit = 20;

enum ForkRequestShelf { movies, shows, anime }

bool _isMovieOrShow(MediaKind kind) => kind == MediaKind.movie || kind == MediaKind.show;

/// Shelf shown in [library], or null when the library is neither movies, shows nor the Anime library.
ForkRequestShelf? shelfForLibrary(MediaLibrary library, {required String? animeLibraryGlobalKey}) {
  if (animeLibraryGlobalKey != null && library.globalKey == animeLibraryGlobalKey) return ForkRequestShelf.anime;
  switch (library.kind) {
    case MediaKind.movie:
      return ForkRequestShelf.movies;
    case MediaKind.show:
      return ForkRequestShelf.shows;
    default:
      return null;
  }
}

/// Whether a title of [kind] belongs to [shelf]. Anime go to the Anime shelf only when the server has such a library.
bool belongsTo(ForkRequestShelf shelf, MediaKind kind, bool isAnime, {required bool serverHasAnimeLibrary}) {
  final inAnime = isAnime && serverHasAnimeLibrary;
  switch (shelf) {
    case ForkRequestShelf.anime:
      return inAnime && _isMovieOrShow(kind);
    case ForkRequestShelf.movies:
      return kind == MediaKind.movie && !inAnime;
    case ForkRequestShelf.shows:
      return kind == MediaKind.show && !inAnime;
  }
}

/// Global key of the server's Anime library, or null when there is none.
///
/// [arrivedAnimeLibraryId] is the library of an available anime title; [arrivedNonAnimeSameKindLibraryId] the library
/// of an available non-anime title of the same kind. When both are equal the library is mixed and rejected.
String? decideAnimeLibrary({
  required List<MediaLibrary> serverLibraries,
  String? arrivedAnimeLibraryId,
  String? arrivedNonAnimeSameKindLibraryId,
}) {
  if (arrivedAnimeLibraryId != null && arrivedAnimeLibraryId != arrivedNonAnimeSameKindLibraryId) {
    for (final library in serverLibraries) {
      if (library.id == arrivedAnimeLibraryId && _isMovieOrShow(library.kind)) return library.globalKey;
    }
  }
  for (final library in serverLibraries) {
    if (_isMovieOrShow(library.kind) && library.title.toLowerCase().contains('anim')) return library.globalKey;
  }
  return null;
}
