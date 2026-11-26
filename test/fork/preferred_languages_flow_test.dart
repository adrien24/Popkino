// FORK: langues-preferees — end-to-end of the rule on the real Plex/Jellyfin mappers
// (preview before playback, subtitle resolver before opening, selection ladder).
// FORK: meilleure-piste-audio — and the channel rule driven by the "Canaux audio" setting.
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/track_choice_memory.dart';
import 'package:plezy/media/account_preferences.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_user_profile.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/jellyfin_media_info_mapper.dart';
import 'package:plezy/services/playback_subtitle_resolver.dart';
import 'package:plezy/services/playback_track_preview.dart';
import 'package:plezy/services/plex_mappers.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/track_selection_service.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// The user's profile: audio English, subtitles French, mode "always".
const _profile = AccountPreferences(
  selectAudioByLanguage: true,
  preferredAudioLanguage: 'en',
  preferredSubtitleLanguage: 'fr',
  subtitlePlaybackMode: SubtitlePlaybackMode.always,
);

Map<String, Object> _plexAudio(
  int id,
  String code, {
  bool selected = false,
  bool isDefault = false,
  int channels = 2,
  String codec = 'aac',
  String? title,
}) => {
  'id': id,
  'streamType': 2,
  'index': id - 100,
  'codec': codec,
  'language': code,
  'languageCode': code,
  'channels': channels,
  'title': ?title,
  if (selected) 'selected': true,
  if (isDefault) 'default': '1',
};

Map<String, Object> _plexSub(int id, String code, {bool forced = false, bool selected = false, String? title}) => {
  'id': id,
  'streamType': 3,
  'index': id - 100,
  'codec': 'srt',
  'language': code,
  'languageCode': code,
  'title': ?title,
  if (forced) 'forced': true,
  if (selected) 'selected': true,
};

MediaSourceInfo _plex(List<Map<String, Object>> streams) => plexMediaSourceInfoFromCacheJson({
  'Media': [
    {
      'id': 1,
      'Part': [
        {'id': 11, 'Stream': streams},
      ],
    },
  ],
})!;

MediaSourceInfo _jellyfin(List<Map<String, Object>> streams, {int? defaultAudio}) =>
    jellyfinMediaSourceToMediaSourceInfo({
      'Id': 'src-1',
      'DefaultAudioStreamIndex': ?defaultAudio,
      'MediaStreams': streams,
    });

Map<String, Object> _jfAudio(
  int index,
  String code, {
  bool isDefault = false,
  int channels = 2,
  String codec = 'aac',
  String? title,
}) => {
  'Index': index,
  'Type': 'Audio',
  'Codec': codec,
  'Language': code,
  'Channels': channels,
  'Title': ?title,
  'IsDefault': isDefault,
};

Map<String, Object> _jfSub(int index, String code, {bool forced = false, String? title}) => {
  'Index': index,
  'Type': 'Subtitle',
  'Codec': 'srt',
  'Language': code,
  'IsForced': forced,
  'Title': ?title,
};

final _plexEpisode = testMediaItem(id: 'ep1', serverId: 'srv', kind: MediaKind.episode);
final _jellyfinEpisode = testMediaItem(
  id: 'ep1',
  serverId: 'srv',
  kind: MediaKind.episode,
  backend: MediaBackend.jellyfin,
);

