// FORK: meilleure-piste-audio — reads the "Canaux audio" setting as the audio output the track choice aims for.
import '../models/audio_channel_limit.dart';
import '../services/settings_service.dart';

/// Audio output the launch-time track choice aims for, derived from the
/// "Canaux audio" setting. See `docs/technique/meilleure-piste-audio/plan.md`.
enum ForkAudioOutput {
  /// Two channels: TV speakers, stereo speakers or headphones.
  stereo,

  /// Up to 5.1 channels.
  multichannel,

  /// No preference: the choice made before this feature (server or first track).
  unknown,
}

/// Maps the "Canaux audio" setting to a [ForkAudioOutput].
///
/// Synchronous on purpose: no native probe, the setting alone decides.
/// Returns [ForkAudioOutput.unknown] when [SettingsService] is not initialised.
ForkAudioOutput forkAudioOutput() {
  final limit = SettingsService.instanceOrNull?.read(SettingsService.audioChannelLimit);
  return switch (limit) {
    AudioChannelLimit.stereo => ForkAudioOutput.stereo,
    AudioChannelLimit.surround51 => ForkAudioOutput.multichannel,
    AudioChannelLimit.original || null => ForkAudioOutput.unknown,
  };
}
