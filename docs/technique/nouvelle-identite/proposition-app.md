# Proposition app — nouvelle-identite

Auteur : architecte-app. Date : 2026-11-26. Périmètre : `lib/`, `test/`, traductions slang, et les
interfaces avec la plateforme. `docs/technique/decisions.md` n'existe pas encore : les décisions durables proposées
sont regroupées en fin de document. Elles seront écrites dans ce fichier au plan final, pour ne pas écrire en même
temps que l'autre architecte.

## Compréhension de la spec

L'app devient **Popkino** partout où un utilisateur, un serveur Plex/Jellyfin ou un service tiers voit son identité.
Elle n'appelle plus aucun service du projet Plezy (`ice.plezy.app`, `bugs.plezy.app`, Discord, dons) et retire
MAL/AniList, les icônes alternatives et l'achat supporter (thèmes offerts). Trakt, Simkl et MDBList restent, avec les
identifiants de l'utilisateur injectés au build, et disparaissent si ces identifiants sont absents. Tout cela doit
rester fusionnable avec l'upstream.

CA de mon périmètre : CA9 (textes), CA10 et CA11 (À propos au D-pad), CA12 et CA13 (identité vue par Plex et
Jellyfin), CA14 (schéma, côté Dart), CA15 (retour du lecteur externe), CA16 (aucun trafic vers plezy.app ni Discord,
côté Dart), CA17, CA18, CA18b, CA19, CA19b à CA19i (côté Dart), CA20, CA21, CA22 et CA23 (Android, côté Dart).
CA1 à CA8 et CA22b à CA27 relèvent de la plateforme. J'y fournis seulement les valeurs et les fichiers d'entrée.

## Existant (lu dans le code)

### Identité visible

| Sujet | Fichier : ligne | Constat |
|---|---|---|
| Produit Plex | `lib/services/plex_client.dart:820-821`, `lib/models/plex/plex_config.dart:48`, `lib/services/plex_auth_service.dart:54` (`_appName`), `lib/services/plex_discover_client.dart:350` | `'Plezy'` en dur, à 4 endroits |
| Client Jellyfin/Emby | `lib/services/jellyfin_auth_header.dart:31,54-56,70` (`buildJellyfinAuthHeader`, `jellyfinClientName`, `jellyfinDeviceName`) | `'Plezy'`, `'Plezy Android TV'`, `'Plezy $platform'` |
| Profil d'appareil Jellyfin | `lib/services/jellyfin_client/parts/playback.dart:920` | `'Name': 'Plezy'` |
| Espace de préférences Jellyfin côté serveur | `lib/models/jellyfin/jellyfin_display_preferences.dart:23` | `client = 'Plezy'` (réglages du compte stockés sur le serveur) |
| User-Agent des images | `lib/utils/media_image_helper.dart:428` | `'Plezy'` |
| Schéma d'URL | `lib/services/deep_links/deep_link.dart:32` | `static const scheme = 'plezy'`. Tout le Dart passe par `DeepLink.scheme`, y compris le retour du lecteur externe (`external_player_service.dart:324,355`) |
| Mise à jour | `lib/services/update_service.dart:18-19` | `_githubRepo = 'edde746/plezy'`, `_feedUrl` = appcast jsDelivr de Plezy |
| Regarder ensemble | `watch_together_provider.dart:79,135,826,828` et `navigation/profile_session_screen.dart:311` | nom par défaut `'Plezy'`, client `'Plezy/<version>'` |
| Télécommande compagnon | `lib/services/companion_remote/lan_discovery_service.dart:120,205` | balise LAN `'app': 'plezy'` et filtre à la réception |
| En-tête des journaux et du diagnostic | `lib/main.dart:1091`, `lib/services/startup_diagnostics.dart:217` | `'Plezy v…'`, `'Plezy startup failure'` |
| Fichier d'export des réglages | `lib/services/settings_export_service.dart:436` | `plezy-settings-AAAAMMJJ.json` (nom visible) |
| Logo | `assets/plezy.png` (`auth_screen.dart:284,313`, `about_screen.dart:36`), `assets/plezy_adaptive_foreground.svg` (`main.dart:2530,2553`, `app_icon_setting.dart:278`) | |
| Titre | `t.app.title` (`main.dart:1973`, `auth_screen.dart`, `logs_screen.dart:133`, `about_screen.dart:19`) | vient de slang |

### Traductions

`lib/i18n/*.i18n.json` : 23 fichiers, 38 à 41 valeurs contenant « Plezy » par fichier (41 en anglais). Ces fichiers sont
au **format canonique** `json.dumps(indent=2, ensure_ascii=False)` dans l'ordre des clés de `en`, normalisé par
`scripts/checks/clean_translations.py` (vérifié sur les 23 fichiers). Deux pièges relevés :

- Des clés contiennent le mot : `profiles.addPlezyProfile`, `startup.quitPlezy`. Il ne faut remplacer que les
  **valeurs**.
- Le nom est **fléchi ou collé** : `Plezys` (sv, da), `Plezyben`, `Plezyt`, `Plezyből`, `Plezy-nek` (hu), `Plezy'yi`,
  `Plezy'nin` (tr), `Plezy-ni`, `Plezy-dən` (az), `Plezy-ді`, `Plezy-дің` (kk), `Plezyning` (uz), et le nom est collé
  aux caractères en japonais et en coréen (`Plezyを`, `Plezy가`). Une règle « mot entier » échoue. Un remplacement
  brut donne des fautes en hu, tr, az et kk (harmonie vocalique : Popkino finit en « o »).
