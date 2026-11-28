// FORK: utilitaires communs aux tests du fork
const forkRemovedSkip = 'Fonction retirée dans Popkino (TRADEMARKS.md)';

// FORK: langues-preferees — marks an upstream test whose behavior Popkino changed on purpose.
// Each use must be listed in [forkChangedSkipAllowlist] (checked by fork_changed_skip_guard_test.dart).
const forkChangedSkip = 'Comportement changé par Popkino (langues-preferees)';

/// Upstream tests marked with [forkChangedSkip]. Key: `'<path> :: <test name>'`,
/// value: the acceptance criterion that justifies the marking.
const Map<String, String> forkChangedSkipAllowlist = {
  'test/services/jellyfin_media_info_test.dart :: jellyfinPlaybackExtrasFromRaw parses native Jellyfin media segments into skip markers':
      'CA3 (motifs-marqueurs-par-defaut)',
};
