# Proposition plateforme — langues-preferees

Auteur : architecte-plateforme · 2026-11-26 · Phase 1 (rédigée sans lire la proposition app)
Spec : `docs/produit/specs/langues-preferees.md`

## Compréhension de la spec

Au lancement d'un film ou d'un épisode, la langue audio et la langue de sous-titres du compte serveur (Plex ou
Jellyfin) doivent passer **avant** le souvenir que le serveur garde par fichier, sauf si l'utilisateur a activé
« Mémoriser les pistes choisies ». Un choix fait à la main n'est gardé que dans ce cas. Le texte de l'option
« Choisir l'audio par langue » est corrigé.

Critères qui touchent mon périmètre :
- **CA1, CA3** : ils doivent aussi tenir quand la lecture est **transcodée**. Dans ce cas, le serveur n'envoie qu'une
  seule piste audio et le lecteur natif ne peut plus en changer (voir Existant §3).
- **CA4 / CA4bis** : ce qui est écrit sur le serveur, quand, et ce que les autres apps du compte en voient.
- **CA10** : un serveur injoignable ou qui refuse l'écriture ne doit bloquer ni la lecture ni le changement de piste.
- **CA11** et toute la recette : à faire sur la Fire Stick (Android 11, 32 bits) avec mpv, le moteur Android par défaut.
- Contrainte `regles-fork` §5 : diff minimal dans des fichiers upstream qui changent souvent.

## Existant

### 1. Lecteur natif : qui choisit la piste, et quand

- Sur Android, le moteur par défaut est **mpv** (`PlayerNative`, `lib/mpv/player/player_native.dart`). ExoPlayer ne
  sert que de secours, choisi par l'utilisateur (`SettingsService.useExoPlayer`, `settings_service.dart:858-866`).
  Les deux passent par la même logique Dart. Côté natif, il n'y a **aucune** logique de langue : ni dans
  `MpvPlayerCore.kt` ni dans `ExoPlayerCore.kt` (pas de `alang` ni de `slang`, aucune préférence de langue dans
  ExoPlayer). Le natif ne fait qu'appliquer un `aid` / `sid` envoyé depuis Dart.
- Le fichier est ouvert par `loadfile <uri> replace -1 <options>`, avec `sid=no,secondary-sid=no` passés pour ce fichier
  seulement (`player_native.dart:517-552`). Aucun `aid` n'est passé : au démarrage, mpv joue sa piste automatique
  (piste marquée par défaut dans le fichier, sinon la première).
- La sélection n'arrive qu'**après l'ouverture** : `playback_open.dart:1192` appelle
  `TrackManager.applyTrackSelectionWhenReady()`, qui attend la liste des pistes de mpv (filet de 5 s, puis 25 s pour
  les sous-titres annoncés), puis `TrackSelectionService.selectAndApplyTracks()`. Ce dernier envoie
  `setProperty('aid', id)` (`player_native.dart:820-828`).
- Conséquence déjà présente dans l'upstream : quand la piste retenue n'est pas celle que mpv a prise d'office, on peut
  entendre l'autre langue un court instant au démarrage. Le basculement d'`aid` en lecture directe provoque aussi une
  relecture courte pour la nouvelle piste (le cache de démultiplexage ne garde que les pistes actives ; son budget
  dépend de la RAM, cf. `DemuxerBudget.kt`). Ce coût existe déjà chaque fois que la piste retenue par le serveur
  diffère de la piste par défaut du fichier. La fonctionnalité ne l'ajoute pas, elle change seulement la piste visée.

### 2. Ordre de sélection actuel

`lib/services/track_selection_service.dart` :
- `TrackSelectionPriority` (l.671) : `navigation > serverSelected > profile > defaultTrack > off`.
- `selectAudioTrack` (l.939) : la piste du serveur (`selected` côté Plex, `DefaultAudioStreamIndex` côté Jellyfin)
  gagne dès qu'elle correspond à une piste mpv (l.973-1011). Le profil (l.1014) n'est consulté que si cette
  correspondance échoue, ce qui n'arrive presque jamais sur Plex : PMS marque toujours une piste `selected`.
