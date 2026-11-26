# Plan technique — meilleure-piste-audio

Spec : docs/produit/specs/meilleure-piste-audio.md
Statut : approuvé       Pilote : architecte-app

Sources : `proposition-app.md`, `proposition-plateforme.md` et `debat.md` (tour 1, aucun ❌). Les précisions de la
spec du 2026-11-26 sont intégrées : « D'origine » garde le choix actuel ; CA11 exclut les commentaires et
l'audiodescription ; CA12 précise les textes de « Canaux audio » ; aucun message supplémentaire sur le silence.

Branche : `feat/meilleure-piste-audio`. La fonctionnalité `sous-titres-mal-etiquetes` partira de cette branche
(même fichier `lib/fork/preferred_languages.dart`).

## Décisions

1. **Pas de détection de l'installation, ni sonde native.** Seul « Canaux audio » (`SettingsService.audioChannelLimit`)
   décide. Raison : mesure sur la Fire Stick, où une TV LG seule annonce 8 canaux, Dolby et DTS. Aucun signal public ne
   distingue une TV seule d'une barre de son en ARC (cf. `proposition-plateforme.md`).
2. **Correspondance**, au moment du choix :
   - Stéréo → sortie `stereo` ;
   - Jusqu'à 5.1 → `multichannel` ;
   - D'origine → `unknown` (choix d'aujourd'hui, CA1/CA3bis) ;
   - `SettingsService` non initialisé → `unknown`.

   Raison : ce sont les décisions du PO.
3. **La règle des canaux vit dans `lib/fork/`** et s'insère dans `forkPreferredAudio`. **Aucune ligne upstream
   ajoutée.** Raison : le crochet de `langues-preferees` dans `TrackSelectionService.selectAudioTrack` suffit (D11).
4. **Quand la sortie est connue et que la règle des canaux désigne une piste, elle l'emporte même si le serveur a déjà
   choisi la langue préférée.** C'est un assouplissement d'A2. Raison : PMS marque en général `selected` la première
   piste anglaise (la stéréo), et sans cela CA2 et CA3 échoueraient. Avec une sortie `unknown`, A2 reste inchangé
   (CA3bis).
5. **Le choix manuel mémorisé (A3) passe avant tout** (CA6). Il est vérifié avant la règle des canaux.
6. **Seules les pistes dont le nombre de canaux est connu et qui ne sont ni un commentaire ni une audiodescription
   participent** (CA11). S'il en reste moins de deux, ou si elles ont toutes le même nombre de canaux, la règle ne dit
   rien (CA4, CA5). Raison : ne jamais deviner et ne jamais régresser.
7. **L'intention de lancement porte le nombre de canaux visé** : 2 pour `stereo`, 6 pour `multichannel`, rien pour
   `unknown`. Raison : `_findTrackByEvidenceBands` départage déjà par parité de canaux. Cela règle le transcodage avec
   plusieurs pistes anglaises (risque restant de `langues-preferees`), sans effet sur CA9.
8. **CA12 se fait par la surcouche i18n**, en surchargeant les clés upstream `settings.audioChannelLimit*Description`
   (extension de D6), sans Dart. Raison : c'est le même mécanisme que pour CA9 de `langues-preferees`.
9. **Silence en DTS ou E-AC3 en transmission directe** : pas de code, pas de message (décision du PO). Le texte upstream
   de « Transmission audio directe » le dit déjà. On le vérifie en recette (T5).

### Règle des canaux — `forkBestTrackForOutput(List<AudioTrack> inLanguage, ForkAudioOutput output) → AudioTrack?`

- Si `output == unknown` → `null`.
- On garde comme candidates les pistes de `inLanguage` qui ont `channels != null` et dont
  `forkIsSpecialAudioTrack(t.title)` est faux.
- Si moins de 2 candidates, ou si toutes ont le même `channels` → `null`.
- Si `stereo` → les candidates avec `channels <= 2`. Aucune → `null`. Sinon, celle qui a `isDefault`, à défaut la
  première.
- Si `multichannel` → les candidates qui ont le `channels` maximal, puis `isDefault`, à défaut la première.

`forkIsSpecialAudioTrack(String? title)` découpe le titre en minuscules sur tout ce qui n'est pas une lettre. Elle
renvoie vrai si un mot entier vaut l'un de : `commentary`, `commentaries`, `commentaire`, `commentaires`, `description`,
`audiodescription`, `descriptive`, `ad`, `dvs`. L'expression est une `static final`, compilée une seule fois.

