# Plan technique — nouvelle-identite

Spec : docs/produit/specs/nouvelle-identite.md (y compris « Précisions après validation » P1 à P7)
Statut : approuvé        Pilote : architecte-plateforme

Sources : `proposition-plateforme.md`, `proposition-app.md`, `debat.md` (tour 1). Décisions durables reportées dans
`docs/technique/decisions.md` (D1 à D10). Actions de l'utilisateur : `actions-manuelles.md` (A1 à A7).

## Décisions

### Table d'identité (référence unique ; copie Dart dans `lib/fork/fork_identity.dart`)

| Élément | Valeur |
|---|---|
| Nom affiché | `Popkino` ; slug `popkino` |
| Identifiant d'app (Android, iOS, macOS, tvOS, Linux, Flatpak) | `io.github.adrien24.popkino` |
| tvOS : extension / App Group | `io.github.adrien24.popkino.TopShelfExtension` / `group.io.github.adrien24.popkino` |
| Android : authorities | `${applicationId}.fileprovider`, `${applicationId}.systemshelf.artwork` |
| Schéma d'URL | `popkino` |
| Dépôt / code source | `adrien24/popkino` / `https://github.com/adrien24/popkino` |
| Flux Sparkle/WinSparkle | `https://cdn.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml` |
| Éditeur | `adrien24` ; copyright `Copyright © 2026 adrien24. Based on Plezy, © 2025 edde746. GPL-3.0.` |
| Windows | exe `popkino.exe` ; `CompanyName` `io.github.adrien24` ; `ProductName` `Popkino` ; Inno `AppId` `1349c251-d469-4cab-87df-a2a01d3ccd68` ; mutex `io.github.adrien24.popkino.SingleInstance` ; registre `Software\Popkino` |
| Linux | paquet et commande `popkino`, dossier `/opt/popkino`, desktop `io.github.adrien24.popkino.desktop`, icône `popkino` |
| Fichiers de release | `popkino-android-{arm64-v8a,armeabi-v7a,x86_64}.tar.gz` (contenant `popkino.apk`), `popkino-ios.ipa`, `popkino-macos.dmg`, `popkino-windows-installer.exe`, `popkino-windows-{x64,arm64}-portable.7z`, `popkino-linux-{x64,arm64}.{tar.gz,deb,rpm,pkg.tar.zst,flatpak,AppImage,AppImage.zsync}`, `appcast.xml` |
| Version | `1.0.0+1`, tags `X.Y.Z` |
| Defines | `POPKINO_TRAKT_CLIENT_ID`, `POPKINO_TRAKT_CLIENT_SECRET`, `POPKINO_SIMKL_CLIENT_ID`, `POPKINO_MDBLIST_CLIENT_ID` |
| Couleurs du logo provisoire | fond `#6D28D9`, « P » `#FFFFFF` |

### Choix structurants

1. **Éditions en place, marquées `FORK:`, noms internes Plezy conservés** (D3) : moins de lignes en conflit ; on change
   valeurs et contenus, pas les noms de fichiers ni de packages.
2. **Services Plezy coupés par des constantes Dart** (`lib/fork/fork_features.dart`, D4), pas par la CI : testable par
   `flutter test` et insensible à une fusion mal résolue de `build.yml`. On ne touche ni `ENABLE_DONATIONS`, ni
   `ENABLE_SENTRY`, ni les `SUPPORTER_MODE` de `build.yml` (inertes).
3. **Seuls `--dart-define` du fork : les identifiants des trackers `POPKINO_*`** (D5) ; vides = service masqué.
4. **Traductions dérivées par `scripts/fork/rebrand_i18n.py`** (D6), qui finit par `clean_translations.normalize()`.
5. **Images régénérées par `scripts/fork/generate_brand_assets.py`** depuis `branding/` : le logo définitif ne
   demandera que de remplacer `branding/mark.svg`.
6. **Cohabitation avec Plezy (CA8)** : authorities Android dérivées de `applicationId`, nouvel `AppId` Inno, mutex et
   registre Windows propres, `CompanyName`/`ProductName` (dossier de données Windows), `APPLICATION_ID` et paquets Linux
   renommés, migration `migrateLegacyDesktopDatabase` coupée, préférences Jellyfin sous « Popkino ».
7. **Mises à jour Mac/Windows** : mécanisme upstream inchangé (appcast attaché à la release, branche `appcast`,
   jsDelivr), nouvelle clé Ed25519 ; lien `gh-html.edde746.dev` retiré ; Mac signé ad hoc tant qu'il n'y a pas de
   compte Apple.
8. **MSIX et winget désactivés** (identité Store et paquet winget appartiennent à Plezy) par `if: github.repository ==
   'edde746/plezy'`.
9. **Permission `BILLING` retirée** par le manifeste (l'app est gratuite, la boutique n'est jamais appelée en
   `unlocked`).
10. **Deux gardes sans recouvrement** (D8) : `test/fork/` pour `lib/`, `scripts/fork/check_identity.py` pour le reste,
    branchés sans nouveau workflow.

## Tâches

Ordre conseillé (vagues ; dans une vague, les tâches sont indépendantes) :
- Vague 1 : T1, T7, T11, T12
- Vague 2 : T2, T4, T5
- Vague 3 : T3, T6
- Vague 4 : T8
- Vague 5 : T9, T10 ; puis T13, T14 (après A3), T16 (après A2)
- Vague 6 : T15

Formatage natif (T9 à T12) : `scripts/format_native.sh` demande un JDK 17+ (ktlint) et `clang-format`. S'ils manquent
sur la machine, la tâche peut être livrée à condition que les changements natifs soient des remplacements de
littéraux sans changement de structure ni de longueur de ligne significative ; le contrôle
`scripts/format_native.sh --check` de `ci.yml` (job l. 253) fait foi au premier push de la branche, et tout échec y
est corrigé avant fusion. Pour T9 (Kotlin, plus de lignes touchées), installer l'outil est recommandé :
`brew install openjdk@17 clang-format`.

Règles communes à toutes les tâches : marquer chaque ligne modifiée d'un fichier upstream `FORK: <raison>` dans la
syntaxe de commentaire du fichier (sauf pbxproj, JSON, binaires) ; ne jamais commiter de secret, de `.jks`, de
`key.properties`, de `popkino_secrets.json` ni de `ed25519_key.pem` ; vérifications de `conventions-code` avant de
déclarer la tâche finie.

### T1 — Socle Dart du fork
- Complexité : S
- Dépend de : —
- Fichiers :
  - créer `lib/fork/fork_identity.dart`, `lib/fork/fork_features.dart`, `lib/fork/fork_trackers.dart`,
    `popkino_secrets.example.json`, `test/fork/fork_trackers_test.dart`
  - modifier `.gitignore`
