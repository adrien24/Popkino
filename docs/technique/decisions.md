# Décisions d'architecture durables

Chaque décision s'applique à tout le fork tant qu'une décision ultérieure ne la remplace pas explicitement. Une
proposition qui s'en écarte doit le dire et justifier pourquoi.

## D1 — Identité de l'app (2026-11-26)
Contexte : le nom et le logo Plezy ne sont pas couverts par la GPL (`TRADEMARKS.md`) ; l'identifiant d'une app ne peut
plus changer après sa première publication. Décision de l'utilisateur (spec `nouvelle-identite`, P7).
Décision : nom affiché `Popkino` ; identifiant `io.github.adrien24.popkino` sur toutes les plateformes (Android
`applicationId`, bundle iOS/macOS/tvOS, `APPLICATION_ID` Linux, id Flatpak) ; extension tvOS
`io.github.adrien24.popkino.TopShelfExtension`, App Group `group.io.github.adrien24.popkino` ; schéma d'URL
`popkino://` ; dépôt `adrien24/popkino` ; flux de mise à jour
`https://cdn.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml` ; éditeur affiché `adrien24`.
Conséquences : ces valeurs ne changent plus après la release 1.0.0. Côté Dart, elles vivent dans
`lib/fork/fork_identity.dart` ; côté natif, dans les fichiers de chaque plateforme, contrôlés par
`scripts/fork/check_identity.py`.

## D2 — Emplacement du code propre au fork (2026-11-26)
Contexte : fusionner régulièrement `edde746/plezy` sans conflit inutile.
Décision : code Dart du fork dans `lib/fork/`, tests dans `test/fork/`, outillage dans `scripts/fork/`, sources de
marque (logo, couleurs) dans `branding/`, documentation dans `docs/`. Un nouveau fichier est toujours préféré à la
modification d'un fichier upstream.
Conséquences : `grep -rn "FORK:"` et ces dossiers donnent l'inventaire complet des écarts avec l'upstream.

## D3 — Modifications de fichiers upstream : en place, petites, marquées (2026-11-26)
Contexte : renommer au moment du build ferait livrer un code différent de celui testé ; supprimer du code upstream
crée des conflits modify/delete.
Décision : on modifie la ligne concernée et on la marque `FORK: <raison>` dans la syntaxe de commentaire du fichier
(`//`, `#`, `<!-- -->`). Les fichiers sans commentaire possible (pbxproj, JSON, binaires) sont couverts par la garde
(D8). Les **identifiants internes de Plezy sont conservés** (package Dart `plezy`, package Kotlin `com.edde746.plezy`,
`PlezyActivity`, canaux `com.plezy/*`, préfixe `plezy_` des identifiants de contenu de la rangée Android TV, binaire
Linux `plezy`, noms de fichiers `assets/plezy.*`, `plezy.icon`, `tv_banner.png`) : on remplace les **valeurs visibles et
les contenus**, pas les noms internes.
Conséquences : les conflits de fusion se limitent aux lignes marquées ; les images remplacées se résolvent en gardant
la version du fork puis en relançant `scripts/fork/generate_brand_assets.py`.

