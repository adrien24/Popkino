// FORK: bouton-mise-a-jour — picks the APK asset matching the device ABI.
import 'dart:ffi' show Abi;

import '../fork_identity.dart';
import 'fork_release.dart';

final RegExp _assetPattern = RegExp(
  '^${ForkIdentity.appSlug}-android-(arm64-v8a|armeabi-v7a|x86_64)(-\\d+\\.\\d+\\.\\d+)?\\.apk\$',
);

/// versionCode tranche per ABI (split-per-abi adds 1, 2 or 4 x 1000 to the code).
const Map<String, int> _abiTranche = {'armeabi-v7a': 1, 'arm64-v8a': 2, 'x86_64': 4};

/// Returns the first asset, following [supportedAbis] order, whose tranche is
/// at least [installedTranche] (never downgrade to a lesser ABI build).
ForkApkAsset? selectApkAsset(List<Map> assets, {required List<String> supportedAbis, required int installedTranche}) {
  final byAbi = <String, ForkApkAsset>{};
  for (final a in assets) {
    final name = a['name'];
    final url = a['browser_download_url'];
    final size = a['size'];
    if (name is! String || url is! String || size is! int) continue;
    final m = _assetPattern.firstMatch(name);
    if (m == null) continue;
    final abi = m.group(1)!;
    byAbi.putIfAbsent(abi, () => ForkApkAsset(name: name, url: url, size: size, abi: abi));
  }
  for (final abi in supportedAbis) {
    final tranche = _abiTranche[abi];
    if (tranche == null || tranche < installedTranche) continue;
    final asset = byAbi[abi];
    if (asset != null) return asset;
  }
  return null;
}

/// Tranche of the running process ABI, or 0 when unknown.
int currentAbiTranche() {
  final abi = Abi.current();
  if (abi == Abi.androidArm) return 1;
  if (abi == Abi.androidArm64) return 2;
  if (abi == Abi.androidX64) return 4;
  return 0;
}
