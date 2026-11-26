# Proposition app — langues-preferees

Auteur : architecte-app (pilote du débat) · 2026-11-26
Spec : `docs/produit/specs/langues-preferees.md` (validée)

## Compréhension de la spec

Au lancement d'un film ou d'un épisode, la langue audio préférée du compte (anglais) et la langue de sous-titres
préférée (français) doivent passer **avant** la piste que le serveur a retenue pour ce fichier (souvenir Plex par
fichier, `DefaultAudioStreamIndex` Jellyfin). Un choix manuel n'est repris au lancement suivant que si « Mémoriser les
pistes choisies » est activé. Pas de sous-titres quand l'audio joué est déjà dans la langue des sous-titres.

Critères dans mon périmètre : tous. CA1, CA2, CA3, CA6, CA7 et CA8 portent sur l'ordre de sélection. CA4, CA4bis, CA5
et CA10 portent sur la mémoire des choix. CA9 est un texte. CA11 est garanti parce qu'on ne change aucune interface
navigable.

## Existant

**Un seul « cerveau » de sélection, utilisé à quatre endroits.** `TrackSelectionService`
(`lib/services/track_selection_service.dart`) porte l'échelle de priorités `TrackSelectionPriority` (l.671 :
`navigation > serverSelected > profile > defaultTrack > off`) dans `selectAudioTrack` (l.944) et `selectSubtitleTrack`
(l.1043). Elle est construite :

1. avant l'ouverture, par `PlaybackSubtitleResolver.resolve` (`lib/services/playback_subtitle_resolver.dart` l.202),
   sur des descripteurs `source:<id>` construits à partir des lignes serveur (`audioTracksForSource`,
   `subtitleTrackForSource`), **avec** le profil. Le sous-titre retenu ici est ensuite transmis au `TrackManager` comme
   préférence de priorité `navigation` (`playback_open.dart` l.1172-1176, `SubtitlePreference.trackOrNull` : un « off »
   devient `SubtitleOffPreference`) ;
2. pendant la lecture, par `TrackManager.applyTrackSelection` (`lib/services/track_manager.dart` l.331), sur les pistes
   natives mpv/ExoPlayer, avec le profil (`AccountPreferencesController.activePreferences`, chargé au démarrage par
   `ensureActiveLoaded`) ;
3. pour le contrôle « pistes prêtes ? », par `TrackManager._tracksReadyForSelection` (l.236), **sans** profil ;
4. sur la fiche, par `previewPlaybackTracks` (`lib/services/playback_track_preview.dart`), qui affiche les pistes
   prévues avant la lecture.

