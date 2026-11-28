// FORK: demandes-recentes-overseerr — guard on the upstream hook lines in the library Recommended tab

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library_recommended_tab.dart carries the shelf hook, each fork line marked', () {
    final lines = File('lib/screens/libraries/tabs/library_recommended_tab.dart').readAsLinesSync();
    final source = lines.join('\n');

    expect(source, contains('ForkRecentRequestsShelf('));
    expect(source, contains('fork.activate('));
    expect(source, contains('fork.tapFor('));
    expect(source, contains('fork.iconFor('));

    for (final needle in ['recent_requests_shelf.dart', 'ForkRecentRequestsShelf(', 'fork.activate(', 'fork.tapFor(']) {
      for (final line in lines.where((l) => l.contains(needle))) {
        expect(line, contains('FORK:'), reason: 'line without FORK marker: $line');
      }
    }
    for (final line in lines.where((l) => l.contains('fork.iconFor('))) {
      expect(line, contains('FORK:'), reason: 'line without FORK marker: $line');
    }
  });

  test('media_card.dart carries the badge hook, each fork line marked', () {
    final lines = File('lib/widgets/media_card.dart').readAsLinesSync();
    final source = lines.join('\n');

    expect(source, contains('forkPosterBadge(item)'));
    expect(source, contains('recent_request_badge.dart'));
    expect(source, contains('_CatalogBadges(labels: badgeLabels)'));

    final start = lines.indexWhere((l) => l.contains('forkPosterBadge(item)'));
    expect(start, greaterThan(0));
    // The hook spans from `forkPosterBadge(item)` to the upstream `_CatalogBadges(...)` line.
    final end = lines.indexWhere((l) => l.contains('_CatalogBadges(labels: badgeLabels)'));
    expect(end, greaterThan(start));
    for (final line in [
      ...lines.sublist(start, end + 1),
      ...lines.where((l) => l.contains('recent_request_badge.dart')),
    ]) {
      expect(line, contains('FORK: demandes-recentes-overseerr'), reason: 'line without FORK marker: $line');
    }
  });

  test('library_recommended_tab.dart carries the placeholder hooks', () {
    final lines = File('lib/screens/libraries/tabs/library_recommended_tab.dart').readAsLinesSync();

    for (final needle in ['forkWarmUpRecentRequestCounts(', 'forkIsSkeletonItem(item)', 'forkSpotlightHubs(tvHubs)']) {
      final matching = lines.where((l) => l.contains(needle)).toList();
      expect(matching, isNotEmpty, reason: 'missing hook: $needle');
      for (final line in matching) {
        expect(line, contains('FORK: demandes-recentes-sans-saut'), reason: 'line without FORK marker: $line');
      }
    }
  });

  test('media_card.dart carries the skeleton hook, each fork line marked', () {
    final lines = File('lib/widgets/media_card.dart').readAsLinesSync();
    final source = lines.join('\n');

    expect(source, contains('forkSkeletonCard(context, widget.item'));
    expect(source, contains('recent_requests_skeleton.dart'));

    for (final needle in ['forkSkeletonCard(context, widget.item', 'recent_requests_skeleton.dart']) {
      for (final line in lines.where((l) => l.contains(needle))) {
        expect(line, contains('FORK: demandes-recentes-sans-saut'), reason: 'line without FORK marker: $line');
      }
    }
  });
}