- À faire :
  - `ForkIdentity` (`abstract final class`, constantes `static const String`) : `appName = 'Popkino'`,
    `appSlug = 'popkino'`, `urlScheme = 'popkino'`, `githubRepo = 'adrien24/popkino'`,
    `sourceCodeUrl = 'https://github.com/adrien24/popkino'`, `updateFeedUrl` (table), `upstreamName = 'Plezy'`,
    `upstreamUrl = 'https://github.com/edde746/plezy'`, `licenseName = 'GPL-3.0'`. Commentaire d'en-tête : copie Dart de
    la table d'identité du plan, vérifiée par `scripts/fork/check_identity.py`.
  - `ForkFeatures` : `static const bool` tous à `false` : `plezyCrashReporting`, `plezyLogUpload`, `discordPresence`,
    `donations`, `alternateAppIcons`, `animeTrackers`, `legacyPlezyMigrations` ; et
    `static const SupporterMode forkSupporterMode = SupporterMode.unlocked`. Commentaire : services du projet Plezy
    interdits par `TRADEMARKS.md`, réactivation via le backlog `services-suivi`.
  - `fork_features.dart` importe `SupporterMode` et `supporter_mode.dart` importera `ForkFeatures` (T3) : cet import
    circulaire est voulu et légal (aucun cycle entre constantes), ne pas chercher à le « corriger ».
  - `fork_trackers.dart` :
    - `abstract final class ForkTrackerDefines` avec 4 `static const String` : `traktClientId =
      String.fromEnvironment('POPKINO_TRAKT_CLIENT_ID')`, `traktClientSecret` (`POPKINO_TRAKT_CLIENT_SECRET`),
      `simklClientId` (`POPKINO_SIMKL_CLIENT_ID`), `mdblistClientId` (`POPKINO_MDBLIST_CLIENT_ID`). Ce sont **les
      seules** valeurs que les `static const` upstream peuvent référencer (lire un champ d'un objet `const` n'est pas
      une expression constante en Dart).
    - `ForkTrackerCredentials` (4 champs `String`) et sa constante `fromEnvironment` construite à partir de
      `ForkTrackerDefines.*` ; utilisée seulement par `ForkTrackers`.
    - `ForkTrackers` avec `@visibleForTesting static ForkTrackerCredentials? debugCredentialsOverride` et
      `static bool isOffered(TrackerService s)` : MAL et AniList → `ForkFeatures.animeTrackers` ; Trakt → id **et**
      secret non vides ; Simkl → id non vide ; MDBList → id non vide.
  - `popkino_secrets.example.json` : les 4 clés `POPKINO_*` avec des valeurs vides.
  - `.gitignore` (racine) : ajouter, sous un commentaire `# FORK: secrets locaux Popkino`, les lignes
    `popkino_secrets.json`, `ed25519_key.pem`, `ed25519_pub.txt`.
