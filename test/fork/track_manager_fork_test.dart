// FORK: langues-preferees — TrackManager flags manual and carried picks.
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/fork/track_choice_memory.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/mpv/player/player_stream_controllers.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/subtitle_preference.dart';
import 'package:plezy/services/track_manager.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

class _FakePlayer with PlayerStreamControllersMixin implements Player {
  _FakePlayer({Tracks tracks = const Tracks()}) : _state = PlayerState(tracks: tracks);

  final PlayerState _state;

  @override
  PlayerState get state => _state;

  late final PlayerStreams _streams = createStreams();

  @override
  PlayerStreams get streams => _streams;

  @override
  bool get disposed => false;

  final List<AudioTrack> selectedAudio = [];
  final List<SubtitleTrack> selectedSubtitle = [];

  @override
  Future<void> selectAudioTrack(AudioTrack t) async => selectedAudio.add(t);

  @override
  Future<void> selectSubtitleTrack(SubtitleTrack t) async => selectedSubtitle.add(t);

  @override
  Future<void> setRate(double rate) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final MediaItem _item = testMediaItem(id: 'ep1', serverId: 'srv', backend: MediaBackend.plex, kind: MediaKind.episode);

const _audio = [AudioTrack(id: '1', language: 'eng'), AudioTrack(id: '2', language: 'fre')];
const _subs = [SubtitleTrack(id: '10', language: 'eng'), SubtitleTrack(id: '11', language: 'fre')];

MediaSourceInfo _info({bool selected = true}) => MediaSourceInfo(
  videoUrl: 'https://example.com/video.mkv',
  partId: 4242,
  audioTracks: [
    MediaAudioTrack(id: 1, languageCode: 'eng', selected: selected),
    MediaAudioTrack(id: 2, languageCode: 'fre', selected: false),
  ],
  subtitleTracks: [
    MediaSubtitleTrack(id: 10, languageCode: 'eng', selected: false, forced: false),
    MediaSubtitleTrack(id: 11, languageCode: 'fre', selected: false, forced: false),
  ],
  chapters: const [],
);

Future<bool> _okPersister({required int partId, required String trackType, required int streamID}) async => true;

TrackManager _make(
  _FakePlayer player, {
  TrackPreferencePersister? persister,
  AudioTrack? preferredAudioTrack,
  SubtitleTrack? preferredSubtitleTrack,
  MediaSourceInfo? mediaInfo,
}) {
  return TrackManager(
    player: player,
    isActive: () => true,
    persistTrackPreference: persister ?? _okPersister,
    getProfileSettings: () => null,
    waitForProfileSettings: () async {},
    metadata: _item,
    mediaInfo: mediaInfo ?? _info(),
    preferredAudioTrack: preferredAudioTrack,
    preferredSubtitleTrack: SubtitlePreference.trackOrNull(preferredSubtitleTrack),
  );
}

Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    ForkTrackChoiceMemory.resetForTesting();
  });
  tearDown(ForkTrackChoiceMemory.resetForTesting);

  bool picked(ForkTrackKind kind) => ForkTrackChoiceMemory.hasManualPick(_item, kind);

  test('explicit audio and subtitle picks set the flag when remembering is on', () async {
    await SettingsService.getInstance();
    final mgr = _make(
      _FakePlayer(
        tracks: const Tracks(audio: _audio, subtitle: _subs),
      ),
    );
    addTearDown(mgr.dispose);

    await mgr.onAudioTrackSelectedByUser(_audio[1]);
    await _drain();
    expect(picked(ForkTrackKind.audio), isTrue);
    expect(picked(ForkTrackKind.subtitle), isFalse);

    await mgr.onSubtitleTrackSelectedByUser(_subs[1]);
    await _drain();
    expect(picked(ForkTrackKind.subtitle), isTrue);
  });

  test('remembering off: nothing is flagged', () async {
    final svc = await SettingsService.getInstance();
    await svc.write(SettingsService.rememberTrackSelections, false);
    final mgr = _make(
      _FakePlayer(
        tracks: const Tracks(audio: _audio, subtitle: _subs),
      ),
    );
    addTearDown(mgr.dispose);

    await mgr.onAudioTrackSelectedByUser(_audio[1]);
    await mgr.onSubtitleTrackSelectedByUser(_subs[1]);
    await _drain();

    await svc.write(SettingsService.rememberTrackSelections, true);
    ForkTrackChoiceMemory.resetForTesting();
    expect(svc.read(ForkTrackChoiceMemory.pref), isEmpty);
  });

  test('a carried (navigation) preference that gets applied counts as manual (CA4ter)', () async {
    await SettingsService.getInstance();
    final player = _FakePlayer(
      tracks: const Tracks(audio: _audio, subtitle: _subs),
    );
    final mgr = _make(player, preferredAudioTrack: _audio[1], preferredSubtitleTrack: _subs[1]);
    addTearDown(mgr.dispose);

    await mgr.applyTrackSelection();
    await _drain();

    expect(player.selectedAudio.map((t) => t.id), ['2']);
    expect(picked(ForkTrackKind.audio), isTrue);
    expect(picked(ForkTrackKind.subtitle), isTrue);
  });

  test('automatic profile / serverSelected selections do not set the flag', () async {
    await SettingsService.getInstance();
    final player = _FakePlayer(
      tracks: const Tracks(audio: _audio, subtitle: _subs),
    );
    // No profile and no carried preference: the server-selected audio is applied.
    final mgr = _make(player);
    addTearDown(mgr.dispose);

    await mgr.applyTrackSelection();
    await _drain();

    expect(player.selectedAudio.map((t) => t.id), ['1']);
    expect(picked(ForkTrackKind.audio), isFalse);
    expect(picked(ForkTrackKind.subtitle), isFalse);
  });

  test('CA10: transient error then 4xx refusal never throw, track applied, flag set', () async {
    await SettingsService.getInstance();
    final player = _FakePlayer(
      tracks: const Tracks(audio: _audio, subtitle: _subs),
    );
    var calls = 0;
    final mgr = _make(
      player,
      persister: ({required int partId, required String trackType, required int streamID}) async {
        calls++;
        if (calls == 1) {
          throw MediaServerHttpException(type: MediaServerHttpErrorType.connectionTimeout, message: 'timed out');
        }
        throw MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 403, message: 'HTTP 403');
      },
    );
    addTearDown(mgr.dispose);

    // The screen applies the track on the player before notifying the manager.
    await player.selectAudioTrack(_audio[1]);
    await mgr.onAudioTrackSelectedByUser(_audio[1]);
    await player.selectSubtitleTrack(_subs[1]);
    await mgr.onSubtitleTrackSelectedByUser(_subs[1]);
    await _drain();

    expect(calls, 2);
    expect(player.selectedAudio.map((t) => t.id), ['2']);
    expect(player.selectedSubtitle.map((t) => t.id), ['11']);
    expect(picked(ForkTrackKind.audio), isTrue);
    expect(picked(ForkTrackKind.subtitle), isTrue);
  });
}
