
## Critique de plateforme sur la proposition app — tour 1

### Arbitrages demandés

- ✅ **Portes `const` dans `lib/fork/fork_features.dart` plutôt que `--dart-define`** : j'adopte sa position et je
  retire ma proposition. Raisons vérifiables : `flutter test` tourne sans define (la valeur réelle du build n'est
  testable qu'en `const`), et `build.yml:36` réactive `ENABLE_DONATIONS=true` à chaque fusion mal résolue. Conséquence
  côté CI : **je ne touche plus ni `ENABLE_DONATIONS`, ni les `SUPPORTER_MODE` par job** (ils deviennent sans effet en
  Dart), ce qui retire 4 lignes de diff à `build.yml`. La CI ne porte plus que `ENABLE_UPDATE_CHECK=true` (inchangé) et
  les 4 secrets `POPKINO_*` ajoutés à `RELEASE_DART_DEFINES` (une ligne).
- ✅ **Noms des defines `POPKINO_TRAKT_CLIENT_ID`, `POPKINO_TRAKT_CLIENT_SECRET`, `POPKINO_SIMKL_CLIENT_ID`,
  `POPKINO_MDBLIST_CLIENT_ID`** : adoptés ; les secrets GitHub portent les mêmes noms. `popkino_secrets.json` dans
  `.gitignore` (+1 ligne) ; la commande de build locale du skill `conventions-code` devra ajouter
  `--dart-define-from-file=popkino_secrets.json` (à signaler à l'orchestrateur).
- ✅ **Gardes complémentaires, pas doublons**, à condition de partager le terrain sans recouvrement :
  `test/fork/*_test.dart` (lui) couvre `lib/` et `lib/i18n/` (URL `plezy.app`/`edde746`, identifiants des trackers,
  valeurs « Plezy ») ; `scripts/fork/check_identity.py` (moi) couvre natif, manifestes, plist, pbxproj, workflows,
  packaging, clés publiques Sparkle, GUID Inno, `gh-html.edde746.dev`. **Je retire mes règles sur `lib/`.** Les deux
  tournent déjà en CI sans nouveau workflow : les siens via `scripts/run_tests.sh` (`ci.yml:141`), le mien via
  `scripts/ci_guard_checks.sh` (`ci.yml:68`, glob `scripts/*/test_*.py`).
- ✅ **Version** : d'accord, `X.Y.Z` numérique propre au fork (`UpdateService._isNewerVersion` coupe sur `-`/`+`, et
  `create-release` exige déjà `^[0-9]+\.[0-9]+\.[0-9]+$` = version du pubspec). Valeur de départ : question produit.
- ✅ **`ForkIdentity.updateFeedUrl`** = `https://cdn.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml`, confirmé
  (même valeur dans `macos/Runner/Info.plist` `SUFeedURL`) ; `githubRepo = adrien24/popkino`.
- ✅ **Logos : mêmes chemins, contenu remplacé** : même position que moi (D3 de ma proposition).
- ✅ **Schéma `popkino`** côté Dart via `DeepLink.scheme`. Le natif suit (manifeste, `DeepLinkPlugin.kt:18`,
  `WatchNextProvider.kt:460,743`, 3 Info.plist, `TopShelfProvider.swift:260`, tests Swift tvOS).

### À amender

- ⚠️ **Schéma : « registre Windows, `.desktop` Linux »** : rien à faire, l'upstream n'enregistre aucun schéma sur ces
  deux plateformes (aucune occurrence `plezy` de type `URL Protocol` dans `windows/runner/`, pas de `MimeType=` dans
  `linux/packaging/com.edde746.plezy.desktop`). → retirer ces deux cibles de la liste d'interface.
- ⚠️ **« Génération des logos via `scripts/codegen/generate_app_icons.py` »** : ce script ne produit que les 23 icônes
  **alternatives** ; l'icône par défaut est faite à la main (vector drawable, `plezy.icon`, image stacks tvOS,
  `app_icon.ico`). → génération par mon nouveau `scripts/fork/generate_brand_assets.py` (`branding/mark.svg` →
  `assets/plezy.png`, `assets/plezy.svg`, `assets/plezy_adaptive_foreground.svg` et toutes les icônes natives).
  L'upstream `generate_app_icons.py` n'est plus lancé dans le fork.
- ⚠️ **`check_icon_consistency.dart` « à adapter »** : non. Il contrôle l'usage du widget d'icône Dart
  (`_canonicalAppIconPath = 'lib/widgets/app_icon.dart'`), pas les icônes de lanceur. Rien à changer.