- Tests : `test/fork/fork_trackers_test.dart` : matrice `isOffered` (MAL/AniList toujours faux ; Trakt faux si id ou
  secret vide ; Simkl et MDBList selon l'id), via `debugCredentialsOverride` remis à `null` dans `tearDown`.
- Critères d'acceptation couverts : CA19f (logique)

### T2 — Identité Dart (serveurs, liens, mise à jour, Regarder ensemble)
- Complexité : M
- Dépend de : T1
- Fichiers à modifier (chaque ligne `// FORK: identité Popkino`, valeur via `ForkIdentity`) :
  `lib/services/plex_client.dart` (l. 820-821), `lib/models/plex/plex_config.dart` (48),
  `lib/services/plex_auth_service.dart` (54), `lib/services/plex_discover_client.dart` (350),
  `lib/services/jellyfin_auth_header.dart` (31, 54-56, 70), `lib/services/jellyfin_client/parts/playback.dart` (920),
  `lib/models/jellyfin/jellyfin_display_preferences.dart` (23, `client = ForkIdentity.appName`, décision P3),
  `lib/utils/media_image_helper.dart` (428), `lib/services/deep_links/deep_link.dart` (32,
  `scheme = ForkIdentity.urlScheme`), `lib/services/update_service.dart` (18-19, `githubRepo` et `updateFeedUrl`),
  `lib/watch_together/providers/watch_together_provider.dart` (79, 135, 826, 828),
  `lib/navigation/profile_session_screen.dart` (311), `lib/services/companion_remote/lan_discovery_service.dart`
  (120 et 205, `ForkIdentity.appSlug`), `lib/main.dart` (1091, en-tête du journal),
  `lib/services/startup_diagnostics.dart` (217), `lib/services/settings_export_service.dart` (436,
  `'${ForkIdentity.appSlug}-settings-…'`).
- Ne pas modifier : canaux `com.plezy/*`, `plezy_downloads.db`, identifiants de contenu `plezy_<server>_<id>`
  (`system_shelf_service.dart`), libellés `plezy-remote-v1`/`plezy-auth-v1`, extension `app.plezy` de Regarder
  ensemble, noms de classes, commentaires.
- Tests :
  - créer `test/fork/fork_identity_test.dart` : en-têtes Plex (`PlexConfig`, `PlexAuthService`) ; `jellyfinClientName`
    et profil d'appareil Jellyfin = Popkino ; `DeepLink.tryParse('plezy://open') == null`, `popkino://open` accepté ;
    lien de retour du lecteur externe en `popkino://` ; nom par défaut et client Regarder ensemble ; balise LAN
    `app == 'popkino'` ; `UpdateService.debugPerformUpdateCheck` avec un `MockClient` : URL
    `https://api.github.com/repos/adrien24/popkino/releases/latest`, et tag `1.0.1` vu plus récent que `1.0.0`.
  - adapter (remplacer `plezy://` par `popkino://` ou par `'${ForkIdentity.urlScheme}://'` ; valeurs « Plezy » par
    `ForkIdentity.appName`) : `test/services/deep_links/deep_link_test.dart`,
    `test/services/deep_links/deep_link_service_test.dart`, `test/services/deep_links/item_links_test.dart`,
    `test/widgets/deep_link_dialog_test.dart`, `test/models/external_player_models_test.dart`,
    `test/services/external_player_service_test.dart`, `test/services/jellyfin_auth_header_test.dart`,
    `test/watch_together/watch_together_provider_test.dart` (429, 448),
    `test/services/media_browser_account_preferences_test.dart`, `test/utils/media_image_helper_test.dart:438` et
    `test/widgets/optimized_media_image_test.dart:52` (User-Agent), `test/services/companion_remote_lan_discovery_service_test.dart:200`
    (`'app': 'plezy'`, sinon la balise est filtrée), `test/services/jellyfin_client_urls_test.dart:3396,3420,3431`
    (`Client="Plezy%20…"`), `test/screens/profile/profile_switch_screen_test.dart:83` (`plezy://open?profile=…`),
    `test/services/settings_export_service_test.dart:933-938` (`plezy-settings-…`). Remplacement mécanique (un `sed`
    ciblé est accepté), sans toucher aux scripts du fork. Après la tâche, `grep -rn "'Plezy\|plezy://\|plezy-settings"
    test --include=*_test.dart` ne doit plus renvoyer que des cas voulus (refus de `plezy://`, commentaires).
  - `scripts/run_tests.sh` sur ces fichiers puis toute la suite.
- Critères d'acceptation couverts : CA12, CA13, CA14 (Dart), CA15 (Dart), CA21, CA22, CA23 (comportement inchangé)

### T3 — Neutralisation des services du projet Plezy
- Complexité : M
- Dépend de : T2 (même fichier `lib/main.dart`), T4 (la garde vérifie l'absence des anciens identifiants)
- Fichiers à modifier (`// FORK: service Plezy retiré`) :
  - `lib/services/plezy_server.dart:4` : `plezyServerBaseUrl = 'https://plezy-services.invalid'`.
  - `lib/main.dart:115-116` : `_enableSentry = ForkFeatures.plezyCrashReporting && bool.fromEnvironment(...)` ; DSN vide.
  - `lib/services/discord_rpc_service.dart` : `isAvailable` (l. 104) faux si `!ForkFeatures.discordPresence` ;
    `_connect()` commence par `if (!isAvailable) return;`.
  - `lib/screens/settings/logs_screen.dart:488` : action d'envoi sous `if (ForkFeatures.plezyLogUpload)` (copier et
    effacer restent).
  - `lib/widgets/startup_failure_view.dart:244` : bouton « Envoyer les détails » sous la même condition.
  - `lib/services/donation_service.dart:11` : `ForkFeatures.donations && …`.
  - `lib/services/supporter/supporter_mode.dart:26-32` : `supporterBuildMode = ForkFeatures.forkSupporterMode` (le
    define est ignoré ; import circulaire voulu, voir T1).
  - `lib/utils/certificate_trust.dart:37` : retirer `'plezy.app'` de `fixedEndpointDomains` ;
    `android/app/src/main/res/xml/network_security_config.xml:33-36` : retirer le commentaire et la ligne
    `<domain includeSubdomains="true">plezy.app</domain>` (remplacés par `<!-- FORK: domaines du projet Plezy retirés -->`).
    T9 ne touche pas ce fichier.
  - `lib/services/trackers/anime_mappings_store.dart:135` : `if (!ForkFeatures.animeTrackers) return null;` en tête de
    `_download()`.
  - `lib/database/app_database.dart` : `if (!ForkFeatures.legacyPlezyMigrations) return;` en tête de
    `migrateLegacyDesktopDatabase` (l. 1477) — sinon Popkino déplacerait la base `plezy_downloads.db` de Plezy
    laissée dans `~/Documents` (CA8).
  - Si l'analyseur signale `dead_code`, ajouter `// ignore: dead_code` sur la ligne.
- Tests :
  - créer `test/fork/fork_test_utils.dart` (`const forkRemovedSkip = 'Fonction retirée dans Popkino (TRADEMARKS.md)';`).
  - créer `test/fork/fork_features_test.dart` : Discord indisponible et `_connect` sans effet ; `DonationService` inactif ;
    `supporterBuildMode == unlocked`, `SupporterService` déverrouillé sans boutique ; `needsFribb` faux pour Trakt,
    Simkl, MDBList ; `LogsScreen` sans action d'envoi mais avec copier/effacer ; `StartupFailureView` sans bouton
    d'envoi ; écran des thèmes sans cadenas ni prix ; `migrateLegacyDesktopDatabase` avec un `sourceOverride` existant
    ne déplace pas le fichier.
  - créer `test/fork/plezy_services_guard_test.dart` : sur `lib/**/*.dart` hors commentaires et `*.g.dart` : aucune
    occurrence de `plezy.app` (aucune exception) ; aucune de `edde746` sauf
    `services/trackers/anime_mappings_store.dart` et `services/donation_service.dart` (code derrière une porte) ; aucun
    des anciens identifiants Trakt, Simkl (V1 et V2) et MDBList ; `Uri.parse(plezyServerBaseUrl).host` finit par
    `.invalid`.
  - adapter `test/android/network_security_config_test.dart` : retirer `'plezy.app'` de `_expectedDomains`, et
    `'lib/services/plezy_server.dart'` et `'lib/main.dart'` de `_fixedEndpointSourcePaths` (ils ne contiennent plus
    d'hôte `https://` couvert) ; `// FORK:` sur chaque ligne.
  - remplacer l'attente par `findsNothing` (pas de `skip`, le reste du test reste utile) :
    `test/startup_bootstrap_test.dart:467` et `test/widgets/startup_failure_view_test.dart:100`
    (`find.byKey(startupFailureUploadKey)`), avec `// FORK:`.
  - marquer `skip: forkRemovedSkip` : tests d'envoi de `test/screens/settings/logs_screen_test.dart` ;
    `test/services/discord_rpc_service_test.dart` (tout le fichier : `isAvailable` devient toujours faux, ses
    `setEnabled(true)` n'ont plus d'effet) ; les tests de `migrateLegacyDesktopDatabase` qui attendent un déplacement.
- Critères d'acceptation couverts : CA16 (Dart), CA17, CA18b, CA19h, CA20, CA8 (bureau)

### T4 — Trakt, Simkl, MDBList avec les identifiants Popkino
- Complexité : M
- Dépend de : T1
- Fichiers à modifier (`// FORK: identifiants Popkino injectés au build`) :
  - `lib/services/trackers/trakt/trakt_constants.dart:13-14` : `clientId = ForkTrackerDefines.traktClientId`,
    `clientSecret = ForkTrackerDefines.traktClientSecret`.
  - `lib/services/trackers/simkl/simkl_constants.dart:22,27,30` : `v2ClientId = ForkTrackerDefines.simklClientId` ;
    `legacyClientId = v2ClientId` ; `appName = ForkIdentity.appSlug`.
  - `lib/services/trackers/mdblist/mdblist_constants.dart:12,17` : `clientId = ForkTrackerDefines.mdblistClientId` ;
    `appName = ForkIdentity.appSlug`.
  - `lib/screens/settings/services_settings_screen.dart:42` : dans la boucle du hub, `if (ForkTrackers.isOffered(info.service))`
    (ne pas filtrer `TrackerServiceInfo.all`).
- Tests : compléter `test/fork/fork_trackers_test.dart` : `ServicesSettingsScreen` affiche/masque chaque ligne selon
  `debugCredentialsOverride`, MAL/AniList jamais affichés, Seerr toujours présent ; `SimklConstants.legacyClientId ==
  SimklConstants.v2ClientId`. Adapter `test/services/trackers/simkl_client_test.dart:84,86` et
  `test/services/trackers/simkl_auth_service_test.dart:73` pour attendre `SimklConstants.appName` (et
  `'${SimklConstants.appName}/$appVersion'`) au lieu de `'plezy'` ; les autres tests des trackers passent sans
  modification (ils référencent les constantes par leur nom).
- Critères d'acceptation couverts : CA19, CA19b (côté app), CA19f, CA19i

### T5 — Traductions dérivées (script et régénération)
- Complexité : L
- Dépend de : T1
- Fichiers :
  - créer `scripts/fork/rebrand_i18n.py`, `scripts/fork/test_rebrand_i18n.py`, `lib/fork/i18n/rebrand_rules.json`,
    `lib/fork/i18n/en.json` et `lib/fork/i18n/fr.json` (objets vides `{}` à ce stade), `test/fork/i18n_branding_test.dart`
  - régénérer `lib/i18n/*.i18n.json` (23) et `lib/i18n/strings*.g.dart`
- À faire :
  - Script idempotent, Python 3 standard uniquement : charger chaque `lib/i18n/<locale>.i18n.json` (ordre conservé) ;
    appliquer les règles par langue (forme la plus longue d'abord), puis la règle générale `Plezy` → `Popkino` sur les
    **valeurs uniquement** (jamais les clés : `profiles.addPlezyProfile`, `startup.quitPlezy` restent), hors `fork.*` ;
    appliquer les règles par clé (`settings.servicesDescription` : `MyAnimeList` → `Simkl`) ; fusionner la surcouche
    `lib/fork/i18n/<locale>.json` ; **terminer en important `normalize`, `locale_plural_categories` et `dump_json` de
    `scripts/checks/clean_translations.py`** (via `importlib` sur le chemin du fichier) et en reproduisant exactement
    l'appel de `clean_pass()` (`clean_translations.py:157-176`) : pour chaque langue autre que `en`,
    `stats = {"added": 0, "removed": 0, "type_fixed": 0, "unchanged": 0}`,
    `normalize(en, loc, "", stats, locale_plural_categories(en, loc))`, puis `dump_json(...)` ; `en` est écrit avec
    `dump_json(en)`. Chaque langue est ainsi écrite sur la structure de `en` (les clés absentes deviennent `""`,
    affichées en anglais grâce à `fallback_strategy: base_locale_empty_string`). Option `--check` : code de sortie 1 si l'écriture modifierait un
    fichier, sans rien écrire.
  - Règles par langue dans `rebrand_rules.json` (reprendre celles de `proposition-app.md` § 5) : `tr`
    (`Plezy'yi`→`Popkino'yu`, `Plezy'nin`→`Popkino'nun`, `Plezy'den`→`Popkino'dan`, `Plezy'de`→`Popkino'da`), `az`
    (`Plezy-ni`→`Popkino-nu`, `Plezy-nin`→`Popkino-nun`, `Plezy-dən`→`Popkino-dan`, `Plezy-də`→`Popkino-da`,
    `Plezy-yə`→`Popkino-ya`), `kk` (`Plezy-дегі`→`Popkino-дағы`, `Plezy-дің`→`Popkino-ның`, `Plezy-ді`→`Popkino-ны`,
    `Plezy-ден`→`Popkino-дан`, `Plezy-де`→`Popkino-да`), `hu` (`Plezyből`/`Plezy-ből`→`Popkinóból`,
    `Plezyben`→`Popkinóban`, `Plezyt`/`Plezy-t`→`Popkinót`, `Plezy-nek`→`Popkinónak`). Avant d'écrire les règles,
    lister toutes les formes réelles avec `grep -o "Plezy[^ \"]*" lib/i18n/*.i18n.json | sort | uniq -c` et couvrir
    chaque forme fléchie trouvée.
  - `scripts/fork/test_rebrand_i18n.py` (lancé automatiquement par `scripts/ci_guard_checks.sh`) : tests unitaires des
    règles (clé jamais modifiée, ordre des règles, idempotence) **et** exécution de `rebrand_i18n.py --check` sur le
    dépôt.
  - Ordre obligatoire : `python3 scripts/fork/rebrand_i18n.py` → `scripts/codegen.sh` → commit des JSON **et** des
    `strings*.g.dart` dans le même commit.
- Tests : `test/fork/i18n_branding_test.dart` : aucune valeur des 23 JSON ne contient « Plezy » hors `fork.*` ;
  `t.app.title == ForkIdentity.appName` en `en` et `fr` ; `settings.servicesDescription` sans « MyAnimeList ». Puis
  `scripts/codegen.sh --check`, `python3 scripts/checks/clean_translations.py --check --strict`,
  `bash scripts/ci_guard_checks.sh`, toute la suite de tests.
- Critères d'acceptation couverts : CA9, CA19 (sous-titre Services), CA21 (message d'invitation), P3 (texte d'aide)

### T6 — Écran « À propos » Popkino
- Complexité : M
- Dépend de : T5 (script et JSON), T1
- Fichiers :
  - créer `lib/fork/screens/fork_about_screen.dart`, `test/fork/fork_about_screen_test.dart`
  - modifier `lib/screens/settings/settings_screen.dart` (l. 54 import, l. 251 `destinationBuilder: (_) => const
    ForkAboutScreen()`, `// FORK: À propos Popkino`), `lib/fork/i18n/en.json`, `lib/fork/i18n/fr.json`,
    `test/fork/i18n_branding_test.dart` ; régénérer `lib/i18n/*.i18n.json` et `strings*.g.dart` (ordre de T5)
- À faire :
  - Clés `fork.about.basedOn` (fr : « Basé sur Plezy. Popkino est un projet indépendant, ni développé ni soutenu par le
    projet Plezy. »), `fork.about.license` (« Licence »), `fork.about.sourceCode` (« Code source »),
    `fork.about.sourceCodeQrHint` (« Scannez ce code avec votre téléphone pour ouvrir l'adresse »), en `en` et `fr`
    seulement (P1). Chaque clé doit être lue par l'écran (sinon `clean_translations --strict` échoue).
  - Écran construit comme `about_screen.dart` (`FocusedScrollScaffold`, `SettingsGroup`, `FocusableListTile`) :
    en-tête non focalisable (logo `assets/plezy.png`, `t.app.title`, version, `t.about.appDescription`,
    `t.fork.about.basedOn`), puis 3 entrées : « Code source » (sous-titre `ForkIdentity.sourceCodeUrl` ; sur TV
    (`PlatformDetector.isTV()`) ou si `openExternalUrl` renvoie `false`, boîte de dialogue avec `QrImageView`, l'URL en
    clair, l'aide `sourceCodeQrHint` et un bouton Fermer focalisé ; sinon navigateur), « Licence » (sous-titre
    `ForkIdentity.licenseName`, ouvre `LicensesScreen`), « Licences open source » (comme l'existant). `about_screen.dart`
    upstream reste intact.
- Tests : `fork_about_screen_test.dart` : logo, nom, version, mention « basé sur Plezy », GPL-3.0, URL ; focus initial sur
  « Code source » au clavier/D-pad ; flèche bas jusqu'à « Licences open source » ; en mode TV, OK ouvre le QR, Retour le
  ferme et le focus revient sur « Code source » ; Retour quitte l'écran. Mode TV forcé comme dans les tests de
  navigation existants (`test/navigation/settings_shortcut_test.dart`) :
  `TvDetectionService.debugSetAppleTVOverride(true)` dans le test (`PlatformDetector.isTV()` lit
  `TvDetectionService.isTVSync()`), remis à `null` dans `tearDown` ; un second test sans override vérifie que
  « Code source » appelle l'ouverture d'URL au lieu du QR. Étendre `i18n_branding_test.dart` :
  `fork.about.basedOn` non vide en `en` et `fr`. Puis les vérifications de T5.
- Critères d'acceptation couverts : CA10, CA11, P1, P2

### T7 — Logo provisoire et générateur d'images
- Complexité : M
- Dépend de : —
- Fichiers :
  - créer `branding/brand.json` (`name`, `backgroundColor` `#6D28D9`, `markColor` `#FFFFFF`, `bannerText` `Popkino`),
    `branding/mark.svg`, `branding/README.md` (comment remplacer le logo), `scripts/fork/generate_brand_assets.py`
  - régénérer (contenu remplacé, mêmes chemins) : `assets/plezy.png` (1024 px), `assets/plezy.svg`,
    `assets/plezy_adaptive_foreground.svg` ; `android/app/src/main/res/drawable/ic_launcher_foreground.xml`,
    `…/drawable/ic_launcher_monochrome.xml`, `…/mipmap-xxxhdpi/ic_launcher.png` (192 px),
    `…/drawable-xxxhdpi/tv_banner.png` (640×360), `…/drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_stat_notification.png`
    (24, 36, 48, 72, 96 px) ; `ios/plezy.icon/Assets/plezy-cropped.svg` et `ios/plezy.icon/icon.json` (`fill` violet),
    idem `macos/plezy.icon/` ; images de `tvos/Runner/Assets.xcassets/AppIcon.brandassets/` (Front/Middle/Back de
    `App Icon.imagestack` 400×240 et 800×480, de `App Icon - App Store.imagestack` 1280×768, `top-shelf.png` 1920×720,
    `top-shelf-wide.png` 2320×720, `top-shelf-wide@2x.png` 4640×1440) ; `windows/runner/resources/app_icon.ico`
    (16, 24, 32, 48, 64, 128, 256 px)
  - modifier `android/app/src/main/res/values/colors.xml` (`ic_launcher_background` = `#6D28D9`, `<!-- FORK: -->`)
- À faire :
  - `mark.svg` : « P » en **tracés géométriques** (aucune police), canevas 1024×1024, signe contenu dans le cercle de
    61 % centré (zone sûre des icônes adaptatives), un seul `<path>` blanc ; le chemin SVG sert tel quel de `pathData`
    pour les VectorDrawable (pas d'arcs `A` si la conversion pose problème : utiliser des courbes `C`).
  - Script : outils `rsvg-convert`, ImageMagick 7 (`magick`), `cwebp` ; message clair si un outil manque ; idempotent
    (deuxième exécution = aucun changement git) ; option `--check` qui compare sans écrire. Bannière TV : fond violet,
    signe à gauche, texte `bannerText` en blanc rendu avec la police du dépôt `assets/go-noto-current-regular.ttf`
    (Google demande le nom de l'app dans la bannière). Si `branding/banner.svg`, `background.svg` ou
    `monochrome.svg` existent, ils remplacent la composition automatique (logo définitif).
  - Ne pas nommer de fichier `scripts/fork/test_*.py` qui appelle ces outils (il tournerait sur le runner CI sans eux).
  - Ne plus lancer `scripts/codegen/generate_app_icons.py` ni `generate_android_icons.sh` (upstream, inchangés).
- Tests : exécuter le script deux fois (deuxième : `git status` propre) ; `file` sur chaque image (dimensions ci-dessus) ;
  `flutter build apk --debug` puis installation sur la TV ou un émulateur Android TV : icône, bannière, splash.
- Critères d'acceptation couverts : CA1, CA2, CA3, CA4 à CA7 (icônes), CA10 (logo)

### T8 — Retrait des icônes alternatives (Dart et natif, une seule tâche)
- Complexité : M
- Dépend de : T3 (`fork_test_utils.dart`, `fork_features_test.dart`), T7 (mêmes dossiers de ressources)
- Fichiers :
  - Dart : modifier `lib/services/app_icon/app_icon_service.dart:47` (`ForkFeatures.alternateAppIcons && …`, ce qui masque
    `AppIconSetting`) ; supprimer `assets/app_icons/` (sources et aperçus) ; `pubspec.yaml` : retirer la ligne
    `assets/app_icons/previews/` (`# FORK:` au-dessus) ; `lib/services/app_icon/app_icon_catalog.dart` **inchangé**.
  - Tests : `skip: forkRemovedSkip` sur `test/services/app_icon/app_icon_catalog_test.dart` (tout le fichier : il
    vérifie les ressources natives supprimées) et `test/screens/settings/app_icon_setting_test.dart` ; vérifier
    `test/services/app_icon/app_icon_service_test.dart` (skip seulement les tests qui lisent des fichiers supprimés) ;
    compléter `test/fork/fork_features_test.dart` : `AppIconService` non pris en charge.
  - Android : supprimer, pour chacun des 23 ids de la liste `ICONS` de `scripts/codegen/generate_app_icons.py`,
    `res/mipmap-anydpi-v26/ic_launcher_<id>.xml`, `res/mipmap-xxxhdpi/ic_launcher_<id>.webp`,
    `res/drawable-xhdpi/tv_banner_<id>.webp`, `res/drawable-{xhdpi,xxhdpi,xxxhdpi}/ic_launcher_<id>_{background,foreground,monochrome}.webp`
    (ne jamais toucher `ic_launcher.xml`, `ic_launcher.png`, `tv_banner.png`) ; `AndroidManifest.xml` : vider le contenu
    entre `BEGIN generated app icon aliases` et `END generated app icon aliases` (marqueurs et `.MainActivity` gardés,
    `<!-- FORK: icônes alternatives Plezy retirées -->` à l'intérieur).
  - iOS : supprimer `ios/Runner/AlternateAppIcons.xcassets/AppIcon-*.appiconset`, garder
    `ios/Runner/AlternateAppIcons.xcassets/Contents.json`.
  - tvOS : supprimer `tvos/Runner/AlternateAppIcons.xcassets/AppIcon-*.imagestack` (garder `Contents.json`) ;
    `tvos/Runner/Info.plist` : vider les `<string>AppIcon-…</string>` entre les marqueurs `BEGIN/END generated tvOS
    alternate icons` (tableau vide, marqueurs gardés).
- Tests : `flutter test` complet ; `flutter build apk --debug` ; `flutter build ios --no-codesign --debug` ;
  `flutter build macos --debug` ; vérifier qu'aucun alias `.appicon.` ne reste (`grep`).
- Critères d'acceptation couverts : CA18, CA18b (aucun « Pack de thèmes et d'icônes »)

### T9 — Identité Android
- Complexité : L
- Dépend de : T8 (même `AndroidManifest.xml`)
- Fichiers :
  - `android/app/build.gradle.kts` : `applicationId = "io.github.adrien24.popkino"` (`namespace` inchangé) ; si
    `BuildConfig` n'est pas généré, ajouter `buildFeatures { buildConfig = true }` dans `android {}`.
  - `android/app/src/main/AndroidManifest.xml` : `android:label="Popkino"` ; `<data android:scheme="popkino"/>` ;
    `android:authorities="${applicationId}.fileprovider"` et `"${applicationId}.systemshelf.artwork"` ;
    `<uses-permission android:name="com.android.vending.BILLING" tools:node="remove"/>` près des autres `remove`.
  - `android/app/src/main/kotlin/com/edde746/plezy/ExternalPlayerChannel.kt:188` : `"${activity.packageName}.fileprovider"`.
  - `…/watchnext/SystemShelfArtworkProvider.kt:25` : `AUTHORITY = "${BuildConfig.APPLICATION_ID}.systemshelf.artwork"`
    (retirer `const` si le compilateur le refuse).
  - `…/deeplink/DeepLinkPlugin.kt:18` : `SCHEME = "popkino"`.
  - `…/watchnext/WatchNextProvider.kt:460,743` : schéma `popkino` **uniquement** ; le préfixe `plezy_` des
    `content_id` reste (lu en dur par `lib/services/system_shelf_service.dart:375-382`).
  - Tests Kotlin à adapter : `android/app/src/test/kotlin/com/edde746/plezy/ExternalPlayerChannelTest.kt`,
    `…/watchnext/SystemShelfArtworkManifestTest.kt`, `…/watchnext/WatchNextProviderTest.kt`,
    `…/deeplink/DeepLinkPluginTest.kt`.
- Tests : `scripts/format_native.sh --fix` ; `cd android && ./gradlew :app:testDebugUnitTest` ;
  `flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true --dart-define-from-file=popkino_secrets.json` ;
  `aapt2 dump badging` sur l'APK arm64 : `package: name='io.github.adrien24.popkino'`, `application-label:'Popkino'`,
  aucune `uses-permission` BILLING ni `REQUEST_INSTALL_PACKAGES` ; sur la TV avec Plezy officiel installé :
  `adb install` réussit, les deux apps coexistent, un lien `popkino://open` ouvre Popkino, `plezy://open` ouvre Plezy,
  lecture par lecteur externe puis retour avec position enregistrée, rangée « Continuer à regarder » qui relance la
  lecture.
- Critères d'acceptation couverts : CA1, CA2, CA3, CA8 (Android), CA14, CA15

### T10 — Identité Apple (iOS, macOS, tvOS)
- Complexité : M
- Dépend de : T8 (même `tvos/Runner/Info.plist`)
- Fichiers :
  - `ios/Runner.xcodeproj/project.pbxproj` : `PRODUCT_BUNDLE_IDENTIFIER = io.github.adrien24.popkino;` et
    `INFOPLIST_KEY_CFBundleDisplayName = Popkino;` (×3 chacun) ; `PRODUCT_NAME` et `DEVELOPMENT_TEAM` inchangés ; les
    `RunnerTests` inchangés.
  - `ios/Runner/Info.plist` : `CFBundleDisplayName` et `CFBundleName` `Popkino`, `CFBundleURLName`
    `io.github.adrien24.popkino`, schéma `popkino`, textes `NSLocationWhenInUseUsageDescription` et
    `NSPhotoLibraryUsageDescription` (« Popkino … »).
  - `macos/Runner/Configs/AppInfo.xcconfig` : `PRODUCT_NAME = Popkino`, `PRODUCT_BUNDLE_IDENTIFIER =
    io.github.adrien24.popkino`, `PRODUCT_COPYRIGHT` = copyright de la table.
  - `macos/Runner/Info.plist` : `CFBundleURLName`, schéma `popkino`, `SUFeedURL` (table). `SUPublicEDKey` : T14.
  - `tvos/Runner.xcodeproj/project.pbxproj` : bundles `io.github.adrien24.popkino` (×3) et
    `io.github.adrien24.popkino.TopShelfExtension` (×3), `INFOPLIST_KEY_CFBundleDisplayName = Popkino;` (×3) ;
    `RunnerTests` inchangés.
  - `tvos/Runner/Info.plist` : `CFBundleDisplayName`, `CFBundleName`, `CFBundleURLName` `io.github.adrien24.popkino.play`,
    schéma `popkino`.
  - `tvos/Runner/Runner.entitlements`, `tvos/TopShelfExtension/TopShelfExtension.entitlements` :
    `group.io.github.adrien24.popkino`.
  - `tvos/TopShelfExtension/TopShelfProvider.swift` (7, 260), `tvos/TopShelfExtension/ShelfSources.swift` (86),
    `tvos/Runner/SystemShelfPlugin.swift` (269) : App Group et schéma.
  - `tvos/RunnerTests/SceneLifecycleTests.swift`, `tvos/RunnerTests/DeepLinkDeliveryCoordinatorTests.swift` : `popkino://`
    (garder `content_id=plezy_…`).
- Tests : `scripts/format_native.sh --fix` ; `flutter build ios --release --no-codesign` puis
  `plutil -p build/ios/iphoneos/Plezy.app/Info.plist` (bundle, nom, schéma) ; `flutter build macos --release` :
  `build/macos/Build/Products/Release/Popkino.app` existe, `plutil -p …/Contents/Info.plist` ; lancer l'app : menus
  « About Popkino » / « Quit Popkino » ; `python3 scripts/checks/check_tvos_test_wiring.py` ; build tvOS si l'environnement
  le permet.
- Critères d'acceptation couverts : CA5, CA7, CA8 (Mac, iPhone), CA14

### T10b — Suites macOS et nom de l'extension Top Shelf (retour de T10)
- Complexité : S
- Dépend de : T10
- Fichiers :
  - `macos/Runner/Configs/AppInfo.xcconfig` : ajouter `PRODUCT_MODULE_NAME = Plezy` sous un commentaire
    `// FORK: keep the Swift module name of upstream so RunnerTests (@testable import Plezy) build unchanged`.
  - `macos/Runner.xcodeproj/project.pbxproj` l. 559, 574, 589 : `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Popkino.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Popkino";`
    (pas de commentaire possible dans un pbxproj ; la ligne `PRODUCT_NAME` de l'xcconfig sert de repère).
  - `tvos/TopShelfExtension/Info.plist:8` : `CFBundleDisplayName` = `Popkino Top Shelf`.
- À faire : ne **pas** toucher `macos/RunnerTests/RunnerTests.swift` (le module reste `Plezy`, identifiant interne
  invisible autorisé par TRADEMARKS ; les futurs tests upstream compileront sans conflit). Ne pas toucher non plus
  `setFrameAutosaveName`, le service Keychain tvOS ni `ios/fastlane/Fastfile` (cf. debat.md).
- Tests : `flutter build macos --config-only --debug --no-pub && pod install --deployment` (dans `macos/`) puis
  `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination platform=macOS
  CODE_SIGNING_ALLOWED=NO` (même commande que le job `apple-native-test` de `ci.yml`) ; `plutil -p` sur
  `build/macos/Build/Products/Debug/Popkino.app/Contents/Info.plist` (nom inchangé : Popkino) ;
  `python3 scripts/checks/check_tvos_test_wiring.py`.
- Critères d'acceptation couverts : CA5 (CI macOS verte), CA14

### T11 — Identité Windows
- Complexité : M
- Dépend de : —
- Fichiers :
  - `windows/CMakeLists.txt:102` : `set(BINARY_NAME "popkino")` (`project(plezy …)` inchangé).
  - `windows/runner/Runner.rc` : `CompanyName "io.github.adrien24"`, `FileDescription`, `InternalName`, `ProductName`
    `"Popkino"`, `OriginalFilename "popkino.exe"`, `LegalCopyright` (table). `EdDSAPub` : T14.
  - `windows/runner/main.cpp` (19, 21, 70) : mutex `io.github.adrien24.popkino.SingleInstance`, `FindWindow(…, L"Popkino")`,
    titre `L"Popkino"`.
  - `windows/runner/flutter_window.cpp:9` : `L"Software\\Popkino"`.
  - `windows/build-installer.ps1` : `$AppGuid = '1349c251-d469-4cab-87df-a2a01d3ccd68'`, `#define Name "Popkino"`,
    `#define Publisher "adrien24"`, `#define ExeName "popkino.exe"`, `OutputBaseFilename=popkino-windows-installer`,
    portables `popkino-windows-{x64,arm64}-portable.7z`, message `ElevationRequired` avec
    `https://github.com/adrien24/popkino/releases/latest`, message final `popkino-windows-installer.exe`. Marqueurs
    `# FORK:` en commentaires PowerShell hors du here-string.
  - `scripts/checks/check_windows_installer.py` : l. 65 `OutputBaseFilename=popkino-windows-installer` et constante
    `APP_GUID` (l. 21) = `1349c251-d469-4cab-87df-a2a01d3ccd68`.
  - `windows/build-msix.ps1:99` : `Executable="popkino.exe"` (`# FORK:` hors du here-string). Effet nul (MSIX non
    construit dans le fork), mais `scripts/checks/check_windows_msix.py` exige que `Application/@Executable` égale le
    `BINARY_NAME` de CMake ; on garde ce contrôle upstream intact plutôt que de l'affaiblir. Le reste de
    `build-msix.ps1` (identité Store de Plezy) ne change pas.
- Tests : `scripts/format_native.sh --fix` ; `python3 scripts/checks/check_windows_installer.py` ;
  `python3 scripts/checks/check_windows_msix.py` ;
  `bash scripts/ci_guard_checks.sh` ; build réel vérifié par T13 (CI Windows) puis A7.
- Critères d'acceptation couverts : CA4, CA8 (Windows), CA22d (inchangé)

### T12 — Identité Linux
- Complexité : L
- Dépend de : —
- Principe : renommer ce qui est visible ou entre en collision avec un paquet Plezy ; garder le binaire interne `plezy`,
  le script `plezy.sh` (nom de fichier), `assets/plezy.png` (source), les variables `PLEZY_*` et les préfixes temporaires.
- Fichiers :
  - `linux/CMakeLists.txt:11` : `APPLICATION_ID "io.github.adrien24.popkino"`.
  - `linux/runner/my_application.cc:68,72` : `"Popkino"`.
  - `git mv linux/packaging/com.edde746.plezy.desktop linux/packaging/io.github.adrien24.popkino.desktop` : `Name=Popkino`,
    `Comment=A Plex, Jellyfin and Emby client for desktop and TV`, `Exec=popkino`, `Icon=popkino`,
    `StartupWMClass=io.github.adrien24.popkino`.
  - `linux/packaging/plezy.sh` : `/opt/plezy` → `/opt/popkino`, `/usr/bin/plezy` → `/usr/bin/popkino` dans les commentaires et
    chemins ; l'exécution de `$INSTALL_DIR/plezy` reste.
  - `linux/packaging/build-packages.py` : `"name": "popkino"`, `"url": "https://github.com/adrien24/popkino"`, mainteneur
    ou vendeur `adrien24` s'il existe, `/opt/popkino/`, `/usr/bin/popkino`, fichier desktop renommé, icônes installées
    `…/apps/popkino.png`, noms de sortie `popkino-linux-*`.
  - `linux/packaging/after-install.sh`, `after-remove.sh` : chemins `/usr/bin/popkino`, `/opt/popkino/…`.
  - `linux/packaging/build-appimage.sh` : sortie `popkino-linux-$ARCH_SUFFIX.AppImage`, `Popkino.AppDir`, fichier desktop
    renommé, icône `popkino.png` (lien `.DirIcon` compris) ; le zsync suit le nom.
  - `linux/packaging/build-flatpak.py` : `APP_ID = "io.github.adrien24.popkino"`, sortie `popkino-linux-{arch}.flatpak`,
    `Icon=plezy` → `Icon={APP_ID}` (inchangé dans le code, la source du desktop change).
  - `git mv` de `linux/packaging/flatpak/com.edde746.plezy.json` et `.metainfo.xml` vers `io.github.adrien24.popkino.*` :
    `app-id`, chemins `install -Dm644 …` des fichiers renommés, icône `io.github.adrien24.popkino.png`, `--own-name` MPRIS
    (déterminer le nom réellement publié en cherchant `MediaPlayer2` dans le plugin de contrôle média du
    `pubspec.lock` ; s'il dérive de l'id d'app : `org.mpris.MediaPlayer2.io_github_adrien24_popkino`) ; metainfo : `id`,
    `name` Popkino, description « Popkino is a media client for Plex, Jellyfin and Emby… based on Plezy », `launchable`,
    URL homepage/bugtracker/vcs vers `https://github.com/adrien24/popkino`, `developer` `adrien24` si la balise existe.
  - `linux/packaging/check-flatpak.py:44` : `io.github.adrien24.popkino` ; texte d'aide l. 4.
  - `.github/workflows/ci.yml` (755, 779, 781, 795) : `popkino-linux-x64.*`.
- Tests : `bash scripts/ci_guard_checks.sh` ; `python3 linux/packaging/test_*` s'il en existe ; lancer `ci.yml` à la main
  sur la branche avec `build_linux_packages=true` (job de paquets) ; vérification complète dans T13 et A7.
- Critères d'acceptation couverts : CA6, CA8 (Linux), CA26 (noms Linux)

### T13 — Workflows de release
- Complexité : L
- Dépend de : T10 (`Popkino.app`), T11 (`popkino.exe`, nom de l'installeur), T12 (noms Linux)
- Fichiers : `.github/workflows/build.yml`, `.github/workflows/update-packages.yml`,
  `scripts/checks/check_build_workflow.py:59`
- À faire dans `build.yml` (chaque bloc modifié précédé de `# FORK: <raison>`) :
  - `RELEASE_DART_DEFINES` (l. 36) : **ajouter seulement** `--dart-define=POPKINO_TRAKT_CLIENT_ID=${{ secrets.TRAKT_CLIENT_ID }}
    --dart-define=POPKINO_TRAKT_CLIENT_SECRET=${{ secrets.TRAKT_CLIENT_SECRET }}
    --dart-define=POPKINO_SIMKL_CLIENT_ID=${{ secrets.SIMKL_CLIENT_ID }}
    --dart-define=POPKINO_MDBLIST_CLIENT_ID=${{ secrets.MDBLIST_CLIENT_ID }}`. Ne rien retirer.
  - Android : archives `popkino-android-*.tar.gz` contenant `popkino.apk` (option `--transform`), `attest`, `upload`.
  - iOS : `zip -r popkino-ios.ipa Payload` (source `build/ios/iphoneos/Plezy.app` inchangée), `attest`, `upload`.
  - macOS : au niveau du job `env: MACOS_SIGNING: ${{ secrets.MACOS_CERTIFICATE_BASE64 != '' && 'developer-id' || 'adhoc' }}` ;
    `if: env.MACOS_SIGNING == 'developer-id'` sur « Import Code Signing Certificate », « Sign Application », « Verify
    Signature », « Notarize Application » ; `Plezy.app` → `Popkino.app` partout ; DMG `-volname "Popkino"`,
    `popkino-macos.dmg` (création, signature EdDSA, `stat`, `attest`, `upload`).
  - Windows : « Verify Windows bundle contents » (l. 487 et suivantes) : `requiredFiles` `popkino.exe`,
    `forbiddenFiles` `popkino.lib`, `popkino.exp` (le bundle produit depuis T11 ne contient plus `plezy.exe`) ; étape « Build Store package
    (MSIX) » et « Upload Store package » avec `if: github.repository == 'edde746/plezy'` ; ligne `plezy-windows.msixbundle`
    retirée de « Attest Windows artifacts » ; signature WinSparkle sur `popkino-windows-installer.exe` ; portables et
    installeur renommés dans `attest` et `upload`.
  - Linux : `flatpak install … "popkino-linux-${{ matrix.arch }}.flatpak"`, tarball, `attest`, `upload` en `popkino-linux-*`.
  - `create-release` : `<title>Popkino Updates</title>` ; **supprimer** la ligne `sparkle:releaseNotesLink`
    (`gh-html.edde746.dev`) ; URL des `enclosure` : `https://github.com/${GITHUB_REPOSITORY}/releases/download/${VERSION}/popkino-macos.dmg`
    et `…/popkino-windows-installer.exe` ; liste « Collect release files » en `popkino-…`.
  - `update-packages.yml` : `if: github.repository == 'edde746/plezy'` sur le job `update-winget` (job `update-appcast-branch`
    inchangé).
  - `check_build_workflow.py:59` : `sign_update popkino-windows-installer.exe $keyPath`.
- Tests : `bash scripts/ci_guard_checks.sh` (inclut `check_build_workflow.py`, `check_update_packages_workflow.py`,
  `check_workflow_security.py`) ; `grep -n "plezy-" .github/workflows/build.yml` ne renvoie rien ; après fusion sur
  `main` : lancer **Build** sans `release_tag` (artefacts seulement) et vérifier que tous les jobs passent, noms
  d'artefacts compris. Le job macOS doit passer sans aucun secret Apple.
- Critères d'acceptation couverts : CA22b (flux), CA26, CA16 (plus de `gh-html.edde746.dev`)

### T14 — Clé publique de mise à jour
- Complexité : S
- Dépend de : T10, T11, action manuelle A3 (clé publique fournie par l'utilisateur)
- Fichiers : `macos/Runner/Info.plist` (`SUPublicEDKey`), `windows/runner/Runner.rc` (`EdDSAPub EDDSA {"<clé>"}`)
- À faire : remplacer la clé publique de Plezy (`q7t6eu1t…`) par le contenu de `ed25519_pub.txt` fourni par
  l'utilisateur, aux deux endroits, avec marqueur `FORK:`.
- Tests : `grep -rn "q7t6eu1txRrqv1PeWDCRV95rFxnmD" macos windows` ne renvoie rien. Test fonctionnel en A7 (mise à jour
  1.0.0 → 1.0.1 acceptée ; appcast signé avec une autre clé refusé).
- Critères d'acceptation couverts : CA22b, CA22c

### T15 — Garde d'identité native et CI
- Complexité : M
- Dépend de : T2, T9, T10, T10b, T11, T12, T13, T14
- Fichiers : créer `scripts/fork/check_identity.py`, `scripts/fork/test_check_identity.py`
- À faire :
  - Python 3 standard, règles déclaratives `(motif de fichiers, expression, message)` ; sortie en erreur avec
    `fichier:ligne: message`.
  - Interdits : `com.edde746.plezy` dans `AndroidManifest.xml` et dans les chaînes Kotlin (pas dans `package`/`import`),
    dans `applicationId`, dans les `PRODUCT_BUNDLE_IDENTIFIER` des pbxproj (sauf `.RunnerTests`), dans les Info.plist,
    entitlements, `linux/CMakeLists.txt`, `linux/packaging/**` ; `group.com.edde746` ; `<string>plezy</string>` et
    `android:scheme="plezy"` ; `"plezy"` comme schéma dans `DeepLinkPlugin.kt`, `WatchNextProvider.kt`,
    `TopShelfProvider.swift` ; `android:label="Plezy"`, `CFBundleDisplayName`/`CFBundleName` contenant « Plezy » (y compris « Plezy Top Shelf »),
    `INFOPLIST_KEY_CFBundleDisplayName = Plezy`, `PRODUCT_NAME = Plezy` dans `AppInfo.xcconfig` (mais `PRODUCT_MODULE_NAME = Plezy` autorisé, T10b), `"Plezy"` dans `Runner.rc`
    et `main.cpp`, `Name=Plezy` dans les `.desktop` ; `plezy-` comme nom d'artefact dans `.github/workflows/*.yml`,
    `windows/build-installer.ps1`, `linux/packaging/**` ; `edde746/plezy` dans les workflows (sauf les conditions
    `github.repository == 'edde746/plezy'`), `windows/build-installer.ps1`, `linux/packaging/**`, Info.plist ;
    `gh-html.edde746.dev` partout hors `docs/` ; clé publique `q7t6eu1txRrqv1PeWDCRV95rFxnmD/D3GZWbUPMwUyU=` ; GUID
    `4213385e-f7be-4f2b-95f9-54082a28bb8f`.
  - Exclusions explicites : `windows/build-msix.ps1`, `windows/msix/**`, `scripts/release/**`, `ios/fastlane/**`
    (outillage store upstream non utilisé), `website/**`, `server/**`, `docs/**`, `test/**`, `lib/**` (couvert par `test/fork/`).
  - Concordance : lire `lib/fork/fork_identity.dart` par regex (`urlScheme`, `githubRepo`, `updateFeedUrl`) et vérifier
    que le schéma du manifeste, des 3 Info.plist et de `DeepLinkPlugin.kt` vaut `urlScheme`, et que `SUFeedURL` vaut
    `updateFeedUrl` ; `applicationId` = `io.github.adrien24.popkino`.
  - `test_check_identity.py` : tests unitaires des règles sur des fichiers temporaires (un cas interdit, un cas exclu,
    un cas autorisé) **et** exécution de `check_identity.py` sur le dépôt (doit réussir).
- Tests : `python3 scripts/fork/test_check_identity.py` ; `bash scripts/ci_guard_checks.sh` ; contre-épreuve : remettre
  temporairement `android:label="Plezy"`, la garde doit échouer.
- Critères d'acceptation couverts : CA1 à CA8, CA14, CA26 (prévention des régressions après fusion)

### T16 — Dépôt, licence et documentation
- Complexité : M
- Dépend de : T8 (même `pubspec.yaml`), action manuelle A2 (empreinte de la clé Android)
- Fichiers :
  - `pubspec.yaml` : `version: 1.0.0+1` (`# FORK: version propre à Popkino`).
  - `README.md` : réécrit. Contenu : titre Popkino avec `assets/plezy.png` ; une phrase de présentation ; « Popkino est
    basé sur [Plezy](https://github.com/edde746/plezy). Projet indépendant, ni développé ni soutenu par le projet
    Plezy. » ; lien vers `TRADEMARKS.md` et `NOTICE.md` ; tableau de téléchargement avec les liens
    `https://github.com/adrien24/popkino/releases/latest/download/popkino-…` (tous les fichiers de la table) ; section
    « Installer sans signature » (Windows SmartScreen, Mac « Ouvrir quand même » et `xattr -dr com.apple.quarantine
    /Applications/Popkino.app`, iPhone via AltStore/Sideloadly avec la limite de 7 jours d'un compte Apple gratuit,
    Android : autoriser les sources inconnues) ; section « Vérifier l'APK » avec l'empreinte SHA-256 (A2) et la commande
    `apksigner verify --print-certs` ; licence GPL-3.0. Aucun badge de store, aucun lien de téléchargement Plezy, pas de
    `plezy.app`.
  - `NOTICE.md` (nouveau) : Popkino est une version modifiée de Plezy (© 2025 edde746 et contributeurs, GPL-3.0),
    modifiée par adrien24 depuis le 2026-11-26 ; les fichiers upstream modifiés sont marqués `FORK:` ou listés par
    `scripts/fork/check_identity.py` ; l'historique git public fait foi ; chaque release correspond à un tag.
  - Supprimer `.github/FUNDING.yml`.
  - `.github/ISSUE_TEMPLATE/config.yml` : lien de discussion vers `https://github.com/adrien24/popkino/discussions` (ou
    retirer `contact_links` si les Discussions ne sont pas activées) ; `.github/ISSUE_TEMPLATE/bug_report.yml:53` :
    `label: Popkino Version` (l'`id` `plezy-version` reste).
  - `.gitattributes` : ajouter `README.md merge=ours` et `NOTICE.md merge=ours` sous `# FORK:` ; créer
    `scripts/fork/setup_merge.sh` (`git config merge.ours.driver true`, avec explication).
  - `docs/technique/fusion-upstream.md` : `git fetch upstream && git merge upstream/main` ; conflits attendus (lignes
    `FORK:`, `version:` du pubspec : garder la nôtre ; images : garder les nôtres puis
    `python3 scripts/fork/generate_brand_assets.py`) ; traductions : `git checkout --theirs -- lib/i18n/*.i18n.json
    lib/i18n/*.g.dart && python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh` ; puis
    `bash scripts/ci_guard_checks.sh`, `scripts/run_tests.sh test/fork/`, toute la suite, build APK.
  - `docs/technique/release.md` : procédure de release (monter `version:`, fusionner sur `main`, workflow Build avec
    `release_tag`, vérifier le brouillon, description, publier, vérifier l'appcast) ; renvoi vers
    `nouvelle-identite/actions-manuelles.md` pour les clés et secrets.
- Tests : `grep -n "edde746\|plezy.app\|liberapay" README.md` ne renvoie que le lien « basé sur Plezy » et
  `TRADEMARKS.md` ; `flutter test` (la version change) ; relecture par l'orchestrateur.
- Critères d'acceptation couverts : CA24, CA25, CA26 (tag), CA27, P5

## Vérification globale

Sur la branche `feat/nouvelle-identite`, toutes tâches fusionnées :

```bash
flutter pub get
python3 scripts/fork/rebrand_i18n.py --check
python3 scripts/fork/generate_brand_assets.py --check
scripts/codegen.sh --check
python3 scripts/checks/clean_translations.py --check --strict
bash scripts/ci_guard_checks.sh          # inclut check_identity et rebrand_i18n
flutter analyze
scripts/run_tests.sh                       # toute la suite, dont test/fork/
(cd android && ./gradlew :app:testDebugUnitTest)
flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true --dart-define-from-file=popkino_secrets.json
```

Sur la TV (avec Plezy officiel installé) : `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` ;
bannière et nom Popkino dans le lanceur ; ouverture ; navigation au D-pad jusqu'à Paramètres > À propos (logo, mention,
QR du code source, Retour) ; Paramètres sans « Soutenir Plezy », icônes alternatives, MAL, AniList, Discord, « Envoyer
les journaux » ; thèmes sans cadenas ; Services : Trakt/Simkl/MDBList selon les identifiants ; connexion Plex puis
appareil « Popkino » sur plex.tv ; lecture, lecteur externe et retour ; Plezy officiel toujours fonctionnel à côté.
Réseau (CA16) : capture du trafic (par exemple proxy ou DNS du routeur) pendant ce parcours, aucun `plezy.app`,
`edde746.dev` ni Discord.

Après fusion sur `main` : workflow Build sans `release_tag`, tous les jobs verts ; puis A6 et A7.

## Ajouts au skill conventions-code

À intégrer par l'orchestrateur dans `.claude/skills/conventions-code/SKILL.md` :

- Build Android local : ajouter `--dart-define-from-file=popkino_secrets.json` (fichier à la racine, ignoré par git,
  modèle `popkino_secrets.example.json`) ; sans lui, Trakt, Simkl et MDBList sont absents de l'app.
- Signature locale : `android/key.properties` pointe vers `~/popkino-secrets/popkino-release.jks` (chemin absolu) ;
  l'APK installé sur la TV doit être signé par cette clé pour pouvoir être mis à jour par les releases.
- Code du fork : `lib/fork/`, `test/fork/`, `scripts/fork/`, `branding/` (D2) ; marqueur `FORK:` dans la syntaxe de
  commentaire du fichier (D3) ; valeurs d'identité Dart toujours via `ForkIdentity`.
- Traductions : ne jamais éditer `lib/i18n/*.i18n.json` à la main ; ajouter une chaîne du fork sous `fork.*` dans
  `lib/fork/i18n/{en,fr}.json`, puis `python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh` (D6).
- Images de marque : `python3 scripts/fork/generate_brand_assets.py` (outils `brew install librsvg imagemagick webp`).
- Vérifications : `bash scripts/ci_guard_checks.sh` lance aussi les gardes du fork ; un test d'une fonction retirée
  se marque `skip: forkRemovedSkip`, il ne se supprime pas.
- Fusion upstream : `docs/technique/fusion-upstream.md`.

## Risques restants

- **Mise à jour Sparkle d'une app Mac signée ad hoc** : non vérifiable avant A7. Repli prévu côté app : constante
  `ForkFeatures.nativeUpdaterOnMacOS = false` dans `update_service.dart:44` (lien GitHub à la place), à ajouter
  seulement si le test échoue.
- **Format de la clé `SPARKLE_PRIVATE_KEY`** : déduit du code (`auto_updater` réf. `9e150f7` : `sign_update` accepte
  le fichier avec ou sans en-têtes et attend une graine Ed25519 de 32 octets ; l'étape macOS ajoute les en-têtes,
  l'étape Windows non). Confirmé seulement par la première release signée.
- **Paquets Linux** : non testables sur le Mac de l'utilisateur ; on s'appuie sur la CI (`build.yml`, job de paquets de
  `ci.yml`) et sur un test en machine virtuelle si possible. Nom MPRIS du Flatpak à confirmer.
- **Regarder ensemble** : les relais Open Watch Party doivent accepter le client `Popkino/x.y.z` (test manuel).
- **Traductions hu, tr, az, kk** : formes fléchies écrites sans relecteur natif.
- **Conflits de fusion** : concentrés sur `build.yml` (~60 lignes renommées), le packaging Linux et la ligne `version:`
  du pubspec ; tous mécaniques et détectés par les gardes.
- **Vérification des développeurs Android** (2027, téléphones et tablettes) : hors périmètre (P6), backlog
  `verification-developpeur-android`.
- **Google Play plus tard** : AAB sans `ENABLE_UPDATE_CHECK` (D7) ; SDK Sentry natif embarqué mais jamais initialisé, à
  déclarer correctement dans « Sécurité des données » ; l'app doit apporter plus qu'une copie de Plezy (règle anti-spam).
- **Dépendances de build hébergées par edde746** (moteur Flutter Windows, `mpv-build`, `auto_updater`) : épinglées par
  SHA-256, ce ne sont pas des services utilisés par l'app ; leur disparition casserait le build (risque déjà présent).
