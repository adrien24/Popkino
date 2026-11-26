---
name: conventions-code
description: Structure du code, conventions et commandes de vérification du fork Plezy (Flutter/Dart, Kotlin, codegen, slang, tests, build APK). À charger avant de concevoir ou d'écrire du code dans le dépôt, ou pour lancer les vérifications.
user-invocable: false
---

# Conventions du code

Relevé sur l'upstream (Plezy 2.26). À compléter quand les architectes découvrent une convention : ils proposent
l'ajout, l'orchestrateur l'écrit ici.

## Pile technique

- Flutter ≥ 3.47, Dart ≥ 3.12 (et < 3.13 tant que `freezed` 3 est utilisé : ne pas relever le plancher du SDK).
- État : `provider`. Base locale : `drift`. Modèles : `freezed` et `json_serializable` (fichiers `*.g.dart` et
  `*.freezed.dart` générés, à ne jamais éditer à la main).
- Traductions : `slang` (config `slang.yaml`, sources dans `lib/i18n/`). Tout texte visible passe par slang, jamais en
  dur dans un widget.
- Lecteur vidéo : mpv (`lib/mpv/`, natif dans `android/app/src/main/cpp/`).
- Android : `android/app/build.gradle.kts`, minSdk 25 (Fire OS), Kotlin dans `android/app/src/main/kotlin/`.

## Où se trouve quoi (`lib/`)

`screens/` écrans · `widgets/` composants · `providers/` état · `services/` logique et clients (dont `plex_client`,
`jellyfin_client`, `update_service.dart`, `settings_service.dart`) · `models/` · `database/` · `focus/` et `navigation/`
navigation TV au D-pad · `i18n/` traductions · `theme/` · `utils/`.

Code propre au fork : à placer de préférence dans des fichiers nouveaux et identifiables. La convention exacte (par ex.
un dossier `lib/fork/`) est à fixer par les architectes dans `docs/technique/decisions.md`. Toute modification d'un
fichier upstream est signalée par `// FORK: <raison>` (cf. skill `regles-fork`).

## SDK Flutter : toujours 3.47.1 (version de la CI)

Un Flutter plus récent (Homebrew, 3.50) est aussi installé sur la machine mais produit des faux positifs. **Préfixe
chaque commande Bash** par :

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
```

`JAVA_HOME` (Java 21, comme la CI) sert à `scripts/format_native.sh` (Kotlin) et aux builds Android ; `clang-format` et `swift-format` sont installés via Homebrew.

## Mise en route (déjà faite sur cette machine)

```bash
flutter pub get
(cd packages/wakelock_plus && flutter pub get --enforce-lockfile --no-example)
scripts/codegen.sh          # traductions + code généré
```

## Vérifications (à lancer avant de déclarer une tâche terminée)

Ce sont les mêmes contrôles que la CI (`.github/workflows/ci.yml`). Ligne de base au 2026-11-26 (code upstream intact) : tout passe, dont 8504 tests (7 ignorés). Tout échec de test vient donc de nos modifications.

```bash
dart format <fichiers modifiés>                   # la CI exclut *.g.dart et *.freezed.dart
scripts/format_native.sh --fix                    # si du Kotlin, du C/C++ ou du Swift a été modifié
scripts/codegen.sh                                # si modèles, base drift ou traductions ont changé
scripts/codegen.sh --check                        # le code généré est à jour
python3 scripts/checks/clean_translations.py --check --strict   # si des traductions ont changé
dart run scripts/checks/check_analyzer.dart       # analyse officielle (≠ `flutter analyze` brut)
bash scripts/ci_guard_checks.sh                   # gardes du dépôt (+ tests scripts/*/test_*.py)
scripts/run_tests.sh [test/chemin_test.dart]      # flutter test parallélisé ; sans argument = toute la suite
```

Ne lance jamais `dart format .` sur tout le dépôt : il reformate des `*.g.dart` générés et crée des diffs parasites.
Formate uniquement les fichiers que tu as modifiés.

Ne lance `git checkout`, `git stash`, `git reset` ou `git restore` sous aucun prétexte : d'autres agents peuvent travailler en même
temps dans le même dossier.

Pendant une tâche, lance d'abord les tests ciblés, puis toute la suite quand la tâche est finie si elle touche du code
partagé.

## Build Android

```bash
# APK de test pour la TV (sideload), avec la vérification de mise à jour activée
flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true \
  --dart-define-from-file=popkino_secrets.json   # identifiants Trakt/Simkl/MDBList (POPKINO_*), fichier local hors git
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (la plupart des TV récentes)
#   ou app-armeabi-v7a-release.apk (TV anciennes ou d'entrée de gamme)
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

La signature de release lit `android/key.properties`. Sans ce fichier, l'APK est signé avec la clé de debug.
**Ne jamais commiter** `key.properties` ni le keystore.

## Style

- Respecter `analysis_options.yaml` et `.editorconfig` ; suivre le style du fichier voisin.
- Commentaires en anglais dans le code (cohérence avec l'upstream), sauf les marqueurs `// FORK:` qui peuvent être en
  français.
- Pas de `print` : utiliser `appLogger` (`lib/utils/app_logger.dart`).
- Options de build : des `bool.fromEnvironment` constants (`ENABLE_*`, `SUPPORTER_MODE`, `TVOS_BUILD`, `PLEZY_*` pour
  le debug).
- Tests : référencer les constantes par leur nom (`MdblistConstants.clientId`), jamais par leur valeur.

## Traductions (détails)

- Les `lib/i18n/*.i18n.json` sont au format `json.dumps(indent=2, ensure_ascii=False)`, dans l'ordre des clés de `en`,
  normalisés par `scripts/checks/clean_translations.py`.
- Les textes en dur dans les widgets sont détectés par `scripts/checks/check_hardcoded_strings.py`.

## TV

- `FocusedScrollScaffold` donne le focus au premier élément de contenu au D-pad : base à utiliser pour un écran de
  réglages TV.
- `openExternalUrl` (`lib/utils/external_url.dart`) renvoie `false` quand rien ne peut ouvrir l'URL (fréquent sur TV,
  souvent sans navigateur) : l'appelant doit proposer une alternative, par exemple un QR code (`qr_flutter`).
