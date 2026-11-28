// FORK: demandes-recentes-sans-saut — memory of the size of each library's recent-requests row
//
// Remembers, per library, how many posters the row showed last time so a grey placeholder row of the same size can be
// inserted on the next visit (no layout jump). Stored as `row_sizes.json` in the app cache directory (excluded from
// Android backups, never read at startup). Only integers are stored: no title, no TMDB id. See
// `docs/technique/demandes-recentes-sans-saut/plan.md`.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../media/media_library.dart';
import '../../models/seerr/seerr_session.dart';
import '../../utils/app_logger.dart';
import '../../utils/serial_future_queue.dart';

const String kRowSizesDirectoryName = 'popkino_recent_requests';
const String kRowSizesFileName = 'row_sizes.json';

const int _kVersion = 1;
const int _kMaxEntries = 64;
const int _kExpiryDays = 30;
const int _kRefreshDays = 7;

class ForkRowSizeMemory {
  static final ForkRowSizeMemory instance = ForkRowSizeMemory();

  @visibleForTesting
  static Future<Directory> Function()? debugDirectory;

  @visibleForTesting
  static void debugReset() {
    instance._loading = null;
    instance._loaded = false;
    instance._owner = null;
    instance._rows.clear();
    instance._queue.reset();
  }

  final SerialFutureQueue _queue = SerialFutureQueue();
  final LinkedHashMap<String, ({int n, int d})> _rows = LinkedHashMap();
  String? _owner;
  bool _loaded = false;
  Future<void>? _loading;

  /// First 16 hex characters of SHA-256 of `baseUrl|userId`.
  static String ownerOf(SeerrSession s) =>
      sha256.convert(utf8.encode('${s.baseUrl}|${s.userId}')).toString().substring(0, 16);

  bool get isLoaded => _loaded;

  static int _today() => clock.now().toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  static Future<File> _file() async {
    final base = await (debugDirectory ?? getApplicationCacheDirectory)();
    return File(p.join(base.path, kRowSizesDirectoryName, kRowSizesFileName));
  }

  /// Reads the file once per process. Never throws.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        var valid = false;
        try {
          final json = jsonDecode(await file.readAsString());
          if (json is Map && json['v'] == _kVersion && json['owner'] is String && json['rows'] is Map) {
            _owner = json['owner'] as String;
            for (final e in (json['rows'] as Map).entries) {
              final v = e.value;
              if (e.key is String && v is Map && v['n'] is int && v['d'] is int) {
                _rows[e.key as String] = (n: v['n'] as int, d: v['d'] as int);
              }
            }
            valid = true;
          }
        } catch (_) {
          valid = false;
        }
        if (!valid) {
          _owner = null;
          _rows.clear();
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      appLogger.w('RecentRequests: row sizes unreadable', error: e);
      _owner = null;
      _rows.clear();
    }
    _loaded = true;
    appLogger.d('RecentRequests: row sizes loaded (${_rows.length} entries)');
  }

  /// Synchronous. `null` when not loaded yet, `0` when unknown, expired or owned by another account.
  int? sizeFor(SeerrSession s, MediaLibrary library) {
    if (!_loaded) return null;
    if (_owner != ownerOf(s)) return 0;
    final entry = _rows[library.globalKey];
    if (entry == null) return 0;
    if (_today() - entry.d > _kExpiryDays) return 0;
    return entry.n;
  }

  Future<void> remember(SeerrSession s, MediaLibrary library, int n) async {
    await ensureLoaded();
    final owner = ownerOf(s);
    final today = _today();
    var changed = false;
    if (_owner != owner) {
      _rows.clear();
      _owner = owner;
      changed = true;
    }
    final key = library.globalKey;
    final existing = _rows[key];
    if (existing == null || existing.n != n || today - existing.d > _kRefreshDays) changed = true;
    if (!changed) return;
    _rows.remove(key);
    _rows[key] = (n: n, d: today);
    _rows.removeWhere((_, v) => today - v.d > _kExpiryDays);
    while (_rows.length > _kMaxEntries) {
      _rows.remove(_rows.keys.first);
    }
    await _write();
  }

  Future<void> forget(SeerrSession s, MediaLibrary library) async {
    await ensureLoaded();
    final owner = ownerOf(s);
    var changed = false;
    if (_owner != owner) {
      _rows.clear();
      _owner = owner;
      changed = true;
    }
    if (_rows.remove(library.globalKey) != null) changed = true;
    if (!changed) return;
    await _write();
  }

  Future<void> _write() {
    final payload = jsonEncode({
      'v': _kVersion,
      'owner': _owner,
      'rows': {
        for (final e in _rows.entries) e.key: {'n': e.value.n, 'd': e.value.d},
      },
    });
    return _queue.run(() async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(payload, flush: true);
        await tmp.rename(file.path);
      } catch (e) {
        appLogger.w('RecentRequests: row sizes not saved', error: e);
      }
    });
  }
}
