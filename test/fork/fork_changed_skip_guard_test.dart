// FORK: langues-preferees — every forkChangedSkip in upstream tests must be listed by name.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fork_test_utils.dart';

void main() {
  test('forkChangedSkip uses match forkChangedSkipAllowlist', () {
    final counts = <String, int>{};
    final testDir = Directory('test');
    for (final entity in testDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('test/fork/')) continue;
      final occurrences = 'forkChangedSkip'.allMatches(entity.readAsStringSync()).length;
      // The constant's own import/definition never appears outside test/fork/.
      if (occurrences > 0) counts[path] = occurrences;
    }

    final total = counts.values.fold<int>(0, (sum, n) => sum + n);
    expect(total, forkChangedSkipAllowlist.length, reason: 'forkChangedSkip uses: $counts');

    for (final key in forkChangedSkipAllowlist.keys) {
      final file = key.split(' :: ').first;
      expect(counts.containsKey(file), isTrue, reason: '$file is listed but contains no forkChangedSkip');
    }
  });
}
