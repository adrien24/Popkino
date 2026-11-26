# Plan technique — sous-titres-mal-etiquetes

Spec : docs/produit/specs/sous-titres-mal-etiquetes.md
Statut : approuvé       Pilote : architecte-app

Sources : `proposition-app.md`, `proposition-plateforme.md` et `debat.md` (tour 1, aucun ❌). La précision de la
spec du 2026-11-26 est intégrée : seuls le français et l'anglais sont reconnus.

Branche : `feat/sous-titres-mal-etiquetes`, **créée à partir de `feat/meilleure-piste-audio`** une fois celle-ci
terminée. Les deux fonctionnalités modifient `lib/fork/preferred_languages.dart` et ses tests.

## Décisions

1. **Langue effective d'un sous-titre = langue nommée par le titre de l'auteur, sinon la langue indiquée.** Elle ne
   sert qu'à la règle du fork (`forkPreferredSubtitle`). Les pistes et leurs libellés ne sont jamais modifiés (CA8).
   Raison : c'est la décision de l'utilisateur, avec le diff le plus petit possible, et aucun fichier upstream touché.
2. **Seul le titre écrit par l'auteur du fichier est lu** :
   - descripteur `source:<N>` → le `title` de la ligne serveur d'id N (`plexMediaInfo.subtitleTracks`), sinon `null` ;
   - piste native **intégrée** (`!isExternal`) → `SubtitleTrack.title`, le nom donné par le conteneur ;
   - piste native **externe** → aucun titre : pour mpv, son titre vient du nom de fichier ou de l'URL ;
   - jamais `displayTitle` ni `extendedDisplayTitle`, que le serveur fabrique à partir de la langue indiquée.

   Raison : CA3, et les demandes de la plateforme.
3. **Reconnaissance sur des mots entiers, à deux niveaux.** Les mots forts (noms de langue et marqueurs VF) l'emportent
   sur les mots faibles (codes). Si le titre nomme plusieurs langues ou aucune, il est ignoré. Raison : pas de faux
   positifs comme « en » dans « Sous-titres en français » ou « fre » dans « Freedom ».
4. **Les pistes bien étiquetées passent d'abord (CA7)** : tri stable avant les règles existantes
   (non forcée, `isDefault`, première).
5. **Français et anglais seulement**, dans une table de constantes extensible (backlog `titres-autres-langues`).
6. **Aucune ligne upstream.** Tout se passe dans `lib/fork/`.

### Reconnaissance — `forkLanguageNamedByTitle(String? title) → String?`

Elle renvoie `'fre'`, `'eng'` ou `null`.
- **Normalisation** : minuscules, accents retirés (`é`→`e`, `ç`→`c`, au moins pour les lettres latines courantes),
  découpage par `RegExp(r'[^a-z]+')` (`static final`). Le résultat est une liste de mots.
- **Mots forts** :
  - fre : `french`, `francais`, `vf`, `vff`, `vfq`, `vfi`, `vostfr`, `truefrench` ;
  - eng : `english`, `anglais`.
- **Mots faibles** :
  - fre : `fr`, `fre`, `fra` ;
  - eng : `en`, `eng`.
- **Ignorés** : `vo`, `vost`, et tout autre mot.
- **Règle** :
  - si les mots forts nomment exactement une langue, c'est elle ;
  - sinon, si aucun mot fort n'est présent et que les mots faibles nomment exactement une langue, c'est elle ;
  - sinon `null`.

## Tâches

### T1 — Reconnaissance de la langue dans un titre
- Complexité : S
- Dépend de : —
- Fichiers :
  - créer `lib/fork/subtitle_title_language.dart` ;
  - créer `test/fork/subtitle_title_language_test.dart`.
- À faire : écrire `forkLanguageNamedByTitle`, exactement comme décrit plus haut. C'est une fonction pure, sans
  dépendance à `SettingsService` ni au lecteur.