- `settings.servicesDescription` cite « MyAnimeList » dans les 23 langues (sous-titre visible de l'entrée Services).

### Services du projet Plezy

| Service | Où | Porte d'entrée actuelle |
|---|---|---|
| Proxy OAuth MAL/AniList, envoi de journaux, posters Discord | `lib/services/plezy_server.dart:4` (`plezyServerBaseUrl = 'https://ice.plezy.app'`), utilisé par `oauth_proxy_client.dart`, `log_upload_service.dart`, `discord_rpc_service.dart:57` | — |
| Sentry | `lib/main.dart:115-116` (`ENABLE_SENTRY`, DSN `bugs.plezy.app`) | `--dart-define`. **`scripts/release/deploy.py:917,1089,1240` le passe à `true`** pour les builds des stores |
| Dons | `lib/services/donation_service.dart` (Liberapay edde746) | `--dart-define=ENABLE_DONATIONS`. **`.github/workflows/build.yml:36` le passe à `true`** pour toutes les releases GitHub |
| Supporter (achat, thèmes, icônes) | `lib/services/supporter/supporter_mode.dart` (`SUPPORTER_MODE` : `off` / `iap` / `unlocked` / `msstore`), `supporter_service.dart` | `unlocked` = thèmes gratuits, la boutique n'est jamais contactée (`init()` sort si ce n'est pas `purchasable`). `build.yml` passe `unlocked` (macOS, Linux), `msstore` (Windows) et rien pour Android/iOS (donc `off` : thèmes masqués) |
| Icônes alternatives | `lib/services/app_icon/app_icon_service.dart:46-47` (`_defaultPlatformHasAlternateIcons = supporterBuildMode != off && (iOS‖Android)`), `AppIconSetting.isShown` dans `appearance_settings_screen.dart:46`, aperçus `assets/app_icons/previews/` **inclus dans le bundle** (`pubspec.yaml`) | |
| Discord | `DiscordRPCService.isAvailable` (`discord_rpc_service.dart:104`) masque l'entrée (`services_settings_screen.dart:43`). **Mais `setEnabled(true)` appelle `_connect()` sans vérifier `isAvailable`** (l.129-135) | |
| Envoi de journaux | bouton dans `logs_screen.dart:488-492`, bouton « Envoyer les détails » dans `startup_failure_view.dart:244-251` | aucune |
| MAL / AniList | `TrackerServiceInfo.all` (`tracker_service_info.dart:62`) : **liste unique** pour le hub Services (`services_settings_screen.dart:42`), le résumé des Paramètres (`settings_screen.dart:335`, connectés seulement) et la feuille de notation (`rating_bottom_sheet.dart:244`, connectés seulement). Le hub est le **seul** endroit qui appelle `startConnection` (`services_settings_screen.dart:97`) | Code réparti dans 57 fichiers de `lib/` et 40 fichiers de test |
| Correspondances anime (`github.com/edde746/anime-mappings`) | `anime_mappings_store.dart:29`, chargées à la demande via `TrackerIdResolver` seulement si un tracker actif a `needsFribb` (`tracker_coordinator.dart:200`). Simkl : `needsFribb => false` | Plus aucun téléchargement si MAL et AniList ne sont jamais connectés |

### Trakt, Simkl, MDBList

- `trakt_constants.dart:13-14` : `clientId` et `clientSecret` de Plezy en dur.
- `simkl_constants.dart:22,27,30` : `legacyClientId` (AUTH V1 de Plezy), `v2ClientId`, `appName = 'plezy'`
  (User-Agent et paramètre `app-name` de chaque URL).
- `mdblist_constants.dart:12,17` : `clientId`, `appName = 'plezy'`.
- Les tests référencent ces constantes **par leur nom** (`MdblistConstants.clientId`, `SimklConstants.legacyClientId`),
  jamais par leur valeur. Changer les valeurs ne casse donc pas ces tests.
- Les sessions sont exclues de l'export des réglages (`sensitive_prefs.dart:43-47`) : un utilisateur ne peut pas
  importer de jeton Plezy, et aucun jeton Simkl V1 n'existera jamais dans Popkino (CA19i).
- Sans session, aucune source de catalogue ni note communautaire (`CatalogSourcesProvider.connectedSources`).

### Écran À propos

`lib/screens/settings/about_screen.dart` (76 lignes) : logo, `t.app.title`, version, `about.appDescription`,
« Licences open source ». Une seule référence : `settings_screen.dart:251` (`const AboutScreen()`).
`FocusedScrollScaffold` donne déjà le focus au premier élément de contenu en mode clavier/D-pad. `qr_flutter` est déjà
une dépendance (`deep_link_dialog.dart`, `pending_auth_dialog.dart`). `openExternalUrl` (`utils/external_url.dart:43`)
renvoie `false` quand rien ne peut ouvrir l'URL, ce qui est le cas sur beaucoup de TV sans navigateur.

## Approche proposée

### Le point clé : supprimer, désactiver par `--dart-define`, ou neutraliser à la compilation ?

Je propose une troisième voie : **neutraliser au point d'entrée avec des constantes de compilation propres au fork,
sans supprimer le code et sans `--dart-define`.** Un `--dart-define` n'est utilisé que pour les secrets (identifiants
Trakt, Simkl, MDBList).

