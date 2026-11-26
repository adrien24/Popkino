// Copie Dart de la table d'identité de docs/technique/nouvelle-identite/plan.md,
// vérifiée par scripts/fork/check_identity.py. Modifier les deux ensemble.
// FORK: identité Popkino
abstract final class ForkIdentity {
  ForkIdentity._();

  /// Nom affiché de l'application.
  static const String appName = 'Popkino';

  /// Slug (identifiant minuscule) : serveurs, journaux, préfixes de fichiers.
  static const String appSlug = 'popkino';

  /// Schéma d'URL des liens profonds (`popkino://`).
  static const String urlScheme = 'popkino';

  /// Dépôt GitHub des versions.
  static const String githubRepo = 'adrien24/popkino';

  /// Adresse du code source.
  static const String sourceCodeUrl = 'https://github.com/adrien24/popkino';

  /// Flux Sparkle/WinSparkle de mise à jour (macOS et Windows).
  static const String updateFeedUrl = 'https://cdn.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml';

  /// Projet d'origine dont Popkino est dérivé.
  static const String upstreamName = 'Plezy';

  /// Adresse du projet d'origine.
  static const String upstreamUrl = 'https://github.com/edde746/plezy';

  /// Licence du code.
  static const String licenseName = 'GPL-3.0';
}
