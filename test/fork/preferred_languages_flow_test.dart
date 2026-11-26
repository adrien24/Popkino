// FORK: langues-preferees — end-to-end of the rule on the real Plex/Jellyfin mappers
// (preview before playback, subtitle resolver before opening, selection ladder).
import 'package:flutter_test/flutter_test.dart';
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
import 'package:plezy/services/track_selection_service.dart';

import '../test_helpers/media_items.dart';

/// The user's profile: audio English, subtitles French, mode "always".
const _profile = AccountPreferences(
  selectAudioByLanguage: true,
  preferredAudioLanguage: 'en',
  preferredSubtitleLanguage: 'fr',
  subtitlePlaybackMode: SubtitlePlaybackMode.always,
);

Map<String, Object> _plexAudio(int id, String code, {bool selected = false, bool isDefault = false}) => {
  'id': id,
  'streamType': 2,
  'index': id - 100,
  'codec': 'aac',
  'language': code,
  'languageCode': code,
  'channels': 2,
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

Map<String, Object> _jfAudio(int index, String code, {bool isDefault = false}) => {
  'Index': index,
  'Type': 'Audio',
  'Codec': 'aac',
  'Language': code,
  'Channels': 2,
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