## D4 — Services du projet Plezy neutralisés par des constantes Dart, pas supprimés (2026-11-26)
Contexte : `build.yml` (upstream) passe `ENABLE_DONATIONS=true` et `SUPPORTER_MODE`, `deploy.py` force
`ENABLE_SENTRY=true` ; `flutter test` tourne sans `--dart-define`. Supprimer MAL/AniList toucherait ~97 fichiers.
Décision : chaque service Plezy (Sentry, envoi de journaux, Discord, dons, achat supporter, icônes alternatives,
MAL/AniList, correspondances d'anime, migrations héritées) est coupé au point d'entrée par une constante `const` de
`lib/fork/fork_features.dart`. La base réseau `plezyServerBaseUrl` pointe vers un domaine `.invalid`. Les drapeaux de
CI upstream (`ENABLE_DONATIONS`, `ENABLE_SENTRY`, `SUPPORTER_MODE`) restent dans `build.yml` mais sont sans effet. Les
tests upstream d'une fonction retirée sont marqués `skip:` (constante `forkRemovedSkip`), pas supprimés.
Conséquences : réactiver un service (backlog `services-suivi`) = passer une constante à `true` et fournir notre
propre serveur.

## D5 — Secrets de build (2026-11-26)
Décision : les seuls `--dart-define` propres au fork sont préfixés `POPKINO_` et lus uniquement dans `lib/fork/`
(`POPKINO_TRAKT_CLIENT_ID`, `POPKINO_TRAKT_CLIENT_SECRET`, `POPKINO_SIMKL_CLIENT_ID`, `POPKINO_MDBLIST_CLIENT_ID`).
Une valeur vide masque la fonction. En CI, ils viennent des secrets GitHub du même nom sans préfixe ; en local, de
`popkino_secrets.json` (ignoré par git) via `--dart-define-from-file`.

## D6 — Traductions dérivées par script (2026-11-26)
Décision : dans le fork, `lib/i18n/*.i18n.json` ne s'éditent jamais à la main. Ils sont produits par
`scripts/fork/rebrand_i18n.py` à partir de la version upstream, de `lib/fork/i18n/` (surcouche, clés `fork.*`) et de
`lib/fork/i18n/rebrand_rules.json`. Le script finit par la normalisation de `scripts/checks/clean_translations.py`.
Ordre obligatoire : script → `scripts/codegen.sh` → commit des JSON et des `strings_*.g.dart`. En conflit de fusion :
version upstream, puis relancer le script.
Conséquences : un script de génération n'est justifié que par le volume ou la grammaire (traductions, images) ;
partout ailleurs, édition en place + garde.

## D7 — Deux canaux de distribution, un seul code (2026-11-26)
Décision : les versions GitHub sont construites avec `--dart-define=ENABLE_UPDATE_CHECK=true` ; toute version store
(AAB Play, Amazon, App Store, Microsoft Store) est construite **sans** ce define (pas de mise à jour hors store,
`regles-fork` §3). Pas de flavor Gradle tant que le manifeste n'a pas à différer entre les canaux. La permission
`com.android.vending.BILLING` est retirée du manifeste (l'app est gratuite).

## D8 — Gardes d'identité (2026-11-26)
Décision : deux gardes complémentaires, sans recouvrement. `test/fork/*_test.dart` couvre `lib/` et `lib/i18n/`
(URL Plezy, identifiants des trackers, valeurs « Plezy », valeurs à l'exécution). `scripts/fork/check_identity.py`
couvre tout le reste (manifestes, plist, pbxproj, rc, CMake, packaging, workflows, clés publiques) et vérifie que les
valeurs natives égalent celles de `lib/fork/fork_identity.dart`. Branchement sans nouveau workflow : `scripts/run_tests.sh`
pour les tests Dart, et le glob `scripts/*/test_*.py` de `scripts/ci_guard_checks.sh` pour les scripts du fork.
Conséquences : un `scripts/fork/test_*.py` ne doit dépendre que de Python 3 standard (il tourne sur le runner
`ubuntu-latest` de `ci.yml` sans outil d'image).

## D9 — Clés de signature et secrets (2026-11-26)
Décision : clé Android RSA 4096 au format PKCS12, alias `popkino`, mêmes mots de passe pour le magasin et la clé ;
clé Ed25519 unique pour Sparkle (macOS) et WinSparkle (Windows). Toutes appartiennent à l'utilisateur, sont rangées
dans les secrets GitHub aux noms utilisés par l'upstream (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`,
`ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`, `SPARKLE_PRIVATE_KEY`) et sauvegardées hors de GitHub. Elles ne sont
jamais commitées. Les secrets Apple, `BUGS_ADMIN_TOKEN` et `WINGET_TOKEN` ne sont pas créés.
Conséquences : perdre une clé empêche toute mise à jour des installations existantes.

## D10 — Version propre au fork (2026-11-26)
Décision : numérotation indépendante de Plezy, en `X.Y.Z+N` dans `pubspec.yaml`, à partir de `1.0.0+1` ; le tag de
release est `X.Y.Z` (numérique, sans préfixe ni suffixe, exigé par `UpdateService` et `build.yml`).
Conséquences : la ligne `version:` de `pubspec.yaml` est en conflit à chaque montée de version upstream ; on garde
toujours la nôtre.

## D11 — Changer un comportement upstream par un crochet « null = upstream » (2026-11-26)
Contexte : `langues-preferees` modifie l'ordre de sélection des pistes (`TrackSelectionService`), un fichier upstream
très remanié dont le mainteneur considère l'ordre comme voulu (#1615) ; l'écart est donc permanent.
Décision : la logique du fork vit dans `lib/fork/` en fonctions pures ; le fichier upstream ne contient qu'un appel
marqué `// FORK: <slug> — <raison>` dont le résultat `null` laisse l'upstream décider. On n'ajoute aucune valeur aux
enums upstream (les `switch` exhaustifs restent intacts) ; une décision du fork réutilise une valeur existante.
Conséquences : un conflit de fusion se limite à replacer l'appel ; les tests `test/fork/` signalent un crochet perdu.

## D4 (extension) — Tests upstream dont le comportement est changé par le fork (2026-11-26)
Décision : un test upstream dont le résultat change volontairement à cause du fork n'est ni supprimé ni réécrit ; il
reçoit `skip: forkChangedSkip` (`test/fork/fork_test_utils.dart`) et figure nominativement, avec le CA qui le justifie,
dans `forkChangedSkipAllowlist` et dans le `plan.md` de la fonctionnalité. Une garde (`test/fork/fork_changed_skip_guard_test.dart`)
échoue si le nombre de `forkChangedSkip` hors de `test/fork/` diffère de cette liste. Le comportement du fork est testé
dans `test/fork/`.
Conséquences : un `skip` ajouté lors d'une fusion ne peut pas masquer une régression upstream sans mise à jour visible
de la liste.

## D6 (extension) — Surcharge d'une clé de traduction upstream (2026-11-26)
Décision : la surcouche `lib/fork/i18n/<locale>.json` peut, en plus des clés `fork.*`, **surcharger une clé upstream
existante** quand seul le texte change (premier cas : `accountPreferences.autoSelectAudioDescription`). La surcharge est
signalée dans le `_comment` de `lib/fork/i18n/rebrand_rules.json`. Les langues non surchargées gardent le texte upstream.
Conséquences : aucun changement Dart pour un correctif de libellé ; à la fusion, relire les clés surchargées si
l'upstream change leur sens.

## D12 — Règles de choix de pistes du fork (2026-11-26)
Contexte : `langues-preferees`, `meilleure-piste-audio` et `sous-titres-mal-etiquetes` empilent des règles sur le même
choix automatique ; une mesure sur la Fire Stick (TV LG seule annonçant 8 canaux, Dolby, DTS) montre que la sortie
audio réelle n'est pas détectable.
Décision : toutes les règles de choix automatique de pistes du fork vivent dans `lib/fork/preferred_languages.dart`
(et ses fichiers d'aide dans `lib/fork/`), derrière les crochets de D11, sans nouvelle ligne upstream. Elles s'appuient
sur des réglages existants (« Canaux audio », préférences du compte) plutôt que sur une détection matérielle ou un
nouveau réglage, se taisent (`null`) quand une information manque, et ne lisent que les métadonnées de l'auteur du
fichier (`title` de la ligne serveur ou du conteneur), jamais les libellés calculés par le serveur (`displayTitle`,
`extendedDisplayTitle`).
Conséquences : un nouveau besoin de choix de piste s'ajoute à ce fichier ; une détection de l'installation audio
(par exemple PCM 5.1 via `AudioTrack.isDirectPlaybackSupported`) serait une fonctionnalité à part, testée sur matériel.

## D7 (amendement) — Le manifeste diffère entre canaux, toujours sans flavor (2026-11-28)
Contexte : `bouton-mise-a-jour` ajoute `REQUEST_INSTALL_PACKAGES` et un installeur Kotlin, interdits sur Google Play.
Un flavor serait une seconde bascule, désynchronisable avec `ENABLE_UPDATE_CHECK`.
Décision : `ENABLE_UPDATE_CHECK=true` reste l'unique bascule. Gradle la lit dans `-Pdart-defines` (ou
`-PpopkinoSideload=true` pour `./gradlew` direct en CI) et ajoute alors `android/app/src/sideload/` (manifeste avec la
permission, Kotlin). Sinon, il ajoute `src/nosideload/` (no-op). Une tâche `bundle*` ou un build `AMAZON` avec ce
define échoue. Le choix est sûr par défaut : sans le define, ni permission, ni code d'installation.
Conséquences : `scripts/fork/test_sideload_isolation.py` vérifie que rien de l'installeur ne sort de `src/sideload*/`.
La CI teste la variante sideload (`testDebugUnitTest -PpopkinoSideload=true`) et compile l'autre (`lintDebug`).

## D10 (amendement) — Numéro de build (2026-11-28)
Contexte : avec `--split-per-abi`, versionCode = ABI × 1000 + N ; des APK 0.2.0+5 sont déjà installés.
Décision : `N` ne redescend jamais sous le plus grand N déjà publié (5 au 2026-11-28 ; la 1.0.0 sera au moins `+6`)
et reste inférieur à 1000. Le tag reste `X.Y.Z` sans préfixe ; les anciens tags `v0.x` restent et sont acceptés par
la vérification. Les APK de release s'appellent `popkino-android-<abi>-<X.Y.Z>.apk` (APK nus, plus de `.tar.gz`).

## D13 — Fonctionnalités du fork : dossier, état, constante éliminable (2026-11-28)
Contexte : `bouton-mise-a-jour` est la première fonctionnalité du fork à plusieurs fichiers, avec un état et un
code interdit dans les versions store.
Décision :
- une fonctionnalité du fork de plus de 2 fichiers vit dans `lib/fork/<sujet>/` (tests dans `test/fork/<sujet>/`) ;
- son état global est un `ChangeNotifier` singleton, exposé derrière la même constante (collection-if
  `if (k…) ChangeNotifierProvider.value(...)`) dans le `MultiProvider` de `lib/main.dart` (une ligne `// FORK:`).
  Le singleton n'est jamais référencé hors d'un test de cette constante, sinon l'AOT le garde dans les autres builds. Il est lu dans les fichiers upstream par
  `context.watch<T?>()` ou `read<T?>()` (nullable), pour que les tests upstream sans ce provider restent verts ;
- un code réservé à une distribution est gardé par une constante
  `const bool k… = bool.fromEnvironment(...)`, testée en tête de chaque point d'entrée, avec un forçage de test
  limité à `kDebugMode`. L'AOT l'élimine alors des autres builds, ce qui se vérifie par `strings libapp.so`.
Conséquences : un crochet upstream reste une ligne (D11) ; une garde `test/fork/` vérifie les crochets et le test de
constante.

## D14 — Code natif Android du fork (2026-11-28)
Décision : le Kotlin propre au fork vit dans le package `com.edde746.plezy.fork`. Il est enregistré par l'unique
appel `ForkPlugins.register(flutterEngine)` de `PlezyActivity.configureFlutterEngine`. Le code propre à un canal de
distribution vit dans `android/app/src/<canal>/`, ajouté par le bloc `FORK` en fin de `build.gradle.kts` (D7
amendé). Les canaux de méthodes nouveaux du fork sont nommés `popkino/<sujet>` ; les canaux upstream `com.plezy/*`
restent inchangés (D3).
