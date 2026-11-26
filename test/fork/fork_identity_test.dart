// FORK: tests de l'identité Popkino (valeurs Dart)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/fork/fork_identity.dart';
import 'package:plezy/models/jellyfin/jellyfin_display_preferences.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/services/deep_links/deep_link.dart';
import 'package:plezy/services/external_player_service.dart';
import 'package:plezy/services/jellyfin_auth_header.dart';
import 'package:plezy/services/plex_auth_service.dart';
import 'package:plezy/services/update_service.dart';
import 'package:plezy/utils/device_identity.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    PackageInfo.setMockInitialValues(
      appName: 'Popkino',
      packageName: 'io.github.adrien24.popkino',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('the identity constants match the identity table', () {
    expect(ForkIdentity.appName, 'Popkino');
    expect(ForkIdentity.appSlug, 'popkino');
    expect(ForkIdentity.urlScheme, 'popkino');
    expect(ForkIdentity.githubRepo, 'adrien24/popkino');
  });

  test('Plex client headers announce Popkino', () async {
    final config = await PlexConfig.create(baseUrl: 'http://plex.local:32400', clientIdentifier: 'cid');
    expect(config.headers['X-Plex-Product'], ForkIdentity.appName);
  });

  test('plex.tv PIN requests announce Popkino', () async {
    late http.Request captured;
    final client = MediaServerHttpClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'id': 1, 'code': 'ABCD'}), 201, headers: {'content-type': 'application/json'});
      }),
    );
    final auth = PlexAuthService.forTesting(http: client);
    addTearDown(auth.dispose);

    await auth.createPin();

    expect(captured.headers['X-Plex-Product'], ForkIdentity.appName);
    expect(auth.getAuthUrl('ABCD'), contains('product%5D=${ForkIdentity.appName}'));
  });

  test('the Jellyfin client name and display-preferences namespace are Popkino', () {
    expect(jellyfinClientName(const DeviceIdentity(platform: 'Linux')), 'Popkino Linux');
    expect(jellyfinClientName(const DeviceIdentity(platform: 'Android', isTv: true)), 'Popkino Android TV');
    expect(jellyfinClientName(const DeviceIdentity(platform: '')), ForkIdentity.appName);
    expect(JellyfinDisplayPreferences.client, ForkIdentity.appName);
  });

  test('deep links use the popkino scheme only', () {
    expect(DeepLink.scheme, 'popkino');
    expect(DeepLink.tryParse('plezy://open'), isNull);
    expect(DeepLink.tryParse('popkino://open'), isNotNull);
  });

  test('external player return links use the popkino scheme', () {
    final links = ExternalPlayerService.returnLinks('s1');
    expect(links.success.toString(), 'popkino://external-player/success/s1');
    expect(links.cancel.scheme, 'popkino');
    expect(links.error.scheme, 'popkino');
  });

  group('update check', () {
    Future<(Map<String, dynamic>?, Uri)> check(String tag) async {
      late Uri requested;
      final client = MediaServerHttpClient(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({'tag_name': tag, 'html_url': 'https://example.com', 'published_at': '2026-01-01'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.close);
      final result = await UpdateService.debugPerformUpdateCheck(
        respectCooldown: false,
        client: client,
        throwOnFailure: true,
      );
      return (result, requested);
    }

    test('queries the Popkino repository and sees 1.0.1 as newer than 1.0.0', () async {
      final (result, url) = await check('1.0.1');
      expect(url.toString(), 'https://api.github.com/repos/adrien24/popkino/releases/latest');
      expect(result?['hasUpdate'], isTrue);
      expect(result?['latestVersion'], '1.0.1');
    });
  });
}
