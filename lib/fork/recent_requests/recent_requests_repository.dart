// FORK: demandes-recentes-overseerr — repository: request list, title summaries, caches, timeouts, Anime library
//
// Builds the "recent requests" row of a library from the user's Overseerr/Seerr requests. Everything is lazy: nothing
// is created or called until [ForkRecentRequestsRepository.rowFor] runs (opening a library), and no snapshot is ever
// shown before a fresh answer. See `docs/technique/demandes-recentes-overseerr/plan.md`.

import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_backend.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/seerr/seerr_media.dart';
import '../../services/catalog/seerr_catalog_source.dart';
import '../../services/seerr/seerr_client.dart';
import '../../services/trackers/future_coalescer.dart';
import '../../utils/app_logger.dart';
import 'recent_request.dart';
import 'recent_request_badge.dart';
import 'recent_requests_classifier.dart';
import 'server_link.dart';
import 'title_summary.dart';

/// Prefix of the fork hub's `id` (followed by the library global key).
const String kRecentRequestsHubIdPrefix = 'popkino.recentRequests:';

/// `MediaHub.identifier` of the fork hub.
const String kRecentRequestsHubIdentifier = 'popkino.recentRequests';

const int _kRequestsTake = 100;
const Duration _listFreshness = Duration(seconds: 30);
const Duration _failureBackoff = Duration(seconds: 60);
const Duration _listTimeout = Duration(seconds: 8);
const Duration _detailTimeout = Duration(seconds: 8);
const Duration _fetchItemTimeout = Duration(milliseconds: 2500);
const Duration _rowBudget = Duration(seconds: 15);
const int _maxDetailsInFlight = 4;

/// Minimum delay before an inconclusive Anime library lookup (server offline or failing) is tried again.
const Duration _animeRetryDelay = Duration(seconds: 60);

/// What the repository needs from the app to build a row for one library.
class ForkRowContext {
  final SeerrCatalogSource source;

  /// Every library the app knows (all servers).
  final List<MediaLibrary> libraries;
  final MediaServerClient? Function(String serverId) clientFor;
  final bool Function(String serverId) isServerOnline;

  const ForkRowContext({
    required this.source,
    required this.libraries,
    required this.clientFor,
    required this.isServerOnline,
  });
}

class ForkRecentRequestEntry {
  final ForkRecentRequest request;
  final CatalogItem catalogItem;

  const ForkRecentRequestEntry({required this.request, required this.catalogItem});
}

class ForkRecentRequestsRow {
  final MediaHub hub;

  /// Entries keyed by the rendering [MediaItem.id] of each hub item.
  final Map<String, ForkRecentRequestEntry> entriesByItemId;

  /// When the request list behind this row was obtained.
  final DateTime fetchedAt;

  const ForkRecentRequestsRow({required this.hub, required this.entriesByItemId, required this.fetchedAt});
}

class ForkRecentRequestsRepository {
  static final Expando<ForkRecentRequestsRepository> _instances = Expando('ForkRecentRequestsRepository');

  /// Replaces [of] in tests.
  @visibleForTesting
  static ForkRecentRequestsRepository Function(SeerrClient)? debugOverride;

  /// The repository of [client]: it lives and dies with the client (sign-out, profile switch).
  static ForkRecentRequestsRepository of(SeerrClient client) {
    final override = debugOverride;
    if (override != null) return override(client);
    return _instances[client] ??= ForkRecentRequestsRepository(client);
  }

  final SeerrClient client;

  ForkRecentRequestsRepository(this.client);

  List<ForkRecentRequest>? _list;
  DateTime? _listAt;
  DateTime? _failureAt;
  final FutureCoalescer<List<ForkRecentRequest>?> _listLoad = FutureCoalescer();

  final Map<String, ForkTitleSummary> _summaries = {};
  final KeyedFutureCoalescer<String, ForkTitleSummary> _summaryLoad = KeyedFutureCoalescer();
  final _Permits _permits = _Permits(_maxDetailsInFlight);

  final Map<String, _AnimeLookup> _animeLibraryByServer = {};

