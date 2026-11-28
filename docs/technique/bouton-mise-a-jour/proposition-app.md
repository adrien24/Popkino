# Proposition app — bouton-mise-a-jour

Auteur : architecte-app · 2026-11-28 · Phase 1 (rédigée sans lire la proposition plateforme)
Spec : `docs/produit/specs/bouton-mise-a-jour.md` (validée le 2026-11-28).
Décisions lues : D1 à D12. La proposition s'appuie sur D2, D3, D6, D7 et D11, et constate que la condition posée par D7
(« pas de flavor tant que le manifeste ne diffère pas ») est maintenant remplie. Ce choix revient à la plateforme.

## Compréhension de la spec

Sur l'APK GitHub (Android TV, Fire TV, téléphone), quand une version plus récente est publiée (pré-versions comprises),
un bouton « Mise à jour » avec une pastille apparaît à droite de Watch Together sur Découvrir. Il ouvre une fenêtre
(notes de version, puis téléchargement de l'APK adapté au processeur avec progression et annulation), et l'installation
passe par l'installeur du système. La fenêtre de démarrage et Paramètres mènent au même parcours. Les versions store
et ordinateur ne changent pas.

Critères de mon périmètre :
- **Dart seul** : CA1 à CA9, CA15 à CA17, CA21, CA23 à CA26.
- **Partagés avec la plateforme** : CA10, CA11, CA13, CA14, CA18, CA19 et CA20. Le Dart pilote le parcours, le natif
  fournit l'autorisation, l'installation et son résultat.
- **Plateforme seule** : CA12, qui dépend du même `applicationId` et de la même clé. Côté Dart, rien n'est effacé.
  CA22 est garanti par construction, voir « Approche ».

## Existant

### Mise à jour
- **`lib/services/update_service.dart`, `UpdateService`** (upstream, déjà marqué `FORK` pour `ForkIdentity`).
  - `_performUpdateCheck` vérifie l'activation (`isUpdateCheckAvailable` = `ENABLE_UPDATE_CHECK` et pas MSIX), puis le
    délai de 6 h (seulement au démarrage). Il enregistre ensuite l'heure **avant** la requête et appelle
    `GET https://api.github.com/repos/$_githubRepo/releases/latest`.
  - Il retire un éventuel `v` du tag, compare avec `_isNewerVersion` et filtre la version ignorée
    (`getSkippedVersion`), y compris pour la vérification manuelle.
  - Il renvoie une `Map<String, dynamic>` (`hasUpdate`, `currentVersion`, `latestVersion`, `releaseUrl`,
    `releaseName`, `releaseNotes`, `publishedAt`).
  - **Constat vérifié** : `gh api repos/adrien24/popkino/releases/latest` renvoie **404**, car les deux releases
    (`v0.1.0`, `v0.2.0`) sont des pré-versions. Aujourd'hui, la vérification échoue donc toujours, sans rien dire.
- **`lib/utils/update_dialog.dart`, `showUpdateAvailableDialog`** (upstream) : `AlertDialog` avec « Plus tard »,
  « Ignorer cette version » (`showSkipVersion`) et « Voir les notes de version » (`launchUrl`). Elle a deux appelants :
  - `lib/screens/main_screen.dart`, `_checkForUpdatesOnStartup` (l.890) : sort tout de suite si
    `autoCheckUpdatesOnStartup` est désactivé, puis appelle `UpdateService.checkForUpdatesOnStartup()` ;
  - `lib/screens/settings/settings_screen.dart`, `_checkForUpdates` (l.923), qui appelle
    `UpdateService.checkForUpdates()`, puis `_showUpdateDialog` (l.947).
- **Réglage** : `SettingsService.autoCheckUpdatesOnStartup` (`settings_service.dart` l.739, `true` par défaut).
- **Releases réelles** (`gh api …/releases`) :
  - les fichiers sont des **APK bruts** nommés `popkino-android-<abi>-<version>.apk`, plus `SHA256SUMS.txt` ;
  - chaque fichier a un champ `digest: "sha256:…"` dans l'API ;
  - `browser_download_url` redirige vers `release-assets.githubusercontent.com`, déjà couvert par
    `network_security_config.xml` (cf. `_redirectTargetDomains` dans `test/android/network_security_config_test.dart`).
  - **En revanche**, `.github/workflows/build.yml` (l.136-139) publie `popkino-android-<abi>.tar.gz` (APK renommé
    `popkino.apk` dans une archive). Une release produite par la CI serait donc invisible pour le bouton. Voir les
    interfaces demandées à la plateforme.
- **Version installée** : `AppVersion.current()` (`lib/utils/app_version.dart`). `pubspec.yaml` est en `1.0.0+1`.

### Accueil et focus
- **`lib/screens/discover_screen.dart`, `_buildOverlaidAppBar`** (l.851) : une seule fonction pour le téléphone et la
  TV (la TV l'enveloppe dans `TvToolbarOverlay`, l.1170). Ordre des actions de `FocusableActionBar` : actualiser,
  **Watch Together**, télécommande compagnon, tâches serveur (bureau), menu utilisateur. Elles sont construites dans un
  `Consumer2<WatchTogetherProvider, CompanionRemoteProvider>`. Le bouton Watch Together utilise `child:` (Stack +
  `IconButton` + pastille `IgnorePointer`). La pastille « connecté » de la télécommande est un rond de 8 px.
- **`lib/focus/focusable_action_bar.dart`** : Gauche/Droite sautent les actions sans `onPressed`
  (`_nextEnabledIndex`). Bas appelle `onNavigateDown` (`_focusContentFromAppBar`) et le bord gauche appelle
  `_navigateToSidebar`.
  - **Piège** : quand la **longueur** de la liste change, `_rebindNodes` ne réutilise les nœuds des actions sans
    `debugLabel` que si la forme de la liste est stable. Faire apparaître un bouton plus tard recrée donc les nœuds de
    Watch Together et des actions suivantes, et fait perdre le focus si l'utilisateur est dans la barre.
  - Si la longueur, les `focusNode` et les `debugLabel` restent identiques, `_shouldRebuildFocusNodes` est faux et
    aucun nœud n'est recréé.
  - Aujourd'hui, au D-pad, aucune action n'affiche son nom au focus : le `tooltip` de l'`IconButton` ne s'affiche qu'au
    survol ou à l'appui long, car le `Focus` parent a `descendantsAreFocusable: false`.
- **Fenêtres** : `showScopedDialog` (`lib/utils/dialogs.dart`) pousse une `DialogRoute` en `closedLoop`. Au retour,
  Flutter rend le focus au dernier nœud focalisé de la route du dessous, ici le bouton.
  - `DialogActionButton` expose `autofocus`, `onNavigateUp`, `onNavigateDown` et `onBack`. Ils serviront à faire
    défiler les notes à Haut/Bas sans quitter les boutons.
- **Tests upstream de Découvrir** (`test/screens/discover_screen_test.dart`) : ils fournissent `WatchTogetherProvider`
  et `CompanionRemoteProvider`, rien d'autre. Un `context.watch<NouveauType>()` non nullable y lèverait
  `ProviderNotFoundException`.
  - L'upstream connaît déjà la lecture tolérante `context.read<T?>()` (`video_player_navigation.dart` l.325,
    `media_navigation_helper.dart` l.221).
  - Dans `provider` 6.1.5, `_inheritedElementOf` renvoie `null` sans lever d'exception quand `T` est nullable.

### Réseau, fichiers, appareil
- **`lib/utils/media_server_http_client.dart`** :
  - `httpClient.get` (décodage JSON, `AbortController`) sert déjà à `UpdateService` et se teste avec `MockClient` ;
  - `downloadFile` n'a **pas** de rappel de progression ;
  - `AbortController` et `http.AbortableRequest` coupent vraiment le transfert.
- **`platform.createPlatformClient()`** (`lib/utils/platform_http_client_io.dart`) : client `dart:io` avec un délai de
  connexion borné, déjà utilisé par `anime_mappings_store.dart` avec `http.AbortableRequest`.
  `CertificateTrust.fixedEndpointDomains` contient déjà `github.com`.
- **`device_info_plus`** (dépendance existante, `platform_detector.dart` l.97) : `AndroidDeviceInfo.supportedAbis`
  liste les ABI par ordre de préférence. La Fire TV Stick (`AFTMA08C15`) n'annonce que `armeabi-v7a`. **Aucun natif
  n'est nécessaire** pour choisir l'APK.
- **`crypto`** (dépendance existante) : `sha256.startChunkedConversion` calcule l'empreinte pendant le
  téléchargement, sans relire le fichier.
- **`path_provider`**, `getTemporaryDirectory()` : `Context.getCacheDir()` sur Android.
- **i18n** : surcouche `lib/fork/i18n/{en,fr}.json` (clés `fork.*`), produite par `scripts/fork/rebrand_i18n.py`
  (D6). `slang.yaml` est en `fallback_strategy: base_locale_empty_string`, donc les autres langues retombent sur
  l'anglais. Clés upstream réutilisables : `update.available`, `update.versionAvailable`, `update.skipVersion`,
  `common.later`, `common.close`, `common.cancel` et `common.retry` (en français : « Mise à jour disponible »,
  « Version X disponible », « Ignorer cette version », « Plus tard », « Fermer », « Annuler », « Réessayer »).

## Approche proposée

### Principe

**Tout le parcours Android vit dans `lib/fork/update/`. L'upstream ne reçoit que 4 crochets d'une ligne, marqués
`// FORK: bouton-mise-a-jour`, dont le résultat `null` laisse l'upstream décider (D11).**
- Les crochets ne s'activent que si `Platform.isAndroid && UpdateService.isUpdateCheckAvailable`.
- Ordinateurs (Sparkle, WinSparkle, repli Linux), iOS et toutes les versions store passent donc par le code upstream,
  inchangé (CA20, CA22).

### 1. Fichiers nouveaux (`lib/fork/update/`)

| Fichier | Contenu | Pur ? |
|---|---|---|
| `fork_release.dart` | `ForkRelease` (version, tag, nom, notes, `htmlUrl`, `publishedAt`, `isPrerelease`, `ForkApkAsset apk`) ; `ForkApkAsset` (nom, url, taille, `sha256?`, abi). Classes immuables simples, sans freezed (rien à générer, aucun conflit). | oui |
| `release_picker.dart` | `ForkRelease? pickForkRelease(List<Object?> releasesJson, {required String installedVersion, required List<String> supportedAbis})` ; `int compareForkVersions(String a, String b)` ; `String releaseNotesToPlainText(String markdown)`. | oui |
| `install_channel.dart` | `ForkInstallChannel` : façade du canal natif (contrat plus bas), remplaçable en test. | — |
| `apk_downloader.dart` | `ForkApkDownloader.download(asset, file, {onProgress, abort})` : flux `http.AbortableRequest` → fichier `.part`, empreinte SHA-256 en continu, délai d'inactivité, correspondance des erreurs. | — |
| `fork_update_controller.dart` | `ForkUpdateController extends ChangeNotifier` : disponibilité de la mise à jour, singleton global. | — |
| `fork_update_session.dart` | `ForkUpdateSession extends ChangeNotifier` : une par fenêtre ; phases du téléchargement et de l'installation. | — |
| `fork_update_dialog.dart` | `showForkUpdateDialog(context, release, {showSkipVersion})` et le widget de la fenêtre. | — |
| `fork_update_action.dart` | `FocusableAction forkUpdateAction(BuildContext context, {required Color iconColor})`. | — |
| `fork_update_hooks.dart` | `ForkUpdateHooks.performCheck(...)` et `ForkUpdateHooks.showDialog(...)` : les seuls points d'entrée appelés depuis l'upstream. | — |

Au total, environ 9 fichiers et 900 lignes, découpables en tâches de moins de 300 lignes. Le sous-dossier par
fonctionnalité est proposé comme décision durable, voir la fin du document.

### 2. Choix de la release (CA5, CA8, CA17) : `release_picker.dart`

- **Requête** : `GET https://api.github.com/repos/${ForkIdentity.githubRepo}/releases?per_page=20`, au lieu de
  `/releases/latest` qui exclut les pré-versions. Elle passe par `httpClient.get` avec un délai de 10 s et l'en-tête
  `Accept: application/vnd.github+json`. Une seule requête par lancement (voir 3) : la limite de 60 requêtes par heure
  et par IP de l'API anonyme reste loin.
- **Filtre** :
  - on écarte `draft == true`. Une requête anonyme ne voit pas les brouillons, mais on se protège quand même ;
  - on garde `prerelease` ;
  - le tag doit correspondre à `^v?\d+\.\d+\.\d+$` : `v0.2.0` (actuel) et `1.0.0` (D10) sont acceptés, tout autre
    tag est ignoré.
- **Ordre** : la release de **plus grand numéro**, pas la plus récente par date (CA5). Si elle n'est pas plus récente
  que la version installée, il n'y a pas de mise à jour. La comparaison de `compareForkVersions` est numérique, champ
  par champ, et ignore `+N`. Je reproduis la logique privée `_isNewerVersion` plutôt que de la rendre publique dans
  l'upstream.
- **Fichier** : on parcourt `supportedAbis` dans l'ordre et on garde le premier asset qui correspond à
  `^${ForkIdentity.appSlug}-android-<abi>(-[0-9][0-9.]*)?\.apk$`, avec ou sans version dans le nom.
  - Fire TV Stick : `armeabi-v7a`. Un appareil 64 bits : `arm64-v8a` en premier (CA8).
  - S'il n'y a aucun asset pour l'appareil, la fonction renvoie `null` et le bouton n'apparaît pas (CA17). On ne
    redescend pas vers une release plus ancienne, voir QUESTIONS PRODUIT.
- **Intégrité** : on reprend `digest` (`sha256:<hex>`) quand il est présent, sinon on ne vérifie pas. L'installeur du
  système refuse de toute façon un APK abîmé ou signé par une autre clé. On ne télécharge pas `SHA256SUMS.txt` : le
  `digest` de l'API suffit et évite une requête.
- **Notes** : `releaseNotesToPlainText` retire `**`, `__`, `` ` `` et les `#` de titre, transforme `[texte](url)` en
  `texte` et les puces `-` ou `*` en `•`. Aucune dépendance Markdown n'est ajoutée (il n'y en a pas dans `pubspec.yaml`).