/// Audio row id and subtitle row id (null = off) the player would start with.
({int? audio, int? subtitle}) _decide(MediaItem item, MediaSourceInfo source, MediaServerUserProfile? profile) {
  final preview = previewPlaybackTracks(item, source, profile: profile)!;
  final resolved = PlaybackSubtitleResolver.resolve(
    metadata: item,
    mediaInfo: source,
    sidecars: const [],
    profileSettings: profile,
  );
  // The preview and the resolver must agree on the subtitle.
  final resolvedId = resolved.isOff ? null : int.parse(resolved.primaryTrack.id.substring('source:'.length));
  expect(resolvedId, preview.subtitle?.id, reason: 'preview and resolver disagree');
  return (audio: preview.audio?.id, subtitle: resolvedId);
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    ForkTrackChoiceMemory.resetForTesting();
  });
  tearDown(ForkTrackChoiceMemory.resetForTesting);

  group('Plex', () {
    test('CA1/CA2: server remembered French, profile wants English audio and French subtitles', () {
      final source = _plex([
        _plexAudio(101, 'eng'),
        _plexAudio(102, 'fra', selected: true),
        _plexSub(201, 'eng', title: 'Full'),
        _plexSub(202, 'fra', title: 'Full'),
      ]);
      final decision = _decide(_plexEpisode, source, _profile);
      expect(decision.audio, 101);
      expect(decision.subtitle, 202);
    });

    test('CA6: file in French only, no full French subtitle needed', () {
      final source = _plex([_plexAudio(101, 'fra', selected: true), _plexSub(201, 'fra', title: 'Full')]);
      final decision = _decide(_plexEpisode, source, _profile);
      expect(decision.audio, 101);
      expect(decision.subtitle, isNull);
    });

    test('CA6: file in German only gets French subtitles', () {
      final source = _plex([
        _plexAudio(101, 'deu', selected: true),
        _plexSub(201, 'eng', title: 'Full'),
        _plexSub(202, 'fra', title: 'Full'),
      ]);
      final decision = _decide(_plexEpisode, source, _profile);
      expect(decision.audio, 101);
      expect(decision.subtitle, 202);
    });

    test('CA12: French audio shows the forced French track', () {
      final source = _plex([
        _plexAudio(101, 'fra', selected: true),
        _plexSub(201, 'fra', title: 'Full'),
        _plexSub(202, 'fra', forced: true),
      ]);
      expect(_decide(_plexEpisode, source, _profile).subtitle, 202);
    });

    test('CA12: French audio with a full French subtitle only gives off', () {
      final source = _plex([_plexAudio(101, 'fra', selected: true), _plexSub(201, 'fra', title: 'Full')]);
      expect(_decide(_plexEpisode, source, _profile).subtitle, isNull);
    });

    test('CA7: English audio without French subtitles gives off even with an English default', () {
      final source = _plex([
        _plexAudio(101, 'eng', selected: true),
        {..._plexSub(201, 'eng', title: 'Full'), 'default': '1'},
      ]);
      final decision = _decide(_plexEpisode, source, _profile);
      expect(decision.audio, 101);
      expect(decision.subtitle, isNull);
    });

    test('CA8: audio by language off behaves as without any profile', () {
      const off = AccountPreferences(
        selectAudioByLanguage: false,
        preferredAudioLanguage: 'en',
        preferredSubtitleLanguage: 'fr',
        subtitlePlaybackMode: SubtitlePlaybackMode.always,
      );
      final source = _plex([
        _plexAudio(101, 'eng'),
        _plexAudio(102, 'fra', selected: true),
        _plexSub(201, 'eng', title: 'Full'),
        _plexSub(202, 'fra', title: 'Full', selected: true),
      ]);
      final withOff = _decide(_plexEpisode, source, off);
      expect(withOff, _decide(_plexEpisode, source, null));
      expect(withOff.audio, 102);
      expect(withOff.subtitle, 202);
    });

    test('server already on the preferred audio language: nothing changes', () {
      final source = _plex([
        _plexAudio(101, 'eng', selected: true),
        _plexAudio(102, 'fra'),
        _plexSub(201, 'fra', title: 'Full'),
      ]);
      expect(_decide(_plexEpisode, source, _profile).audio, 101);
    });
  });

  group('Jellyfin', () {
    test('CA3: DefaultAudioStreamIndex on French, profile wants English audio and French subtitles', () {
      final source = _jellyfin([
        _jfAudio(1, 'eng'),
        _jfAudio(2, 'fra', isDefault: true),
        _jfSub(3, 'eng', title: 'Full'),
        _jfSub(4, 'fra', title: 'Full'),
      ], defaultAudio: 2);
      final decision = _decide(_jellyfinEpisode, source, _profile);
      expect(decision.audio, 1);
      expect(decision.subtitle, 4);
    });

    test('CA6: file in French only', () {
      final source = _jellyfin([_jfAudio(1, 'fra', isDefault: true), _jfSub(2, 'fra', title: 'Full')], defaultAudio: 1);
      final decision = _decide(_jellyfinEpisode, source, _profile);
      expect(decision.audio, 1);
      expect(decision.subtitle, isNull);
    });
  });

  group('audio channels (meilleure-piste-audio)', () {
    Future<void> setOutput(AudioChannelLimit limit) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.audioChannelLimit, limit);
    }

    // Two files with the same shape: EN 2.0, FR 2.0, EN 5.1, FR 5.1. The server marks EN 2.0 as its choice.
    final plexFiles = <String, List<Map<String, Object>>>{
      'S3E8': [
        _plexAudio(101, 'eng', selected: true),
        _plexAudio(102, 'fra'),
        _plexAudio(103, 'eng', channels: 6, codec: 'eac3', title: 'ENG VO - EAC3 DDP 5.1'),
        _plexAudio(104, 'fra', channels: 6, codec: 'eac3'),
        _plexSub(201, 'eng', title: 'Full'),
        _plexSub(202, 'fra', title: 'Full'),
      ],
      'Green Lantern': [
        _plexAudio(101, 'eng', selected: true),
        _plexAudio(102, 'fra'),
        _plexAudio(103, 'eng', channels: 6, codec: 'dts'),
        _plexAudio(104, 'fra', channels: 6, codec: 'ac3'),
        _plexSub(201, 'eng', title: 'Full'),
        _plexSub(202, 'fra', title: 'Full'),
      ],
    };
    final jellyfinFiles = <String, List<Map<String, Object>>>{
      'S3E8': [
        _jfAudio(1, 'eng', isDefault: true),
        _jfAudio(2, 'fra'),
        _jfAudio(3, 'eng', channels: 6, codec: 'eac3', title: 'ENG VO - EAC3 DDP 5.1'),
        _jfAudio(4, 'fra', channels: 6, codec: 'eac3'),
        _jfSub(5, 'eng', title: 'Full'),
        _jfSub(6, 'fra', title: 'Full'),
      ],
      'Green Lantern': [
        _jfAudio(1, 'eng', isDefault: true),
        _jfAudio(2, 'fra'),
        _jfAudio(3, 'eng', channels: 6, codec: 'dts'),
        _jfAudio(4, 'fra', channels: 6, codec: 'ac3'),
        _jfSub(5, 'eng', title: 'Full'),
        _jfSub(6, 'fra', title: 'Full'),
      ],
    };

    for (final MapEntry(key: name, value: streams) in plexFiles.entries) {
      test('Plex $name: the audio row follows "Canaux audio", subtitles stay for English audio', () async {
        final source = _plex(streams);
        final expected = {
          AudioChannelLimit.surround51: 103,
          AudioChannelLimit.stereo: 101,
          AudioChannelLimit.original: 101,
        };
        for (final MapEntry(key: limit, value: audio) in expected.entries) {
          await setOutput(limit);
          final decision = _decide(_plexEpisode, source, _profile);
          expect(decision.audio, audio, reason: '$limit');
          expect(decision.subtitle, 202, reason: '$limit');
        }
      });
    }

    for (final MapEntry(key: name, value: streams) in jellyfinFiles.entries) {
      test('CA10 Jellyfin $name: the audio row follows "Canaux audio", subtitles stay for English audio', () async {
        final source = _jellyfin(streams, defaultAudio: 1);
        final expected = {AudioChannelLimit.surround51: 3, AudioChannelLimit.stereo: 1, AudioChannelLimit.original: 1};
        for (final MapEntry(key: limit, value: audio) in expected.entries) {
          await setOutput(limit);
          final decision = _decide(_jellyfinEpisode, source, _profile);
          expect(decision.audio, audio, reason: '$limit');
          expect(decision.subtitle, 6, reason: '$limit');
        }
      });
    }

    test('CA7: two episodes in a row, no carried preference, land on the same channel class', () async {
      final source = _plex(plexFiles['S3E8']!);
      final tracks = PlaybackSubtitleResolver.audioTracksForSource(source);
      final expectedChannels = {AudioChannelLimit.surround51: 6, AudioChannelLimit.stereo: 2};
      for (final MapEntry(key: limit, value: channels) in expectedChannels.entries) {
        await setOutput(limit);
        for (final id in ['ep1', 'ep2']) {
          final episode = testMediaItem(id: id, serverId: 'srv', kind: MediaKind.episode);
          final service = TrackSelectionService(profileSettings: _profile, metadata: episode, plexMediaInfo: source);
          final result = service.selectAudioTrack(tracks, null);
          expect(result?.track.channels, channels, reason: '$limit $id');
          expect(result?.track.language, 'eng', reason: '$limit $id');
        }
      }
    });
  });

  group('CA5: carried preference', () {
    test('a French preference carried from the previous item wins with the navigation priority', () {
      final source = _plex([_plexAudio(101, 'eng', selected: true), _plexAudio(102, 'fra')]);
      final service = TrackSelectionService(profileSettings: _profile, metadata: _plexEpisode, plexMediaInfo: source);
      final result = service.selectAudioTrack(
        PlaybackSubtitleResolver.audioTracksForSource(source),
        const AudioTrack(id: carriedAudioTrackId, language: 'fra'),
      );
      expect(result?.track.id, 'source:102');
      expect(result?.priority, TrackSelectionPriority.navigation);
    });
  });
}