**Cause du symptôme.**
- Audio : la priorité 2 (`serverSelected`, l.977-1012) prend la ligne `selected` du serveur (Plex : souvenir par
  fichier, posé par n'importe quelle app via `PUT /library/parts/{id}?audioStreamID=…&allParts=1`) ou, pour
  Jellyfin, la ligne `DefaultAudioStreamIndex` (le mapper `jellyfin_media_info_mapper.dart` l.37-39 la marque
  `selected`). Le profil (priorité 3) n'est consulté que si rien n'a été trouvé. C'est le cas de #1615 et de #2649.
- Sous-titres : pour Plex, `_selectSubtitleTrackByProfile` (l.801) sort tout de suite (`backend == plex`) : la décision
  revient toujours au serveur. S'il a retenu « pas de sous-titres » avec l'audio français, la branche l.1144-1147 coupe
  les sous-titres. Le mode « Toujours » tombe aussi, à défaut, sur `_findDefaultSubtitleTrack ?? first` (l.818-822) :
  cela impose une autre langue, contraire à CA7.

**Mémoire des choix.** `SettingsService.rememberTrackSelections` (`settings_service.dart` l.702, vrai par défaut)
commande tout :
- Plex : `TrackManager._guardTrackChange` → `_saveTrackPreferences` → `_plexTrackPersister`
  (`video_player_screen.dart` l.455) écrit sur le serveur à chaque choix explicite
  (`onAudioTrackSelectedByUser` / `onSubtitleTrackSelectedByUser`, l.461-470). Les choix automatiques ne sont écrits
  que s'ils viennent d'une préférence `navigation` (l.1232 et l.1258 du service, plus le verrou
  `persistAutomaticSubtitleSelection`, #2323).
- Jellyfin : les index joués partent dans les rapports de progression (`playback_progress_tracker.dart` l.789-799) et
  `_ensureServerRemembersSelections` active les drapeaux `RememberAudioSelections`/`RememberSubtitleSelections` du
  compte.
- Changement de piste pendant un transcodage : `playback_reload.dart` l.188-205 écrit directement par `selectStreams`,
  sans passer par `TrackManager`.
- Enchaînement d'épisodes (CA5) : `episode_navigation.dart` l.169-200 transmet `_sessionAudioPreference` et la
  préférence de sous-titres (priorité 1 `navigation`), sauf si `followServerTrackSelections` est activé.

**Stockage local disponible.** `JsonPref<Map<String, dynamic>>` (`base_shared_preferences_service.dart` l.603) et
le modèle d'entrées datées avec plafond de `ScopedPlayerPrefs` (`scoped_player_prefs.dart`, `maxEntriesPerProperty`,
`_prune`). Pour une lecture synchrone sans planter dans les tests : `SettingsService.instanceOrNull`. Clés :
`buildGlobalKey(serverId, id)` et `serverIdOrNull` (`lib/media/ids.dart`).

**CA9.** `account_preferences_detail_screen.dart` l.239-246 affiche `t.accountPreferences.autoSelectAudioDescription`
dans les deux états. Textes : fr « Désactivé : la piste audio marquée par défaut dans le fichier est conservée. »,
en « Off keeps whatever audio track the file marks as default. ». Le script `scripts/fork/rebrand_i18n.py` fusionne
déjà la surcouche `lib/fork/i18n/<locale>.json` et la surcouche l'emporte (`merge_overlay`, testé par
`test_overlay_wins_and_adds_keys`).

**Avertissement upstream à contredire en connaissance de cause.** Le commentaire de `AccountPreferencesDetailScreen`
(l.47-50) dit : « Do not add client-side enforcement on top of them, or the preference gets applied twice ». C'est
justement ce qu'on fait. C'est sans danger si la règle du fork **ne fait rien quand le choix du serveur respecte déjà
la préférence** : appliquer deux fois donne alors le même résultat (cf. règle A2).

## Approche proposée

### Principe

Une **règle « langue préférée d'abord »**, écrite en fonctions pures dans `lib/fork/preferred_languages.dart`, est
appelée par deux crochets dans `TrackSelectionService`, **entre la priorité 1 (`navigation`) et la priorité 2
(`serverSelected`)**. Si la règle renvoie `null`, l'échelle upstream se déroule sans changement. Comme les quatre
consommateurs passent par ce service, la fiche (aperçu), la décision avant ouverture (y compris le chargement du bon
fichier de sous-titres externe) et la lecture restent cohérentes sans autre modification.

La priorité 1 reste au-dessus : un choix porté d'un épisode à l'autre (CA5) n'est pas touché. Le résultat porte la
priorité existante `TrackSelectionPriority.profile`. On n'ajoute pas de valeur à l'enum, pour ne pas casser les
`switch` exhaustifs upstream. Effet utile : les choix `profile` ne sont **jamais écrits sur le serveur** (l.1232 et
l.1258), et `primaryHonorsPreference` reste faux dans le resolver.

### Règle audio (`forkPreferredAudio`)

Elle renvoie `null` (comportement upstream) dans chacun de ces cas :
- **A1** : pas de profil, `autoSelectAudio == false` (CA8), langue audio préférée vide, ou contenu musical
  (`metadata.kind == MediaKind.track`) ;
