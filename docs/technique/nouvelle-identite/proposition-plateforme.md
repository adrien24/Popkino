# Proposition plateforme — nouvelle-identite

Auteur : architecte-plateforme. Date : 2026-11-26. `docs/technique/decisions.md` n'existe pas encore : aucune décision
antérieure à respecter ; les décisions durables proposées sont regroupées en fin de document (§ 6).

## Compréhension de la spec

Popkino doit être une app distincte de Plezy sur **toutes** les plateformes publiées par GitHub (Android/TV/Fire TV,
Windows, macOS, Linux, iOS ; tvOS en code seulement) : nom, logo provisoire (« P » blanc sur violet), identifiants
définitifs, schéma d'URL, fichiers de release `popkino-…`, mises à jour signées par nos propres clés, aucun service ni
enregistrement du projet Plezy, cohabitation avec Plezy officiel sur le même appareil. Le diff avec l'upstream doit
rester petit et localisé pour continuer à fusionner `edde746/plezy`.

Critères d'acceptation de mon périmètre : CA1 à CA8 (lanceurs, installeurs, cohabitation), CA14 (schéma d'URL, côté
natif), CA15 (retour du lecteur externe : FileProvider Android), CA16 (pas de trafic `plezy.app` / services Plezy, côté
build et appcast), CA18 (ressources natives des icônes alternatives), CA22, CA22b, CA22c, CA22d, CA23 (mises à jour, côté
flux et clés), CA24 à CA27 (dépôt, releases, licence, README).

## 1. Existant (lu dans le code)

### Android
- `android/app/build.gradle.kts` : `namespace` et `applicationId = "com.edde746.plezy"` (l. 290 et 306) ; signature
  release lue depuis `android/key.properties` si présent, sinon clé de debug (l. 338-361) ; variante Amazon par la
  variable d'env. `AMAZON` (`versionCode + 3000`, ABI arm seulement).
- `android/app/src/main/AndroidManifest.xml` : `android:label="Plezy"` (l. 35), `android:banner="@drawable/tv_banner"`,
  `LEANBACK_LAUNCHER` porté par l'alias `.MainActivity` ; schéma `plezy` (l. 76) ; **23 `activity-alias`
  `.appicon.*`** entre marqueurs générés (l. 81-538) ; **deux `authorities` codées en dur**
  `com.edde746.plezy.fileprovider` (l. 541) et `com.edde746.plezy.systemshelf.artwork` (l. 552).
- Kotlin (package `com.edde746.plezy`, à garder) : chaînes en dur `"com.edde746.plezy.fileprovider"`
  (`ExternalPlayerChannel.kt:188`), `AUTHORITY = "com.edde746.plezy.systemshelf.artwork"`
  (`watchnext/SystemShelfArtworkProvider.kt:25`), schéma `"plezy"` (`deeplink/DeepLinkPlugin.kt:18`,
  `watchnext/WatchNextProvider.kt:460` et `:743`).
- Ressources : icône adaptative vectorielle `res/drawable/ic_launcher_foreground.xml` + `ic_launcher_monochrome.xml`,
  fond `@color/ic_launcher_background` (`values/colors.xml`, blanc), icône héritée `mipmap-xxxhdpi/ic_launcher.png`
  (192 px, API 25), bannière `drawable-xxxhdpi/tv_banner.png` (640×360), `drawable-*/ic_stat_notification.png`
  (générées par `scripts/codegen/generate_android_icons.sh` depuis `assets/plezy.svg`), splash `drawable/splash_icon.xml`
  (réutilise le foreground). Les 23 icônes alternatives (`*_<id>_*.webp`, `mipmap-anydpi-v26/ic_launcher_<id>.xml`)
  sont générées par `scripts/codegen/generate_app_icons.py` depuis `assets/app_icons/source/`.
- `.gitignore` Android exclut déjà `key.properties`, `*.jks`, `*.keystore`.

