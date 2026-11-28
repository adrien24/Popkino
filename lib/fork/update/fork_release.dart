// FORK: bouton-mise-a-jour — immutable models of a published release.
import 'package:flutter/foundation.dart';

@immutable
class ForkApkAsset {
  const ForkApkAsset({required this.name, required this.url, required this.size, required this.abi});

  final String name;

  /// `browser_download_url` of the GitHub asset.
  final String url;
  final int size;
  final String abi;
}

@immutable
class ForkRelease {
  const ForkRelease({
    required this.version,
    required this.tag,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.publishedAt,
    required this.isPrerelease,
    required this.apk,
  });

  final String version;
  final String tag;
  final String name;

  /// Release notes, already converted to plain text.
  final String notes;
  final String htmlUrl;
  final String publishedAt;
  final bool isPrerelease;
  final ForkApkAsset apk;
}
