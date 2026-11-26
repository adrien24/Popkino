// FORK: garde contre le retour des services et identifiants du projet Plezy dans lib/
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/plezy_server.dart';

/// Source files where an `edde746` string stays: code behind a feature gate.
const _edde746Allowed = <String>{
  'lib/services/trackers/anime_mappings_store.dart',
  'lib/services/donation_service.dart',
  // Attribution link to the upstream project (GPL), shown in the About screen.
  'lib/fork/fork_identity.dart',
};

/// Former Plezy identifiers (Trakt, Simkl V1 and V2, MDBList) that must never
/// come back.
const _forbiddenCredentials = <String>[
  '9861e686e95c13409dd321736f903973cb9b8e5c6abd0634bec8962f52ea30f4',
  'acfa17b9d77fabd7e51175b7da6631aea69423530a6d49b3b3c38cd107cbd207',
  'ac97718a469c33eab948b63f92226106157e58fdcdd70c1b5857f1779b1d3a6a',
  'ec68bc6a9d04b3c50af8cc495f9c9bf478c2371b979aed7e3385bdb771b9b18d',
  'xOUwKUPdGEbHif6aKwW2gCxCAvFx7m0Q3jX0ZxXZ',
];

/// Drops `//` and `/* */` comments while leaving string literals intact, so
/// `'https://…'` is not mistaken for a comment.
String _stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (c == '/' && next == '*') {
      final end = source.indexOf('*/', i + 2);
      i = end == -1 ? source.length : end + 2;
    } else if (c == "'" || c == '"') {
      final triple = source.startsWith(c * 3, i);
      final delimiter = triple ? c * 3 : c;
      out.write(delimiter);
      i += delimiter.length;
      while (i < source.length && !source.startsWith(delimiter, i)) {
        if (source[i] == r'\' && i + 1 < source.length) {
          out.write(source[i]);
          i++;
        } else if (!triple && source[i] == '\n') {
          break;
        }
        out.write(source[i]);
        i++;
      }
      if (i < source.length && source.startsWith(delimiter, i)) {
        out.write(delimiter);
        i += delimiter.length;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

Map<String, String> _libSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart') || entity.path.endsWith('.g.dart')) continue;
    sources[entity.path.replaceAll(r'\', '/')] = _stripComments(entity.readAsStringSync());
  }
  return sources;
}

void main() {
  late Map<String, String> sources;

  setUpAll(() => sources = _libSources());

  test('the scanner ignores comments but sees string literals', () {
    expect(_stripComments("// plezy.app\nfinal a = 'https://x.test'; /* edde746 */"), "\nfinal a = 'https://x.test'; ");
    expect(_stripComments("final b = 'plezy.app';"), contains('plezy.app'));
  });

  test('lib/ never references plezy.app', () {
    final offenders = [
      for (final entry in sources.entries)
        if (entry.value.contains('plezy.app')) entry.key,
    ];
    expect(offenders, isEmpty);
  });

  test('lib/ references edde746 only behind a feature gate', () {
    final offenders = [
      for (final entry in sources.entries)
        if (entry.value.contains('edde746') && !_edde746Allowed.contains(entry.key)) entry.key,
    ];
    expect(offenders, isEmpty);
  });

  test('lib/ carries none of the former Plezy tracker credentials', () {
    final offenders = [
      for (final entry in sources.entries)
        for (final credential in _forbiddenCredentials)
          if (entry.value.contains(credential)) '${entry.key}: ${credential.substring(0, 8)}…',
    ];
    expect(offenders, isEmpty);
  });

  test('the Plezy server base URL points to a reserved .invalid host', () {
    expect(Uri.parse(plezyServerBaseUrl).host, endsWith('.invalid'));
  });
}
