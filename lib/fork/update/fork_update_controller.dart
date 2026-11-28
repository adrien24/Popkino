// FORK: bouton-mise-a-jour — app-global availability of a sideload update.
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;

import '../../utils/app_logger.dart';
import '../../utils/app_version.dart';
import '../../utils/media_server_http_client.dart';
import '../fork_identity.dart';
import 'apk_asset.dart';
import 'fork_release.dart';
import 'release_picker.dart';
import 'sideload_flags.dart';
import 'sideload_installer.dart';
import 'update_files.dart';

/// A verified APK left on disk by a previous run (`pending.json`), ready to install.
@immutable
class ForkPendingInstall {
  const ForkPendingInstall({required this.pending, required this.release, required this.apkPath});

  final ForkPendingUpdate pending;

  /// Minimal release rebuilt from the record: only version, tag and APK info are meaningful.
  final ForkRelease release;
  final String apkPath;
}

/// Knows whether a newer release is available. Never filters the skipped
/// version and applies no cool-down: those belong to the automatic dialog.
class ForkUpdateController extends ChangeNotifier {
  ForkUpdateController({
    MediaServerHttpClient? http,
    SideloadInstaller? installer,
    ForkUpdateFiles? files,
    Future<List<String>> Function()? supportedAbis,
    int Function()? abiTranche,
    Future<String> Function()? installedVersion,
  }) : _injectedHttp = http,
       _installer = installer ?? MethodChannelSideloadInstaller(),
       _files = files ?? ForkUpdateFiles(),
       _supportedAbis = supportedAbis ?? _deviceAbis,
       _abiTranche = abiTranche ?? currentAbiTranche,
       _installedVersion = installedVersion ?? _appVersion;

  /// Only reference this behind `kForkSideloadUpdates` / `ForkSideload.isSupported`,
  /// so the AOT compiler can drop it from store builds.
  static final ForkUpdateController instance = ForkUpdateController();

  static Future<List<String>> _deviceAbis() async => (await DeviceInfoPlugin().androidInfo).supportedAbis;

  static Future<String> _appVersion() async => (await AppVersion.current()).version ?? '0.0.0';

  static const _requestTimeout = Duration(seconds: 10);

  final MediaServerHttpClient? _injectedHttp;
  MediaServerHttpClient? _http;
  final SideloadInstaller _installer;
  final ForkUpdateFiles _files;
  final Future<List<String>> Function() _supportedAbis;
  final int Function() _abiTranche;
  final Future<String> Function() _installedVersion;

  final Set<String> _refusedTags = {};
  Future<void>? _checking;

  ForkRelease? available;
  ForkPendingInstall? pendingInstall;

  /// Set once the "resume" window has been shown for [pendingInstall].
  bool resumeConsumed = false;

  /// One run per process; concurrent callers share the same future. Never throws.
  Future<void> ensureChecked() => _checking ??= _runCheck();

  Future<void> _runCheck() async {
    try {
      if (!ForkSideload.isSupported) return;

      final installed = await _installedVersion();
      final pending = await _files.purge(installedVersion: installed);
      if (pending != null) {
        pendingInstall = await _toPendingInstall(pending);
        notifyListeners();
      }

      try {
        await _installer.canRequestInstalls();
      } on MissingPluginException {
        return;
      }

      await _fetch(installed);
    } catch (e, st) {
      appLogger.w('Update check failed', error: e, stackTrace: st);
    }
  }

  Future<ForkPendingInstall> _toPendingInstall(ForkPendingUpdate pending) async {
    final dir = await _files.directory();
    final release = ForkRelease(
      version: pending.version,
      tag: 'v${pending.version}',
      name: 'v${pending.version}',
      notes: '',
      htmlUrl: '',
      publishedAt: '',
      isPrerelease: false,
      apk: ForkApkAsset(name: pending.fileName, url: '', size: pending.size, abi: pending.abi),
    );
    return ForkPendingInstall(
      pending: pending,
      release: release,
      apkPath: p.join(dir.path, p.basename(pending.fileName)),
    );
  }

  Future<ForkRelease?> _fetch([String? installed]) async {
    installed ??= await _installedVersion();
    final client = _http ??= _injectedHttp ?? MediaServerHttpClient();
    final response = await client.get(
      'https://api.github.com/repos/${ForkIdentity.githubRepo}/releases',
      queryParameters: {'per_page': 20},
      headers: {'Accept': 'application/vnd.github+json'},
      timeout: _requestTimeout,
    );
    throwIfHttpError(response);
    final data = response.data;
    if (data is! List) throw const FormatException('Unexpected releases payload');

    var picked = pickForkRelease(
      data,
      installedVersion: installed,
      supportedAbis: await _supportedAbis(),
      installedTranche: _abiTranche(),
    );
    if (picked != null && _refusedTags.contains(picked.tag)) picked = null;

    final changed = picked?.tag != available?.tag || picked?.apk.url != available?.apk.url;
    available = picked;
    if (changed) notifyListeners();
    return picked;
  }

  /// Manual check: always issues a new request.
  Future<ForkRelease?> refresh({bool throwOnFailure = false}) async {
    try {
      return await _fetch();
    } catch (e, st) {
      appLogger.w('Manual update check failed', error: e, stackTrace: st);
      if (throwOnFailure) rethrow;
      return available;
    }
  }

  /// The installer refused [tag] as not newer: hide it until the next launch.
  void markRefused(String tag) {
    _refusedTags.add(tag);
    if (available?.tag == tag) {
      available = null;
      notifyListeners();
    }
  }

  void clearPending() {
    if (pendingInstall == null) return;
    pendingInstall = null;
    notifyListeners();
  }
}
