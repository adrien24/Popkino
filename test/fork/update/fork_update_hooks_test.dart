import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/fork/fork_identity.dart';
import 'package:plezy/fork/update/fork_update_controller.dart';
import 'package:plezy/fork/update/fork_update_hooks.dart';
import 'package:plezy/fork/update/sideload_flags.dart';
import 'package:plezy/fork/update/update_files.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/update_service.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import '../../test_helpers/prefs.dart';
import 'fake_sideload_installer.dart';

void main() {
  late Directory tmp;
  late List<Uri> requests;
  late bool fail;

  setUp(() {
    resetSharedPreferencesForTest();
    PackageInfo.setMockInitialValues(
      appName: 'Popkino',
      packageName: 'com.test',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    tmp = Directory.systemTemp.createTempSync('fork_update_hooks');
    requests = [];
    fail = false;
    ForkSideload.debugForceSupported = true;
    ForkSideload.debugIsAndroid = true;
    final installer = FakeSideloadInstaller();
    ForkUpdateHooks.debugController = ForkUpdateController(
      http: MediaServerHttpClient(
        client: MockClient((r) async {
          requests.add(r.url);
          if (fail) return http.Response('boom', 500);
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'v0.2.0',
                'draft': false,
                'prerelease': true,
                'name': 'Release',
                'body': 'notes',
                'html_url': 'https://example.test/v0.2.0',
                'published_at': '2026-01-01T00:00:00Z',
                'assets': [
                  {
                    'name': '${ForkIdentity.appSlug}-android-arm64-v8a-0.2.0.apk',
                    'browser_download_url': 'https://x/a.apk',
                    'size': 10,
                  },
                ],
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
      installer: installer..canRequestInstallsAnswers.add(true),
      files: ForkUpdateFiles(root: tmp),
      supportedAbis: () async => ['arm64-v8a'],
      abiTranche: () => 2,
      installedVersion: () async => '0.1.0',
    );
  });

  tearDown(() {
    ForkSideload.debugForceSupported = false;
    ForkSideload.debugIsAndroid = null;
    ForkUpdateHooks.debugController = null;
    tmp.deleteSync(recursive: true);
  });

  final unusedClient = MediaServerHttpClient(client: MockClient((_) async => http.Response('{}', 404)));

  test('unsupported: performCheck returns null synchronously', () {
    ForkSideload.debugForceSupported = false;
    expect(ForkUpdateHooks.performCheck('0.1.0', startup: true), isNull);
  });

  test('startup check returns the pre-release map from /releases?per_page=20', () async {
    final result = await UpdateService.debugPerformUpdateCheck(respectCooldown: true, client: unusedClient);
    expect(result, isNotNull);
    expect(result!['hasUpdate'], true);
    expect(result['currentVersion'], '0.1.0');
    expect(result['latestVersion'], '0.2.0');
    expect(result['releaseUrl'], 'https://example.test/v0.2.0');
    expect(result['releaseName'], 'Release');
    expect(result['releaseNotes'], 'notes');
    expect(result['publishedAt'], '2026-01-01T00:00:00Z');
    expect(result['forkRelease'], isNotNull);
    expect(requests.single.path, '/repos/${ForkIdentity.githubRepo}/releases');
    expect(requests.single.query, 'per_page=20');
  });

  test('skipped version: null at startup, returned by a manual check', () async {
    await UpdateService.skipVersion('0.2.0');
    expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: true, client: unusedClient), isNull);
    final manual = await UpdateService.debugPerformUpdateCheck(
      respectCooldown: false,
      client: unusedClient,
      throwOnFailure: true,
    );
    expect(manual?['latestVersion'], '0.2.0');
    final prefs = await BaseSharedPreferencesService.sharedCache();
    expect(prefs.getString('update_skipped_version'), '0.2.0');
  });

  test('manual check failure throws', () async {
    fail = true;
    await expectLater(
      UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: unusedClient, throwOnFailure: true),
      throwsA(anything),
    );
  });
}
