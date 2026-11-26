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