### 3. État : `ForkUpdateController` (provider global)

```dart
class ForkUpdateController extends ChangeNotifier {
  static final instance = ForkUpdateController();          // + constructor injection for tests
  static bool get isSupported => Platform.isAndroid && UpdateService.isUpdateCheckAvailable; // overridable in tests
  ForkRelease? get available;                               // null = no button
  Future<void> ensureChecked();                             // once per process, never throws (CA15)
  Future<ForkRelease?> refresh({bool throwOnFailure = false}); // manual check from Settings
}
```

- **Une vérification réseau par lancement, sans délai de 6 h**. C'est ce qui permet au bouton d'apparaître à chaque
  ouverture (CA1, CA4), y compris quand la vérification au démarrage est désactivée (CA25). Le délai de 6 h ne
  s'applique qu'à la fenêtre automatique, voir 4.
- **Les appels simultanés partagent la même requête** (`_inFlight`). Avant la requête, `ensureChecked()` :
  - demande au natif `getInstallCapability()` : si `declared` est faux (permission absente du manifeste), il n'y a
    jamais de bouton ;
  - **purge `<cache>/popkino_update/`**, ce qui couvre l'APK resté après une installation réussie (le système tue le
    processus pendant la mise à jour) ou après un plantage (CA14).
- **Échec réseau, HTTP non 200 ou JSON invalide** : `appLogger.w`, `available` reste `null`, aucun message (CA15).
- **La version ignorée n'est pas filtrée ici** : le bouton reste visible (CA24).
- `notifyListeners()` n'est appelé que si `available` change, c'est-à-dire presque jamais. La barre de Découvrir n'est
  pas reconstruite pendant le téléchargement, car la progression vit dans `ForkUpdateSession`. C'est important sur la
  Fire TV Stick.
