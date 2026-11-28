// FORK: bouton-mise-a-jour — chooses the release to propose from the GitHub list.
import 'apk_asset.dart';
import 'fork_release.dart';

final RegExp _tagPattern = RegExp(r'^v?\d+\.\d+\.\d+$');

List<int> _fields(String v) {
  var s = v.trim();
  if (s.startsWith('v')) s = s.substring(1);
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  return s.split('.').map((p) => int.tryParse(p) ?? 0).toList();
}

/// Numeric field-by-field comparison, ignoring `+N` and a leading `v`.
int compareForkVersions(String a, String b) {
  final fa = _fields(a);
  final fb = _fields(b);
  final n = fa.length > fb.length ? fa.length : fb.length;
  for (var i = 0; i < n; i++) {
    final x = i < fa.length ? fa[i] : 0;
    final y = i < fb.length ? fb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Picks the highest published version (pre-releases included, drafts and
/// invalid tags ignored). Returns null when it is not newer than
/// [installedVersion] or has no APK for this device: never falls back to an
/// intermediate release.
ForkRelease? pickForkRelease(
  List<Object?> json, {
  required String installedVersion,
  required List<String> supportedAbis,
  required int installedTranche,
}) {
  Map? best;
  String? bestVersion;
  for (final item in json) {
    if (item is! Map) continue;
    if (item['draft'] == true) continue;
    final tag = item['tag_name'];
    if (tag is! String || !_tagPattern.hasMatch(tag)) continue;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (bestVersion == null || compareForkVersions(version, bestVersion) > 0) {
      best = item;
      bestVersion = version;
    }
  }
  if (best == null || bestVersion == null) return null;
  if (compareForkVersions(bestVersion, installedVersion) <= 0) return null;

  final rawAssets = best['assets'];
  final assets = rawAssets is List ? rawAssets.whereType<Map>().toList() : <Map>[];
  final apk = selectApkAsset(assets, supportedAbis: supportedAbis, installedTranche: installedTranche);
  if (apk == null) return null;

  final tag = best['tag_name'] as String;
  return ForkRelease(
    version: bestVersion,
    tag: tag,
    name: (best['name'] as String?)?.trim().isNotEmpty == true ? best['name'] as String : tag,
    notes: releaseNotesToPlainText((best['body'] as String?) ?? ''),
    htmlUrl: (best['html_url'] as String?) ?? '',
    publishedAt: (best['published_at'] as String?) ?? '',
    isPrerelease: best['prerelease'] == true,
    apk: apk,
  );
}

/// Minimal Markdown to plain text conversion for release notes.
String releaseNotesToPlainText(String md) {
  var s = md.replaceAll('\r\n', '\n');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!);
  s = s.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
  s = s.replaceAll(RegExp(r'^[ \t]*#{1,6}[ \t]*', multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r'^([ \t]*)[-*][ \t]+', multiLine: true), (m) => '${m.group(1)}• ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
