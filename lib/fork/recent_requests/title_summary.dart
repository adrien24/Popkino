// FORK: demandes-recentes-overseerr — light TMDB title summary kept in memory instead of the full details
//
// See `docs/technique/demandes-recentes-overseerr/plan.md`.

import '../../media/media_kind.dart';
import '../../models/seerr/seerr_details.dart';
import '../../models/seerr/seerr_media.dart';
import '../../services/seerr/seerr_constants.dart';

class ForkTitleSummary {
  final int tmdbId;
  final MediaKind kind;
  final String? title;
  final String? name;
  final String? originalTitle;
  final String? originalName;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final String? firstAirDate;
  final double? voteAverage;
  final String? imdbId;
  final int? tvdbId;
  final bool isAnime;

  const ForkTitleSummary({
    required this.tmdbId,
    required this.kind,
    this.title,
    this.name,
    this.originalTitle,
    this.originalName,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.firstAirDate,
    this.voteAverage,
    this.imdbId,
    this.tvdbId,
    this.isAnime = false,
  });

  ForkTitleSummary.fromDetails(SeerrDetails d, this.kind)
    : tmdbId = d.id ?? d.mediaInfo?.tmdbId ?? 0,
      title = d.title,
      name = d.name,
      originalTitle = d.originalTitle,
      originalName = d.originalName,
      overview = d.overview,
      posterPath = d.posterPath,
      backdropPath = d.backdropPath,
      releaseDate = d.releaseDate,
      firstAirDate = d.firstAirDate,
      voteAverage = d.voteAverage,
      imdbId = d.imdbId ?? d.externalIds?.imdbId,
      tvdbId = d.externalIds?.tvdbId,
      // Same rule as the request sheet (`seerr_request_sheet.dart`).
      isAnime = d.keywords?.any((k) => k.id == SeerrConstants.animeKeywordId) ?? false;

  /// Rebuilds a [SeerrDetails] carrying [mediaInfo], enough for `SeerrCatalogSource.catalogItemFromDetailsForFork`.
  SeerrDetails toDetails(SeerrMediaInfo mediaInfo) => SeerrDetails(
    id: tmdbId,
    imdbId: imdbId,
    title: title,
    name: name,
    originalTitle: originalTitle,
    originalName: originalName,
    overview: overview,
    posterPath: posterPath,
    backdropPath: backdropPath,
    releaseDate: releaseDate,
    firstAirDate: firstAirDate,
    voteAverage: voteAverage,
    externalIds: SeerrExternalIds(imdbId: imdbId, tvdbId: tvdbId),
    mediaInfo: mediaInfo,
  );
}