- **Exposé par provider** : dans `lib/main.dart`, on ajoute au `MultiProvider` racine
  `ChangeNotifierProvider<ForkUpdateController>.value(value: ForkUpdateController.instance)`. Le provider est global,
  car la mise à jour ne dépend pas du profil. On utilise `.value` pour que le singleton ne soit jamais libéré.
- **Lecture tolérante** : `context.watch<ForkUpdateController?>()`. Les tests upstream qui ne fournissent pas ce
  provider obtiennent `null`, donc pas de bouton, et passent sans modification.

### 4. Crochets upstream : 4 fichiers, une ligne de code chacun (plus l'import)

**H1 — `lib/screens/discover_screen.dart`**, dans la liste `actions:`, juste après le `FocusableAction` de Watch
Together :

```dart
forkUpdateAction(context, iconColor: foregroundColor), // FORK: bouton-mise-a-jour — update button next to Watch Together
```

`forkUpdateAction` lit `context.watch<ForkUpdateController?>()` (le `context` est celui du builder du `Consumer2`,
qui se reconstruit donc quand la disponibilité change) et appelle `controller.ensureChecked()`. L'appel est
idempotent et asynchrone ; il déclenche la vérification dès l'arrivée sur l'accueil (CA1 : en général moins de 2 s).

