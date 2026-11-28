// FORK: motifs-marqueurs-par-defaut — hooks into the Plex/Jellyfin mappers and end-to-end behavior.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/skip_markers.dart';
import 'package:plezy/media/chapter_marker_classifier.dart';
import 'package:plezy/services/jellyfin_media_info_mapper.dart';
import 'package:plezy/services/plex_mappers.dart';

int _ticks(int ms) => ms * 10000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hooks into upstream files', () {
    test('both mappers call ForkSkipMarkers.apply(', () {
      for (final path in ['lib/services/plex_mappers.dart', 'lib/services/jellyfin_media_info_mapper.dart']) {
        expect(File(path).readAsStringSync(), contains('ForkSkipMarkers.apply('), reason: path);
      }
    });

    test('jellyfin_media_info_mapper.dart maps the Recap segment to ForkSkipMarkers.recapType', () {
      expect(
        File('lib/services/jellyfin_media_info_mapper.dart').readAsStringSync(),
        contains('ForkSkipMarkers.recapType'),
      );
    });
  });

  test('Jellyfin segments keep Recap as the internal recap type', () {
    final markers = jellyfinMediaSegmentsToMarkers({
      'Items': [
        {'Type': 'Intro', 'StartTicks': _ticks(5000), 'EndTicks': _ticks(45000)},
        {'Type': 'Outro', 'StartTicks': _ticks(90000), 'EndTicks': _ticks(100000)},
        {'Type': 'Recap', 'StartTicks': _ticks(0), 'EndTicks': _ticks(4000)},
      ],
    });

    expect(markers.map((m) => m.type), ['intro', 'credits', ForkSkipMarkers.recapType]);
    expect(markers[0].startTimeOffset, 5000);
    expect(markers[0].endTimeOffset, 45000);
    expect(markers[1].startTimeOffset, 90000);
    expect(markers[1].endTimeOffset, 100000);
    expect(markers[2].startTimeOffset, 0);
    expect(markers[2].endTimeOffset, 4000);
  });

  group('end to end with the bundled classifier', () {
    late ChapterMarkerClassifier classifier;
    setUpAll(() async => classifier = await ChapterMarkerClassifier.bundled);

    test('Plex: a leading "Recap" chapter becomes an intro marker (CA15)', () {
      final extras = plexPlaybackExtrasFromCacheJson({
        'Chapter': [
          {'id': 1, 'index': 1, 'tag': 'Recap', 'startTimeOffset': 0, 'endTimeOffset': 79000},
          {'id': 2, 'index': 2, 'tag': 'Scene 1', 'startTimeOffset': 79000, 'endTimeOffset': 2682000},
          {'id': 3, 'index': 3, 'tag': 'Credits', 'startTimeOffset': 2682000, 'endTimeOffset': 2900000},
        ],
      }, classifier: classifier);

      final intros = extras.markers.where((m) => m.type == 'intro').toList();
      expect(intros, hasLength(1));
      expect(intros.single.startTimeOffset, 0);
      expect(intros.single.endTimeOffset, 79000);
      expect(extras.markers.any((m) => m.type == ForkSkipMarkers.recapType), isFalse);
    });

    test('Jellyfin: Recap segment followed by an Intro segment chain into one intro', () {
      final extras = jellyfinPlaybackExtrasFromRaw(
        {'RunTimeTicks': _ticks(1500000)},
        'item-1',
        classifier: classifier,
        markers: jellyfinMediaSegmentsToMarkers({
          'Items': [
            {'Type': 'Recap', 'StartTicks': _ticks(0), 'EndTicks': _ticks(60000)},
            {'Type': 'Intro', 'StartTicks': _ticks(62000), 'EndTicks': _ticks(150000)},
          ],
        }),
      );

      final intros = extras.markers.where((m) => m.type == 'intro').toList();
      expect(intros, hasLength(1));
      expect(intros.single.startTimeOffset, 0);
      expect(intros.single.endTimeOffset, 150000);
      expect(extras.markers.any((m) => m.type == ForkSkipMarkers.recapType), isFalse);
    });

    test('Jellyfin: Recap segment and a chapter intro found by the model chain into one intro', () {
      final extras = jellyfinPlaybackExtrasFromRaw(
        {
          'RunTimeTicks': _ticks(1500000),
          'Chapters': [
            {'Name': 'Opening', 'StartPositionTicks': _ticks(62000)},
            {'Name': 'Episode', 'StartPositionTicks': _ticks(150000)},
          ],
        },
        'item-1',
        classifier: classifier,
        markers: jellyfinMediaSegmentsToMarkers({
          'Items': [
            {'Type': 'Recap', 'StartTicks': _ticks(0), 'EndTicks': _ticks(60000)},
          ],
        }),
      );

      final intros = extras.markers.where((m) => m.type == 'intro').toList();
      expect(intros, hasLength(1));
      expect(intros.single.startTimeOffset, 0);
      expect(intros.single.endTimeOffset, 150000);
      expect(extras.markers.any((m) => m.type == ForkSkipMarkers.recapType), isFalse);
    });
  });
}