- **A2** : la ligne retenue par le serveur (Plex : `selected` ; MediaBrowser : `selected` sinon
  `defaultAudioStreamIndex`) est déjà dans la langue préférée. L'upstream la garde, ce qui préserve son choix entre
  deux pistes anglaises (VO ou commentaire) ;
- **A3** : « Mémoriser » est activé et l'utilisateur a choisi l'audio à la main pour ce contenu dans Popkino
  (`ForkTrackChoiceMemory.hasManualPick`, voir plus bas). Le serveur contient alors ce choix : l'upstream le
  reprend (CA4bis) ;
- **A4** : aucune piste disponible n'est dans la langue préférée (CA6 : on garde l'échelle upstream, qui donne en
  pratique la piste par défaut du fichier).

Sinon, elle prend parmi les pistes de la langue préférée celle marquée `isDefault`, à défaut la première (même
comparaison que l'upstream : `TrackSelectionService.languageMatches`). Résultat : `TrackSelectionResult(track,
profile)`.

### Règle sous-titres (`forkPreferredSubtitle`)

Elle renvoie `null` (comportement upstream) dans chacun de ces cas :
- **S1** : mêmes conditions que A1 (dont `autoSelectAudio == false`, pour CA8 et par cohérence avec Plex Web, qui
  force `autoSelectSubtitle=0` dans ce cas, cf. `PlexAccountPreferences.queryParametersFor`), ou langue de
  sous-titres préférée vide, ou mode `none`, `defaultMode` ou inconnu. Le `none` Plex signifie « manuel » : on n'y
  touche pas ;
- **S2** : « Mémoriser » est activé et l'utilisateur a choisi les sous-titres à la main pour ce contenu ;
- **S3** : la règle voudrait un sous-titre de la langue préférée, aucune piste disponible ne convient, mais le
  catalogue serveur (`plexMediaInfo.subtitleTracks`) en annonce un. C'est une piste native pas encore arrivée : on
  laisse l'upstream gérer l'attente (son mécanisme d'échéance à 30 s). En pratique ce cas ne se présente qu'en lecture
  native sans passage par le resolver, puisque le resolver voit tout le catalogue.

Sinon, avec `A` la piste audio retenue (paramètre `selectedAudioTrack`, déjà calculé par l'appelant) :

| Mode du compte | Audio `A` dans la langue des sous-titres préférés | Autre langue (ou inconnue) |
|---|---|---|
| `always` (« Toujours activé ») | off (décision utilisateur, CA6) — voir Q1 pour les forcés | sous-titre complet (non forcé) de la langue préférée, sinon off (CA7) |
| `smart` | sémantique upstream : si `A` est dans la langue **audio** préférée, sous-titre forcé de la langue préférée sinon off ; sinon sous-titre complet de la langue préférée sinon off | (idem) |
| `onlyForced` | sous-titre forcé de la langue préférée, sinon off | (idem) |

Différence volontaire avec l'upstream : **aucun repli sur « le premier sous-titre venu »** (CA7). Entre plusieurs
sous-titres complets en français, on prend celui marqué `isDefault` (pour un descripteur `source:` du resolver, c'est
la ligne `selected` du serveur), sinon le premier. Le choix entre SDH et non-SDH est hors périmètre.

### Mémoire des choix manuels (`lib/fork/track_choice_memory.dart`)

`ForkTrackChoiceMemory` ne garde **qu'un indicateur par contenu et par type de piste** (« l'utilisateur a choisi
l'audio / les sous-titres à la main dans Popkino »). Il ne garde pas la piste elle-même : le serveur la garde déjà
(Plex par fichier, Jellyfin par les rapports et les drapeaux `Remember*`). Concrètement :
- stockage : un `JsonPref<Map<String, dynamic>>('fork_manual_track_picks')` déclaré dans le fichier du fork. Clé
  `buildGlobalKey(serverId, item.id)` (épisode ou film, pas la série) → `{'a': ms, 's': ms}`. Plafond de 500 entrées,
  les plus anciennes supprimées (même logique que `ScopedPlayerPrefs._prune`). Cache mémoire pour que la lecture
  synchrone ne décode pas le JSON à chaque passage de l'échelle. Pas d'export ni de réinitialisation : c'est de l'état
  d'exécution, comme `supporterEntitlementCached` ;
- lecture : `hasManualPick(item, kind)` est synchrone, passe par `SettingsService.instanceOrNull` et renvoie `false`
  si le service n'est pas prêt (tests upstream) ou si `rememberTrackSelections` est désactivé (CA4) ;
- écriture : `recordManualPick(item, kind)`, appelée seulement si `rememberTrackSelections` est activé, **avant**
  l'écriture serveur, et sans attendre de résultat (`unawaited`, erreurs journalisées) pour ne rien bloquer (CA10) ;
- crochets d'écriture : `TrackManager.onAudioTrackSelectedByUser` et `onSubtitleTrackSelectedByUser` (ils couvrent le
  menu des pistes et les raccourcis `cycleAudioTrack`/`cycleSubtitleTrack`), plus le chemin de changement de source
  de `playback_reload.dart` (l.188, quand `isAudioChange`/`isSubtitleChange`).

Un choix **porté** à l'épisode suivant (CA5) n'est pas un choix manuel sur ce nouvel épisode : il n'est pas marqué.
L'upstream l'écrit pourtant sur le serveur pour ce nouvel épisode (priorité `navigation`, l.1232). Au lancement
suivant de cet épisode, la règle du fork repasse donc à l'anglais. C'est ce que dit CA4bis (« les autres épisodes
qu'il n'a pas modifiés à la main démarrent toujours en anglais ») ; voir Q2 pour confirmer.

### Crochets dans les fichiers upstream (diff complet prévu)

```dart
// lib/services/track_selection_service.dart — selectAudioTrack, juste avant « Priority 2 »
// FORK: langues-preferees — la langue du compte passe avant le souvenir serveur
final forkAudio = forkPreferredAudio(this, availableTracks);
if (forkAudio != null) return forkAudio;