- ⚠️ **Suppression des icônes alternatives** : à faire dans **une seule tâche** partagée, sinon le build casse entre
  deux tâches : `assets/app_icons/` + ligne `pubspec.yaml` + `ForkFeatures.alternateAppIcons` + test `skip` (lui) ;
  ressources Android `*_<id>_*` et `mipmap-anydpi-v26/ic_launcher_<id>.xml`, bloc d'alias du manifeste vidé (marqueurs
  gardés, `.MainActivity` intact), `ios/Runner/AlternateAppIcons.xcassets` et `tvos/Runner/AlternateAppIcons.xcassets`
  vidés **mais gardés avec leur `Contents.json`** (référencés par les pbxproj), bloc généré de `tvos/Runner/Info.plist`
  vidé (moi). Kotlin `AppIconChannel` reste : sans appel Dart, il ne fait rien.
- ⚠️ **Permission `BILLING` ajoutée par `in_app_purchase_android`** : puisque `supporterBuildMode` est forcé à
  `unlocked`, `SupporterService.init()` ne contacte jamais la boutique ; je retire la permission dans le manifeste
  principal (`<uses-permission android:name="com.android.vending.BILLING" tools:node="remove"/>`, 1 ligne, `FORK:`).
  Pas bloquant pour GitHub, utile pour la future fiche Play (l'app est gratuite). Vérification : `aapt2 dump
  permissions` sur l'APK. SDK Sentry natif : non initialisé sans `ENABLE_SENTRY` ; à confirmer par la capture réseau
  de CA16, pas d'action préalable.
- ⚠️ **`rebrand_i18n.py` et la CI** (`ci.yml:62` `codegen.sh --check`, `ci.yml:65` `clean_translations.py --check
  --strict`) :
  1. `clean_translations.normalize()` reconstruit chaque langue sur la structure de `en` et **remplit les clés
     manquantes par `""`** (`empty_shaped_like`). Si le script n'ajoute `fork.*` qu'en `en` et `fr`, `--check` échoue sur
     les 21 autres langues. → le script doit **importer et appeler** `normalize()`/`dump_json()` de
     `scripts/checks/clean_translations.py` en dernière étape (pas une réimplémentation du format), ce qui garantit un
     résultat identique octet pour octet. Les `""` donnent bien l'anglais grâce à
     `fallback_strategy: base_locale_empty_string` (`slang.yaml`).
  2. `--strict` échoue sur toute clé de `en` non référencée dans `lib/` : les clés `fork.*` doivent toutes être lues
     par `ForkAboutScreen` (pas de clé prévue « pour plus tard »). Les clés des fonctions neutralisées restent
     référencées tant que le code upstream reste : OK.
  3. Ordre obligatoire dans la procédure et dans les tâches : `rebrand_i18n.py` → `dart run slang` (via
     `scripts/codegen.sh`) → commit des `strings_*.g.dart` ; sinon `codegen.sh --check` échoue.
  4. Branchement CI sans toucher aux workflows : `scripts/fork/test_rebrand_i18n.py` qui lance
     `rebrand_i18n.py --check` ; il est ramassé automatiquement par le glob `scripts/*/test_*.py` de
     `scripts/ci_guard_checks.sh`.
- ⚠️ **Tests upstream réécrits (`plezy://` → `popkino://`, ~70 littéraux)** : ne pas étendre `rebrand_i18n.py` aux
  tests (deux responsabilités dans un script). Préférer `ForkIdentity.urlScheme` dans les assertions, ou une
  substitution `sed` ponctuelle documentée dans la tâche.

### Bloquant

- Aucun. Rien dans la proposition app ne fait courir de risque de rejet Play ni de violation de `TRADEMARKS.md` ;
  les points ci-dessus sont des corrections de faits ou d'ordonnancement.

## Critique de app sur la proposition plateforme — tour 1

Lu : `proposition-plateforme.md` en entier, plus des vérifications dans le code (citées ci-dessous).

### Points de friction demandés par l'orchestrateur

- ✅ **Éditions en place (plateforme) contre centralisation dans `lib/fork/` (app) : compatibles, ce n'est pas la même
  couche.** Côté Dart aussi, les fichiers upstream sont modifiés en place, ligne par ligne, avec `// FORK:`. La seule
  différence est que la valeur vient d'une constante `ForkIdentity.*` au lieu d'un littéral. Le Dart a ~15 sites pour
  la même valeur (« Popkino » : Plex ×4, Jellyfin ×5, Regarder ensemble ×4…) et des tests qui doivent la référencer ;
  le natif, lui, ne peut pas partager de constante entre Kotlin, plist, rc et CMake. Règle commune pour le plan : le
  `§ 2` de la plateforme est la **table de référence**, et `lib/fork/fork_identity.dart` en est la copie Dart. La garde
  Python vérifie que les deux concordent (voir point suivant).
- ✅ **Garde Dart contre `scripts/fork/check_identity.py` : complémentaires, sans doublon si chacune a son
  territoire.**
  → Proposition :
  - `check_identity.py` (plateforme) couvre **tout sauf `lib/` et `test/`** : manifestes, plist, pbxproj, rc, CMake,
    packaging, workflows. Il ne porte **pas** de règle sur `lib/` (ton § 3.1 y prévoyait `ice.plezy.app`, `bugs.plezy.app`
    et `liberapay`) : elles sont dans `test/fork/plezy_services_guard_test.dart`, qui sait ignorer les commentaires et
    les `*.g.dart`, et a des listes d'exceptions justifiées (`certificate_trust.dart`, `anime_mappings_store.dart`).
  - La garde Dart ne peut pas être remplacée par du grep : elle vérifie des valeurs **à l'exécution**
    (`DeepLink.tryParse('plezy://open') == null`, `jellyfinClientName(...)`, `ForkTrackers.isOffered`, `t.app.title`).
  - Seule règle croisée : `check_identity.py` lit `lib/fork/fork_identity.dart` (simple regex sur `urlScheme`,
    `githubRepo`, `updateFeedUrl`) et vérifie qu'ils égalent le schéma du manifeste et du plist, et le `SUFeedURL`. Cela
    évite qu'un natif `popkino` et un Dart `plezy` divergent sans qu'aucun test ne le voie.
  - J'adopte ton mécanisme `scripts/*/test_*.py` lancé par `ci_guard_checks.sh` : j'ajoute
    `scripts/fork/test_rebrand_i18n.py`, qui lance `rebrand_i18n.py --check`. Aucun workflow n'est modifié.
- ❌ **`SUPPORTER_MODE=unlocked` en `--dart-define` de CI : bloquant comme mécanisme principal.**
  - Le flag vit dans `build.yml`, la zone la plus mouvante de l'upstream (ton propre § 5, risques). Ta proposition
    retire les `SUPPORTER_MODE` par job (macOS, Windows, Linux) : cela fait 3 lignes de plus en conflit potentiel.
  - Le moindre raté de fusion, par exemple l'upstream qui réintroduit `SUPPORTER_MODE=msstore` sur un job Windows, masque
    les thèmes sous Windows (CA18b) sans qu'aucun test ne le voie : `flutter test` tourne sans define.
  - Les builds locaux de `conventions-code` (`flutter build apk …`) n'ont pas le flag : thèmes masqués sur la TV de test.
  → Alternative :
  - La constante `supporterBuildMode = ForkFeatures.forkSupporterMode` (`unlocked`) dans
    `lib/services/supporter/supporter_mode.dart`. Ce fichier est presque immobile upstream ; le changement est testable
    (`test/fork/fork_features_test.dart`) et le define est ignoré.
  - Dans `build.yml` : **ne rien toucher** aux `SUPPORTER_MODE` (ni ajout global, ni retrait par job). Ils deviennent
    inertes, et c'est autant de lignes de moins en conflit.
  - Même logique pour `ENABLE_DONATIONS` (porte Dart `ForkFeatures.donations`) et `ENABLE_SENTRY`
    (`scripts/release/deploy.py:917,1089,1240` le force à `true`, hors de toute condition sur le dépôt). Tu peux
    retirer `ENABLE_DONATIONS=true` de `RELEASE_DART_DEFINES` par hygiène, mais la sécurité ne doit pas en dépendre.
- ✅ **Version propre au fork `1.0.0+1`, tags `X.Y.Z` = version du pubspec** : c'est exactement ce qu'exige
  `UpdateService`. Il compare `tag_name` (sans le `v`) à la version courante et coupe sur `-` et `+`
  (`_parseVersionParts`) : un tag `2.26.0-popkino.1` n'aurait jamais été vu comme une mise à jour. Avec des tags
  numériques propres au fork, CA22 tient sans toucher à la logique.
  - ⚠️ À ajouter au plan : un test `test/fork/fork_identity_test.dart` qui vérifie, via
    `UpdateService.debugPerformUpdateCheck` et un `MockClient`, que l'URL interrogée est
    `api.github.com/repos/adrien24/popkino/releases/latest` et qu'un tag `1.0.1` est plus récent que `1.0.0`.

### § 3.12 — ce que tu attends du Dart, point par point

- ✅ `UpdateService._githubRepo` / `_feedUrl` : valeurs de ton § 2, via `ForkIdentity.githubRepo` / `updateFeedUrl`.
- ✅ `DeepLink.scheme = 'popkino'` : le parseur des retours du lecteur externe passe déjà par `DeepLink.scheme`
  (`external_player_service.dart:324,355`), donc une seule ligne.
  - ⚠️ Côté natif, `WatchNextProvider.kt:460,743` : ne change **que le schéma**, pas le préfixe d'identifiant de contenu
    `plezy_` (`content_id=plezy_<server>_<item>`). Dart le parse en dur (`system_shelf_service.dart:375-382`) : le
    renommer casserait la lecture depuis la rangée Android TV. C'est un identifiant interne, on le garde.
- ✅ Noms du client Plex et Jellyfin, `'app'` de `LanDiscoveryService` : déjà dans ma proposition.
- ⚠️ **Noms des `--dart-define`** : `POPKINO_TRAKT_CLIENT_ID`, `POPKINO_TRAKT_CLIENT_SECRET`, `POPKINO_SIMKL_CLIENT_ID`,
  `POPKINO_MDBLIST_CLIENT_ID`, et non `TRAKT_CLIENT_ID`. Raison : si l'upstream sort un jour ses propres identifiants du
  code avec un define du même nom, on aurait une collision silencieuse de sens. Les **secrets GitHub** peuvent garder
  tes noms.
  → Dans `RELEASE_DART_DEFINES` : `--dart-define=POPKINO_TRAKT_CLIENT_ID=${{ secrets.TRAKT_CLIENT_ID }}`, etc. Un secret
  absent donne une valeur vide, donc un service masqué (CA19f). C'est le seul usage de `--dart-define` que je retiens
  pour le fork.
- ✅ **Défaut de `SUPPORTER_MODE`** : réglé par la constante Dart (voir le ❌ plus haut). Cela couvre aussi les builds
  locaux.
- ✅ **Sélecteur d'icônes et `pubspec.yaml`** : porte `ForkFeatures.alternateAppIcons` dans
  `app_icon_service.dart:47`, suppression de `assets/app_icons/previews/` et de sa ligne dans `pubspec.yaml`, `skip:`
  sur `test/screens/settings/app_icon_setting_test.dart`.
  → **Une seule tâche commune** avec ton `git rm` des ressources natives, pour garder le build vert (je dépendrai de ta
  tâche ou l'inverse, au plan).
  - Correction de ma proposition : `scripts/checks/check_icon_consistency.dart` contrôle le widget `AppIcon`
    (`lib/widgets/app_icon.dart`), pas les icônes de l'app. Il n'est pas concerné.
- ✅ **Règles Dart de la garde** : dans `test/fork/` (voir le partage des territoires plus haut).
- ⚠️ **Correspondances d'anime (`github.com/edde746/anime-mappings`)** : elles sont **déjà** inatteignables sans MAL ni
  AniList. Le téléchargement n'a lieu que via `TrackerIdResolver` quand un tracker actif a `needsFribb`
  (`tracker_id_resolver.dart:212,273`, `tracker_coordinator.dart:200`), et c'est faux pour Simkl
  (`simkl_tracker.dart:45`).
  → J'accepte quand même une porte d'une ligne, par défense en profondeur : `if (!ForkFeatures.animeTrackers) return null;`
  en tête de `AnimeMappingsStore._download()` (`anime_mappings_store.dart:135`). Plus un test qui vérifie `needsFribb ==
  false` pour Trakt, Simkl et MDBList. Simkl reconnaît alors les animes par les identifiants externes du serveur (CA19h).
  Ce fichier sort de la liste d'exceptions de la garde dès que la porte est en place.

### Autres remarques sur la proposition plateforme

- ✅ **`io.github.adrien24.popkino`** : aucun code Dart de `lib/` n'utilise l'identifiant d'app (vérifié :
  `com.edde746` n'apparaît que dans des noms de canaux de plugin et dans des tests). Changer l'identifiant n'impose donc
  aucune modification Dart.
- ✅ **Authorities Android dérivées de `applicationId`** (prérequis de CA8 et CA15) : rien à faire côté Dart, le canal
  `com.plezy/external_player` ne transporte pas l'autorité.
- ✅ **Séparation des données Windows et Linux** (`CompanyName`/`ProductName`, `APPLICATION_ID`) : base et réglages
  Dart sont sous `getApplicationSupportDirectory()` (`app_database.dart:1430-1434`, `download_storage_service.dart:111`),
  donc séparés une fois ton changement fait.
- ⚠️ **Nouveau point CA8 que j'ai trouvé en vérifiant ta séparation des données** :
  - `migrateLegacyDesktopDatabase` (`app_database.dart:1477-1495`) cherche `plezy_downloads.db` dans
    `getApplicationDocumentsDirectory()`, c'est-à-dire `~/Documents`, **partagé entre les deux apps sur ordinateur**,
    puis le **déplace**.
  - Sur un ordinateur où une ancienne version de Plezy officiel a laissé ce fichier, Popkino s'approprierait la base de
    téléchargements de Plezy.
  → Porte Dart d'une ligne au début de la fonction : `if (!ForkFeatures.legacyPlezyMigrations) return;`. C'est à mon
  compte, à ajouter au plan, avec un test qui passe un `sourceOverride` existant et vérifie qu'il n'est pas déplacé.
- ⚠️ **Permission BILLING** (ton § 5 la classe « côté app ») : ce n'est pas faisable proprement côté Dart. Retirer
  `in_app_purchase` imposerait de supprimer les imports de `supporter_service.dart` et `supporter_store.dart` (code
  upstream).
  → C'est au manifeste de le faire : `<uses-permission android:name="com.android.vending.BILLING"
  tools:node="remove"/>` dans `AndroidManifest.xml` (`// FORK:`). En Dart, la boutique n'est jamais appelée en mode
  `unlocked` (`SupporterService.init()` sort si ce n'est pas `purchasable`). Je propose de le faire dès maintenant : une
  ligne, et un APK sans BILLING évite une question sur la fiche Play plus tard.
- ⚠️ **§ 4, alternative « script d'application d'un tableau de remplacements » écartée** : d'accord pour tes ~40 lignes
  natives, la garde suffit. Mais pas pour les traductions, où je propose `scripts/fork/rebrand_i18n.py`. Là, le volume
  change la conclusion :
  - ~41 valeurs × 23 fichiers, soit environ 940 lignes ;
  - des formes fléchies (`Plezyt`, `Plezy'yi`, `Plezy-ді`…) qu'une garde détecte mais ne corrige pas ;
  - une résolution de conflit qui devient « version upstream puis relancer le script ».
  → Règle pour le plan : un script de génération seulement quand le volume ou la grammaire le justifient (traductions) ;
  partout ailleurs, édition en place, marqueur et garde.
- ⚠️ **`docs/technique/fusion-upstream.md` (ton § 3.11)** : y ajouter l'étape des traductions
  (`git checkout --theirs -- lib/i18n/*.i18n.json && python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh`) et
  `flutter test test/fork/` juste après `ci_guard_checks.sh`.
- ✅ **Mise à jour macOS** : le repli « `useNativeUpdater` faux sur macOS si Sparkle refuse une app ad hoc » est
  accepté côté app. Ce serait une constante `ForkFeatures.nativeUpdaterOnMacOS` dans `update_service.dart:44`, à activer
  seulement si le test manuel de CA22b échoue.
- ✅ Logos : mêmes chemins, contenu remplacé, générés par `scripts/fork/generate_brand_assets.py`. C'est identique à ma
  proposition, et le Dart n'a rien à changer (`auth_screen.dart`, splash de `main.dart`, À propos).

## Validation du plan — tour 1 (architecte-app)

Relu : `plan.md` (surtout T1 à T8), `decisions.md` (D1 à D10), et les précisions P1 à P7 de la spec, vérifiés contre le
code. Couverture des CA du périmètre app et de P1 à P5 : complète. Dépendances entre tâches qui touchent les mêmes
fichiers : correctes (`main.dart` T2→T3, `pubspec.yaml` T8→T16, `settings_screen.dart` seulement dans T6,
`i18n_branding_test.dart` T5→T6). Complexités : honnêtes.

**Non approuvé** : 3 objections bloquantes. Elles sont faciles à corriger, mais en l'état le build ou la suite de tests
casse, ou le codeur doit faire un choix d'architecture.

- ❌ **T1/T4 — l'initialisation prescrite ne compile pas.** T4 demande `clientId = ForkTrackerCredentials.fromEnvironment.*`
  dans des `static const` (`trakt_constants.dart:13-14`, `simkl_constants.dart:27`, `mdblist_constants.dart:12`). En
  Dart, lire un champ d'un objet `const` n'est **pas** une expression constante (seuls `String.length` et les
  références à des constantes statiques le sont). C'est une erreur de compilation. L'erreur vient de ma proposition, le
  plan l'a reprise.
  → T1 : ajouter `abstract final class ForkTrackerDefines` avec 4 `static const String` lus par `String.fromEnvironment('POPKINO_…')` ;
  `ForkTrackerCredentials.fromEnvironment` est construit à partir d'eux. T4 : les constantes upstream référencent
  `ForkTrackerDefines.traktClientId` (et les 3 autres), pas `fromEnvironment.*`.
- ❌ **T3 casse `test/android/network_security_config_test.dart`, et rien dans le plan ne le traite.**
  - Le test scanne `lib/services/plezy_server.dart` et `lib/main.dart` (`_fixedEndpointSourcePaths`, l. 30-40) et exige
    que chaque hôte `https://` soit couvert par `_expectedDomains` (l. 91-109) : `plezy-services.invalid` ne l'est pas.
  - Il exige aussi que chaque domaine attendu soit observé dans les sources (l. 113-124). Or, une fois le DSN vidé et
    l'URL remplacée, `plezy.app` n'apparaît plus nulle part.
  - Il exige enfin que `CertificateTrust.fixedEndpointDomains` et `network_security_config.xml` égalent
    `_expectedDomains` (l. 71, 88).
  → Ajouter à T3 :
  - retirer `'plezy.app'` de `lib/utils/certificate_trust.dart:37`, du `<domain>plezy.app</domain>` de
    `android/app/src/main/res/xml/network_security_config.xml:33-36` (`<!-- FORK: -->`) et de `_expectedDomains` dans le
    test ;
  - retirer `'lib/services/plezy_server.dart'` et `'lib/main.dart'` de `_fixedEndpointSourcePaths` : après T3, ces
    fichiers ne contiennent plus aucun littéral `https://` couvert ;
  - dans `plezy_services_guard_test.dart`, la liste d'exceptions pour `plezy.app` devient vide.
  - T3 touche alors un fichier XML Android, que T9 ne modifie pas : aucune dépendance à ajouter.
- ❌ **T2/T3/T4 — les listes de tests upstream à adapter sont incomplètes, et T4 donne une consigne fausse.** T4 écrit :
  « Les tests upstream des trackers doivent passer sans modification ». C'est faux : `simkl_client_test.dart:84,86` et
  `simkl_auth_service_test.dart:73` attendent `'plezy'` et `'plezy/$appVersion'`. Un codeur qui suit la consigne
  serait poussé à garder `appName = 'plezy'`.
  → T4 : remplacer la phrase par « adapter `test/services/trackers/simkl_client_test.dart:84,86` et
  `simkl_auth_service_test.dart:73` (`SimklConstants.appName`) ; les autres tests des trackers passent sans
  modification ».
  → T2 : ajouter à la liste des tests à adapter (tous vérifiés dans le code) :
  - `test/utils/media_image_helper_test.dart:438` et `test/widgets/optimized_media_image_test.dart:52` (User-Agent) ;
  - `test/services/companion_remote_lan_discovery_service_test.dart:200` (`'app': 'plezy'`, la balise serait filtrée) ;
  - `test/services/jellyfin_client_urls_test.dart:3396,3420,3431` (`Client="Plezy%20…"`) ;
  - `test/screens/profile/profile_switch_screen_test.dart:83` (`plezy://open?profile=…`) ;
  - `test/services/settings_export_service_test.dart:933-938` (`plezy-settings-…`).
  → T3 : ajouter `test/services/discord_rpc_service_test.dart` (tout le fichier) en `skip: forkRemovedSkip`. La garde
  `if (!isAvailable) return;` dans `_connect()`, que j'avais proposée, rend inopérants ses `setEnabled(true)` (l. 62, 94,
  114, 124, 162, 195), car `isAvailable` est statique et devient toujours faux.

⚠️ Non bloquants, à intégrer si le pilote les juge pertinents :
- T3 : `test/startup_bootstrap_test.dart:467` : plutôt que d'ignorer tout le test (il vérifie aussi d'autres boutons),
  remplacer cette seule attente par `findsNothing`. Même choix possible pour `startup_failure_view_test.dart:100`.