| Critère | Supprimer le code | Flag `--dart-define` | **Neutraliser (const Dart du fork)** |
|---|---|---|---|
| Diff upstream | Énorme : MAL/AniList seuls = 57 fichiers de `lib/` et 40 de `test/`, plus l'enum `TrackerService` dont le `.name` est persisté (`tracker_constants.dart:31-33`) | Nul en Dart | 1 à 3 lignes par point d'entrée, ~50 lignes en tout |
| Fusions upstream | Conflit modify/delete à chaque évolution upstream de MAL, du supporter, de Discord… | Sans conflit en Dart, mais **la CI upstream réactive** : `build.yml` passe `ENABLE_DONATIONS=true`, `deploy.py` passe `ENABLE_SENTRY=true`. Une fusion de `build.yml` mal résolue réactive les dons vers Liberapay edde746 sans qu'aucune ligne de Dart ne change | Conflit seulement si l'upstream modifie la ligne exacte de la porte. Aucun flag de CI ne peut réactiver un service |
| Vérifiable par les tests | Oui | **Non** : `flutter test` tourne sans define, on teste donc la valeur par défaut, pas le build réel | Oui : constantes lisibles en test, et test de garde sur le code source |
| Réactivation future (backlog `services-suivi` : MAL/AniList avec notre proxy) | Il faut annuler la suppression | Facile | Passer une constante à `true` et changer l'URL du proxy |
| Taille de l'APK et risque Play | Minimal | Code mort embarqué | Code mort embarqué, en grande partie éliminé par le compilateur AOT quand la porte est `const`. Aucune donnée envoyée |

Les tests upstream qui couvrent un service neutralisé (MAL, Discord…) **continuent de passer sans modification**, parce
que le code existe toujours et que les tests appellent les classes directement. Seuls les tests qui vérifient
l'**interface utilisateur** d'un service retiré, ou une **valeur** d'identité, sont à adapter (liste plus bas).

Défense en profondeur pour CA16 : en plus des portes dans l'interface, la **base réseau** des services Plezy est
rendue inaccessible (`plezyServerBaseUrl` pointe vers un domaine réservé `.invalid`). Un chemin oublié échoue donc
sans jamais joindre `plezy.app`, et un test de garde détecte toute nouvelle URL `plezy.app` ou `edde746` apportée par
une fusion.

### 1. Code propre au fork : `lib/fork/`

```
lib/fork/
  fork_identity.dart       // valeurs d'identité (nom, slug, schéma, dépôt, URL)
  fork_features.dart       // portes const des services Plezy neutralisés
  fork_trackers.dart       // identifiants injectés et disponibilité de chaque tracker
  screens/fork_about_screen.dart
  i18n/                    // surcouche de traductions et règles (voir §4)
test/fork/                 // tests de garde et tests des écrans du fork
scripts/fork/rebrand_i18n.py
```

`fork_identity.dart` :

```dart
abstract final class ForkIdentity {
  static const appName = 'Popkino';            // produit vu par Plex, Jellyfin, Regarder ensemble…
  static const appSlug = 'popkino';            // User-Agent Simkl/MDBList, balise LAN, noms de fichiers
  static const urlScheme = 'popkino';          // = DeepLink.scheme ; à aligner avec le natif
  static const githubRepo = 'adrien24/popkino';
  static const sourceCodeUrl = 'https://github.com/adrien24/popkino';
  static const updateFeedUrl = 'https://cdn.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml'; // à confirmer par la plateforme
  static const upstreamName = 'Plezy';
  static const upstreamUrl = 'https://github.com/edde746/plezy';
  static const licenseName = 'GPL-3.0';
}
```

`fork_features.dart` : constantes `static const bool` toutes à `false` : `plezyCrashReporting`,
`plezyLogUpload`, `discordPresence`, `donations`, `alternateAppIcons`, `animeTrackers` (MAL + AniList). Plus une
constante `forkSupporterMode = SupporterMode.unlocked`. Une seule raison commune en commentaire : services du projet
Plezy interdits (TRADEMARKS.md), réactivation éventuelle via le backlog.

### 2. Identité : petites modifications localisées des fichiers upstream

Chaque ligne modifiée remplace un littéral par une constante de `ForkIdentity` et porte `// FORK: identité Popkino`.

| Fichier upstream | Modification | CA |
|---|---|---|
| `services/plex_client.dart:820-821` | `'Plezy'` → `ForkIdentity.appName` (2 lignes) | CA12 |
| `models/plex/plex_config.dart:48` | `product ?? ForkIdentity.appName` | CA12 |
| `services/plex_auth_service.dart:54` | `_appName = ForkIdentity.appName` | CA12 |
| `services/plex_discover_client.dart:350` | idem | CA12 |
| `services/jellyfin_auth_header.dart:31,54-56,70` | 5 lignes : `'${ForkIdentity.appName} $platform'`, `'${ForkIdentity.appName} Android TV'`… | CA13 |
| `services/jellyfin_client/parts/playback.dart:920` | `'Name': ForkIdentity.appName` | CA13 |
| `models/jellyfin/jellyfin_display_preferences.dart:23` | `client = ForkIdentity.appName` (voir QUESTIONS PRODUIT) | CA8 |
| `utils/media_image_helper.dart:428` | User-Agent | — |
| `services/deep_links/deep_link.dart:32` | `scheme = ForkIdentity.urlScheme`. Couvre aussi les liens de retour du lecteur externe | CA14, CA15 |
| `services/update_service.dart:18-19` | `_githubRepo`, `_feedUrl` | CA22 |
| `watch_together/providers/watch_together_provider.dart:79,135,826,828` et `navigation/profile_session_screen.dart:311` | nom par défaut et client `'${ForkIdentity.appName}/<version>'` | CA21 |
| `services/companion_remote/lan_discovery_service.dart:120,205` | `'app': ForkIdentity.appSlug` à l'émission et à la réception : Popkino ne voit que des Popkino (hypothèse de la spec) | — |
| `main.dart:1091`, `services/startup_diagnostics.dart:217` | en-têtes des journaux et du diagnostic | CA9 |
| `services/settings_export_service.dart:436` | `'${ForkIdentity.appSlug}-settings-…'` | CA9 |

