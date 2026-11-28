// FORK: demandes-recentes-overseerr — widget that inserts the "recent requests" row into a library's Recommended tab
//
// The upstream tab keeps loading its own hubs exactly as before. This widget wraps the rendering only: it loads the
// fork row on its own, never makes the tab wait for it, and adds the hub to the list handed to the tab's builder once
// a fresh answer from Overseerr/Seerr is in. See `docs/technique/demandes-recentes-overseerr/plan.md` (decisions 1, 3, 6).
//
// FORK: demandes-recentes-sans-saut — while the answer is pending, a grey placeholder row of the remembered size holds
// the place of the real one (same hub id, same height), for at most 10 s after the library was opened. See
// `docs/technique/demandes-recentes-sans-saut/plan.md` (T4).

import 'dart:async';
import 'dart:math' as math;

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
import 'recent_requests_row_sizes.dart';
import 'recent_requests_skeleton.dart';

export 'recent_requests_repository.dart' show kRecentRequestsShowWithin;
export 'recent_requests_skeleton.dart' show forkIsSkeletonItem;

/// A displayed row whose list is older than this is dropped when its refresh does not deliver a newer one.
const Duration kRecentRequestsKeepFor = Duration(minutes: 5);

/// The grey placeholder row stays at most this long after the library was opened; then the visit is closed.
const Duration kRecentRequestsPlaceholderTimeout = Duration(seconds: 10);

const int _kMaxOpenedEntries = 16;

/// When each library was last opened (noted by [forkWarmUpRecentRequestCounts]), bounded to [_kMaxOpenedEntries].
final Map<String, DateTime> _openedAt = {};

void _noteOpened(String libraryKey) {
  _openedAt.remove(libraryKey);
  _openedAt[libraryKey] = clock.now();
  while (_openedAt.length > _kMaxOpenedEntries) {
    _openedAt.remove(_openedAt.keys.first);
  }
}

@visibleForTesting
void forkDebugResetOpenedAt() => _openedAt.clear();

bool _isEligible(MediaLibrary library) => library.kind == MediaKind.movie || library.kind == MediaKind.show;

/// Called when a library opens, before its hubs load: notes the opening time (start of the 10 s placeholder window) and,
/// only when a row could be inserted (Seerr connected, online, movies or shows), reads the row-size memory. Providers
/// are read before any `await`.
Future<void> forkWarmUpRecentRequestCounts(BuildContext context, MediaLibrary library) async {
  _noteOpened(library.globalKey);
  final source = context.read<CatalogSourcesProvider?>()?.seerrSource;
  final offline = context.read<OfflineModeProvider?>()?.isOffline ?? false;
  if (source == null || offline || !_isEligible(library)) return;
  await ForkRowSizeMemory.instance.ensureLoaded();
}

