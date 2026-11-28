import 'package:plezy/fork/update/sideload_installer.dart';

/// Programmable [SideloadInstaller]: queue answers, inspect recorded calls.
/// When a queue is empty the last-resort default is returned.
class FakeSideloadInstaller implements SideloadInstaller {
  final List<String> calls = [];

  final List<bool> canRequestInstallsAnswers = [];
  final List<InstallSettingsTarget> openInstallSettingsAnswers = [];
  final List<int?> availableBytesAnswers = [];
  final List<ApkInspection> inspectApkAnswers = [];
  final List<InstallOutcome> installAnswers = [];

  @override
  Future<bool> canRequestInstalls() async {
    calls.add('canRequestInstalls');
    return canRequestInstallsAnswers.isEmpty ? false : canRequestInstallsAnswers.removeAt(0);
  }

  @override
  Future<InstallSettingsTarget> openInstallSettings() async {
    calls.add('openInstallSettings');
    return openInstallSettingsAnswers.isEmpty ? InstallSettingsTarget.none : openInstallSettingsAnswers.removeAt(0);
  }

  @override
  Future<int?> availableBytes() async {
    calls.add('availableBytes');
    return availableBytesAnswers.isEmpty ? null : availableBytesAnswers.removeAt(0);
  }

  @override
  Future<ApkInspection> inspectApk(String path) async {
    calls.add('inspectApk:$path');
    return inspectApkAnswers.isEmpty
        ? (status: ApkCheck.ok, versionName: null, versionCode: null)
        : inspectApkAnswers.removeAt(0);
  }

  @override
  Future<InstallOutcome> install(String path) async {
    calls.add('install:$path');
    return installAnswers.isEmpty ? InstallOutcome.installed : installAnswers.removeAt(0);
  }
}
