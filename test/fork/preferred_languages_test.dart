// FORK: langues-preferees — unit tests of the "preferred language first" rule
// FORK: meilleure-piste-audio — and of the channel rule among the tracks of the preferred language
// FORK: sous-titres-mal-etiquetes — and of the subtitle language read from the author's own title
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/audio_output.dart';
import 'package:plezy/fork/preferred_languages.dart';
import 'package:plezy/fork/track_choice_memory.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_user_profile.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/playback_subtitle_resolver.dart';
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

  group('channel rule (meilleure-piste-audio)', () {
    Future<void> setOutput(AudioChannelLimit limit) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.audioChannelLimit, limit);
    }

    // S3E8: EN 2.0 AAC, FR 2.0, EN EAC3 5.1 (titled), FR 5.1.
    const s3En20 = AudioTrack(id: '1', language: 'eng', codec: 'aac', channels: 2);
    const s3Fr20 = AudioTrack(id: '2', language: 'fra', codec: 'aac', channels: 2);
    const s3En51 = AudioTrack(id: '3', language: 'eng', codec: 'eac3', channels: 6, title: 'ENG VO - EAC3 DDP 5.1');
    const s3Fr51 = AudioTrack(id: '4', language: 'fra', codec: 'eac3', channels: 6);
    final s3 = [s3En20, s3Fr20, s3En51, s3Fr51];

    // Green Lantern: EN 2.0, FR 2.0, EN DTS 5.1, FR AC3 5.1.
    const glEn20 = AudioTrack(id: '1', language: 'eng', codec: 'aac', channels: 2);
    const glFr20 = AudioTrack(id: '2', language: 'fra', codec: 'aac', channels: 2);
    const glEn51 = AudioTrack(id: '3', language: 'eng', codec: 'dts', channels: 6);
    const glFr51 = AudioTrack(id: '4', language: 'fra', codec: 'ac3', channels: 6);
    final greenLantern = [glEn20, glFr20, glEn51, glFr51];

    // The server marked the first English track (the stereo one) as selected.
    MediaSourceInfo serverOnEn20() =>
        _info([_row(1, 'eng', selected: true), _row(2, 'fra'), _row(3, 'eng'), _row(4, 'fra')]);

    for (final (name, tracks, en20, en51) in [
      ('S3E8', s3, s3En20, s3En51),
      ('Green Lantern', greenLantern, glEn20, glEn51),
    ]) {
      group(name, () {
        test('stereo picks English 2.0', () async {
          await setOutput(AudioChannelLimit.stereo);
          final result = forkPreferredAudio(_service(profile: _Profile(), info: serverOnEn20()), tracks);
          expect(result?.track, en20);
          expect(result?.priority, TrackSelectionPriority.profile);
        });

        test('multichannel picks English 5.1 even when the server chose English 2.0 (A2 relaxed)', () async {
          await setOutput(AudioChannelLimit.surround51);
          final result = forkPreferredAudio(_service(profile: _Profile(), info: serverOnEn20()), tracks);
          expect(result?.track, en51);
          expect(result?.priority, TrackSelectionPriority.profile);
        });

        test('unknown keeps today\'s choice (A2: server already on English)', () async {
          await setOutput(AudioChannelLimit.original);
          expect(forkPreferredAudio(_service(profile: _Profile(), info: serverOnEn20()), tracks), isNull);
        });

        test('unknown keeps today\'s choice (server on French: first English track)', () async {
          await setOutput(AudioChannelLimit.original);
          final info = _info([_row(1, 'eng'), _row(2, 'fra', selected: true), _row(3, 'eng'), _row(4, 'fra')]);
          expect(forkPreferredAudio(_service(profile: _Profile(), info: info), tracks)?.track, en20);
        });
      });
    }

    test('only the 5.1 track reports its channels: the rule says nothing', () async {
      const unknown20 = AudioTrack(id: '1', language: 'eng');
      const known51 = AudioTrack(id: '3', language: 'eng', channels: 6);
      final service = _service(profile: _Profile(), info: _info([_row(2, 'fra', selected: true)]));
      await setOutput(AudioChannelLimit.stereo);
      expect(forkBestTrackForOutput(const [unknown20, known51], ForkAudioOutput.stereo), isNull);
      // Current order: the first English track.
      expect(forkPreferredAudio(service, [_fr, unknown20, known51])?.track, unknown20);
      await setOutput(AudioChannelLimit.surround51);
      expect(forkBestTrackForOutput(const [unknown20, known51], ForkAudioOutput.multichannel), isNull);
      expect(forkPreferredAudio(service, [_fr, unknown20, known51])?.track, unknown20);
    });

    test('CA5: two English 5.1 tracks, the rule says nothing', () {
      const a = AudioTrack(id: '1', language: 'eng', channels: 6);
      const b = AudioTrack(id: '2', language: 'eng', channels: 6);
      expect(forkBestTrackForOutput(const [a, b], ForkAudioOutput.stereo), isNull);
      expect(forkBestTrackForOutput(const [a, b], ForkAudioOutput.multichannel), isNull);
    });

    test('CA4: a single English track, the rule says nothing', () {
      const a = AudioTrack(id: '1', language: 'eng', channels: 6);
      expect(forkBestTrackForOutput(const [a], ForkAudioOutput.stereo), isNull);
      expect(forkBestTrackForOutput(const [a], ForkAudioOutput.multichannel), isNull);
      expect(forkBestTrackForOutput(const [], ForkAudioOutput.multichannel), isNull);
    });

    test('stereo output with no stereo track: the rule says nothing', () {
      const a = AudioTrack(id: '1', language: 'eng', channels: 6);
      const b = AudioTrack(id: '2', language: 'eng', channels: 8);
      expect(forkBestTrackForOutput(const [a, b], ForkAudioOutput.stereo), isNull);
    });

    test('multichannel takes the most channels, then isDefault, then the first', () {
      const stereo = AudioTrack(id: '1', language: 'eng', channels: 2);
      const six = AudioTrack(id: '2', language: 'eng', channels: 6);
      const eight = AudioTrack(id: '3', language: 'eng', channels: 8);
      const eightDefault = AudioTrack(id: '4', language: 'eng', channels: 8, isDefault: true);
      expect(forkBestTrackForOutput(const [stereo, six, eight], ForkAudioOutput.multichannel), eight);
      expect(forkBestTrackForOutput(const [stereo, eight, eightDefault], ForkAudioOutput.multichannel), eightDefault);
    });

    test('stereo takes isDefault among the stereo tracks, then the first', () {
      const first = AudioTrack(id: '1', language: 'eng', channels: 2);
      const second = AudioTrack(id: '2', language: 'eng', channels: 2, isDefault: true);
      const six = AudioTrack(id: '3', language: 'eng', channels: 6);
      expect(forkBestTrackForOutput(const [first, second, six], ForkAudioOutput.stereo), second);
      expect(forkBestTrackForOutput([first, second.copyWith(isDefault: false), six], ForkAudioOutput.stereo), first);
    });

    test('CA11: a commentary track is never chosen by the rule', () {
      const surround = AudioTrack(id: '1', language: 'eng', channels: 6, title: 'English 5.1');
      const commentary = AudioTrack(id: '2', language: 'eng', channels: 2, title: 'English 2.0 Commentary');
      expect(forkBestTrackForOutput(const [surround, commentary], ForkAudioOutput.stereo), isNull);
      expect(forkBestTrackForOutput(const [surround, commentary], ForkAudioOutput.multichannel), isNull);
    });

    test('CA11: an audio description track is never chosen by the rule', () {
      const description = AudioTrack(id: '1', language: 'eng', channels: 6, title: 'Audio Description');
      const stereo = AudioTrack(id: '2', language: 'eng', channels: 2, title: 'English 2.0');
      expect(forkBestTrackForOutput(const [description, stereo], ForkAudioOutput.multichannel), isNull);
      expect(forkBestTrackForOutput(const [description, stereo], ForkAudioOutput.stereo), isNull);
    });

    test('CA6: a manual pick leaves the server in charge whatever the output', () async {
      await SettingsService.getInstance();
      final service = _service(profile: _Profile(), info: serverOnEn20());
      await ForkTrackChoiceMemory.recordManualPick(service.metadata, ForkTrackKind.audio);
      for (final limit in AudioChannelLimit.values) {
        await setOutput(limit);
        expect(forkPreferredAudio(service, s3), isNull, reason: '$limit');
      }
    });

    test('CA8: choosing audio by language off gives null whatever the output', () async {
      await setOutput(AudioChannelLimit.surround51);
      final service = _service(profile: _Profile(auto: false), info: serverOnEn20());
      expect(forkPreferredAudio(service, s3), isNull);
    });

    test('forkIsSpecialAudioTrack matches whole words only', () {
      for (final title in ["Director's Commentary", 'Commentaire audio', 'AD', 'Audiodescription']) {
        expect(forkIsSpecialAudioTrack(title), isTrue, reason: title);
      }
      for (final title in ['ENG VO - EAC3 DDP 5.1', 'Adventure', 'Headphones', '', null]) {
        expect(forkIsSpecialAudioTrack(title), isFalse, reason: '$title');
      }
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

    group('mislabeled subtitles (sous-titres-mal-etiquetes)', () {
      // Green Lantern: three rows all declared English, two of them titled French.
      MediaSubtitleTrack row(int id, String? title, {bool forced = false, String? displayTitle}) => MediaSubtitleTrack(
        id: id,
        languageCode: 'eng',
        title: title,
        displayTitle: displayTitle,
        selected: id == 12,
        forced: forced,
      );
      final complet = row(10, 'French Complet');
      final frForced = row(11, 'French Forced', forced: true);
      final english = row(12, 'English');
      final rows = [complet, frForced, english];
      final info = _info(const [], subtitles: rows);
      final descriptors = [for (final r in rows) PlaybackSubtitleResolver.subtitleTrackForSource(r)];
      final descriptorComplet = descriptors[0];
      final descriptorForced = descriptors[1];
      final descriptorEnglish = descriptors[2];

      test('CA1: English audio, the track titled French Complet is chosen', () {
        expect(run(descriptors, _en, info: info)?.track, descriptorComplet);
      });

      test('CA2: French audio, the track titled French Forced is chosen', () {
        expect(run(descriptors, _fr, info: info)?.track, descriptorForced);
      });

      test('CA3: the real English track is never taken for French', () {
        for (final audio in <AudioTrack?>[_en, _fr, _de, null]) {
          expect(run(descriptors, audio, info: info)?.track, isNot(descriptorEnglish), reason: '$audio');
        }
        expect(run([descriptorEnglish], _en, info: _info(const [], subtitles: [english]))?.track, SubtitleTrack.off);
      });

      test('CA7: a well-labeled French track comes before a mislabeled one, whatever the order or isDefault', () {
        const good = SubtitleTrack(id: '20', language: 'fra', title: 'Full');
        const mislabeled = SubtitleTrack(id: '21', language: 'eng', title: 'French', isDefault: true);
        expect(run([mislabeled, good], _en)?.track, good);
        expect(run([good, mislabeled], _en)?.track, good);
        const goodForced = SubtitleTrack(id: '22', language: 'fra', title: 'Forced', isForced: true);
        const mislabeledForced = SubtitleTrack(id: '23', language: 'eng', title: 'French Forced');
        expect(run([mislabeledForced, goodForced], _fr)?.track, goodForced);
      });

      test('CA5: title and declared language agree', () {
        const agree = SubtitleTrack(id: '30', language: 'fra', title: 'Français');
        expect(run([_subEnFull, agree], _en)?.track, agree);
      });

      test('CA6: no title or a neutral title leaves the declared language', () {
        const untitled = SubtitleTrack(id: '31', language: 'eng');
        const neutral = SubtitleTrack(id: '32', language: 'eng', title: 'SDH');
        const both = SubtitleTrack(id: '33', language: 'eng', title: 'English / French');
        expect(run([untitled, neutral, both], _en)?.track, SubtitleTrack.off);
      });

      test('an embedded native track titled French is French', () {
        const embedded = SubtitleTrack(id: '34', language: 'eng', title: 'French Complet');
        expect(run([embedded], _en)?.track, embedded);
      });

      test('an external native track: its title (a file name) is not read', () {
        const wrongName = SubtitleTrack(id: '35', language: 'eng', title: 'movie.fr.srt', isExternal: true);
        expect(run([wrongName], _en)?.track, SubtitleTrack.off);
        const rightLanguage = SubtitleTrack(
          id: '36',
          language: 'fra',
          title: 'subs-en.srt',
          isExternal: true,
          uri: 'file:///subs-en.srt',
        );
        expect(run([rightLanguage], _en)?.track, rightLanguage);
        const english = SubtitleTrack(id: '37', language: 'eng', title: 'subs-en.srt', isExternal: true);
        expect(run([english], _en)?.track, SubtitleTrack.off);
      });

      test('a server row without a title: its display titles are not read', () {
        final fabricated = row(13, null, displayTitle: 'French Complet (English SRT)');
        final descriptor = PlaybackSubtitleResolver.subtitleTrackForSource(fabricated);
        // The descriptor falls back to the display title, but the rule must not.
        expect(descriptor.title, 'French Complet (English SRT)');
        final fabricatedInfo = _info(const [], subtitles: [fabricated]);
        expect(run([descriptor], _en, info: fabricatedInfo)?.track, SubtitleTrack.off);
      });

      test('a source descriptor whose row is unknown has no author title', () {
        const stale = SubtitleTrack(id: 'source:99', language: 'eng', title: 'French Complet');
        expect(run([stale], _en, info: _info(const [], subtitles: [english]))?.track, SubtitleTrack.off);
      });

      test('S3: a row only titled French, not arrived natively yet, waits for the upstream ladder', () {
        expect(run([_subEnFull], _en, info: info), isNull);
        // Once the native track carrying the title is there, the rule decides.
        const arrived = SubtitleTrack(id: '40', language: 'eng', title: 'French Complet');
        expect(run([_subEnFull, arrived], _en, info: info)?.track, arrived);
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
