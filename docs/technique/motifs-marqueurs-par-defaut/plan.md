# Plan technique — motifs-marqueurs-par-defaut

Spec : docs/produit/specs/motifs-marqueurs-par-defaut.md
Statut : approuvé       Pilote : architecte-app (voie courte, seul architecte)

## Constat dans le code (ce qui oriente tout le plan)

- Les marqueurs de saut sont construits par `PlaybackExtras.withChapterFallback` (`lib/media/media_source_info.dart`),
  appelé par **deux** fonctions seulement : `plexPlaybackExtrasFromCacheJson` (`lib/services/plex_mappers.dart`) et
  `jellyfinPlaybackExtrasFromRaw` (`lib/services/jellyfin_media_info_mapper.dart`). Tous les chemins y passent :
  lecture en ligne (`PlexClient.getPlaybackExtras`, `JellyfinClient.fetchPlaybackExtras`), hors ligne
  (`CachedPlaybackMetadataService`) et téléchargements (`DownloadManagerService` via `fetchPlaybackExtras`).
- **Les motifs par défaut ne servent pas à classer les chapitres.** Tant que l'utilisateur n'a pas remplacé un motif,
  les titres de chapitres sont classés par le modèle ML `ChapterMarkerClassifier` (`lib/media/chapter_marker_classifier.dart`,
  seuil 0,8). `defaultIntroPattern` / `defaultCreditsPattern` ne servent qu'à reclasser des types de marqueurs serveur
  non standard, ou deviennent le motif actif quand l'utilisateur en saisit un autre (`_customPattern` : un motif égal
  au défaut, vide ou absent = « pas personnalisé »). Modifier ces constantes ne ferait donc **pas** reconnaître
  « Générique » ou « Recap ».
- Le bouton (`SkipMarkerButton`, `lib/widgets/video_controls/widgets/skip_marker_button.dart`) affiche
  « Passer l'intro » pour tout marqueur qui n'est pas `credits`, et suit `skipIntroMode`
  (`_skipModeFor`, `video_controls.dart:884`). `_syncCurrentMarkerForPosition` (`parts/markers.dart`) parcourt tous
  les marqueurs : plusieurs marqueurs `intro` dans un épisode fonctionnent déjà (bouton, focus TV automatique,
  compte à rebours, disparition, Retour).
- Jellyfin : `_jellyfinSegmentMarkerType` (`jellyfin_media_info_mapper.dart:163`) ne garde que `Intro`, `Outro`,
  `Credits` ; le segment `Recap` est jeté. Un test upstream le vérifie explicitement
  (`test/services/jellyfin_media_info_test.dart`, « parses native Jellyfin media segments into skip markers »).
- Dans la fusion upstream, un marqueur serveur `intro` empêche tout marqueur `intro` tiré des chapitres
  (`synthetic.where((m) => !nativeTypes.contains(m.type))`).

## Décisions

1. **Aucune migration de réglage, aucune dépendance, aucun stockage nouveau.** Les constantes `defaultIntroPattern`,
   `defaultCreditsPattern` et les `StringPref` `intro_pattern` / `credits_pattern` restent intactes. Raison : changer
   la constante ne détecterait rien (cf. constat) et ferait passer pour « personnalisé » tout utilisateur qui a
   enregistré ou importé l'ancien défaut, ce qui désactiverait chez lui le modèle ML. CA12 est tenu par construction.
2. **Un post-traitement pur du fork**, `ForkSkipMarkers.apply(extras, introPattern:, creditsPattern:)` dans le nouveau
   fichier `lib/fork/skip_markers.dart`, appliqué au résultat de `withChapterFallback` dans les deux fonctions de
   mappage. Raison : un seul point de passage pour Plex et Jellyfin, `media_source_info.dart` n'est pas touché (D2, D11).
3. **Le récap devient un marqueur de type `intro`** à la sortie du post-traitement. Raison : bouton, libellé, réglage
   `skipIntroMode`, focus et Retour existants réutilisés sans une ligne d'UI (CA4, CA14) ; aucun enum ni libellé
   nouveau (D11).