### Nouvel ordre de `forkPreferredAudio`

1. A1 (inchangé) ; `availableTracks` vide → `null`.
2. A3 : `hasManualPick(audio)` → `null`. Ce test, aujourd'hui placé après A2, est avancé ici : le résultat ne change
   pas, il passe simplement avant la règle des canaux.
3. `inLanguage` vide (A4) → `null`.
4. `best = forkBestTrackForOutput(inLanguage, forkAudioOutput())`. S'il n'est pas `null`, on journalise
   `Fork preferred language: audio <langue>, channels <stereo|most>` et on renvoie `TrackSelectionResult(best,
   profile)`.
5. A2 (inchangé) : la ligne serveur est déjà dans la langue → `null`.
6. Sinon, on prend la piste `isDefault`, à défaut la première, et on journalise « current order ».

## Tâches

### T1 — Sortie audio lue dans « Canaux audio »
- Complexité : S
- Dépend de : —
- Fichiers :
  - créer `lib/fork/audio_output.dart` ;
  - créer `test/fork/audio_output_test.dart`.
- À faire :
  - Écrire `enum ForkAudioOutput { stereo, multichannel, unknown }` et une fonction synchrone
    `ForkAudioOutput forkAudioOutput()`. Elle lit `SettingsService.instanceOrNull?.read(SettingsService.audioChannelLimit)`
    et renvoie `stereo` → `stereo`, `surround51` → `multichannel`, `original` ou service absent → `unknown`.
  - Ne pas utiliser `AudioChannelLimit.onExoPlayer` : le choix de piste se fait en Dart pour les deux moteurs.
  - Aucune sonde native, aucun `await`.
- Tests :
  - les trois valeurs du réglage ;
  - service non initialisé → `unknown` ;
  - avec la valeur héritée `audio_downmix = true`, `LegacyBoolEnumPref` donne `stereo`.
- Critères d'acceptation couverts : CA1, CA3, CA3bis (correspondance).

### T2 — Règle des canaux dans le choix de la piste audio
- Complexité : L
- Dépend de : T1
- Fichiers :
  - modifier `lib/fork/preferred_languages.dart`, `test/fork/preferred_languages_test.dart` et
    `test/fork/preferred_languages_flow_test.dart`.
- À faire :
  - Écrire `forkIsSpecialAudioTrack` et `forkBestTrackForOutput` dans `preferred_languages.dart`, avec la
    visibilité publique pour les tests, exactement comme décrit plus haut.
  - Réordonner `forkPreferredAudio` selon le « Nouvel ordre ».
  - Ne toucher ni `forkPreferredSubtitle` ni aucun fichier upstream.
- Tests :
  - `preferred_languages_test.dart`, tests unitaires sur des `AudioTrack` construits à la main :
    - S3E8 (EN 2.0 AAC, FR 2.0, EN EAC3 5.1 titrée « ENG VO - EAC3 DDP 5.1 », FR 5.1) : `stereo` → EN 2.0,
      `multichannel` → EN 5.1, `unknown` → choix d'aujourd'hui ;
    - Green Lantern (EN 2.0, FR 2.0, EN DTS 5.1, FR AC3 5.1) : même chose ;
    - **seule la 5.1 indique ses canaux** (2.0 avec `channels: null`) : `stereo` → `null`, donc l'ordre actuel ;
      `multichannel` → `null` (moins de 2 candidates connues) ;
    - deux pistes anglaises 5.1 → `null` (CA5) ;
    - une seule piste anglaise (CA4) ;
    - « English 5.1 » + « English 2.0 Commentary » avec `stereo` → `null`, le commentaire n'est jamais choisi par la
      règle (CA11) ;
    - « Audio Description » 5.1 + « English 2.0 » avec `multichannel` → `null` (CA11) ;
    - le serveur a déjà choisi EN 2.0 (`selected`) et la sortie vaut `multichannel` → EN 5.1, priorité `profile`
      (A2 assoupli) ;
    - même cas avec `unknown` → `null` (A2) ;
    - `hasManualPick(audio)` vrai → `null` quelle que soit la sortie (CA6) ;
    - `autoSelectAudio` faux → `null` (CA8) ;
    - mots de `forkIsSpecialAudioTrack` : « Director's Commentary », « Commentaire audio », « AD », « Audiodescription »
      → vrai ; « ENG VO - EAC3 DDP 5.1 », « Adventure », « Headphones » → faux.

    Pour fixer la sortie, initialiser `SharedPreferences.setMockInitialValues` avec la clé de `audioChannelLimit`,
    comme dans `track_choice_memory_test.dart`.
  - `preferred_languages_flow_test.dart` : S3E8 et Green Lantern en JSON Plex (`Part.Stream[]` avec `channels`,
    `title`, et `selected` sur EN 2.0) et en JSON Jellyfin (`MediaStreams` avec `Channels`, `DefaultAudioStreamIndex`
    sur EN 2.0, CA10). On passe par `previewPlaybackTracks` et `PlaybackSubtitleResolver.resolve` pour vérifier :
    - « Jusqu'à 5.1 » → ligne EN 5.1 ;
    - « Stéréo » → ligne EN 2.0 ;
    - « D'origine » → ligne d'aujourd'hui ;
    - dans les trois cas, les sous-titres sont calculés pour l'anglais.
  - CA7 : deux appels successifs à `selectAudioTrack` sur deux épisodes, sans préférence reportée, donnent la même
    classe de canaux.
