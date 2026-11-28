// FORK: motifs-marqueurs-par-defaut — récap et mots français pour les marqueurs de saut
//
// Pure post-processing of [PlaybackExtras.withChapterFallback]: recaps become `intro` markers, French
// intro/credits chapter titles complete the upstream detection, and a recap chains with the intro that follows it.
// See `docs/technique/motifs-marqueurs-par-defaut/plan.md` for the decisions.

import 'package:flutter/foundation.dart';

import '../media/chapter_marker_classifier.dart';
import '../media/media_source_info.dart';

abstract final class ForkSkipMarkers {
  /// Internal marker type for a recap (Jellyfin `Recap` segment); never leaves [apply].
  static const recapType = 'recap';

  /// A recap absorbs the intro/recap markers starting less than this after its end.
  static const chainGap = Duration(seconds: 5);

  static const maxRecapDuration = Duration(minutes: 5);
  static const maxRecapStartFraction = 0.25;
  static const maxIntroStartFraction = 0.25;

  static const _accentFolding = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'œ': 'oe',
  };

  static final _recapPattern = RegExp(
    r"^(?:recap(?:itulatif)?(?:\b.*)?|previously(?: on\b.*)?|precedemment(?: dans\b.*)?|last time(?: on\b.*)?|resume)$",
  );
  static final _introOnlyPattern = RegExp(r"^(?:generique de debut|generique d'ouverture|ouverture)$");
  static final _creditsOnlyPattern = RegExp(r'^(?:generique de fin|fin)$');
  static final _ambiguousPattern = RegExp(r'^generiques?$');
  static final _trailingPunctuation = RegExp(r'[.…:!\-–—\s]+$');

  /// Lowercase, accents removed, `’` → `'`, spaces collapsed, trailing punctuation dropped.
  @visibleForTesting
  static String normalizeTitle(String title) {
    final buffer = StringBuffer();
    for (final rune in title.toLowerCase().replaceAll('’', "'").runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_accentFolding[ch] ?? ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(_trailingPunctuation, '');
  }

  @visibleForTesting
  static bool isRecapTitle(String? title) {
    if (title == null || title.isEmpty) return false;
    return _recapPattern.hasMatch(normalizeTitle(title));
  }

  static bool _custom(String? pattern, String defaultPattern) =>
      pattern != null && pattern.trim().isNotEmpty && pattern != defaultPattern;

  static PlaybackExtras apply(PlaybackExtras extras, {String? introPattern, String? creditsPattern}) {
    if (extras.chapters.isEmpty && !extras.markers.any((m) => m.type == recapType)) return extras;

    // Chapters with a usable span, as in PlaybackExtras.withChapterFallback.
    final chapters = extras.chapters;
    final spanned = <({MediaChapter chapter, int start, int end})>[];
    var runtimeMs = 0;
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final offset = ch.endTimeOffset ?? ch.startTimeOffset ?? 0;
      if (offset > runtimeMs) runtimeMs = offset;
      final start = ch.startTimeOffset;
      final end = ch.endTimeOffset ?? (i + 1 < chapters.length ? chapters[i + 1].startTimeOffset : null);
      if (start == null || end == null || end < start) continue;
      spanned.add((chapter: ch, start: start, end: end));
    }

    final minMs = ChapterMarkerClassifier.minMarkerDuration.inMilliseconds;

    bool recapOk(int start, int end) =>
        end - start >= minMs &&
        end - start <= maxRecapDuration.inMilliseconds &&
        start <= runtimeMs * maxRecapStartFraction;
    bool introOk(int start, int end) =>
        end - start >= minMs &&
        end - start <= ChapterMarkerClassifier.maxIntroDuration.inMilliseconds &&
        start <= runtimeMs * maxIntroStartFraction;
    bool creditsOk(int start, int end) =>
        end - start >= minMs && start >= runtimeMs * PlaybackExtras.minChapterCreditsStartFraction;

    final recaps = <MediaMarker>[];
    final others = <MediaMarker>[];
    for (final m in extras.markers) {
      (m.type == recapType ? recaps : others).add(m);
    }
    final recapChapterIds = <int>{};
    for (final s in spanned) {
      if (isRecapTitle(s.chapter.title) && recapOk(s.start, s.end)) {
        recapChapterIds.add(s.chapter.id);
        recaps.add(MediaMarker(id: s.chapter.id, type: recapType, startTimeOffset: s.start, endTimeOffset: s.end));
      }
    }

    final result = <MediaMarker>[...others];
    final customIntro = _custom(introPattern, PlaybackExtras.defaultIntroPattern);
    final customCredits = _custom(creditsPattern, PlaybackExtras.defaultCreditsPattern);
    final candidates = [
      for (final s in spanned)
        if (!recapChapterIds.contains(s.chapter.id) && (s.chapter.title ?? '').isNotEmpty)
          (span: s, title: normalizeTitle(s.chapter.title!)),
    ];

    int? introChapterId;
    if (!customIntro && !others.any((m) => m.type == 'intro')) {
      for (final c in candidates) {
        if ((_introOnlyPattern.hasMatch(c.title) || _ambiguousPattern.hasMatch(c.title)) &&
            introOk(c.span.start, c.span.end)) {
          introChapterId = c.span.chapter.id;
          result.add(
            MediaMarker(id: introChapterId, type: 'intro', startTimeOffset: c.span.start, endTimeOffset: c.span.end),
          );
          break;
        }
      }
    }
    if (!customCredits && !others.any((m) => m.type == 'credits')) {
      for (final c in candidates) {
        if (c.span.chapter.id == introChapterId) continue;
        if ((_creditsOnlyPattern.hasMatch(c.title) || _ambiguousPattern.hasMatch(c.title)) &&
            creditsOk(c.span.start, c.span.end)) {
          result.add(
            MediaMarker(
              id: c.span.chapter.id,
              type: 'credits',
              startTimeOffset: c.span.start,
              endTimeOffset: c.span.end,
            ),
          );
          break;
        }
      }
    }

    // Chain each recap with the intro/recap markers that follow or overlap it.
    final pool = [
      ...recaps.map((m) => (marker: m, isRecap: true)),
      ...result.where((m) => m.type == 'intro').map((m) => (marker: m, isRecap: false)),
    ]..sort((a, b) => a.marker.startTimeOffset.compareTo(b.marker.startTimeOffset));
    result.removeWhere((m) => m.type == 'intro');

    final gapMs = chainGap.inMilliseconds;
    for (var i = 0; i < pool.length; i++) {
      final entry = pool[i];
      if (!entry.isRecap) {
        result.add(entry.marker);
        continue;
      }
      var end = entry.marker.endTimeOffset;
      while (i + 1 < pool.length && pool[i + 1].marker.startTimeOffset - end < gapMs) {
        i++;
        if (pool[i].marker.endTimeOffset > end) end = pool[i].marker.endTimeOffset;
      }
      result.add(
        MediaMarker(
          id: entry.marker.id,
          type: 'intro',
          startTimeOffset: entry.marker.startTimeOffset,
          endTimeOffset: end,
        ),
      );
    }

    result.sort((a, b) => a.startTimeOffset.compareTo(b.startTimeOffset));
    return PlaybackExtras(chapters: extras.chapters, markers: result);
  }
}
