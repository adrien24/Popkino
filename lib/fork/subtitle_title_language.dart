// FORK: sous-titres-mal-etiquetes — language named by a subtitle's own title.
//
// Pure function, no dependency on settings or the player. See
// `docs/technique/sous-titres-mal-etiquetes/plan.md` (decision 3) for the rules.

/// Accented Latin letters folded to their plain ASCII form before splitting.
const Map<String, String> _accentFolding = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ç': 'c',
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
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
};

/// Strong words: a language name or a VF/VOSTFR marker. They win over weak words.
const Map<String, String> _strongWords = {
  'french': 'fre',
  'francais': 'fre',
  'vf': 'fre',
  'vff': 'fre',
  'vfq': 'fre',
  'vfi': 'fre',
  'vostfr': 'fre',
  'truefrench': 'fre',
  'english': 'eng',
  'anglais': 'eng',
};

/// Weak words: short language codes. Only used when no strong word is present.
const Map<String, String> _weakWords = {'fr': 'fre', 'fre': 'fre', 'fra': 'fre', 'en': 'eng', 'eng': 'eng'};

final RegExp _nonLetters = RegExp(r'[^a-z]+');

/// Splits [title] into lowercase ASCII words, with accents removed.
List<String> _words(String title) {
  final buffer = StringBuffer();
  for (final rune in title.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentFolding[char] ?? char);
  }
  return buffer.toString().split(_nonLetters).where((w) => w.isNotEmpty).toList();
}

/// The language code (`fre` or `eng`) that a subtitle [title] names, or null.
///
/// Strong words decide alone when they name exactly one language. Otherwise,
/// and only when no strong word is present, weak words decide when they name
/// exactly one language. A title naming several languages, or none, gives null.
String? forkLanguageNamedByTitle(String? title) {
  if (title == null || title.trim().isEmpty) return null;
  final words = _words(title);

  final strong = {
    for (final w in words)
      if (_strongWords.containsKey(w)) _strongWords[w]!,
  };
  if (strong.isNotEmpty) return strong.length == 1 ? strong.single : null;

  final weak = {
    for (final w in words)
      if (_weakWords.containsKey(w)) _weakWords[w]!,
  };
  return weak.length == 1 ? weak.single : null;
}