- Critères d'acceptation couverts : CA1, CA2 (choix), CA3, CA3bis, CA4, CA5, CA6, CA7, CA8, CA10, CA11.

### T3 — Intention de lancement avec canaux, et verrou de CA9
- Complexité : M
- Dépend de : T2 (même fichier `preferred_languages.dart`)
- Fichiers :
  - modifier `lib/fork/preferred_languages.dart` et `test/fork/preferred_languages_launch_test.dart` ;
  - créer `test/fork/audio_direct_play_test.dart`.
- À faire :
  - Dans `forkLaunchAudioIntent`, ajouter `channels: 2` quand `forkAudioOutput()` vaut `stereo`, `6` quand elle vaut
    `multichannel`, et rien sinon. Rien d'autre ne change : pas de nouvel `await`, pas de nouveau crochet.
  - CA9 : chercher dans `test/services/` un test upstream qui exerce la décision « lecture directe ou transcodage » de
    `PlexClient`, avec un faux HTTP ou `buildTranscodeParamsForTesting`, et un test équivalent pour le profil de
    lecture directe Jellyfin (`jellyfin_client/parts/playback.dart` l.983).
    - S'il en existe, le reprendre dans `audio_direct_play_test.dart` avec deux pistes audio anglaises (2.0 AAC et
      5.1 DTS) et l'intention `channels: 6`, puis vérifier que `isTranscoding` reste faux et que le profil n'interdit
      aucun codec audio.
    - **Ne pas ajouter de point d'entrée de test dans un fichier upstream.** S'il n'en existe pas, écrire seulement le
      test Jellyfin possible, et le signaler au pilote. CA9 est alors vérifié en recette.
- Tests (`preferred_languages_launch_test.dart`) :
  - l'intention porte `channels: 2`, `6` ou `null` selon le réglage ;
  - `findSourceAudioTrackForIntent(intention, lignes)` renvoie la ligne EN 5.1 pour `6`, la ligne EN 2.0 pour `2`, et
    `null` pour l'intention sans canaux sur S3E8 (ambiguïté de `langues-preferees`, inchangée avec D'origine).
- Critères d'acceptation couverts : CA2 et CA3 en transcodage, CA9.

### T4 — Textes de « Canaux audio » (CA12)
- Complexité : S
- Dépend de : —
- Fichiers :
  - modifier `lib/fork/i18n/fr.json` et `lib/fork/i18n/en.json` ;
  - régénérer `lib/i18n/*.i18n.json` et `lib/i18n/strings*.g.dart`.
- À faire :
  - Ajouter `"settings": { … }` aux deux surcouches, avec les trois clés suivantes. Garder l'apostrophe typographique
    (’) comme dans l'upstream.
    - `audioChannelLimitOriginalDescription` :
      - fr : « Lire tous les canaux de la piste. Au lancement, la piste audio n’est pas choisie selon son nombre de
        canaux. »
      - en : « Play every channel in the track. At launch, the audio track is not picked by channel count. »
    - `audioChannelLimitSurround51Description` :
      - fr : « Au lancement, choisit la piste de votre langue qui a le plus de canaux (5.1). Convertit le 7.1 en 5.1
        pour les téléviseurs et amplis qui n’acceptent que le PCM 5.1. La transmission directe n’est pas affectée. »
      - en : « At launch, picks the track in your language with the most channels (5.1). Mixes 7.1 down to 5.1 for TVs
        and receivers that only take 5.1 PCM. Passthrough is unaffected. »
    - `audioChannelLimitStereoDescription` :
      - fr : « Au lancement, choisit la piste stéréo de votre langue. Convertit en deux canaux pour les haut-parleurs du
        téléviseur, des enceintes stéréo ou un casque. Désactive la transmission directe. »
      - en : « At launch, picks the stereo track in your language. Mixes down to two channels for TV speakers, stereo
        speakers or headphones. Turns passthrough off. »
  - Puis `python3 scripts/fork/rebrand_i18n.py`, puis `scripts/codegen.sh` (D6). Ne jamais éditer `lib/i18n/` à la
    main.
