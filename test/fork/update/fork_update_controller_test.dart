import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/fork/fork_identity.dart';
import 'package:plezy/fork/update/fork_update_controller.dart';
import 'package:plezy/fork/update/sideload_flags.dart';
import 'package:plezy/fork/update/sideload_installer.dart';
import 'package:plezy/fork/update/update_files.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'fake_sideload_installer.dart';

class _ThrowingInstaller extends FakeSideloadInstaller {
  @override
  Future<bool> canRequestInstalls() async {
    calls.add('canRequestInstalls');
    throw MissingPluginException();
  }
}

List<Map<String, Object?>> _releases(String tag) {
  final v = tag.substring(1);
  return [
    {
      'tag_name': tag,
      'draft': false,
      'prerelease': true,
      'name': 'Release $tag',
      'body': 'notes',
      'html_url': 'https://example.test/$tag',
      'published_at': '2026-01-01T00:00:00Z',
      'assets': [
        {
          'name': '${ForkIdentity.appSlug}-android-arm64-v8a-$v.apk',
          'browser_download_url': 'https://x/$tag.apk',
          'size': 10,
        },
      ],
    },
  ];
}

void main() {
  late Directory tmp;
  late FakeSideloadInstaller installer;
  late List<Uri> requests;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fork_update_ctrl');
    installer = FakeSideloadInstaller();
    requests = [];
    ForkSideload.debugForceSupported = true;
    ForkSideload.debugIsAndroid = true;
  });

  tearDown(() {
    ForkSideload.debugForceSupported = false;
    ForkSideload.debugIsAndroid = null;
    tmp.deleteSync(recursive: true);
  });

  ForkUpdateController build(Future<http.Response> Function(http.Request) handler, {SideloadInstaller? inst}) {
    return ForkUpdateController(
      http: MediaServerHttpClient(
        client: MockClient((r) {
          requests.add(r.url);
          return handler(r);
        }),
      ),
      installer: inst ?? installer,
      files: ForkUpdateFiles(root: tmp),
      supportedAbis: () async => ['arm64-v8a'],
      abiTranche: () => 2,
      installedVersion: () async => '0.1.0',
    );
  }

  http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  test('two ensureChecked calls issue one request, on the expected URL', () async {
    final c = build((_) async => ok(_releases('v0.2.0')));
    await Future.wait([c.ensureChecked(), c.ensureChecked()]);
    await c.ensureChecked();
    expect(requests, hasLength(1));
    expect(requests.single.path, '/repos/${ForkIdentity.githubRepo}/releases');
    expect(requests.single.query, 'per_page=20');
    expect(c.available?.version, '0.2.0');
  });

  test('network failure, HTTP 500 and invalid JSON leave available null without throwing', () async {
    final handlers = <Future<http.Response> Function(http.Request)>[
      (_) async => throw const SocketException('down'),
      (_) async => http.Response('boom', 500),
      (_) async => http.Response('not json', 200, headers: {'content-type': 'application/json'}),
    ];
    for (final h in handlers) {
      final c = build(h);
      await c.ensureChecked();
      expect(c.available, isNull);
    }
  });

  test('unavailable channel: no request', () async {
    final c = build((_) async => ok(_releases('v0.2.0')), inst: _ThrowingInstaller());
    await c.ensureChecked();
    expect(requests, isEmpty);
    expect(c.available, isNull);
  });

  test('unsupported platform: nothing is called', () async {
    ForkSideload.debugForceSupported = false;
    final c = build((_) async => ok(_releases('v0.2.0')));
    await c.ensureChecked();
    expect(installer.calls, isEmpty);
    expect(requests, isEmpty);
  });

  test('a skipped version stays in available (controller does not filter it)', () async {
    final c = build((_) async => ok(_releases('v0.2.0')));
    await c.ensureChecked();
    expect(c.available, isNotNull);
  });

  test('valid pending record is exposed before the network answer', () async {
    final files = ForkUpdateFiles(root: tmp);
    final apk = File('${tmp.path}/popkino-0.2.0-arm64-v8a.apk')..writeAsBytesSync(List.filled(10, 1));
    await files.writePending(
      version: '0.2.0',
      abi: 'arm64-v8a',
      versionCode: 2002,
      size: 10,
      fileName: 'popkino-0.2.0-arm64-v8a.apk',
    );
    final c = build((_) async {
      return ok(<Object>[]);
    });
    ForkPendingInstall? atRequest;
    c.addListener(() => atRequest ??= c.pendingInstall);
    await c.ensureChecked();
    expect(atRequest?.release.version, '0.2.0');
    expect(atRequest?.apkPath, apk.path);
    expect(c.pendingInstall, isNotNull);
    c.clearPending();
    expect(c.pendingInstall, isNull);
  });

  test('markRefused hides the release until next launch', () async {
    final c = build((_) async => ok(_releases('v0.2.0')));
    await c.ensureChecked();
    var notified = 0;
    c.addListener(() => notified++);
    c.markRefused('v0.2.0');
    expect(c.available, isNull);
    expect(notified, 1);
    expect(await c.refresh(), isNull);
  });

  test('refresh always sends a new request and can throw', () async {
    var fail = false;
    final c = build((_) async => fail ? http.Response('x', 500) : ok(_releases('v0.2.0')));
    await c.ensureChecked();
    await c.refresh();
    expect(requests, hasLength(2));
    fail = true;
    expect(await c.refresh(), isNotNull);
    await expectLater(c.refresh(throwOnFailure: true), throwsA(anything));
  });
}
