import '../../../fork/fork_trackers.dart';

/// Bundled Trakt API credentials and base URLs.
///
/// The client_id/client_secret are extractable from the binary; this is
/// the standard pattern for native Trakt apps and is acceptable given the
/// same threat model as the Plex token already in `SharedPreferences`.
class TraktConstants {
  TraktConstants._();

  // Registered Trakt app credentials. Same threat model as the Plex token in
  // SharedPreferences — extractable from the binary, but acceptable for a
  // native client app. To rotate, update the registration at
  // https://trakt.tv/oauth/applications.
  // FORK: identifiants Popkino injectés au build
  static const String clientId = ForkTrackerDefines.traktClientId;
  static const String clientSecret = ForkTrackerDefines.traktClientSecret;

  static const String apiBase = 'https://api.trakt.tv';
  static const String apiVersion = '2';

  // OAuth endpoints
  static const String deviceCodeUrl = '$apiBase/oauth/device/code';
  static const String deviceTokenUrl = '$apiBase/oauth/device/token';
  static const String tokenUrl = '$apiBase/oauth/token';
  static const String revokeUrl = '$apiBase/oauth/revoke';

  // Scopes — Trakt's OAuth doesn't use granular scopes; "public" is the only value
  static const String scope = 'public';

  /// Headers required on every Trakt API call.
  static Map<String, String> headers({String? accessToken}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'trakt-api-version': apiVersion,
      'trakt-api-key': clientId,
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }
}

/// Catalog list flavor for Trakt's discover/watchlist endpoints, named after
/// the URL path segment (`/movies/trending`, `/sync/watchlist/shows/...`).
enum TraktCatalogType { movies, shows }
