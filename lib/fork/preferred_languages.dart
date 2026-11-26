// FORK: langues-preferees — "preferred language first" rule for the track selection ladder.
// FORK: meilleure-piste-audio — channel rule among the tracks of that language.
// FORK: sous-titres-mal-etiquetes — subtitle language read from the author's own title.
//
// Both functions return null when the rule has nothing to say, in which case
// the upstream ladder applies untouched. See
// `docs/technique/langues-preferees/plan.md` for the reasoning behind each case.
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_user_profile.dart';
import '../media/media_source_info.dart';
import '../mpv/mpv.dart';
import '../providers/account_preferences_controller.dart';
import '../services/playback_initialization_types.dart';
import '../services/playback_subtitle_resolver.dart';
import '../services/track_selection_service.dart';
import '../utils/app_logger.dart';
import '../utils/subtitle_forced_semantics.dart';
import 'audio_output.dart';
import 'subtitle_title_language.dart';
import 'track_choice_memory.dart';

/// The profile when the rule may act at all (conditions shared by audio and
/// subtitles), or null (A1/S1): no profile, "choose audio by language" off,
/// no preferred audio language, or music.
MediaServerUserProfile? _activeProfile(TrackSelectionService service) =>
    _profileIfRuleApplies(service.profileSettings, service.metadata);

MediaServerUserProfile? _profileIfRuleApplies(MediaServerUserProfile? profile, MediaItem item) {
  if (profile == null || !profile.autoSelectAudio) return null;
  final audioLanguage = profile.defaultAudioLanguage;
  if (audioLanguage == null || audioLanguage.isEmpty) return null;
  if (item.kind == MediaKind.track) return null;
  return profile;
}

/// The audio row the server has chosen for this item, if any.
MediaAudioTrack? _serverAudioRow(TrackSelectionService service) {
  final info = service.plexMediaInfo;
  if (info == null) return null;
  for (final row in info.audioTracks) {
    if (row.selected) return row;
  }
  if (!service.metadata.backend.usesMediaBrowserApi) return null;
  final defaultIndex = info.defaultAudioStreamIndex;
  if (defaultIndex == null) return null;
  for (final row in info.audioTracks) {
    if ((row.index ?? row.id) == defaultIndex) return row;
  }
  return null;
}

/// Words that mark a commentary or audio-description track in its title.
const Set<String> _specialAudioWords = {
  'commentary',
  'commentaries',
  'commentaire',
  'commentaires',
  'description',
  'audiodescription',
  'descriptive',
  'ad',
  'dvs',
};

final RegExp _nonLetters = RegExp(r'[^\p{L}]+', unicode: true);

/// Whether [title] says the track is a commentary or an audio description: a
/// whole word of the lowercased title (split on anything that is not a letter)
/// is one of [_specialAudioWords]. Such tracks never take part in the channel
/// rule (meilleure-piste-audio, CA11).
bool forkIsSpecialAudioTrack(String? title) {
  if (title == null || title.isEmpty) return false;
  return title.toLowerCase().split(_nonLetters).any(_specialAudioWords.contains);
}

/// Channel rule (meilleure-piste-audio): among the tracks [inLanguage], the one
/// that fits [output], or null when the rule has nothing to say (unknown
/// output, fewer than two tracks with a known channel count, all with the same
/// count, or no stereo track for a stereo output). Commentary and audio
/// description tracks never take part. Ties go to the `isDefault` track, then
/// the first one.
AudioTrack? forkBestTrackForOutput(List<AudioTrack> inLanguage, ForkAudioOutput output) {
  if (output == ForkAudioOutput.unknown) return null;
  final candidates = inLanguage.where((t) => t.channels != null && !forkIsSpecialAudioTrack(t.title)).toList();
  if (candidates.length < 2) return null;
  if (candidates.every((t) => t.channels == candidates.first.channels)) return null;

  final List<AudioTrack> fitting;
  if (output == ForkAudioOutput.stereo) {
    fitting = candidates.where((t) => t.channels! <= 2).toList();
  } else {
    final most = candidates.map((t) => t.channels!).reduce((a, b) => a > b ? a : b);
    fitting = candidates.where((t) => t.channels == most).toList();
  }
  if (fitting.isEmpty) return null;
  return fitting.where((t) => t.isDefault).firstOrNull ?? fitting.first;
}

