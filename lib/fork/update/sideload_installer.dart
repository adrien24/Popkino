import 'package:flutter/services.dart';

import '../../utils/app_logger.dart';

/// Result of the native APK inspection (package, signers, version code).
enum ApkCheck { ok, invalid, wrongPackage, signatureMismatch, notNewer, unavailable }

/// Result of handing the APK to the system installer.
enum InstallOutcome {
  installed,
  cancelled,
  permissionRequired,
  signatureMismatch,
  notNewer,
  insufficientStorage,
  invalid,
  unavailable,
  failed,
}

/// Settings screen that was actually opened by [SideloadInstaller.openInstallSettings].
enum InstallSettingsTarget { appPermission, unknownAppsList, developerOptions, security, settings, none }

typedef ApkInspection = ({ApkCheck status, String? versionName, int? versionCode});

/// Dart side of the native `popkino/sideload_updater` channel. Only registered in
/// sideload builds: elsewhere every call degrades to "unavailable".
abstract interface class SideloadInstaller {
  /// Directory name (under the temporary directory) holding downloaded APKs.
  static const updatesDirName = 'updates';

  Future<bool> canRequestInstalls();
  Future<InstallSettingsTarget> openInstallSettings();

  /// Free bytes on the cache partition, or null when unknown.
  Future<int?> availableBytes();
  Future<ApkInspection> inspectApk(String path);
  Future<InstallOutcome> install(String path);
}

class MethodChannelSideloadInstaller implements SideloadInstaller {
  MethodChannelSideloadInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('popkino/sideload_updater');

  final MethodChannel _channel;

  @override
  Future<bool> canRequestInstalls() async {
    try {
      return await _channel.invokeMethod<bool>('canRequestInstalls') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<InstallSettingsTarget> openInstallSettings() async {
    try {
      final result = await _channel.invokeMethod<String>('openInstallSettings');
      return switch (result) {
        'appPermission' => InstallSettingsTarget.appPermission,
        'unknownAppsList' => InstallSettingsTarget.unknownAppsList,
        'developerOptions' => InstallSettingsTarget.developerOptions,
        'security' => InstallSettingsTarget.security,
        'settings' => InstallSettingsTarget.settings,
        _ => InstallSettingsTarget.none,
      };
    } on MissingPluginException {
      return InstallSettingsTarget.none;
    }
  }

  @override
  Future<int?> availableBytes() async {
    try {
      return await _channel.invokeMethod<int>('availableBytes');
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<ApkInspection> inspectApk(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('inspectApk', {'path': path});
      final status = switch (result?['status']) {
        'ok' => ApkCheck.ok,
        'wrongPackage' => ApkCheck.wrongPackage,
        'signatureMismatch' => ApkCheck.signatureMismatch,
        'notNewer' => ApkCheck.notNewer,
        _ => ApkCheck.invalid,
      };
      final code = result?['versionCode'];
      return (
        status: status,
        versionName: result?['versionName'] as String?,
        versionCode: code is num ? code.toInt() : null,
      );
    } on MissingPluginException {
      return (status: ApkCheck.unavailable, versionName: null, versionCode: null);
    }
  }

  @override
  Future<InstallOutcome> install(String path) async {
    try {
      final result = await _channel.invokeMethod<String>('install', {'path': path});
      switch (result) {
        case 'installed':
          return InstallOutcome.installed;
        case 'cancelled':
          return InstallOutcome.cancelled;
        case 'permissionRequired':
          return InstallOutcome.permissionRequired;
        case 'signatureMismatch':
          return InstallOutcome.signatureMismatch;
        case 'notNewer':
          return InstallOutcome.notNewer;
        case 'insufficientStorage':
          return InstallOutcome.insufficientStorage;
        case 'invalid':
          return InstallOutcome.invalid;
        default:
          // invalidPath, installerUnavailable, busy, failed:<code>, or anything unexpected.
          appLogger.w('Sideload install failed: $result');
          return InstallOutcome.failed;
      }
    } on MissingPluginException {
      return InstallOutcome.unavailable;
    }
  }
}
