// FORK: demandes-recentes-overseerr — widget that inserts the "recent requests" row into a library's Recommended tab
//
// The upstream tab keeps loading its own hubs exactly as before. This widget wraps the rendering only: it loads the
// fork row on its own, never makes the tab wait for it, and adds the hub to the list handed to the tab's builder once
// a fresh answer from Overseerr/Seerr is in. See `docs/technique/demandes-recentes-overseerr/plan.md` (decisions 1, 3, 6).

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/offline_mode_provider.dart';
import '../../services/catalog/seerr_catalog_source.dart';
import '../../utils/app_logger.dart';
import 'recent_request_opener.dart';
import 'recent_requests_repository.dart';

/// A row is only shown when the request list behind it is younger than this when the row arrives.
const Duration kRecentRequestsShowWithin = Duration(seconds: 30);

/// A displayed row whose list is older than this is dropped when its refresh does not deliver a newer one.
const Duration kRecentRequestsKeepFor = Duration(minutes: 5);

typedef ForkShelfBuilder = Widget Function(BuildContext context, List<MediaHub> hubs, ForkRequestActivator fork);

/// What the tab needs to render and activate the fork hub; everything answers "not mine" for any other hub.
class ForkRequestActivator {
  final ForkRecentRequestsRow? _row;
  final MediaLibrary? _library;

  const ForkRequestActivator._(this._row, this._library);

  /// Neutral activator: no hub is the fork's.
  static const ForkRequestActivator none = ForkRequestActivator._(null, null);

  static bool _isForkHub(MediaHub hub) => hub.id.startsWith(kRecentRequestsHubIdPrefix);

  /// `TvBrowseRail.onActivateItem`: true when [hub] is the fork hub and the activation was handled here.
  FutureOr<bool> activate(BuildContext context, MediaHub hub, MediaItem item) {
    if (!_isForkHub(hub)) return false;
    final library = _library;
    final entry = _row?.entriesByItemId[item.id];
    // The hub is ours but the entry is gone (row replaced meanwhile): swallow the OK rather than let upstream try to
    // open a catalog-derived item as a server item.
    if (entry == null || library == null) return true;
    unawaited(openRecentRequest(context, entry.request, entry.catalogItem, library));
    return true;
  }

  /// `HubSection.onItemTap`: null for any hub that is not the fork's (null means "upstream behaviour").
  ValueChanged<MediaItem>? tapFor(BuildContext context, MediaHub hub) {
    if (!_isForkHub(hub)) return null;
    return (item) => activate(context, hub, item);
  }

  /// Icon of the fork hub's header, or null (upstream icon) for any other hub.
  IconData? iconFor(MediaHub hub) => _isForkHub(hub) ? Symbols.playlist_add_check_rounded : null;
}

class ForkRecentRequestsShelf extends StatefulWidget {
  final MediaLibrary library;
  final List<MediaHub> hubs;
  final ForkShelfBuilder builder;

  const ForkRecentRequestsShelf({super.key, required this.library, required this.hubs, required this.builder});

  @override
  State<ForkRecentRequestsShelf> createState() => _ForkRecentRequestsShelfState();
}

class _ForkRecentRequestsShelfState extends State<ForkRecentRequestsShelf> {
  ForkRecentRequestsRow? _row;
  SeerrCatalogSource? _source;

  /// Bumped on every library, source or dispose change: answers carrying an older token are dropped.
  int _generation = 0;
  int? _loadingGeneration;

  ValueListenable<TickerModeData>? _tickerModeNotifier;

  static bool _eligible(MediaLibrary library) => library.kind == MediaKind.movie || library.kind == MediaKind.show;

  bool get _visible => _tickerModeNotifier?.value.enabled ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTickerModeNotifier();

    final source = context.read<CatalogSourcesProvider?>()?.seerrSource;
    if (!identical(source, _source)) {
      _source = source;
      _generation++;
      _loadingGeneration = null;
      _row = null;
      if (source != null) unawaited(_load());
    }
  }

  @override
  void activate() {
    super.activate();
    _updateTickerModeNotifier();
  }

  @override
  void didUpdateWidget(ForkRecentRequestsShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library.globalKey != widget.library.globalKey) {
      // The tab state is reused from one library to the next: the previous library's row must vanish at once.
      _generation++;
      _loadingGeneration = null;
      _row = null;
      unawaited(_load());
    } else if (!identical(oldWidget.hubs, widget.hubs)) {
      // The tab reloaded its own hubs: refresh the row too (the repository's 30 s freshness keeps this cheap).
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    _tickerModeNotifier?.removeListener(_onVisibilityChanged);
    _tickerModeNotifier = null;
    super.dispose();
  }

  /// Mirrors `BaseLibraryTab`: [TickerMode.getValuesNotifier] reads the ancestor without registering a dependency.
  void _updateTickerModeNotifier() {
    final notifier = TickerMode.getValuesNotifier(context);
    if (identical(notifier, _tickerModeNotifier)) return;
    _tickerModeNotifier?.removeListener(_onVisibilityChanged);
    _tickerModeNotifier = notifier..addListener(_onVisibilityChanged);
  }

  void _onVisibilityChanged() {
    if (!mounted || !_visible) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    final source = _source;
    final library = widget.library;
    if (source == null || !_eligible(library) || !_visible) return;
    if (context.read<OfflineModeProvider?>()?.isOffline ?? false) return;

    final generation = _generation;
    if (_loadingGeneration == generation) return;
    _loadingGeneration = generation;

    final multi = context.read<MultiServerProvider?>();
    final ctx = ForkRowContext(
      source: source,
      libraries: context.read<LibrariesProvider?>()?.libraries ?? const [],
      clientFor: (id) => multi?.getClientForServer(ServerId(id)),
      isServerOnline: (id) => multi?.isServerOnline(ServerId(id)) ?? false,
    );

    ForkRecentRequestsRow? row;
    try {
      row = await ForkRecentRequestsRepository.of(source.client).rowFor(library, ctx);
    } catch (e) {
      appLogger.d('RecentRequests: row unavailable', error: e);
    }

    if (!mounted || generation != _generation) return;
    _loadingGeneration = null;
    _apply(row);
  }

  void _apply(ForkRecentRequestsRow? row) {
    final shown = _row;
    final now = clock.now();

    final fresh = row != null && row.hub.items.isNotEmpty && now.difference(row.fetchedAt) < kRecentRequestsShowWithin;
    // A late answer must never replace a newer one.
    if (fresh && shown != null && row.fetchedAt.isBefore(shown.fetchedAt)) return;

    ForkRecentRequestsRow? next;
    if (fresh) {
      next = row;
    } else if (shown != null && now.difference(shown.fetchedAt) <= kRecentRequestsKeepFor) {
      // Failed, negative-cached or stale answer: the displayed row stays (focus must not vanish under the user).
      next = shown;
    }
    if (identical(next, shown)) return;
    setState(() => _row = next);
  }

  @override
  Widget build(BuildContext context) {
    final source = context.watch<CatalogSourcesProvider?>()?.seerrSource;
    final row = _row;
    if (source == null || !_eligible(widget.library) || row == null) {
      return widget.builder(context, widget.hubs, ForkRequestActivator.none);
    }

    final hubs = List<MediaHub>.of(widget.hubs);
    final index = hubs.isNotEmpty && hubs.first.isContinueWatchingHub ? 1 : 0;
    hubs.insert(index, row.hub);
    return widget.builder(context, hubs, ForkRequestActivator._(row, widget.library));
  }
}
