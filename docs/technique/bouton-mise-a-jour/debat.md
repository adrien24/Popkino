# Débat — bouton-mise-a-jour

## Critique de app sur la proposition plateforme — tour 1

Précisions du PO prises en compte (2026-11-28) :
- CA17 : rien n'est proposé quand la version la plus récente n'a pas d'APK pour l'appareil, pas de repli sur une
  version intermédiaire ;
- CA6 : les notes de version sont en texte simple ;
- CA11 : « Réessayer » rouvre directement l'écran d'autorisation.

Ma proposition (`proposition-app.md`) s'aligne déjà sur ces trois points.

### ✅ D'accord

- **Une seule bascule** (§ 1) : Gradle lit `ENABLE_UPDATE_CHECK` dans `-Pdart-defines`. Un flavor créerait une seconde
  bascule désynchronisable avec le define Dart, et ce bloc ajouté en fin de fichier ne touche aucune ligne upstream.
  L'échec du build sur `bundle*` et `AMAZON` couvre CA20 mieux que mon champ `declared`.
- **Absence du plugin hors sideload** (`nosideload/ForkPlugins.kt` vide) : `MissingPluginException` remplace mon champ
  `declared`, avec la même défense en profondeur. Je le retire.
- **Nom du canal `popkino/sideload_updater`, et ses 5 méthodes plutôt que mes 3** : je retire `com.plezy/fork_update`.
  D3 ne vise que les canaux upstream existants, et un nom propre au fork se repère mieux à la fusion. Ce qui me fait
  céder sur le nombre de méthodes :
  - `openInstallSettings` renvoie l'écran réellement ouvert (`appPermission`, `developerOptions`, etc.), ce qui permet
    d'adapter la phrase d'aide. Mon booléen ne le permettait pas ;
  - `inspectApk` est séparé de `install` : le Dart peut afficher « Vérification… », puis le message de CA19 **avant**
    l'écran système.

  Le wrapper `SideloadInstaller` (interface simulable) remplace mon `install_channel.dart`.
- **Choix de l'asset avec la tranche de versionCode** (§ 6, `Abi.current()` de `dart:ffi`) : c'est un cas que j'avais
  manqué. Un téléphone qui a l'APK arm64 (2xxx) ne doit pas se voir proposer l'APK v7a (1xxx), que le système
  refuserait comme une rétrogradation. Je reprends la règle telle quelle dans le sélecteur pur.
- **Seuil d'espace** `2 × taille + 100 Mo` (§ 7), à la place de mon « taille + 10 % ». L'installeur recopie l'APK dans
  `/data/app`, sur la même partition.
- **Dossier `getTemporaryDirectory()/updates/`** à la place de mon `popkino_update/`. J'ai vérifié qu'aucun code de
  `lib/` ni de `android/app/src/main/kotlin` n'utilise déjà `updates`. Le `cache-path` du FileProvider existant le
  couvre.
- **`ACTION_INSTALL_PACKAGE` plutôt que les sessions `PackageInstaller`** : on évite une copie de 94 Mo sur l'eMMC de
  la Fire Stick. Le Dart ne dépend que des chaînes de résultat, donc l'implémentation pourra changer derrière le
  canal.
- **Amendement de D10** (N ne redescend jamais sous 5 et reste inférieur à 1000), pour l'appliquer dès la 1.0.0.

### ⚠️ À amender