### Apple
- iOS : `ios/Runner.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER = com.edde746.plezy` (×3),
  `INFOPLIST_KEY_CFBundleDisplayName = Plezy` (×3), `PRODUCT_NAME = Plezy` (×3), `ASSETCATALOG_COMPILER_APPICON_NAME =
  plezy` (icône au format Icon Composer `ios/plezy.icon/`, SVG `Assets/plezy-cropped.svg` + `icon.json`) ;
  `ios/Runner/Info.plist` → `CFBundleDisplayName`/`CFBundleName` « Plezy », `CFBundleURLName com.edde746.plezy`, schéma
  `plezy`, deux textes de permission qui citent « Plezy » (l. 64 et 66, visibles dans les demandes d'autorisation).
  `ios/Runner/AlternateAppIcons.xcassets` : 23 icônes alternatives.
- macOS : `macos/Runner/Configs/AppInfo.xcconfig` → `PRODUCT_NAME = Plezy`, `PRODUCT_BUNDLE_IDENTIFIER`,
  `PRODUCT_COPYRIGHT` ; `macos/Runner/Info.plist` → schéma, `SUFeedURL =
  https://cdn.jsdelivr.net/gh/edde746/plezy@appcast/appcast.xml`, `SUPublicEDKey` de Plezy ; icône `macos/plezy.icon/`
  (identique à celle d'iOS). Le menu (`MainMenu.xib`, `APP_NAME`) dépend du nom du bundle.
- tvOS : bundle `com.edde746.plezy`, extension `com.edde746.plezy.TopShelfExtension`, App Group
  `group.com.edde746.plezy` (2 entitlements + 3 constantes Swift : `TopShelfProvider.swift:7`,
  `ShelfSources.swift:86`, `SystemShelfPlugin.swift:269`), schéma `plezy` (`TopShelfProvider.swift:260`, Info.plist),
  icône en image stacks (`AppIcon.brandassets` : 400×240, 800×480, 1280×768, top shelf 1920×720 et 2320×720 @1x/@2x).

### Windows
- `windows/CMakeLists.txt:102` `BINARY_NAME "plezy"` → `plezy.exe`.
- `windows/runner/Runner.rc` : `CompanyName "com.edde746"`, `ProductName/FileDescription "Plezy"`, clé publique
  WinSparkle `EdDSAPub` de Plezy (l. 114). **`path_provider` dérive `%APPDATA%\<CompanyName>\<ProductName>` de ces
  champs** : tant qu'ils valent ceux de Plezy, les deux apps partagent réglages et base.
- `windows/runner/main.cpp:19-21` : mutex d'instance unique `com.edde746.Plezy.SingleInstance` + `FindWindow(…, L"Plezy")`
  → **lancer Popkino pendant que Plezy tourne activerait Plezy et quitterait Popkino** ; titre de fenêtre l. 70.
- `windows/runner/flutter_window.cpp:9` : clé registre `Software\\Plezy` (placement de fenêtre partagé).
- `windows/build-installer.ps1` (Inno Setup) : `AppId` GUID `4213385e-…` (**le même AppId ferait installer Popkino par
  dessus Plezy**), `Name "Plezy"`, `Publisher "edde746"`, `ExeName`, `OutputBaseFilename=plezy-windows-installer`, message
  d'élévation avec l'URL `edde746/plezy`.
- `windows/build-msix.ps1` : identité Microsoft Store réservée par edde746 (`edde746.Plezy`), inutilisable par nous.
- `windows/runner/resources/app_icon.ico` (une seule taille, 48 px).

### Linux
- `linux/CMakeLists.txt` : `BINARY_NAME "plezy"`, `APPLICATION_ID "com.edde746.plezy"` (id GTK/Wayland, et répertoire de
  données via `path_provider`) ; `linux/runner/my_application.cc:68,72` : titres « Plezy ».
- `linux/packaging/` : `com.edde746.plezy.desktop` (Name, Exec, Icon), `plezy.sh` (`/opt/plezy`), `build-packages.py`
  (paquet `plezy`, `/opt/plezy`, `/usr/bin/plezy`, icônes `plezy.png`), `after-install.sh`/`after-remove.sh`,
  `build-appimage.sh`, `build-flatpak.py` + `flatpak/com.edde746.plezy.{json,metainfo.xml}` (dont
  `--own-name=org.mpris.MediaPlayer2.com_edde746_plezy`), scripts `check-*.py`. Icônes produites depuis
  `assets/plezy.png`. **Paquets deb/rpm/pacman de même nom et mêmes chemins que Plezy : cohabitation impossible.**

### CI et dépôt
- `.github/workflows/build.yml` (manuel, `main` seulement) : `RELEASE_DART_DEFINES` (l. 36) avec `ENABLE_UPDATE_CHECK=true`,
  `ENABLE_SENTRY` **déjà conditionné à `github.repository == 'edde746/plezy'`**, `ENABLE_DONATIONS=true` ;
  `SUPPORTER_MODE` par job (`unlocked` macOS/Linux, `msstore` Windows, absent Android/iOS) ; signature Android par les
  secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` ; envoi des
  symboles vers `bugs.plezy.app` **déjà conditionné au dépôt edde746** ; macOS : import de certificat Developer ID,
  signature, notarisation **sans condition** (échouent sans compte Apple) ; Sparkle/WinSparkle signés par
  `SPARKLE_PRIVATE_KEY` (une seule clé Ed25519 pour les deux) ; MSIX Store ; appcast généré dans `create-release` avec
  des URL `edde746/plezy` et `sparkle:releaseNotesLink` vers **`gh-html.edde746.dev`** (service du mainteneur de Plezy) ;
  ~60 noms `plezy-…`. Le runner iOS `xcode-27` est une image GitHub hébergée (GA depuis le 2026-10-15) : OK pour le fork.
- `.github/workflows/update-packages.yml` (sur release publiée) : `update-winget` (identifiant `edde746.Plezy`, secret
  `WINGET_TOKEN`) et `update-appcast-branch` (pousse `appcast.xml` sur la branche orpheline `appcast`, lue via jsDelivr).
- `.github/workflows/ci.yml` : sur push/PR ; job optionnel de paquets Linux avec des noms `plezy-linux-x64.*`.
- Gardes upstream lancées par `scripts/ci_guard_checks.sh` (CI + hook pre-commit) qui figent des noms :
  `check_build_workflow.py:59` (`sign_update plezy-windows-installer.exe`), `check_windows_installer.py:65`
  (`OutputBaseFilename=plezy-windows-installer`). Ce script exécute aussi **tout `scripts/*/test_*.py`**.
- `.github/FUNDING.yml` (`github: edde746`, `liberapay: edde746`), README Plezy (badges des stores Plezy), `ISSUE_TEMPLATE`
  avec liens Plezy. Le dépôt `adrien24/plezy` est un fork GitHub public, Actions activées, aucun secret défini.
- `lib/services/update_service.dart:18-19` : `_githubRepo = 'edde746/plezy'`, `_feedUrl` jsDelivr de Plezy (fichier Dart,
  périmètre app ; valeurs fixées ici).
- `pubspec.yaml` : `version: 2.26.0+160` ; `create-release` exige tag = version du pubspec.

## 2. Identité cible (table de référence commune aux deux architectes)

| Élément | Valeur proposée |
|---|---|
| Nom affiché | `Popkino` |
| Identifiant d'app (Android `applicationId`, bundle iOS/macOS/tvOS, `APPLICATION_ID` Linux, id Flatpak) | **`io.github.adrien24.popkino`** |
| Extension tvOS / App Group | `io.github.adrien24.popkino.TopShelfExtension` / `group.io.github.adrien24.popkino` |
| Authorities Android | `${applicationId}.fileprovider`, `${applicationId}.systemshelf.artwork` |
| Schéma d'URL | `popkino://` |
| Dépôt / releases | `adrien24/popkino`, tags `X.Y.Z` |
| Flux de mise à jour (Sparkle/WinSparkle) | `https://cdn.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml` |
| Windows : exe / CompanyName / ProductName | `popkino.exe` / `io.github.adrien24` / `Popkino` → données dans `%APPDATA%\io.github.adrien24\Popkino` |
| Windows : Inno `AppId` | `1349c251-d469-4cab-87df-a2a01d3ccd68` (généré pour Popkino, à ne jamais changer) |
| Windows : mutex d'instance | `io.github.adrien24.popkino.SingleInstance` |
| Linux : paquet / commande / dossier | `popkino` / `/usr/bin/popkino` / `/opt/popkino` ; desktop `io.github.adrien24.popkino.desktop` |
| Fichiers de release | `popkino-android-<abi>.tar.gz`, `popkino-ios.ipa`, `popkino-macos.dmg`, `popkino-windows-installer.exe`, `popkino-windows-<arch>-portable.7z`, `popkino-linux-<arch>.{tar.gz,deb,rpm,pkg.tar.zst,flatpak,AppImage,AppImage.zsync}`, `appcast.xml` |
| Couleur provisoire | violet `#6D28D9`, « P » blanc |

### Pourquoi `io.github.adrien24.popkino`

- **Définitif et vérifiable** : la spec impose un identifiant qui ne changera plus. La convention « domaine inversé »
  suppose de posséder le domaine ; `popkino.com` est pris, `popkino.app` n'est pas acheté. `io.github.<compte>` est
  prouvable par le compte GitHub (c'est la convention exigée par Flathub pour les apps sans domaine). `app.popkino`
  deviendrait trompeur si un tiers achetait `popkino.app`.
- **Google Play / Amazon** : aucune contrainte de domaine, seulement l'unicité ; ce nom est libre. Le même id sert la
  version GitHub et la future version store (spec).
- **Vérification des développeurs Android** (en vigueur depuis le 2026-09-30 dans 4 pays, mondiale en 2027) : il faudra
  enregistrer le nom de package et l'empreinte SHA-256 de la clé de signature ; un nom déjà utilisé par un autre
  développeur n'est « pas éligible ». Un id neuf, signé dès la première release par notre clé, est donc la bonne voie.
  Pour la distribution hors Play, l'obligation ne vise que téléphones et tablettes ; la TV n'est pas concernée, mais
  l'APK GitHub sert aussi aux téléphones (CA2).
- Apple accepte ce format tel quel ; tvOS, iOS et macOS gardent le même id, comme chez Plezy (achat universel possible
  plus tard).
- Inconvénient : l'id contient le pseudo GitHub, déjà public via l'URL du dépôt. Si un nom de domaine est acheté avant
  la première release, `app.popkino` reste possible (voir QUESTIONS PRODUIT) ; après, c'est figé.

## 3. Approche proposée

### 3.1 Principe : éditions en place, petites, marquées, et une garde automatique

1. **Identifiants et noms visibles modifiés directement dans les fichiers upstream**, ligne par ligne, avec un marqueur
   `FORK:` là où le format accepte un commentaire (`// FORK:` Kotlin/Swift/C++/Dart/Gradle, `# FORK:` YAML/Python/shell/
   CMake/PowerShell, `<!-- FORK: -->` XML/plist). Le pbxproj (Xcode réécrit le fichier), le JSON et les binaires ne
   prennent pas de marqueur : ils sont couverts par la garde (point 3).
2. **Les chemins internes restent ceux de Plezy** (autorisé par `TRADEMARKS.md`) pour éviter des cascades de
   modifications : `assets/plezy.png`, `assets/plezy.svg`, `assets/plezy_adaptive_foreground.svg`, `ios/plezy.icon`,
   `macos/plezy.icon`, `tv_banner.png`, `ic_launcher_*`, package Kotlin, `PlezyActivity`, binaire Linux `plezy` dans
   `/opt/popkino`. **On remplace le contenu des images, pas leur nom** : l'écran « À propos », l'écran de connexion,
   le splash Flutter, les paquets Linux, l'AppImage et le Flatpak prennent le nouveau logo sans changer une ligne de
   code.
3. **Garde d'identité** `scripts/fork/check_identity.py` (nouveau) : liste de règles (fichier ou motif de fichiers,
   expression interdite, message) sur les seuls fichiers qui finissent dans un livrable ou une release :
   `com.edde746.plezy` hors package Kotlin/`namespace`, `group.com.edde746`, `scheme="plezy"` / `<string>plezy</string>`
   dans les plist, `android:label="Plezy"`, `plezy-` dans les noms d'artefacts des workflows et scripts de packaging,
   `edde746/plezy` dans les URL de release/flux, `gh-html.edde746.dev`, la clé publique Sparkle de Plezy
   (`q7t6eu1t…`), le GUID Inno `4213385e-…`, `ice.plezy.app`/`bugs.plezy.app`/`liberapay` dans `lib/` (règles côté Dart
   à compléter par l'architecte-app), et la présence attendue des valeurs du § 2. Son test
   `scripts/fork/test_check_identity.py` vérifie les règles **et lance la garde sur le dépôt réel**. Comme
   `scripts/ci_guard_checks.sh` exécute déjà tous les `scripts/*/test_*.py`, la garde tourne dans `ci.yml` et dans le
   hook pre-commit **sans modifier aucun workflow**. Après chaque fusion upstream, une nouvelle occurrence de Plezy
   (nouvel artefact, nouvelle plateforme) fait échouer la CI au lieu de partir en release.

### 3.2 Android

| Fichier | Changement |
|---|---|
| `android/app/build.gradle.kts` | `applicationId = "io.github.adrien24.popkino" // FORK:` ; `namespace` inchangé. `buildFeatures { buildConfig = true }` si `BuildConfig` n'est pas déjà généré (à vérifier au build). |
| `AndroidManifest.xml` | `android:label="Popkino"` ; `<data android:scheme="popkino"/>` ; `android:authorities="${applicationId}.fileprovider"` et `"${applicationId}.systemshelf.artwork"` ; bloc d'alias généré **vidé** (marqueurs conservés, `.MainActivity` intact). |
| `ExternalPlayerChannel.kt:188` | `"${activity.packageName}.fileprovider"` (CA15 : sinon `getUriForFile` lève une exception, l'autorité n'existant plus). |
| `SystemShelfArtworkProvider.kt:25` | `AUTHORITY = "${BuildConfig.APPLICATION_ID}.systemshelf.artwork"`. |
| `DeepLinkPlugin.kt:18`, `WatchNextProvider.kt:460,743` | schéma `popkino`. |
| `res/values/colors.xml` | `ic_launcher_background` → `#6D28D9`. |
| Ressources | remplacées par le générateur (§ 3.8) ; ressources des 23 icônes alternatives supprimées. |

Sans les deux `authorities` dérivées de `applicationId`, l'installation de Popkino à côté de Plezy échoue
(`INSTALL_FAILED_CONFLICTING_PROVIDER`) : c'est un **prérequis de CA8**, pas une option. Ce changement est générique ; je
propose de l'envoyer en PR upstream (« dériver les authorities de applicationId ») : s'il est accepté, notre diff
Android se réduit encore.

Signature : **aucun changement de code ni de workflow**. On réutilise les noms de secrets de l'upstream. Clé à générer
une fois par l'utilisateur :

```
keytool -genkeypair -v -storetype PKCS12 -keystore popkino-release.jks -alias popkino \
  -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Popkino"
```

- RSA 4096 : au-dessus du minimum de Play App Signing (RSA 2048). PKCS12 : **même mot de passe** pour le magasin et la
  clé (`ANDROID_STORE_PASSWORD` = `ANDROID_KEY_PASSWORD`).
- Cette clé est la **clé de signature de l'app**. Le jour de `publication-stores`, on pourra la fournir à Play App
  Signing (« Change key », clé importée) pour que l'APK GitHub et la version Play aient la même signature, avec une clé
  d'importation séparée ; décision reportée à ce sujet, mais la clé générée maintenant le permet.
- Secrets : `base64 -i popkino-release.jks | gh secret set ANDROID_KEYSTORE_BASE64 -R adrien24/popkino`, puis les trois
  autres. Sauvegarde hors GitHub (gestionnaire de mots de passe + copie chiffrée). Local : `android/key.properties` avec
  `storeFile=` en chemin absolu hors du dépôt (déjà ignoré par git).
- L'empreinte SHA-256 du certificat est publiée dans le README (vérification par `apksigner verify --print-certs`) et
  servira à l'enregistrement du package (vérification des développeurs).

### 3.3 Apple

- **iOS** (pbxproj + `Info.plist`) : `PRODUCT_BUNDLE_IDENTIFIER` (×3) et `INFOPLIST_KEY_CFBundleDisplayName` (×3) ;
  `CFBundleDisplayName`, `CFBundleName`, `CFBundleURLName`, schéma, et les deux textes de permission (« Popkino uses… »).
  **`PRODUCT_NAME` reste `Plezy`** : sur iOS le nom de l'exécutable n'est jamais affiché, et le garder évite 3 lignes
  de pbxproj et le chemin `build/ios/iphoneos/Plezy.app` du workflow. `DEVELOPMENT_TEAM` de Plezy laissé tel quel (sans
  effet en `--no-codesign`, à revoir à `publication-stores`). `AlternateAppIcons.xcassets` vidé (on garde le dossier et
  son `Contents.json` : il est référencé par le pbxproj).
- **macOS** (`AppInfo.xcconfig`, 3 lignes) : `PRODUCT_NAME = Popkino` (nom du `.app` dans le Finder, du processus et du
  menu « À propos de Popkino / Quitter Popkino », CA5), `PRODUCT_BUNDLE_IDENTIFIER`, `PRODUCT_COPYRIGHT = Copyright ©
  2025 edde746 (Plezy), 2026 adrien24 (Popkino)`. `Info.plist` : schéma, `CFBundleURLName`, `SUFeedURL`, `SUPublicEDKey`.
- **tvOS** : bundle, extension, App Group (2 entitlements + 3 constantes Swift), nom, schéma (Info.plist +
  `TopShelfProvider.swift:260`), tests Swift qui citent `plezy://`, image stacks régénérées. Pas de release.
- Icône iOS/macOS : on remplace `plezy.icon/Assets/plezy-cropped.svg` par le « P » et le `fill` de `icon.json` par le
  violet ; le nom `plezy` de l'icône reste (aucun changement de pbxproj). Xcode 26+ en déduit aussi les icônes des
  anciens macOS.

### 3.4 Windows

- `windows/CMakeLists.txt` : `BINARY_NAME "popkino"` (l'exe est la cible des raccourcis, visible dans le Gestionnaire
  des tâches et le dossier d'installation) ; `project(plezy)` inchangé.
- `Runner.rc` : `CompanyName "io.github.adrien24"`, `FileDescription`/`InternalName`/`ProductName "Popkino"`,
  `OriginalFilename "popkino.exe"`, `LegalCopyright` (crédits Plezy conservés + GPL-3.0), **nouvelle** `EdDSAPub`. Le
  changement de `CompanyName`/`ProductName` sépare aussi les données (`path_provider`) et le registre WinSparkle.
- `main.cpp` : mutex `io.github.adrien24.popkino.SingleInstance`, `FindWindow(…, L"Popkino")`, titre `L"Popkino"`.
- `flutter_window.cpp:9` : `Software\\Popkino`.
- `build-installer.ps1` : `AppId` `1349c251-d469-4cab-87df-a2a01d3ccd68`, `Name "Popkino"`, `Publisher` (voir QUESTIONS
  PRODUIT), `ExeName "popkino.exe"`, `OutputBaseFilename=popkino-windows-installer`, noms des portables, URL du message
  d'élévation vers `adrien24/popkino`.
- **MSIX non produit** : l'identité Store (`edde746.Plezy`) appartient à Plezy et le paquet n'est pas publié sur GitHub.
  Les trois étapes MSIX de `build.yml` prennent `if: github.repository == 'edde746/plezy'` ; `build-msix.ps1` et
  `windows/msix/` restent intacts (non distribués).
- `app_icon.ico` régénéré en multi-tailles (16 à 256 px).

### 3.5 Linux

Changements limités à ce qui est visible ou entre en collision avec un paquet Plezy installé :
- `linux/CMakeLists.txt` : `APPLICATION_ID "io.github.adrien24.popkino"` (id Wayland/GTK et dossier de données) ;
  `BINARY_NAME` reste `plezy` (binaire interne dans `/opt/popkino`, jamais dans le `PATH` ; le renommer obligerait à
  modifier les cibles CMake de `ci.yml`, les scripts `check-*` et le Flatpak pour un fichier invisible).
- `my_application.cc:68,72` : titres « Popkino ».
- Desktop : `git mv` vers `io.github.adrien24.popkino.desktop` ; `Name=Popkino`, `Exec=popkino`, `Icon=popkino`,
  `StartupWMClass=io.github.adrien24.popkino`, `Comment` sans « Plezy » (« pour Plex » autorisé).
- `build-packages.py`, `plezy.sh` (chemin `/opt/popkino`), `after-install.sh`, `after-remove.sh`, `build-appimage.sh`,
  `build-flatpak.py`, `flatpak/*.json` et `*.metainfo.xml` (renommés `io.github.adrien24.popkino.*`, nom, URL, développeur,
  `--own-name` MPRIS à aligner sur le nom réellement publié par le plugin), `check-flatpak.py`, `check-package-deps.py` :
  nom de paquet `popkino`, chemins, fichiers de sortie `popkino-linux-*`.
- On garde les six formats de Plezy (tar.gz, deb, rpm, pacman, Flatpak, AppImage) : même coût de renommage par format,
  et l'AppImage se met à jour seule via `github.repository` (déjà paramétré).

### 3.6 CI (`build.yml`, `update-packages.yml`, `ci.yml`)

`build.yml` :
- `RELEASE_DART_DEFINES` (une ligne) : retirer `ENABLE_DONATIONS=true` ; garder `ENABLE_UPDATE_CHECK=true` (versions
  GitHub) ; laisser `ENABLE_SENTRY` (inerte hors `edde746/plezy`) ; ajouter `--dart-define=SUPPORTER_MODE=unlocked` et
  les identifiants des services : `--dart-define=TRAKT_CLIENT_ID=${{ secrets.TRAKT_CLIENT_ID }}`, `TRAKT_CLIENT_SECRET`,
  `SIMKL_CLIENT_ID`, `MDBLIST_CLIENT_ID` (noms à confirmer par l'architecte-app ; secret vide = service absent, CA19f).
  Les `SUPPORTER_MODE` par job (macOS, Windows, Linux) sont retirés pour n'avoir qu'une valeur.
  Justification d'un ajout à la variable commune : diff d'une ligne ; ces valeurs finissent de toute façon dans le
  binaire (spec) ; GitHub masque les secrets dans les journaux ; le workflow ne tourne que sur `main` et en
  `workflow_dispatch` (jamais sur une PR externe).
- Noms d'artefacts `plezy-…` → `popkino-…` dans les jobs, `attest`, `upload-artifact` et `create-release` ; `Plezy.app`
  → `Popkino.app` (macOS) ; `-volname "Popkino"` ; `plezy.exe`/`plezy.lib`/`plezy.exp` → `popkino.*` dans la vérification
  du bundle Windows ; `plezy-ios.ipa` (le `.app` source reste `Plezy.app`, cf. § 3.3).
- macOS sans compte Apple : job-level `env: MACOS_SIGNING: ${{ secrets.MACOS_CERTIFICATE_BASE64 != '' && 'developer-id'
  || 'adhoc' }}` et `if: env.MACOS_SIGNING == 'developer-id'` sur « Import Code Signing Certificate », « Sign
  Application », « Verify Signature », « Notarize Application ». La sortie de `flutter build macos` est déjà signée
  ad hoc (`CODE_SIGN_IDENTITY = "-"`, aucun certificat sur le runner au moment du build), ce que Sparkle accepte avec
  la signature EdDSA. Le jour où un compte Apple existe, il suffit d'ajouter les secrets.
- Appcast (`create-release`) : titre « Popkino Updates » ; **suppression de `sparkle:releaseNotesLink`** (pointe vers
  `gh-html.edde746.dev`, service du mainteneur de Plezy) ; URL des `enclosure` construites avec
  `https://github.com/${GITHUB_REPOSITORY}/releases/download/…` (plus de dépôt en dur, modification réutilisable
  upstream).
- MSIX : 3 étapes conditionnées (§ 3.4), `plezy-windows.msixbundle` retiré de la liste `attest`.
- Gardes upstream à mettre à jour en même temps (sinon `ci.yml` et le pre-commit échouent) :
  `scripts/checks/check_build_workflow.py:59` et `scripts/checks/check_windows_installer.py:65` (nom du fichier
  d'installation).

`update-packages.yml` : `update-winget` prend `if: github.repository == 'edde746/plezy'` (une ligne ; sans
`WINGET_TOKEN` il échouerait, et la publication winget est hors périmètre). `update-appcast-branch` fonctionne tel quel
sur notre dépôt.

`ci.yml` : seules les lignes du job optionnel de paquets Linux (`plezy-linux-x64.*`) sont renommées.

Non modifiés : `upload-symbols` (déjà conditionnés au dépôt edde746), `.github/actions/`, `dependabot.yml` (les mises à
jour de version Dependabot sont désactivées par défaut sur un fork GitHub ; ne pas les activer, elles créeraient des
conflits avec les mêmes montées de version upstream).

Secrets GitHub du dépôt (aucun n'existe aujourd'hui) :

| Secret | Usage | Obligatoire |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` | signature APK | oui (sinon le job Android échoue, ce qui est voulu) |
| `SPARKLE_PRIVATE_KEY` | signature EdDSA du DMG et de l'installeur Windows (une clé pour les deux, comme l'upstream) | oui pour CA22b |
| `TRAKT_CLIENT_ID`, `TRAKT_CLIENT_SECRET`, `SIMKL_CLIENT_ID`, `MDBLIST_CLIENT_ID` | services de suivi | non (service absent si vide) |
| `MACOS_CERTIFICATE_*`, `APPLE_*`, `KEYCHAIN_PASSWORD`, `BUGS_ADMIN_TOKEN`, `WINGET_TOKEN` | — | **ne pas créer** |

### 3.7 Mises à jour Windows/macOS

- **Hébergement du flux : même mécanisme que l'upstream** (fichier `appcast.xml` attaché à la release, recopié sur la
  branche orpheline `appcast` à la publication, servi par jsDelivr). Zéro nouveau workflow ; le flux ne change qu'à la
  publication d'une release non préliminaire, et un brouillon incomplet ne casse jamais le flux en place.
- Clés : une paire Ed25519 générée par l'utilisateur sur son Mac avec l'outil du paquet (`dart run
  auto_updater:generate_keys`, qui s'appuie sur `generate_keys` de Sparkle), clé privée exportée et rangée dans
  `SPARKLE_PRIVATE_KEY` au **même format que celui attendu par les deux étapes de signature existantes** (à valider en
  signant localement un fichier avec les deux commandes du workflow avant de pousser le secret) ; clé publique copiée
  dans `macos/Runner/Info.plist` (`SUPublicEDKey`) et `windows/runner/Runner.rc` (`EdDSAPub`). La garde interdit la clé
  publique de Plezy : un fichier signé par Plezy est alors refusé (CA22c).
- Versions portables Windows et installations Homebrew/winget : comportement upstream inchangé (`UpdateService` :
  pas de WinSparkle sans `unins000.exe`), donc lien GitHub seulement (CA22d).
- Android : inchangé côté natif ; `UpdateService` interroge `api.github.com/repos/adrien24/popkino/releases/latest` (CA22).

### 3.8 Logo provisoire et générateur reproductible

Nouveaux fichiers :
- `branding/brand.json` : nom, couleur de fond `#6D28D9`, couleur du signe `#FFFFFF`, texte de la bannière.
- `branding/mark.svg` : le « P » en **tracé géométrique** (pas de police : rendu identique sur toute machine), canevas
  1024, dans la zone sûre de 61 % des icônes adaptatives. Optionnels pour le logo définitif : `background.svg`,
  `monochrome.svg`, `banner.svg` (bannière dessinée à la main, prioritaire sur la bannière composée).
- `scripts/fork/generate_brand_assets.py` : un seul script, outils déjà exigés par les générateurs upstream
  (`rsvg-convert`, ImageMagick 7, `cwebp`), idempotent, qui écrit :

| Cible | Fichiers |
|---|---|
| Flutter (logo dans l'app, README, paquets Linux) | `assets/plezy.png`, `assets/plezy.svg`, `assets/plezy_adaptive_foreground.svg` (contenu remplacé, noms gardés) |
| Android | `drawable/ic_launcher_foreground.xml` et `ic_launcher_monochrome.xml` (VectorDrawable produits depuis le tracé SVG), `mipmap-xxxhdpi/ic_launcher.png` (192 px, API 25), `drawable-xxxhdpi/tv_banner.png` (640×360 : signe + « Popkino » rendu avec `assets/go-noto-current-regular.ttf`, police OFL déjà dans le dépôt ; Google demande le nom de l'app dans la bannière TV), `drawable-*/ic_stat_notification.png` (5 densités) |
| iOS / macOS | `ios/plezy.icon/` et `macos/plezy.icon/` (SVG + `fill` de `icon.json`) |
| tvOS | image stacks `App Icon` (400×240, 800×480), `App Icon - App Store` (1280×768), top shelf (1920×720, 2320×720, 4640×1440) |
| Windows | `windows/runner/resources/app_icon.ico` (16-256 px) |

  Remplacer le logo provisoire par le définitif = remplacer `branding/mark.svg` (et éventuellement les SVG optionnels),
  relancer le script, committer. Aucune autre modification.
- Icônes alternatives : `git rm` de `assets/app_icons/source/`, des 23 jeux de ressources Android
  (`*_<id>_*`, `ic_launcher_<id>.*`), des `AppIcon-<id>` iOS et tvOS ; bloc généré du manifeste et de
  `tvos/Runner/Info.plist` vidés (marqueurs gardés). Le catalogue Dart, l'écran de choix et `assets/app_icons/previews/`
  (déclaré dans `pubspec.yaml`) relèvent de l'architecte-app : à faire dans la même tâche pour que le build reste vert.
- `generate_app_icons.py` et `generate_android_icons.sh` upstream ne sont plus lancés dans le fork (le premier
  échouerait sans sources ; le second utilise `declare -A`, absent du bash 3.2 de macOS).

### 3.9 Dépôt, GPL et marque

- `README.md` réécrit pour Popkino : « basé sur Plezy, projet indépendant non affilié », lien vers `TRADEMARKS.md` et vers
  le dépôt d'origine comme source, aucun badge ni lien de téléchargement Plezy, tableau des fichiers `popkino-…` (liens
  `releases/latest/download/…`), section « Installer sans signature » (CA27 : SmartScreen Windows, « Ouvrir quand même »
  dans Réglages > Confidentialité et sécurité ou `xattr -dr com.apple.quarantine` sur Mac, sideload iOS avec AltStore/
  Sideloadly et la limite de 7 jours), empreinte SHA-256 de la clé Android.
- `NOTICE.md` (nouveau, CA25) : Popkino est une version modifiée de Plezy (© 2025 edde746 et contributeurs, GPL-3.0),
  modifiée depuis le 2026-11-26 ; les fichiers upstream modifiés portent un marqueur `FORK:` ou figurent dans
  `scripts/fork/check_identity.py`, l'historique git public fait foi. `LICENSE` et `TRADEMARKS.md` inchangés.
- `.github/FUNDING.yml` supprimé (CA24) ; liens de `.github/ISSUE_TEMPLATE/config.yml` pointés vers le fork. Si les
  « Issues » restent désactivées sur le fork, ce fichier est sans effet (voir QUESTIONS PRODUIT).
- Chaque release correspond déjà à un tag (`create-release` crée le tag sur `github.sha` et vérifie tag = version du
  pubspec) : rien à ajouter pour « une source par release ».
- `.gitattributes` : ajouter `README.md merge=ours` et `.github/FUNDING.yml merge=ours`, avec
  `scripts/fork/setup_merge.sh` qui fait `git config merge.ours.driver true`. Sans cette configuration, git retombe sur
  la fusion normale : l'ajout est sans risque.

### 3.10 Version de l'app

Popkino est une nouvelle app (nouvel id) : elle prend **sa propre version**, par exemple `1.0.0+1`, incrémentée à
chaque release du fork. Garder la numérotation de Plezy créerait des collisions (un correctif du fork en `2.26.1`
entrerait en conflit avec le futur `2.26.1` de Plezy) et ferait mentir la comparaison de versions de l'`UpdateService`.
Coût : la ligne `version:` de `pubspec.yaml` est en conflit à chaque montée de version upstream ; résolution mécanique
(garder la nôtre), décrite dans la procédure de fusion.

### 3.11 Procédure de fusion upstream (à écrire dans `docs/technique/fusion-upstream.md`)

`git fetch upstream && git merge upstream/main` → conflits attendus uniquement sur les lignes marquées : garder la
valeur Popkino, accepter le reste. Conflits binaires sur les images remplacées : garder les nôtres puis relancer
`scripts/fork/generate_brand_assets.py`. Puis `bash scripts/ci_guard_checks.sh` (inclut la garde d'identité) et un
build APK.

### 3.12 Interfaces avec l'architecte-app (à aligner au débat)

Je fixe les valeurs ; l'architecte-app fait les éditions Dart : `UpdateService._githubRepo` / `_feedUrl` (§ 2),
`DeepLink.scheme = 'popkino'` et le parseur des liens du lecteur externe (CA14/CA15, doit concorder avec le natif),
noms de client Plex/Jellyfin, `LanDiscoveryService` `'app'`, noms des `--dart-define` des services, défaut de
`SUPPORTER_MODE` si on veut aussi les thèmes gratuits dans les builds locaux, suppression du sélecteur d'icônes et de
l'entrée `assets/app_icons/previews/` du `pubspec.yaml`, règles Dart de la garde, téléchargement des correspondances
d'anime (`github.com/edde746/anime-mappings`) à couper avec MAL/AniList.

## 4. Alternatives écartées

- **Renommer au moment du build** (fichiers upstream intacts, un script réécrit l'identité en CI) : zéro conflit de
  fusion, mais le code testé n'est plus celui qui est livré, les builds locaux (`flutter build apk` de
  `conventions-code`) sortent en `com.edde746.plezy` et entrent en collision avec Plezy sur la TV, les workflows ne
  peuvent pas se réécrire eux-mêmes, et une ligne upstream modifiée ne casse qu'au moment de la release.
- **Script d'application d'un tableau de remplacements** (comme ci-dessus mais résultat committé) : utile pour
  résoudre les conflits, mais c'est une deuxième source de vérité à maintenir pour une quarantaine de lignes ; la garde
  seule détecte les oublis à moindre coût.
- **`flutter_launcher_icons`** : ne gère ni la bannière Android TV, ni les image stacks tvOS, ni le format Icon Composer
  (`.icon`) déjà utilisé, ni Linux ; ajoute une dépendance au `pubspec.yaml` et `pubspec.lock` ; réécrit lui-même
  manifeste, Info.plist et projets Xcode (diff non maîtrisé).
- **Nouveau workflow `popkino-release.yml`** à la place de `build.yml` : moins de conflits, mais il ne suivrait plus les
  évolutions upstream (version de Flutter, moteur Windows patché, libmpv, nouvelles étapes) ; on dériverait
  silencieusement vers des builds cassés.
- **Flavors Gradle** (`github` / `play`) : inutile tant que la bascule `ENABLE_UPDATE_CHECK` suffit (`regles-fork` §3) ;
  à reconsidérer à `publication-stores` seulement si le manifeste doit différer.
- **Flux de mise à jour via `releases/latest/download/appcast.xml`** : supprime la branche `appcast`, mais un brouillon
  publié sans appcast rendrait le flux introuvable ; le mécanisme upstream est éprouvé et ne coûte aucune ligne.
- **Réduire les formats Linux** : économiserait quelques lignes mais supprimer des étapes est aussi un diff, et ce serait
  une régression par rapport à Plezy.
- **Renommer aussi le binaire Linux** : rien de visible en plus, une dizaine de lignes de plus dans `ci.yml` et les
  scripts de vérification.
- **`app.popkino` comme identifiant** sans posséder le domaine : risque de confusion si un tiers l'achète (voir § 2).

## 5. Impact

### Fichiers upstream modifiés (estimation : ~45 fichiers texte, ~170 lignes, plus des images remplacées)
- Android : `build.gradle.kts` (1-2), `AndroidManifest.xml` (5 + bloc d'alias vidé), 4 fichiers Kotlin (5),
  `colors.xml` (1).
- Apple : `ios/Runner.xcodeproj/project.pbxproj` (6), `ios/Runner/Info.plist` (6), `macos/Runner/Configs/AppInfo.xcconfig`
  (3), `macos/Runner/Info.plist` (4), `tvos/Runner.xcodeproj/project.pbxproj` (~6), `tvos/Runner/Info.plist` (4 + bloc
  vidé), 2 entitlements, 3 fichiers Swift + 2 tests Swift tvOS, `plezy.icon/icon.json` (×2).
- Windows : `CMakeLists.txt` (1), `Runner.rc` (7), `main.cpp` (3), `flutter_window.cpp` (1), `build-installer.ps1` (~8).
- Linux : `CMakeLists.txt` (1), `my_application.cc` (2), desktop (renommé), `plezy.sh` (1), 2 scripts `after-*`, 
  `build-packages.py`, `build-appimage.sh`, `build-flatpak.py`, 2 fichiers Flatpak (renommés), 2 scripts `check-*`.
- CI : `build.yml` (~70 lignes, presque toutes des renommages), `update-packages.yml` (1), `ci.yml` (~6),
  `check_build_workflow.py` (1), `check_windows_installer.py` (1).
- Dépôt : `README.md` (réécrit), `.gitattributes` (+2), `.github/ISSUE_TEMPLATE/config.yml`, `.github/FUNDING.yml`
  (supprimé), `pubspec.yaml` (`version`).
- Supprimés : sources et ressources des 23 icônes alternatives (Android, iOS, tvOS).

### Nouveaux fichiers
`branding/brand.json`, `branding/mark.svg`, `scripts/fork/generate_brand_assets.py`, `scripts/fork/check_identity.py`,
`scripts/fork/test_check_identity.py`, `scripts/fork/setup_merge.sh`, `NOTICE.md`,
`docs/technique/fusion-upstream.md`, `docs/technique/release.md` (procédure : générer les clés, créer les secrets,
lancer `build.yml` avec `release_tag`, publier le brouillon).

### Dépendances ajoutées
Aucune dépendance Dart ni Gradle. Outils de poste de dev pour le générateur, déjà requis par l'upstream : `librsvg`,
ImageMagick 7, `webp`.

### Risques
- **Google Play** : rien de bloquant maintenant (pas de `REQUEST_INSTALL_PACKAGES` ; la mise à jour Android ouvre la page
  GitHub). Pour `publication-stores` : l'AAB devra être construit **sans** `ENABLE_UPDATE_CHECK` (pas d'invitation à
  télécharger hors Play) ; le plugin `in_app_purchase` ajoute la permission `com.android.vending.BILLING` alors que
  l'app sera gratuite (à retirer, côté app) ; le règlement anti-spam exige que l'app apporte plus qu'une copie de Plezy
  (question produit, pas technique) ; test fermé de 14 jours ; niveau d'API cible de l'année.
- **Vérification des développeurs Android** : enregistrer `io.github.adrien24.popkino` et l'empreinte de la clé avant
  la généralisation de 2027, sinon les utilisateurs de téléphones devront passer par le « flux avancé » (24 h d'attente)
  ou ADB. Le compte « distribution limitée » (gratuit) plafonne à 20 appareils ; le compte complet coûte 25 $.
  Les TV ne sont pas concernées par l'obligation hors Play.
- **Marque** : un oubli dans un fichier binaire ou un nouvel artefact upstream ; couvert par la garde, plus une
  vérification manuelle des listes CA1 à CA7.
- **Performances TV** : nulles (icône vectorielle simple, bannière PNG de même taille qu'avant).
- **Conflits de fusion** : concentrés sur `build.yml` (≈70 lignes, la zone la plus mouvante de l'upstream), le
  packaging Linux et `pubspec.yaml` (`version`). Tous mécaniques ; la garde signale ce qui aurait été mal résolu.
- **macOS non certifié** : Gatekeeper bloque la première ouverture ; mise à jour Sparkle d'une app signée ad hoc à
  tester à la main (prévu par la spec). Si Sparkle refusait, repli : `useNativeUpdater` faux sur macOS et lien GitHub
  (décision app).
- **Dépendances de build hébergées par edde746** (moteur Flutter patché Windows, `mpv-build`, `auto_updater`) : ce sont
  des téléchargements de build épinglés par SHA-256, pas des services utilisés par l'app, donc compatibles avec
  `TRADEMARKS.md` ; s'ils disparaissent, le build casse (risque déjà présent).
- Clés perdues = plus de mise à jour possible (Android : désinstallation obligatoire ; Mac/Windows : mises à jour
  refusées). Procédure de sauvegarde dans `docs/technique/release.md`.

## 6. Décisions durables proposées (pour `docs/technique/decisions.md`)

- **D1 — Identité de l'app** : `io.github.adrien24.popkino` sur toutes les plateformes, schéma `popkino://`, dépôt
  `adrien24/popkino`. Ne changent plus après la première release.
- **D2 — Emplacement du code propre au fork** : outillage dans `scripts/fork/`, sources de marque dans `branding/`,
  documentation dans `docs/` ; (côté Dart, à fixer par l'architecte-app).
- **D3 — Identifiants internes de Plezy conservés** (package Dart, package Kotlin, `PlezyActivity`, noms de fichiers
  d'assets `plezy.*`, binaire Linux) : on remplace les contenus et les valeurs visibles, pas les noms internes.
- **D4 — Marqueurs** : `FORK:` dans la syntaxe de commentaire du fichier ; fichiers sans commentaire (pbxproj, JSON,
  binaires) couverts par `scripts/fork/check_identity.py`, exécutée via `scripts/ci_guard_checks.sh`.
- **D5 — Deux canaux, un code** : versions GitHub construites avec `ENABLE_UPDATE_CHECK=true` ; toute version store
  sans (pas de flavor tant que le manifeste n'a pas à différer).
- **D6 — Clés** : clé Android RSA 4096 PKCS12 et clé Ed25519 Sparkle/WinSparkle à l'utilisateur, secrets GitHub aux
  noms de l'upstream, sauvegarde hors GitHub obligatoire.
- **D7 — Version propre au fork** (semver indépendant de Plezy), tag = version du `pubspec.yaml`.

## Résumé

1. Identifiant définitif proposé : `io.github.adrien24.popkino` (prouvable sans domaine, libre sur Play/Amazon, prêt pour la vérification des développeurs Android).
2. Éditions en place, petites et marquées `FORK:` (~45 fichiers, ~170 lignes) ; noms internes et noms de fichiers d'assets Plezy gardés, contenus remplacés.
3. Garde `scripts/fork/check_identity.py` lancée par le `ci_guard_checks.sh` existant : aucun workflow ajouté, toute réapparition de Plezy fait échouer la CI.
4. Cohabitation avec Plezy (CA8) : authorities Android dérivées de `applicationId`, nouveau GUID Inno, mutex, `CompanyName`/`ProductName`, `APPLICATION_ID` et paquets Linux renommés.
5. Signature Android : aucun changement de code, secrets aux noms upstream, clé RSA 4096 à générer et sauvegarder.
6. Mises à jour Mac/Windows : mécanisme upstream (appcast sur branche `appcast` via jsDelivr), nouvelle clé Ed25519, lien `gh-html.edde746.dev` retiré.
7. CI : `popkino-…` partout, macOS signé ad hoc tant qu'il n'y a pas de compte Apple, MSIX et winget désactivés, `ENABLE_DONATIONS` retiré, `SUPPORTER_MODE=unlocked` global.
8. Logo provisoire : `branding/mark.svg` (tracé géométrique) + `scripts/fork/generate_brand_assets.py` qui produit toutes les déclinaisons ; le logo définitif = un SVG à remplacer.
9. GPL/marque : README Popkino, `NOTICE.md`, `FUNDING.yml` supprimé, tag par release déjà garanti par `build.yml`.
10. Version propre au fork (ex. `1.0.0+1`).

## QUESTIONS PRODUIT

1. **Identifiant définitif** : `io.github.adrien24.popkino` (recommandé, gratuit, lié au compte GitHub) ou acheter
   `popkino.app` (~15 €/an, à renouveler à vie) **avant la première release** pour utiliser `app.popkino` ? Une fois une
   release publiée, ce choix ne peut plus changer.
2. **Nom de l'éditeur affiché** (« Éditeur » dans « Applications installées » de Windows, développeur dans les
   métadonnées Linux, copyright Mac) : le pseudo `adrien24`, « Popkino », ou un nom réel ?
3. **Numéro de la première version** : repartir à `1.0.0` (recommandé : c'est une nouvelle app) ou un autre numéro ?
4. **Issues GitHub** : les activer sur le dépôt `popkino` (désactivées par défaut sur un fork) pour recevoir des
   signalements ?
5. **Vérification des développeurs Android** : accepter de créer plus tard un compte Android Developer Console (25 $,
   pièce d'identité) ou Play Console, pour que les téléphones installent l'APK sans manipulation après 2027 ? (Sans
   effet sur la TV ; à trancher au plus tard à `publication-stores`.)
