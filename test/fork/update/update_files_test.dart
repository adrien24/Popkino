import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plezy/fork/update/fork_release.dart';
import 'package:plezy/fork/update/update_files.dart';

ForkRelease release(String version, {String abi = 'armeabi-v7a'}) => ForkRelease(
  version: version,
  tag: 'v$version',
  name: version,
  notes: '',
  htmlUrl: 'https://x',
  publishedAt: '2026-01-01T00:00:00Z',
  isPrerelease: false,
  apk: ForkApkAsset(name: 'a.apk', url: 'https://x/a.apk', size: 10, abi: abi),
);

void main() {
  late Directory dir;
  late ForkUpdateFiles files;
  final now = DateTime.utc(2026, 5, 1, 12);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('upd_files');
    files = ForkUpdateFiles(root: dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<File> apk(String version, int bytes) async {
    final f = await files.apkFile(release(version));
    await f.writeAsBytes(List.filled(bytes, 1));
    return f;
  }

  Future<void> pending(String version, int size, {DateTime? at}) async {
    final f = await files.apkFile(release(version));
    await files.writePending(
      version: version,
      abi: 'armeabi-v7a',
      versionCode: 1,
      size: size,
      fileName: p.basename(f.path),
      now: at ?? now,
    );
  }

  test('file names', () async {
    expect(p.basename((await files.apkFile(release('0.3.0'))).path), 'popkino-0.3.0-armeabi-v7a.apk');
    expect(p.basename((await files.partFile(release('0.3.0'))).path), 'popkino-0.3.0-armeabi-v7a.apk.part');
  });

  test('writePending / readPending round trip, no temp file left', () async {
    await pending('0.3.0', 10);
    final r = await files.readPending();
    expect(r?.version, '0.3.0');
    expect(r?.size, 10);
    expect(r?.createdAt, now);
    expect(File(p.join(dir.path, 'pending.json.tmp')).existsSync(), isFalse);
  });

  test('purge keeps a valid record and its APK', () async {
    await apk('0.3.0', 10);
    await pending('0.3.0', 10);
    final r = await files.purge(installedVersion: '0.2.0', now: now.add(const Duration(hours: 1)));
    expect(r?.version, '0.3.0');
    expect(dir.listSync().length, 2);
  });

  test('purge removes every .part', () async {
    await File(p.join(dir.path, 'x.apk.part')).writeAsString('x');
    expect(await files.purge(installedVersion: '0.2.0', now: now), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('purge removes an APK without record', () async {
    await apk('0.3.0', 10);
    expect(await files.purge(installedVersion: '0.2.0', now: now), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('purge removes record and APK when version is not newer', () async {
    await apk('0.3.0', 10);
    await pending('0.3.0', 10);
    expect(await files.purge(installedVersion: '0.3.0', now: now), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('purge removes record and APK when size differs', () async {
    await apk('0.3.0', 9);
    await pending('0.3.0', 10);
    expect(await files.purge(installedVersion: '0.2.0', now: now), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('purge removes record and APK older than 24 h', () async {
    await apk('0.3.0', 10);
    await pending('0.3.0', 10);
    expect(await files.purge(installedVersion: '0.2.0', now: now.add(const Duration(hours: 25))), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('corrupted record is treated as absent', () async {
    await apk('0.3.0', 10);
    await File(p.join(dir.path, 'pending.json')).writeAsString('{not json');
    expect(await files.readPending(), isNull);
    expect(await files.purge(installedVersion: '0.2.0', now: now), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('deleteAll empties the directory', () async {
    await apk('0.3.0', 10);
    await pending('0.3.0', 10);
    await files.deleteAll();
    expect(dir.listSync(), isEmpty);
  });
}
