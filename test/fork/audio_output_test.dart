// FORK: meilleure-piste-audio — mapping of the "Canaux audio" setting to the audio output
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/audio_output.dart';
import 'package:plezy/models/audio_channel_limit.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  test('service not initialised gives unknown', () {
    expect(forkAudioOutput(), ForkAudioOutput.unknown);
  });

  test('original gives unknown', () async {
    final svc = await SettingsService.getInstance();
    await svc.write(SettingsService.audioChannelLimit, AudioChannelLimit.original);
    expect(forkAudioOutput(), ForkAudioOutput.unknown);
  });

  test('surround51 gives multichannel', () async {
    final svc = await SettingsService.getInstance();
    await svc.write(SettingsService.audioChannelLimit, AudioChannelLimit.surround51);
    expect(forkAudioOutput(), ForkAudioOutput.multichannel);
  });

  test('stereo gives stereo', () async {
    final svc = await SettingsService.getInstance();
    await svc.write(SettingsService.audioChannelLimit, AudioChannelLimit.stereo);
    expect(forkAudioOutput(), ForkAudioOutput.stereo);
  });

  test('legacy audio_downmix = true gives stereo', () async {
    resetSharedPreferencesForTest(initialAsync: {'audio_downmix': true});
    await SettingsService.getInstance();
    expect(forkAudioOutput(), ForkAudioOutput.stereo);
  });
}