- `selectSubtitleTrack` : sur Plex, `_selectSubtitleTrackByProfile` renvoie `null` (l.788). C'est un choix explicite de
  l'upstream (commit `51beb5ac4`, « leave Plex subtitle auto-selection to the server »). Tout vient donc de `selected`.
- Le même ordre sert à l'aperçu des pistes avant lecture (`lib/services/playback_track_preview.dart:46`). Corriger
  l'ordre corrige donc l'aperçu en même temps.

### 3. Transcodage : la piste audio est choisie à l'ouverture, côté serveur

- Plex : `plex_client.dart:3841` → `_resolveAudioStreamId` (l.4001) prend la piste `selected` du serveur, qui part en
  `audioStreamID` dans la requête de transcodage (l.3198).
- Jellyfin : `jellyfin_client/parts/playback.dart:404` → `_resolveJellyfinAudioStreamId` (l.578) prend
  `DefaultAudioStreamIndex`, puis `selected`.
- Une préférence audio « sémantique » (langue, titre, codec) existe déjà : `PlaybackInitializationOptions.preferredAudioTrack`
  (`playback_initialization_types.dart:46-51`), résolue par `findSourceAudioTrackForIntent`
  (`track_selection_service.dart:397`) avant l'ouverture (Plex l.3800-3803, Jellyfin l.298), puis par
  `findNativeAudioTrackForIntent` (l.411) après l'ouverture. Elle sert aujourd'hui à garder la piste d'un épisode au
  suivant (CA5).
- En transcodage, la feuille des pistes passe par `onSwitchAudioStreamId` → `_switchVersionAndQuality` → rechargement
  (`track_sheet.dart:42-46`, `playback_reload.dart:186-208`).

**Conséquence** : modifier seulement `selectAudioTrack` ne suffit pas. En transcodage, mpv ne reçoit qu'une piste, celle
que le serveur a déjà choisie (le français dans le cas de la spec). `findAudioTrackByProfile` ne trouvera jamais
l'anglais et CA1 échouera dès que la lecture est transcodée : qualité différente d'« Original », codec refusé,
repli `forceTranscode`, sous-titres image incrustés.

### 4. Écritures vers le serveur (effets de bord)

| Chemin | Écrit quoi | Condition | Fichier |
|---|---|---|---|
| Choix manuel en lecture directe (Plex) | `PUT /library/parts/{partId}?audioStreamID=` ou `subtitleStreamID=` | `rememberTrackSelections` activé | `track_manager.dart:484-609` (`_guardTrackChange` l.545), `video_player_screen.dart:455-459` |
| Choix manuel en transcodage (Plex) | même `PUT`, **avant** le rechargement | idem | `playback_reload.dart:186-208` |
| Sous-titre incrusté en transcodage (Plex) | `PUT /library/parts/{partId}?subtitleStreamID=` | **toujours**, même si l'option est désactivée | `plex_client.dart:2930, 2995-3004` (`selectSubtitleStreamForBurn`) |
| Jellyfin | index de pistes dans les rapports de progression + passage à `true` des drapeaux **du compte** `RememberAudioSelections` / `RememberSubtitleSelections` | `rememberTrackSelections` activé | `playback_progress_tracker.dart:777-792`, `track_manager.dart:35`, `media_browser_dialect.dart:218-230` |

Points à retenir :
- Le souvenir Plex est attaché au **fichier (part) sur le serveur**. Toutes les apps Plex du même compte le lisent,
  et c'est justement ce qui cause le bug : un épisode lancé en français ailleurs revient en français dans Popkino.
  À vérifier sur le serveur de test : ce souvenir est-il propre à chaque utilisateur du serveur ou partagé entre eux ?
  La documentation publique de PMS ne le dit pas.
- `SettingsService.rememberTrackSelections` vaut **`true` par défaut** (`settings_service.dart:702`). Sur une
  installation neuve, Popkino écrit donc vers le serveur et, sur Jellyfin, active la mémoire **du compte** pour tous
  ses clients.
- Avec l'option désactivée, Popkino n'écrit rien. Seule exception : l'incrustation de sous-titres en transcodage Plex,
  qui écrit quand même.
