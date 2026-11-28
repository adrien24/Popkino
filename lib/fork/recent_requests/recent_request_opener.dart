// FORK: demandes-recentes-overseerr — opens a recent request: the server title when it is really there, else Explorer
//
// See `docs/technique/demandes-recentes-overseerr/plan.md` (decision 8 and 12).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/seerr/seerr_media.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/catalog/catalog_library_matcher.dart';
import '../../utils/app_logger.dart';
import '../../utils/catalog_navigation_helper.dart';
import '../../utils/media_navigation_helper.dart';
import 'recent_request.dart';
import 'server_link.dart';

const Duration kRecentRequestResolveBudget = Duration(milliseconds: 2500);
const Duration _overlayDelay = Duration(milliseconds: 300);

/// Resolves the media-server copy of a requested title, or null (never throws).
///
/// Only titles Overseerr reports as available or partially available are resolved ([isAvailable], computed by the
/// caller); anything else returns null without a single call. The whole resolution is bounded by [budget].
Future<MediaItem?> resolveServerItem({
  required ForkRecentRequest request,
  required CatalogItem item,
  required bool isAvailable,
  required MediaLibrary library,
  required MediaServerClient? Function(String serverId) clientFor,
  required bool Function(String serverId) isServerOnline,
  Future<List<MediaItem>> Function(CatalogItem item)? matchLibraries,
  Duration budget = kRecentRequestResolveBudget,
}) async {
  if (!isAvailable) return null;
  try {
    return await _resolve(
      request: request,
      item: item,
      library: library,
      clientFor: clientFor,
      isServerOnline: isServerOnline,
      matchLibraries: matchLibraries,
    ).timeout(budget, onTimeout: () => null);
  } catch (e) {
    appLogger.d('RecentRequests: resolve failed for tmdb ${request.tmdbId}', error: e);
    return null;
  }
}

Future<MediaItem?> _resolve({
  required ForkRecentRequest request,
  required CatalogItem item,
  required MediaLibrary library,
  required MediaServerClient? Function(String serverId) clientFor,
  required bool Function(String serverId) isServerOnline,
  required Future<List<MediaItem>> Function(CatalogItem item)? matchLibraries,
}) async {
  final link = request.link ?? request.link4k;
  if (link != null) {
    final linked = await _fromLink(link, request, library, clientFor, isServerOnline);
    if (linked != null) return linked;
  }

  if (matchLibraries == null) return null;
  final copies = await matchLibraries(item);
  if (copies.isEmpty) return null;
  return copies.where((c) => c.serverId == library.serverId && c.libraryId == library.id).firstOrNull ??
      copies.where((c) => c.serverId == library.serverId).firstOrNull ??
      copies.first;
}

Future<MediaItem?> _fromLink(
  ForkServerLink link,
  ForkRecentRequest request,
  MediaLibrary library,
  MediaServerClient? Function(String serverId) clientFor,
  bool Function(String serverId) isServerOnline,
) async {
  final linkServerId = link.serverId;
  final serverId = linkServerId ?? library.serverId;
  if (serverId == null) return null;
  // `PlexClient.fetchItem` can fall back to the API cache: an offline server must not be asked.
  if (!isServerOnline(serverId)) return null;
  final client = clientFor(serverId);
  if (client == null) return null;

  final fetched = await client.fetchItem(link.itemId);
  if (fetched == null || fetched.kind != request.kind) return null;

  // A bare rating key repeats from one Plex server to another: check the title is the requested one.
  if (linkServerId == null) {
    final ids = await client.fetchExternalIds(link.itemId);
    if (ids.tmdb != request.tmdbId) return null;
  }
  return fetched;
}

bool _opening = false;

/// Opens [request]: the server title when available and found, otherwise the Explorer detail page (CA11).
///
/// A second call while one is in flight is ignored. A centred spinner (no focus) appears if resolving takes more than
/// 300 ms. [resolver], [openServerItem] and [openCatalog] are test seams.
Future<void> openRecentRequest(
  BuildContext context,
  ForkRecentRequest request,
  CatalogItem catalogItem,
  MediaLibrary library, {
  Future<MediaItem?> Function()? resolver,
  Future<void> Function(BuildContext context, MediaItem item)? openServerItem,
  Future<void> Function(BuildContext context, CatalogItem item)? openCatalog,
}) async {
  if (_opening) return;
  _opening = true;

  final overlay = Overlay.maybeOf(context);
  OverlayEntry? entry;
  Timer? timer;
  MediaItem? serverItem;
  try {
    if (overlay != null) {
      timer = Timer(_overlayDelay, () {
        entry = OverlayEntry(
          builder: (_) => const IgnorePointer(child: Center(child: CircularProgressIndicator())),
        );
        overlay.insert(entry!);
      });
    }
    serverItem = await (resolver ?? () => _resolveFromContext(context, request, catalogItem, library))();
  } catch (e) {
    appLogger.d('RecentRequests: open failed', error: e);
  } finally {
    timer?.cancel();
    entry?.remove();
    entry?.dispose();
    _opening = false;
  }

  if (!context.mounted) return;
  if (serverItem != null) {
    await (openServerItem ?? (c, i) => navigateToMediaItemDetails(c, i))(context, serverItem);
  } else {
    await (openCatalog ?? navigateToCatalogItem)(context, catalogItem);
  }
}

Future<MediaItem?> _resolveFromContext(
  BuildContext context,
  ForkRecentRequest request,
  CatalogItem catalogItem,
  MediaLibrary library,
) {
  final product = context.read<CatalogSourcesProvider?>()?.seerrSource?.client.session.product;
  if (product == null) return Future.value(null);
  bool available(int? code) {
    final s = SeerrMediaStatus.resolve(code, product);
    return s == SeerrMediaStatus.available || s == SeerrMediaStatus.partiallyAvailable;
  }

  final multi = context.read<MultiServerProvider?>();
  final matcher = context.read<CatalogLibraryMatcher?>();
  return resolveServerItem(
    request: request,
    item: catalogItem,
    isAvailable: available(request.mediaStatusCode) || available(request.mediaStatus4kCode),
    library: library,
    clientFor: (id) => multi?.getClientForServer(ServerId(id)),
    isServerOnline: (id) => multi?.isServerOnline(ServerId(id)) ?? false,
    matchLibraries: matcher == null ? null : (item) async => (await matcher.match(item)).items,
  );
}
