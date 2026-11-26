# Proposition app — meilleure-piste-audio

Auteur : architecte-app (pilote) · 2026-11-26 · Phase 1 (rédigée sans lire la proposition plateforme)
Spec : `docs/produit/specs/meilleure-piste-audio.md`. Elle prolonge `langues-preferees` (commit `cc990ad3b`).

## Compréhension de la spec

Parmi les pistes de la langue préférée, on démarre :
- sur la stéréo quand la sortie n'est qu'en stéréo (télévision seule, ou « Canaux audio » = Stéréo) ;
- sur la piste qui a le plus de canaux quand l'installation sait les restituer ;
- sur la piste d'aujourd'hui quand l'app ne peut pas savoir (CA3bis).

Aucun nouvel écran.

Critères de mon périmètre : CA1 à CA8 et CA10. La règle de choix est en Dart. La détection de ce que restitue
l'installation relève de la plateforme (AudioManager, passthrough), et je n'en consomme que le résultat. CA9 est
garanti par construction (voir « Impact »).

## Existant

- **Règle du fork** : `lib/fork/preferred_languages.dart`, `forkPreferredAudio`. Elle est appelée par le crochet
  `// FORK:` de `TrackSelectionService.selectAudioTrack`, avant la priorité `serverSelected`.
  - Elle renvoie `null` si le serveur a déjà choisi la langue préférée (**A2**), si l'utilisateur a choisi à la main
    (**A3**), ou si aucune piste n'est dans la langue (**A4**).
  - Sinon, parmi les pistes de la langue, elle prend celle marquée `isDefault`, à défaut **la première**. C'est la
    cause du symptôme : sur S3E8, « English 2.0 » est la première.
  - Sur Plex, PMS marque en général `selected` la première piste de la langue du compte. A2 rend alors la main à
    l'upstream, qui garde cette piste, toujours la stéréo ici.
- **Canaux disponibles des deux côtés** :
  - pistes natives : `AudioTrack.channels` (`lib/mpv/models.dart` l.110, rempli par mpv et ExoPlayer) ;
  - descripteurs `source:` du resolver et de l'aperçu de la fiche : `PlaybackSubtitleResolver.audioTrackForSource`
    recopie `MediaAudioTrack.channels`.

  Une même règle donne donc le même choix avant l'ouverture, pendant la lecture et dans l'aperçu
  (`previewPlaybackTracks`).
- **Réglage « Canaux audio »** : `SettingsService.audioChannelLimit` (`settings_service.dart` l.905),
  `AudioChannelLimit { original, surround51, stereo }` (`lib/models/audio_channel_limit.dart`), appliqué au lecteur par
  `video_player_screen.dart` l.2179-2186.

  Le commentaire upstream du modèle prévient : « Nothing downstream of the TV is visible to the platform APIs, so the
  viewer picks the limit. » Autrement dit, l'upstream considère qu'on ne voit pas, côté plateforme, ce qu'il y a
  derrière la TV. Ce point est à confronter à l'analyse de la plateforme.
- **Indice existant sur la route audio** : `player_native.dart` l.1112-1120, `getAudioSpdifCodecs`. Le plugin Android
  déduit les codecs passthrough de la route audio courante. C'est un indice, pas une preuve de 5.1 (voir les risques).
- **Report d'un épisode à l'autre** : seul un choix manuel est reporté (`_sessionAudioPreference`), par
  `findNativeAudioTrackForIntent`, qui départage déjà par nombre de canaux (`extraScore`). Un choix automatique n'est
  pas reporté : l'épisode suivant repasse par la règle.
- **Intention de lancement** (transcodage) : `forkLaunchAudioIntent` envoie `AudioTrack(id: carried, language: …)`.
  Avec deux pistes anglaises, `_findTrackByEvidenceBands` est à égalité et refuse. C'est le risque restant de
  `langues-preferees`.

## Approche proposée

### 1. Une notion de sortie audio à trois états — `lib/fork/audio_output.dart` (nouveau)

```dart
enum ForkAudioOutput { stereo, multichannel, unknown }
ForkAudioOutput forkAudioOutput(); // synchrone, utilisable dans l'échelle de sélection
```

Le résultat se calcule ainsi, dans l'ordre :
1. « Canaux audio » = `stereo` → `stereo` (CA3) ;
2. « Canaux audio » = `surround51` → `multichannel`. L'utilisateur affirme alors que sa chaîne restitue la 5.1 ;
3. « Canaux audio » = `original` → la dernière valeur connue de la sonde plateforme (`ForkAudioRouteProbe.current`),
   par défaut `unknown` ;
