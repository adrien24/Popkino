// FORK: demandes-recentes-overseerr — single colored status badge of the recent-requests row
//
// The row shows exactly one short, opaque badge per poster (or none), computed from the user's requests and the
// Seerr media status. `MediaCard` draws it through the one-line hook `forkPosterBadge`. See
// `docs/technique/demandes-recentes-overseerr/plan.md` (T10).

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../models/seerr/seerr_media.dart';
import '../../models/seerr/seerr_request.dart';
import '../../models/seerr/seerr_session.dart';
import 'recent_request.dart';

/// Key of [MediaItem.raw] holding the [ForkRequestBadge.name]; only the fork hub's items carry it.
const String kForkRequestBadgeRawKey = 'popkinoRequestBadge';

/// Declared in the base order of CA7e, plus [blocked] (CA7f). The index is not a rank: see [forkRequestBadgeFor].
enum ForkRequestBadge { available, partial, processing, requested, pending, failed, declined, deleted, blocked }

/// The badge of [r], or null when nothing recognizable applies (CA7f).
///
/// CA7g: like Overseerr, "processing" is shown only while a real download runs on that tier (`downloading` /
/// `downloading4k`). A `processing` media status without a download counts as "requested", unless it is stale (a
/// `failed` request and no `approved` one on that tier). A real download wins over the stale rule.
ForkRequestBadge? forkRequestBadgeFor(ForkRecentRequest r, SeerrProduct product) {
  final hd = SeerrMediaStatus.resolve(r.mediaStatusCode, product);
  final uhd = SeerrMediaStatus.resolve(r.mediaStatus4kCode, product);
  final statuses = [hd, uhd];
  bool hasStatus(SeerrMediaStatus s) => statuses.contains(s);
  bool has(SeerrRequestStatus s) => r.myRequests.any((q) => q.status == s);

  // Same stale-status rule as the Explorer request state, per tier.
  bool stale(bool is4k) {
    final tier = r.myRequests.where((q) => (q.is4k ?? false) == is4k);
    return tier.any((q) => q.status == SeerrRequestStatus.failed) &&
        !tier.any((q) => q.status == SeerrRequestStatus.approved);
  }

  final available = hasStatus(SeerrMediaStatus.available);
  final partial = hasStatus(SeerrMediaStatus.partiallyAvailable);
  final processing =
      (hd == SeerrMediaStatus.processing && r.downloading) || (uhd == SeerrMediaStatus.processing && r.downloading4k);
  final queued =
      (hd == SeerrMediaStatus.processing && !r.downloading && !stale(false)) ||
      (uhd == SeerrMediaStatus.processing && !r.downloading4k && !stale(true));
  final requested = has(SeerrRequestStatus.approved) || hasStatus(SeerrMediaStatus.pending) || queued;
  final pending = has(SeerrRequestStatus.pending);

  if (available) return ForkRequestBadge.available;
  if (partial) return ForkRequestBadge.partial;
  if (processing) return ForkRequestBadge.processing;
  if (hasStatus(SeerrMediaStatus.deleted)) {
    return pending ? ForkRequestBadge.pending : ForkRequestBadge.deleted;
  }
  if (hasStatus(SeerrMediaStatus.blocklisted)) return ForkRequestBadge.blocked;
  if (requested) return ForkRequestBadge.requested;
  if (pending) return ForkRequestBadge.pending;
  if (has(SeerrRequestStatus.failed)) return ForkRequestBadge.failed;
  if (has(SeerrRequestStatus.declined)) return ForkRequestBadge.declined;
  return null;
}

extension ForkRequestBadgeX on ForkRequestBadge {
  String get label {
    final b = t.fork.recentRequests.badge;
    return switch (this) {
      ForkRequestBadge.available => b.available,
      ForkRequestBadge.partial => b.partial,
      ForkRequestBadge.processing => b.processing,
      ForkRequestBadge.requested => b.requested,
      ForkRequestBadge.pending => b.pending,
      ForkRequestBadge.failed => b.failed,
      ForkRequestBadge.declined => b.declined,
      ForkRequestBadge.deleted => b.deleted,
      ForkRequestBadge.blocked => b.blocked,
    };
  }

  /// Opaque, so the contrast never depends on the poster.
  Color get background => switch (this) {
    ForkRequestBadge.available => const Color(0xFF1B7F3B),
    ForkRequestBadge.partial => const Color(0xFF1565C0),
    ForkRequestBadge.processing => const Color(0xFFFB8C00),
    ForkRequestBadge.requested => const Color(0xFF6A1B9A),
    ForkRequestBadge.pending => const Color(0xFFF9C80E),
    ForkRequestBadge.failed ||
    ForkRequestBadge.declined ||
    ForkRequestBadge.deleted ||
    ForkRequestBadge.blocked => const Color(0xFFC62828),
  };

  /// Black on orange and yellow (white fails there), white elsewhere.
  Color get foreground => switch (this) {
    ForkRequestBadge.processing || ForkRequestBadge.pending => const Color(0xFF000000),
    _ => const Color(0xFFFFFFFF),
  };
}

/// The badge overlay for [item], or null (upstream badges apply) when [item] is not a fork hub item.
Widget? forkPosterBadge(Object item) {
  if (item is! MediaItem) return null;
  final name = item.raw?[kForkRequestBadgeRawKey];
  final badge = name is String ? ForkRequestBadge.values.asNameMap()[name] : null;
  if (badge == null) return null;
  return Positioned(
    key: const Key('fork-request-badge'),
    top: 6,
    left: 6,
    right: 6,
    child: Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(color: badge.background, borderRadius: BorderRadius.circular(4)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              badge.label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(color: badge.foreground, fontSize: 11, fontWeight: FontWeight.w700, height: 1),
            ),
          ),
        ),
      ),
    ),
  );
}
