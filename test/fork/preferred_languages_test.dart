// FORK: langues-preferees — unit tests of the "preferred language first" rule
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/preferred_languages.dart';
import 'package:plezy/fork/track_choice_memory.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_user_profile.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/track_selection_service.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

class _Profile implements MediaServerUserProfile {
  _Profile({this.auto = true, this.audio = 'en', this.subtitle = 'fr', this.mode = SubtitlePlaybackMode.always});

  final bool auto;
  final String? audio;
  final String? subtitle;
  final SubtitlePlaybackMode? mode;

  @override
  bool get autoSelectAudio => auto;
  @override
  String? get defaultAudioLanguage => audio;
  @override
  String? get defaultSubtitleLanguage => subtitle;
  @override
  SubtitlePlaybackMode? get subtitleMode => mode;
}

const _en = AudioTrack(id: '1', language: 'eng');
const _fr = AudioTrack(id: '2', language: 'fra');
const _de = AudioTrack(id: '3', language: 'deu');

const _subFrFull = SubtitleTrack(id: '10', language: 'fra', title: 'Full');
const _subFrForced = SubtitleTrack(id: '11', language: 'fra', title: 'Forced', isForced: true);
const _subEnFull = SubtitleTrack(id: '12', language: 'eng', title: 'Full', isDefault: true);
const _subEnForced = SubtitleTrack(id: '13', language: 'eng', title: 'Forced', isForced: true);

MediaAudioTrack _row(int id, String code, {bool selected = false, bool isDefault = false, int? index}) =>
    MediaAudioTrack(id: id, index: index, languageCode: code, selected: selected, isDefault: isDefault);

MediaSourceInfo _info(
  List<MediaAudioTrack> audio, {
  List<MediaSubtitleTrack> subtitles = const [],
  int? defaultAudioStreamIndex,
}) => MediaSourceInfo(
  videoUrl: '',
  audioTracks: audio,
  subtitleTracks: subtitles,
  chapters: const [],
  defaultAudioStreamIndex: defaultAudioStreamIndex,
);