- Chez Plex, une série peut aussi avoir sa propre langue audio ou de sous-titres (`audioLanguage`, modifiable dans
  Popkino via `lib/metadata_edit/plex_metadata_edit_adapter.dart:232, 337`). PMS l'intègre au même `selected`. Vu du
  client, rien ne distingue « souvenir du fichier », « réglage de la série » et « préférence du compte ».

### 5. Serveur injoignable (CA10)

- Lecture directe, choix manuel : `player.selectAudioTrack` est appelé **avant** l'écriture, qui tourne en
  arrière-plan (`track_manager.dart:427-429`, `unawaited`). Un échec réseau n'est que journalisé
  (`_handleServerSyncFailure`, l.616-626). Un refus du serveur affiche une seule fois un snackbar non bloquant
  (`trackSelectionNotRemembered`). CA10 tient déjà.
- Transcodage Plex avec l'option activée : le `PUT` est fait **avant** le rechargement. S'il échoue ou s'il est refusé,
  on obtient `streamSelectionFailed`, un snackbar d'erreur, et **la piste n'est pas changée**
  (`playback_reload.dart:200-206`). Si le serveur est vraiment injoignable, le rechargement du transcodage échouerait de
  toute façon. En revanche, un serveur joignable qui refuse l'écriture (droits d'un utilisateur partagé, erreur 4xx)
  bloque à tort le changement de piste. C'est un défaut upstream que la fonctionnalité ne crée pas, mais que la
  recette de CA10 peut faire apparaître.
- Le changement de piste suppose de toute façon que le serveur réponde : en lecture directe, mpv doit relire le flux
  pour la nouvelle piste. Si le serveur est coupé, la lecture s'arrête, quelle que soit la logique de l'app. On ne peut
  donc vérifier CA10 de bout en bout que pour « l'écriture échoue », pas pour « le serveur est éteint ».

### 6. Fusions avec l'upstream