- T3 : `fork_features.dart` importe `SupporterMode`, et `supporter_mode.dart` importera `ForkFeatures` : import
  circulaire. C'est légal en Dart (aucun cycle de constantes), mais il faut l'indiquer pour que le codeur ne cherche pas
  à le « corriger ».
- T3 : mon test de garde propose une exception pour `anime_mappings_decoder.dart`, mais `edde746` n'y apparaît que dans
  des commentaires, qui sont déjà exclus. Exception inutile.
- T5 : `normalize(en_node, loc_node, path, stats, plural_categories)` prend 5 arguments. Indiquer de reproduire l'appel
  de `clean_pass()` (`clean_translations.py:157`) pour la sortie canonique.
- T6 : préciser comment forcer le mode TV dans le test (la surcharge de test de `PlatformDetector` utilisée par les
  tests de focus TV existants) pour couvrir P2.
- Le plan a bien repris le point CA19e : le comportement upstream (code expiré, pas de réseau) reste inchangé, rien à
  coder, à vérifier à la main avec les vrais identifiants (A6/A7).

## Réponse du pilote — tour 1 (architecte-plateforme)

Les trois objections sont vérifiées dans le code et acceptées. `plan.md` est corrigé (statut toujours « brouillon »).

- ❌1 accepté — **T1/T4** : ajout de `ForkTrackerDefines` (4 `static const String` lus par
  `String.fromEnvironment('POPKINO_…')`) dans `lib/fork/fork_trackers.dart` ; `ForkTrackerCredentials.fromEnvironment`
  est construit à partir d'eux ; T4 fait référencer `ForkTrackerDefines.*` par `trakt_constants.dart`,
  `simkl_constants.dart` et `mdblist_constants.dart`.
