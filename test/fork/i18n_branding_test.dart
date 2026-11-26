import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/fork_identity.dart';
import 'package:plezy/i18n/strings.g.dart';

/// Collects `path -> value` for every string leaf, skipping the top-level `fork` branch.
void _collectStrings(Object? node, String path, Map<String, String> out) {
  if (node is Map) {
    node.forEach((key, value) {
      if (path.isEmpty && key == 'fork') return;
      _collectStrings(value, path.isEmpty ? '$key' : '$path.$key', out);
    });
  } else if (node is List) {
    for (final item in node) {
      _collectStrings(item, path, out);
    }
  } else if (node is String) {
    out[path] = node;
  }
}

void main() {
  final i18nDir = Directory('lib/i18n');
  final files = i18nDir.listSync().whereType<File>().where((f) => f.path.endsWith('.i18n.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('all 23 translation files are found', () {
    expect(files.length, 23);
  });

  for (final file in files) {
    test('no value of ${file.uri.pathSegments.last} mentions Plezy outside fork.*', () {
      final strings = <String, String>{};
      _collectStrings(jsonDecode(file.readAsStringSync()), '', strings);
      final offenders = strings.entries.where((e) => e.value.contains('Plezy')).map((e) => e.key).toList();
      expect(offenders, isEmpty, reason: 'run scripts/fork/rebrand_i18n.py then scripts/codegen.sh');
    });
  }

  for (final locale in [AppLocale.en, AppLocale.fr]) {
    test('app title is the fork name in ${locale.languageCode}', () async {
      // Non-English locales are deferred libraries: load them asynchronously.
      await LocaleSettings.setLocale(locale);
      addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
      expect(t.app.title, ForkIdentity.appName);
    });
  }

  test('services description no longer cites MyAnimeList', () async {
    addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
    for (final locale in AppLocale.values) {
      await LocaleSettings.setLocale(locale);
      expect(t.settings.servicesDescription, isNot(contains('MyAnimeList')), reason: locale.languageTag);
    }
  });

  for (final locale in [AppLocale.en, AppLocale.fr]) {
    test('about notice is filled in ${locale.languageCode}', () async {
      await LocaleSettings.setLocale(locale);
      addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
      expect(t.fork.about.basedOn, isNotEmpty);
    });
  }
}
