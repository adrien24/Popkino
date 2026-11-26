// FORK: sous-titres-mal-etiquetes — language named by a subtitle's own title
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/subtitle_title_language.dart';

void main() {
  group('forkLanguageNamedByTitle', () {
    test('strong French words, any casing', () {
      for (final title in [
        'French',
        'FRENCH',
        'french',
        'FrEnCh',
        'Francais',
        'FRANCAIS',
        'Français',
        'VF',
        'vf',
        'VFF',
        'vff',
        'VFQ',
        'vfq',
        'VFI',
        'vfi',
        'VOSTFR',
        'vostfr',
        'TrueFrench',
        'truefrench',
      ]) {
        expect(forkLanguageNamedByTitle(title), 'fre', reason: title);
      }
    });

    test('strong English words, any casing', () {
      for (final title in ['English', 'ENGLISH', 'english', 'EnGlIsH', 'Anglais', 'ANGLAIS', 'anglais']) {
        expect(forkLanguageNamedByTitle(title), 'eng', reason: title);
      }
    });

    test('weak French codes, any casing', () {
      for (final title in ['fr', 'FR', 'Fr', 'fre', 'FRE', 'fra', 'FRA']) {
        expect(forkLanguageNamedByTitle(title), 'fre', reason: title);
      }
    });

    test('weak English codes, any casing', () {
      for (final title in ['en', 'EN', 'En', 'eng', 'ENG']) {
        expect(forkLanguageNamedByTitle(title), 'eng', reason: title);
      }
    });

    test('title with a strong word keeps its language', () {
      expect(forkLanguageNamedByTitle('French Complet'), 'fre');
      expect(forkLanguageNamedByTitle('French Forced'), 'fre');
      expect(forkLanguageNamedByTitle('Français'), 'fre');
      expect(forkLanguageNamedByTitle('Sous-titres en français'), 'fre');
      expect(forkLanguageNamedByTitle('VOSTFR'), 'fre');
    });

    test('a title naming two languages gives null', () {
      expect(forkLanguageNamedByTitle('English / French'), isNull);
      expect(forkLanguageNamedByTitle('French Complet (English SRT)'), isNull);
    });

    test('VO and VOST name no language', () {
      expect(forkLanguageNamedByTitle('VO'), isNull);
      expect(forkLanguageNamedByTitle('VOST'), isNull);
    });

    test('words containing a code are not matched', () {
      expect(forkLanguageNamedByTitle('Freedom'), isNull);
      expect(forkLanguageNamedByTitle('Enfant'), isNull);
      expect(forkLanguageNamedByTitle('Frénésie'), isNull);
    });

    test('weak codes in file names are matched as whole words', () {
      expect(forkLanguageNamedByTitle('EN'), 'eng');
      expect(forkLanguageNamedByTitle('eng.srt'), 'eng');
    });

    test('a strong word wins over a conflicting weak code', () {
      expect(forkLanguageNamedByTitle('en French'), 'fre');
    });

    test('null and empty titles give null', () {
      expect(forkLanguageNamedByTitle(null), isNull);
      expect(forkLanguageNamedByTitle(''), isNull);
      expect(forkLanguageNamedByTitle('   '), isNull);
    });
  });
}