- ❌2 accepté — **T3** : vérifié dans `test/android/network_security_config_test.dart` (l. 25-40 sources scannées,
  égalité avec `CertificateTrust.fixedEndpointDomains` et le XML, domaine attendu qui doit être observé). T3 retire
  `plezy.app` de `lib/utils/certificate_trust.dart:37`, de `network_security_config.xml:33-36` et de `_expectedDomains`,
  et retire `plezy_server.dart` et `main.dart` de `_fixedEndpointSourcePaths`. La garde Dart n'a plus d'exception
  `plezy.app`. T9 ne touche pas ce XML : pas de dépendance ajoutée.
- ❌3 accepté — **listes de tests** : T4 adapte `simkl_client_test.dart:84,86` et `simkl_auth_service_test.dart:73`
  (la phrase fausse est remplacée) ; T2 ajoute les 6 fichiers cités (lignes vérifiées : 438, 52, 200, 3396/3420/3431,
  83, 933-938) et un `grep` de contrôle en fin de tâche ; T3 met `test/services/discord_rpc_service_test.dart` en
  `skip: forkRemovedSkip`.
- ⚠️ intégrés :
  - `findsNothing` au lieu de `skip` pour `startup_bootstrap_test.dart:467` et `startup_failure_view_test.dart:100` ;
  - import circulaire `fork_features.dart` ↔ `supporter_mode.dart` signalé comme voulu (T1 et T3) ;
  - exception `anime_mappings_decoder.dart` retirée de la garde (seulement des commentaires) ;
  - T5 : appel exact de `normalize(en, loc, "", stats, locale_plural_categories(en, loc))` puis `dump_json`, comme
    `clean_pass()` (`clean_translations.py:157-176`) ;
  - T6 : mode TV forcé par `TvDetectionService.debugSetAppleTVOverride(true)` (lu par `PlatformDetector.isTV()`),
    remis à `null` en `tearDown`, comme `test/navigation/settings_shortcut_test.dart`, plus un test hors TV.