- Tests :
  - chaque mot de CA4, en majuscules, en minuscules et en casse mixte ;
  - « French Complet » → fre ; « French Forced » → fre ; « Français » → fre ;
  - « Sous-titres en français » → fre (le mot fort l'emporte) ;
  - « English / French » → `null` ;
  - « VO » et « VOST » → `null` ;
  - « Freedom », « Enfant », « Frénésie » → `null` ;
  - « VOSTFR » → fre ; « EN » → eng ; « eng.srt » → eng ;
  - « French Complet (English SRT) » → `null` (deux langues) ;
  - `null` et vide → `null`.
- Critères d'acceptation couverts : CA4, CA6 (titres sans langue).

### T2 — Langue effective dans la règle des sous-titres
- Complexité : L (choix des sous-titres à la lecture, avec des pistes natives qui arrivent tard)
- Dépend de : T1, et de la tâche T3 de `docs/technique/meilleure-piste-audio/plan.md`, la dernière qui modifie
  `lib/fork/preferred_languages.dart` et ses tests
- Fichiers :
  - modifier `lib/fork/preferred_languages.dart`, `test/fork/preferred_languages_test.dart` et
    `test/fork/preferred_languages_flow_test.dart`.
- À faire, dans `forkPreferredSubtitle` uniquement :
  - Écrire une fonction locale `String? authorTitle(SubtitleTrack t)` :
    - si `t.id` commence par `source:`, elle renvoie le `title` de la ligne de `service.plexMediaInfo?.subtitleTracks`
      d'id N, ou `null` si la ligne est introuvable (id périmé) : le `title` d'un descripteur peut venir du repli
      `displayTitle` (décision 2) ;
    - sinon, si `!t.isExternal` (piste native intégrée), elle renvoie `t.title` ;
    - sinon `null`.
  - Écrire `String? effectiveLanguage(SubtitleTrack t) => forkLanguageNamedByTitle(authorTitle(t)) ?? t.language;`,
    puis faire en sorte que `inSubtitleLanguage(t)` compare `effectiveLanguage(t)` à la langue préférée, avec
    `service.languageMatches`.
  - CA7 : avant `forced()` et `full()`, trier les candidates de façon stable. Rang 0 : la langue indiquée correspond à
    la langue préférée. Rang 1 : seule la langue tirée du titre correspond. Les règles existantes (non forcée,
    `isDefault`, première) restent appliquées dans cet ordre.
  - S3 : pour les lignes serveur annoncées, la langue effective vaut `forkLanguageNamedByTitle(row.title) ??
    (row.languageCode ?? row.language)`. Jamais `displayTitle`.
  - Journal : quand une piste choisie n'a sa langue que par le titre, ajouter
    `appLogger.d('Fork preferred language: subtitle title says <code>, declared <langue>')`.
  - Ne rien modifier d'autre : la règle des modes, `effectiveForced` (qui lit déjà « Forced » dans le titre) et la
    règle audio restent telles quelles.
- Tests :
  - `preferred_languages_test.dart` :
    - Green Lantern, avec les descripteurs `source:` et les lignes serveur « French Complet » (eng),
      « French Forced » (eng, titre forcé) et « English » (eng) :
      - audio anglais → French Complet (CA1) ;
      - audio français → French Forced (CA2) ;
      - en mode `always`, le vrai anglais n'est jamais retenu comme français (CA3) ;
    - une piste fre bien étiquetée et une piste « French » indiquée eng → la piste bien étiquetée (CA7) ;
    - titre et langue concordants (CA5) ;
    - pas de titre, ou titre neutre (CA6) ;
    - **piste native externe** dont le titre est un nom de fichier (`movie.fr.srt`, `subs-en.srt`) et la langue
      indiquée eng → la langue indiquée reste eng ;
    - ligne serveur sans `title`, avec `displayTitle`/`extendedDisplayTitle` « French Complet (English SRT) » → reste
      anglaise ;
    - S3 : une ligne serveur dont seul le `title` dit « French », pas encore arrivée en natif → `null` (attente
      upstream).
  - `preferred_languages_flow_test.dart` : Green Lantern en JSON Plex (`Part.Stream[]` avec `title`, `languageCode`
    eng, `displayTitle` et `extendedDisplayTitle` réels) et en JSON Jellyfin (`MediaStreams` avec `Title`,
    `Language` eng et `DisplayTitle`, CA9), via `PlaybackSubtitleResolver.resolve` :
    - `primarySourceStreamId` est celui de « French Complet » ;
    - le titre du descripteur retenu est celui d'origine (CA8).
- Critères d'acceptation couverts : CA1, CA2, CA3, CA5, CA6, CA7, CA8, CA9.

### T3 — Recette sur la Fire Stick
- Complexité : S
- Dépend de : T2
- Fichiers : aucun. Le compte rendu va dans `docs/technique/sous-titres-mal-etiquetes/recette.md`.
- À faire :
  - **Green Lantern en lecture directe (qualité Originale)**, audio anglais : « French Complet » est affiché et coché
    dans le menu (CA1, CA8).
  - **Même film, audio français choisi à la main** : « French Forced » (CA2).
  - **CA3** : choisir à la main la vraie piste anglaise : elle reste affichée « English ».
  - **Journal** : `adb logcat -v time -s flutter | grep -E "Subtitle:|Fork preferred"` doit afficher « title says fre,
    declared eng ».
  - **Non-régression** sur S3E8 (sous-titres bien étiquetés, CA5).
- Critères d'acceptation couverts : CA1, CA2, CA3, CA5, CA8 sur la TV.

## Vérification globale

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
dart format <fichiers modifiés>
dart run scripts/checks/check_analyzer.dart
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh test/fork/
scripts/run_tests.sh                       # suite complète, aucun nouvel échec ni nouveau skip
git diff feat/meilleure-piste-audio --stat -- lib ':!lib/fork'   # vide : aucun fichier upstream touché
```

## Risques restants

- **Sous-titres image en transcodage Plex** : la piste à incruster est choisie avant le resolver
  (`_resolveTranscodeSubtitleTrack`, `plex_client.dart` l.4022). Au lancement, c'est le `selected` du serveur qui
  l'emporte. Un « French Complet » en PGS mal étiqueté n'est donc pas incrusté. CA1 ne tient qu'en lecture directe ou
  avec des sous-titres texte. Ce n'est pas pire qu'aujourd'hui. Un choix manuel qui mène à une incrustation écrit sur
  le serveur (`selectSubtitleStreamForBurn`), c'est l'effet de bord connu.
- **Pistes externes vues après l'ouverture** : leur titre n'est pas lu. Elles restent couvertes avant l'ouverture par
  le resolver, via le `title` de la ligne serveur. Un sidecar sans ligne serveur (téléchargement ancien) garde sa
  langue indiquée.
- **Faux positif** : un titre qui nomme une langue sans parler de la piste. C'est rare et limité par les mots entiers
  et les deux niveaux de mots. On corrige à la main.
- **Report d'épisode** : un choix manuel d'une piste mal étiquetée garde la langue indiquée dans l'intention. Sur
  l'épisode suivant, la règle du fork choisit quand même la bonne piste.
- **Autres langues** non reconnues (backlog `titres-autres-langues`).
- **Fusions** : aucune ligne upstream.