// selectSubtitleTrack, juste avant « Priority 2 »
// FORK: langues-preferees — sous-titres recalculés pour l'audio réellement choisi
final forkSubtitle = forkPreferredSubtitle(this, availableTracks, selectedAudioTrack);
if (forkSubtitle != null) return forkSubtitle;
```

À cela s'ajoutent un `import` par fichier, une ligne dans chacun des deux `on…SelectedByUser` de `track_manager.dart`
et deux lignes dans `playback_reload.dart`. Au total : 3 fichiers upstream, environ 15 lignes, toutes marquées
`// FORK:`. Les fonctions du fork reçoivent le `TrackSelectionService` pour lire `profileSettings`, `metadata`,
`plexMediaInfo` et `languageMatches`, qui sont publics. Aucun membre privé n'est nécessaire.

### CA9 sans toucher au Dart

On surcharge la clé upstream `accountPreferences.autoSelectAudioDescription` dans `lib/fork/i18n/fr.json` et
`lib/fork/i18n/en.json`, puis on lance `rebrand_i18n.py` et `codegen.sh` (ordre de D6). Le texte décrit les deux
états :
- fr : « Activé : la piste audio dans votre langue préférée est choisie dès que le fichier en contient une.
  Désactivé : la piste marquée par défaut dans le fichier est conservée. »
- en : « On: picks the audio track in your preferred language whenever the file has one. Off: keeps the track the
  file marks as default. »

