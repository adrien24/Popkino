# Plan technique — langues-preferees

Spec : docs/produit/specs/langues-preferees.md
Statut : approuvé       Pilote : architecte-app

Sources : `proposition-app.md`, `proposition-plateforme.md`, `debat.md` (tour 1 des deux côtés, aucun ❌ restant).
Décisions produit intégrées :
- CA12 : la piste française « forcée » est affichée quand l'audio est en français.
- CA4ter : avec « Mémoriser », un choix reporté automatiquement compte comme un choix manuel sur l'épisode suivant.
- La langue réglée sur une série dans Plex est hors périmètre.

## Décisions

1. **Une règle « langue préférée d'abord », en fonctions pures dans `lib/fork/preferred_languages.dart`, appelée par
   deux crochets dans `TrackSelectionService`, placés entre la priorité 1 (`navigation`) et la priorité 2
   (`serverSelected`). Quand la règle renvoie `null`, l'échelle upstream s'applique telle quelle.**
   Raison : c'est la seule échelle de décision. Elle est utilisée par le resolver avant l'ouverture, par le
   `TrackManager`, par l'aperçu de la fiche et par la vérification « pistes prêtes ». Deux appels de deux lignes,
   c'est le diff le plus petit et le plus facile à fusionner (D11).
2. **La règle ne fait rien quand le serveur a déjà choisi la langue préférée (A2).**
   Raison : on peut ainsi appliquer la préférence une seconde fois sans danger (cf. l'avertissement de
   `AccountPreferencesDetailScreen` l.47-50), l'upstream garde son choix entre deux pistes anglaises, et la quasi-totalité
   des tests upstream reste intacte.
3. **La règle s'applique quel que soit « Mémoriser ».** Elle ne laisse la main au serveur que pour les contenus marqués
   « choisi par l'utilisateur » dans `ForkTrackChoiceMemory`, et seulement quand « Mémoriser » est activé.
   Raison : CA4bis et CA4ter, alors que `rememberTrackSelections` est activé par défaut (`settings_service.dart` l.702).
4. **La mémoire locale ne retient qu'un indicateur par contenu et par type de piste**, jamais la piste elle-même. Elle
   est stockée dans un `JsonPref` (500 entrées au plus), pas dans drift.
   Raison : le serveur garde déjà la piste (Plex par fichier, Jellyfin par les rapports). On évite une migration et de
   nouveaux rapprochements de pistes (#1716/#1785).
5. **L'indicateur est posé là où l'upstream écrit sur le serveur, c'est-à-dire au début de
   `TrackManager._guardTrackChange`.**
   Raison : ce point couvre les choix explicites (menu, raccourcis) **et** les choix reportés de priorité `navigation`
   (CA4ter). Les choix automatiques de priorité `profile` ou `serverSelected` n'y passent jamais. Dans le chemin de
   changement de source (`playback_reload.dart`), l'indicateur n'est posé **qu'après** un `selectStreams` réussi
   (demande de la plateforme).
6. **Transcodage, audio** : une intention de langue (`AudioTrack(id: carriedAudioTrackId, language: …)`) alimente
   **uniquement** `PlaybackInitializationOptions.preferredAudioTrack`. Elle n'est transmise ni au resolver ni au
   `TrackManager`.
   Raison : Plex (`plex_client.dart` l.3800) et Jellyfin (`playback.dart` l.295) savent déjà la résoudre pour le
   transcodeur, et on évite une priorité `navigation` artificielle, qui écrirait sur le serveur.
7. **Transcodage, sous-titres** : dans `_resolveSubtitleSelectionForOpen`, quand `result.isTranscoding` est vrai et
   qu'aucune préférence audio n'est passée, on fournit au resolver le descripteur de la piste audio **réellement
   envoyée** (`result.activeAudioStreamId`, sinon `selected`).
   Raison : les sous-titres doivent être calculés pour l'audio que le serveur envoie vraiment, même quand l'intention a
   été refusée (plusieurs pistes anglaises). Sinon on aurait des sous-titres français sur un audio français, contraire
   à CA6 (demande de la plateforme).
8. **Avant d'utiliser le profil au lancement, on attend `AccountPreferencesController.ensureActiveLoaded()`, au plus
   2 s, et seulement si `activePreferences` vaut `null`.**
   Raison : démarrage à froid depuis la rangée « À suivre » ou depuis un lien profond (demande de la plateforme).
9. **Aucune nouvelle valeur dans `TrackSelectionPriority`.** Les décisions du fork portent la priorité `profile`.
   Raison : on ne casse pas les `switch` upstream, et un choix `profile` n'est jamais écrit sur le serveur (l.1232 et
   l.1258 du service, `primaryHonorsPreference`).
