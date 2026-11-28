import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the one-line hooks into upstream files (D11): a merge that drops one
/// must fail here instead of silently disabling the feature.
void main() {
  test('update_service.dart calls ForkUpdateHooks.performCheck(', () {
    final source = File('lib/services/update_service.dart').readAsStringSync();
    expect(source, contains('ForkUpdateHooks.performCheck('));
  });

  test('performCheck starts with the ForkSideload.isSupported guard', () {
    final source = File('lib/fork/update/fork_update_hooks.dart').readAsStringSync();
    final start = source.indexOf('performCheck(');
    expect(start, isNonNegative);
    final body = source.substring(source.indexOf(') {', start) + 3).trimLeft();
    expect(body, startsWith('if (!ForkSideload.isSupported) return null;'));
  });

  test('discover_screen.dart calls forkUpdateAction(', () {
    expect(File('lib/screens/discover_screen.dart').readAsStringSync(), contains('forkUpdateAction('));
  });

  test('update_dialog.dart calls ForkUpdateHooks.showDialog(', () {
    expect(File('lib/utils/update_dialog.dart').readAsStringSync(), contains('ForkUpdateHooks.showDialog('));
  });

  // main.dart is compared with whitespace collapsed: `dart format` may wrap the provider over several lines.
  String normalized(String source) => source.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'\(\s+'), '(');

  final guardedProvider = RegExp(
    r'if \(kForkSideloadUpdates\) ChangeNotifierProvider<ForkUpdateController>\.value\( ?value: ForkUpdateController\.instance,? ?\)',
  );

  test('main.dart provides the controller behind kForkSideloadUpdates', () {
    final source = normalized(File('lib/main.dart').readAsStringSync());
    expect(source, contains('if (kForkSideloadUpdates) ChangeNotifierProvider<ForkUpdateController>'));
    expect(guardedProvider.hasMatch(source), isTrue);
  });

  test('ForkUpdateController.instance is only used in lib/fork/update/ and the guarded main.dart provider', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.startsWith('lib/fork/update/')) continue;
      final source = entity.readAsStringSync();
      final total = 'ForkUpdateController.instance'.allMatches(source).length;
      if (total == 0) continue;
      final allowed = entity.path == 'lib/main.dart' ? guardedProvider.allMatches(normalized(source)).length : 0;
      if (total != allowed) offenders.add(entity.path);
    }
    expect(offenders, isEmpty);
  });

  test('forkUpdateAction starts with the ForkSideload.isSupported guard', () {
    final source = File('lib/fork/update/fork_update_action.dart').readAsStringSync();
    final start = source.indexOf('FocusableAction forkUpdateAction(');
    expect(start, isNonNegative);
    final body = source.substring(source.indexOf(') {', start) + 3).trimLeft();
    expect(body, startsWith('if (!ForkSideload.isSupported) return'));
  });

  test('ForkUpdateHooks.showDialog starts with the ForkSideload.isSupported guard', () {
    final source = File('lib/fork/update/fork_update_hooks.dart').readAsStringSync();
    final start = source.indexOf('showDialog(');
    expect(start, isNonNegative);
    final body = source.substring(source.indexOf(') {', start) + 3).trimLeft();
    expect(body, startsWith('if (!ForkSideload.isSupported) return null;'));
  });
}
