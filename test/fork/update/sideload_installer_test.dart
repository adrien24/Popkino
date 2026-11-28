import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/update/sideload_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('popkino/sideload_updater');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelSideloadInstaller installer;
  MethodCall? lastCall;

  void mock(Object? Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(
      channel,
      handler == null
          ? null
          : (c) async {
              lastCall = c;
              return handler(c);
            },
    );
  }

  setUp(() {
    installer = MethodChannelSideloadInstaller();
    lastCall = null;
  });
  tearDown(() => mock(null));

  test('canRequestInstalls', () async {
    mock((_) => true);
    expect(await installer.canRequestInstalls(), isTrue);
    mock((_) => null);
    expect(await installer.canRequestInstalls(), isFalse);
  });

  test('openInstallSettings maps every target', () async {
    final expected = {
      'appPermission': InstallSettingsTarget.appPermission,
      'unknownAppsList': InstallSettingsTarget.unknownAppsList,
      'developerOptions': InstallSettingsTarget.developerOptions,
      'security': InstallSettingsTarget.security,
      'settings': InstallSettingsTarget.settings,
      'none': InstallSettingsTarget.none,
      'weird': InstallSettingsTarget.none,
    };
    for (final e in expected.entries) {
      mock((_) => e.key);
      expect(await installer.openInstallSettings(), e.value, reason: e.key);
    }
  });

  test('availableBytes', () async {
    mock((_) => 12345);
    expect(await installer.availableBytes(), 12345);
  });

  test('inspectApk maps statuses and sends the path', () async {
    final expected = {
      'ok': ApkCheck.ok,
      'invalid': ApkCheck.invalid,
      'wrongPackage': ApkCheck.wrongPackage,
      'signatureMismatch': ApkCheck.signatureMismatch,
      'notNewer': ApkCheck.notNewer,
      'other': ApkCheck.invalid,
    };
    for (final e in expected.entries) {
      mock((_) => {'status': e.key, 'versionName': '1.2.3', 'versionCode': 42});
      final r = await installer.inspectApk('/x/a.apk');
      expect(r.status, e.value, reason: e.key);
      expect(r.versionName, '1.2.3');
      expect(r.versionCode, 42);
      expect(lastCall!.arguments, {'path': '/x/a.apk'});
    }
  });

  test('install maps every contract string', () async {
    final expected = {
      'installed': InstallOutcome.installed,
      'cancelled': InstallOutcome.cancelled,
      'permissionRequired': InstallOutcome.permissionRequired,
      'signatureMismatch': InstallOutcome.signatureMismatch,
      'notNewer': InstallOutcome.notNewer,
      'insufficientStorage': InstallOutcome.insufficientStorage,
      'invalid': InstallOutcome.invalid,
      'invalidPath': InstallOutcome.failed,
      'installerUnavailable': InstallOutcome.failed,
      'busy': InstallOutcome.failed,
      'failed:-110': InstallOutcome.failed,
    };
    for (final e in expected.entries) {
      mock((_) => e.key);
      expect(await installer.install('/x/a.apk'), e.value, reason: e.key);
      expect(lastCall!.arguments, {'path': '/x/a.apk'});
    }
  });

  test('MissingPluginException degrades gracefully', () async {
    mock(null);
    expect(await installer.canRequestInstalls(), isFalse);
    expect(await installer.openInstallSettings(), InstallSettingsTarget.none);
    expect(await installer.availableBytes(), isNull);
    expect((await installer.inspectApk('/x.apk')).status, ApkCheck.unavailable);
    expect(await installer.install('/x.apk'), InstallOutcome.unavailable);
  });
}
