// FORK: identifiants des trackers injectés par Popkino au build
import 'package:flutter/foundation.dart';

import '../services/trackers/tracker_constants.dart';
import 'fork_features.dart';

/// Valeurs lues au build (`--dart-define`). Ce sont les seules que les
/// `static const` upstream peuvent référencer : lire un champ d'un objet
/// `const` n'est pas une expression constante en Dart.
// FORK: identifiants Popkino
abstract final class ForkTrackerDefines {
  ForkTrackerDefines._();

  static const String traktClientId = String.fromEnvironment('POPKINO_TRAKT_CLIENT_ID');
  static const String traktClientSecret = String.fromEnvironment('POPKINO_TRAKT_CLIENT_SECRET');
  static const String simklClientId = String.fromEnvironment('POPKINO_SIMKL_CLIENT_ID');
  static const String mdblistClientId = String.fromEnvironment('POPKINO_MDBLIST_CLIENT_ID');
}

/// Identifiants des trackers. Utilisé seulement par [ForkTrackers].
// FORK: identifiants Popkino
class ForkTrackerCredentials {
  const ForkTrackerCredentials({
    required this.traktClientId,
    required this.traktClientSecret,
    required this.simklClientId,
    required this.mdblistClientId,
  });

  final String traktClientId;
  final String traktClientSecret;
  final String simklClientId;
  final String mdblistClientId;
}

/// Décide quels trackers sont proposés dans cette build. Un tracker sans
/// identifiants est masqué.
// FORK: identifiants Popkino
abstract final class ForkTrackers {
  ForkTrackers._();

  static const ForkTrackerCredentials _defined = ForkTrackerCredentials(
    traktClientId: ForkTrackerDefines.traktClientId,
    traktClientSecret: ForkTrackerDefines.traktClientSecret,
    simklClientId: ForkTrackerDefines.simklClientId,
    mdblistClientId: ForkTrackerDefines.mdblistClientId,
  );

  /// Remplace les identifiants compilés, pour les tests.
  @visibleForTesting
  static ForkTrackerCredentials? debugCredentialsOverride;

  /// Vrai si le tracker [s] est proposé dans cette build.
  static bool isOffered(TrackerService s) {
    final creds = debugCredentialsOverride ?? _defined;
    switch (s) {
      case TrackerService.mal:
      case TrackerService.anilist:
        return ForkFeatures.animeTrackers;
      case TrackerService.trakt:
        return creds.traktClientId.isNotEmpty && creds.traktClientSecret.isNotEmpty;
      case TrackerService.simkl:
        return creds.simklClientId.isNotEmpty;
      case TrackerService.mdblist:
        return creds.mdblistClientId.isNotEmpty;
    }
  }
}