Je laisse volontairement inchangés, car invisibles (TRADEMARKS.md l'autorise) : le package Dart `plezy`, les canaux
`com.plezy/*`, `plezy_downloads.db`, les identifiants de contenu `plezy_<server>_<id>` de la rangée Android TV, les
libellés cryptographiques `plezy-remote-v1` et `plezy-auth-v1` de la télécommande, l'extension `app.plezy` des
descripteurs Regarder ensemble (elle garde l'interopérabilité avec les salles Plezy), les noms de classes
(`PlezyPlayerAdapter`, `PlezyWidgetsBinding`) et les commentaires.

**Logos** : je propose de **garder les chemins** `assets/plezy.png`, `assets/plezy_adaptive_foreground.svg` et
`assets/plezy.svg`, et de **remplacer leur contenu** par le logo Popkino provisoire. Cela fait zéro ligne de Dart
modifiée (`auth_screen.dart`, écran de démarrage de `main.dart`, À propos). Si l'upstream change son logo, la fusion
produit un conflit binaire évident, à résoudre en gardant notre version. La génération des fichiers revient à la
plateforme (pipeline `scripts/codegen/generate_app_icons.py`).

### 3. Services du projet Plezy : neutralisation aux portes d'entrée

| Fichier upstream | Modification (`// FORK: service Plezy retiré`) | CA |
|---|---|---|
| `services/plezy_server.dart:4` | `plezyServerBaseUrl = 'https://plezy-services.invalid'` (domaine réservé par la RFC 6761, ne se résout jamais) | CA16 |
| `main.dart:115-116` | `_enableSentry = ForkFeatures.plezyCrashReporting && bool.fromEnvironment(...)` ; DSN vidé | CA16 |
| `services/discord_rpc_service.dart:104,232` | `isAvailable` renvoie `false` si `!ForkFeatures.discordPresence` ; `_connect()` commence par `if (!isAvailable) return;` (ferme le chemin `setEnabled(true)`, par exemple après un import de réglages) | CA16, CA19 |
| `screens/settings/logs_screen.dart:488` | `if (ForkFeatures.plezyLogUpload)` devant l'action d'envoi | CA20 |
| `widgets/startup_failure_view.dart:244` | idem devant le bouton « Envoyer les détails » | CA16 |
| `services/donation_service.dart:11` | `ForkFeatures.donations && …` | CA17 |
| `services/supporter/supporter_mode.dart:26-32` | `supporterBuildMode = ForkFeatures.forkSupporterMode` (`unlocked`), le define est ignoré. Résultat : thèmes gratuits partout, aucun achat, aucune tuile Supporter (`settings_screen.dart:216` exige `iap`) | CA17, CA18b |
| `services/app_icon/app_icon_service.dart:47` | `ForkFeatures.alternateAppIcons && …`, ce qui masque `AppIconSetting` | CA18 |
| `screens/settings/services_settings_screen.dart:42` | `if (ForkTrackers.isOffered(info.service))` dans la boucle du hub | CA19, CA19f |

Pourquoi filtrer **dans le hub** et non dans `TrackerServiceInfo.all` : le hub est le seul point de connexion. Les deux
autres usages n'affichent que les services **connectés** (et MAL/AniList ne pourront jamais l'être). Filtrer `.all`
casserait `test/widgets/rating_bottom_sheet_test.dart`, qui attend 5 lignes avec des sessions injectées.

Le pack d'icônes : supprimer `assets/app_icons/` (aperçus et sources, qui sont des logos Plezy) et la ligne
`assets/app_icons/previews/` de `pubspec.yaml`. Fichiers partagés avec la plateforme (alias d'activité Android,
icônes alternatives iOS, `scripts/checks/check_icon_consistency.dart`) : à coordonner.

### 4. Trakt, Simkl, MDBList : identifiants injectés, masqués s'ils sont absents (CA19f)

`lib/fork/fork_trackers.dart` :

```dart
class ForkTrackerCredentials {
  const ForkTrackerCredentials({required this.traktClientId, required this.traktClientSecret,
      required this.simklClientId, required this.mdblistClientId});
  static const fromEnvironment = ForkTrackerCredentials(
    traktClientId: String.fromEnvironment('POPKINO_TRAKT_CLIENT_ID'),
    traktClientSecret: String.fromEnvironment('POPKINO_TRAKT_CLIENT_SECRET'),
    simklClientId: String.fromEnvironment('POPKINO_SIMKL_CLIENT_ID'),
    mdblistClientId: String.fromEnvironment('POPKINO_MDBLIST_CLIENT_ID'),
  );
  …
}

abstract final class ForkTrackers {
  @visibleForTesting static ForkTrackerCredentials? debugCredentialsOverride;
  static bool isOffered(TrackerService s) => switch (s) {
    TrackerService.mal || TrackerService.anilist => ForkFeatures.animeTrackers,  // false
    TrackerService.trakt => c.traktClientId.isNotEmpty && c.traktClientSecret.isNotEmpty,
    TrackerService.simkl => c.simklClientId.isNotEmpty,
    TrackerService.mdblist => c.mdblistClientId.isNotEmpty,
  };
}
```

Modifications upstream (`// FORK: identifiants Popkino injectés au build`) :

- `trakt_constants.dart:13-14` : `clientId = ForkTrackerCredentials.fromEnvironment.traktClientId` (et le secret).
- `simkl_constants.dart:22,27,30` : `v2ClientId` = identifiant injecté ; **`legacyClientId = v2ClientId`** (l'identifiant
  V1 de Plezy disparaît du binaire, et aucun jeton V1 ne peut exister dans Popkino) ; `appName = ForkIdentity.appSlug`.
- `mdblist_constants.dart:12,17` : `clientId` injecté, `appName = ForkIdentity.appSlug`.

Conséquences : aucun identifiant Plezy ne reste dans le code. Un build sans identifiant n'affiche pas le service, ne
peut pas s'y connecter, et n'a donc ni session, ni catalogue, ni notes (`connectedSources`). Les autres services ne
sont pas touchés. Les secrets ne sont pas dans le dépôt. En local, on les passe par
`--dart-define-from-file=popkino_secrets.json` (fichier ignoré par git, avec un modèle `popkino_secrets.example.json` à
valeurs vides) ; la CI les crée depuis les secrets GitHub (plateforme).

Cas limite assumé : si un build *avec* identifiants est remplacé par un build *sans* identifiants, une session déjà
enregistrée reste chargée. Les appels échouent alors en 401 et le code upstream invalide la session. Je ne mets pas de
filtre dans `TrackerAccountStore.load` : il casserait `trackers_provider_test.dart` (les tests tournent sans
identifiants) pour un scénario que seul un tiers ayant d'abord compilé avec nos identifiants pourrait rencontrer.

### 5. Traductions : fichiers upstream « dérivés », regénérés par script

Règle durable : **dans le fork, `lib/i18n/*.i18n.json` ne s'éditent jamais à la main.** Ils sont produits par
`scripts/fork/rebrand_i18n.py` à partir de la version upstream, d'une surcouche et de règles :

```
lib/fork/i18n/
  en.json, fr.json            // surcouche : clés nouvelles (fork.*) et valeurs remplacées, par langue
  rebrand_rules.json          // règles de remplacement, globales, par clé et par langue
```

Ce que fait le script, de façon idempotente :

1. Charger chaque `lib/i18n/<locale>.i18n.json` (en préservant l'ordre des clés).
2. Appliquer les règles **par langue** pour les formes fléchies, en commençant par la plus longue. Exemples :
   `tr` `Plezy'yi`→`Popkino'yu`, `Plezy'nin`→`Popkino'nun`, `Plezy'den`→`Popkino'dan`, `Plezy'de`→`Popkino'da` ;
   `az` `Plezy-ni`→`Popkino-nu`, `Plezy-nin`→`Popkino-nun`, `Plezy-dən`→`Popkino-dan`, `Plezy-də`→`Popkino-da`,
   `Plezy-yə`→`Popkino-ya` ; `kk` `Plezy-дегі`→`Popkino-дағы`, `Plezy-дің`→`Popkino-ның`, `Plezy-ді`→`Popkino-ны`,
   `Plezy-ден`→`Popkino-дан`, `Plezy-де`→`Popkino-да` ; `hu` `Plezyből`, `Plezy-ből`→`Popkinóból`, `Plezyben`→`Popkinóban`,
   `Plezyt`, `Plezy-t`→`Popkinót`, `Plezy-nek`→`Popkinónak`. Les composés (`Plezy-Profil`, `Plezy-ikon`), le japonais,
   le coréen (particules identiques : les deux noms finissent par une voyelle), l'ouzbek et le génitif suédois ou danois
   (`Plezys`→`Popkinos`) passent par la règle générale.
3. Règle générale : `Plezy`→`Popkino` dans **toutes les valeurs, jamais dans les clés**, sauf sous `fork.*`.
4. Règles **par clé** : `settings.servicesDescription` : `MyAnimeList`→`Simkl` (présent tel quel dans les 23 langues).
5. Fusion de la surcouche : ajout du bloc `fork` (À propos) et des valeurs remplacées.
6. Écriture avec le format canonique de `clean_translations.py` (`json.dumps(…, ensure_ascii=False, indent=2)`). Le
   diff textuel par rapport à l'upstream se limite donc aux lignes réellement changées.
7. `--check` : sortie en erreur si l'écriture modifierait un fichier (à brancher dans la CI du fork, côté plateforme).

Procédure de fusion upstream (à mettre dans le README du fork ou le skill `regles-fork`) :

```bash
git merge upstream/main
# en cas de conflit dans les traductions :
git checkout --theirs -- lib/i18n/*.i18n.json
python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh
```

Comme le fork n'édite jamais ces fichiers à la main, reprendre la version upstream ne perd rien. Une nouvelle chaîne
« Plezy » ajoutée par l'upstream sans conflit est détectée par le test de garde (`test/fork/i18n_branding_test.dart`).

Clés `fork.*` (en et fr obligatoires ; pour les autres langues, voir QUESTIONS PRODUIT) :
`fork.about.basedOn` (« Basé sur Plezy. Popkino est un projet indépendant, ni développé ni soutenu par le projet
Plezy. »), `fork.about.license` (« Licence »), `fork.about.sourceCode` (« Code source »),
`fork.about.sourceCodeQrHint` (« Scannez ce code avec votre téléphone pour ouvrir l'adresse »). Le nom de licence
`GPL-3.0` et l'URL ne sont pas traduits : ils viennent de `ForkIdentity`.

### 6. Écran À propos : nouveau fichier, route redirigée

`lib/fork/screens/fork_about_screen.dart` (`ForkAboutScreen`), construit comme `AboutScreen` avec
`FocusedScrollScaffold`, `FocusableListTile` et `SettingsGroup`. Seule modification upstream :
`settings_screen.dart:54,251` (import et `destinationBuilder: (_) => const ForkAboutScreen()`, `// FORK: À propos Popkino`).
L'entrée garde le `FocusNode` `_kAbout`, donc Retour revient sur « À propos » (parcours 3).

Contenu, de haut en bas :

- En-tête non focalisable : logo, `t.app.title`, version, `t.about.appDescription` (inchangée, ne cite pas Plezy),
  puis `t.fork.about.basedOn`.
- Groupe focalisable :
  1. « Code source », avec l'URL en sous-titre. OK : sur TV (`PlatformDetector.isTV()`) ou si `openExternalUrl`
     renvoie `false`, ouverture d'une boîte de dialogue avec QR code (`QrImageView`, déjà utilisé par
     `deep_link_dialog.dart`), l'URL en clair et un bouton Fermer focalisé ; ailleurs, ouverture du navigateur.
  2. « Licence » : sous-titre `GPL-3.0`. OK ouvre `LicensesScreen`, comme l'entrée existante.
  3. « Licences open source » (existante).

Le premier focus va sur « Code source » (`FocusedScrollScaffold`). Haut et bas parcourent les 3 entrées. Retour ferme
la boîte de dialogue, puis revient aux Paramètres (CA10, CA11). L'écran upstream `about_screen.dart` reste intact et
inutilisé (le compilateur l'élimine).

### 7. Tests

Nouveaux tests dans `test/fork/` :

| Fichier | Vérifie | CA |
|---|---|---|
| `i18n_branding_test.dart` | Aucune valeur des 23 JSON ne contient « Plezy » hors `fork.*` ; `t.app.title == ForkIdentity.appName` (en, fr) ; `fork.about.basedOn` présent en en et fr ; `settings.servicesDescription` sans « MyAnimeList » | CA9, CA19 |
| `plezy_services_guard_test.dart` | Analyse `lib/**/*.dart` (hors commentaires et `*.g.dart`) : pas de `plezy.app` sauf `certificate_trust.dart` ; pas de `edde746` sauf `anime_mappings_store.dart` et `donation_service.dart` (code mort) ; aucun des 4 anciens identifiants Trakt/Simkl/MDBList ; `Uri.parse(plezyServerBaseUrl).host` finit par `.invalid` | CA16, CA19f |
| `fork_features_test.dart` | `DiscordRPCService.isAvailable` faux ; `DonationService.isEnabled` faux ; `supporterBuildMode == unlocked` et `SupporterService` déverrouillé sans boutique ; `AppIconService` non pris en charge par défaut ; `needsFribb` faux pour Trakt, Simkl et MDBList ; `LogsScreen` sans action d'envoi mais avec copier et effacer ; `StartupFailureView` sans bouton d'envoi ; `ThemeSettingsScreen` sans cadenas | CA16, CA17, CA18, CA18b, CA19h, CA20 |
| `fork_trackers_test.dart` | Matrice `isOffered` (MAL/AniList toujours faux ; les trois autres selon les identifiants) ; `ServicesSettingsScreen` affiche ou masque chaque ligne selon `debugCredentialsOverride` sans toucher Seerr ; `SimklConstants.legacyClientId == v2ClientId` | CA19, CA19f, CA19i |
| `fork_identity_test.dart` | En-têtes Plex (`PlexConfig`, `PlexAuthService`) ; `jellyfinClientName` ; profil d'appareil Jellyfin ; `DeepLink.tryParse('plezy://open') == null` et `popkino://open` accepté ; lien de retour du lecteur externe en `popkino://` ; nom par défaut et client Regarder ensemble ; balise LAN `app == 'popkino'` ; URL interrogée par `UpdateService.debugPerformUpdateCheck` = `api.github.com/repos/adrien24/popkino/…` | CA12 à CA15, CA21, CA22 |
| `fork_about_screen_test.dart` | Logo, nom, version, mention « basé sur Plezy », GPL-3.0, URL ; focus initial sur « Code source » au D-pad ; flèche bas jusqu'à « Licences open source » ; en mode TV, OK ouvre le QR et Retour le ferme avec retour du focus ; Retour quitte l'écran | CA10, CA11 |

Tests upstream à adapter (une ligne chacun quand c'est possible, en référençant `ForkIdentity`) :

- Schéma : `test/services/deep_links/{deep_link,deep_link_service,item_links}_test.dart`,
  `test/widgets/deep_link_dialog_test.dart`, `test/models/external_player_models_test.dart`,
  `test/services/external_player_service_test.dart` (environ 70 littéraux `plezy://` → `popkino://`, remplacement
  mécanique, que le script peut prendre en charge avec une règle dédiée aux tests).
- Valeurs : `test/services/jellyfin_auth_header_test.dart` (environ 10 attentes sur les valeurs de repli),
  `test/watch_together/watch_together_provider_test.dart:429,448`,
  `test/services/media_browser_account_preferences_test.dart` (si l'espace Jellyfin change).
- Fonctions retirées : `test/screens/settings/logs_screen_test.dart` (tests d'envoi),
  `test/widgets/startup_failure_view_test.dart:100`, `test/startup_bootstrap_test.dart:467`, et
  `test/screens/settings/app_icon_setting_test.dart` (aperçus supprimés). Ces tests sont **marqués `skip:`** avec une
  constante `forkRemovedSkip` (dans `test/fork/fork_test_utils.dart`), pas supprimés : le diff reste d'une ligne et la
  fusion reste triviale.

## Alternatives écartées

1. **Supprimer le code des services retirés** : voir le tableau du point clé. MAL/AniList touchent 57 fichiers de
   `lib/` et 40 de test, sans compter le supporter et Discord. Chaque évolution upstream de ces zones produirait un
   conflit modify/delete, et la réactivation prévue au backlog serait coûteuse.
2. **Désactiver par `--dart-define`** (par exemple ne plus passer `ENABLE_DONATIONS`) : la décision vivrait dans la CI,
   que l'upstream modifie lui-même (`build.yml:36` active les dons, `deploy.py` active Sentry). Elle serait invisible
   en revue Dart et impossible à couvrir par `flutter test`. Je garde `--dart-define` seulement pour les secrets.
3. **Traductions** :
   - éditer les JSON à la main : 41 lignes × 23 fichiers en conflit potentiel, sans procédure de résolution
     mécanique ;
   - remplacer « Plezy » par un paramètre slang `${app}` : change la signature de ~40 clés, ce qui touche le Dart
     appelant et toutes les langues, soit un diff bien plus gros ;
   - post-traiter les `strings_*.g.dart` générés : les JSON continueraient d'afficher « Plezy », il faudrait modifier
     `scripts/codegen.sh` (upstream), et la mention « basé sur Plezy » demanderait un échappement.
4. **Modifier `about_screen.dart` sur place** : acceptable (fichier peu modifié), mais un nouveau fichier isole le fork
   pour 2 lignes de diff. Je le garde en repli si la plateforme ou l'orchestrateur préfère.
5. **Renommer les fichiers de logo** (`assets/popkino.png`) : 6 références Dart à modifier, et l'ancien fichier
   resterait dans le bundle s'il n'est pas supprimé. Remplacer le contenu suffit.
6. **Filtrer dans `TrackerServiceInfo.all`** : casse `rating_bottom_sheet_test.dart` sans rien apporter, car le hub est
   le seul point de connexion.

## Impact

### Fichiers upstream modifiés (`// FORK:` sur chaque ligne)

Environ **28 fichiers de `lib/`, environ 50 lignes**, de 1 à 7 lignes par fichier. Le plus gros diff est
`supporter_mode.dart` (expression const remplacée). Liste : `plex_client.dart`, `plex_config.dart`,
`plex_auth_service.dart`, `plex_discover_client.dart`, `jellyfin_auth_header.dart`, `jellyfin_client/parts/playback.dart`,
`jellyfin_display_preferences.dart`, `media_image_helper.dart`, `deep_link.dart`, `update_service.dart`,
`watch_together_provider.dart`, `profile_session_screen.dart`, `lan_discovery_service.dart`, `main.dart`,
`startup_diagnostics.dart`, `settings_export_service.dart`, `plezy_server.dart`, `discord_rpc_service.dart`,
`logs_screen.dart`, `startup_failure_view.dart`, `donation_service.dart`, `supporter_mode.dart`,
`app_icon_service.dart`, `services_settings_screen.dart`, `settings_screen.dart`, `trakt_constants.dart`,
`simkl_constants.dart`, `mdblist_constants.dart`.

Fichiers dérivés : les 23 `lib/i18n/*.i18n.json` et les `strings_*.g.dart` générés (environ 41 lignes par langue,
regénérés par script). Tests upstream : environ 15 fichiers. Partagés avec la plateforme : `pubspec.yaml` (une
ligne d'assets) et les fichiers de logo.

### Nouveaux fichiers

`lib/fork/fork_identity.dart`, `lib/fork/fork_features.dart`, `lib/fork/fork_trackers.dart`,
`lib/fork/screens/fork_about_screen.dart`, `lib/fork/i18n/{en,fr}.json`, `lib/fork/i18n/rebrand_rules.json`,
`scripts/fork/rebrand_i18n.py`, `popkino_secrets.example.json`, `test/fork/*.dart` (7 fichiers).

### Dépendances ajoutées

Aucune. `qr_flutter`, `in_app_purchase`, `sentry_flutter` et `dart_discord_presence` restent : les retirer
imposerait de supprimer leurs imports dans le code upstream.

### Interfaces avec la plateforme (à aligner en phase 2)

- Valeur du schéma : `popkino` (manifeste Android, Info.plist, registre Windows, `.desktop` Linux, et tout code natif
  qui **construit** des URI `plezy://`, par exemple la rangée Watch Next ou les raccourcis).
- Noms des defines : `POPKINO_TRAKT_CLIENT_ID`, `POPKINO_TRAKT_CLIENT_SECRET`, `POPKINO_SIMKL_CLIENT_ID`,
  `POPKINO_MDBLIST_CLIENT_ID` ; `popkino_secrets.json` dans `.gitignore`.
- La CI du fork n'a plus besoin de passer `ENABLE_DONATIONS`, `ENABLE_SENTRY` ni `SUPPORTER_MODE` : ils sont ignorés ou
  sans effet en Dart. `ENABLE_UPDATE_CHECK=true` reste nécessaire pour les releases GitHub.
- URL de l'appcast (`ForkIdentity.updateFeedUrl`) : à fixer avec le pipeline Sparkle/WinSparkle du fork.
- **Schéma de version** : `UpdateService._isNewerVersion` compare le `tag_name` GitHub avec la version de
  `pubspec.yaml`, et coupe sur `-` et `+`. Un tag du type `v2.26.0-popkino.1` ne serait jamais vu comme plus récent que
  `2.26.0`. Il faut une version numérique `X.Y.Z` propre au fork.
- Alias d'icônes Android et icônes alternatives iOS à retirer, `check_icon_consistency.dart` à adapter, logos à
  regénérer aux mêmes chemins.
- `certificate_trust.dart:37` garde `plezy.app` (miroir de `network_security_config.xml`, vérifié par
  `test/android/network_security_config_test.dart`). C'est inoffensif ; le retirer demande de changer les deux côtés.
- `in_app_purchase_android` ajoute la permission `com.android.vending.BILLING` au manifeste. Il faut évaluer s'il faut
  la retirer (`tools:node="remove"`) pour la fiche Play et le formulaire « Sécurité des données » (l'app ne fait aucun
  achat). Même question pour la présence du SDK Sentry natif.
- Brancher `python3 scripts/fork/rebrand_i18n.py --check` dans la CI du fork.

### Risques

- **Google Play** : du code mort embarqué (MAL, proxy, Discord, IAP) n'envoie aucune donnée. Les points sensibles sont
  la permission BILLING et le SDK Sentry (voir ci-dessus).
- **Marque** : « Plezy » ne reste visible que dans la mention « basé sur Plezy » de l'écran À propos. Il reste aussi
  dans des messages de journal techniques (par exemple sur l'hôte des posters, inatteignable) et dans
  `startup.repairBodySessionsUncertain`, qui cite « MAL, AniList » (écran de réparation rare : laissé tel quel).
- **Traductions** : les règles hu, tr, az et kk sont écrites sans relecteur natif. Risque de formes maladroites, sans
  impact fonctionnel.
- **Analyseur** : un `if (ForkFeatures.x)` sur une constante `false` peut déclencher un avertissement `dead_code` selon
  la version de l'analyseur. Si c'est le cas, ajouter `// ignore: dead_code` sur la ligne concernée.
- **Regarder ensemble** : les relais Open Watch Party connaissent les clients par leur chaîne `client`, et le SDK a un
  code `clientBlocked`. Il faut vérifier qu'un nouveau nom `Popkino/x.y.z` est accepté sans enregistrement préalable
  (test manuel).
- **Performances TV** : aucun impact (portes `const`, aucun travail ajouté au démarrage).
- **Conflits de fusion** : environ 28 fichiers avec des diffs d'une à quelques lignes, marqués `// FORK:` ; les
  traductions se résolvent mécaniquement ; environ 15 tests avec des diffs d'une ligne.

## Décisions durables proposées (pour `docs/technique/decisions.md` au plan final)

- **D1 — Emplacement du code du fork** : `lib/fork/`, `test/fork/`, `scripts/fork/`. Toute ligne modifiée dans un
  fichier upstream porte `// FORK: <raison>` (en français), et le diff reste localisé. Inventaire :
  `grep -rn "FORK:" lib test`.
- **D2 — Identité centralisée** : chaque valeur d'identité (nom, slug, schéma, dépôt, URL) vit dans
  `lib/fork/fork_identity.dart`. Le code upstream y fait référence, jamais à un littéral.
- **D3 — Services retirés = neutralisés, pas supprimés** : constantes `const` de `lib/fork/fork_features.dart`
  (jamais `--dart-define`), appliquées au point d'entrée et à la base réseau. Les tests upstream de l'interface d'une
  fonction retirée sont marqués `skip:`, pas supprimés.
- **D4 — Secrets de build** : `--dart-define` préfixés `POPKINO_`, lus uniquement dans `lib/fork/`. Une valeur vide
  masque la fonction. En local : `--dart-define-from-file=popkino_secrets.json` (ignoré par git).
- **D5 — Traductions dérivées** : `lib/i18n/*.i18n.json` ne s'éditent jamais à la main dans le fork. Ils sont produits
  par `scripts/fork/rebrand_i18n.py` (upstream + `lib/fork/i18n/` + règles). En cas de conflit : version upstream, puis
  on relance le script. Les nouvelles chaînes du fork vont sous la clé `fork.*`.
- **D6 — Tests de garde du fork** : `test/fork/` contient des tests d'invariants (aucun service Plezy, aucune valeur
  « Plezy » visible). Ils sont la première chose à lancer après chaque fusion upstream.

## Résumé

1. Identité : `lib/fork/fork_identity.dart` centralise nom, schéma, dépôt et URL ; ~28 fichiers upstream changent d'une
   à quelques lignes, marquées `// FORK:`.
2. Services Plezy (Sentry, journaux, Discord, dons, supporter, icônes, MAL/AniList) : neutralisés par des constantes
   `const` du fork, ni supprimés (MAL/AniList = 97 fichiers) ni laissés à un `--dart-define`, que la CI upstream active.
3. Défense en profondeur : `plezyServerBaseUrl` pointe vers un domaine `.invalid`, et un test de garde bloque toute
   nouvelle URL `plezy.app` ou `edde746` après une fusion.
4. Trakt/Simkl/MDBList : identifiants via `--dart-define` `POPKINO_*` ; service masqué dans le hub s'il manque ;
   identifiants Plezy (dont Simkl V1) retirés du code.
5. Traductions : fichiers upstream dérivés par `scripts/fork/rebrand_i18n.py`, avec des règles pour les langues à
   flexion (hu, tr, az, kk) ; fusion = version upstream + relancer le script.
6. À propos : nouvel écran `ForkAboutScreen` (QR code pour le code source sur TV), 2 lignes changées dans
   `settings_screen.dart`.
7. Logos : mêmes chemins de fichiers, contenu remplacé ; aucune ligne de Dart touchée.
8. À trancher avec la plateforme : schéma de version numérique, permission BILLING, appcast, retrait des alias
   d'icônes.

## QUESTIONS PRODUIT

1. **Langues des nouvelles phrases** (mention « Basé sur Plezy… », « Code source », aide du QR code) : faut-il les
   traduire dans les 22 langues, ou l'anglais par défaut (avec le français) suffit-il pour les autres ? Ma
   recommandation : anglais et français maintenant, les autres langues plus tard.
2. **« Code source » sur TV** : la plupart des TV n'ont pas de navigateur. Je propose d'afficher un QR code et
   l'adresse en clair, à scanner avec le téléphone. Est-ce le comportement attendu ?
3. **Préférences de compte Jellyfin/Emby enregistrées sur le serveur** : aujourd'hui sous le nom « Plezy ». Si Popkino
   garde ce nom, un réglage changé dans Popkino change aussi dans Plezy officiel pour le même compte. Ma recommandation,
   au nom du CA8 : séparer, sous le nom « Popkino ». À confirmer.
4. **Écran de réparation au démarrage** : un texte rare cite « MAL, AniList » parmi les services enregistrés. Peut-on
   le laisser tel quel ? Ma recommandation : oui, il reste exact.