4. **Type interne `'recap'`** (`ForkSkipMarkers.recapType`) pour le segment Jellyfin entre le mappage des segments et
   le post-traitement. Raison : s'il était mappé directement en `intro`, la fusion upstream supprimerait l'intro tirée
   des chapitres (`nativeTypes` contiendrait `intro`), ce qui casserait l'enchaînement CA4b. Le type `'recap'` ne sort
   jamais de `jellyfinPlaybackExtrasFromRaw`.
5. **Mots français d'intro/générique en complément, pas en remplacement** : ils ne créent un marqueur que si le type
   (`intro` ou `credits`) manque après l'upstream, et seulement si l'utilisateur n'a pas personnalisé le motif de ce
   type. Raison : CA9, CA10 et CA11 restent tenus par le code upstream inchangé ; un motif personnalisé garde la main,
   comme dans l'upstream (CA12).
6. **Détection du récap toujours active**, sans réglage (CA4 : pas de nouveau réglage), même avec un motif
   personnalisé (les motifs ne concernent que l'intro et le générique).
7. **Comparaison de titres normalisée** : minuscules, accents retirés, apostrophe typographique `’` → `'`, espaces
   regroupés, ponctuation finale (`. … : ! - – —`) retirée, puis expressions **ancrées sur tout le titre**.
   Raison : couvrir « Previously on The Handmaid's Tale… », « RÉCAP », sans faux positifs du type « Closing Day »
   (#2734) ou « La fin du monde ».
8. **Garde-fous** (constantes nommées, réutilisant celles de l'upstream quand elles existent) :
   - récap tiré d'un chapitre : durée ≥ `ChapterMarkerClassifier.minMarkerDuration` (5 s) et ≤ 5 min (CA5), début
     ≤ 25 % de la durée (CA6) ;
   - intro par mot français : durée entre 5 s et `ChapterMarkerClassifier.maxIntroDuration` (3 min), début ≤ 25 %
     (CA7, CA10) ;
   - générique par mot français : durée ≥ 5 s, début ≥ `PlaybackExtras.minChapterCreditsStartFraction` (75 %) (CA8,
     CA10) ;
   - la durée de référence est l'offset de chapitre le plus lointain, comme dans `withChapterFallback` ;
   - les marqueurs fournis par le serveur (dont le `Recap` Jellyfin) ne subissent **aucun** garde-fou, comme dans
     l'upstream.
9. **Enchaînement (CA4b)** : un récap absorbe les marqueurs `intro` (et récaps) qui le suivent ou le chevauchent tant
   que l'écart entre la fin courante et le début du suivant est **< 5 s** (`ForkSkipMarkers.chainGap`) ; le résultat
   est un seul marqueur `intro` [début du récap, fin la plus lointaine]. Au-delà de 5 s, deux marqueurs `intro`
   distincts : l'UI existante réaffiche le bouton au début de l'intro. Un marqueur `intro` seul n'absorbe jamais rien
   (CA11 : une intro serveur sans récap reste identique).
10. **Proposable à l'upstream (#3051)** : `lib/fork/skip_markers.dart` n'importe que `lib/media/` et reste en fonctions
    pures ; une PR upstream déplacerait la logique dans `withChapterFallback` et ajouterait `case 'recap'`. Pas fait
    ici.

## Tâches

### T1 — Logique pure : détection du récap, mots français, enchaînement
- Complexité : M
- Dépend de : —
- Fichiers :
  - créer `lib/fork/skip_markers.dart`
  - créer `test/fork/skip_markers_test.dart`
- À faire :
  - En tête de fichier : `// FORK: motifs-marqueurs-par-defaut — récap et mots français pour les marqueurs de saut`.
    Imports : `package:flutter/foundation.dart` (pour `@visibleForTesting`), `../media/chapter_marker_classifier.dart`,
    `../media/media_source_info.dart`.
  - `abstract final class ForkSkipMarkers` avec :
    - `static const recapType = 'recap';`
    - `static const chainGap = Duration(seconds: 5);`
    - `static const maxRecapDuration = Duration(minutes: 5);`
    - `static const maxRecapStartFraction = 0.25;` et `static const maxIntroStartFraction = 0.25;`
    - `@visibleForTesting static String normalizeTitle(String title)` (règles de la décision 7 ; table de repli
      d'accents limitée aux lettres latines courantes : àâä, éèêë, îï, ôö, ùûü, ç, œ→oe).
    - Expressions (sur le titre normalisé, `RegExp` `static final`) :
      - récap : `^(?:recap(?:itulatif)?(?:\b.*)?|previously(?: on\b.*)?|precedemment(?: dans\b.*)?|last time(?: on\b.*)?|resume)$`
        (les accents sont déjà retirés par `normalizeTitle`) ;
      - intro seule : `^(?:generique de debut|generique d'ouverture|ouverture)$` ;
      - générique seul : `^(?:generique de fin|fin)$` ;
      - ambigu : `^generiques?$` → générique s'il est dans le dernier quart, sinon intro s'il passe les garde-fous
        d'intro.
    - `@visibleForTesting static bool isRecapTitle(String? title)`.
    - `static PlaybackExtras apply(PlaybackExtras extras, {String? introPattern, String? creditsPattern})` :
      1. Chemin rapide : si `extras.chapters` est vide et qu'aucun marqueur n'a le type `recapType`, renvoyer
         `extras` tel quel (CA13).
      2. Calculer les spans des chapitres exactement comme `withChapterFallback` (fin absente = début du suivant ;
         ignorer début/fin nuls ou fin < début) et la durée de référence (offset le plus lointain).
      3. Récaps = marqueurs `recapType` + chapitres dont `isRecapTitle` est vrai et qui passent les garde-fous récap.
      4. Personnalisation : `custom(p, def) => p != null && p.trim().isNotEmpty && p != def` avec
         `PlaybackExtras.defaultIntroPattern` / `defaultCreditsPattern` (même règle que `_customPattern`).
      5. Si aucun marqueur `intro` et motif d'intro non personnalisé : ajouter le **premier** chapitre (hors récaps)
         correspondant à « intro seule » ou « ambigu » et passant les garde-fous d'intro.
         Si aucun marqueur `credits` et motif de générique non personnalisé : ajouter le **premier** chapitre (hors
         récaps et hors intro retenue) correspondant à « générique seul » ou « ambigu » et passant les garde-fous de
         générique. Marqueurs synthétiques : `id` = `chapter.id`, offsets = span.
      6. Enchaînement (décision 9) : trier par début ; pour chaque récap, absorber les `intro`/récaps suivants tant que
         `suivant.startTimeOffset - finCourante < chainGap` (un chevauchement donne un écart négatif, donc absorbé).
         Sortie : `MediaMarker(id: recap.id, type: 'intro', start: début du récap, end: fin max)`.
         Un récap qui n'absorbe rien devient aussi `type: 'intro'`.
      7. Renvoyer `PlaybackExtras(chapters: extras.chapters, markers: …triés par début)`. Aucun marqueur de type
         `recapType` ne doit rester dans la sortie.
  - Pas de `print`, pas de texte visible (aucune traduction).
- Tests (`test/fork/skip_markers_test.dart`, sans classifieur : construire des `PlaybackExtras` à la main) :
  - `normalizeTitle` et `isRecapTitle` : toute la liste CA2 (« Previously », « Previously on The Handmaid's Tale… »,
    « Recap », « RÉCAP », « Récapitulatif », « Résumé », « Précédemment », « Précédemment dans… », « Last time on… ») →
    vrai ; « Recapture », « Résumé du film » (hors liste), « Scene 1 », « Closing Day » → faux.
  - CA15 / CA1 : chapitres « Recap » 0–79 000, « Scene 1 » 79 000–2 682 000, « Credits » 2 682 000–2 900 000 et
    un marqueur `credits` déjà présent → un marqueur `intro` 0–79 000, le `credits` inchangé.
  - CA5 : « Recap » de 5 min 01 → aucun marqueur ajouté. CA6 : « Résumé » qui commence à 30 % → aucun.
  - CA3 : marqueur `recapType` 0–4 000 sans chapitres → un marqueur `intro` 0–4 000 (pas de garde-fou serveur).
  - CA4b : récap 0–79 000 + intro 82 000–170 000 → un seul `intro` 0–170 000 ; intro à 85 000 (écart 6 s) → deux
    `intro` ; récap qui chevauche une intro serveur → fusion ; intro serveur seule → identique (CA11).
  - CA7 : « Générique », « Générique de début », « Ouverture » au début, < 3 min, sans intro existante → `intro` ;
    « Ouverture » de 4 min → rien ; intro déjà présente → pas de doublon.
  - CA8 : « Générique », « Générique de fin », « Fin » dans le dernier quart sans `credits` → `credits` ;
    « Fin » à 50 % → rien (CA10).
  - Motif personnalisé (`introPattern: 'prologue'`) : « Générique » de début non ajouté, récap toujours détecté (CA12,
    décision 6). Motif égal à `PlaybackExtras.defaultIntroPattern` → traité comme non personnalisé.
  - CA13 : extras vides → même instance renvoyée (`identical`).
  - Référencer les constantes par leur nom (`ForkSkipMarkers.chainGap`, `ChapterMarkerClassifier.maxIntroDuration`…).
- Critères d'acceptation couverts : CA1, CA2, CA3 (partie logique), CA4b, CA5, CA6, CA7, CA8, CA10, CA11, CA12, CA13,
  CA15 (partie logique).

### T2 — Branchement Plex et Jellyfin, segment Recap, test upstream marqué
- Complexité : M
- Dépend de : T1
- Fichiers :
  - modifier `lib/services/plex_mappers.dart` (`plexPlaybackExtrasFromCacheJson`)
  - modifier `lib/services/jellyfin_media_info_mapper.dart` (`jellyfinPlaybackExtrasFromRaw`,
    `_jellyfinSegmentMarkerType`)
  - modifier `test/services/jellyfin_media_info_test.dart` (un seul test marqué)
  - modifier `test/fork/fork_test_utils.dart` (`forkChangedSkipAllowlist`)
  - créer `test/fork/skip_markers_hooks_test.dart`
- À faire :
  - `plexPlaybackExtrasFromCacheJson` : envelopper le `PlaybackExtras.withChapterFallback(...)` existant :
    `return ForkSkipMarkers.apply( // FORK: motifs-marqueurs-par-defaut — récap et mots FR` puis l'appel upstream
    inchangé, puis `introPattern: introPattern, creditsPattern: creditsPattern);`. Import
    `'../fork/skip_markers.dart'` marqué `// FORK:`.
  - `jellyfinPlaybackExtrasFromRaw` : même enveloppe, même marqueur, même import.
  - `_jellyfinSegmentMarkerType` : ajouter `case 'recap': return ForkSkipMarkers.recapType; // FORK: motifs-marqueurs-par-defaut — segment Recap (#3051)`.
    Ne pas mapper `preview` ni `commercial` (hors périmètre).
  - Ne pas toucher `media_source_info.dart`, `plex_client.dart`, `playback.dart`, ni l'UI.
  - Test upstream « parses native Jellyfin media segments into skip markers » (groupe `jellyfinPlaybackExtrasFromRaw`) :
    il attend que `Recap` soit jeté. Lui ajouter `skip: forkChangedSkip` (import `../fork/fork_test_utils.dart`),
    sans rien réécrire, et l'inscrire dans `forkChangedSkipAllowlist` :
    `'test/services/jellyfin_media_info_test.dart :: jellyfinPlaybackExtrasFromRaw parses native Jellyfin media segments into skip markers': 'CA3 (motifs-marqueurs-par-defaut)'`.
  - `test/fork/skip_markers_hooks_test.dart` :
    - garde (modèle `test/fork/update/fork_update_hooks_guard_test.dart`) : les deux fichiers contiennent
      `ForkSkipMarkers.apply(` et `jellyfin_media_info_mapper.dart` contient `ForkSkipMarkers.recapType` ;
    - reprise des assertions du test upstream marqué, avec le comportement du fork : types
      `['intro', 'credits', ForkSkipMarkers.recapType]` et offsets ;
    - bout en bout Plex avec `ChapterMarkerClassifier.bundled` (comme `jellyfin_media_info_test.dart`, qui charge le
      vrai modèle) : JSON `Chapter` de S3E8 (`tag` « Recap » 0 / « Scene 1 » 79 000 / « Credits » 2 682 000, fin
      2 900 000) → un marqueur `intro` 0–79 000, aucun marqueur de type `recapType` (CA15) ;
    - bout en bout Jellyfin : segment `Recap` 0–60 s + segment `Intro` 62–150 s → un seul `intro` 0–150 s (CA3,
      CA4b) ; segment `Recap` 0–60 s + chapitre « Opening » trouvé par le modèle à 62 s → un seul `intro` (vérifie la
      décision 4).
- Tests : `scripts/run_tests.sh test/fork/` puis `test/services/jellyfin_media_info_test.dart`,
  `test/media/media_source_info_test.dart`, `test/services/playback_initialization_offline_cache_test.dart`, puis
  toute la suite (code partagé).
- Critères d'acceptation couverts : CA3, CA4b, CA9, CA11, CA13, CA15 (partie code).

## Vérification globale

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
dart format lib/fork/skip_markers.dart lib/services/plex_mappers.dart lib/services/jellyfin_media_info_mapper.dart \
  test/fork/skip_markers_test.dart test/fork/skip_markers_hooks_test.dart test/fork/fork_test_utils.dart \
  test/services/jellyfin_media_info_test.dart
dart run scripts/checks/check_analyzer.dart
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh            # toute la suite : 1 test upstream de plus en skip (forkChangedSkip), justifié CA3
```

Aucun `codegen`, aucune traduction à vérifier (pas de texte nouveau).

Recette TV (APK de test, cf. `conventions-code`), Fire TV :
1. The Handmaid's Tale S3E8 depuis la fiche : « Passer l'intro » apparaît dès le début avec le focus ; OK → reprise à
   1:19 (±2 s). Idem S3E9 et S3E10 (CA15, CA1, CA14).
2. Même épisode via « Continuer à regarder » repris à 0:30 : le bouton est présent jusqu'à 1:19.
3. Paramètres > Lecture > Passer l'intro sur « Désactivé » : pas de bouton ; sur « Automatique » : compte à rebours
   puis saut à 1:19 (CA4).
4. Retour pendant que le bouton a le focus : même comportement que sur une intro ordinaire (CA14).
5. Fin de S3E8 : « Passer le générique » / « Épisode suivant » à 44:42 comme avant (non-régression).
6. Un épisode avec un vrai marqueur d'intro Plex : bouton au même moment qu'avant (CA11).
7. Paramètres > Lecture : les deux motifs affichent la même valeur qu'avant la mise à jour (CA12).
8. Si un serveur Jellyfin avec segments Recap est disponible : CA3 ; sinon, couvert par les tests de T2.

## Risques restants

- **Faux positifs** des mots ajoutés : limités par l'ancrage sur tout le titre et les garde-fous ; « Fin » dans le
  dernier quart d'un film peut désigner la dernière scène et non le générique (choix de la spec, CA8).
- **Modèle ML** : si le classifieur choisit lui-même un chapitre « Recap » comme intro (probabilité ≥ 0,8), le résultat
  est le même grâce à la fusion par chevauchement ; pas de doublon.
- **Fusion upstream** : 2 fichiers upstream touchés, 3 lignes marquées `FORK:` plus 2 imports. Si l'upstream ajoute
  lui-même le `Recap` Jellyfin (#3051), retirer notre `case` et garder la sortie de l'upstream ; la garde
  `skip_markers_hooks_test.dart` signale un crochet perdu.
- **Réglage invisible** : les mots ajoutés ne figurent pas dans la formule affichée de « Motif du marqueur… » (voir
  question produit).
- Le bouton disparaît au bout de 7 s en mode « Bouton » (comportement upstream de `_startSkipButtonDismissTimer`),
  donc avant la fin d'un récap de 1:19 : c'est le comportement actuel de « Passer l'intro », conforme à la spec
  (« comme le bouton actuel »), à signaler en recette pour éviter une fausse anomalie.