4. `SettingsService.instanceOrNull` vaut `null` (tests) → `unknown`.

La sonde est fournie par la plateforme. Côté Dart, une façade `ForkAudioRouteProbe` expose
`static ForkAudioOutput current` et `static Future<void> refresh()`. `refresh()` est attendue dans
`forkLaunchAudioIntent`, qui est déjà attendue avant chaque ouverture en ligne et chaque rechargement. Elle a un délai
maximum, et aucun crochet upstream de plus n'est nécessaire. Le chemin hors ligne, qui n'est pas accroché, lit la
dernière valeur connue. La sonde ne doit répondre `stereo` ou `multichannel` **que si elle est sûre**, sinon `unknown`.

### 2. Choix de la meilleure piste dans la langue — modification de `forkPreferredAudio` (fichier du fork)

Nouvelle fonction pure `forkBestTrackForOutput(List<AudioTrack> inLanguage, ForkAudioOutput output) → AudioTrack?`.
Elle ne considère que les pistes dont `channels` est connu et qui ne sont **pas** des pistes spéciales (voir Q1) :
- `unknown`, moins de 2 candidates, ou candidates qui ont toutes le même nombre de canaux → `null`. On garde le choix
  d'aujourd'hui (CA3bis, CA4, CA5) ;
- `stereo` → les candidates à 2 canaux au plus. S'il y en a, on prend `isDefault`, à défaut la première. S'il n'y en a
  aucune, `null` (une 5.1 seule sera réduite en stéréo, comme aujourd'hui) ;
- `multichannel` → les candidates qui ont le plus de canaux, avec la même règle de départage `isDefault` puis la
  première (CA5). Une 7.1 l'emporte donc sur une 5.1, conformément à la spec.

Intégration dans `forkPreferredAudio` :
- **A3** (choix manuel avec « Mémoriser ») est vérifié en premier et renvoie toujours `null` (CA6) ;
- **A2 est assoupli** : si le serveur a déjà choisi la langue préférée, on renvoie `null` **sauf** quand
  `forkBestTrackForOutput` désigne une autre piste. C'est le cas S3E8 sur une installation 5.1. Si la sortie est
  `unknown`, A2 reste inchangé, ce qui garantit CA3bis : aucune régression quand on ne sait pas ;
- sinon : `forkBestTrackForOutput(...) ?? (isDefault ?? première)`, c'est-à-dire le comportement actuel en repli.

Le résultat garde la priorité `profile`, donc rien n'est écrit sur le serveur. CA8 est garanti par A1 :
« Choisir l'audio par langue » désactivé → `null`.

### 3. Transcodage — intention enrichie (fichier du fork)

`forkLaunchAudioIntent` ajoute `channels: 2` si la sortie est `stereo`, `6` si elle est `multichannel`, et rien si
elle est `unknown`. `_findTrackByEvidenceBands` départage déjà à égalité de langue par parité de canaux
(`extraScore`). La piste voulue est donc demandée au transcodeur même s'il y a plusieurs pistes anglaises. C'est la
résorption partielle d'un risque de `langues-preferees`. Une 7.1 sans 5.1 reste à égalité avec la stéréo ; ce cas est
toléré, et le serveur garde alors son choix.

### 4. Enchaînement (CA7)

Il n'y a rien à faire : un choix automatique n'est pas reporté, et l'épisode suivant repasse par la même règle, avec
la même sortie. Un choix manuel reporté garde la priorité 1, sans changement.

### Tests (`test/fork/`)

- `audio_output_test.dart` : correspondance entre le réglage et la sortie ; service absent → `unknown` ; valeur de la
  sonde utilisée seulement si le réglage vaut `original`.
- `preferred_languages_test.dart`, à compléter :
  - stéréo, 5.1, inconnue, sur les pistes de S3E8 et de Green Lantern (DTS 5.1) ;
  - A2 avec le serveur sur English 2.0 ;
  - même nombre de canaux (CA5) ;
  - une seule piste (CA4) ;
  - canaux inconnus ;
  - piste de commentaire (Q1) ;
  - A3 prioritaire (CA6).
- `preferred_languages_flow_test.dart` : JSON Plex (`Part.Stream[]`) de S3E8 et de Green Lantern, et équivalent
  Jellyfin (CA10), avec `previewPlaybackTracks` et `PlaybackSubtitleResolver.resolve`. Les sous-titres restent calculés
  pour l'anglais.
- `preferred_languages_launch_test.dart` : l'intention porte `channels`, et `findSourceAudioTrackForIntent` choisit la
  bonne ligne parmi deux pistes anglaises.

### Découpage pressenti

- T1 (M) : `audio_output.dart` et la façade de la sonde côté Dart.
- T2 (L) : `forkBestTrackForOutput`, assouplissement d'A2, intention enrichie, tests. Sélection de pistes en lecture.
- T3 : sonde native, au périmètre de la plateforme.
- T4 : recette sur la Fire Stick, TV seule.

## Alternatives écartées

1. **Toujours préférer la 5.1** (« le plus de canaux »). C'est contraire à CA1 : l'utilisateur écoute sur la TV, et
   la réduction en stéréo affaiblit les voix.
2. **Préférer la 5.1 seulement si « Transmission audio directe » est activée.** Ce réglage dit « laisse passer le flux
   compressé », pas « mon installation a 6 haut-parleurs » : une TV seule accepte souvent l'AC3 en passthrough et le
   réduit elle-même. Ce n'est pas un indice fiable.
3. **Nouveau réglage « Piste préférée : stéréo / multicanal ».** Le hors périmètre l'exclut (« on réutilise Canaux
   audio »).