  /// The recent-requests row for [library], or null when there is nothing to show (no list, failure, empty row).
  Future<ForkRecentRequestsRow?> rowFor(MediaLibrary library, ForkRowContext ctx) async {
    final serverId = library.serverId;
    if (serverId == null) return null;
    // Callers already filter, but no network call must ever happen for a library that is neither movies nor shows.
    if (library.kind != MediaKind.movie && library.kind != MediaKind.show) return null;

    final snapshot = await _currentList();
    if (snapshot == null || snapshot.list.isEmpty) return null;

    final budget = _Budget(_rowBudget);
    try {
      final anime = await Future.any<({String? key})?>([
        _animeLibraryFor(library, serverId, ctx, snapshot.list).then((key) => (key: key)),
        budget.whenExpired.then((_) => null),
      ]);
      if (anime == null) return null;

      final shelf = shelfForLibrary(library, animeLibraryGlobalKey: anime.key);
      if (shelf == null) return null;
      final serverHasAnimeLibrary = anime.key != null;

      final candidates = [
        for (final r in snapshot.list)
          if (shelf == ForkRequestShelf.anime ||
              (shelf == ForkRequestShelf.movies && r.kind == MediaKind.movie) ||
              (shelf == ForkRequestShelf.shows && r.kind == MediaKind.show))
            r,
      ];

      final retained = <(ForkRecentRequest, ForkTitleSummary)>[];
      await _readOrdered(candidates, budget, (request, summary) {
        if (summary != null &&
            belongsTo(shelf, request.kind, summary.isAnime, serverHasAnimeLibrary: serverHasAnimeLibrary)) {
          retained.add((request, summary));
        }
        return retained.length >= kRecentRequestsRowLimit;
      });
      if (retained.isEmpty) return null;

      final entries = <String, ForkRecentRequestEntry>{};
      final items = <MediaItem>[];
      for (final (request, summary) in retained) {
        try {
          final catalogItem = await ctx.source.catalogItemFromDetailsForFork(
            summary.toDetails(request.mediaInfo),
            request.kind,
          );
          final badge = forkRequestBadgeFor(request, client.session.product);
          final base = catalogItem.toMediaItem();
          final item = badge == null ? base : base.copyWith(raw: {...?base.raw, kForkRequestBadgeRawKey: badge.name});
          entries[item.id] = ForkRecentRequestEntry(request: request, catalogItem: catalogItem);
          items.add(item);
        } catch (e) {
          appLogger.d('RecentRequests: skipped tmdb ${request.tmdbId} (mapping failed)', error: e);
        }
      }
      if (items.isEmpty) return null;

      return ForkRecentRequestsRow(
        hub: MediaHub(
          id: '$kRecentRequestsHubIdPrefix${library.globalKey}',
          identifier: kRecentRequestsHubIdentifier,
          title: t.fork.recentRequests.title,
          type: 'mixed',
          items: items,
          size: items.length,
        ),
        entriesByItemId: entries,
        fetchedAt: snapshot.at,
      );
    } finally {
      budget.dispose();
    }
  }

  // ---------- Request list ----------

  Future<({List<ForkRecentRequest> list, DateTime at})?> _currentList() async {
    final now = clock.now();
    final cached = _list;
    final cachedAt = _listAt;
    if (cached != null && cachedAt != null && now.difference(cachedAt) < _listFreshness) {
      return (list: cached, at: cachedAt);
    }
    final failedAt = _failureAt;
    if (failedAt != null && now.difference(failedAt) < _failureBackoff) return null;

    final loaded = await _listLoad.run(_fetchList);
    final at = _listAt;
    if (loaded == null || at == null) return null;
    return (list: loaded, at: at);
  }

  /// Never throws: any failure (network, Seerr error, a non-JSON 200 raising a `TypeError`, a malformed page) starts
  /// the negative cache and yields null.
  Future<List<ForkRecentRequest>?> _fetchList() async {
    try {
      final userId = client.session.userId;
      final loading = client.getRequestsJson(take: _kRequestsTake, requestedBy: userId).then((json) {
        final list = parseRecentRequests(json, userId: userId);
        // Fills the cache even when the answer lands after the caller's timeout.
        _list = list;
        _listAt = clock.now();
        _failureAt = null;
        return list;
      });
      return await loading.timeout(_listTimeout);
    } catch (e) {
      _failureAt = clock.now();
      appLogger.w('RecentRequests: request list unavailable', error: e);
      return null;
    }
  }

  // ---------- Title summaries ----------

  String _summaryKey(ForkRecentRequest r) =>
      '${LocaleSettings.currentLocale.plexLanguageCode}|${r.kind.id}:${r.tmdbId}';

