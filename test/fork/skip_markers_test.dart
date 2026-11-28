import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/skip_markers.dart';
import 'package:plezy/media/chapter_marker_classifier.dart';
import 'package:plezy/media/media_source_info.dart';

MediaChapter ch(int id, String? title, int start, int end) =>
    MediaChapter(id: id, index: id, startTimeOffset: start, endTimeOffset: end, title: title);

MediaMarker mk(int id, String type, int start, int end) =>
    MediaMarker(id: id, type: type, startTimeOffset: start, endTimeOffset: end);

List<(String, int, int)> flat(PlaybackExtras e) => [
  for (final m in e.markers) (m.type, m.startTimeOffset, m.endTimeOffset),
];

PlaybackExtras run(
  List<MediaChapter> chapters, [
  List<MediaMarker> markers = const [],
  String? intro,
  String? credits,
]) => ForkSkipMarkers.apply(
  PlaybackExtras(chapters: chapters, markers: markers),
  introPattern: intro,
  creditsPattern: credits,
);

void main() {
  group('titles', () {
    test('recap titles', () {
      for (final t in [
        'Previously',
        "Previously on The Handmaid's Tale…",
        'Recap',
        'RÉCAP',
        'Récapitulatif',
        'Résumé',
        'Précédemment',
        'Précédemment dans…',
        'Last time on…',
      ]) {
        expect(ForkSkipMarkers.isRecapTitle(t), isTrue, reason: t);
      }
      for (final t in ['Recapture', 'Résumé du film', 'Scene 1', 'Closing Day', '']) {
        expect(ForkSkipMarkers.isRecapTitle(t), isFalse, reason: t);
      }
      expect(ForkSkipMarkers.isRecapTitle(null), isFalse);
    });

    test('normalizeTitle', () {
      expect(ForkSkipMarkers.normalizeTitle('  Précédemment   Dans… '), 'precedemment dans');
      expect(ForkSkipMarkers.normalizeTitle('L’œuvre'), "l'oeuvre");
    });
  });

  group('recap', () {
    final chapters = [ch(1, 'Recap', 0, 79000), ch(2, 'Scene 1', 79000, 2682000), ch(3, 'Credits', 2682000, 2900000)];

    test('CA15 recap becomes intro, credits unchanged', () {
      final out = run(chapters, [mk(9, 'credits', 2682000, 2900000)]);
      expect(flat(out), [('intro', 0, 79000), ('credits', 2682000, 2900000)]);
    });

    test('CA5 too long', () {
      final out = run([ch(1, 'Recap', 0, 301000), ch(2, 'Scene', 301000, 3000000)]);
      expect(out.markers, isEmpty);
    });

    test('CA6 starts too late', () {
      final out = run([
        ch(1, 'Scene', 0, 1000000),
        ch(2, 'Résumé', 1000000, 1060000),
        ch(3, 'Scene', 1060000, 3000000),
      ]);
      expect(out.markers, isEmpty);
    });

    test('CA3 server recap without chapters', () {
      expect(flat(run([], [mk(1, ForkSkipMarkers.recapType, 0, 4000)])), [('intro', 0, 4000)]);
    });

    test('CA4b chaining', () {
      expect(flat(run([], [mk(1, ForkSkipMarkers.recapType, 0, 79000), mk(2, 'intro', 82000, 170000)])), [
        ('intro', 0, 170000),
      ]);
      expect(flat(run([], [mk(1, ForkSkipMarkers.recapType, 0, 79000), mk(2, 'intro', 85000, 170000)])), [
        ('intro', 0, 79000),
        ('intro', 85000, 170000),
      ]);
      expect(flat(run([], [mk(1, ForkSkipMarkers.recapType, 0, 90000), mk(2, 'intro', 60000, 170000)])), [
        ('intro', 0, 170000),
      ]);
    });

    test('CA11 intro without recap is identical', () {
      final out = run([ch(1, 'Scene 1', 0, 3000000)], [mk(2, 'intro', 10000, 40000)]);
      expect(flat(out), [('intro', 10000, 40000)]);
    });
  });

  group('French words', () {
    final scenes = ch(2, 'Scene', 200000, 2400000);

    test('CA7 intro words', () {
      for (final t in ['Générique', 'Générique de début', 'Ouverture']) {
        final out = run([ch(1, t, 0, 90000), scenes, ch(3, 'x', 2400000, 3000000)]);
        expect(flat(out), [('intro', 0, 90000)], reason: t);
      }
      expect(run([ch(1, 'Ouverture', 0, 240000), ch(3, 'x', 240000, 3000000)]).markers, isEmpty);
      final existing = run([ch(1, 'Ouverture', 0, 90000), ch(3, 'x', 90000, 3000000)], [mk(5, 'intro', 5000, 60000)]);
      expect(flat(existing), [('intro', 5000, 60000)]);
    });

    test('CA8 credits words', () {
      for (final t in ['Générique', 'Générique de fin', 'Fin']) {
        final out = run([ch(1, 'Scene', 0, 2600000), ch(2, t, 2600000, 3000000)]);
        expect(flat(out), [('credits', 2600000, 3000000)], reason: t);
      }
      expect(
        run([ch(1, 'Scene', 0, 1500000), ch(2, 'Fin', 1500000, 1600000), ch(3, 'x', 1600000, 3000000)]).markers,
        isEmpty,
      );
    });

    test('CA12 custom pattern wins, recap still detected', () {
      final chapters = [ch(1, 'Résumé', 0, 60000), ch(2, 'Générique', 60000, 120000), ch(3, 'x', 120000, 3000000)];
      expect(flat(run(chapters, [], 'prologue')), [('intro', 0, 60000)]);
      expect(flat(run(chapters, [], PlaybackExtras.defaultIntroPattern)), [('intro', 0, 120000)]);
    });

    test('max intro duration constant', () {
      final d = ChapterMarkerClassifier.maxIntroDuration.inMilliseconds;
      expect(run([ch(1, 'Ouverture', 0, d + 1), ch(2, 'x', d + 1, 9000000)]).markers, isEmpty);
    });
  });

  test('CA13 empty extras returns the same instance', () {
    final extras = PlaybackExtras(chapters: [], markers: []);
    expect(identical(ForkSkipMarkers.apply(extras), extras), isTrue);
  });
}