1. **Ma proposition (et non la sienne) : reprise après le redémarrage à froid d'Android 11.** La plateforme a raison :
   ma purge complète de `cache/updates/` dans `ensureChecked()` supprimerait l'APK après le premier octroi et ferait
   échouer CA10. Je corrige ainsi :
   - **Fiche de reprise** : quand l'APK est complet (taille exacte) **et** que `inspectApk` renvoie `ok`, le Dart écrit
     à côté un fichier `pending.json` : `{version, abi, versionCode, size, fileName, createdAt}`. L'APK n'est jamais
     considéré comme prêt sans cette fiche.
   - **Purge au démarrage**, première étape de `ensureChecked()`, avant toute requête réseau. Elle supprime :
     - tous les `.part` ;
     - tout `.apk` sans fiche valide ;
     - et la fiche avec son APK si la version est inférieure ou égale à l'installée, si la taille ne correspond plus,
       ou si `createdAt` date de plus de 24 h (CA14 : rien de durable).
   - **Reprise** : si une fiche valide reste, le contrôleur l'expose dans `pendingInstall`, sans attendre le réseau.
     Si `canRequestInstalls()` est vrai, `forkUpdateAction` ouvre la fenêtre dans une nouvelle phase
     `readyToInstall`, une seule fois par processus, par un `addPostFrameCallback` et seulement si la route de
     Découvrir est au premier plan (`ModalRoute.of(context)?.isCurrent`, pour ne pas s'ouvrir sur le choix de profil).
     Cette phase affiche « Version X.Y.Z prête à installer », avec les boutons Plus tard et **Installer** (focus).
   - **Sans redémarrage** (Android 8 à 10, 12 et plus, téléphones) : `AppLifecycleListener(onResume:)` dans la session
     enchaîne directement sur `install`, comme prévu. Les deux chemins aboutissent au même appel `install(path)`.
   - **Sans autorisation après le redémarrage** : la fiche est gardée. La fenêtre s'ouvre en `permissionDenied`
     (CA11, « Réessayer » rouvre les réglages).
   - Je rejoins sa recommandation (b) de la question produit 1 : la fenêtre rouverte avec « Installer », plutôt qu'un
     écran système qui s'ouvre seul. À trancher par le PO, car CA10 dit « l'installation se lance », ce qui
     ressemblerait plutôt à (a).
2. **Vérification de l'APK : `inspectApk` remplace le digest GitHub, il ne s'y ajoute pas.** J'abandonne le SHA-256
   calculé en Dart pendant le téléchargement :
   - **taille exacte**, puis **`inspectApk`**, puis la vérification de l'installeur, cela suffit. Un fichier tronqué
     est rejeté par la taille ou rendu `invalid` par `getPackageArchiveInfo` (le répertoire central du zip est à la
     fin) ;
   - le contrôle du signataire est une garantie d'authenticité que le digest n'apporte pas : le digest vient de la
     même source que le fichier ;
   - le SHA-256 en Dart pur sur le thread de l'interface, pour 94 Mo sur ARMv7, était le principal risque de saccades
     de ma proposition. Il disparaît sans plan B en isolate ;
   - on garde le champ `digest` dans `ForkApkAsset` (gratuit), sans l'utiliser.

   Correspondance des statuts côté Dart :
   - `invalid` : le fichier est supprimé, puis `failed(network)`, avec « Réessayer » qui retélécharge ;
   - `signatureMismatch` : `failed(signature)`, message de CA19 ;
   - `wrongPackage` : `failed(other)`, message générique ;
   - `notNewer` : `failed(other)`, et le tag est noté dans le contrôleur pour masquer le bouton jusqu'au prochain
     lancement. Sans cela, le bouton proposerait en boucle une release que le système refuse. Avec l'amendement de
     D10, ce cas ne devrait jamais se présenter.
3. **Constante éliminable par l'AOT** (son § 9, dernier point), à préciser. `UpdateService.isUpdateCheckEnabled` est
   un **getter** ; je ne veux pas parier sur son inlining par l'analyse globale de l'AOT. Le fork déclare sa propre
   constante dans `lib/fork/update/fork_update_controller.dart` :

   ```dart
   const bool kForkSideloadUpdates = bool.fromEnvironment('ENABLE_UPDATE_CHECK'); // same define as UpdateService
   static bool get isSupported =>
       (kForkSideloadUpdates || (kDebugMode && debugForceSupported)) && Platform.isAndroid;
   ```

   En release, `kDebugMode` vaut `false` à la compilation : l'expression se réduit à `kForkSideloadUpdates`. Les tests
   (mode debug) peuvent forcer `debugForceSupported`. **Chaque point d'entrée** commence par `if (!isSupported) return …`
   avant toute référence au downloader ou au canal : `forkUpdateAction` (emplacement vide), `ForkUpdateHooks.performCheck`
   et `ForkUpdateHooks.showDialog` (renvoient `null`, donc l'upstream continue). Une garde de test vérifie que ces trois
   fonctions commencent bien par ce test.
4. **Contrat des fichiers** (son point 1) : « renommé quand la taille égale le `size` de l'asset GitHub ». Si
   `Content-Length` diffère de `asset.size`, je fais confiance à `asset.size` et je traite l'écart comme
   `failed(network)`. Pas besoin de suivre spécialement la redirection vers `objects.githubusercontent.com` :
   aujourd'hui elle arrive sur `release-assets.githubusercontent.com`, et `githubusercontent.com` (avec ses
   sous-domaines) est déjà dans `network_security_config.xml`. Le client `dart:io` suit les redirections d'un GET par
   défaut. Rien à changer côté plateforme.
5. **Traductions des écrans de réglage** : comme `openInstallSettings` renvoie la cible, j'ajoute aux clés
   `fork.update.*` une phrase d'aide par cible : `appPermission` (phrase de la spec), `unknownAppsList`
   (« … puis choisissez Popkino »), `developerOptions` (« Options pour les développeurs > Installer des applis
   inconnues > Popkino ») et `security` / `settings` / `none` (chemin complet). Cela répond à sa question produit 2 dans
   le sens de sa recommandation, sous réserve de l'accord du PO.

### ❌ Bloquant

Aucun. Tous les points ci-dessus sont des amendements ; le seul vrai défaut identifié, la purge au démarrage qui
casserait CA10 sous Android 11, était dans ma proposition et je le corrige au point 1.

### Interfaces retenues pour le plan (contrat Dart ↔ natif)

- **Canal** : `popkino/sideload_updater`, avec les méthodes et les chaînes de retour exactes de sa table
  « Interfaces exposées ».
- **Côté Dart** : `SideloadInstaller` (`lib/fork/update/sideload_installer.dart`) ; `MissingPluginException` donne
  `unavailable`, ce qui masque tout.
- **Dossier** : `getTemporaryDirectory()/updates/`, avec des `.part`, des `.apk` et un `pending.json`. Le natif
  n'accepte que des `.apk` de ce dossier.
- **Ordre côté Dart** :
  1. `availableBytes` (refus si moins de `2 × size + 100 Mo`) ;
  2. téléchargement ;
  3. contrôle de la taille exacte ;
  4. `inspectApk` ;
  5. écriture de `pending.json` ;
  6. `canRequestInstalls` (sinon `openInstallSettings`, puis reprise) ;
  7. `install`.
- **Côté Dart, aucun appel** au canal si `isSupported` est faux (CA20).

## Critique de plateforme sur la proposition app — tour 1 (position finale)

Ma première version de cette section, perdue lors d'une réécriture simultanée du fichier, proposait d'adopter le canal
de l'app. L'app a fait le chemin inverse dans sa section ci-dessus. Pour éviter toute ambiguïté, **voici ma position
finale, qui retient la synthèse de l'app** :

- ✅ **Canal** : `popkino/sideload_updater`, avec les 5 méthodes et les chaînes de retour de la table « Interfaces
  exposées » de `proposition-plateforme.md`. `com.plezy/fork_update` est abandonné.
- ✅ **Dossier** : `getTemporaryDirectory()/updates/` (`.part`, `.apk`, `pending.json`). `file_provider_paths.xml`
  ne change pas.
- ✅ **Vérification** : la taille exacte, puis `inspectApk` (paquet, puis signataires, puis versionCode), **sans digest
  SHA-256 en Dart**. `install` refait la même inspection côté natif (défense en profondeur) et ne lance jamais
  l'installeur si elle échoue.
- ✅ **Reprise après le redémarrage à froid d'Android 11** : la fiche `pending.json` et la purge au démarrage du point 1
  de l'app me conviennent telles quelles. C'est conforme à la décision du PO (1) : la fenêtre se rouvre en phase
  `readyToInstall`, avec « Installer » au focus et sans retéléchargement.
- ✅ **Constante éliminable** (point 3 de l'app) : `kForkSideloadUpdates` + `kDebugMode && debugForceSupported`, testé
  en tête de chaque point d'entrée. Cela lève mon objection Play. J'ajoute au plan la vérification d'artefact : sur un
  build **sans** le define, `strings` sur `libapp.so` ne doit contenir ni `releases?per_page` ni `popkino-android-`,
  et `aapt2 dump permissions` ne doit pas lister `REQUEST_INSTALL_PACKAGES`.
- ✅ **Phrases d'aide par cible des réglages** (point 5 de l'app) : conforme à la décision du PO (2), le chemin complet
  n'est affiché que si la cible n'est pas `appPermission`.
- ✅ **Clé de signature** : réinstallation unique au passage à la clé définitive (décision du PO, 3). Pas de rotation
  de clé ; le message de CA19 vient de `inspectApk` → `signatureMismatch`.
- ✅ **Nom des fichiers de release** (décision du PO, 4) : le README ne pointera plus vers `releases/latest/download/…`
  (cette URL ignore les pré-versions), mais vers la page `https://github.com/adrien24/popkino/releases`. Un nom de
  fichier stable n'a donc plus d'intérêt. **Je me range au format versionné**
  `popkino-android-<abi>-<X.Y.Z>.apk`, déjà utilisé par les releases manuelles : un seul format partout. `build.yml`
  remplacera ses `tar.gz` par des copies sous ce nom. Le sélecteur garde le motif à version facultative.
- ⚠️ Un seul point reste à écrire dans le plan, sans désaccord : la vérification d'artefact ci-dessus, et
  `-PpopkinoSideload=true` sur la ligne `testDebugUnitTest` de `ci.yml`.
- ❌ Aucun bloquant restant.

## Validation croisée de plateforme sur plan.md — tour 1

Relu : `plan.md` (T1 à T13, vérifications, risques) et `decisions.md` (D7 et D10 amendés, D13, D14). Les tâches
natives (T1 à T4) reprennent fidèlement `proposition-plateforme.md`. Le contrat du canal est conforme. Les AAB de
`scripts/release/deploy.py` sont construits sans `ENABLE_UPDATE_CHECK` (l. 916), donc compatibles avec le garde-fou
de T1.

- ❌ **Bloquant (une seule objection)** — **H4 (`main.dart`, T9) contredit la vérification d'artefact n° 2 du plan.**
  La ligne `ChangeNotifierProvider<ForkUpdateController>.value(value: ForkUpdateController.instance)` est
  inconditionnelle : l'initialiseur de `instance` construit le contrôleur avec ses dépendances par défaut
  (`MethodChannelSideloadInstaller`, `ForkUpdateFiles`, client HTTP). Ces classes, et la chaîne
  `'popkino/sideload_updater'`, restent donc dans le `libapp.so` des builds store. La commande
  `strings libapp.so | grep -E '…|sideload_updater'` du plan échouera alors à coup sûr. Le codeur serait tenté de
  retirer la vérification, qui est précisément la preuve exigée par `regles-fork` §3. Cela contredit aussi D13 (« la
  constante est testée en tête de chaque point d'entrée ») : `instance` est un point d'entrée non gardé.
  → **Modification attendue** :
  - T9 : dans `main.dart`, écrire la ligne en collection-if dans la liste littérale `providers: [...]`, soit
    `if (kForkSideloadUpdates) ChangeNotifierProvider<ForkUpdateController>.value(value: ForkUpdateController.instance), // FORK: …`.
    Les lectures `context.watch<ForkUpdateController?>()` renvoient déjà `null` sans provider ;
  - D13 : remplacer « exposé par `ChangeNotifierProvider.value` dans le `MultiProvider` » par « exposé, derrière la
    même constante (collection-if), par `ChangeNotifierProvider.value` dans le `MultiProvider` » ;
  - T13 : la garde de crochets vérifie `if (kForkSideloadUpdates) ChangeNotifierProvider<ForkUpdateController>` dans
    `main.dart`.

**Remarques non bloquantes**
- Vérification manuelle de CA9 : `adb shell run-as io.github.adrien24.popkino …` échoue sur un APK de release (non
  debuggable). → utiliser `adb shell dumpsys diskstats` (tailles de cache par paquet), comme pour CA14.
- T4, « Collect release files » : un motif littéral `echo 'artifacts/android-apk/popkino-android-*.apk'`, comme pour
  Linux (`'artifacts/linux-x64/*'`), est plus simple que `ls` et laisse `softprops/action-gh-release` développer le
  motif.
- Risque « écran Fire OS » : d'accord pour trancher en recette. Si la règle Amazon devient nécessaire, le test sera
  `packageManager.hasSystemFeature("amazon.hardware.fire_tv")`, plus fiable que `Build.MANUFACTURER`.
- T1 : pour la vérification « le dex ne contient pas `SideloadUpdaterPlugin` », `$BT/dexdump -l plain` sur
  `classes*.dex` extraits suffit (`apkanalyzer` n'est pas forcément installé).

**Statut** : `APPROUVÉ` dès que l'objection ci-dessus est intégrée (trois lignes à changer, sans autre conséquence).

## Réponse de app à la validation croisée — tour 1

- ❌ intégré : T9 écrit le provider dans `main.dart` en collection-if
  (`if (kForkSideloadUpdates) ChangeNotifierProvider<ForkUpdateController>.value(...)`). `ForkUpdateController.instance`
  n'est plus jamais référencé hors d'un test de la constante. La garde de T13 vérifie cette forme exacte et échoue si
  `instance` est référencé ailleurs dans `lib/`. D13 est ajusté dans `decisions.md`.
- Remarques non bloquantes, toutes retenues :
  - CA9 se vérifie par `dumpsys diskstats` (et non plus `run-as`) ;
  - T4 utilise le motif littéral `echo 'artifacts/android-apk/popkino-android-*.apk'` ;
  - la règle Fire OS éventuelle s'appuiera sur `hasSystemFeature("amazon.hardware.fire_tv")` ;
  - le dex se contrôle par `dexdump -l plain`.
