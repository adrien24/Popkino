# Plan technique — bouton-mise-a-jour

Spec : docs/produit/specs/bouton-mise-a-jour.md
Statut : approuvé       Pilote : architecte-app
Sources : `proposition-app.md`, `proposition-plateforme.md`, `debat.md` (tour 1, aucun bloquant restant).

## Décisions

1. **Une seule bascule, `ENABLE_UPDATE_CHECK=true`**. Elle active le Dart, et Gradle la lit aussi dans
   `-Pdart-defines` pour ajouter `src/sideload/` (permission `REQUEST_INSTALL_PACKAGES` et Kotlin). Un flavor serait une
   seconde bascule désynchronisable. Un `bundle*` ou un build `AMAZON` avec ce define échoue (CA20). Amende D7.
2. **Code d'installation absent des versions store, côté Kotlin comme côté Dart** :
   - Kotlin : `nosideload/ForkPlugins.kt` est vide, donc le plugin n'existe pas dans ces builds ;
   - Dart : la constante `kForkSideloadUpdates` est testée en tête de chaque point d'entrée, et l'AOT élimine
     `lib/fork/update/`. C'est la politique Play « Device and Network Abuse ».
3. **Canal `popkino/sideload_updater`**, 5 méthodes, wrapper Dart `SideloadInstaller`. Les écrans de réglage ouverts
   et l'inspection séparée de l'installation permettent CA10 (phrase adaptée) et CA19 (message avant l'écran système).
4. **Vérification** : taille exacte, puis `inspectApk` (paquet, puis signataires, puis versionCode), puis l'installeur
   du système. Pas de SHA-256 en Dart : le contrôle du signataire est plus fort, et le hachage de 94 Mo sur le thread
   d'interface de la Fire Stick faisait saccader.
5. **Reprise par `pending.json`** : Android 11 (Fire OS 8) tue l'app au premier octroi de l'autorisation. Une fiche
   écrite après l'inspection permet de rouvrir la fenêtre en `readyToInstall`, sans retélécharger (CA10).
6. **4 crochets d'une ligne marqués `// FORK: bouton-mise-a-jour`, avec « null = upstream » (D11)**, dans
   `discover_screen.dart`, `update_service.dart`, `update_dialog.dart` et `main.dart`. Tout le reste vit dans
   `lib/fork/update/`. Plezy a refusé la fonction (#2868), elle ne reviendra pas par les fusions.
7. **Le bouton a un emplacement fixe dans `FocusableActionBar`** (`debugLabel: 'fork_update'`, vide et sans focus sans
   mise à jour). Changer la longueur de `actions` recréerait les nœuds de Watch Together et des suivants (`_rebindNodes`),
   et ferait perdre le focus (CA2, CA3).
8. **État** : un provider global `ForkUpdateController`, exposé par `.value` et lu par `context.watch<T?>()`. Les tests
   upstream sans ce provider restent verts. La progression vit dans une `ForkUpdateSession` par fenêtre, pour ne pas
   reconstruire la barre d'accueil pendant le téléchargement.
9. **Une vérification réseau par lancement, sans délai de 6 h**, pour le bouton (CA1, CA4, CA25). Le délai de 6 h et
   « Ignorer cette version » ne valent que pour la fenêtre automatique (CA23, CA24).
10. **Releases** :
    - liste `/releases?per_page=20`, pour inclure les pré-versions (`/releases/latest` répond 404 aujourd'hui) ;
    - la plus grande version gagne, brouillons écartés ;
    - assets `popkino-android-<abi>-<X.Y.Z>.apk` (le motif accepte aussi l'absence de version) ;
    - ABI dans l'ordre de `supportedAbis`, avec une tranche de versionCode au moins égale à celle de l'APK installé ;
    - rien d'intermédiaire (CA17) ;
    - `build.yml` publie des APK nus.
11. **Fichiers** : tout dans `getTemporaryDirectory()/updates/` (`.part`, `.apk`, `pending.json`), purgé au démarrage
    et à la fermeture de la fenêtre (CA9, CA14). Le natif refuse tout autre chemin.
12. **Espace** : le téléchargement est refusé si `availableBytes < 2 × size + 100 Mo`, car l'installeur recopie l'APK
    sur la même partition (CA18).
13. **Notes de version en texte simple** (CA6, précision du PO), sans dépendance Markdown.

## Contrat Dart ↔ natif (référence pour T2 et T6)

Canal `MethodChannel('popkino/sideload_updater')`, enregistré seulement dans les builds sideload. Ailleurs, l'appel
lève `MissingPluginException`.

| Méthode | Arguments | Retour |
|---|---|---|
| `canRequestInstalls` | — | `bool` (API ≥ 26 : `canRequestPackageInstalls()` ; API 25 : `INSTALL_NON_MARKET_APPS == 1`) |
| `openInstallSettings` | — | `String` : `appPermission` \| `unknownAppsList` \| `developerOptions` \| `security` \| `settings` \| `none` (essais dans cet ordre, retour immédiat) |
| `availableBytes` | — | `int` (`StatFs(cacheDir).availableBytes`) |
| `inspectApk` | `{path}` | `{status: ok\|invalid\|wrongPackage\|signatureMismatch\|notNewer, versionName?, versionCode?}` (lecture sur `Dispatchers.IO`) |
| `install` | `{path}` | `String` : `cancelled` \| `permissionRequired` \| `signatureMismatch` \| `notNewer` \| `insufficientStorage` \| `invalid` \| `invalidPath` \| `installerUnavailable` \| `busy` \| `failed:<code>` \| `installed`. Pas de réponse en cas de succès, car le processus est tué. |

Règles pour `install` :
- le chemin canonique doit être dans `cacheDir/updates/` et finir par `.apk` ;
- le natif refait `inspectApk` avant de lancer l'installeur ;
- l'installeur est lancé avec `ACTION_INSTALL_PACKAGE`, le FileProvider existant (`${applicationId}.fileprovider`,
  `cache-path` inchangé), `EXTRA_RETURN_RESULT` et `startActivityForResult` avec un code dédié (différent de 7461) ;
- correspondance des résultats : `RESULT_CANCELED` → `cancelled` ; `INSTALL_RESULT` `-7` → `signatureMismatch`,
  `-25` → `notNewer`, `-4` → `insufficientStorage`.

## Tâches

### T1 — Bascule Gradle, manifeste sideload, enregistrement des plugins du fork
- Complexité : L
- Dépend de : —
- Fichiers :
  - modifier `android/app/build.gradle.kts` (un bloc ajouté **en fin de fichier**) ;
  - modifier `android/app/src/main/kotlin/com/edde746/plezy/PlezyActivity.kt` (une ligne) ;
  - modifier `.github/workflows/ci.yml` (une ligne) ;
  - créer `android/app/src/sideload/AndroidManifest.xml` ;
  - créer `android/app/src/sideload/kotlin/com/edde746/plezy/fork/ForkPlugins.kt` ;
  - créer `android/app/src/nosideload/kotlin/com/edde746/plezy/fork/ForkPlugins.kt`.
- À faire :
  - **Gradle** : ajouter en fin de `build.gradle.kts` le bloc `// FORK: bouton-mise-a-jour` de
    `proposition-plateforme.md` § 1 :
    - `popkinoSideload` est vrai si les `dart-defines` décodés (Base64) contiennent `ENABLE_UPDATE_CHECK=true`, ou si
      `-PpopkinoSideload=true` est passé ;
    - le build échoue (`GradleException`) si `popkinoSideload` est vrai et que `AMAZON` est défini, ou qu'une tâche
      demandée contient `bundle` ;
    - `sourceSets.main.java.srcDir("src/sideload/kotlin")` ou `"src/nosideload/kotlin"` ;
    - en sideload, `test.java.srcDir("src/sideloadTest/kotlin")` et
      `androidComponents.onVariants { variant.sources.manifests.addStaticManifestFile("src/sideload/AndroidManifest.xml") }`.
  - **Manifeste** : `src/sideload/AndroidManifest.xml` ne contient que
    `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>`.
  - **`ForkPlugins`** : `object ForkPlugins { fun register(engine: FlutterEngine) }`, avec la même signature dans les
    deux dossiers. Version sideload : `engine.plugins.add(SideloadUpdaterPlugin())` (classe créée en T2 ; d'ici là,
    un plugin minimal qui répond `notImplemented` peut être livré dans le même fichier pour que T1 compile seul).
    Version nosideload : vide.
  - **`PlezyActivity.configureFlutterEngine`** : après les `plugins.add` existants, ajouter
    `ForkPlugins.register(flutterEngine) // FORK: plugins natifs du fork (bouton-mise-a-jour)`.
  - **`ci.yml`** : ajouter `-PpopkinoSideload=true` à la commande `./gradlew :app:testDebugUnitTest …` (l.229) avec
    un commentaire `# FORK: bouton-mise-a-jour`. `lintDebug` reste sans ce paramètre, ce qui compile la variante
    nosideload.
  - Si `java.srcDir` n'est pas pris en compte par le plugin Kotlin 2.4, utiliser `kotlin.srcDir` (repli prévu par la
    plateforme).
- Tests :
  - `./gradlew :app:testDebugUnitTest -PpopkinoSideload=true` et `./gradlew :app:lintDebug` passent ;
  - vérifications d'artefact de la section « Vérification globale », points 2 et 3 (permission présente ou absente,
    échec de `flutter build appbundle` avec le define).
- Critères d'acceptation couverts : CA20 (partie native).

### T2 — Plugin Kotlin `SideloadUpdaterPlugin`
- Complexité : L
- Dépend de : T1
- Fichiers :
  - créer, dans `android/app/src/sideload/kotlin/com/edde746/plezy/fork/sideload/`, `SideloadUpdaterPlugin.kt`,
    `ApkInspector.kt`, `InstallPermission.kt`, `InstallResults.kt` et `UpdatesPath.kt` ;
  - créer `android/app/src/sideloadTest/kotlin/com/edde746/plezy/fork/sideload/*Test.kt` ;
  - modifier `android/app/src/sideload/kotlin/com/edde746/plezy/fork/ForkPlugins.kt` (retirer le plugin minimal
    éventuel).
- À faire :
  - **Plugin** : `FlutterPlugin` + `ActivityAware` + `PluginRegistry.ActivityResultListener`, sur le canal et le
    contrat ci-dessus. Le travail lourd tourne dans un scope de coroutines sur `Dispatchers.IO`, annulé à
    `onDetachedFromEngine`.
  - **`ApkInspector`** :
    - lecture par `PackageManager.getPackageArchiveInfo` ;
    - signataires : API ≥ 28 avec `GET_SIGNING_CERTIFICATES` (repli `GET_SIGNATURES` si `signingInfo` est nul),
      API 25-27 avec `GET_SIGNATURES` ;
    - la décision est une **fonction pure**, dans l'ordre : `invalid`, puis `wrongPackage`, puis `signatureMismatch`
      (toutes les empreintes SHA-256 de l'app installée doivent figurer dans les signataires de l'APK ou dans
      l'historique de rotation), puis `notNewer` (`longVersionCode` ≤ installé), puis `ok`.
  - **`InstallPermission`** :
    - `canRequestInstalls` selon l'API ;
    - `openInstallSettings` essaie, dans l'ordre : `ACTION_MANAGE_UNKNOWN_APP_SOURCES` avec `package:<pkg>`, le même
      sans data, `ACTION_APPLICATION_DEVELOPMENT_SETTINGS`, `ACTION_SECURITY_SETTINGS`, `ACTION_SETTINGS`. Il capture
      `ActivityNotFoundException` et renvoie la cible qui a démarré. Pas de `<queries>`.
  - **`UpdatesPath`** : chemin canonique dans `cacheDir/updates/`, extension `.apk` ; refuse `..` et les liens qui
    sortent du dossier.
  - **`install`** :
    - chemin invalide → `invalidPath` ;
    - nouvelle inspection, puis renvoi de son statut si ce n'est pas `ok` ;
    - sans autorisation → `permissionRequired` ;
    - un second appel pendant un premier → `busy` ;
    - sinon, intent décrit dans le contrat. L'appel en attente reçoit une erreur si l'activité se détache.
- Tests (JUnit et Robolectric 4.16, `src/sideloadTest/`) :
  - `ApkDecisionTest` : ordre des statuts, empreintes de rotation acceptées ;
  - `UpdatesPathTest` ;
  - `InstallResultsTest` : `RESULT_CANCELED`, `-7`, `-25`, `-4`, un autre code, `RESULT_OK` ;
  - `InstallPermissionTest` (`@Config(sdk = [25, 30])`) : valeur selon l'API, ordre des intents essayés et replis ;
  - `SideloadUpdaterPluginTest` : méthode inconnue → `notImplemented`, `busy`, détachement.
  - Lancer `scripts/format_native.sh --fix`.
- Critères d'acceptation couverts : CA10, CA11, CA12, CA13, CA18 (code -4), CA19 et CA20 (côté natif).

### T3 — Garde statique d'isolation sideload
- Complexité : M
- Dépend de : T2
- Fichiers : créer `scripts/fork/test_sideload_isolation.py`.
- À faire : un test en Python 3 standard (D8), ramassé par le glob `scripts/*/test_*.py` de `ci_guard_checks.sh`. Il
  échoue si l'une de ces conditions n'est plus vraie :
  - `REQUEST_INSTALL_PACKAGES` n'apparaît dans aucun `AndroidManifest.xml` hors de `android/app/src/sideload/` ;
  - `ACTION_INSTALL_PACKAGE`, `PackageInstaller`, `MANAGE_UNKNOWN_APP_SOURCES` et `canRequestPackageInstalls`
    n'apparaissent pas hors de `android/app/src/sideload*/` ;
  - le bloc `FORK: bouton-mise-a-jour` est présent dans `build.gradle.kts` ;
  - `ForkPlugins.register(flutterEngine)` est présent dans `PlezyActivity.kt` ;
  - les deux `ForkPlugins.kt` déclarent `fun register(engine: FlutterEngine)`.
- Tests : `bash scripts/ci_guard_checks.sh`. Vérifier aussi que la garde échoue quand on ajoute temporairement la
  permission au manifeste principal.
- Critères d'acceptation couverts : CA20.

### T4 — Releases : APK nus, README, procédure
- Complexité : L (publication et CI, même si les modifications sont mécaniques)
- Dépend de : —
- Fichiers :
  - modifier `.github/workflows/build.yml` (lignes déjà marquées `# FORK:`) ;
  - modifier `README.md` ;
  - modifier `docs/technique/release.md`.
- À faire :
  - **`build.yml`, étape « Package APKs »** :
    - lire la version avec
      `VERSION=$(grep '^version:' pubspec.yaml | sed -E 's/^version: *([0-9.]+).*/\1/')` ;
    - remplacer les trois `tar -czf` par
      `cp build/app/outputs/flutter-apk/app-<abi>-release.apk popkino-android-<abi>-$VERSION.apk`, pour arm64-v8a,
      armeabi-v7a et x86_64 ;
    - remplacer `.tar.gz` par le motif `popkino-android-*.apk` dans « Attest APKs », « Upload APKs » et « Collect
      release files ». Pour cette dernière, écrire le motif littéral
      `echo 'artifacts/android-apk/popkino-android-*.apk'`, comme pour Linux (`'artifacts/linux-x64/*'`).
      `softprops/action-gh-release` développe lui-même le motif.
  - **`README.md`** : les trois lignes Android pointent vers `https://github.com/adrien24/popkino/releases`, car
    `releases/latest/download` ignore les pré-versions. Indiquer quel fichier choisir (arm64-v8a : TV et téléphones
    récents ; armeabi-v7a : Fire TV Stick et TV d'entrée de gamme ; x86_64). Ajouter une section de dépannage avec
    `adb shell appops set io.github.adrien24.popkino REQUEST_INSTALL_PACKAGES allow`, pour le cas où Popkino
    n'apparaît pas dans la liste « Installer des applis inconnues » de Fire OS.
  - **`release.md`** :
    - ajouter la procédure « release Android seule » : build local signé avec la clé définitive et
      `--dart-define=ENABLE_UPDATE_CHECK=true`, renommage en `popkino-android-<abi>-<X.Y.Z>.apk`,
      `apksigner verify --print-certs` (empreinte de la clé définitive), `aapt2 dump permissions` (doit lister
      `REQUEST_INSTALL_PACKAGES`), puis `gh release create X.Y.Z --prerelease` ;
    - rappeler les règles : tag sans `v` (D10) ; N ne redescend jamais sous le plus grand N publié et reste inférieur
      à 1000 (D10 amendé) ; seule une release **publiée** est proposée ; toute pré-version est proposée à tous les
      utilisateurs ;
    - noter que la 0.2.0, signée avec la clé de debug, exigera une réinstallation unique (CA19).
- Tests : `bash scripts/ci_guard_checks.sh` (dont `check_identity.py`). Relire le YAML (`actionlint` s'il est
  disponible).
- Critères d'acceptation couverts : CA8 et CA17 (format des assets), CA20 (procédure).

### T5 — Drapeau, modèles et sélecteur de release (Dart pur)
- Complexité : M
- Dépend de : —
- Fichiers :
  - créer `lib/fork/update/sideload_flags.dart`, `lib/fork/update/fork_release.dart`, `lib/fork/update/apk_asset.dart`
    et `lib/fork/update/release_picker.dart` ;
  - créer `test/fork/update/release_picker_test.dart` et `test/fork/update/apk_asset_test.dart`.
- À faire :
  - **`sideload_flags.dart`** : `const bool kForkSideloadUpdates = bool.fromEnvironment('ENABLE_UPDATE_CHECK');`, et
    `abstract final class ForkSideload` avec :
    - `@visibleForTesting static bool debugForceSupported = false;` ;
    - `static bool get isSupported => (kForkSideloadUpdates || (kDebugMode && debugForceSupported)) && Platform.isAndroid;`,
      la plateforme Android étant elle aussi forçable en test par `@visibleForTesting static bool? debugIsAndroid` ;
    - un commentaire qui explique que l'AOT élimine le code de mise à jour quand le define est absent.
  - **`fork_release.dart`** : classes immuables, sans freezed :
    - `ForkRelease { version, tag, name, notes (déjà en texte), htmlUrl, publishedAt, isPrerelease, apk }` ;
    - `ForkApkAsset { name, url (browser_download_url), size, abi }`.
  - **`apk_asset.dart`** :
    - `ForkApkAsset? selectApkAsset(List<Map> assets, {required List<String> supportedAbis, required int installedTranche})` ;
    - motif `^${ForkIdentity.appSlug}-android-(arm64-v8a|armeabi-v7a|x86_64)(-\d+\.\d+\.\d+)?\.apk$` ;
    - tranches : armeabi-v7a 1, arm64-v8a 2, x86_64 4 ;
    - on parcourt `supportedAbis` dans l'ordre et on prend le premier asset dont la tranche est ≥ `installedTranche` ;
    - `int currentAbiTranche()` lit `Abi.current()` de `dart:ffi` (`androidArm` → 1, `androidArm64` → 2,
      `androidX64` → 4, sinon 0).
  - **`release_picker.dart`** :
    - `int compareForkVersions(String a, String b)` : comparaison numérique champ par champ, en ignorant `+N` et un `v`
      initial ;
    - `ForkRelease? pickForkRelease(List<Object?> json, {required String installedVersion, required List<String> supportedAbis, required int installedTranche})` :
      on écarte `draft == true` et les tags qui ne correspondent pas à `^v?\d+\.\d+\.\d+$` ; on garde les
      pré-versions ; on prend le **plus grand numéro** ; on renvoie `null` s'il n'est pas plus récent que la version
      installée, ou si `selectApkAsset` renvoie `null`. On ne redescend jamais vers une release intermédiaire (CA17) ;
    - `String releaseNotesToPlainText(String md)` : retire `**`, `__`, `` ` `` et les `#` de titre, transforme
      `[texte](url)` en `texte` et les puces `-` ou `*` en `• `, réduit les lignes vides multiples.
- Tests :
  - pré-version proposée ; brouillon ignoré ; plus grand numéro plutôt que plus récent par date ; `v0.2.0` comme
    `1.0.0` ; tag invalide ignoré ; pas plus récent → `null` ; la plus récente sans APK pour l'ABI → `null`, même si
    une intermédiaire en a un ;
  - Fire Stick `[armeabi-v7a, armeabi]` → v7a ; téléphone `[arm64-v8a, armeabi-v7a]` avec la tranche 2 → arm64 ;
    tranche 2 sans asset arm64 → `null` ; nom avec et sans version ; `.tar.gz` ignoré ;
  - texte des notes.
- Critères d'acceptation couverts : CA5, CA6 (texte), CA8, CA17.

### T6 — Wrapper `SideloadInstaller` et faux pour les tests
- Complexité : M
- Dépend de : —
- Fichiers : créer `lib/fork/update/sideload_installer.dart` et `test/fork/update/fake_sideload_installer.dart`,
  `test/fork/update/sideload_installer_test.dart`.
- À faire :
  - les enums `ApkCheck`, `InstallOutcome` (`installed`, `cancelled`, `permissionRequired`, `signatureMismatch`,
    `notNewer`, `insufficientStorage`, `invalid`, `unavailable`, `failed`) et `InstallSettingsTarget` ;
  - `abstract interface class SideloadInstaller` (`canRequestInstalls`, `openInstallSettings`, `availableBytes`,
    `inspectApk` → `({ApkCheck status, String? versionName, int? versionCode})`, `install`), avec
    `static const updatesDirName = 'updates'` ;
  - l'implémentation `MethodChannelSideloadInstaller` sur `MethodChannel('popkino/sideload_updater')` :
    - correspondance de chaque chaîne du contrat ; `invalidPath`, `installerUnavailable`, `busy` et `failed:<code>`
      donnent `failed`, avec le code journalisé par `appLogger.w` ;
    - `MissingPluginException` donne `unavailable` (ou `null` / `false` selon la méthode) ;
  - le faux est programmable : réponses en file d'attente, et enregistrement des appels.
- Tests : canal simulé par `TestDefaultBinaryMessengerBinding` ; chaque chaîne de retour ; `MissingPluginException`.
- Critères d'acceptation couverts : CA10, CA11, CA13, CA18, CA19 (côté Dart).

### T7 — Dossier de mise à jour : `pending.json`, purge, téléchargeur
- Complexité : M
- Dépend de : T5
- Fichiers : créer `lib/fork/update/update_files.dart`, `lib/fork/update/apk_downloader.dart`,
  `test/fork/update/update_files_test.dart` et `test/fork/update/apk_downloader_test.dart`.
- À faire :
  - **`ForkUpdateFiles`** (racine injectable, `getTemporaryDirectory()/updates` par défaut) :
    - `apkFile(release)` donne `popkino-<version>-<abi>.apk`, et `partFile` le même avec `.part` ;
    - `writePending({version, abi, versionCode, size, fileName})` ajoute `createdAt` (UTC ISO) et écrit
      `pending.json` de façon atomique (fichier temporaire, puis `rename`) ;
    - `readPending()` ;
    - `purge({required String installedVersion, DateTime? now})` supprime tous les `.part`, tous les `.apk` sans fiche
      valide, et la fiche avec son APK si la version est ≤ à l'installée, si la taille du fichier diffère de `size`, ou
      si `createdAt` date de plus de 24 h. Elle renvoie la fiche restante, ou `null` ;
    - `deleteAll()`.
  - **`ForkApkDownloader.download(asset, partFile, apkFile, {required void Function(int received, int total) onProgress, required Future<void> abortTrigger})`** :
    - client `platform.createPlatformClient()` (même import conditionnel que `anime_mappings_store.dart`) et
      `http.AbortableRequest` ;
    - écriture en flux dans le `.part`, jamais l'APK entier en mémoire ;
    - délai d'inactivité : 30 s sans octet reçu ;
    - total : `asset.size` ; si `Content-Length` existe et diffère, c'est une erreur réseau ;
    - progression signalée au plus toutes les 250 ms ou tous les 1 % ;
    - à la fin, la taille doit être **exactement** `asset.size`, sinon c'est une erreur réseau ; on renomme ensuite le
      `.part` en `.apk` ;
    - tout échec ou toute annulation supprime le `.part` ;
    - erreurs typées `ForkDownloadFailure { network, storage, cancelled }` : `storage` pour une
      `FileSystemException` dont `osError?.errorCode == 28` (ENOSPC) ; le client est fermé à la fin.
- Tests (`MockClient.streaming`, dossier temporaire) :
  - **downloader** : progression croissante et limitée ; annulation qui ne laisse ni `.part` ni `.apk` ; coupure au
    milieu ; inactivité (`fakeAsync`) ; taille incorrecte ; ENOSPC simulé par un puits d'écriture injectable ;
  - **purge** : chaque règle, et une fiche corrompue traitée comme absente.
- Critères d'acceptation couverts : CA8 (progression), CA9, CA14, CA16, CA18.

### T8 — Traductions `fork.update.*`
- Complexité : S
- Dépend de : —
- Fichiers :
  - modifier `lib/fork/i18n/en.json` et `lib/fork/i18n/fr.json` ;
  - régénérer `lib/i18n/*.i18n.json` et `lib/i18n/strings*.g.dart` par script.
- À faire : ajouter sous `fork.update` les clés suivantes (textes français ; l'anglais est traduit dans le même
  esprit) :

  | Clé | Texte français |
  |---|---|
  | `buttonLabel` | « Mise à jour disponible » |
  | `installedVersion(version)` | « Version installée : ${version} » |
  | `downloadAndInstall` | « Télécharger et installer » |
  | `install` | « Installer » |
  | `readyToInstall(version)` | « Version ${version} prête à installer » |
  | `progress(percent)` | « ${percent} % » |
  | `verifying` | « Vérification… » |
  | `permissionExplanation` | « Pour installer la mise à jour, autorisez Popkino à installer des applications. » |
  | `openSettings` | « Ouvrir les réglages » |
  | `permissionPathUnknownApps` | « Choisissez Popkino dans la liste, puis activez l'autorisation. » |
  | `permissionPathDeveloper` | « Options pour les développeurs > Installer des applis inconnues > Popkino » |
  | `permissionPathGeneric` | « Paramètres > Ma Fire TV > Options pour les développeurs > Installer des applis inconnues > Popkino (ou Paramètres > Sécurité > Sources inconnues) » |
  | `permissionDenied` | « Installation impossible sans autorisation. » |
  | `installing` | « Suivez les instructions à l'écran pour installer la mise à jour. » |
  | `downloadFailed` | « Le téléchargement a échoué. Vérifiez la connexion. » |
  | `notEnoughSpace` | « Espace insuffisant pour télécharger la mise à jour. » |
  | `signatureConflict` | « Cette version est signée avec une autre clé que celle installée. Désinstallez Popkino puis installez-la : vos serveurs devront être ajoutés à nouveau. » |
  | `installFailed` | « L'installation a échoué. » |

  Ensuite : `python3 scripts/fork/rebrand_i18n.py`, `scripts/codegen.sh`, puis
  `clean_translations.py --check --strict` (D6).
- Tests : `test/fork/i18n_branding_test.dart` passe, et `scripts/codegen.sh --check`.
- Critères d'acceptation couverts : textes de CA6 à CA19.

### T9 — `ForkUpdateController` et provider global
- Complexité : M
- Dépend de : T5, T6, T7
- Fichiers :
  - créer `lib/fork/update/fork_update_controller.dart` et `test/fork/update/fork_update_controller_test.dart` ;
  - modifier `lib/main.dart` (import et une ligne).
- À faire :
  - **`ForkUpdateController extends ChangeNotifier`** :
    - `static final instance` ;
    - constructeur avec des dépendances injectables : `MediaServerHttpClient`, `SideloadInstaller`, `ForkUpdateFiles`,
      fournisseur d'ABI (`DeviceInfoPlugin().androidInfo.supportedAbis`), tranche (`currentAbiTranche`), version
      installée (`AppVersion.current()`).
  - **État** : `ForkRelease? available` ; `ForkPendingInstall? pendingInstall` (fiche et release minimale
    reconstruite : version et chemin) ; `bool resumeConsumed`.
  - **`Future<void> ensureChecked()`** : une seule exécution par processus, et les appels simultanés partagent le même
    `Future`. Il ne lève jamais d'exception (CA15 : `appLogger.w`). Étapes :
    1. si `!ForkSideload.isSupported`, ne rien faire ;
    2. `files.purge(installedVersion)` ; une fiche restante devient `pendingInstall` et l'on notifie, sans attendre le
       réseau ;
    3. `installer.canRequestInstalls()` ; `MissingPluginException` (donc `unavailable`) signifie qu'il ne faut plus
       rien faire ;
    4. `_fetch()`.
  - **`_fetch()`** :
    - `GET https://api.github.com/repos/${ForkIdentity.githubRepo}/releases?per_page=20`, avec l'en-tête
      `Accept: application/vnd.github+json` et un délai de 10 s ;
    - `pickForkRelease`, sauf pour les tags présents dans `_refusedTags` ;
    - notification seulement si `available` change.
  - **`Future<ForkRelease?> refresh({bool throwOnFailure = false})`** : vérification manuelle, toujours une nouvelle
    requête. Il lève une exception en cas d'échec si `throwOnFailure` est vrai.
  - **`markRefused(String tag)`** (après `notNewer`) : retire la release et masque le bouton jusqu'au prochain
    lancement.
  - **`clearPending()`**.
  - **Ce que le contrôleur ne fait pas** : il ne filtre jamais la version ignorée (CA24) et n'applique pas le délai de
    6 h (CA1, CA4, CA25).
  - **`lib/main.dart`** : dans la liste littérale `providers: [...]` du `MultiProvider` racine (l.1746), ajouter
    l'import marqué `// FORK:` et un collection-if :
    `if (kForkSideloadUpdates) ChangeNotifierProvider<ForkUpdateController>.value(value: ForkUpdateController.instance), // FORK: bouton-mise-a-jour — update availability, app-global`.
    Sans le define, l'AOT élimine `instance` et ses dépendances par défaut (canal, fichiers, client HTTP), et
    `context.watch<ForkUpdateController?>()` renvoie `null`. **Ne jamais référencer `ForkUpdateController.instance`
    hors d'un test de `kForkSideloadUpdates` ou de `ForkSideload.isSupported`** (debat.md, validation tour 1).
- Tests :
  - deux `ensureChecked` donnent une seule requête ;
  - échec réseau, HTTP 500 et JSON invalide donnent `available == null`, sans exception ;
  - `unavailable` : aucune requête ;
  - une version ignorée reste dans `available` ;
  - fiche valide : `pendingInstall` est exposé avant la réponse réseau ;
  - `markRefused` ;
  - `isSupported` faux : rien n'est appelé (faux installeur sans appel) ;
  - URL appelée = `/repos/adrien24/popkino/releases?per_page=20` (constante `ForkIdentity.githubRepo`).
- Critères d'acceptation couverts : CA1, CA4, CA5, CA15, CA17, CA20, CA24, CA25.

### T10 — Crochet de vérification dans `UpdateService`
- Complexité : M
- Dépend de : T9
- Fichiers :
  - créer `lib/fork/update/fork_update_hooks.dart`, `test/fork/update/fork_update_hooks_test.dart` et
    `test/fork/update/fork_update_hooks_guard_test.dart` ;
  - modifier `lib/services/update_service.dart` et `test/android/network_security_config_test.dart`.
- À faire :
  - **`ForkUpdateHooks.performCheck(String currentVersion, {required bool startup})`**, qui renvoie
    `Future<Map<String, dynamic>?>?` :
    - première ligne : `if (!ForkSideload.isSupported) return null;` ;
    - au démarrage : `await controller.ensureChecked()`, puis `null` si `available == null` ou si sa version est
      égale à `await UpdateService.getSkippedVersion()` ;
    - en manuel : `await controller.refresh(throwOnFailure: true)`, sans filtre de version ignorée (CA21) ;
    - la map renvoyée contient `hasUpdate: true`, `currentVersion`, `latestVersion`, `releaseUrl` (htmlUrl),
      `releaseName`, `releaseNotes`, `publishedAt` et `forkRelease` (l'objet `ForkRelease`).
  - **`update_service.dart`** :
    - import marqué ;
    - dans `_performUpdateCheck`, juste après `if (respectCooldown) { await _updateLastCheckTime(); }` et avant le
      `get`, insérer :

      ```dart
      // FORK: bouton-mise-a-jour — pre-releases and per-ABI APK on Android (null = upstream)
      if (ForkUpdateHooks.performCheck(currentVersion, startup: respectCooldown) case final fork?) return await fork;
      ```
  - **`network_security_config_test.dart`** : ajouter `'lib/fork/update/fork_update_controller.dart', // FORK: URL de l'API des releases`
    à `_fixedEndpointSourcePaths`.
  - **Garde de crochets** (D11) : un test textuel qui vérifie la présence de l'appel `ForkUpdateHooks.performCheck(`
    dans `update_service.dart`. T13 y ajoutera les autres crochets. Il vérifie aussi que `performCheck` commence par
    `if (!ForkSideload.isSupported) return null;`.
- Tests :
  - avec `ForkSideload.debugForceSupported` et `debugIsAndroid = true`, plus `debugPerformUpdateCheck` et
    `MockClient`, on vérifie :
    - l'URL `/releases?per_page=20` ;
    - au démarrage, une version ignorée donne `null` ;
    - en manuel, la même version est renvoyée ;
    - un échec en manuel lève une exception ;
  - sans forçage, `test/services/update_service_test.dart` et `test/fork/fork_identity_test.dart` (`/releases/latest`)
    restent verts sans modification.
- Critères d'acceptation couverts : CA21, CA22, CA23 (déclenchement), CA24.

### T11 — `ForkUpdateSession` : machine à états du parcours
- Complexité : L (asynchrone, annulation, cycle de vie de l'app, redémarrage à froid)
- Dépend de : T6, T7, T9
- Fichiers : créer `lib/fork/update/fork_update_session.dart` et `test/fork/update/fork_update_session_test.dart`.
- À faire :
  - **`ForkUpdateSession extends ChangeNotifier`** : elle reçoit `ForkRelease` ou `ForkPendingInstall`, le
    contrôleur, `SideloadInstaller`, `ForkUpdateFiles` et `ForkApkDownloader`.
  - **Phases** : classe scellée `ForkUpdatePhase` :
    - `details`, `downloading(double fraction)`, `verifying` ;
    - `needsPermission(InstallSettingsTarget? lastTarget)`, `permissionDenied(InstallSettingsTarget? lastTarget)` ;
    - `readyToInstall`, `installing`, `done` ;
    - `failed(ForkUpdateFailure kind)` avec `network`, `storage`, `signature`, `other`.
  - **`startDownload()`** :
    1. `availableBytes` : si la valeur est connue et inférieure à `2 × size + 100 Mo`, passer en `failed(storage)` ;
    2. `downloading`, puis téléchargement ;
    3. `verifying` et `inspectApk` :
       - `ok` : `writePending`, puis `_afterVerified()` ;
       - `invalid` : suppression des fichiers, puis `failed(network)` ;
       - `signatureMismatch` : suppression, puis `failed(signature)` ;
       - `wrongPackage` : suppression, puis `failed(other)` ;
       - `notNewer` : suppression, `controller.markRefused(tag)`, puis `failed(other)`.
  - **`_afterVerified()`** : si `canRequestInstalls` est vrai, appeler `install()` tout de suite (parcours, étape 4
    puis étape 6 : pas de clic supplémentaire quand l'autorisation existe déjà). Sinon, `needsPermission(null)`. La
    phase `readyToInstall` ne sert qu'après un retour des réglages ou un redémarrage (CA10).
  - **`openSettings()`** : `openInstallSettings()` mémorise `lastTarget`. Si la cible est `none`, rester en
    `needsPermission(none)` (le chemin complet s'affiche). Sinon, attendre la reprise.
  - **Reprise** : un `AppLifecycleListener(onResume:)` actif en `needsPermission` ou `permissionDenied` appelle
    `canRequestInstalls()` : accordée → `readyToInstall` (focus « Installer », CA10) ; refusée → `permissionDenied`
    (CA11). « Réessayer » rappelle `openSettings()`.
  - **`install()`** : `installing`, puis selon le résultat :
    - `cancelled` ou `installed` : `files.deleteAll()`, `controller.clearPending()`, puis `done` (la fenêtre se
      ferme ; CA13, CA14) ;
    - `permissionRequired` : `needsPermission` ;
    - `signatureMismatch` : `failed(signature)` et suppression ;
    - `notNewer` : `markRefused`, `failed(other)` et suppression ;
    - `insufficientStorage` : `failed(storage)` et suppression ;
    - `invalid` : `failed(network)` et suppression ;
    - autre : `failed(other)` et suppression.
  - **`retry()`** : selon l'échec, relance `startDownload()` (`network`, `storage`) ou `openSettings()`
    (`permissionDenied`).
  - **`cancel()`** (Retour, « Annuler », « Plus tard », fermeture) : déclenche l'abandon du téléchargement, supprime
    les fichiers et la fiche, sauf en `installing`, où il ne fait que fermer ; il est idempotent. `dispose()` appelle
    `cancel()` et retire le listener.
  - **Construction depuis une fiche** (reprise après redémarrage) : `canRequestInstalls` ? `readyToInstall` :
    `permissionDenied(null)`.
- Tests (faux installeur, faux téléchargeur, `fakeAsync`) :
  - chaque transition du tableau ;
  - reprise avec autorisation accordée ou refusée ;
  - `none` affiche le chemin ;
  - annulation pendant le téléchargement : aucun fichier ;
  - `cancelled` : suppression ;
  - fiche écrite seulement après `ok` ;
  - construction depuis une fiche.
- Critères d'acceptation couverts : CA8 à CA14, CA16, CA18, CA19.

### T12 — Fenêtre de mise à jour
- Complexité : M
- Dépend de : T8, T11
- Fichiers : créer `lib/fork/update/fork_update_dialog.dart` et `test/fork/update/fork_update_dialog_test.dart`.
- À faire :
  - **`Future<void> showForkUpdateDialog(BuildContext context, {ForkRelease? release, ForkPendingInstall? pending, bool showSkipVersion = false})`** :
    - ne fait rien si une fenêtre est déjà ouverte (garde statique) ;
    - `showScopedDialog`, qui crée la session et la libère à la fermeture.
  - **Mise en page** : `AlertDialog`, actions `DialogActionButton`, `autofocus` sur le bouton principal de chaque phase :

    | Phase | Contenu | Boutons (principal en gras) |
    |---|---|---|
    | `details` | `t.update.versionAvailable`, `fork.update.installedVersion`, notes | `t.common.later` · `t.update.skipVersion` (si `showSkipVersion`) · **`downloadAndInstall`** |
    | `downloading` | `LinearProgressIndicator` + `progress` | **`t.common.cancel`** |
    | `verifying` | indicateur + `verifying` | **`t.common.cancel`** |
    | `needsPermission` | `permissionExplanation` (+ chemin si la cible n'est pas `appPermission`) | `t.common.cancel` · **`openSettings`** |
    | `permissionDenied` | `permissionDenied` (+ chemin si besoin) | `t.common.close` · **`t.common.retry`** |
    | `readyToInstall` | `readyToInstall(version)` | `t.common.later` · **`install`** |
    | `installing` | `installing` | **`t.common.cancel`** |
    | `failed(network)` | `downloadFailed` | `t.common.close` · **`t.common.retry`** |
    | `failed(storage)` | `notEnoughSpace` | `t.common.close` · **`t.common.retry`** |
    | `failed(signature)` | `signatureConflict` | **`t.common.close`** |
    | `failed(other)` | `installFailed` | **`t.common.close`** |

  - **Chemin des réglages** : `unknownAppsList` → `permissionPathUnknownApps` ; `developerOptions` →
    `permissionPathDeveloper` ; `security`, `settings` et `none` → `permissionPathGeneric` ; `appPermission` et `null`
    → rien (décision du PO : le chemin seulement si nécessaire).
  - **Notes** :
    - `ConstrainedBox(maxHeight: 50 % de la hauteur)` + `SingleChildScrollView` avec `ScrollController` +
      `Scrollbar` ;
    - `onNavigateUp` et `onNavigateDown` de **tous** les boutons de `details` font défiler de 80 % de la hauteur
      visible (`animateTo`, borné). Le focus ne quitte jamais les boutons (CA6) ;
    - styles `titleMedium` (version) et `bodyLarge` (notes).
  - **Fermeture** : `PopScope(canPop: true, onPopInvokedWithResult: (didPop, _) { if (didPop) session.cancel(); })`.
    En phase `done`, la fenêtre se ferme d'elle-même (`Navigator.pop`).
  - **« Ignorer cette version »** : `await UpdateService.skipVersion(release.version)`, puis la fenêtre se ferme
    (CA24).
  - **Aucun texte en dur** (`check_hardcoded_strings.py`).
- Tests (widgets, mode clavier par `InputModeTracker`, faux installeur et faux téléchargeur) :
  - focus initial sur « Télécharger et installer » ;
  - flèche Bas : l'`offset` du défilement augmente et le focus ne bouge pas ;
  - Plus tard et Retour : fermeture sans appel à l'installeur ;
  - trois boutons si `showSkipVersion`, et « Ignorer » écrit la préférence ;
  - progression, puis Annuler : fermeture et aucun fichier ;
  - autorisation : `needsPermission`, puis reprise (on simule `AppLifecycleState.resumed`), puis « Installer » au
    focus ;
  - `developerOptions` affiche le chemin ;
  - `signatureMismatch` affiche le message de CA19 ;
  - `failed(network)` puis « Réessayer » relance.
- Critères d'acceptation couverts : CA6, CA7, CA9, CA10, CA11, CA13, CA16, CA18, CA19, CA23, CA24.

### T13 — Bouton d'accueil, crochets d'interface et reprise
- Complexité : M
- Dépend de : T10, T12
- Fichiers :
  - créer `lib/fork/update/fork_update_action.dart` et `test/fork/update/fork_update_action_test.dart` ;
  - modifier `lib/screens/discover_screen.dart`, `lib/utils/update_dialog.dart`, `lib/fork/update/fork_update_hooks.dart`
    et `test/fork/update/fork_update_hooks_guard_test.dart`.
- À faire :
  - **`FocusableAction forkUpdateAction(BuildContext context, {required Color iconColor})`** :
    - si `!ForkSideload.isSupported`, renvoie l'action vide ;
    - sinon : `final c = context.watch<ForkUpdateController?>();`, puis `c?.ensureChecked()` (sans `await`) ;
    - **reprise** : si `c?.pendingInstall != null && !c.resumeConsumed`, on marque `resumeConsumed = true` et l'on
      programme `addPostFrameCallback`. Ce rappel ouvre `showForkUpdateDialog(context, pending: …)` si
      `context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)`. Sinon, on remet `resumeConsumed` à `false`
      pour réessayer à la reconstruction suivante (CA10 après redémarrage) ;
    - **action vide** (pas de contrôleur ou `available == null`) :
      `FocusableAction(debugLabel: 'fork_update', onPressed: null, child: const SizedBox.shrink())` ;
    - **action pleine** : `FocusableAction(debugLabel: 'fork_update', onPressed: open, builder: …)`. Le builder
      affiche :
      - un `Container(decoration: FocusTheme.focusBackgroundDecoration(context, isFocused: state.showFocus, borderRadius: 20))` ;
      - un `Stack` avec l'`IconButton(icon: AppIcon(Symbols.system_update_rounded, color: iconColor), onPressed: open, tooltip: t.fork.update.buttonLabel)` ;
      - une pastille ronde de 8 px en `colorScheme.primary`, en `Positioned(top: 6, right: 6)` sous `IgnorePointer` ;
      - quand `state.showFocus`, une étiquette `t.fork.update.buttonLabel` sous le bouton, par `OverlayPortal`
        (contrôleur montré ou caché selon `showFocus`), sans changer la mise en page ;
    - `open` appelle `showForkUpdateDialog(context, release: c.available!)`.
  - **`discover_screen.dart`** :
    - import marqué ;
    - dans `actions:` de `_buildOverlaidAppBar`, juste après le `FocusableAction` de Watch Together (avant
      « Companion Remote »), ajouter :

      ```dart
      forkUpdateAction(context, iconColor: foregroundColor), // FORK: bouton-mise-a-jour — update button next to Watch Together
      ```
  - **`fork_update_hooks.dart`** : ajouter `static Future<void>? showDialog(BuildContext context, Map<String, dynamic> info, {required bool showSkipVersion})`.
    Première ligne : `if (!ForkSideload.isSupported) return null;`. Il renvoie `null` si `info['forkRelease']` n'est
    pas un `ForkRelease`, sinon `showForkUpdateDialog(context, release: …, showSkipVersion: showSkipVersion)`.
  - **`update_dialog.dart`** : import marqué, et en première ligne de `showUpdateAvailableDialog` :

    ```dart
    // FORK: bouton-mise-a-jour — download and install the APK instead of opening the browser (null = upstream)
    if (ForkUpdateHooks.showDialog(context, updateInfo, showSkipVersion: showSkipVersion) case final fork?) return fork;
    ```
  - **Garde de crochets** : ajouter la présence de `forkUpdateAction(` dans `discover_screen.dart`, de
    `ForkUpdateHooks.showDialog(` dans `update_dialog.dart`, et de la forme exacte
    `if (kForkSideloadUpdates) ChangeNotifierProvider<ForkUpdateController>` dans `main.dart`. Elle échoue aussi si
    `ForkUpdateController.instance` apparaît ailleurs dans `lib/` hors de `lib/fork/update/` et de cette ligne.
    Vérifier aussi que `forkUpdateAction` et `showDialog` commencent par le test de `ForkSideload.isSupported`.
- Tests (`FocusableActionBar` réel avec actualiser, Watch Together, `forkUpdateAction` et télécommande, en mode
  clavier) :
  - **sans mise à jour** : largeur nulle, et Droite depuis Watch Together va à la télécommande (CA2) ;
  - **apparition alors que le focus est sur la télécommande** : le focus reste sur la télécommande (aucun nœud recréé) ;
  - **avec mise à jour** : Droite depuis Watch Together arrive sur le bouton, puis Gauche et Droite, et Bas appelle
    `onNavigateDown` (CA3) ;
  - étiquette visible seulement au focus ; pastille présente ;
  - OK ouvre la fenêtre, et à la fermeture le focus revient au bouton (CA7, CA9) ;
  - toucher sur l'`IconButton` (CA26) ;
  - **reprise** : une fiche présente ouvre la fenêtre en `readyToInstall` une seule fois ;
  - **sans provider**, l'action est vide : les tests upstream de `discover_screen_test.dart` restent verts sans
    modification.
- Critères d'acceptation couverts : CA1, CA2, CA3, CA6, CA7, CA9, CA10, CA21, CA23, CA26.

## Ordre conseillé

T1 → T2 → T3 côté plateforme. T5, T6, T8 en parallèle, puis T7, puis T9 → T10 → T11 → T12 → T13 côté app. T4 est
indépendante. Aucune tâche n'ajoute de `forkChangedSkip` ; `forkChangedSkipAllowlist` reste vide.

## Vérification globale

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
dart format <fichiers Dart modifiés>
scripts/format_native.sh --fix
python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh && scripts/codegen.sh --check
python3 scripts/checks/clean_translations.py --check --strict
dart run scripts/checks/check_analyzer.dart
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh test/fork/update && scripts/run_tests.sh       # toute la suite : 0 échec
(cd android && ./gradlew :app:testDebugUnitTest -PpopkinoSideload=true -x :app:compileFlutterBuildDebug && ./gradlew :app:lintDebug)
```

**Artefacts** (`BT=$(ls -d ~/Library/Android/sdk/build-tools/* | tail -1)`) :
1. **Build GitHub** :
   `flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true --dart-define-from-file=popkino_secrets.json`.
   Puis `$BT/aapt2 dump permissions build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` doit lister
   `REQUEST_INSTALL_PACKAGES`.
2. **Build sans le define** : `flutter build apk --release --split-per-abi --dart-define-from-file=popkino_secrets.json`.
   `aapt2 dump permissions` ne doit **pas** lister la permission. Extraire `lib/armeabi-v7a/libapp.so` de l'APK :
   `strings libapp.so | grep -E 'releases\?per_page|popkino-android-|sideload_updater'` doit être **vide**. Le dex ne
   doit pas contenir `SideloadUpdaterPlugin` : extraire les `classes*.dex`, puis
   `$BT/dexdump -l plain classes*.dex | grep SideloadUpdaterPlugin` doit être vide.
3. `flutter build appbundle --release --dart-define=ENABLE_UPDATE_CHECK=true` doit **échouer** (garde-fou du
   build).

**Manuel sur la Fire TV Stick** (`192.168.1.173:5555`, armeabi-v7a) et sur un téléphone Android :
- **Préparation** :
  - installer un build signé avec la clé définitive, en version basse
    (`--build-name=0.0.1 --build-number=1 --dart-define=ENABLE_UPDATE_CHECK=true`), face à une pré-version publiée,
    signée avec la même clé, contenant les APK nus ;
  - entre deux essais, remettre l'autorisation à zéro :
    `adb shell appops set io.github.adrien24.popkino REQUEST_INSTALL_PACKAGES default`.
- **Accueil** :
  - le bouton et sa pastille apparaissent en moins de 10 s ; le focus de départ reste sur le contenu ;
  - Haut, puis Gauche/Droite : focus visible et étiquette au focus ; Bas revient au contenu (CA1, CA3) ;
  - sans release plus récente, la barre est identique (CA2) ;
  - en mode avion, aucun message (CA15).
- **Fenêtre** :
  - notes qui défilent à Haut/Bas ; Plus tard et Retour rendent le focus au bouton (CA6, CA7) ;
  - téléchargement, puis Annuler : `adb shell dumpsys diskstats` (tailles de cache par paquet) revient à sa valeur
    d'avant le téléchargement (CA9). `run-as` échoue sur un APK de release, non débogable ;
  - Wi-Fi coupé pendant le téléchargement : message, puis « Réessayer » (CA16).
- **Autorisation** :
  - « Ouvrir les réglages » : noter l'écran Fire OS réellement ouvert, puis activer et appuyer sur Retour ;
  - Popkino redémarre (Android 11) et la fenêtre se rouvre avec « Installer » au focus, sans retéléchargement
    (vérifier l'absence de trafic, ou la date du fichier) (CA10) ;
  - même parcours en refusant l'autorisation : message, puis « Réessayer » rouvre les réglages (CA11).
- **Installation** :
  - « Installer », puis « Ouvrir » : nouveau numéro dans À propos, serveurs Plex et Jellyfin connectés, langues
    préférées conservées, bouton disparu (CA12) ;
  - « Annuler » dans l'écran système : le bouton est toujours là (CA13) ;
  - `adb shell dumpsys diskstats` avant et après : le cache n'augmente pas (CA14).
- **Signature** : depuis la 0.2.0 actuelle (clé de debug), vers une release signée avec la clé définitive : message de
  CA19, sans écran d'erreur du système.
- **Démarrage et Paramètres** :
  - la fenêtre de démarrage a trois boutons (CA23) ;
  - « Ignorer » : la fenêtre ne revient pas au lancement suivant, mais le bouton reste (CA24) ;
  - vérification automatique désactivée : le bouton apparaît quand même (CA25) ;
  - Paramètres > Mises à jour > Vérifier : même fenêtre (CA21).
- **Ordinateur** (macOS) : le comportement de mise à jour est inchangé (CA22).

## Risques restants

- **Écran Fire OS ouvert par `MANAGE_UNKNOWN_APP_SOURCES`** : il n'est pas encore vérifié visuellement (la TV était en
  veille). Si ce n'est pas le réglage propre à Popkino, la phrase d'aide affiche le chemin, mais la cible renvoyée
  restera `appPermission`. Si le test manuel le montre, il faudra une règle propre à Fire OS
  (`packageManager.hasSystemFeature("amazon.hardware.fire_tv")` donne `developerOptions`), à décider en recette.
- **Bug de liste vide de Fire OS** (automne 2026) : seul adb permet de s'en sortir, documenté dans le README (T4).
- **Redémarrage à froid** : si l'utilisateur ne revient pas sur Découvrir (autre onglet au démarrage), la reprise
  attend son retour sur Découvrir. Au-delà de 24 h, la fiche est purgée et il faut retélécharger.
- **`java.srcDir` et Kotlin 2.4** : à confirmer par le premier build de T1 (repli `kotlin.srcDir`).
- **Réseau au réveil de la TV** : un échec au lancement cache le bouton jusqu'au lancement suivant (CA4 le permet).
- **Pré-versions proposées à tous** : c'est une règle de process de release, rappelée dans `release.md` (T4).
- **Fusion upstream** :
  - une dizaine de lignes marquées dans `discover_screen.dart`, `update_service.dart`, `update_dialog.dart`,
    `main.dart`, `network_security_config_test.dart`, `PlezyActivity.kt` et `ci.yml` ;
  - un bloc en fin de `build.gradle.kts` ;
  - les gardes de T3, T10 et T13 détectent un crochet perdu.
- **Signature et publication** : aucun changement de clé ni de secret. Seuls le format des fichiers de release
  (`build.yml`) et la procédure (`release.md`) changent. Le passage de la 0.2.0 (clé de debug) à la clé définitive
  impose une réinstallation unique, acceptée par le PO.

## Ajouts proposés au skill `conventions-code` (à écrire par l'orchestrateur)

- **TV** : dans un `FocusableActionBar`, une action affichée sous condition garde un emplacement fixe :
  `debugLabel`, avec `onPressed: null` et `child: SizedBox.shrink()` quand elle est masquée. Changer la longueur de
  `actions` recrée les nœuds des actions sans `debugLabel` (`_rebindNodes`) et fait perdre le focus.
- **État** : un provider qui peut être absent (provider du fork, tests upstream qui ne le fournissent pas) se lit avec
  `context.watch<T?>()` ou `read<T?>()`. Avec `provider` 6, la lecture renvoie `null` au lieu de lever une exception.
- **Options de build** : le code du fork réservé à une distribution est gardé par une constante
  `const bool k… = bool.fromEnvironment(...)` testée **en tête** de chaque point d'entrée, avec un forçage de test
  limité à `kDebugMode`. L'AOT l'élimine alors du binaire, ce qui se vérifie par `strings libapp.so`.
- **GitHub** : `/releases/latest` ignore les pré-versions et renvoie 404 s'il n'y a que des pré-versions. Pour les
  inclure, lister `/releases`.
- **Android natif du fork** : package `com.edde746.plezy.fork`, enregistré par `ForkPlugins.register(flutterEngine)`.
  Le code propre au canal sideload vit dans `android/app/src/sideload/` (D14).