- Tests :
  - `python3 scripts/fork/rebrand_i18n.py --check` ;
  - `scripts/codegen.sh --check` ;
  - `python3 scripts/checks/clean_translations.py --check --strict` ;
  - `test/fork/i18n_branding_test.dart`.
- Critères d'acceptation couverts : CA12.

### T5 — Recette sur la Fire Stick
- Complexité : M
- Dépend de : T1 à T4
- Fichiers : aucun. Le compte rendu va dans `docs/technique/meilleure-piste-audio/recette.md`.
- À faire : voir « Vérification globale ».
- Critères d'acceptation couverts : CA1 à CA12 (CA2 au sens strict, sur une installation 5.1 réelle, seulement par
  les tests et par « Jusqu'à 5.1 »).

## Vérification globale

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
dart format <fichiers modifiés>
python3 scripts/fork/rebrand_i18n.py --check && scripts/codegen.sh --check
python3 scripts/checks/clean_translations.py --check --strict
dart run scripts/checks/check_analyzer.dart
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh test/fork/
scripts/run_tests.sh                       # suite complète, aucun nouvel échec ni nouveau skip
git diff feat/langues-preferees --stat -- lib ':!lib/fork' ':!lib/i18n'   # vide : aucun fichier upstream touché
```

Recette sur la TV (APK `armeabi-v7a`, journaux de débogage activés,
`adb logcat -v time -s flutter | grep -E "Audio:|Fork preferred"`) :
1. **« Canaux audio » = D'origine** : S3E8 et Green Lantern démarrent en English 2.0. Le journal dit « current order »
   ou montre le choix du serveur (CA1, CA3bis).
2. **« Stéréo »** : English 2.0 (CA3).
3. **« Jusqu'à 5.1 »** :
   - S3E8 → « ENG VO - EAC3 DDP 5.1 » cochée ;
   - Green Lantern → English DTS 5.1 cochée, **transmission audio directe activée, et le son sort** sur le téléviseur
     (risque DTS/E-AC3) ;
   - refaire avec la transmission directe désactivée.
4. **CA6** : avec « Mémoriser » activé, choisir 2.0 à la main, quitter, relancer → 2.0.
5. **CA7** : en « Jusqu'à 5.1 », l'épisode suivant enchaîné démarre en 5.1.
6. **CA9** : en « Jusqu'à 5.1 », aucune session de transcodage (`GET /status/sessions` sur PMS) et pas de transcodage
   dans le journal d'ouverture.
7. **CA12** : textes des trois choix de « Canaux audio », en français puis en anglais.
8. **CA11** : seulement si un fichier de test avec une piste de commentaire est disponible, sinon par les tests.

## Risques restants

- **Pas de 5.1 automatique** : il faut régler une fois « Jusqu'à 5.1 » avec une barre de son ou un home cinéma
  (conséquence acceptée par le PO).
- **Silence en transmission directe** (DTS ou E-AC3) si un maillon annonce à tort un format, par exemple une barre de
  son en ARC sans DTS. C'est un défaut upstream (#1458, #1703), plus exposé avec « Jusqu'à 5.1 ». Le recours est de
  désactiver « Transmission audio directe », comme le dit déjà son texte.
- **« D'origine » avec une piste de commentaire en tête** et rien de marqué par défaut : on garde le choix d'aujourd'hui
  (CA3bis). La règle CA11 ne joue que pour les réglages Stéréo et Jusqu'à 5.1.
- **Nombre de canaux absent** sur certains flux (mpv `demux-channel-count`) : la règle se tait, et on garde le choix
  d'aujourd'hui.
- **Transcodage avec une intention `channels: 6`** sur un fichier qui n'a que 7.1 et 2.0 : égalité, le serveur garde
  sa piste.
- **Fusions** : aucune ligne upstream ajoutée. La surcharge i18n de trois clés `settings.*` est à relire si l'upstream
  change leur sens.