/// Audio rule: the track in the profile's preferred language, unless the user
/// picked by hand (A3) or the file has no such track (A4). Among several tracks
/// in that language, the channel rule picks by the "Canaux audio" setting and
/// wins even over the server's choice. Otherwise the server's language choice
/// is kept (A2).
TrackSelectionResult<AudioTrack>? forkPreferredAudio(TrackSelectionService service, List<AudioTrack> availableTracks) {
  if (availableTracks.isEmpty) return null;
  final profile = _activeProfile(service);
  if (profile == null) return null;
  final preferred = profile.defaultAudioLanguage!;

  if (ForkTrackChoiceMemory.hasManualPick(service.metadata, ForkTrackKind.audio)) return null;

  final inLanguage = availableTracks.where((t) => service.languageMatches(t.language, preferred)).toList();
  if (inLanguage.isEmpty) return null;

  final output = forkAudioOutput();
  final best = forkBestTrackForOutput(inLanguage, output);
  if (best != null) {
    appLogger.d(
      'Fork preferred language: audio $preferred, channels ${output == ForkAudioOutput.stereo ? 'stereo' : 'most'}',
    );
    return TrackSelectionResult(best, TrackSelectionPriority.profile);
  }

  final serverRow = _serverAudioRow(service);
  if (serverRow != null && service.languageMatches(serverRow.languageCode ?? serverRow.language, preferred)) {
    return null;
  }

  final track = inLanguage.where((t) => t.isDefault).firstOrNull ?? inLanguage.first;
  appLogger.d('Fork preferred language: audio $preferred, current order');
  return TrackSelectionResult(track, TrackSelectionPriority.profile);
}

/// Subtitle rule: follow the profile's subtitle mode with the preferred
/// subtitle language, judged against the audio actually selected. Never picks a
/// subtitle in another language (CA7).
TrackSelectionResult<SubtitleTrack>? forkPreferredSubtitle(
  TrackSelectionService service,
  List<SubtitleTrack> availableTracks,
  AudioTrack? selectedAudioTrack,
) {
  final profile = _activeProfile(service);
  if (profile == null) return null;
  final subtitleLanguage = profile.defaultSubtitleLanguage;
  if (subtitleLanguage == null || subtitleLanguage.isEmpty) return null;
  final mode = profile.subtitleMode;
  if (mode != SubtitlePlaybackMode.always &&
      mode != SubtitlePlaybackMode.smart &&
      mode != SubtitlePlaybackMode.onlyForced) {
    return null;
  }
  if (ForkTrackChoiceMemory.hasManualPick(service.metadata, ForkTrackKind.subtitle)) return null;

  final announced = service.plexMediaInfo?.subtitleTracks ?? const <MediaSubtitleTrack>[];

  // The title the file's author wrote, never a display title the server builds
  // from the declared language. A `source:<N>` descriptor reads the server row's
  // own title; a native embedded track reads its container title; an external
  // native track has none (mpv derives its title from the file name or URL).
  String? authorTitle(SubtitleTrack t) {
    if (t.id.startsWith('source:')) {
      final rowId = int.tryParse(t.id.substring('source:'.length));
      return announced.where((row) => row.id == rowId).firstOrNull?.title;
    }
    return t.isExternal ? null : t.title;
  }

  // The language the title names, else the declared one. Only used by this rule:
  // tracks and their labels are never changed.
  String? effectiveLanguage(SubtitleTrack t) => forkLanguageNamedByTitle(authorTitle(t)) ?? t.language;

  bool inSubtitleLanguage(SubtitleTrack t) => service.languageMatches(effectiveLanguage(t), subtitleLanguage);

  // S3: a native track of the preferred language is announced but has not
  // arrived yet; the upstream ladder handles the wait.
  if (!availableTracks.any(inSubtitleLanguage)) {
    if (announced.any(
      (row) => service.languageMatches(
        forkLanguageNamedByTitle(row.title) ?? (row.languageCode ?? row.language),
        subtitleLanguage,
      ),
    )) {
      return null;
    }
  }

  // CA7: tracks declared in the preferred language come before those that only
  // their title puts there. Order inside each group is kept.
  List<SubtitleTrack> inLanguage(bool Function(SubtitleTrack) test) {
    final matching = availableTracks.where((t) => inSubtitleLanguage(t) && test(t)).toList();
    return [
      ...matching.where((t) => service.languageMatches(t.language, subtitleLanguage)),
      ...matching.where((t) => !service.languageMatches(t.language, subtitleLanguage)),
    ];
  }

  SubtitleTrack? forced() => inLanguage((t) => t.effectiveForced).firstOrNull;
  SubtitleTrack? full() {
    final candidates = inLanguage((t) => !t.effectiveForced);
    // Well-labeled tracks first: the isDefault rule only looks inside the best group.
    final wellLabeled = candidates.where((t) => service.languageMatches(t.language, subtitleLanguage)).toList();
    final pool = wellLabeled.isNotEmpty ? wellLabeled : candidates;
    final preferredFull = pool.where((t) => t.isDefault).firstOrNull ?? pool.firstOrNull;
    return preferredFull ?? forced();
  }

  final audioInSubtitleLanguage =
      selectedAudioTrack != null && service.languageMatches(selectedAudioTrack.language, subtitleLanguage);
  final audioInPreferredAudioLanguage =
      selectedAudioTrack != null && service.languageMatches(selectedAudioTrack.language, profile.defaultAudioLanguage);

  final SubtitleTrack? chosen;
  if (mode != SubtitlePlaybackMode.onlyForced && audioInSubtitleLanguage) {
    chosen = forced();
  } else if (mode == SubtitlePlaybackMode.always) {
    chosen = full();
  } else if (mode == SubtitlePlaybackMode.smart) {
    chosen = audioInPreferredAudioLanguage ? forced() : full();
  } else {
    chosen = forced();
  }

  appLogger.d('Fork preferred language: subtitle $subtitleLanguage ($mode) over server selection');
  if (chosen != null && !service.languageMatches(chosen.language, subtitleLanguage)) {
    appLogger.d(
      'Fork preferred language: subtitle title says ${effectiveLanguage(chosen)}, declared ${chosen.language}',
    );
  }
  return TrackSelectionResult(chosen ?? SubtitleTrack.off, TrackSelectionPriority.profile);
}