TrackSelectionService _service({
  MediaServerUserProfile? profile,
  MediaSourceInfo? info,
  MediaBackend backend = MediaBackend.plex,
  MediaKind kind = MediaKind.episode,
}) => TrackSelectionService(
  profileSettings: profile,
  metadata: testMediaItem(id: 'ep1', serverId: 'srv', backend: backend, kind: kind),
  plexMediaInfo: info,
);

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    ForkTrackChoiceMemory.resetForTesting();
  });
  tearDown(ForkTrackChoiceMemory.resetForTesting);

  group('forkPreferredAudio', () {
    test('picks the preferred language over the server selection', () {
      final service = _service(profile: _Profile(), info: _info([_row(1, 'eng'), _row(2, 'fra', selected: true)]));
      final result = forkPreferredAudio(service, [_fr, _en, _de]);
      expect(result?.track, _en);
      expect(result?.priority, TrackSelectionPriority.profile);
    });

    test('A1: no profile, auto-select off, no language, music, no tracks', () {
      final info = _info([_row(2, 'fra', selected: true)]);
      expect(forkPreferredAudio(_service(info: info), [_en, _fr]), isNull);
      expect(forkPreferredAudio(_service(profile: _Profile(auto: false), info: info), [_en, _fr]), isNull);
      expect(forkPreferredAudio(_service(profile: _Profile(audio: null), info: info), [_en, _fr]), isNull);
      expect(
        forkPreferredAudio(
          _service(
            profile: _Profile(audio: ''),
            info: info,
          ),
          [_en, _fr],
        ),
        isNull,
      );
      expect(forkPreferredAudio(_service(profile: _Profile(), info: info, kind: MediaKind.track), [_en, _fr]), isNull);
      expect(forkPreferredAudio(_service(profile: _Profile(), info: info), const []), isNull);
    });

    test('A2: the server is already on the preferred language', () {
      final service = _service(profile: _Profile(), info: _info([_row(1, 'eng', selected: true), _row(2, 'fra')]));
      expect(forkPreferredAudio(service, [_fr, _en]), isNull);
    });

    test('A2: two English tracks, the server choice is kept (commentary)', () {
      const commentary = AudioTrack(id: '4', language: 'eng', title: 'Commentary');
      final service = _service(
        profile: _Profile(),
        info: _info([_row(1, 'eng', selected: true), _row(2, 'fra'), _row(4, 'eng')]),
      );
      expect(forkPreferredAudio(service, [_en, _fr, commentary]), isNull);
    });

    test('A2 also reads a region code on the server row', () {
      final service = _service(profile: _Profile(), info: _info([_row(1, 'en-US', selected: true)]));
      expect(forkPreferredAudio(service, [_en, _fr]), isNull);
    });

    test('A3: a manual pick on this item leaves the server in charge', () async {
      await SettingsService.getInstance();
      final service = _service(profile: _Profile(), info: _info([_row(2, 'fra', selected: true), _row(1, 'eng')]));
      expect(forkPreferredAudio(service, [_fr, _en]), isNotNull);
      await ForkTrackChoiceMemory.recordManualPick(service.metadata, ForkTrackKind.audio);
      expect(forkPreferredAudio(service, [_fr, _en]), isNull);
    });

    test('A4: no track in the preferred language (file in French only, or German only)', () {
      final service = _service(profile: _Profile(), info: _info([_row(2, 'fra', selected: true)]));
      expect(forkPreferredAudio(service, [_fr]), isNull);
      expect(forkPreferredAudio(service, [_de, _fr]), isNull);
    });

    test('two English tracks, the isDefault one is chosen', () {
      const enOther = AudioTrack(id: '5', language: 'eng', title: 'Other');
      const enDefault = AudioTrack(id: '6', language: 'eng', isDefault: true);
      final service = _service(profile: _Profile(), info: _info([_row(2, 'fra', selected: true)]));
      expect(forkPreferredAudio(service, [_fr, enOther, enDefault])?.track, enDefault);
      expect(forkPreferredAudio(service, [_fr, enOther, enDefault.copyWith(isDefault: false)])?.track, enOther);
    });

    test('without server info the rule still applies', () {
      expect(forkPreferredAudio(_service(profile: _Profile()), [_fr, _en])?.track, _en);
    });

    test('Jellyfin: DefaultAudioStreamIndex without selected row', () {
      final jellyfin = MediaBackend.jellyfin;
      final french = _info([_row(1, 'eng', index: 1), _row(2, 'fra', index: 2)], defaultAudioStreamIndex: 2);
      expect(
        forkPreferredAudio(_service(profile: _Profile(), info: french, backend: jellyfin), [_en, _fr])?.track,
        _en,
      );
      final english = _info([_row(1, 'eng', index: 1), _row(2, 'fra', index: 2)], defaultAudioStreamIndex: 1);
      expect(forkPreferredAudio(_service(profile: _Profile(), info: english, backend: jellyfin), [_en, _fr]), isNull);
    });

    test('Plex: DefaultAudioStreamIndex is ignored', () {
      final info = _info([_row(1, 'eng', index: 1), _row(2, 'fra', index: 2)], defaultAudioStreamIndex: 1);
      expect(forkPreferredAudio(_service(profile: _Profile(), info: info), [_en, _fr])?.track, _en);
    });
  });

  group('forkPreferredSubtitle', () {
    TrackSelectionResult<SubtitleTrack>? run(
      List<SubtitleTrack> tracks,
      AudioTrack? audio, {
      MediaServerUserProfile? profile,
      MediaSourceInfo? info,
    }) => forkPreferredSubtitle(_service(profile: profile ?? _Profile(), info: info), tracks, audio);

    test('S1: no profile, auto-select off, languages unset, music, unsupported modes', () {
      final tracks = [_subFrFull];
      expect(forkPreferredSubtitle(_service(), tracks, _en), isNull);
      expect(run(tracks, _en, profile: _Profile(auto: false)), isNull);
      expect(run(tracks, _en, profile: _Profile(audio: null)), isNull);
      expect(run(tracks, _en, profile: _Profile(subtitle: null)), isNull);
      expect(run(tracks, _en, profile: _Profile(subtitle: '')), isNull);
      expect(run(tracks, _en, profile: _Profile(mode: null)), isNull);
      expect(run(tracks, _en, profile: _Profile(mode: SubtitlePlaybackMode.none)), isNull);
      expect(run(tracks, _en, profile: _Profile(mode: SubtitlePlaybackMode.defaultMode)), isNull);
      expect(forkPreferredSubtitle(_service(profile: _Profile(), kind: MediaKind.track), tracks, _en), isNull);
    });

    test('S1 does not require available tracks', () {
      expect(run(const [], _en)?.track, SubtitleTrack.off);
    });

    test('S2: a manual subtitle pick leaves the server in charge', () async {
      await SettingsService.getInstance();
      final service = _service(profile: _Profile());
      expect(forkPreferredSubtitle(service, [_subFrFull], _en), isNotNull);
      await ForkTrackChoiceMemory.recordManualPick(service.metadata, ForkTrackKind.subtitle);
      expect(forkPreferredSubtitle(service, [_subFrFull], _en), isNull);
    });

    test('S3: a preferred-language track announced but not arrived yet', () {
      final announced = [MediaSubtitleTrack(id: 10, languageCode: 'fra', selected: false, forced: false)];
      final info = _info(const [], subtitles: announced);
      expect(run([_subEnFull], _en, info: info), isNull);
      // Once a French native track is there, the rule decides.
      expect(run([_subEnFull, _subFrFull], _en, info: info)?.track, _subFrFull);
      // Nothing announced: no wait, off.
      expect(run([_subEnFull], _en)?.track, SubtitleTrack.off);
    });

    group('always', () {
      final p = _Profile();
      test('audio in the subtitle language: forced else off (CA6, CA12)', () {
        expect(run([_subFrFull, _subFrForced], _fr, profile: p)?.track, _subFrForced);
        expect(run([_subFrFull], _fr, profile: p)?.track, SubtitleTrack.off);
      });
      test('audio in the preferred audio language: full else forced else off (CA7)', () {
        expect(run([_subEnFull, _subFrForced, _subFrFull], _en, profile: p)?.track, _subFrFull);
        expect(run([_subEnFull, _subFrForced], _en, profile: p)?.track, _subFrForced);
        expect(run([_subEnFull, _subEnForced], _en, profile: p)?.track, SubtitleTrack.off);
      });
      test('audio in another language: same as above', () {
        expect(run([_subFrFull, _subFrForced], _de, profile: p)?.track, _subFrFull);
        expect(run([_subEnFull], _de, profile: p)?.track, SubtitleTrack.off);
      });
      test('no audio selected is treated as another language', () {
        expect(run([_subFrFull, _subFrForced], null, profile: p)?.track, _subFrFull);
      });
      test('the default full track is preferred', () {
        const second = SubtitleTrack(id: '20', language: 'fra', isDefault: true);
        expect(run([_subFrFull, second], _en, profile: p)?.track, second);
      });
      test('a title saying forced counts as forced', () {
        const titled = SubtitleTrack(id: '21', language: 'fra', title: 'Français (Forced)');
        expect(run([titled, _subFrFull], _en, profile: p)?.track, _subFrFull);
        expect(run([titled, _subFrFull], _fr, profile: p)?.track, titled);
      });
    });

    group('smart', () {
      final p = _Profile(mode: SubtitlePlaybackMode.smart);
      test('audio in the subtitle language: forced else off', () {
        expect(run([_subFrFull, _subFrForced], _fr, profile: p)?.track, _subFrForced);
        expect(run([_subFrFull], _fr, profile: p)?.track, SubtitleTrack.off);
      });
      test('audio in the preferred audio language: forced else off', () {
        expect(run([_subFrFull, _subFrForced], _en, profile: p)?.track, _subFrForced);
        expect(run([_subFrFull], _en, profile: p)?.track, SubtitleTrack.off);
      });
      test('audio in another language: full else off', () {
        expect(run([_subFrFull, _subFrForced], _de, profile: p)?.track, _subFrFull);
        expect(run([_subEnFull], _de, profile: p)?.track, SubtitleTrack.off);
        expect(run([_subFrFull], null, profile: p)?.track, _subFrFull);
      });
    });

    group('onlyForced', () {
      final p = _Profile(mode: SubtitlePlaybackMode.onlyForced);
      test('forced in the preferred language, whatever the audio', () {
        for (final audio in <AudioTrack?>[_fr, _en, _de, null]) {
          expect(run([_subFrFull, _subFrForced], audio, profile: p)?.track, _subFrForced);
          expect(run([_subFrFull, _subEnForced], audio, profile: p)?.track, SubtitleTrack.off);
        }
      });
    });

    test('result carries the profile priority', () {
      expect(run([_subFrFull], _en)?.priority, TrackSelectionPriority.profile);
    });
  });

  group('through TrackSelectionService', () {
    test('selectAudioTrack: the carried preference (navigation) still wins', () {
      final service = _service(profile: _Profile(), info: _info([_row(2, 'fra', selected: true)]));
      final result = service.selectAudioTrack([_fr, _en], _fr);
      expect(result?.track, _fr);
      expect(result?.priority, TrackSelectionPriority.navigation);
    });

    test('selectAudioTrack: hook applies before the server selection', () {
      final service = _service(profile: _Profile(), info: _info([_row(1, 'eng'), _row(2, 'fra', selected: true)]));
      final result = service.selectAudioTrack([_en, _fr], null);
      expect(result?.track, _en);
      expect(result?.priority, TrackSelectionPriority.profile);
    });

    test('selectSubtitleTrack: hook applies before the server selection', () {
      final info = _info(
        const [],
        subtitles: [MediaSubtitleTrack(id: 11, languageCode: 'eng', selected: true, forced: false)],
      );
      final service = _service(profile: _Profile(), info: info);
      final result = service.selectSubtitleTrack([_subEnFull, _subFrFull], null, _en);
      expect(result?.track, _subFrFull);
    });
  });
}