`git log` sur la branche : `track_selection_service.dart` a reçu 13 commits upstream entre fin juillet et fin
septembre 2026. `track_manager.dart` et `plex_client.dart` changent aussi beaucoup. La philosophie upstream est
« faire confiance au serveur » (commits `42b6710f0` et `51beb5ac4`), et le mainteneur a refusé ce changement
(#1993, #1615). Notre écart sera donc **permanent** : aucune PR upstream n'a de chance d'être acceptée.

## Approche proposée

Le pilote est l'architecte-app, qui choisira le mécanisme Dart. Voici les contraintes plateforme et la forme que je
recommande.

### P1 — Aucun changement natif, aucun changement Android

Ni Kotlin, ni C++, ni manifeste, ni Gradle, ni workflow. La décision reste en Dart, là où elle est déjà prise, et
s'applique pareil à mpv et à ExoPlayer. Rien ne change pour Google Play : pas de permission, pas de nouvelle
dépendance, aucune donnée nouvelle à déclarer dans le formulaire « Sécurité des données ». La version GitHub et la
version Play gardent le même comportement (D7).

### P2 — Une seule règle, appliquée avant l'ouverture et après

La règle « préférence du compte avant souvenir du serveur » doit agir aux **deux** moments où la piste est décidée :
1. **avant l'ouverture**, pour le transcodage (Plex `audioStreamID`, Jellyfin `AudioStreamIndex`) ;
2. **après l'ouverture**, pour la sélection mpv (`selectAudioTrack`) et pour l'aperçu (`playback_track_preview.dart`).

Forme recommandée, qui réutilise l'existant : quand aucune piste n'est reportée de l'épisode précédent
(`preferredAudioTrack == null`), que « Mémoriser » est désactivé, que `autoSelectAudio` est activé et qu'une langue
audio est réglée, le lanceur fournit une **intention de langue** sous forme d'`AudioTrack` neutre
(`id: carriedAudioTrackId`, `language: <langue du compte>`). Ce mécanisme sert déjà au report d'un épisode à
l'autre. Avantages :
- avant l'ouverture, Plex (`plex_client.dart:3800`) et Jellyfin (`playback.dart:298`) savent déjà la résoudre en
  piste source pour le transcodage, sans toucher aux clients ;
- après l'ouverture, `selectAudioTrack` la prend en priorité 1 via `findNativeAudioTrackForIntent`, sans modifier
  l'ordre upstream `TrackSelectionPriority` ;
- si le fichier n'a pas cette langue, l'intention est refusée (l.974) et l'ordre upstream reprend (CA6, CA8) ;
- avec « Mémoriser » activé, on ne crée pas d'intention : le souvenir du serveur gagne (CA4bis), comme chez l'upstream ;
- elle n'écrit rien : la priorité `navigation` appelle `onAudioTrackChanged`, mais `_guardTrackChange` s'arrête dès
  que « Mémoriser » est désactivé (l.546).

Le code qui fabrique l'intention vit dans un **nouveau fichier `lib/fork/`** (D2), testé dans `test/fork/`. Côté
upstream, il ne reste qu'un appel marqué `// FORK:` à l'endroit où `_preferredAudioTrack` est fixé au lancement
(`playback_start.dart` ou équivalent, au choix de l'architecte-app).

**À vérifier par l'architecte-app** : une intention de priorité `navigation` qui n'a pas été choisie à la main ne
doit pas être reportée comme un choix manuel à l'épisode suivant. CA5 ne vaut que pour un choix fait à la main. Si le
report s'appuie sur `player.state.track.audio`, il reportera l'anglais, ce qui est sans effet visible ici mais à
confirmer.

Pour les **sous-titres**, l'architecte-app arbitre le mécanisme (CA6 demande de les couper quand l'audio est en
français, alors que le compte dit « Toujours activé »). Côté plateforme, deux exigences :
- le choix doit lui aussi être connu **avant l'ouverture**, car `_resolveTranscodeSubtitleTrack` décide ce qui est
  incrusté ;
- tout choix qui conduit à une **incrustation** en transcodage Plex déclenche un `PUT` vers le serveur, même avec
  « Mémoriser » désactivé (`selectSubtitleStreamForBurn`). Je propose de l'accepter : c'est indispensable pour que PMS
  incruste la bonne piste, et ce n'est fréquent qu'avec des sous-titres image en transcodage. Il faut en revanche le
  documenter dans `plan.md` comme effet de bord connu.

### P3 — Pas de nouvel appel réseau au lancement

La règle doit utiliser le profil déjà chargé (`getProfileSettings` / `waitForProfileSettings` du `TrackManager`, ou
`AccountPreferencesController`). Pas de nouvel appel réseau au démarrage de la lecture : sur une Fire Stick en Wi-Fi,
chaque aller-retour supplémentaire retarde le démarrage. Je considérerais comme **bloquante** une solution qui lirait
les réglages de la série chez PMS (`/library/metadata/{id}/prefs`) à chaque lancement, sauf si elle est mise en cache.

### P4 — Coût sur Fire Stick 32 bits

C'est une comparaison de langues sur quelques pistes, en Dart compilé (ARMv7) : négligeable. Pas de mémoire ajoutée
côté natif, et le budget du cache mpv ne change pas. Il y a au plus **un** changement d'`aid` au démarrage, comme
aujourd'hui. En transcodage, on économise même un rechargement : la bonne piste est demandée dès l'ouverture, alors
qu'aujourd'hui l'utilisateur doit en relancer un à la main.

### P5 — CA10 : ne rien ajouter, prouver par les tests

Aucune nouvelle écriture n'est créée. CA10 repose sur l'existant (§5), qu'il faut **verrouiller par des tests** dans
`test/fork/` : un faux `TrackPreferencePersister` qui lève une `MediaServerHttpException` (erreur temporaire, puis
refus 4xx) ne doit empêcher ni le changement de piste ni la lecture. Je mets hors du périmètre la correction du défaut
« refus 4xx en transcodage avec Mémoriser activé » (`playback_reload.dart:200-206`), qui touche un fichier upstream
sensible. Je propose de l'ajouter au backlog.

### P6 — Recette sur la TV (adb)

```bash
# Fire Stick Android 11 32 bits : ABI armeabi-v7a
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true \
  --dart-define-from-file=popkino_secrets.json
adb connect <ip-firestick>:5555
adb install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

- Activer Paramètres > « Journaux de débogage » (`enableDebugLogging`, qui agit aussi en release), puis suivre la
  décision en direct :
  `adb logcat -v time -s flutter | grep -E "Audio:|Subtitle:|carry declined|stream selection"`.
  Chaque décision s'affiche avec sa priorité, par exemple `Audio: English [navigation]` ou `[serverSelected]`. Le
  plan doit garder ces lignes, et l'intention de langue doit être reconnaissable dans le journal, par exemple via un
  `appLogger.d` dans `lib/fork/`.
- Écart audio au démarrage : comparer l'heure de la ligne `Audio:` à celle du premier `playback-restart` de mpv dans
  `adb logcat` pour mesurer combien de temps la mauvaise langue est audible.
- **Vérifier côté serveur qu'aucune écriture n'a eu lieu** (CA4) : relever la piste `selected` avant et après la
  recette.
  - Plex : `curl -s "http://<pms>:32400/library/metadata/<ratingKey>?X-Plex-Token=<token>" | grep -E 'streamType="2"'`
    (le `selected="1"` ne doit pas bouger avec « Mémoriser » désactivé).
  - Jellyfin : `GET /Items/<id>/PlaybackInfo?UserId=<uid>` → `DefaultAudioStreamIndex`, et `GET /Users/<uid>` →
    `Configuration.RememberAudioSelections`.
- Préparer le fichier de test de la spec (souvenir serveur = français) : lancer l'épisode en français dans Plex Web,
  ou poser le souvenir directement avec `curl -X PUT "http://<pms>:32400/library/parts/<partId>?audioStreamID=<id fr>&X-Plex-Token=<token>"`.
- Couvrir **deux modes** pour CA1/CA3 : lecture directe (qualité Original) **et** transcodage forcé (qualité 720p dans
  le menu du lecteur). Le second est celui qui échouerait avec une correction limitée à `selectAudioTrack`.
- Option ExoPlayer : refaire CA1 une fois avec « Utiliser ExoPlayer » pour vérifier que les deux moteurs se comportent
  pareil (même chemin Dart, test rapide).

### P7 — Fusions

- Aucun fichier natif ni de build n'est touché.
- Côté Dart upstream : un seul appel marqué `// FORK:` au point de lancement. Si l'architecte-app touche
  `track_selection_service.dart`, je demande que ce soit **un seul appel par fonction** vers `lib/fork/`, pas une
  modification de l'ordre de sélection : c'est le fichier le plus remanié par l'upstream.
- Les tests upstream existants (`test/services/track_selection_service_test.dart`, 16 vérifications de
  `serverSelected`) ne doivent pas être modifiés. L'approche par intention les laisse intacts : ils ne passent ni
  profil, ni intention, ni réglage « Mémoriser ».
- Texte de CA9 : passer par la surcouche `lib/fork/i18n/` et `scripts/fork/rebrand_i18n.py` (D6), jamais par une
  édition directe de `lib/i18n/fr.i18n.json` (clé `autoSelectAudioDescription`, l.1136).

## Alternatives écartées

1. **Passer `alang=` ou `aid=` à mpv dans les options de `loadfile`** (comme `sid=no`) pour que mpv démarre directement
   sur la bonne langue. Écartée pour l'instant :
   - elle modifie `player_native.dart`, upstream et sensible, ainsi que le contrat d'ouverture ;
   - la correspondance des langues de mpv diffère de `languageMatches` (variantes ISO 639), ce qui peut provoquer deux
     changements de piste ;
   - elle ne couvre ni ExoPlayer ni le transcodage ;
   - le gain se limite au court passage par la mauvaise langue au démarrage, qui existe déjà aujourd'hui.

   À reconsidérer seulement si la mesure de P6 montre une gêne réelle.
2. **Inverser `serverSelected` et `profile` dans `TrackSelectionPriority`**. Écartée : le changement ne vaut qu'après
   l'ouverture (CA1 échoue en transcodage, §3) ; il touche le cœur d'un fichier très remanié ; il casse des tests
   upstream ; il change le comportement pour qui a activé « Mémoriser ».
3. **Effacer le souvenir sur le serveur** (`PUT /library/parts` vers la piste du profil à chaque lancement). Écartée :
   on écrirait vers le serveur alors que l'utilisateur a désactivé « Mémoriser », et on modifierait ce que voient les
   autres apps du compte (Plex Web, l'app Plex TV), donc l'inverse de CA4.
4. **Mémoire locale des choix par fichier** (table drift sur la TV) pour CA4bis. Écartée par défaut : nouveau stockage
   et nouvelle migration, et la mémoire ne serait pas partagée entre appareils. À ne rouvrir que si le PO répond « non »
   à la question produit 1.
5. **Recalculer le choix du serveur** à partir des réglages de la série (`/library/metadata/{id}/prefs`). Écartée :
   un appel réseau de plus à chaque lancement (P3), Plex uniquement, pour un cas que la spec exclut du périmètre.

## Impact

- **Fichiers upstream modifiés** : aucun fichier Android, natif, Gradle ou CI. Côté Dart, pour l'architecte-app : un
  appel marqué `// FORK:` au point de lancement de la lecture, plus un éventuel appel par fonction de sélection des
  sous-titres. Rien dans `plex_client.dart` ni `jellyfin_client/` si l'intention passe par `preferredAudioTrack`.
- **Nouveaux fichiers** : `lib/fork/<règle de langue>.dart`, `test/fork/<règle>_test.dart` (dont CA10 avec un faux
  persister qui échoue), et la surcouche `lib/fork/i18n/` pour CA9.
- **Dépendances ajoutées** : aucune.
- **Google Play** : aucun impact (ni permission, ni SDK, ni donnée collectée, ni téléchargement de code). Rien à
  ajouter au formulaire « Sécurité des données ».
- **Marque** : aucun impact.
- **Performances TV** : négligeables (P4). En transcodage, un rechargement manuel en moins.
- **Risques** :
  - *Réglage de langue par série chez Plex ignoré* quand « Mémoriser » est désactivé (§4) : régression possible pour
    qui l'utilise (question produit 2).
  - *Valeur par défaut de « Mémoriser » = activé* : sur une installation neuve, la règle ne s'applique pas et le
    souvenir du serveur continue de gagner. C'est le bug de départ pour tout nouvel utilisateur du Play Store
    (question produit 3).
  - *Écritures déjà présentes* : incrustation en transcodage Plex (toujours), et drapeaux du compte Jellyfin
    (avec « Mémoriser » activé). Il faut les documenter, pas les corriger ici.
  - *Fusions* : écart permanent avec la philosophie upstream. On le limite en mettant le code dans `lib/fork/` et en
    ne gardant qu'un seul appel marqué `// FORK:`. À relire à chaque fusion de `track_selection_service.dart`,
    `playback_start.dart` et `playback_open.dart`.
  - *CA10 en transcodage* : un refus 4xx du serveur bloque le changement de piste quand « Mémoriser » est activé (défaut
    upstream, §5). Hors périmètre, à ajouter au backlog.

## QUESTIONS PRODUIT

1. **« Mémoriser » activé et choix faits dans une autre app Plex** : si l'utilisateur active « Mémoriser » et qu'un
   épisode a été lancé en français depuis Plex Web, faut-il démarrer en français, ce qui suit le souvenir du serveur,
   partagé par toutes les apps du compte ? Ou en anglais, ce qui ne retiendrait que les choix faits dans Popkino, sur
   cette TV, et suppose une mémoire locale ? La dernière phrase de CA4bis penche pour la seconde réponse ; la solution
   simple donne la première.
2. **Langue réglée sur une série dans Plex** (par exemple « audio japonais » pour un anime, réglé dans Plex ou dans
   Popkino via « Modifier ») : quand « Mémoriser » est désactivé, ce réglage de série doit-il gagner sur la langue du
   compte ? Si oui, il faut un appel réseau de plus au lancement, ou un cache. Si non, ce réglage n'aura plus d'effet
   dans Popkino.
3. **Valeur par défaut de « Mémoriser les pistes choisies »** : l'upstream l'active d'office. Avec cette valeur, un
   nouvel utilisateur garde le comportement actuel (le souvenir du serveur gagne) et Popkino écrit ses choix sur le
   serveur. Faut-il la désactiver par défaut dans Popkino ?