Les autres langues gardent le texte upstream (CA9 n'exige que fr et en ; backlog `traductions-fork`). Ce correctif de
libellé est le seul morceau proposable en PR à l'upstream : le mainteneur reconnaît que ces libellés prêtent à
confusion (#1615).

### Tests

- `test/fork/preferred_languages_test.dart` : tests unitaires de `forkPreferredAudio` et `forkPreferredSubtitle`
  (A1-A4, S1-S3, le tableau des modes), sur Plex et Jellyfin.
- `test/fork/preferred_languages_flow_test.dart` : scénarios des CA sur les **vrais mappers**, en reprenant le
  modèle de `test/services/playback_track_preview_test.dart` (JSON `Part.Stream[]` Plex et `MediaSources`
  Jellyfin) : `previewPlaybackTracks` et `PlaybackSubtitleResolver.resolve` pour CA1, CA3, CA6 (fr seul ; allemand
  seul), CA7 et CA8 ; `TrackSelectionService.selectAudioTrack` avec une préférence portée pour CA5.
- `test/fork/track_choice_memory_test.dart` : écriture et lecture, « Mémoriser » désactivé (CA4), plafond, service
  non initialisé, et l'enchaînement CA4bis : choix manuel, puis le serveur renvoie `selected` = fr, puis la règle
  renvoie `null`.
- Tests `TrackManager` dans `test/fork/` : un choix explicite marque la mémoire ; un serveur qui lève une erreur
  transitoire ne bloque rien (CA10).
- Tests upstream qui encodent l'ordre `serverSelected > profile` avec un profil contraire : ils sont marqués
  `skip: forkChangedSkip` (nouvelle constante dans `test/fork/fork_test_utils.dart`, à côté de `forkRemovedSkip`), sans
  être supprimés ni réécrits. Estimation : quelques cas dans `track_selection_service_test.dart`,
  `playback_subtitle_resolver_test.dart` et `track_manager_test.dart`, à confirmer en lançant la suite.

### Découpage pressenti (pour le plan)

- T1 (M) : `lib/fork/track_choice_memory.dart` et ses tests.
- T2 (L) : `lib/fork/preferred_languages.dart`, les crochets dans `track_selection_service.dart`, les tests unitaires
  et de parcours, le marquage des tests upstream en conflit. Classée L parce que c'est le choix des pistes à la
  lecture, avec des pistes natives qui arrivent tard.
- T3 (S, dépend de T1) : les crochets dans `track_manager.dart` et `playback_reload.dart` et leurs tests.
- T4 (S) : les textes de CA9 (surcouche i18n, script, codegen).
- T5 : recette manuelle sur la Fire Stick (CA1 à CA11), Plex puis Jellyfin.

## Alternatives écartées

1. **Mettre `profile` au-dessus de `serverSelected` dans l'enum upstream** (inverser les blocs). Écartée : le diff est
   plus gros et mélangé à du code délicat (attente des sous-titres en retard), et la logique ne sait plus distinguer
   A2 ni A3. CA4bis échouerait et deux pistes anglaises ne seraient plus départagées par le serveur. Les tests
   upstream cassés seraient bien plus nombreux, et chaque fusion de ce fichier, qui change souvent, deviendrait un
   conflit.
2. **Réécrire les indicateurs `selected` de `MediaSourceInfo` selon la langue du compte**, dans le constructeur de
   `TrackSelectionService` ou là où `mediaInfo` est fixé. C'est tentant (une seule ligne de diff), mais implicite :
   les journaux afficheraient `serverSelected` pour une décision du fork, et il faudrait aussi fausser
   `defaultSubtitleStreamIndex = -1` pour le « off » Jellyfin. Surtout, `_tracksReadyForSelection` (l.236) construit
   le service sans profil, donc avec d'autres données que le passage réel. Écartée au profit de crochets explicites.
3. **Mémoriser localement la piste choisie** (langue, titre, codec, intention de sous-titres) et l'appliquer comme une
   préférence portée. C'est plus robuste si l'écriture serveur échoue (CA10), mais cela duplique la mémoire que
   l'upstream confie au serveur et ajoute du rapprochement de pistes (risque de « mauvaise piste », cf. #1716/#1785).
   Écartée pour cette version ; c'est la piste de repli si la recette montre que la mémoire serveur n'est pas fiable.
4. **Synthétiser une préférence portée « anglais »** au lancement (`preferredAudioTrack`). Écartée : la priorité
   `navigation` déclenche l'écriture serveur (l.1232), donc on écrirait à chaque lancement. De plus,
   `findNativeAudioTrackForIntent` refuse de choisir entre deux pistes de la même langue (« declines rather than
   guesses »), et le repli redonnerait le français.
5. **Changer les préférences côté serveur** (par exemple effacer le souvenir Plex par fichier). Écartée : on modifierait
   les données d'autres apps, et ce n'est pas possible pour les choix faits ailleurs.

## Impact

- **Fichiers upstream modifiés** : `lib/services/track_selection_service.dart` (2 crochets et 1 import),
  `lib/services/track_manager.dart` (2 lignes et 1 import), `lib/screens/video_player/parts/playback_reload.dart`
  (2 lignes et 1 import). Fichiers régénérés (D6) : `lib/i18n/en.i18n.json`, `lib/i18n/fr.i18n.json`,
  `lib/i18n/strings*.g.dart`. Quelques tests upstream reçoivent `skip: forkChangedSkip`.
- **Nouveaux fichiers** : `lib/fork/preferred_languages.dart`, `lib/fork/track_choice_memory.dart`,
  `test/fork/preferred_languages_test.dart`, `test/fork/preferred_languages_flow_test.dart`,
  `test/fork/track_choice_memory_test.dart`, `test/fork/track_manager_fork_test.dart`. Modifiés côté fork :
  `lib/fork/i18n/en.json`, `lib/fork/i18n/fr.json`, `test/fork/fork_test_utils.dart`.
- **Dépendances ajoutées** : aucune.
- **Risques** :
  - *Transcodage* : quand le serveur transcode, le flux ne contient que la piste audio choisie **avant** l'ouverture.
    Pour Plex, `_resolveAudioStreamId` (`plex_client.dart` l.4001) lit `selected` ; pour Jellyfin,
    `_resolveJellyfinAudioStreamId`. La règle du fork, qui agit sur les pistes disponibles, ne peut alors pas passer à
    l'anglais. La Fire Stick lit en lecture directe en qualité « Originale » (le défaut), mais un fichier refusé par le
    décodeur ou une qualité réduite transcode. Correction possible plus tard : un crochet dans ces deux résolveurs, ce
    qui demande d'y faire parvenir le profil, soit un diff plus profond dans les clients. → Q3.
    *Transcodage avec sous-titres incrustés (Plex)* : `selectSubtitleStreamForBurn` écrit la sélection sur le serveur
    pour incruster la bonne piste, même si « Mémoriser » est désactivé. C'est le comportement upstream, et il n'est pas
    aggravé.
  - *Réglages de langue par série dans Plex* (Plex Web, ou l'écran d'édition de Popkino :
    `plex_metadata_edit_adapter.dart` l.232, `audioLanguage`/`subtitleLanguage`) : PMS les intègre à `selected`. On ne
    peut pas les distinguer du souvenir par fichier, donc la règle du fork les **ignorera**. C'est une régression
    pour qui les utilise. → Q4.
  - *Profil non chargé* : si `activePreferences` vaut `null` au moment de la lecture, la règle ne s'applique pas
    (retour à l'upstream). Au démarrage, `ensureActiveLoaded` est attendu, ce qui rend le cas rare. Hors ligne,
    `waitForProfileSettings` attend 2 s. À surveiller en recette (journal `Audio: … [serverSelected]`).
  - *Jellyfin* : « Choisir l'audio par langue » est l'inverse de `PlayDefaultAudioTrack`, qui vaut vrai par défaut
    côté Jellyfin. Sur un compte Jellyfin neuf, la règle est donc inactive tant que l'utilisateur n'a pas activé
    l'option. C'est conforme à CA8.
  - *Fusions upstream* : `track_selection_service.dart` change souvent. Deux crochets de 2 lignes, insérés juste
    avant les commentaires « Priority 2 », se recasent facilement. Le risque réel vient d'une refonte upstream de
    l'échelle : il faudra alors replacer les crochets à la main, et les tests `test/fork/` le signaleront.
  - *Performances TV* : quelques parcours de listes de pistes et une lecture en cache mémoire. Négligeable.
  - *Google Play, marque* : aucun impact.

## Décisions durables proposées (à ajouter à `decisions.md` si le plan est approuvé)

- **D11 — Changer un comportement upstream par un crochet `null = upstream`** : la logique du fork vit dans
  `lib/fork/` en fonctions pures. Le fichier upstream ne contient qu'un appel marqué `// FORK:` qui renvoie `null`
  pour laisser l'upstream décider. Pas de nouvelle valeur dans les enums upstream.
- **Extension de D4** : un test upstream dont le comportement est volontairement changé par le fork reçoit
  `skip: forkChangedSkip` (même mécanisme que `forkRemovedSkip`). Le comportement du fork est testé dans `test/fork/`.
- **Extension de D6** : la surcouche `lib/fork/i18n/<locale>.json` peut **surcharger une clé upstream existante**
  (pas seulement ajouter des clés `fork.*`) quand seul le texte change. Il faut le noter dans `rebrand_rules.json`
  (`_comment`) ou dans le README des traductions, pour repérer ces surcharges à la fusion.

## Ajouts proposés au skill `conventions-code`

- Sélection des pistes : `TrackSelectionService` est l'unique échelle de décision. Elle est appelée avant l'ouverture
  par `PlaybackSubtitleResolver.resolve`, dont le choix de sous-titres est ensuite **transmis comme préférence de
  priorité `navigation`**, puis par `TrackManager` et par l'aperçu de la fiche (`previewPlaybackTracks`). Une
  modification de l'échelle s'applique donc partout.
- Seuls les choix de priorité `navigation` sont écrits sur le serveur. Les choix automatiques ne le sont pas (#2323).
- Lecture synchrone d'un réglage dans de la logique pure : `SettingsService.instanceOrNull` (null dans les tests qui
  n'initialisent rien), pas `SettingsService.instance`, qui lève une erreur.
- Petit stockage local indexé par contenu : `JsonPref<Map<String, dynamic>>` avec entrées datées et plafond
  (modèle : `ScopedPlayerPrefs`), clé `buildGlobalKey(serverId, id)`.
- Shell (zsh) : mettre entre guillemets les motifs de `grep --include='*.dart'`, sinon zsh les développe et la
  commande échoue (« no matches found »).

## QUESTIONS PRODUIT

- **Q1 — Sous-titres forcés quand l'audio est déjà en français.** Certains fichiers ont une piste française
  « forcée », qui ne s'affiche que sur les passages dans une autre langue (panneaux, dialogues étrangers). Faut-il
  l'afficher quand l'audio est en français (comportement des modes « avec audio étranger » de Plex et Jellyfin), ou
  n'afficher aucun sous-titre, comme le dit CA6 à la lettre ? Recommandation : afficher la piste forcée si elle
  existe (CA6 deviendrait « aucun sous-titre complet »).
- **Q2 — Un choix porté à l'épisode suivant compte-t-il comme un choix manuel ?** Exemple : l'utilisateur passe
  l'épisode 1 en français, l'épisode 2 enchaîne en français (CA5), il quitte puis relance l'épisode 2. Avec la
  proposition, l'épisode 2 redémarre en anglais : seul l'épisode 1 a été changé à la main. Est-ce le comportement
  attendu ?
- **Q3 — Lecture transcodée.** Quand le serveur transcode (qualité réduite choisie, ou format que la TV ne lit pas),
  la langue préférée ne pourra pas être imposée dans cette version : la piste retenue par le serveur sera jouée.
  Acceptable pour cette version (Must couvert en lecture directe), ou à inclure tout de suite, avec un changement plus
  profond dans les clients Plex et Jellyfin ?
- **Q4 — Réglages de langue par série dans Plex.** Si une série a sa propre langue réglée dans Plex (par exemple un
  anime réglé en japonais), la langue du compte passera désormais avant. Acceptable (la spec écarte les réglages par
  série), ou faut-il respecter ces réglages, ce qui coûte une requête de plus au lancement, pour Plex seulement ?