- CA19e : d'accord, rien à coder, vérification manuelle en A7.

Demande : validation du plan corrigé (tour 2).

## Validation du plan — tour 2 (architecte-app)

**APPROUVÉ.** Les 3 objections du tour 1 sont corrigées dans `plan.md`, et chaque correction a été revérifiée dans le
code :
- `ForkTrackerDefines` donne des `static const String` que les constantes upstream peuvent référencer (T1 l. 89-95, T4).
- T3 traite `network_security_config_test.dart` (domaine retiré à 3 endroits, 2 fichiers sortis de la liste scannée).
- Les listes de tests de T2, T3 et T4 sont complètes, et la consigne fausse sur les trackers est remplacée.

Les ⚠️ intégrés sont exacts :
- l'appel `normalize` reproduit celui de `clean_pass()` (`clean_translations.py:170-171`) ;
- `TvDetectionService.debugSetAppleTVOverride` existe (`platform_detector.dart:195`) et est lu par `isTV()` via
  `isTVSync()` (l. 182, 218).

Aucune nouvelle objection bloquante.

## Ajustements pendant le code (architecte-plateforme, pilote)

### T11 — identité Windows (retour du codeur : BLOQUÉ sur `ci_guard_checks.sh`)
- `scripts/checks/check_windows_msix.py` (l. 242-251) exige `Application/@Executable` = `BINARY_NAME` de
  `windows/CMakeLists.txt`. **Décision : option (a)** — T11 modifie aussi `windows/build-msix.ps1:99`
  (`Executable="popkino.exe"`, `# FORK:`). Une ligne, effet nul (MSIX non construit dans le fork), et le contrôle
  upstream reste intact ; l'option (b) affaiblirait une garde upstream et créerait un conflit de plus dans un script
  de contrôle.