/// [hubs] without the grey placeholder row: the spotlight area must never show a placeholder.
Iterable<MediaHub> forkSpotlightHubs(Iterable<MediaHub> hubs) =>
    hubs.where((hub) => hub.items.isEmpty || !hub.items.every(forkIsSkeletonItem));

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

  /// Number of grey posters of the placeholder row (0: none), and the timer that closes the visit after 10 s.
  int _placeholderCount = 0;
  Timer? _placeholderTimer;

  /// True once the placeholder timed out: the real row is not shown any more for this visit (it still updates the memory).
  bool _visitClosed = false;

  /// True during the first of the two frames that remove the placeholder (one poster left, then none).
  bool _dropping = false;

  ValueListenable<TickerModeData>? _tickerModeNotifier;

  bool get _visible => _tickerModeNotifier?.value.enabled ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTickerModeNotifier();

    final source = context.read<CatalogSourcesProvider?>()?.seerrSource;
    if (!identical(source, _source)) {
      _source = source;
      _resetFor();
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
      _resetFor();
    } else if (!identical(oldWidget.hubs, widget.hubs)) {
      // The tab reloaded its own hubs: refresh the row too (the repository's 30 s freshness keeps this cheap). This
      // never reopens a closed visit.
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    _placeholderTimer?.cancel();
    _placeholderTimer = null;
    _tickerModeNotifier?.removeListener(_onVisibilityChanged);
    _tickerModeNotifier = null;
    super.dispose();
  }

  /// Starts a new visit: forgets the previous row and placeholder, then decides what holds the row's place while the
  /// answer loads (the last row built, a placeholder of the remembered size, or nothing). No `setState`: runs during
  /// `didUpdateWidget`, `didChangeDependencies` or right before a `setState`.
  void _resetFor() {
    _generation++;
    _loadingGeneration = null;
    _row = null;
    _placeholderTimer?.cancel();
    _placeholderTimer = null;
    _placeholderCount = 0;
    _visitClosed = false;
    _dropping = false;

    final source = _source;
    final library = widget.library;
    if (source == null || !_isEligible(library)) return;
    if (context.read<OfflineModeProvider?>()?.isOffline ?? false) return;

    final recent = ForkRecentRequestsRepository.of(source.client).recentRowFor(library);
    if (recent != null) {
      _row = recent;
    } else {
      final n = ForkRowSizeMemory.instance.sizeFor(source.client.session, library);
      if (n != null && n > 0) {
        final now = clock.now();
        final elapsed = now.difference(_openedAt[library.globalKey] ?? now);
        var remaining = kRecentRequestsPlaceholderTimeout - elapsed;
        if (remaining > kRecentRequestsPlaceholderTimeout) remaining = kRecentRequestsPlaceholderTimeout;
        if (remaining > Duration.zero) {
          _placeholderCount = n;
          _placeholderTimer = Timer(remaining, _onPlaceholderTimeout);
        }
      }
    }
    unawaited(_load());
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
    if (_visitClosed) {
      // The tab is back in the foreground: a new visit. Never done while a real row is shown (the focus could vanish).
      _noteOpened(widget.library.globalKey);
      _resetFor();
      setState(() {});
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final source = _source;
    final library = widget.library;
    if (source == null || !_isEligible(library) || !_visible) return;
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

    ForkRowResult result = (row: null, conclusive: false);
    try {
      result = await ForkRecentRequestsRepository.of(source.client).rowResultFor(library, ctx);
    } catch (e) {
      appLogger.d('RecentRequests: row unavailable', error: e);
    }

    if (!mounted || generation != _generation) return;
    _loadingGeneration = null;
    _apply(result);
  }

  void _apply(ForkRowResult result) {
    final source = _source;
    if (source == null) return;
    final session = source.client.session;
    final library = widget.library;
    final row = result.row;
    final shown = _row;
    final now = clock.now();

    final fresh = row != null && row.hub.items.isNotEmpty && now.difference(row.fetchedAt) < kRecentRequestsShowWithin;
    // A late answer must never replace a newer one.
    if (fresh && shown != null && row.fetchedAt.isBefore(shown.fetchedAt)) return;

    if (fresh) {
      unawaited(ForkRowSizeMemory.instance.remember(session, library, row.hub.items.length));
      // Closed visit: the row is not shown any more, but the memory stays up to date.
      if (_visitClosed) return;
      _placeholderTimer?.cancel();
      _placeholderTimer = null;
      if (identical(row, shown) && _placeholderCount == 0) return;
      setState(() {
        _placeholderCount = 0;
        _dropping = false;
        _row = row;
      });
      return;
    }

    if (row == null && result.conclusive) {
      // The server answered and there is nothing to show: forget the size, and remove the placeholder.
      unawaited(ForkRowSizeMemory.instance.forget(session, library));
      if (_placeholderCount > 0) {
        _placeholderTimer?.cancel();
        _placeholderTimer = null;
        _dropPlaceholder();
      }
    }

    // Failed, negative-cached or stale answer: a displayed row stays (focus must not vanish under the user).
    ForkRecentRequestsRow? next;
    if (shown != null && now.difference(shown.fetchedAt) <= kRecentRequestsKeepFor) next = shown;
    if (identical(next, shown)) return;
    setState(() => _row = next);
  }

  void _onPlaceholderTimeout() {
    _placeholderTimer = null;
    if (!mounted || _row != null || _placeholderCount <= 0) return;
    _visitClosed = true;
    _dropPlaceholder();
  }

  /// Removes the placeholder in two frames: first a single poster (a focus on it returns to column 0), then none, so the
  /// rail hands the focus to a neighbouring row.
  void _dropPlaceholder() {
    if (_dropping) return;
    _dropping = true;
    final generation = _generation;
    setState(() => _placeholderCount = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || !_dropping) return;
      setState(() {
        _placeholderCount = 0;
        _dropping = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = context.watch<CatalogSourcesProvider?>()?.seerrSource;
    final row = _row;
    final library = widget.library;
    if (source == null || !_isEligible(library) || (row == null && _placeholderCount <= 0)) {
      return widget.builder(context, widget.hubs, ForkRequestActivator.none);
    }

    final MediaHub hub;
    if (row != null) {
      hub = row.hub;
    } else {
      final int count;
      if (_dropping) {
        count = 1;
      } else {
        final cap = forkSkeletonVisibleCap(context, forkRecentRequestsHub(library, forkSkeletonItems(library, 1)));
        count = math.min(_placeholderCount, cap);
      }
      hub = forkRecentRequestsHub(library, forkSkeletonItems(library, count));
    }

    final hubs = List<MediaHub>.of(widget.hubs);
    final index = hubs.isNotEmpty && hubs.first.isContinueWatchingHub ? 1 : 0;
    hubs.insert(index, hub);
    return widget.builder(context, hubs, ForkRequestActivator._(row, library));
  }
}