**L'emplacement est stable** (c'est le point TV important) :
- l'action est **toujours présente**, avec `debugLabel: 'fork_update'` ;
- **sans mise à jour** : `onPressed: null` et `child: SizedBox.shrink()`. Largeur nulle (la barre de Découvrir a
  `spacing: 0`), pas de focus possible, Gauche/Droite sautent par-dessus. La barre est donc visuellement identique à
  aujourd'hui (CA2) ;
- **avec une mise à jour** : `onPressed` est renseigné et le contenu apparaît. La longueur, les `debugLabel` et les
  `focusNode` sont inchangés, donc `_shouldRebuildFocusNodes` est faux. Aucun nœud n'est recréé et le focus de
  l'utilisateur n'est pas perturbé, même s'il est dans la barre au moment où le bouton apparaît ;
- le bouton utilise `builder:` (qui reçoit `showFocus`). Il reproduit la décoration de ses voisins
  (`FocusTheme.focusBackgroundDecoration(context, isFocused: showFocus, borderRadius: 20)`), avec un `IconButton`
  `Symbols.system_update_rounded` de même taille, `tooltip` pour le toucher et le survol, et une pastille ronde de 8 px
  en `colorScheme.primary` sous `IgnorePointer`, comme celle de la télécommande (#2846 upstream) ;
- **au focus D-pad** (`showFocus`), le nom « Mise à jour disponible » s'affiche dans une étiquette sous le bouton,
  dessinée par `OverlayPortal`. Elle ne change pas la mise en page et n'est pas coupée par `ToolbarScrim`.
  C'est l'étape 2 du parcours ; aujourd'hui, les voisins n'affichent pas leur nom au focus.
- Le focus de départ de l'écran ne change pas : aucun `autofocus` (étape 1 du parcours). Gauche, Droite, Bas et le bord
  gauche sont gérés par `FocusableActionBar` comme pour Watch Together (CA3). Le toucher passe par l'`IconButton` (CA26).
- `onPressed` appelle `showForkUpdateDialog(context, controller.available!, showSkipVersion: false)`. À la fermeture,
  le focus revient au bouton grâce à la restauration de focus de la route (CA7, CA9).

**H2 — `lib/services/update_service.dart`, `_performUpdateCheck`**, juste après le bloc
`if (respectCooldown) await _updateLastCheckTime();`, dans le `try` :

```dart
// FORK: bouton-mise-a-jour — pre-releases and per-ABI APK on Android (null = upstream)
if (ForkUpdateHooks.performCheck(currentVersion, startup: respectCooldown) case final fork?) return await fork;
```

- Le crochet renvoie `Future<Map<String, dynamic>?>?`, ou `null` hors Android, ce qui laisse l'upstream continuer.
- Le délai de 6 h, l'enregistrement de l'heure avant la requête et le `catch` (journal, puis `rethrow` si
  `throwOnFailure`) restent ceux de l'upstream. Le crochet ne remplace que la requête et l'analyse.
- **Démarrage** (`startup: true`) : `await controller.ensureChecked()` (résultat déjà en cache si l'accueil l'a
  lancé), puis le crochet **applique la version ignorée** (`UpdateService.getSkippedVersion()`, public) et renvoie la
  map ou `null` (CA23, CA24).
- **Manuel, depuis Paramètres** (`startup: false`) : `await controller.refresh(throwOnFailure: true)`. La version
  ignorée **n'est pas** filtrée, contrairement à l'upstream, car CA21 demande que Paramètres trouve la version.
  « Vous utilisez la dernière version » et « Échec de la vérification » restent les messages upstream.
- Dans les deux cas, la map garde les clés upstream (`hasUpdate`, `currentVersion`, `latestVersion`, `releaseUrl`,
  `releaseName`, `releaseNotes`, `publishedAt`) et ajoute `'forkRelease': ForkRelease`. La tuile de Paramètres
  (`_updateInfo['latestVersion']`) fonctionne donc sans changement.
- `main_screen.dart` et `settings_screen.dart` **ne sont pas modifiés**. La fenêtre de démarrage garde son
  enchaînement upstream : réglage activé, puis délai de 6 h, puis version ignorée.

**H3 — `lib/utils/update_dialog.dart`, `showUpdateAvailableDialog`**, en première ligne :

```dart
// FORK: bouton-mise-a-jour — download and install the APK instead of opening the browser (null = upstream)
if (ForkUpdateHooks.showDialog(context, updateInfo, showSkipVersion: showSkipVersion) case final fork?) return fork;
```

Le crochet renvoie `null` si la map ne contient pas `forkRelease` (ordinateur), sinon il appelle
`showForkUpdateDialog`. Il couvre à la fois la fenêtre de démarrage (`main_screen`, `showSkipVersion: true` : trois
boutons, CA23) et Paramètres (CA21). Le libellé de fermeture est toujours « Plus tard », comme CA6, même quand
Paramètres passe `t.common.close`.

**H4 — `lib/main.dart`** : la ligne `ChangeNotifierProvider…value` décrite en 3.

En option, mais recommandé : ajouter `'lib/fork/update/release_picker.dart'` (ou le fichier qui porte l'URL
`https://api.github.com/…`) à `_fixedEndpointSourcePaths` de `test/android/network_security_config_test.dart`, avec
`// FORK:`. Ce test vérifie que l'hôte reste couvert par la configuration réservée aux autorités système.

### 5. Fenêtre et parcours : `ForkUpdateSession` et `fork_update_dialog.dart`

La session, créée par la fenêtre et libérée avec elle, est une machine à états sur une classe scellée
`ForkUpdatePhase` :

| Phase | Contenu affiché | Boutons (focus initial en **gras**) | CA |
|---|---|---|---|
| `details` | `update.versionAvailable(X.Y.Z)`, « Version installée : A.B.C », notes en texte | Plus tard · [Ignorer cette version] · **Télécharger et installer** | CA6, CA7, CA23 |
| `downloading(fraction)` | barre `LinearProgressIndicator` + « 42 % » | **Annuler** | CA8, CA9 |
| `needsPermission` | « Pour installer la mise à jour, autorisez Popkino à installer des applications. » | Annuler · **Ouvrir les réglages** | CA10 |
| `permissionDenied` | « Installation impossible sans autorisation. » | Fermer · **Réessayer** (rouvre les réglages) | CA11 |
| `installing` | « Suivez les instructions à l'écran pour installer la mise à jour. » | **Annuler** | CA12, CA13 |
| `failed(kind)` | réseau : « Le téléchargement a échoué. Vérifiez la connexion. » ; espace : « Espace insuffisant pour télécharger la mise à jour. » ; signature : message de CA19 ; autre : message générique | Fermer · **Réessayer** (Fermer seul pour la signature) | CA16, CA18, CA19 |

Règles :
- **TV** :
  - `AlertDialog` et `DialogActionButton`, avec `autofocus` sur le bouton en gras ;
  - les notes sont dans un `SingleChildScrollView` avec un `ScrollController`, `maxHeight` à 50 % de l'écran ;
  - `onNavigateUp` et `onNavigateDown` des boutons font défiler les notes d'environ 80 % de leur hauteur visible
    (CA6). Le focus reste sur les boutons, donc jamais sur un texte non actionnable ;
  - styles `titleMedium` et `bodyLarge`, lisibles à 3 m.
- **Retour** : `PopScope` laisse toujours fermer. `onPopInvokedWithResult` et le `dispose` de la session appellent
  `session.cancel()`, qui coupe la requête (`abort`) et supprime le `.part` et l'APK (CA7, CA9, CA14). Le focus revient
  au bouton.
- **Téléchargement** (`ForkApkDownloader`) :
  - le fichier est écrit dans `<getTemporaryDirectory()>/popkino_update/popkino-<version>-<abi>.apk.part`, puis renommé
    en `.apk` quand l'empreinte est vérifiée ;
  - un délai d'inactivité de 30 s sans octet reçu compte comme une erreur réseau (CA16) ;
  - la taille de référence est `Content-Length`, sinon `asset.size` ;
  - la progression est signalée au plus toutes les 250 ms ou tous les 1 %, pour éviter des reconstructions inutiles
    sur TV ;
  - **avant de télécharger**, si le natif renvoie `availableBytes` et qu'il est inférieur à `asset.size` + 10 %, on
    passe en `failed(storage)` sans rien télécharger (CA18). Pendant l'écriture, une `FileSystemException` avec
    `osError.errorCode == 28` (ENOSPC) donne le même résultat ;
  - une empreinte différente est traitée comme `failed(network)` : le fichier est supprimé et « Réessayer » relance.
- **Autorisation** :
  - après le téléchargement, `getInstallCapability()` ; si `canRequestInstalls` est faux, on passe en
    `needsPermission` ;
  - « Ouvrir les réglages » appelle `openInstallPermissionSettings()`. Un `AppLifecycleListener(onResume:)` interroge
    ensuite à nouveau le natif : accordée, on installe **sans retélécharger** (l'APK est gardé) ; refusée, on passe en
    `permissionDenied` (CA10, CA11) ;
  - si le natif renvoie `false` (aucune activité de réglage, possible sur certains Fire OS), on affiche le chemin à
    suivre à la main (texte `fork.update.permissionManual`).
- **Installation** : `installApk(path)` renvoie une issue :
  - `cancelled` : la fenêtre se ferme et l'APK est supprimé. Le bouton reste et peut resservir (CA13, CA14) ;
  - `conflict` : `failed(signature)` (CA19) ;
  - `storage` : `failed(storage)` ;
  - `blocked` : `permissionDenied` ;
  - `invalid` ou `failed` : `failed(other)`.

  En cas de succès, le système tue le processus. Au lancement suivant, la purge de `ensureChecked()` supprime l'APK et
  la nouvelle vérification ne trouve plus rien : le bouton disparaît (étape 7, CA14).
- **Une seule session à la fois** : `showForkUpdateDialog` ne fait rien si une fenêtre est déjà ouverte (garde
  statique).
- **« Ignorer cette version »** appelle `UpdateService.skipVersion(version)` (public, même clé de préférence que
  l'upstream), puis ferme la fenêtre (CA24).

### 6. Traductions (D6) : `lib/fork/i18n/en.json` et `fr.json`

Nouvelles clés `fork.update.*` :
- `buttonLabel` : « Mise à jour disponible » ;
- `installedVersion(version)` : « Version installée : ${version} » ;
- `downloadAndInstall` : « Télécharger et installer » ;
- `progress(percent)` : « ${percent} % » ;
- `permissionExplanation`, `openSettings`, `permissionManual`, `permissionDenied` ;
- `installing` ;
- `downloadFailed`, `notEnoughSpace` ;
- `signatureConflict` (« Cette version est signée avec une autre clé que celle installée. Désinstallez Popkino puis
  installez-la : vos serveurs devront être ajoutés à nouveau. ») ;
- `installFailed`.

Les autres libellés réutilisent les clés upstream listées dans « Existant ». Le nom « Popkino » est écrit en dur dans
la branche `fork`, que `rebrand_rules.json` ignore (`skipTopLevel`). Ordre de travail : script, puis
`scripts/codegen.sh`, puis `clean_translations.py --check --strict`.

### 7. Ce dont j'ai besoin de la plateforme (interfaces)

**Canal** : `MethodChannel('com.plezy/fork_update')`. Le préfixe `com.plezy/` suit les canaux existants (D3) et
`fork_` le rend identifiable. Je m'aligne si la plateforme préfère un autre nom.

| Méthode | Arguments | Retour | Exigences |
|---|---|---|---|
| `getInstallCapability` | — | `{declared: bool, canRequestInstalls: bool, availableBytes: int?}` | `declared` : `REQUEST_INSTALL_PACKAGES` figure dans le manifeste **installé**. Le Dart n'affiche rien si elle est absente, même avec `ENABLE_UPDATE_CHECK` (défense en profondeur pour CA20). `canRequestInstalls` : `PackageManager.canRequestPackageInstalls()` en API 26 et plus, `true` en API 25. `availableBytes` : `StatFs` sur `cacheDir`. |
| `openInstallPermissionSettings` | — | `bool` | `ACTION_MANAGE_UNKNOWN_APP_SOURCES` avec `package:<applicationId>`. `false` si aucune activité ne répond. |
| `installApk` | `{path: String}` | `String` parmi `cancelled`, `conflict`, `storage`, `blocked`, `invalid`, `failed` | Refuser tout chemin hors de `cacheDir/popkino_update/`. Répondre **après** la décision de l'utilisateur dans l'installeur, pas au lancement de l'intent. `conflict` = signature incompatible (`STATUS_FAILURE_CONFLICT` ou `INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Le choix entre `PackageInstaller` et `ACTION_INSTALL_PACKAGE` avec FileProvider revient à la plateforme ; dans le second cas, il faut `cache-path path="popkino_update/"`. |

Autres attentes :
- **Store sans permission** : les versions store sont construites sans `ENABLE_UPDATE_CHECK` (D7) **et** sans
  `REQUEST_INSTALL_PACKAGES`. Le Dart n'appelle jamais le canal si `isSupported` est faux, et l'app ne demande donc
  jamais l'autorisation (CA20).
- **Format des releases CI** : `build.yml` doit publier les APK **bruts** nommés
  `popkino-android-<abi>-<X.Y.Z>.apk`, au lieu de `.tar.gz`. Les releases manuelles 0.1.0 et 0.2.0 ont déjà ce format.
  Il faut aussi que les releases soient publiées (pas en brouillon) au moment où on veut qu'elles soient proposées, et
  que `versionName` égale le tag. Le Dart accepte les tags `X.Y.Z` (D10) et `vX.Y.Z` (releases actuelles).
- **Version de départ** : `pubspec.yaml` est en `1.0.0+1`, plus grand que `0.2.0`. Un APK construit depuis `main`
  sans `--build-name` ne verrait jamais les releases 0.x. La première release qui contient le bouton doit être
  numérotée au-dessus de tout ce qui est installé.
- **CA12 et CA19** : même `applicationId` et même clé de signature d'une release à l'autre. Le Dart ne touche à
  aucune donnée.

## Alternatives écartées

1. **Modifier `UpdateService` en profondeur** (passer à `/releases`, ajouter les ABI et le téléchargement) :
   - le fichier est réécrit, avec des conflits sûrs à chaque fusion ;
   - la logique vise Android, mais le fichier sert aussi au repli Linux et à macOS via Homebrew : CA22 exige qu'ils ne
     changent pas ;
   - Plezy a refusé la fonction (#2868), elle ne reviendra pas par l'upstream.

   Rejeté au profit d'un crochet d'une ligne (D11).
2. **Ajouter le provider au `MultiProvider` et le lire avec `Consumer3` ou `context.watch<ForkUpdateController>()`
   non nullable** : les tests upstream de Découvrir, qui ne fournissent pas ce provider, lèveraient
   `ProviderNotFoundException`. Il faudrait les modifier, contre D4 (extension). La lecture nullable suffit.
3. **Ajouter l'action seulement quand une mise à jour existe** (`if (available != null) FocusableAction(...)`) :
   - la longueur de la liste change, donc `_rebindNodes` recrée les nœuds de Watch Together et des actions suivantes,
     qui n'ont pas de `debugLabel` ;
   - le focus est perdu si l'utilisateur est dans la barre quand la réponse arrive.

   L'emplacement fixe et invisible évite ce bug sans toucher les actions upstream.
4. **Envelopper la barre dans un `ListenableBuilder` sur le singleton** (sans provider) : cela réindente environ
   80 lignes upstream, un gros diff à chaque fusion, et s'écarte de la convention `provider`.
5. **Ajouter `onProgress` à `MediaServerHttpClient.downloadFile`** : c'est un fichier upstream central (failover,
   annulation). Un téléchargeur du fork de 120 lignes sur `platform.createPlatformClient()` et
   `http.AbortableRequest` (même schéma que `anime_mappings_store.dart`) ne touche rien d'upstream.
6. **Télécharger dans un isolate** : la mesure à faire sur la Fire TV Stick est le coût du SHA-256 par bloc de 64 Ko
   sur le thread principal. Si elle montre des saccades, on déplacera le hachage et l'écriture dans un `Isolate.run`.
   Pas avant.
7. **`package:flutter_markdown` pour les notes** : une nouvelle dépendance pour une fenêtre. Le texte simple suffit à
   CA6.
8. **Utiliser le délai de 6 h aussi pour le bouton** : avec le délai, deux lancements à moins de 6 h d'intervalle
   n'affichent plus le bouton. Contraire à CA1 et CA4.

## Impact

### Fichiers upstream modifiés (5, environ 10 lignes, toutes marquées `// FORK: bouton-mise-a-jour`)

| Fichier | Lignes |
|---|---|
| `lib/screens/discover_screen.dart` | 1 import + 1 action |
| `lib/services/update_service.dart` | 1 import + 2 (commentaire et crochet) |
| `lib/utils/update_dialog.dart` | 1 import + 2 |
| `lib/main.dart` | 1 import + 1 provider |
| `test/android/network_security_config_test.dart` | 1 chemin (optionnel) |

### Fichiers nouveaux
- `lib/fork/update/*.dart` (9 fichiers, voir 1) et `lib/fork/i18n/{en,fr}.json` (clés `fork.update.*`).
- Régénérés par script (D6) : `lib/i18n/*.i18n.json` et `strings_*.g.dart`.
- Tests dans `test/fork/update/` :
  - `release_picker_test.dart` : pré-version proposée ; brouillon ignoré ; plus grand numéro plutôt que plus récent ;
    `v0.2.0` et `1.0.0` ; tag invalide ignoré ; ABI dans l'ordre de préférence ; pas d'APK, donc `null` ; pas plus
    récent, donc `null` ; lecture du `digest` ; texte des notes. Couvre CA5, CA8, CA17.
  - `apk_downloader_test.dart` (`MockClient` en flux) : progression ; annulation qui ne laisse ni `.part` ni `.apk` ;
    coupure réseau ; inactivité ; empreinte différente ; ENOSPC donne `storage`. Couvre CA8, CA9, CA14, CA16, CA18.
  - `fork_update_controller_test.dart` : une seule requête pour deux `ensureChecked` ; échec silencieux ;
    `declared: false` donc rien ; version ignorée toujours disponible ; purge du dossier. Couvre CA1, CA4, CA15, CA20,
    CA24, CA25.
  - `fork_update_hooks_test.dart` (Android simulé) : `debugPerformUpdateCheck` appelle `/releases?per_page=20` ; au
    démarrage, la version ignorée est filtrée ; en manuel, elle ne l'est pas ; hors Android, l'upstream est intact
    (`/releases/latest`). Couvre CA21, CA22, CA23, CA24.
  - `fork_update_action_test.dart` (`FocusableActionBar` réel, mode clavier) :
    - sans mise à jour : largeur nulle et Droite passe de Watch Together à la télécommande (CA2) ;
    - quand la mise à jour apparaît, le focus déjà dans la barre n'est pas perdu ;
    - Gauche, Droite et Bas (CA3) ; étiquette au focus ; pastille ; appui (CA26).
  - `fork_update_dialog_test.dart` (canal simulé avec `TestDefaultBinaryMessenger`) : focus initial ; Haut/Bas font
    défiler ; Plus tard et Retour ferment ; trois boutons au démarrage ; progression puis Annuler ; autorisation
    accordée ou refusée à la reprise ; `cancelled`, `conflict`, `storage`. Couvre CA6, CA7, CA9, CA10, CA11, CA13,
    CA18, CA19, CA23.
  - `fork_update_hooks_guard_test.dart` : garde textuelle (D11) qui échoue si l'un des 4 crochets disparaît d'un
    fichier upstream après une fusion.
- **Tests upstream** : aucun `skip`, aucune modification. `update_service_test.dart` et `fork_identity_test.dart`
  tournent hors Android, donc le crochet H2 est inactif ; les tests de Découvrir n'ont pas de provider, donc
  l'emplacement reste vide.

### Dépendances ajoutées
Aucune : `http`, `crypto`, `device_info_plus`, `path_provider` et `provider` sont déjà présentes.

### Risques
- **Google Play** :
  - sans `ENABLE_UPDATE_CHECK`, aucun code de téléchargement n'est atteint ;
  - mais le code Dart est présent dans l'AAB. Le §3 de `regles-fork` interdit le téléchargement de code exécutable,
    pas le code mort. La vraie barrière est l'absence de `REQUEST_INSTALL_PACKAGES`, qui relève de la plateforme ;
  - `declared` rajoute une seconde barrière côté Dart ;
  - si la plateforme juge nécessaire d'exclure aussi le code Dart de l'AAB, une constante `const` en tête des crochets
    permet au compilateur d'éliminer le code de `lib/fork/update/`. À discuter dans le débat.
- **Marque** : uniquement `ForkIdentity.githubRepo` et `ForkIdentity.appSlug`, aucun service Plezy. Les textes
  disent « Popkino ».
- **Performances TV** :
  - aucune reconstruction de la barre pendant le téléchargement, et une progression limitée à 4 rafraîchissements par
    seconde ;
  - le SHA-256 en continu sur ARMv7 est à mesurer (environ 95 Mo). Plan B : `Isolate.run`.
- **Réseau au réveil de la TV** : si la requête échoue au lancement, le bouton n'apparaît qu'au lancement suivant
  (CA4 le permet). Aucune nouvelle tentative automatique.
- **Fusion upstream** :
  - environ 10 lignes marquées dans 5 fichiers ;
  - le risque principal est un remaniement de `_buildOverlaidAppBar` ou de `_performUpdateCheck`, détecté par la garde
    de crochets ;
  - `update_dialog.dart` est un petit fichier stable.
- **Pré-versions pour tous** : comme le dit la spec, toute pré-version publiée sera proposée à tous les utilisateurs.
  C'est un point de process de release, pas du code.
- **Repli Linux** : il garde `/releases/latest` (CA22), donc ne voit pas les pré-versions. C'est voulu.

## Proposition de décision durable (pour `decisions.md`)

**D13 — Provider et code d'une fonctionnalité du fork** : une fonctionnalité du fork de plus de 2 fichiers vit dans
`lib/fork/<slug>/`.
- Son état global est un `ChangeNotifier` exposé par `ChangeNotifierProvider.value` dans le `MultiProvider` de
  `lib/main.dart` (une ligne `// FORK:`).
- Il est lu dans les fichiers upstream par `context.watch<T?>()` ou `context.read<T?>()`, en type nullable. Les tests
  upstream qui ne le fournissent pas restent ainsi verts sans modification.

## Proposition d'ajouts au skill `conventions-code`

- **TV, section « TV »** : dans un `FocusableActionBar`, une action affichée sous condition garde un **emplacement
  fixe**, avec `debugLabel`, `onPressed: null` et `child: SizedBox.shrink()` quand elle est masquée. Changer la
  longueur de `actions` recrée les nœuds des actions sans `debugLabel` (`_rebindNodes`) et fait perdre le focus.
- **État** : pour lire un provider qui peut être absent (provider du fork, tests upstream), utiliser
  `context.watch<T?>()` ou `read<T?>()`. Avec `provider` 6, la lecture renvoie `null` au lieu de lever une exception.
- **GitHub** : `/releases/latest` ignore les pré-versions et renvoie 404 s'il n'y a que des pré-versions. Pour les
  inclure, lister `/releases` ; le champ `digest` (`sha256:…`) de chaque fichier dispense de `SHA256SUMS.txt`.

## QUESTIONS PRODUIT

1. **CA17, cas limite** : la version la plus récente n'a pas d'APK pour l'appareil, mais une version intermédiaire,
   plus récente que celle installée, en a un. Je propose de **ne rien proposer**, comme le dit la spec à la lettre.
   L'autre choix serait de proposer la version intermédiaire. Lequel préférez-vous ?
2. **Notes de version** : elles seront affichées en **texte simple** (gras retiré, liens réduits à leur texte, puces
   conservées), sans rendu Markdown. Cela vous convient-il ?
3. **CA11, « Réessayer »** : je propose qu'il **rouvre directement l'écran d'autorisation** plutôt que de revenir à la
   phrase d'explication. À confirmer.