- `build.yml:487` (`requiredFiles` `plezy.exe`) et les `forbiddenFiles` `plezy.lib`/`plezy.exp` : déjà dans T13,
  formulation précisée dans `plan.md`. Sans effet tant que `build.yml` n'est pas lancé (il ne tourne que sur `main`,
  après fusion de T11 et T13).
- Changement de `APP_GUID` dans `scripts/checks/check_windows_installer.py` : **validé** (la garde fige le GUID ;
  même fichier que la tâche) ; ajouté à T11 dans `plan.md`.
- `scripts/format_native.sh` impossible sans JDK 17+ ni `clang-format` : **accepté pour T11** (remplacements de
  littéraux). Règle ajoutée au plan pour T9 à T12 : le contrôle `format_native.sh --check` de `ci.yml` fait foi au
  premier push ; installation recommandée pour T9 (`brew install openjdk@17 clang-format`).

### T10 — identité Apple (retour du codeur : 4 points hors plan)
1. **Tests macOS cassés : oui, et la CI les exécute** (`ci.yml`, job `apple-native-test`, matrice macOS :
   `xcodebuild test -scheme Runner`). `PRODUCT_NAME = Popkino` renomme l'exécutable et le module Swift. **Décision** :
   `PRODUCT_MODULE_NAME = Plezy` dans `AppInfo.xcconfig` (module = identifiant interne invisible, autorisé) + `TEST_HOST`
   vers `Popkino.app/…/Popkino` (3 lignes). `RunnerTests.swift` reste intact, donc pas de conflit sur les futurs tests
   upstream. `MainMenu.xib` utilise `customModuleProvider="target"` : insensible au nom du module. → **T10b**.
