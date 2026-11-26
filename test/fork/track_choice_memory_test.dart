// FORK: langues-preferees — manual track pick memory
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/track_choice_memory.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    ForkTrackChoiceMemory.resetForTesting();
  });
  tearDown(ForkTrackChoiceMemory.resetForTesting);

  final item = testMediaItem(id: 'ep1', serverId: 'srv');

  test('write then read, per kind', () async {
    await SettingsService.getInstance();
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.audio), isFalse);
    await ForkTrackChoiceMemory.recordManualPick(item, ForkTrackKind.audio);
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.audio), isTrue);
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.subtitle), isFalse);
    await ForkTrackChoiceMemory.recordManualPick(item, ForkTrackKind.subtitle);
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.audio), isTrue);
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.subtitle), isTrue);
    expect(
      ForkTrackChoiceMemory.hasManualPick(testMediaItem(id: 'ep2', serverId: 'srv'), ForkTrackKind.audio),
      isFalse,
    );
  });

  test('remember disabled: reads false and nothing is written', () async {
    final svc = await SettingsService.getInstance();
    await svc.write(SettingsService.rememberTrackSelections, false);
    await ForkTrackChoiceMemory.recordManualPick(item, ForkTrackKind.audio);
    expect(svc.read(ForkTrackChoiceMemory.pref), isEmpty);

    await svc.write(SettingsService.rememberTrackSelections, true);
    await ForkTrackChoiceMemory.recordManualPick(item, ForkTrackKind.audio);
    await svc.write(SettingsService.rememberTrackSelections, false);
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.audio), isFalse);
  });

  test('uninitialized service: false, no exception', () async {
    expect(SettingsService.instanceOrNull, isNull);
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.audio), isFalse);
    await ForkTrackChoiceMemory.recordManualPick(item, ForkTrackKind.audio);
  });

  test('prunes at 501 entries, dropping the oldest', () async {
    final svc = await SettingsService.getInstance();
    final seeded = <String, dynamic>{
      for (var i = 0; i < ForkTrackChoiceMemory.maxEntries; i++) 'srv:old$i': {'a': 1000 + i},
    };
    await svc.write(ForkTrackChoiceMemory.pref, seeded);
    ForkTrackChoiceMemory.resetForTesting();

    await ForkTrackChoiceMemory.recordManualPick(item, ForkTrackKind.audio);

    final stored = svc.read(ForkTrackChoiceMemory.pref);
    expect(stored.length, ForkTrackChoiceMemory.maxEntries);
    expect(stored.containsKey('srv:old0'), isFalse);
    expect(stored.containsKey('srv:old1'), isTrue);
    expect(ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.audio), isTrue);
  });

  test('item without serverId is not remembered', () async {
    final svc = await SettingsService.getInstance();
    final noServer = testMediaItem(id: 'ep1');
    expect(ForkTrackChoiceMemory.keyFor(noServer), isNull);
    await ForkTrackChoiceMemory.recordManualPick(noServer, ForkTrackKind.audio);
    expect(svc.read(ForkTrackChoiceMemory.pref), isEmpty);
    expect(ForkTrackChoiceMemory.hasManualPick(noServer, ForkTrackKind.audio), isFalse);
  });
}