  /// Summary of [request]'s title, from memory or the Seerr details endpoint (at most [_maxDetailsInFlight] in flight
  /// across the repository). Null on failure (never cached) or when [cancelled] turns true while waiting.
  Future<ForkTitleSummary?> _summaryFor(ForkRecentRequest request, bool Function() cancelled) async {
    final key = _summaryKey(request);
    final cached = _summaries[key];
    if (cached != null) return cached;

    await _permits.acquire();
    try {
      if (cancelled()) return null;
      final again = _summaries[key];
      if (again != null) return again;
      return await _summaryLoad.run(key, () => _loadSummary(request, key));
    } catch (e) {
      appLogger.d('RecentRequests: details unavailable for ${request.kind.id}:${request.tmdbId}', error: e);
      return null;
    } finally {
      _permits.release();
    }
  }

  Future<ForkTitleSummary> _loadSummary(ForkRecentRequest request, String key) async {
    final loading = request.kind == MediaKind.movie ? client.getMovie(request.tmdbId) : client.getTv(request.tmdbId);
    final details = await loading.timeout(_detailTimeout);
    final summary = ForkTitleSummary.fromDetails(details, request.kind);
    _summaries[key] = summary;
    return summary;
  }

  /// Reads the summaries of [entries] in order, at most [_maxDetailsInFlight] at a time, and hands each result to
  /// [onResult] **in list order**. Stops when [onResult] returns true, when every entry was consumed, or when [budget]
  /// expires (results received so far were already handed over).
  Future<void> _readOrdered(
    List<ForkRecentRequest> entries,
    _Budget budget,
    bool Function(ForkRecentRequest request, ForkTitleSummary? summary) onResult,
  ) async {
    final done = Completer<void>();
    final slots = List<({bool ready, ForkTitleSummary? summary})>.filled(entries.length, (ready: false, summary: null));
    var next = 0;
    var consumed = 0;
    var stopped = false;

    bool isCancelled() => stopped || budget.expired;

    void drain() {
      while (!stopped && consumed < entries.length && slots[consumed].ready) {
        final index = consumed++;
        if (onResult(entries[index], slots[index].summary)) stopped = true;
      }
      if ((stopped || consumed >= entries.length) && !done.isCompleted) done.complete();
    }

    Future<void> worker() async {
      while (!isCancelled()) {
        final index = next++;
        if (index >= entries.length) return;
        final summary = await _summaryFor(entries[index], isCancelled);
        slots[index] = (ready: true, summary: summary);
        drain();
      }
    }

    drain();
    if (done.isCompleted) return;
    for (var i = 0; i < _maxDetailsInFlight && i < entries.length; i++) {
      unawaited(worker());
    }
    await Future.any([done.future, budget.whenExpired]);
    stopped = true;
  }

  // ---------- Anime library ----------

  /// Anime library of [serverId]. A conclusive answer is kept for the life of the repository. An inconclusive one (a
  /// needed `fetchItem` was skipped because the server was offline, threw, or timed out) only serves the loads that
  /// follow within [_animeRetryDelay]; the first load after that tries again. Concurrent callers share one lookup.
  Future<String?> _animeLibraryFor(
    MediaLibrary library,
    String serverId,
    ForkRowContext ctx,
    List<ForkRecentRequest> list,
  ) {
    final existing = _animeLibraryByServer[serverId];
    if (existing != null) {
      final settledAt = existing.settledAt;
      final retry = settledAt != null && !existing.conclusive && clock.now().difference(settledAt) >= _animeRetryDelay;
      if (!retry) return existing.result.then((r) => r.key);
    }
    final lookup = _AnimeLookup();
    lookup.result = _detectAnimeLibrary(library, serverId, ctx, list).then((r) {
      lookup.conclusive = r.conclusive;
      lookup.settledAt = clock.now();
      return r;
    });
    _animeLibraryByServer[serverId] = lookup;
    return lookup.result.then((r) => r.key);
  }

  bool _isAvailable(ForkRecentRequest r) {
    final product = client.session.product;
    bool ok(int? code) {
      final status = SeerrMediaStatus.resolve(code, product);
      return status == SeerrMediaStatus.partiallyAvailable || status == SeerrMediaStatus.available;
    }

    return ok(r.mediaStatusCode) || ok(r.mediaStatus4kCode);
  }