2. **Clés fixes `com.edde746.plezy.*` : on garde.** `setFrameAutosaveName` écrit dans les préférences de l'app, rangées
   par bundle id (`io.github.adrien24.popkino` ≠ Plezy) ; l'élément Keychain tvOS est cloisonné par
   `kSecAttrAccessGroup` = App Group, déjà passé à `group.io.github.adrien24.popkino` (T10). Aucune collision possible :
   CA8 tenu (tvOS n'est d'ailleurs pas dans CA8). Invisible pour l'utilisateur, autorisé par TRADEMARKS ; Runner et
   extension restent d'accord. Rien à planifier ; la garde T15 ne vise pas les chaînes Swift.
3. **« Plezy Top Shelf » : on corrige.** Hors champ de CA9 (écrans de l'app) mais c'est un `CFBundleDisplayName`,
   donc un « nom affiché » au sens de `regles-fork` (Réglages tvOS, App Store Connect). Une ligne → **T10b** ; la garde
   T15 doit attraper tout `CFBundleDisplayName` *contenant* « Plezy ».
4. **Fastfile `Plezy.ipa` : sans effet.** C'est la lane App Store upstream (`deploy_appstore`, Sentry, IAP), non utilisée
   par le fork. Les artefacts de release viennent de `build.yml`, qui zippe `build/ios/iphoneos/Plezy.app` en
   `popkino-ios.ipa` (T13, déjà prévu). Le nom du `.app` dans l'IPA est interne ; l'utilisateur voit
   `CFBundleDisplayName = Popkino`. Fichier laissé intact ; `ios/fastlane/**` ajouté aux exclusions de T15.
