// FORK: demandes-recentes-sans-saut — grey placeholder posters of the recent-requests row
//
// While the real row is still loading, the shelf inserts a row of the same shape made of grey cards, so nothing
// jumps when the real posters arrive. `MediaCard` draws them through the one-line hook `forkSkeletonCard`. See
// `docs/technique/demandes-recentes-sans-saut/plan.md` (T3).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../focus/card_focus_scope.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../navigation/main_screen_scope.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/media_card.dart';
import '../../widgets/tv_browse_rail.dart';
import 'recent_requests_classifier.dart';

/// Key of [MediaItem.raw] marking a placeholder item.
const String kForkSkeletonRawKey = 'popkinoSkeleton';

/// Whether [item] is a placeholder built by [forkSkeletonItems].
bool forkIsSkeletonItem(Object item) => item is MediaItem && item.raw?[kForkSkeletonRawKey] == true;

/// [n] placeholder items: portrait posters, no title, no server, no catalog key.
List<MediaItem> forkSkeletonItems(MediaLibrary library, int n) => [
  for (var i = 0; i < n; i++)
    MediaItem(
      id: 'popkino.recentRequests.skeleton:$i',
      backend: library.backend,
      kind: MediaKind.movie,
      raw: const {kForkSkeletonRawKey: true},
    ),
];

/// The grey card replacing [MediaCard]'s content for a placeholder [item], or null for any other item.
///
/// Same geometry as the real grid card (`MediaCard.gridCardPadding`, height given by the rail) so the row keeps the
/// height of the real one. No button semantics, tap area or context menu: the card is inert.
Widget? forkSkeletonCard(BuildContext context, Object item, {double? width, double? height, required bool fullBleed}) {
  if (!forkIsSkeletonItem(item)) return null;
  final radius = tokens(context).radiusSm;
  final poster = CardFocusBorder(
    borderRadius: radius,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: const SkeletonLoader(child: SizedBox.expand()),
    ),
  );

  if (fullBleed) {
    return ExcludeSemantics(
      child: SizedBox(width: width, height: height, child: poster),
    );
  }

  return ExcludeSemantics(
    child: SizedBox(
      width: width,
      child: ClipRect(
        child: Padding(
          padding: MediaCard.gridCardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (height != null)
                SizedBox(width: double.infinity, height: height, child: poster)
              else
                AspectRatio(aspectRatio: 2 / 3, child: poster),
              const SizedBox(height: 2),
              const SkeletonLoader(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                child: SizedBox(height: 11, width: double.infinity),
              ),
              const SizedBox(height: 3),
              const FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.6,
                child: SkeletonLoader(borderRadius: BorderRadius.all(Radius.circular(4)), child: SizedBox(height: 9)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// How many placeholder posters fit on screen: 8 off TV, otherwise the visible card count of the TV rail, computed
/// with the same parameters as the Recommended tab's TV content.
int forkSkeletonVisibleCap(BuildContext context, MediaHub skeletonHub) {
  if (!PlatformDetector.isTV()) return 8;
  final size = MainScreenFocusScope.foregroundSizeOf(context);
  final settings = SettingsService.instance;
  final metrics = TvBrowseRailLayout.metricsForHub(
    hub: skeletonHub,
    availableWidth: size.width,
    density: settings.read(SettingsService.libraryDensity),
    episodePosterMode: settings.read(SettingsService.episodePosterMode),
    fullCardLayout: settings.read(SettingsService.tvFullCardLayout),
    gridSpacing: settings.read(SettingsService.gridSpacing),
    scale: TvLayoutConstants.scaleForSize(size),
    tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
    widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
  );
  final visible = (size.width - 2 * metrics.railEdgePadding + metrics.itemGap) / (metrics.cardWidth + metrics.itemGap);
  return math.min(math.max(visible.ceil(), 1), kRecentRequestsRowLimit);
}