  /// Global key of the Anime library of [serverId], or null, and whether the answer is [conclusive]. Never throws.
  Future<({String? key, bool conclusive})> _detectAnimeLibrary(
    MediaLibrary library,
    String serverId,
    ForkRowContext ctx,
    List<ForkRecentRequest> list,
  ) async {
    final budget = _Budget(_rowBudget);
    try {
      ForkRecentRequest? firstAnime;
      final firstNonAnimeByKind = <MediaKind, ForkRecentRequest>{};
      final available = [
        for (final r in list)
          if (_isAvailable(r)) r,
      ];
      await _readOrdered(available, budget, (request, summary) {
        if (summary == null) return false;
        if (summary.isAnime) {
          firstAnime ??= request;
        } else {
          firstNonAnimeByKind.putIfAbsent(request.kind, () => request);
        }
        final anime = firstAnime;
        return anime != null && firstNonAnimeByKind.containsKey(anime.kind);
      });

      final animeRequest = firstAnime;
      final nonAnimeRequest = animeRequest == null ? null : firstNonAnimeByKind[animeRequest.kind];
      final lookups = await Future.wait([
        if (animeRequest != null) _libraryIdOf(animeRequest, library, serverId, ctx),
        if (nonAnimeRequest != null) _libraryIdOf(nonAnimeRequest, library, serverId, ctx),
      ]);
      final key = decideAnimeLibrary(
        serverLibraries: [
          for (final l in ctx.libraries)
            if (l.serverId == serverId) l,
        ],
        arrivedAnimeLibraryId: animeRequest == null ? null : lookups[0].id,
        arrivedNonAnimeSameKindLibraryId: nonAnimeRequest == null ? null : lookups[1].id,
      );
      return (key: key, conclusive: lookups.every((l) => l.conclusive));
    } catch (e) {
      appLogger.w('RecentRequests: Anime library detection failed', error: e);
      return (key: null, conclusive: false);
    } finally {
      budget.dispose();
    }
  }

  /// `libraryId` of the server item behind [request]. Not [conclusive] when a needed `fetchItem` could not be made or
  /// failed (server offline or unknown, exception, timeout). A link that does not point at [serverId], an absent item
  /// or an item without `libraryId` are conclusive.
  Future<({String? id, bool conclusive})> _libraryIdOf(
    ForkRecentRequest request,
    MediaLibrary library,
    String serverId,
    ForkRowContext ctx,
  ) async {
    final link = request.link ?? request.link4k;
    if (link == null) return (id: null, conclusive: true);
    if (link.serverId != null && link.serverId != serverId) return (id: null, conclusive: true);
    if (!_backendMatches(link.backend, library.backend)) return (id: null, conclusive: true);
    if (!ctx.isServerOnline(serverId)) return (id: null, conclusive: false);
    final serverClient = ctx.clientFor(serverId);
    if (serverClient == null) return (id: null, conclusive: false);
    try {
      final item = await serverClient.fetchItem(link.itemId).timeout(_fetchItemTimeout);
      return (id: item?.libraryId, conclusive: true);
    } catch (e) {
      appLogger.d('RecentRequests: fetchItem ${link.itemId} failed on $serverId', error: e);
      return (id: null, conclusive: false);
    }
  }

  static bool _backendMatches(ForkServerLinkBackend linkBackend, MediaBackend backend) => switch (linkBackend) {
    ForkServerLinkBackend.plex => backend == MediaBackend.plex,
    ForkServerLinkBackend.jellyfin => backend == MediaBackend.jellyfin || backend == MediaBackend.emby,
  };
}

/// One Anime library lookup of a server, shared by concurrent callers.
class _AnimeLookup {
  late Future<({String? key, bool conclusive})> result;
  bool conclusive = false;

  /// When the lookup finished; null while it is in flight.
  DateTime? settledAt;
}

/// A deadline: [expired] flips and [whenExpired] completes when the time is up.
class _Budget {
  final Completer<void> _expired = Completer<void>();
  late final Timer _timer;

  _Budget(Duration duration) {
    _timer = Timer(duration, () {
      if (!_expired.isCompleted) _expired.complete();
    });
  }

  bool get expired => _expired.isCompleted;
  Future<void> get whenExpired => _expired.future;

  void dispose() => _timer.cancel();
}

/// Counting semaphore.
class _Permits {
  int _free;
  final Queue<Completer<void>> _waiters = Queue();

  _Permits(this._free);

  Future<void> acquire() {
    if (_free > 0) {
      _free--;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _free++;
    }
  }
}
