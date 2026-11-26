// FORK: langues-preferees — launch audio intent, transcode subtitle anchor and the
// post-commit audio stream id.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/preferred_languages.dart';
import 'package:plezy/fork/track_choice_memory.dart';
import 'package:plezy/media/account_preferences.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_user_profile.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/providers/account_preferences_controller.dart';
import 'package:plezy/services/playback_initialization_types.dart';
import 'package:plezy/services/playback_subtitle_resolver.dart';
import 'package:plezy/services/plex_mappers.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/track_selection_service.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

const _profile = AccountPreferences(
  selectAudioByLanguage: true,
  preferredAudioLanguage: 'en',
  preferredSubtitleLanguage: 'fr',
  subtitlePlaybackMode: SubtitlePlaybackMode.always,
);

/// A controller whose profile is set by the test; [onEnsure] stands in for the
/// real load.
class _FakeController extends AccountPreferencesController {
  _FakeController(this._prefs, {this.onEnsure});

  AccountPreferences? _prefs;
  final Future<void> Function(_FakeController self)? onEnsure;
  int ensureCalls = 0;

  @override
  AccountPreferences? get activePreferences => _prefs;

  @override
  Future<void> ensureActiveLoaded() async {
    ensureCalls++;
    await onEnsure?.call(this);
  }
}

Map<String, Object> _plexAudio(int id, String code, {bool selected = false}) => {
  'id': id,
  'streamType': 2,
  'index': id - 100,
  'codec': 'aac',
  'language': code,
  'languageCode': code,
  'channels': 2,
  if (selected) 'selected': true,
};

Map<String, Object> _plexAudioCh(int id, String code, int channels, {String? title}) => {
  'id': id,
  'streamType': 2,
  'index': id - 100,
  'codec': channels > 2 ? 'eac3' : 'aac',
  'language': code,
  'languageCode': code,
  'channels': channels,
  'title': ?title,
};

