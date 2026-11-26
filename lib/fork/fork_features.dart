// FORK: fonctionnalités des services du projet Plezy coupées dans Popkino
import '../services/supporter/supporter_mode.dart';

/// Services du projet Plezy interdits par TRADEMARKS.md : tout reste à `false`.
/// Réactivation possible via le backlog `services-suivi`.
// FORK: services Plezy coupés
abstract final class ForkFeatures {
  ForkFeatures._();

  /// Envoi des rapports de plantage vers le service Sentry de Plezy.
  static const bool plezyCrashReporting = false;

  /// Envoi des journaux vers le service de Plezy.
  static const bool plezyLogUpload = false;

  /// Présence Discord de Plezy.
  static const bool discordPresence = false;

  /// Dons vers le projet Plezy.
  static const bool donations = false;

  /// Icônes d'application alternatives (retirées de Popkino).
  static const bool alternateAppIcons = false;

  /// Trackers d'anime (MyAnimeList, AniList) et leurs mappages.
  static const bool animeTrackers = false;

  /// Migration de la base de bureau héritée de Plezy (`plezy_downloads.db`).
  static const bool legacyPlezyMigrations = false;

  /// Mode Supporter imposé : les avantages sont débloqués sans boutique.
  static const SupporterMode forkSupporterMode = SupporterMode.unlocked;
}