10. **Tests upstream** : on n'en modifie aucun. Un test dont le comportement change volontairement recevrait
    `skip: forkChangedSkip` et figurerait nominativement dans la liste « Tests upstream marqués » ci-dessous. Une garde
    vérifie que les deux correspondent. Aucun test n'est attendu, voir T2.
11. **CA9** passe par une surcharge de la clé upstream `accountPreferences.autoSelectAudioDescription` dans la surcouche
    `lib/fork/i18n/` (extension de D6). On ne touche pas au Dart.
12. **Hors du code, à documenter (cf. Risques restants)** :
    - le `PUT` d'incrustation Plex (`selectSubtitleStreamForBurn`) ;
    - sur Jellyfin, avec « Mémoriser » activé, l'écriture du choix automatique par les rapports de progression ;
    - le refus 4xx en transcodage (`playback_reload.dart` l.200-206), au backlog.

### Règle audio — `forkPreferredAudio(service, availableTracks)`

Renvoie `null` dans chacun de ces cas (comportement upstream) :
- **A1** :
  - `service.profileSettings == null`,
  - ou `!profile.autoSelectAudio` (CA8),
  - ou `profile.defaultAudioLanguage` est vide,
  - ou `service.metadata.kind == MediaKind.track` (musique),
  - ou `availableTracks` est vide.
- **A2** : la ligne serveur est déjà dans la langue préférée, selon
  `service.languageMatches(row.languageCode ?? row.language, pref)`. La ligne serveur est la première
  `plexMediaInfo.audioTracks` avec `selected`. À défaut, et seulement si `metadata.backend.usesMediaBrowserApi`, c'est
  la ligne telle que `(row.index ?? row.id) == plexMediaInfo.defaultAudioStreamIndex`.
- **A3** : `ForkTrackChoiceMemory.hasManualPick(metadata, ForkTrackKind.audio)`.
- **A4** : aucune piste de `availableTracks` ne correspond à la langue préférée. Couvre CA6 (piste par défaut du
  fichier) et le transcodage, où le flux n'a qu'une piste.

Sinon, la règle prend la première piste de la langue préférée marquée `isDefault`, à défaut la première de la
langue. Elle journalise `appLogger.d('Fork preferred language: audio <langue> over server selection')` et renvoie
`TrackSelectionResult(track, TrackSelectionPriority.profile)`.

### Règle sous-titres — `forkPreferredSubtitle(service, availableTracks, selectedAudioTrack)`

Renvoie `null` dans chacun de ces cas (comportement upstream) :
- **S1** :
  - conditions A1 sauf « `availableTracks` vide » ;
  - ou `profile.defaultSubtitleLanguage` est vide ;
  - ou `profile.subtitleMode` n'est pas `always`, `smart` ou `onlyForced` (le `none` Plex signifie « manuel »).
- **S2** : `ForkTrackChoiceMemory.hasManualPick(metadata, ForkTrackKind.subtitle)`.
- **S3** : la règle voudrait une piste de la langue préférée, `availableTracks` n'en contient aucune, mais
  `plexMediaInfo?.subtitleTracks` en annonce une. C'est une piste native qui n'est pas encore arrivée : l'upstream gère
  l'attente.

Notations :
- `P` est la langue de sous-titres préférée.
- `A` est `selectedAudioTrack`. Si `A` est `null` ou sans langue, on la traite comme étant « dans une autre langue ».
- `forcé(P)` est la première piste avec `effectiveForced` et la langue `P`.
- `complet(P)` est la première piste **non** forcée de langue `P`, en préférant `isDefault`. À défaut, on prend
  `forcé(P)`.

Décision, dans l'ordre :
1. Modes `always` et `smart`, si `A` est dans la langue `P` : `forcé(P)` sinon off (CA6, CA12).
2. Mode `always` : `complet(P)` sinon off (CA7 : jamais une autre langue).
3. Mode `smart` (sémantique upstream) : si `A` est dans la langue **audio** préférée, `forcé(P)` sinon off ; sinon
   `complet(P)` sinon off.
