// FORK: demandes-recentes-sans-saut — tests of the row size memory (temporary directory, fake clock)

import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/recent_requests/recent_requests_row_sizes.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';

SeerrSession _session({int userId = 7, String baseUrl = 'https://seerr.example.com'}) => SeerrSession(
  baseUrl: baseUrl,
  method: SeerrAuthMethod.local,
  identifier: 'a@b.c',
  secret: 'pw',
  cookie: 'cookie',
  userId: userId,
  permissions: SeerrPermission.admin,
  displayName: 'Alice',
  instanceLabel: 'Seerr',
  product: SeerrProduct.unknown,
  createdAt: 0,
);

MediaLibrary _lib(String id) =>
    MediaLibrary(id: id, backend: MediaBackend.plex, title: 'Series', kind: MediaKind.show, serverId: 'srvA');

void main() {
  late Directory dir;
  final memory = ForkRowSizeMemory.instance;
  final t0 = DateTime.utc(2026, 11, 28, 12);

  File file() => File('${dir.path}/popkino_recent_requests/$kRowSizesFileName');
  Map<String, dynamic> content() => jsonDecode(file().readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('row_sizes_test');
    ForkRowSizeMemory.debugDirectory = () async => dir;
    ForkRowSizeMemory.debugReset();
  });

  tearDown(() {
    ForkRowSizeMemory.debugDirectory = null;
    ForkRowSizeMemory.debugReset();
    dir.deleteSync(recursive: true);
  });

  test('round trip survives a reset', () async {
    await withClock(Clock.fixed(t0), () async {
      await memory.remember(_session(), _lib('1'), 7);
      ForkRowSizeMemory.debugReset();
      await memory.ensureLoaded();
      expect(memory.sizeFor(_session(), _lib('1')), 7);
    });
  });

  test('sizeFor is null before ensureLoaded', () async {
    expect(memory.isLoaded, isFalse);
    expect(memory.sizeFor(_session(), _lib('1')), isNull);
    await memory.ensureLoaded();
    expect(memory.isLoaded, isTrue);
    expect(memory.sizeFor(_session(), _lib('1')), 0);
  });

  test('another owner sees 0, then remember rewrites with the new owner only', () async {
    await withClock(Clock.fixed(t0), () async {
      await memory.remember(_session(), _lib('1'), 7);
      final other = _session(userId: 8);
      expect(memory.sizeFor(other, _lib('1')), 0);
      await memory.remember(other, _lib('2'), 3);
      final json = content();
      expect(json['owner'], ForkRowSizeMemory.ownerOf(other));
      expect((json['rows'] as Map).keys, [_lib('2').globalKey]);
    });
  });

  test('wrong version or corrupt JSON gives an empty table and deletes the file', () async {
    for (final body in ['{"v":2,"owner":"x","rows":{}}', 'not json{']) {
      ForkRowSizeMemory.debugReset();
      file().parent.createSync(recursive: true);
      file().writeAsStringSync(body);
      await memory.ensureLoaded();
      expect(memory.sizeFor(_session(), _lib('1')), 0);
      expect(file().existsSync(), isFalse);
    }
  });

  test('entries expire after 30 days', () async {
    await withClock(Clock.fixed(t0), () => memory.remember(_session(), _lib('1'), 5));
    await withClock(Clock.fixed(t0.add(const Duration(days: 29))), () async {
      expect(memory.sizeFor(_session(), _lib('1')), 5);
    });
    await withClock(Clock.fixed(t0.add(const Duration(days: 31))), () async {
      expect(memory.sizeFor(_session(), _lib('1')), 0);
    });
  });

  test('table is capped at 64 entries, oldest dropped', () async {
    await withClock(Clock.fixed(t0), () async {
      for (var i = 0; i < 65; i++) {
        await memory.remember(_session(), _lib('$i'), 4);
      }
      final rows = content()['rows'] as Map;
      expect(rows.length, 64);
      expect(rows.containsKey(_lib('0').globalKey), isFalse);
      expect(rows.containsKey(_lib('64').globalKey), isTrue);
    });
  });

  test('same value is not rewritten until 7 days have passed', () async {
    await withClock(Clock.fixed(t0), () => memory.remember(_session(), _lib('1'), 5));
    final past = DateTime(2020);
    file().setLastModifiedSync(past);
    await withClock(Clock.fixed(t0.add(const Duration(days: 3))), () => memory.remember(_session(), _lib('1'), 5));
    expect(file().lastModifiedSync(), past);
    await withClock(Clock.fixed(t0.add(const Duration(days: 8))), () => memory.remember(_session(), _lib('1'), 5));
    expect(file().lastModifiedSync().isAfter(past), isTrue);
  });

  test('forget of a missing entry writes nothing', () async {
    await withClock(Clock.fixed(t0), () async {
      await memory.remember(_session(), _lib('1'), 5);
      final past = DateTime(2020);
      file().setLastModifiedSync(past);
      await memory.forget(_session(), _lib('2'));
      expect(file().lastModifiedSync(), past);
      await memory.forget(_session(), _lib('1'));
      expect(content()['rows'], isEmpty);
    });
  });

  test('two remember calls without awaiting keep the second', () async {
    await withClock(Clock.fixed(t0), () async {
      final a = memory.remember(_session(), _lib('1'), 3);
      final b = memory.remember(_session(), _lib('1'), 9);
      await Future.wait([a, b]);
      expect(((content()['rows'] as Map)[_lib('1').globalKey] as Map)['n'], 9);
    });
  });

  test('file only holds v, owner and rows with n and d', () async {
    await withClock(Clock.fixed(t0), () => memory.remember(_session(), _lib('1'), 5));
    final json = content();
    expect(json.keys.toSet(), {'v', 'owner', 'rows'});
    final entry = (json['rows'] as Map).values.single as Map;
    expect(entry.keys.toSet(), {'n', 'd'});
  });
}