Map<String, Object> _plexSub(int id, String code, {bool forced = false}) => {
  'id': id,
  'streamType': 3,
  'index': id - 100,
  'codec': 'srt',
  'language': code,
  'languageCode': code,
  'title': 'Full',
  if (forced) 'forced': true,
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

PlaybackInitializationResult _result(MediaSourceInfo? info, {bool transcoding = false, int? activeAudio}) =>
    PlaybackInitializationResult(
      availableVersions: const [],
      mediaInfo: info,
      isTranscoding: transcoding,
      activeAudioStreamId: activeAudio,
    );

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    ForkTrackChoiceMemory.resetForTesting();
  });
  tearDown(ForkTrackChoiceMemory.resetForTesting);

  final episode = testMediaItem(id: 'ep1', serverId: 'srv', kind: MediaKind.episode);

  group('forkLaunchAudioIntent', () {
    test('loaded profile gives the English intent without waiting', () async {
      final controller = _FakeController(_profile);
      addTearDown(controller.dispose);
      final intent = await forkLaunchAudioIntent(item: episode, controller: controller);
      expect(intent, isNotNull);
      expect(intent!.id, carriedAudioTrackId);
      expect(intent.language, 'en');
      expect(controller.ensureCalls, 0);
    });

    test('audio by language off gives null', () async {
      final controller = _FakeController(
        const AccountPreferences(selectAudioByLanguage: false, preferredAudioLanguage: 'en'),
      );
      addTearDown(controller.dispose);
      expect(await forkLaunchAudioIntent(item: episode, controller: controller), isNull);
    });

    test('music gives null', () async {
      final controller = _FakeController(_profile);
      addTearDown(controller.dispose);
      final track = testMediaItem(id: 't1', serverId: 'srv', kind: MediaKind.track);
      expect(await forkLaunchAudioIntent(item: track, controller: controller), isNull);
    });

    test('a manual audio pick gives null', () async {
      await SettingsService.getInstance();
      await ForkTrackChoiceMemory.recordManualPick(episode, ForkTrackKind.audio);
      final controller = _FakeController(_profile);
      addTearDown(controller.dispose);
      expect(await forkLaunchAudioIntent(item: episode, controller: controller), isNull);
    });

    test('profile loaded by ensureActiveLoaded within 2 s gives the intent', () async {
      final controller = _FakeController(
        null,
        onEnsure: (self) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          self._prefs = _profile;
        },
      );
      addTearDown(controller.dispose);
      final intent = await forkLaunchAudioIntent(item: episode, controller: controller);
      expect(intent?.language, 'en');
      expect(controller.ensureCalls, 1);
    });

    test('profile still missing after 2 s gives null, without exception', () {
      fakeAsync((async) {
        final controller = _FakeController(null, onEnsure: (_) => Completer<void>().future);
        AudioTrack? result;
        var done = false;
        forkLaunchAudioIntent(item: episode, controller: controller).then((value) {
          result = value;
          done = true;
        });
        async.elapse(const Duration(milliseconds: 1900));
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(result, isNull);
        controller.dispose();
      });
    });

    test('an error while loading the profile gives null, without exception', () async {
      final controller = _FakeController(null, onEnsure: (_) async => throw StateError('boom'));
      addTearDown(controller.dispose);
      expect(await forkLaunchAudioIntent(item: episode, controller: controller), isNull);
    });
  });

  group('channels in the intent (meilleure-piste-audio)', () {
    Future<AudioTrack?> intentFor(AudioChannelLimit? limit) async {
      final svc = await SettingsService.getInstance();
      if (limit != null) await svc.write(SettingsService.audioChannelLimit, limit);
      final controller = _FakeController(_profile);
      addTearDown(controller.dispose);
      return forkLaunchAudioIntent(item: episode, controller: controller);
    }

    test('stereo carries 2 channels', () async {
      expect((await intentFor(AudioChannelLimit.stereo))?.channels, 2);
    });

    test('surround51 carries 6 channels', () async {
      expect((await intentFor(AudioChannelLimit.surround51))?.channels, 6);
    });

    test('original carries no channel count', () async {
      final intent = await intentFor(AudioChannelLimit.original);
      expect(intent, isNotNull);
      expect(intent!.channels, isNull);
    });

    test('the intent picks the matching English row of an S3E8-like episode', () async {
      final info = _plex([
        _plexAudioCh(101, 'eng', 2),
        _plexAudioCh(102, 'fra', 2),
        _plexAudioCh(103, 'eng', 6, title: 'ENG VO - EAC3 DDP 5.1'),
        _plexAudioCh(104, 'fra', 6),
      ]);
      final stereo = await intentFor(AudioChannelLimit.stereo);
      expect(findSourceAudioTrackForIntent(stereo!, info.audioTracks)?.id, 101);
      final multi = await intentFor(AudioChannelLimit.surround51);
      expect(findSourceAudioTrackForIntent(multi!, info.audioTracks)?.id, 103);
      final original = await intentFor(AudioChannelLimit.original);
      expect(findSourceAudioTrackForIntent(original!, info.audioTracks), isNull);
    });
  });

  group('forkTranscodedAudioAnchor', () {
    final twoEnglishPlusFrench = _plex([
      _plexAudio(101, 'eng'),
      _plexAudio(102, 'eng', selected: true),
      _plexAudio(103, 'fra'),
      _plexSub(201, 'eng'),
      _plexSub(202, 'fra'),
    ]);

    test('direct play gives null', () {
      expect(forkTranscodedAudioAnchor(_result(twoEnglishPlusFrench, activeAudio: 103)), isNull);
    });

    test('no media info gives null', () {
      expect(forkTranscodedAudioAnchor(_result(null, transcoding: true, activeAudio: 103)), isNull);
    });

    test('transcode with the active stream on French gives the French descriptor', () {
      final anchor = forkTranscodedAudioAnchor(_result(twoEnglishPlusFrench, transcoding: true, activeAudio: 103));
      expect(anchor?.id, 'source:103');
      expect(anchor?.language, 'fra');
    });

    test('transcode without an active id falls back to the selected row', () {
      final anchor = forkTranscodedAudioAnchor(_result(twoEnglishPlusFrench, transcoding: true));
      expect(anchor?.id, 'source:102');
    });

    test('transcode without any row gives null', () {
      final info = _plex([_plexSub(201, 'fra')]);
      expect(forkTranscodedAudioAnchor(_result(info, transcoding: true)), isNull);
    });

    test('subtitles for a transcode in French: no full French subtitle (CA6/CA12)', () {
      final result = _result(twoEnglishPlusFrench, transcoding: true, activeAudio: 103);
      final selection = PlaybackSubtitleResolver.resolve(
        metadata: episode,
        mediaInfo: twoEnglishPlusFrench,
        sidecars: const [],
        profileSettings: _profile,
        preferredAudioTrack: forkTranscodedAudioAnchor(result),
        isTranscoding: true,
      );
      expect(selection.isOff, isTrue);
    });
  });

  group('intent resolution on Plex', () {
    const intent = AudioTrack(id: carriedAudioTrackId, language: 'en');

    test('one English row: the intent finds it (CA1 when transcoding)', () {
      final info = _plex([_plexAudio(101, 'eng'), _plexAudio(102, 'fra', selected: true)]);
      expect(findSourceAudioTrackForIntent(intent, info.audioTracks)?.id, 101);
    });

    test('two English rows: declined (documented risk)', () {
      final info = _plex([_plexAudio(101, 'eng'), _plexAudio(102, 'eng'), _plexAudio(103, 'fra', selected: true)]);
      expect(findSourceAudioTrackForIntent(intent, info.audioTracks), isNull);
    });
  });

  group('forkAudioStreamIdAfterCommit', () {
    test('intent used with direct play: null', () {
      expect(
        forkAudioStreamIdAfterCommit(sessionAudioStreamId: 101, launchIntentUsed: true, isTranscoding: false),
        isNull,
      );
    });

    test('intent used with a transcode: the id is kept', () {
      expect(forkAudioStreamIdAfterCommit(sessionAudioStreamId: 101, launchIntentUsed: true, isTranscoding: true), 101);
    });

    test('no intent: the id is kept (upstream behavior)', () {
      expect(
        forkAudioStreamIdAfterCommit(sessionAudioStreamId: 101, launchIntentUsed: false, isTranscoding: false),
        101,
      );
      expect(
        forkAudioStreamIdAfterCommit(sessionAudioStreamId: null, launchIntentUsed: true, isTranscoding: false),
        isNull,
      );
    });
  });
}