/// Longest wait for the active profile to load before a launch, so a cold start
/// (resume row, deep link) does not resolve the stream without the preference.
const Duration _launchProfileWait = Duration(seconds: 2);

/// Audio intent to hand to the stream resolver at launch: the profile's
/// preferred language as a semantic carry (never an item-bound id). Backends
/// resolve it for the transcoder; direct play ignores it beyond the active
/// stream id. Returns null when the rule does not apply (A1) or the user picked
/// by hand (A3). Waits at most 2 s, and only when the profile is not loaded yet.
Future<AudioTrack?> forkLaunchAudioIntent({
  required MediaItem item,
  required AccountPreferencesController controller,
}) async {
  if (controller.activePreferences == null) {
    try {
      await controller.ensureActiveLoaded().timeout(_launchProfileWait);
    } catch (e) {
      appLogger.d('Fork preferred language: profile not ready for the launch intent', error: e);
    }
  }
  final profile = _profileIfRuleApplies(controller.activePreferences, item);
  if (profile == null) return null;
  if (ForkTrackChoiceMemory.hasManualPick(item, ForkTrackKind.audio)) return null;
  // Target channel count for the transcoder's evidence bands (parity tiebreaker);
  // nothing for "original", which keeps today's behaviour.
  final channels = switch (forkAudioOutput()) {
    ForkAudioOutput.stereo => 2,
    ForkAudioOutput.multichannel => 6,
    ForkAudioOutput.unknown => null,
  };
  return AudioTrack(id: carriedAudioTrackId, language: profile.defaultAudioLanguage, channels: channels);
}

/// The audio descriptor of the stream a transcode actually sends, so subtitles
/// are resolved for that audio (CA6/CA12) even when the intent was declined.
/// Null for direct play or when the row is unknown.
AudioTrack? forkTranscodedAudioAnchor(PlaybackInitializationResult result) {
  final info = result.mediaInfo;
  if (!result.isTranscoding || info == null) return null;
  final activeId = result.activeAudioStreamId;
  MediaAudioTrack? row;
  if (activeId != null) {
    row = info.audioTracks.where((t) => t.id == activeId).firstOrNull;
  }
  row ??= info.audioTracks.where((t) => t.selected).firstOrNull;
  return row == null ? null : PlaybackSubtitleResolver.audioTrackForSource(row);
}

/// The value `_selectedAudioStreamId` takes after a session commit. With direct
/// play the launch intent comes back as the active stream id; keeping it would
/// send it to the transcoder on a later quality change and undo a manual pick
/// made in the player. When transcoding, the id is the stream really sent.
int? forkAudioStreamIdAfterCommit({
  required int? sessionAudioStreamId,
  required bool launchIntentUsed,
  required bool isTranscoding,
}) => launchIntentUsed && !isTranscoding ? null : sessionAudioStreamId;
