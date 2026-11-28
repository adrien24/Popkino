# Proposition plateforme — bouton-mise-a-jour

Auteur : architecte-plateforme · 2026-11-28 · Spec : `docs/produit/specs/bouton-mise-a-jour.md` (validée)

## Compréhension de la spec

La version GitHub (APK installé hors store) doit télécharger l'APK de la nouvelle release correspondant au processeur
de l'appareil, puis l'installer par l'écran système d'Android ou de Fire OS, entièrement à la télécommande, sans perdre
les comptes. Les versions store (Play, Amazon) ne doivent contenir ni ce mécanisme ni l'autorisation d'installer.

CA qui touchent mon périmètre :
- **CA8 / CA17** : choix de l'APK selon l'ABI ; pas de bouton s'il n'y a aucun APK installable pour l'appareil.
- **CA10 / CA11** : autorisation « installer des applis inconnues », ouverture de son écran, reprise sans
  retéléchargement.
- **CA12 / CA13** : installation par l'écran système, données conservées, annulation sans effet de bord.
- **CA14 / CA18** : pas de fichier résiduel, espace insuffisant signalé.
- **CA19** : signature différente (clé de test puis clé définitive) détectée et expliquée.
- **CA20** : rien de tout cela dans les builds store (permission, code natif, téléchargement d'APK).
- **CA22 / CA26** : bureau inchangé ; même APK et même parcours sur téléphone Android.

## Existant

Lu dans le code et mesuré sur la Fire TV Stick (adb, lecture seule, 2026-11-28).

**Android / Gradle**
- `android/app/build.gradle.kts` : AGP **9.3.1**, Kotlin 2.4.10, `minSdk = 25`, `targetSdk = flutter.targetSdkVersion`
  (36), `applicationId = "io.github.adrien24.popkino"` (FORK), aucun flavor. Signature release seulement si
  `android/key.properties` existe. Build type supplémentaire `minified`. Un précédent upstream de variante par
  environnement existe déjà : `if (System.getenv("AMAZON") != null)` (versionCode + 3000).
- `android/app/src/main/AndroidManifest.xml` : **aucune** `REQUEST_INSTALL_PACKAGES`. Un **FileProvider existe déjà**
  (`${applicationId}.fileprovider`, `res/xml/file_provider_paths.xml` avec `cache-path name="cache"`), utilisé par
  `ExternalPlayerChannel.kt` l. 189. `BILLING` déjà retiré (D7).
- `android/app/src/main/kotlin/com/edde746/plezy/PlezyActivity.kt` : canaux `com.plezy/*` enregistrés dans
  `configureFlutterEngine` (l. 875) ; `onActivityResult` (l. 619) passe les codes inconnus à `super`, donc aux plugins
  Flutter (`ActivityPluginBinding.addActivityResultListener` fonctionne sans toucher l'activité).
- Tests Kotlin : JUnit + Robolectric 4.16 dans `src/test/kotlin` ; CI : `./gradlew :app:testDebugUnitTest … ` et
  `:app:lintDebug` (`.github/workflows/ci.yml` l. 229 et 233), **sans** `--dart-define`.
- Flutter transmet les `--dart-define` (y compris ceux de `--dart-define-from-file`) à Gradle sous la propriété
  `-Pdart-defines=<base64>,<base64>…` (`flutter_tools/lib/src/build_info.dart` l. 412, lue par `FlutterPlugin.kt`
  l. 647). Gradle peut donc lire `ENABLE_UPDATE_CHECK` lui-même.
- AGP 9.3.1 expose `variant.sources.manifests.addStaticManifestFile(String)` (vérifié dans `gradle-api-9.3.1.jar`).
- `--split-per-abi` : Flutter fixe `versionCode = ABI × 1000 + N` avec armeabi-v7a = 1, arm64-v8a = 2, x86_64 = 4
  (`FlutterPluginConstants.kt` l. 39).

**Dart**
- `lib/services/update_service.dart` : `isUpdateCheckEnabled` = `bool.fromEnvironment('ENABLE_UPDATE_CHECK')`,
  `isUpdateCheckAvailable` ; appel GitHub `releases/latest` (ignore les pré-versions, sujet de l'architecte-app).
- Dépendances déjà présentes : `device_info_plus` (`AndroidDeviceInfo.supportedAbis` = `Build.SUPPORTED_ABIS`),
  `path_provider` (`getTemporaryDirectory()` = `Context.getCacheDir()` sur Android).

**Release**
- `.github/workflows/build.yml` : `RELEASE_DART_DEFINES` contient `ENABLE_UPDATE_CHECK=true` ; l'étape « Package APKs »
  (l. 134-138, FORK) produit `popkino-android-<abi>.tar.gz` contenant `popkino.apk` ; `create-release` n'est créée que
  si **toutes** les plateformes sont cochées (l. 964).
- **Les releases réellement publiées (v0.1.0, v0.2.0, pré-versions manuelles) contiennent des APK nus**
  `popkino-android-<abi>-<version>.apk` + `SHA256SUMS.txt`, pas de tar.gz : le workflow et la pratique divergent.
- README l. 17-19 : liens vers les tar.gz.

**Fire TV Stick AFTMA08C15 (mesures adb)**
- Fire OS 8.1.8.6, API 30, `ro.product.cpu.abilist = armeabi-v7a,armeabi`.
- Popkino 0.2.0 installé : `versionCode=1005`, `primaryCpuAbi=armeabi-v7a`, **signé `CN=Android Debug`** (clé de debug,
  SHA-256 `b2124008…`), alors que la clé définitive a l'empreinte `9F:6F:21:45…` (A2) : la première release signée
  avec la clé définitive ne pourra pas mettre à jour cette installation (CA19 confirmé).
- `appops get … REQUEST_INSTALL_PACKAGES` : non accordé.
- `android.settings.MANAGE_UNKNOWN_APP_SOURCES` (avec ou sans `package:`) est résolu par
  `com.amazon.tv.settings.v2/.tv.device.DeviceActivity` ; `APPLICATION_DEVELOPMENT_SETTINGS` aussi (sans data) ;
  `INSTALL_PACKAGE` et `VIEW` d'un APK : `com.android.packageinstaller/.InstallStart` (installeur AOSP).
- `/data` : 2,6 Go libres ; APK armeabi-v7a 0.2.0 : 94 Mo.
- Écran ouvert par l'intent non vérifié visuellement (TV en veille, je ne l'ai pas réveillée) : test manuel à faire.

## Approche proposée

### 1. Une seule bascule : `ENABLE_UPDATE_CHECK=true` pilote aussi le natif

D7 dit « pas de flavor tant que le manifeste n'a pas à différer ». Il diffère désormais (permission), mais un flavor
introduirait **une deuxième bascule** (`--flavor` + `--dart-define`) qui peut être désynchronisée : un AAB
`--flavor store --dart-define=ENABLE_UPDATE_CHECK=true` aurait le bouton sans pouvoir installer, et l'inverse livrerait
la permission sur Play. Je propose que **Gradle lise le même define** que Dart. Un seul bloc, ajouté **à la fin** de
`android/app/build.gradle.kts` (aucune ligne upstream modifiée, conflit de fusion quasi nul) :

```kotlin
// FORK: bouton-mise-a-jour — the sideload APK installer (permission + Kotlin) ships only when the dart-defines
// contain ENABLE_UPDATE_CHECK=true (GitHub APKs). Store builds never get it (Google Play / Amazon policy).
val popkinoSideload: Boolean = run {
  val defines = (findProperty("dart-defines") as String?).orEmpty()
    .split(',').filter(String::isNotBlank)
    .map { String(java.util.Base64.getDecoder().decode(it), Charsets.UTF_8) }
  "ENABLE_UPDATE_CHECK=true" in defines || findProperty("popkinoSideload") == "true"
}
if (popkinoSideload &&
  (System.getenv("AMAZON") != null ||
    gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) })
) {
  throw GradleException("ENABLE_UPDATE_CHECK=true is for GitHub APKs only; store builds must not ship the APK installer")
}
android {
  sourceSets {
    getByName("main").java.srcDir(if (popkinoSideload) "src/sideload/kotlin" else "src/nosideload/kotlin")
    if (popkinoSideload) getByName("test").java.srcDir("src/sideloadTest/kotlin")
  }
}
androidComponents {
  onVariants { variant ->
    if (popkinoSideload) variant.sources.manifests.addStaticManifestFile("src/sideload/AndroidManifest.xml")
  }
}
```

Propriétés :
- **Sûr par défaut** : sans le define (AAB Play, Amazon, `flutter run` ordinaire), ni permission ni code
  d'installation. Oublier un flag ne peut pas faire rejeter l'app ; au pire le bouton manque.
- **Garde-fou** : `flutter build appbundle` (tâche `bundleRelease`) ou `AMAZON=…` avec le define **échoue au build**.
- `popkinoSideload=true` (propriété Gradle) sert uniquement à la CI pour compiler et tester le code sideload avec
  `./gradlew` direct (qui ne reçoit pas de dart-defines).
- `java.srcDir` plutôt que l'API de variantes pour le Kotlin : le plugin Kotlin 2.4 (mode `builtInKotlin=false`) suit
  les source sets du DSL ; l'API `variant.sources.kotlin` n'est pas garantie d'être vue. Le manifeste, lui, ne peut
  être ajouté qu'au niveau variante (un seul manifeste par source set) : `addStaticManifestFile`.

Ce choix **amende D7** (voir § Décisions durables).

### 2. Fichiers natifs propres au fork, isolés par dossier

```
android/app/src/sideload/AndroidManifest.xml          <uses-permission REQUEST_INSTALL_PACKAGES/> et rien d'autre
android/app/src/sideload/kotlin/com/edde746/plezy/fork/ForkPlugins.kt
android/app/src/sideload/kotlin/com/edde746/plezy/fork/sideload/SideloadUpdaterPlugin.kt
android/app/src/sideload/kotlin/com/edde746/plezy/fork/sideload/ApkInspector.kt
android/app/src/sideload/kotlin/com/edde746/plezy/fork/sideload/InstallPermission.kt
android/app/src/sideload/kotlin/com/edde746/plezy/fork/sideload/InstallResults.kt
android/app/src/nosideload/kotlin/com/edde746/plezy/fork/ForkPlugins.kt   no-op
android/app/src/sideloadTest/kotlin/com/edde746/plezy/fork/sideload/*Test.kt
```

Enregistrement : **une seule ligne** dans `PlezyActivity.configureFlutterEngine` (après les `plugins.add` existants) :

```kotlin
ForkPlugins.register(flutterEngine) // FORK: plugins natifs du fork (bouton-mise-a-jour)
```

`ForkPlugins` existe dans les deux dossiers avec la même signature `object ForkPlugins { fun register(engine:
FlutterEngine) }` ; la version sideload fait `engine.plugins.add(SideloadUpdaterPlugin())`, la version nosideload ne
fait rien. Pas de réflexion, compatible R8, et le code d'installation est **absent** du dex des builds store (pas
seulement inactif : Play analyse aussi le code, cf. politique « Device and Network Abuse »).

`SideloadUpdaterPlugin` = `FlutterPlugin` + `ActivityAware` + `PluginRegistry.ActivityResultListener`, canal
`popkino/sideload_updater` (nom propre au fork ; D3 ne concerne que les canaux upstream existants). Travaux lourds
(lecture de l'APK) sur `Dispatchers.IO` (coroutines déjà en dépendance), scope annulé à `onDetachedFromEngine`.

### 3. Installation : intent `ACTION_INSTALL_PACKAGE` + FileProvider existant

1. Dart télécharge dans `getTemporaryDirectory()/updates/` (= `cacheDir/updates/`) sous un nom `.part`, puis renomme en
   `popkino-<version>-<abi>.apk` une fois la taille attendue atteinte.
2. Dart appelle `inspectApk(path)`, puis `install(path)`.
3. Natif : vérifie que le chemin canonique est dans `cacheDir/updates/` et finit par `.apk` ; refait l'inspection
   (défense en profondeur) ; vérifie l'autorisation ; lance :
   `Intent(ACTION_INSTALL_PACKAGE)`, `data = FileProvider.getUriForFile(activity, "$packageName.fileprovider", file)`,
   `FLAG_GRANT_READ_URI_PERMISSION`, `EXTRA_RETURN_RESULT = true`, via `startActivityForResult` (code dédié, distinct du
   `7461` de `ExternalPlayerChannel`). `file_provider_paths.xml` n'a pas à changer (`cache-path` existe).
4. Résultat : `RESULT_CANCELED` → `cancelled` (CA13) ; `RESULT_FIRST_USER` + extra `android.intent.extra.INSTALL_RESULT`
   → `-7` (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) = `signatureMismatch`, `-25` (downgrade) = `notNewer`, `-4` =
   `insufficientStorage`, autre = `failed(code)`. En cas de succès, le système tue Popkino pendant l'installation : la
   réponse n'arrive jamais, c'est normal (étape 7 de la spec : l'écran système propose « Ouvrir »).
5. Pas de `<queries>` à ajouter : on lance et on capture `ActivityNotFoundException` au lieu de `resolveActivity`.

Mêmes `applicationId` et même clé ⇒ Android conserve `/data/data/<pkg>` : comptes, base drift et réglages restent
(CA12) sans aucune action de notre part.

### 4. Inspection de l'APK avant l'installation (CA19 sans écran d'erreur système)

`inspectApk` lit l'archive avec `PackageManager.getPackageArchiveInfo` et renvoie, dans cet ordre :
- `invalid` : archive illisible (téléchargement tronqué, fichier corrompu) ;
- `wrongPackage` : `packageName` différent du nôtre ;
- `signatureMismatch` : les empreintes SHA-256 des signataires actuels de l'app installée ne figurent pas toutes dans
  les signataires (ou l'historique de rotation) de l'APK. API ≥ 28 : `GET_SIGNING_CERTIFICATES`, repli
  `GET_SIGNATURES` si `signingInfo` est nul pour une archive ; API 25-27 : `GET_SIGNATURES` ;
- `notNewer` : `longVersionCode` de l'APK ≤ celui installé ;
- `ok`, avec `versionName` et `versionCode` de l'APK.

La signature est contrôlée **avant** la version pour que le passage clé de debug → clé définitive affiche le message
CA19, même si le numéro de build a aussi reculé (cas réel : 0.2.0+5 installée, `pubspec` à 1.0.0+1).

Cette vérification fait aussi office de contrôle d'intégrité : HTTPS + même signataire que l'app installée. Un
`SHA256SUMS.txt` n'apporte rien de plus pour l'installation ; je ne le rends pas obligatoire.

Performance : vérifier la signature v2/v3 relit tout l'APK (94 Mo), compter 1 à 3 s sur la Fire Stick ; c'est fait sur
`Dispatchers.IO`, l'UI Dart affiche un état « Vérification… » sans bloquer le D-pad.

### 5. Autorisation « installer des applis inconnues » (CA10, CA11)

- `canRequestInstalls()` : API ≥ 26 `packageManager.canRequestPackageInstalls()` ; API 25 (Fire OS 6)
  `Settings.Secure.INSTALL_NON_MARKET_APPS == 1`. (Sans la permission dans le manifeste, `canRequestPackageInstalls`
  lève une `SecurityException` : raison de plus pour que ce code n'existe que dans les builds sideload.)
- `openInstallSettings()` essaie dans l'ordre, s'arrête au premier qui démarre, et **dit lequel** :
  1. `ACTION_MANAGE_UNKNOWN_APP_SOURCES` + `package:<pkg>` (API ≥ 26) → `appPermission` ;
  2. `ACTION_MANAGE_UNKNOWN_APP_SOURCES` sans data → `unknownAppsList` ;
  3. `ACTION_APPLICATION_DEVELOPMENT_SETTINGS` → `developerOptions` (Fire OS range « Installer des applis inconnues »
     dans les options pour les développeurs) ;
  4. `ACTION_SECURITY_SETTINGS` → `security` (API 25) ;
  5. `ACTION_SETTINGS` → `settings` ; sinon `none`.
  Sur la Fire Stick, le n° 1 est résolu par `com.amazon.tv.settings.v2` ; reste à voir s'il ouvre le réglage propre à
  Popkino ou un écran général (test manuel T-final). Dart adapte la phrase d'aide selon la valeur renvoyée.
- **Retour dans l'app** : on ne se fie pas à `onActivityResult` des réglages (Fire OS peut ouvrir les réglages dans une
  autre tâche, ce qui renvoie un résultat immédiat). Dart revérifie `canRequestInstalls()` à
  `AppLifecycleState.resumed`.
- **Piège Android 11 (= Fire OS 8, la TV cible)** : au **premier** octroi de cette autorisation, Android 11 **tue le
  processus** de l'app (comportement voulu par Google). En appuyant sur Retour, l'utilisateur revient dans un Popkino
  redémarré à froid : l'état Dart en mémoire est perdu. Pour tenir CA10 (« sans retélécharger »), l'APK vérifié doit
  rester dans `cacheDir/updates/` et l'app doit, au démarrage, reprendre à l'étape « installer » si un APK complet
  d'une version plus récente que l'installée s'y trouve et que l'autorisation est maintenant accordée. C'est une
  exigence pour l'architecte-app (voir Interfaces).
- **Bug Fire OS connu (août-septembre 2026)** : une mise à jour des réglages Fire TV vidait la liste « Installer des
  applis inconnues » ; correctif déployé depuis le 16/09/2026. Si Popkino n'apparaît pas dans la liste, la seule
  issue est adb : `adb shell appops set io.github.adrien24.popkino REQUEST_INSTALL_PACKAGES allow` (à documenter dans
  le README, section dépannage).

### 6. Choix de l'APK selon l'ABI (CA8, CA17) — sans code natif

Côté Dart, fonction pure (fichier `lib/fork/update/apk_asset.dart`, à écrire par le codeur) :
- noms acceptés : `^popkino-android-(arm64-v8a|armeabi-v7a|x86_64)(-\d+\.\d+\.\d+)?\.apk$` (avec ou sans version,
  pour couvrir les releases manuelles existantes et le format CI proposé ci-dessous) ; les `.tar.gz` sont ignorés ;
- ordre des ABI : `AndroidDeviceInfo.supportedAbis` (`device_info_plus`, déjà en dépendance) = `Build.SUPPORTED_ABIS`.
  La Fire Stick renvoie `[armeabi-v7a, armeabi]` : son processeur peut être 64 bits, c'est l'OS 32 bits qui compte,
  donc **ne jamais** se fier à `uname`/`os.arch` ;
- on prend le premier ABI de cette liste qui a un asset **et** dont la tranche de versionCode (1, 2 ou 4) est ≥ à celle
  de l'APK installé (déduite de `Abi.current()` de `dart:ffi` : `androidArm` → 1, `androidArm64` → 2,
  `androidX64` → 4). Sinon : aucun asset installable → pas de bouton (CA17). Exemple : téléphone 64 bits qui a l'APK
  arm64 (2xxx) et release sans arm64 → l'APK armeabi-v7a (1xxx) serait un downgrade refusé, donc pas de bouton.
- Conséquence de la formule `ABI × 1000 + N` : **N doit rester < 1000** (sinon les tranches se chevauchent).

### 7. Espace de stockage (CA18)

`availableBytes()` renvoie `StatFs(cacheDir).availableBytes`. Règle proposée à l'architecte-app : refuser le
téléchargement si `available < 2 × taille de l'asset + 100 Mo` (l'APK téléchargé + sa copie par l'installeur dans
`/data/app`, même partition sur la Fire Stick ; les `.so` ne sont pas extraits, `useLegacyPackaging` désactivé par
défaut à minSdk 25). Une erreur d'écriture (`ENOSPC`) pendant le téléchargement et le code `-4` de l'installeur mènent
au même message.

### 8. Format des fichiers de release (workflow et procédure)

- `build.yml`, étape « Package APKs » (lignes déjà FORK) : remplacer les trois `tar -czf` par
  `cp build/app/outputs/flutter-apk/app-<abi>-release.apk popkino-android-<abi>.apk`, et mettre à jour les listes
  « Attest », « Upload » et « Collect release files » (`.tar.gz` → `.apk`). Nom **sans version** : les liens README
  `releases/latest/download/popkino-android-<abi>.apk` restent stables. Télécharger un tar.gz sur la TV puis
  l'extraire doublerait l'espace et le temps CPU pour rien (un APK est déjà compressé).
- README l. 17-19 : liens vers les `.apk`.
- `docs/technique/release.md` : ajouter la procédure « release Android seule » (c'est ce qui a été fait pour 0.1.0 et
  0.2.0, car `create-release` exige toutes les plateformes) : build local avec `key.properties` (clé définitive),
  `flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true
  --dart-define-from-file=popkino_secrets.json`, renommage `popkino-android-<abi>.apk`, contrôle
  `apksigner verify --print-certs` (SHA-256 = `9F:6F:21:45…`) et `aapt2 dump permissions` (doit lister
  `REQUEST_INSTALL_PACKAGES`), puis `gh release create X.Y.Z --prerelease …`. Tag sans `v` (D10) ; les anciens tags
  `v0.x` restent (la vérification Dart retire déjà le `v`).
- Numéro de build : la Fire Stick a `versionCode=1005` (0.2.0+**5**) et `pubspec.yaml` est à `1.0.0+1`. Ici sans
  conséquence (le changement de clé impose de toute façon une réinstallation), mais la règle de `release.md`
  (« N augmente toujours ») contredit D10 (« à partir de 1.0.0+1 »). Je propose de publier la 1.0.0 en **`+6`** au
  minimum et d'amender D10.

### 9. Garde-fous contre une fuite vers les stores (CA20)

- **Build** : le `throw` du § 1 (AAB ou Amazon avec le define).
- **Garde statique** `scripts/fork/test_sideload_isolation.py` (Python standard, lancé par `ci_guard_checks.sh`, D8) :
  `REQUEST_INSTALL_PACKAGES` n'apparaît dans aucun `AndroidManifest.xml` sauf `android/app/src/sideload/` ;
  `ACTION_INSTALL_PACKAGE`, `PackageInstaller`, `MANAGE_UNKNOWN_APP_SOURCES`, `canRequestPackageInstalls`
  n'apparaissent pas hors de `src/sideload*/` ; le bloc FORK de `build.gradle.kts` et l'appel `ForkPlugins.register`
  de `PlezyActivity.kt` sont présents ; les deux `ForkPlugins.kt` déclarent la même signature.
- **CI** : `ci.yml` l. 229, ajouter `-PpopkinoSideload=true` à la commande `testDebugUnitTest` (une ligne FORK) pour
  compiler et tester le code sideload ; `lintDebug` reste sans, ce qui compile la variante nosideload. Les deux
  variantes sont donc compilées à chaque CI.
- **Vérification d'artefact** (plan, et plus tard `publication-stores`) : `aapt2 dump permissions` sur l'APK GitHub
  (présente) et sur un APK construit sans le define (absente) ; `bundletool dump manifest` sur l'AAB Play.
- **Dart (architecte-app)** : tout le code de téléchargement d'APK et l'appel au canal doivent être derrière la
  constante `UpdateService.isUpdateCheckEnabled` (`const bool.fromEnvironment`) pour que l'AOT les élimine de l'AAB
  (politique Play : pas de téléchargement de code exécutable hors Play).

## Interfaces exposées à l'architecte-app

Canal `MethodChannel('popkino/sideload_updater')`, enregistré **uniquement** dans les builds avec
`ENABLE_UPDATE_CHECK=true` sur Android. Ailleurs : `MissingPluginException`.

| Méthode | Arguments | Retour | Notes |
|---|---|---|---|
| `canRequestInstalls` | — | `bool` | à rappeler à chaque `resumed` après l'ouverture des réglages |
| `openInstallSettings` | — | `String` : `appPermission`, `unknownAppsList`, `developerOptions`, `security`, `settings`, `none` | revient tout de suite ; ne dit **pas** si l'autorisation a été donnée |
| `availableBytes` | — | `int` | `StatFs(cacheDir)` |
| `inspectApk` | `{path: String}` | `{status: ok/invalid/wrongPackage/signatureMismatch/notNewer, versionName?, versionCode?}` | IO, 1 à 3 s |
| `install` | `{path: String}` | `String` : `cancelled`, `permissionRequired`, `signatureMismatch`, `notNewer`, `insufficientStorage`, `invalid`, `invalidPath`, `installerUnavailable`, `busy`, `failed:<code>`, `installed` | ne revient pas en cas de succès (processus tué) |

Wrapper Dart proposé (`lib/fork/update/sideload_installer.dart`, interface pour pouvoir le simuler dans les tests) :

```dart
enum ApkCheck { ok, invalid, wrongPackage, signatureMismatch, notNewer }
enum InstallOutcome { installed, cancelled, permissionRequired, signatureMismatch, notNewer,
  insufficientStorage, invalid, unavailable, failed }
enum InstallSettingsTarget { appPermission, unknownAppsList, developerOptions, security, settings, none }

abstract interface class SideloadInstaller {
  static const updatesDirName = 'updates'; // under getTemporaryDirectory()
  Future<bool> canRequestInstalls();
  Future<InstallSettingsTarget> openInstallSettings();
  Future<int?> availableBytes();
  Future<({ApkCheck status, String? versionName})> inspectApk(String path);
  Future<InstallOutcome> install(String path); // MissingPluginException -> unavailable
}
```

Ce que j'attends en retour du côté Dart (contrat) :
1. Fichiers uniquement dans `getTemporaryDirectory()/updates/`, `.part` pendant le téléchargement, renommé en `.apk`
   quand la taille égale le `size` de l'asset GitHub ; écriture en flux (jamais l'APK entier en mémoire : 94 Mo sur
   une TV à 1-2 Go de RAM) ; suivre les redirections (`browser_download_url` → `objects.githubusercontent.com`) ;
   progression limitée à quelques rafraîchissements par seconde.
2. **Reprise après redémarrage** (piège Android 11) : au démarrage, supprimer les `.part` et les `.apk` d'une version
   ≤ à l'installée ; garder un `.apk` complet d'une version plus récente et proposer directement l'installation si
   `canRequestInstalls()` est vrai.
3. Supprimer le fichier après `cancelled`, `signatureMismatch`, `notNewer`, `invalid` et sur « Annuler » (CA9, CA14).
4. Choix de l'asset par la fonction pure du § 6 ; contrôle d'espace du § 7.
5. Tout appel derrière `UpdateService.isUpdateCheckAvailable && Platform.isAndroid`.

## Alternatives écartées

- **Flavors Gradle `github` / `store`** : deuxième bascule désynchronisable avec `ENABLE_UPDATE_CHECK` ; `--flavor`
  obligatoire partout ; chemins de sortie changés (`app-github-armeabi-v7a-release.apk`), tâches renommées
  (`testGithubDebugUnitTest`, `lintGithubDebug`, `-Pplezy.testBuildType`) dans `ci.yml`, `build.yml`, README,
  `CLAUDE.md` et les skills : gros diff upstream pour le même résultat. Le bloc du § 1 reste compatible avec des
  flavors futurs si `publication-stores` en a besoin (renommer `src/sideload` en source set de flavor).
- **Permission toujours déclarée, retirée pour les stores par `tools:node="remove"`** : sûr seulement si on n'oublie
  jamais le retrait ; un oubli = rejet Play. Mon approche est sûre par défaut.
- **Plugin pub d'installation (`ota_update`, `app_installer`, `open_filex`…)** : la dépendance est dans toutes les
  builds et certains déclarent `REQUEST_INSTALL_PACKAGES` dans leur propre manifeste, fusionné dans l'AAB Play ⇒ rejet.
  Et une ligne de plus dans `pubspec.yaml`.
- **API `PackageInstaller` (sessions)** : non dépréciée et statuts plus fins, mais trois fois plus de code (session,
  `IntentSender`, receiver dynamique avec drapeaux `FLAG_MUTABLE`/`RECEIVER_NOT_EXPORTED` selon l'API), copie des 94 Mo
  dans la session (double écriture sur l'eMMC lente de la Fire Stick, 2,6 Go libres) et parcours de confirmation non
  documenté sur Fire OS. `ACTION_INSTALL_PACKAGE` est déprécié depuis l'API 29 mais fonctionne toujours, c'est la voie
  des outils de sideload Fire TV, et le couple inspection + codes `INSTALL_RESULT` couvre nos cas d'erreur. Repli si
  un futur Android le retire : remplacer l'implémentation de `install` derrière le même canal.
- **Téléchargement natif (`DownloadManager`)** : progression par sondage, notification système, et logique éclatée
  entre Kotlin et Dart ; le téléchargement Dart reste testable et unique pour toutes les plateformes.
- **Garder les tar.gz et extraire sur l'appareil** : double espace et temps CPU sur la TV pour aucun gain.
- **Rotation de clé APK v3 (debug → définitive)** pour éviter la réinstallation de CA19 : possible sur Android ≥ 9
  (la Fire Stick est en Android 11), mais ajoute la clé de debug à la lignée de signature **pour toujours** et
  complique la signature en CI ; pour quelques appareils de test, une réinstallation est moins chère (la spec
  l'accepte). Voir QUESTIONS PRODUIT.

## Impact

**Fichiers upstream modifiés (4, tous marqués FORK)**
- `android/app/build.gradle.kts` : un bloc d'environ 25 lignes ajouté en fin de fichier.
- `android/app/src/main/kotlin/com/edde746/plezy/PlezyActivity.kt` : une ligne.
- `.github/workflows/ci.yml` : une ligne (`-PpopkinoSideload=true`).
- `.github/workflows/build.yml` : lignes déjà FORK (tar → cp, listes de fichiers).
- (+ `README.md`, déjà propre au fork.)

**Nouveaux fichiers** : `android/app/src/sideload/**`, `android/app/src/nosideload/**`,
`android/app/src/sideloadTest/**`, `scripts/fork/test_sideload_isolation.py`, `lib/fork/update/sideload_installer.dart`,
`lib/fork/update/apk_asset.dart` (+ tests `test/fork/update/`), mise à jour de `docs/technique/release.md`.

**Dépendances ajoutées** : aucune (FileProvider, coroutines, `device_info_plus`, `path_provider` déjà là).

**Risques**
- **Google Play** : bloquant si la permission ou le code d'installation arrivaient dans l'AAB ; couvert par la
  bascule unique sûre par défaut, l'échec de build sur `bundle*`, la garde statique et la vérification d'artefact.
  Politiques vérifiées le 2026-11-28 : « Device and Network Abuse » (pas de mise à jour hors Play, pas de
  téléchargement de code exécutable) et la politique `REQUEST_INSTALL_PACKAGES` (auto-mise à jour non admise, retrait
  du manifeste exigé).
- **Amazon** : pas de règle explicite trouvée ; même prudence (build échoue avec `AMAZON` + define).
- **Fire OS** : écran réellement ouvert par `MANAGE_UNKNOWN_APP_SOURCES` à vérifier sur la TV ; bug de liste vide de
  l'automne 2026 (contournement adb) ; redémarrage forcé d'Android 11 au premier octroi (mécanisme de reprise exigé).
- **Plugin Kotlin et `java.srcDir`** : à confirmer par un build (le dex de l'APK GitHub contient
  `SideloadUpdaterPlugin`, celui de l'APK sans define non). Repli : `kotlin.srcDir`.
- **Marque** : rien de visible côté plateforme ; canal et fichiers nommés `popkino`/`sideload`, aucun service Plezy.
- **Performances TV** : inspection sur IO, téléchargement en flux, progression limitée.
- **Fusion upstream** : 1 bloc en fin de Gradle, 1 ligne d'activité, 1 ligne de CI ; le reste dans des dossiers neufs.

## Tests

**Kotlin (JUnit, Robolectric si besoin) — `android/app/src/sideloadTest/kotlin/com/edde746/plezy/fork/sideload/`**
- `ApkDecisionTest` : la décision est une fonction pure (paquet, versionCode, empreintes installées / de l'archive) →
  `invalid`, `wrongPackage`, `signatureMismatch` avant `notNewer`, `ok` ; empreintes de rotation acceptées.
- `UpdatesPathTest` : chemin dans `cacheDir/updates` accepté ; `..`, lien hors dossier, autre extension refusés.
- `InstallResultsTest` : `RESULT_CANCELED` → `cancelled` ; `RESULT_FIRST_USER` + `-7`, `-25`, `-4`, autre code →
  bonne valeur ; `RESULT_OK` → `installed`.
- `InstallPermissionTest` (Robolectric, `@Config(sdk = [25, 30])`) : `canRequestInstalls` selon l'API ; ordre des
  intents essayés et repli sur `ActivityNotFoundException`.
- `SideloadUpdaterPluginTest` : méthode inconnue → `notImplemented` ; second `install` pendant un premier → `busy` ;
  détachement de l'activité → l'appel en attente reçoit une erreur.

**Garde** : `scripts/fork/test_sideload_isolation.py` (§ 9).

**Dart — `test/fork/update/`** : `apk_asset_test.dart` (Fire Stick `[armeabi-v7a, armeabi]` → v7a ; téléphone
`[arm64-v8a, armeabi-v7a]` → arm64 ; arm64 installé sans asset arm64 → aucun ; noms avec et sans version ; tar.gz
ignoré) et `sideload_installer_test.dart` (canal simulé : correspondance de chaque chaîne ; `MissingPluginException`
→ `unavailable`).

**Artefacts**
```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
BT=$(ls -d ~/Library/Android/sdk/build-tools/* | tail -1)
flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true --dart-define-from-file=popkino_secrets.json
$BT/aapt2 dump permissions build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk | grep REQUEST_INSTALL_PACKAGES  # présent
flutter build apk --release --split-per-abi --dart-define-from-file=popkino_secrets.json
$BT/aapt2 dump permissions build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk | grep REQUEST_INSTALL_PACKAGES  # absent
flutter build appbundle --release --dart-define=ENABLE_UPDATE_CHECK=true   # doit échouer (garde-fou)
```

**Manuel sur la Fire TV Stick (192.168.1.173)**
- Préparation : installer un build signé avec la clé définitive et un numéro bas,
  `flutter build apk … --build-name=0.0.1 --build-number=1`, face à une release publiée signée avec la même clé.
- Remise à zéro de l'autorisation entre deux essais :
  `adb shell appops set io.github.adrien24.popkino REQUEST_INSTALL_PACKAGES default`.
- Parcours : autorisation absente → « Ouvrir les réglages » (noter l'écran Fire OS réellement ouvert) → activer →
  Retour (redémarrage attendu sous Android 11) → reprise sans retéléchargement → « Installer » → « Ouvrir » → version
  et comptes Plex + Jellyfin conservés (CA10, CA12) ; « Annuler » dans l'écran système (CA13).
- CA19 : depuis la 0.2.0 actuelle (clé de debug), tenter la mise à jour vers la première release signée avec la clé
  définitive → message dédié, aucun écran d'erreur système.
- CA14 : `adb shell dumpsys diskstats` (tailles de cache par paquet) avant et après une mise à jour.

## Décisions durables proposées (pour `decisions.md`, si le plan les retient)

- **D7 (amendement)** : le manifeste diffère désormais entre canaux, mais **sans flavor** : `ENABLE_UPDATE_CHECK=true`,
  lu aussi par Gradle depuis `dart-defines`, ajoute `src/sideload/` (permission + Kotlin) ; un build `bundle*` ou
  `AMAZON` avec ce define échoue.
- **D13 — Code natif Android du fork** : package `com.edde746.plezy.fork`, enregistré par l'unique appel
  `ForkPlugins.register(flutterEngine)` dans `PlezyActivity` ; le code propre à un canal de distribution vit dans
  un dossier `src/<canal>/` ajouté par le bloc FORK de `build.gradle.kts`.
- **D10 (amendement)** : le numéro de build `N` ne redescend jamais sous le plus grand déjà publié (5) et reste < 1000.

## QUESTIONS PRODUIT

1. **Redémarrage sous Android 11** : sur la Fire Stick, après avoir activé l'autorisation, Popkino redémarre (le
   système le ferme). Au retour, préfères-tu (a) que l'écran d'installation du système s'ouvre tout seul quelques
   secondes après le redémarrage, ou (b) que la fenêtre de mise à jour se rouvre avec un bouton « Installer » ?
   Je recommande (b) : l'utilisateur comprend où il en est.
2. **Si Fire OS n'ouvre pas directement le réglage de Popkino** (écran général « Mon Fire TV » par exemple), la phrase
   d'aide doit-elle indiquer le chemin complet (« Options pour les développeurs > Installer des applis inconnues >
   Popkino ») ? Je recommande oui, affiché seulement dans ce cas.
3. **Passage à la clé définitive (CA19)** : accepter la réinstallation unique (comptes à rajouter) sur tes appareils de
   test, comme le prévoit la spec, plutôt qu'une rotation de clé qui garderait les données mais lierait la clé de debug
   à l'app pour toujours ? Je recommande la réinstallation.
4. **Format des fichiers de release** : remplacer les `.tar.gz` du workflow par des `.apk` nus
   (`popkino-android-<abi>.apk`), comme les releases déjà publiées ? Le README changera ses liens de téléchargement.