4. **Changer l'ordre upstream ou `findAudioTrackByProfile`.** Ce serait un diff upstream pour rien : la règle du fork
   est déjà au bon endroit.

## Impact

- **Fichiers upstream modifiés** : aucun côté Dart. Les crochets de `langues-preferees` suffisent. La plateforme dira
  ce que demande la sonde (canal natif nouveau ou existant).
- **Nouveaux fichiers** :
  - `lib/fork/audio_output.dart` ;
  - `test/fork/audio_output_test.dart`.
- **Fichiers du fork modifiés** :
  - `lib/fork/preferred_languages.dart` ;
  - les tests `test/fork/preferred_languages*_test.dart`.
- **Dépendances** : aucune.
- **CA9 (lecture directe conservée)** : en lecture directe, le choix de piste est local (`aid` de mpv, après
  l'ouverture). Choisir la 5.1 ne change donc pas la décision de lecture directe, qui ne porte que sur la vidéo et le
  conteneur (`_sourceCodecRefused`, préréglage de qualité). À confirmer par la plateforme : un codec audio refusé ne
  déclenche pas de transcodage.
- **Risques** :
  - *Détection peu fiable* : la Fire Stick ne voit que l'EDID de la TV. Beaucoup de TV annoncent l'AC3 ou l'EAC3 5.1
    même sans barre de son. Si la sonde se trompe en répondant `multichannel`, CA1 échoue. Elle doit donc être
    prudente, quitte à répondre `unknown` (CA3bis). Dans ce cas, CA1 n'est garanti que pour les fichiers dont la
    stéréo est la première piste (c'est le cas de S3E8 et de Green Lantern) ou avec « Canaux audio » = Stéréo. → Q2.
  - *Piste de commentaire ou d'audiodescription en stéréo* : sur une TV seule, la règle « stéréo » pourrait la
    préférer à la piste principale en 5.1. → Q1.
  - *Lecture directe d'une piste DTS sur la Fire Stick* (CA2, « pas de silence ») : il faut décoder ou faire passer le
    flux, ce qui relève de la plateforme (`getAudioSpdifCodecs`).
  - *Fusions* : aucune ligne upstream ajoutée.

## QUESTIONS PRODUIT

- **Q1 — Commentaires et audiodescription.** Exemple : « English 5.1 » + « English 2.0 Commentaire du réalisateur » sur
  la TV seule. Faut-il exclure de la règle des canaux les pistes dont le titre indique un commentaire ou une
  audiodescription (« Commentary », « Commentaire », « Audio Description », « AD », « Descriptive ») ? Recommandation :
  oui. On jouerait alors la 5.1 réduite en stéréo plutôt que le commentaire.
- **Q2 — Si la détection n'est pas fiable** (à confirmer par la plateforme). Avec « Canaux audio » = D'origine, faut-il
  garder le choix d'aujourd'hui, comme le dit CA3bis (en général la première piste) ? Ou traiter D'origine comme « 5.1 »,
  comme le dit la note de la spec, ce qui obligerait l'utilisateur à passer en « Stéréo » ? Recommandation : CA3bis,
  et conseiller « Stéréo » à l'utilisateur. Dans les deux cas, ce réglage règle aussi le volume des voix.
