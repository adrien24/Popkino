import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/update/apk_asset.dart';

Map<String, Object> a(String name) => {'name': name, 'browser_download_url': 'https://x/$name', 'size': 10};

void main() {
  test('Fire Stick picks armeabi-v7a', () {
    final r = selectApkAsset(
      [a('popkino-android-arm64-v8a-0.3.0.apk'), a('popkino-android-armeabi-v7a-0.3.0.apk')],
      supportedAbis: ['armeabi-v7a', 'armeabi'],
      installedTranche: 1,
    );
    expect(r?.abi, 'armeabi-v7a');
    expect(r?.url, 'https://x/popkino-android-armeabi-v7a-0.3.0.apk');
  });

  test('phone with tranche 2 picks arm64', () {
    final r = selectApkAsset(
      [a('popkino-android-armeabi-v7a-0.3.0.apk'), a('popkino-android-arm64-v8a-0.3.0.apk')],
      supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      installedTranche: 2,
    );
    expect(r?.abi, 'arm64-v8a');
  });

  test('tranche 2 without arm64 asset gives null', () {
    final r = selectApkAsset(
      [a('popkino-android-armeabi-v7a-0.3.0.apk')],
      supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      installedTranche: 2,
    );
    expect(r, isNull);
  });

  test('name without version accepted, tar.gz ignored', () {
    expect(
      selectApkAsset([a('popkino-android-arm64-v8a.apk')], supportedAbis: ['arm64-v8a'], installedTranche: 0)?.abi,
      'arm64-v8a',
    );
    expect(
      selectApkAsset([a('popkino-android-arm64-v8a.tar.gz')], supportedAbis: ['arm64-v8a'], installedTranche: 0),
      isNull,
    );
  });
}
