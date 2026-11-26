// FORK: langues-preferees — local memory of "the user picked a track by hand" flags.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';

/// Kind of track a manual pick applies to.
enum ForkTrackKind {
  audio('a'),
  subtitle('s');

  const ForkTrackKind(this.code);

  /// Storage code used in the persisted map.
  final String code;
}

/// Remembers, per media item and track kind, that the user chose a track
/// manually. Only a flag is kept (never the track itself): the server already
/// stores the track. See `docs/technique/langues-preferees/plan.md`.
abstract final class ForkTrackChoiceMemory {
  static final pref = JsonPref<Map<String, dynamic>>(
    'fork_manual_track_picks',
    defaultValue: const {},
    encode: json.encode,
    decode: (raw) => Map<String, dynamic>.from(raw as Map),
  );

  static const maxEntries = 500;

  static SettingsService? _cachedFor;
  static Map<String, dynamic>? _cache;

  /// Key of the content itself (episode or movie), never the series.
  static String? keyFor(MediaItem item) {
    final serverId = serverIdOrNull(item.serverId);
    if (serverId == null) return null;
    return buildGlobalKey(serverId, item.id);
  }

  static Map<String, dynamic> _entries(SettingsService svc) {
    final cached = _cache;
    if (cached != null && identical(_cachedFor, svc)) return cached;
    final map = svc.read(pref);
    _cachedFor = svc;
    _cache = map;
    return map;
  }

  static bool hasManualPick(MediaItem item, ForkTrackKind kind) {
    final svc = SettingsService.instanceOrNull;
    if (svc == null) return false;
    if (!svc.read(SettingsService.rememberTrackSelections)) return false;
    final key = keyFor(item);
    if (key == null) return false;
    final entry = _entries(svc)[key];
    return entry is Map && entry.containsKey(kind.code);
  }

  static Future<void> recordManualPick(MediaItem item, ForkTrackKind kind) async {
    try {
      final svc = SettingsService.instanceOrNull;
      if (svc == null) return;
      if (!svc.read(SettingsService.rememberTrackSelections)) return;
      final key = keyFor(item);
      if (key == null) return;

      final entries = Map<String, dynamic>.from(_entries(svc));
      final previous = entries[key];
      final entry = previous is Map ? Map<String, dynamic>.from(previous) : <String, dynamic>{};
      entry[kind.code] = DateTime.now().millisecondsSinceEpoch;
      entries[key] = entry;

      final pruned = _prune(entries);
      // Invalidate before writing so a failed write never leaves stale data.
      _cache = null;
      await svc.write(pref, pruned);
    } catch (e) {
      appLogger.w('Failed to record manual track pick', error: e);
    }
  }

  static Map<String, dynamic> _prune(Map<String, dynamic> entries) {
    if (entries.length <= maxEntries) return entries;
    final sorted = entries.entries.toList()..sort((a, b) => _timestampOf(b.value).compareTo(_timestampOf(a.value)));
    return Map.fromEntries(sorted.take(maxEntries));
  }

  /// Latest timestamp among the kinds stored for an entry.
  static int _timestampOf(Object? entry) {
    if (entry is! Map) return 0;
    var latest = 0;
    for (final v in entry.values) {
      if (v is int && v > latest) latest = v;
    }
    return latest;
  }

  @visibleForTesting
  static void resetForTesting() {
    _cachedFor = null;
    _cache = null;
  }
}
