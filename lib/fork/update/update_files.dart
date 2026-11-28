// FORK: bouton-mise-a-jour — on-disk state of a downloaded update (APK, .part, pending.json).
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../fork_identity.dart';
import 'fork_release.dart';
import 'release_picker.dart';
import 'sideload_installer.dart';

/// Record of a verified APK waiting to be installed (`pending.json`).
class ForkPendingUpdate {
  const ForkPendingUpdate({
    required this.version,
    required this.abi,
    required this.versionCode,
    required this.size,
    required this.fileName,
    required this.createdAt,
  });

  final String version;
  final String abi;
  final int versionCode;
  final int size;
  final String fileName;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'version': version,
    'abi': abi,
    'versionCode': versionCode,
    'size': size,
    'fileName': fileName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Returns null when [json] is not a complete record.
  static ForkPendingUpdate? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final abi = json['abi'];
    final versionCode = json['versionCode'];
    final size = json['size'];
    final fileName = json['fileName'];
    final createdAt = json['createdAt'];
    if (version is! String || abi is! String || versionCode is! int || size is! int) return null;
    if (fileName is! String || createdAt is! String) return null;
    final created = DateTime.tryParse(createdAt);
    if (created == null) return null;
    return ForkPendingUpdate(
      version: version,
      abi: abi,
      versionCode: versionCode,
      size: size,
      fileName: fileName,
      createdAt: created,
    );
  }
}

/// Owns the `updates/` directory: file names, `pending.json` and cleanup.
class ForkUpdateFiles {
  /// [root] overrides the directory (tests); default is `<temp>/updates`.
  ForkUpdateFiles({this.root});

  static const pendingFileName = 'pending.json';
  static const maxPendingAge = Duration(hours: 24);

  final Directory? root;

  Future<Directory> directory() async {
    final dir = root ?? Directory(p.join((await getTemporaryDirectory()).path, SideloadInstaller.updatesDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> apkFile(ForkRelease release) async =>
      File(p.join((await directory()).path, '${ForkIdentity.appSlug}-${release.version}-${release.apk.abi}.apk'));

  Future<File> partFile(ForkRelease release) async => File('${(await apkFile(release)).path}.part');

  Future<File> _pendingFile() async => File(p.join((await directory()).path, pendingFileName));

  Future<ForkPendingUpdate> writePending({
    required String version,
    required String abi,
    required int versionCode,
    required int size,
    required String fileName,
    DateTime? now,
  }) async {
    final pending = ForkPendingUpdate(
      version: version,
      abi: abi,
      versionCode: versionCode,
      size: size,
      fileName: fileName,
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    final target = await _pendingFile();
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(jsonEncode(pending.toJson()), flush: true);
    await tmp.rename(target.path);
    return pending;
  }

  /// Returns null when the record is absent or corrupted.
  Future<ForkPendingUpdate?> readPending() async {
    try {
      final file = await _pendingFile();
      if (!await file.exists()) return null;
      return ForkPendingUpdate.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// Removes partial downloads, orphan APKs and stale records. Returns the
  /// record that is still valid, or null.
  Future<ForkPendingUpdate?> purge({required String installedVersion, DateTime? now}) async {
    final dir = await directory();
    var pending = await readPending();
    File? pendingApk;
    if (pending != null) {
      // A file name with separators would point outside the directory.
      pendingApk = File(p.join(dir.path, p.basename(pending.fileName)));
      final age = (now ?? DateTime.now()).toUtc().difference(pending.createdAt.toUtc());
      final valid =
          compareForkVersions(pending.version, installedVersion) > 0 &&
          age <= maxPendingAge &&
          await pendingApk.exists() &&
          await pendingApk.length() == pending.size;
      if (!valid) {
        pending = null;
      }
    }
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final keep = pending != null && (name == pendingFileName || name == p.basename(pending.fileName));
      if (keep) continue;
      if (name.endsWith('.part') ||
          name.endsWith('.apk') ||
          name == pendingFileName ||
          name == '$pendingFileName.tmp') {
        await _tryDelete(entity);
      }
    }
    return pending;
  }

  Future<void> deleteAll() async {
    final dir = await directory();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) await _tryDelete(entity);
    }
  }

  Future<void> _tryDelete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Best effort: the next purge retries.
    }
  }
}