4. Mode `onlyForced` : `forcé(P)` sinon off.

Le résultat est `TrackSelectionResult(piste ou SubtitleTrack.off, TrackSelectionPriority.profile)`, journalisé de la
même manière.

## Tâches

### T1 — Mémoire locale des choix manuels
- Complexité : M
- Dépend de : —
- Fichiers :
  - créer `lib/fork/track_choice_memory.dart` ;
  - créer `test/fork/track_choice_memory_test.dart`.
- À faire :
  - `enum ForkTrackKind { audio, subtitle }`, avec les codes de stockage `'a'` et `'s'`.
  - `abstract final class ForkTrackChoiceMemory` avec :
    - `static final pref = JsonPref<Map<String, dynamic>>('fork_manual_track_picks', defaultValue: const {},
      encode: json.encode, decode: (raw) => Map<String, dynamic>.from(raw as Map))`. Le pref n'est ajouté à aucune liste
      de `SettingsService` : ni export, ni réinitialisation.
    - `static const maxEntries = 500`.
    - `static String? keyFor(MediaItem item)` : `serverIdOrNull(item.serverId)`. S'il est `null`, renvoie `null`, sinon
      `buildGlobalKey(serverId, item.id)` (`lib/utils/global_key_utils.dart`). La clé désigne le contenu lui-même
      (épisode ou film), jamais la série.
    - `static bool hasManualPick(MediaItem item, ForkTrackKind kind)`, **synchrone**. Renvoie `false` si
      `SettingsService.instanceOrNull` vaut `null`, si `read(SettingsService.rememberTrackSelections)` est faux, ou si la
      clé vaut `null`. Sinon, renvoie `true` si l'entrée contient le code du type.
    - `static Future<void> recordManualPick(MediaItem item, ForkTrackKind kind)`. Ne fait rien si « Mémoriser » est
      désactivé ou si la clé vaut `null`. Sinon, écrit `{code: DateTime.now().millisecondsSinceEpoch}` dans l'entrée
      (en fusionnant avec l'autre code), puis élague au-delà de `maxEntries` en gardant les entrées au plus grand
      horodatage, sur le modèle de `ScopedPlayerPrefs._prune`. Toute exception est capturée et journalisée
      (`appLogger.w`), jamais propagée.
  - Cache mémoire de la map décodée : il est invalidé à chaque écriture et quand l'instance de `SettingsService`
    change (comparaison `identical`). On évite ainsi de décoder le JSON à chaque passage de l'échelle et à chaque
    reconstruction de l'aperçu. Prévoir `@visibleForTesting static void resetForTesting()`.
- Tests (initialisation de `SharedPreferences.setMockInitialValues` comme dans les tests upstream de
  `SettingsService`) :
  - écriture puis lecture, par type ;
  - « Mémoriser » désactivé : `false` à la lecture, rien n'est écrit (CA4) ;
  - service non initialisé : `false` ;
  - élagage à 501 entrées : l'entrée la plus ancienne disparaît ;
  - un élément sans `serverId` n'est pas mémorisé.
- Critères d'acceptation couverts : CA4, CA4bis, CA4ter (stockage).

### T2 — Règle « langue préférée d'abord » dans l'échelle de sélection
- Complexité : L
- Dépend de : T1
- Fichiers :
  - créer `lib/fork/preferred_languages.dart` ;
  - modifier `lib/services/track_selection_service.dart` ;
  - créer `test/fork/preferred_languages_test.dart` ;
  - créer `test/fork/preferred_languages_flow_test.dart` ;
  - créer `test/fork/fork_changed_skip_guard_test.dart` ;
  - modifier `test/fork/fork_test_utils.dart`.
- À faire :
  - Dans `preferred_languages.dart`, écrire `forkPreferredAudio` et `forkPreferredSubtitle` exactement selon les règles
    ci-dessus. On n'utilise que les membres publics du service : `profileSettings`, `metadata`, `plexMediaInfo` et
    `languageMatches`. Pour `effectiveForced`, on importe `lib/utils/subtitle_forced_semantics.dart`.
  - Dans `track_selection_service.dart`, faire trois modifications marquées
    `// FORK: langues-preferees — <raison>` :
    1. ajouter l'`import '../fork/preferred_languages.dart';` ;
    2. dans `selectAudioTrack`, juste avant le commentaire `// Priority 2: Check server-selected track`, ajouter
       `final forkAudio = forkPreferredAudio(this, availableTracks); if (forkAudio != null) return forkAudio;` ;
    3. dans `selectSubtitleTrack`, juste avant le commentaire `// Priority 2: Trust the server's selected track`, ajouter
       `final forkSubtitle = forkPreferredSubtitle(this, availableTracks, selectedAudioTrack);
       if (forkSubtitle != null) return forkSubtitle;`.

    Ne rien modifier d'autre dans ce fichier.
  - Dans `fork_test_utils.dart`, ajouter :
    - `const forkChangedSkip = 'Comportement changé par Popkino (langues-preferees)';`
    - `const Map<String, String> forkChangedSkipAllowlist = {};`, dont les clés sont
      `'<chemin> :: <nom du test>'` et les valeurs le CA qui justifie le marquage.
  - Dans `fork_changed_skip_guard_test.dart`, parcourir `test/**/*.dart` hors de `test/fork/`, compter les occurrences
    de `forkChangedSkip`, puis vérifier deux choses : le nombre est égal à `forkChangedSkipAllowlist.length`, et chaque
    fichier cité dans la liste contient au moins une occurrence.
  - Lancer toute la suite. **Aucun test upstream ne devrait échouer.** Les tests à profil de
    `track_selection_service_test.dart`, `playback_subtitle_resolver_test.dart` et `playback_track_preview_test.dart`
    ont été relus :
    - ils n'ont pas de langue audio préférée ;
    - ou ils ont `PlayDefaultAudioTrack: true` (donc `autoSelectAudio` faux) ;
    - ou le serveur n'a rien choisi et l'upstream donnait déjà le même résultat.

    Si un test upstream échoue, **ne pas le marquer de soi-même** : s'arrêter et transmettre au pilote son nom et
    l'assertion en cause. Le pilote décide et met à jour la liste ci-dessous.
- Tests :
  - `preferred_languages_test.dart`, tests unitaires sur des `AudioTrack`/`SubtitleTrack` construits à la main :
    - A1 à A4, dont « deux pistes anglaises, l'une `isDefault` » : c'est elle qui est choisie ;
    - « serveur déjà en anglais (commentaire) » : `null` ;
    - S1 à S3 ;
    - chaque ligne du tableau des modes, avec audio dans la langue `P`, dans la langue audio préférée, dans une autre
      langue, et `null` ;
    - musique ;
    - Plex et Jellyfin (`defaultAudioStreamIndex` sans `selected`).
  - `preferred_languages_flow_test.dart`, sur les **vrais mappers**, sur le modèle de `playback_track_preview_test.dart`
    (JSON `Part.Stream[]` Plex et `MediaSources` Jellyfin), avec le profil « English / French / Toujours » :
    - CA1 et CA2 : `previewPlaybackTracks` et `PlaybackSubtitleResolver.resolve` donnent l'audio anglais et les
      sous-titres français, pour un fichier dont le serveur a retenu le français ;
    - CA3 : même chose sur Jellyfin (`DefaultAudioStreamIndex` = français) ;
    - CA6 : fichier en français seul, aucun sous-titre ; fichier en allemand seul, sous-titres français ;
    - CA12 : français + forcé français → forcé ; français + complet français seul → off ;
    - CA7 : anglais sans sous-titres français → off, même si une piste anglaise `default` existe ;
    - CA8 : `selectAudioByLanguage: false` donne le même résultat qu'avec un profil `null` ;
    - CA5 : `TrackSelectionService.selectAudioTrack` avec une préférence française reportée → français, priorité
      `navigation`.
- Critères d'acceptation couverts : CA1, CA2, CA3, CA6, CA7, CA8, CA12 ; CA4 (règle insensible au serveur).

### T3 — Marquer les choix manuels et reportés
- Complexité : M
- Dépend de : T1
- Fichiers :
  - modifier `lib/services/track_manager.dart` ;
  - modifier `lib/screens/video_player/parts/playback_reload.dart` ;
  - créer `test/fork/track_manager_fork_test.dart`.
- À faire :
  - Dans `track_manager.dart`, faire deux modifications marquées `// FORK: langues-preferees — …` :
    1. ajouter l'import ;
    2. dans `_guardTrackChange`, juste après `if (!await shouldPersistTrackSelections()) return null;`, ajouter
       `unawaited(ForkTrackChoiceMemory.recordManualPick(metadata, trackType == 'audio' ? ForkTrackKind.audio :
       ForkTrackKind.subtitle));`.

    Ce point est atteint par les choix explicites (`onAudioTrackSelectedByUser`, `onSubtitleTrackSelectedByUser`,
    `cycleAudioTrack`, `cycleSubtitleTrack`) et par les choix reportés de priorité `navigation` (CA4ter). Ce n'est pas
    le cas des choix automatiques.
  - Dans `playback_reload.dart` (changement de source, l.186-208), ajouter un import et une seule instruction marquée
    `// FORK:`. Elle se place **après** le bloc `if (isPlexBacked && (isSubtitleChange || isAudioChange) && await
    TrackManager.shouldPersistTrackSelections()) { … }`, donc après le `throw` sur `!saved`. Si
    `(isAudioChange || isSubtitleChange) && await TrackManager.shouldPersistTrackSelections()`, elle appelle
    `recordManualPick` (sans attendre) pour l'audio si `isAudioChange` et pour les sous-titres si `isSubtitleChange`,
    avec `_currentMetadata`. Un `PUT` refusé lève une exception avant d'arriver là, donc l'indicateur n'est pas posé.
- Tests (`TrackManager` avec un faux `Player`, sur le modèle de `test/services/track_manager_test.dart`) :
  - choix explicite avec « Mémoriser » activé → indicateur posé ; désactivé → rien ;
  - préférence `navigation` reportée et appliquée → indicateur posé (CA4ter) ;
  - sélection automatique `profile` ou `serverSelected` → rien ;
  - CA10 : un faux `TrackPreferencePersister` qui lève une `MediaServerHttpException` temporaire, puis un refus 4xx →
    pas d'exception, piste appliquée au lecteur, indicateur posé.
  - Le chemin `playback_reload` se vérifie en recette (T6), car il n'existe pas de test unitaire upstream de ce widget.
- Critères d'acceptation couverts : CA4bis, CA4ter, CA5, CA10.

### T4 — Transcodage : intention de langue et sous-titres calés sur l'audio envoyé
- Complexité : L
- Dépend de : T2 (même fichier `lib/fork/preferred_languages.dart`), T3 (même fichier `playback_reload.dart`)
- Fichiers :
  - modifier `lib/fork/preferred_languages.dart` ;
  - modifier `lib/screens/video_player_screen.dart` ;
  - modifier `lib/screens/video_player/parts/playback_reload.dart` ;
  - modifier `lib/screens/video_player/parts/playback_open.dart` ;
  - créer `test/fork/preferred_languages_launch_test.dart`.
- À faire :
  - Dans `preferred_languages.dart` :
    - `Future<AudioTrack?> forkLaunchAudioIntent({required MediaItem item, required AccountPreferencesController
      controller})`. Si `controller.activePreferences == null`, attendre
      `controller.ensureActiveLoaded().timeout(const Duration(seconds: 2))`, en capturant le délai dépassé ou l'erreur.
      Lire ensuite le profil et renvoyer `null` dans les cas A1 (sans la condition sur les pistes) ou A3. Sinon,
      renvoyer `AudioTrack(id: carriedAudioTrackId, language: profile.defaultAudioLanguage)`. Quand le profil est déjà
      chargé, aucun `await` réel n'a lieu.
    - `AudioTrack? forkTranscodedAudioAnchor(PlaybackInitializationResult result)`. Renvoie `null` si
      `!result.isTranscoding` ou si `result.mediaInfo` vaut `null`. Sinon, prend la ligne `audioTracks` d'`id ==
      result.activeAudioStreamId`, à défaut la première `selected`, et renvoie
      `PlaybackSubtitleResolver.audioTrackForSource(ligne)`, ou `null` sans ligne.
  - Dans `video_player_screen.dart` (l.~1817, chemin en ligne de `_initializePlayer`) :
    - capturer `final forkAccountPrefs = context.read<AccountPreferencesController>();` à côté des autres
      `context.read`, avant tout `await` ;
    - remplacer `_playbackDataFuture = playbackResolver.resolve(PlaybackInitializationOptions(…))` par
      `_playbackDataFuture = (_preferredAudioTrack == null && _selectedAudioStreamId == null ? forkLaunchAudioIntent(…)
      : Future<AudioTrack?>.value()).then((forkIntent) => playbackResolver.resolve(PlaybackInitializationOptions(…,
      preferredAudioTrack: _preferredAudioTrack ?? forkIntent, …)))`.

    Les valeurs lues dans la closure sont copiées dans des `final` locales avant l'appel. L'affectation de
    `_playbackDataFuture` reste synchrone. Marquer `// FORK:`. Le chemin hors ligne (`playback_start.dart` l.189)
    n'est **pas** modifié : un téléchargement ne passe jamais par le transcodage.
  - Dans `playback_reload.dart` (l.~585, `PlaybackInitializationOptions` du rechargement en place) :
    - avant `playbackResolver.resolve`, ajouter
      `final forkIntent = initializationAudioTrack == null && targetAudioStreamId == null ? await
      forkLaunchAudioIntent(item: metadata, controller: <AccountPreferencesController capturé avant le premier await de
      la méthode>) : null; if (!isCurrentReload()) return MediaReloadOutcome.superseded;` ;
    - passer `preferredAudioTrack: initializationAudioTrack ?? forkIntent`.

    Ne **pas** modifier l'argument `preferredAudioTrack` de `_resolveSubtitleSelectionForOpen` à cet endroit. Marquer
    `// FORK:`.
  - Dans `video_player_screen.dart` (correctif de l'objection de la plateforme, tour 1 de validation) :
    - déclarer dans `VideoPlayerScreenState`, avec un `// FORK:`, le champ
      `bool _forkLaunchIntentUsed = false;`, à côté de `_selectedAudioStreamId` (l.~778) ;
    - l'affecter à `forkIntent != null` dans la closure `.then` de `_initializePlayer`, avant
      `playbackResolver.resolve`, ainsi qu'au point d'appel de `playback_reload.dart` ci-dessus, avant `resolve` ;
    - dans `_commitPlaybackSession` (l.1120), juste après `_selectedAudioStreamId = session.audioStreamId;`, ajouter
      `if (_forkLaunchIntentUsed && !session.isTranscoding) _selectedAudioStreamId = null; // FORK: langues-preferees`.

    Raison : en lecture directe, l'intention revient en `activeAudioStreamId` (`plex_client.dart` l.3884/3894,
    `playback.dart` l.447) puis dans `_selectedAudioStreamId`. Un changement de qualité ou de version la renverrait
    alors au transcodeur (`playback_reload.dart` l.511-514, `targetAudioStreamId = selectedAudioStreamId ??
    _selectedAudioStreamId`) et annulerait un choix manuel fait dans mpv. En transcodage, l'id est la piste réellement
    envoyée : il reste.
  - Dans `playback_open.dart`, `_resolveSubtitleSelectionForOpen` : remplacer `preferredAudioTrack: preferredAudioTrack`
    par `preferredAudioTrack: preferredAudioTrack ?? forkTranscodedAudioAnchor(result)`, avec un `// FORK:`. Le
    descripteur exact est retenu en priorité 1 par `selectAudioTrack` (même `id`, `title`, `language`), et le resolver
    calcule alors les sous-titres pour l'audio réellement envoyé.
- Tests (`preferred_languages_launch_test.dart`) :
  - `forkLaunchAudioIntent` :
    - profil chargé → intention anglaise ;
    - `autoSelectAudio` faux, musique ou indicateur manuel → `null` ;
    - profil `null`, puis chargé par `ensureActiveLoaded` en moins de 2 s → intention ;
    - au-delà de 2 s → `null`, sans exception (contrôleur factice) ;
  - `forkTranscodedAudioAnchor` :
    - lecture directe → `null` ;
    - transcodage avec `activeAudioStreamId` = français → descripteur français ;
  - `PlaybackSubtitleResolver.resolve` avec ce descripteur, sur un fichier « 2 pistes anglaises + français » transcodé en
    français → aucun sous-titre complet (CA6/CA12) ;
  - résolution Plex de l'intention : `findSourceAudioTrackForIntent(intention, lignes)` renvoie la ligne anglaise unique
    (CA1 en transcodage) et `null` quand il y a deux lignes anglaises (risque documenté).
  - `_commitPlaybackSession`. Si un test widget de l'écran est trop lourd, extraire la condition dans une fonction pure
    `forkAudioStreamIdAfterCommit({required int? sessionAudioStreamId, required bool launchIntentUsed, required bool
    isTranscoding})` de `lib/fork/preferred_languages.dart`, appelée par la ligne `// FORK:`, et la tester :
    - intention utilisée en lecture directe → `null` ;
    - intention utilisée en transcodage → l'id est conservé ;
    - sans intention → l'id est conservé (comportement upstream).
- Critères d'acceptation couverts : CA1 et CA3 en transcodage, CA6 et CA12 en transcodage, démarrage à froid ; pas de
  régression sur le changement de qualité après un choix manuel.

### T5 — Texte de « Choisir l'audio par langue » (CA9)
- Complexité : S
- Dépend de : —
- Fichiers :
  - modifier `lib/fork/i18n/fr.json`, `lib/fork/i18n/en.json` et `lib/fork/i18n/rebrand_rules.json` (`_comment`) ;
  - régénérer `lib/i18n/*.i18n.json` et `lib/i18n/strings*.g.dart`.
- À faire :
  - Ajouter `"accountPreferences": {"autoSelectAudioDescription": "…"}` aux deux surcouches :
    - fr : « Activé : la piste audio dans votre langue préférée est choisie dès que le fichier en contient une.
      Désactivé : la piste marquée par défaut dans le fichier est conservée. »
    - en : « On: picks the audio track in your preferred language whenever the file has one. Off: keeps the track the
      file marks as default. »
  - Compléter le `_comment` de `rebrand_rules.json` d'une phrase : « The overlays may also override existing upstream
    keys when only the wording changes (e.g. accountPreferences.autoSelectAudioDescription). »
  - Puis lancer `python3 scripts/fork/rebrand_i18n.py`, puis `scripts/codegen.sh`. Ne jamais éditer `lib/i18n/` à la
    main (D6).
- Tests : `python3 scripts/fork/rebrand_i18n.py --check`, `scripts/codegen.sh --check`,
  `python3 scripts/checks/clean_translations.py --check --strict`, `test/fork/i18n_branding_test.dart`.
- Critères d'acceptation couverts : CA9.

### T6 — Recette sur la Fire Stick
- Complexité : M
- Dépend de : T1 à T5
- Fichiers : aucun. Le compte rendu va dans `docs/technique/langues-preferees/recette.md`.
- À faire : voir « Vérification globale ». Journaux de débogage activés.
- Critères d'acceptation couverts : CA1 à CA12, dont CA11 (télécommande seule, focus visible, Retour).

## Tests upstream marqués `forkChangedSkip`

| Test (fichier :: nom) | CA qui justifie le marquage |
|---|---|
| *(aucun attendu, à confirmer par T2)* | — |

## Vérification globale

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
dart format <fichiers modifiés>
python3 scripts/fork/rebrand_i18n.py --check && scripts/codegen.sh --check
python3 scripts/checks/clean_translations.py --check --strict
dart run scripts/checks/check_analyzer.dart
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh test/fork/
scripts/run_tests.sh   # suite complète : 0 échec, nombre d'ignorés = base + forkChangedSkipAllowlist.length
grep -rn "FORK: langues-preferees" lib | wc -l   # 5 fichiers upstream attendus
```

Recette sur la TV (APK `armeabi-v7a`, procédure P6 de `proposition-plateforme.md`), avec
`adb logcat -v time -s flutter | grep -E "Audio:|Subtitle:|Fork preferred|carry declined|stream selection"`.
Préparer le fichier de test : passer le souvenir Plex en français avec
`curl -X PUT ".../library/parts/<partId>?audioStreamID=<id fr>&X-Plex-Token=…"`, puis noter le `selected` avant et
après chaque scénario.
1. **Plex en lecture directe (qualité Originale)** :
   - CA1 et CA2 (menus des pistes) ;
   - CA4 : avec « Mémoriser » désactivé, `selected` ne bouge pas côté serveur ;
   - CA4bis ;
   - CA4ter : épisode 1 changé à la main, épisode 2 enchaîné, relance de l'épisode 2 ;
   - CA5, CA6 (fichier en français seul, fichier en allemand), CA7, CA8, CA12 ;
   - régression du changement de qualité : lancement en anglais, passage à la main au français, puis qualité 720p dans
     le menu du lecteur → l'audio reste en français.
2. **Plex en transcodage forcé (720p dans le menu du lecteur)** : CA1, puis un fichier « 2 pistes anglaises » (doit
   rester cohérent : audio français sans sous-titres complets).
3. **Jellyfin** : CA3, puis CA4bis avec « Mémoriser » activé. Vérifier `DefaultAudioStreamIndex` par `GET
   /Items/<id>/PlaybackInfo?UserId=…` : l'effet de bord documenté est attendu.
4. **Démarrage à froid** : `adb shell am force-stop io.github.adrien24.popkino`, puis lancement depuis la rangée
   « À suivre ». Aucun `[serverSelected]` en français n'est attendu.
5. **CA10** : il est prouvé par les tests de T3 (faux persister : erreur temporaire, puis refus 4xx). Sur la TV,
   avec « Mémoriser » activé, provoquer une coupure réseau **brève** du serveur juste après un changement de piste, et
   constater qu'aucun message bloquant ne vient de l'écriture. Un arrêt du flux lui-même est hors sujet : en lecture
   directe, mpv doit relire le flux pour la nouvelle piste.
6. **CA11** : tous les parcours à la télécommande ; une fois avec ExoPlayer.
7. **CA9** : Paramètres > Préférences du compte, en français puis en anglais.

## Risques restants

- **Transcodage d'un fichier qui a plusieurs pistes anglaises** : l'intention est refusée (`_findTrackByEvidenceBands`
  l.490), le serveur garde sa piste. Les sous-titres restent cohérents grâce à T4, mais CA1 n'est pas tenu dans ce cas
  précis. On l'accepte : cas rare, la Fire Stick lisant en lecture directe en qualité Originale.
- **Écart d'audio au démarrage** : comme aujourd'hui, mpv peut faire entendre un instant la piste par défaut du fichier
  avant le changement d'`aid`. À mesurer en recette (P6). Une option `aid` dans `loadfile` n'est à envisager que si la
  gêne est réelle.
- **Effets de bord serveur** (documentés, non corrigés) :
  - l'incrustation de sous-titres en transcodage Plex écrit sur le serveur même si « Mémoriser » est désactivé
    (upstream) ;
  - sur Jellyfin avec « Mémoriser » activé, l'audio choisi par la règle part dans les rapports de progression et
    devient le souvenir du compte ;
  - sur Plex, un choix reporté est écrit sur l'épisode suivant (upstream, CA4ter le veut).
- **Indicateur posé alors que l'écriture serveur échoue ensuite** (chemin `TrackManager`, CA10) : au lancement suivant,
  on suit le serveur, dont la valeur est périmée. Le choix de l'utilisateur est perdu, sans blocage. Repli possible
  plus tard : mémoriser la piste elle-même (alternative 3 de `proposition-app.md`).
- **Indicateurs partagés entre les profils de l'app** sur la même TV, comme `ScopedPlayerPrefs`. Un choix manuel d'un
  profil fait suivre le serveur, propre à chaque compte, pour ce contenu dans l'autre profil. Impact faible.
- **Intention en lecture directe** : elle fixe `activeAudioStreamId`. `_selectedAudioStreamId` est remis à `null` au
  commit (T4), ce qui rétablit l'état upstream d'un lancement sans report. Vérifié en recette (point 1).
- **Démarrage à froid** : jusqu'à 2 s d'attente du profil avant de demander le flux, seulement s'il n'est pas chargé.
- **Langue réglée sur une série dans Plex** : ignorée (hors périmètre, backlog Could).
- **Refus 4xx en transcodage avec « Mémoriser » activé** : il bloque le changement de piste (upstream,
  `playback_reload.dart` l.200-206). À ajouter au backlog.
- **Fusions** : 5 fichiers upstream sont touchés, avec environ 22 lignes `// FORK:` :
  - `track_selection_service.dart`
  - `track_manager.dart`
  - `playback_reload.dart`
  - `video_player_screen.dart`
  - `playback_open.dart`

  Une refonte upstream de l'échelle de sélection obligerait à replacer les crochets à la main. Les tests de
  `test/fork/` et la garde `forkChangedSkip` le signaleront.

## Décisions durables à reporter dans `decisions.md` après approbation

- **D11** : changer un comportement upstream par un crochet `// FORK:` qui appelle `lib/fork/`, `null` = upstream, sans
  nouvelle valeur dans les enums upstream.
- **Extension de D4** : `forkChangedSkip`, avec sa liste nominative et sa garde.
- **Extension de D6** : la surcouche i18n peut surcharger une clé upstream existante quand seul le texte change.
