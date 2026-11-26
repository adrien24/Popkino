# Débat — langues-preferees

## Critique de app sur la proposition plateforme — tour 1

- ✅ D'accord :
  - **P1** : aucun changement natif, Gradle, CI ni manifeste, et aucun impact Google Play.
  - **P3** : pas de nouvel appel réseau au lancement. Je retire en conséquence l'option « requête des réglages de
    série » de ma Q4.
  - **P4** : le coût sur la TV est négligeable.
  - **P5** : CA10 se verrouille par des tests avec un faux `TrackPreferencePersister` qui lève une erreur (temporaire,
    puis refus 4xx). Le défaut upstream « refus 4xx en transcodage bloque le changement de piste »
    (`playback_reload.dart` l.200-206) va au backlog.
  - **P6** : recette par `adb logcat`, avec relevé de `selected` / `DefaultAudioStreamIndex` côté serveur avant et après.
    La décision du fork doit apparaître dans le journal : `appLogger.d` dans `lib/fork/`, avec un libellé reconnaissable.
  - **P7** : un seul appel `// FORK:` par fonction de sélection. C'est exactement la forme de ma proposition.
  - **CA9** : le texte passe par la surcouche `lib/fork/i18n/`, conformément à D6.
  - **Incrustation Plex** : le `PUT` de `selectSubtitleStreamForBurn` est accepté et documenté comme effet de bord
    connu.
  - **Correction de mon analyse** : le transcodage doit être traité dès cette version et pas renvoyé en question
    produit. Pour l'audio, `PlaybackInitializationOptions.preferredAudioTrack`, résolu par
    `findSourceAudioTrackForIntent` dans `plex_client.dart` l.3800-3803 et `jellyfin_client/parts/playback.dart`
    l.295-299, est le bon point d'entrée **avant ouverture**, sans toucher aux clients.

- ❌ Bloquant : l'intention de langue comme **unique** mécanisme (priorité 1 `navigation`) fait échouer CA1 sur des
  fichiers courants.
  - **Fait vérifiable.** `_findTrackByEvidenceBands` (`track_selection_service.dart` l.446-492) renvoie `null` dès que
    deux candidats sont à égalité (`if (bestIsAmbiguous) return null;`). Une intention qui ne contient qu'une langue
    (`id: carriedAudioTrackId`, titre, codec et canaux vides) donne la même clé à toutes les pistes anglaises : 1 pour
    la langue, 1 pour le titre (`_titleScore(null, …) == 1`), 0 pour le codec, 0 pour les canaux.
  - **Conséquence.** Un fichier « anglais TrueHD 7.1 + anglais AC3 5.1 + français » (cas typique d'un remux Blu-ray),
    ou « anglais + commentaire anglais + français », fait refuser l'intention avant l'ouverture
    (`findSourceAudioTrackForIntent`) et après (`findNativeAudioTrackForIntent`). L'échelle upstream reprend alors la
    piste du serveur, c'est-à-dire le français.
  - **Alternative.** Garder mes deux crochets dans `TrackSelectionService` (après la priorité 1, voir
    `proposition-app.md`). Ils choisissent la piste `isDefault` parmi les pistes anglaises, à défaut la première, et ne
    font rien quand le serveur a déjà choisi une piste anglaise. Ils couvrent la lecture directe, l'aperçu de la fiche
    et le resolver.

- ❌ Bloquant : l'intention n'est créée que si « Mémoriser » est désactivé, alors que c'est activé par défaut
  (`settings_service.dart` l.702).
  - **Conséquence.** Sur une installation neuve, comme dans le cas de la spec avec l'option activée, la correction ne
    s'applique pas. Un épisode lancé en français dans Plex Web revient en français, ce qui contredit CA4bis : « Les
    autres épisodes qu'il n'a pas modifiés à la main démarrent toujours en anglais ».
  - **Alternative.** La règle s'applique quel que soit le réglage. Elle ne s'efface que pour les contenus que
    l'utilisateur a modifiés à la main dans Popkino, quand « Mémoriser » est activé : c'est l'indicateur local
    `ForkTrackChoiceMemory`.
  - **Ce n'est pas la table drift** que tu écartes en alternative 4. C'est un `JsonPref` d'indicateurs horodatés, avec
    plafond (modèle `ScopedPlayerPrefs`) : pas de migration, pas de copie de la piste, le serveur reste la mémoire de
    la piste.

- ⚠️ À amender : ne pas transmettre l'intention au `TrackManager` → n'alimenter **que**
  `PlaybackInitializationOptions.preferredAudioTrack`, aux deux appels de `playback_start.dart` (l.~194 hors ligne et
  son équivalent en ligne), via un appel marqué `// FORK:` à `forkLaunchAudioIntent(item, profile)` dans
  `lib/fork/preferred_languages.dart`.
  - **Pourquoi.** Laisser `_preferredAudioTrack`, transmis au resolver (l.236) et au `TrackManager` (l.294), à `null`
    évite une priorité `navigation` artificielle. Une telle priorité, avec « Mémoriser » activé, écrirait sur le
    serveur à chaque lancement (`selectAndApplyTracks` l.1232). Ta réserve sur le report à l'épisode suivant disparaît
    aussi : seul `_sessionAudioPreference`, qui n'est rempli que par un choix manuel, est reporté.
  - **Combinaison obtenue.** Avant l'ouverture, l'intention fait demander l'anglais au transcodeur quand le choix est
    sans ambiguïté. Après l'ouverture, les crochets du service décident en lecture directe dans tous les cas.
  - **Reste ouvert, sans être bloquant.** Un transcodage d'un fichier qui a plusieurs pistes anglaises garde le choix
    du serveur. C'est un risque à noter dans `plan.md`.

- ⚠️ À amender : les sous-titres en transcodage → à vérifier dans le plan, avant de coder.
  - `_resolveTranscodeSubtitleTrack(info, options.preferredSubtitleTrack)` (`plex_client.dart` l.4022) décide de
    l'incrustation à partir de `selected` quand aucune préférence n'est passée.
  - Le resolver (`PlaybackSubtitleResolver.resolve`, avec mes crochets) tourne **après** cette décision.
  - Je vérifie dans le plan comment le flux d'ouverture concilie les deux (`primarySubtitleIsServerRendered`,
    `burnRequiresRenegotiation`). Si ce n'est pas sûr, on pose comme règle : en transcodage, la règle du fork ne choisit
    que l'audio, et le sous-titre suit l'upstream.

- ⚠️ À amender : ta P7 demande que les tests upstream ne soient pas modifiés → d'accord comme objectif.
  - Mes crochets ne s'activent que s'il y a un profil **et** que le choix du serveur contredit la préférence.
  - Or la plupart des 16 vérifications `serverSelected` n'utilisent pas de profil (`_svc(info: info)`). Le nombre de
    tests à marquer `skip: forkChangedSkip` devrait donc être nul ou très faible.
  - On le mesure à T2 (suite complète), et on documente chaque test marqué dans le plan.

### Questions produit restantes (fusion app + plateforme, sans doublon)

Ne sont plus ouvertes :
- **Ma Q3 (transcodage)** : traité, voir l'amendement ci-dessus.
- **Ta Q1 (« Mémoriser » activé et choix faits dans Plex Web)** : la dernière phrase de CA4bis y répond déjà. Seuls les
  choix faits à la main dans Popkino sont repris, grâce à l'indicateur local.
- **Ta Q3 (valeur par défaut de « Mémoriser »)** : la correction marche avec les deux valeurs. Désactiver l'option par
  défaut reste possible, mais ce n'est plus nécessaire pour cette fonctionnalité. C'est à ajouter au backlog si le PO
  le souhaite.

Restent ouvertes :
1. **Sous-titres forcés avec audio français** (ma Q1). Faut-il afficher la piste française « forcée » (passages en
   langue étrangère) quand l'audio est en français ? Ou n'afficher aucun sous-titre, comme le dit CA6 à la lettre ?
   Recommandation : l'afficher.
2. **Choix reporté à l'épisode suivant** (ma Q2). Un choix reporté automatiquement à l'épisode suivant (CA5)
   compte-t-il comme un choix manuel sur cet épisode, et doit-il être repris à son prochain lancement si « Mémoriser »
   est activé ? Proposition : non, seul l'épisode modifié à la main est concerné.
3. **Langue réglée sur une série dans Plex** (ma Q4 et ta Q2, fusionnées). Le réglage de la série sera ignoré, et la
   langue du compte gagnera. Est-ce acceptable ? La spec écarte les réglages par série. Le respecter coûterait un appel
   réseau au lancement, ou un cache, que la plateforme juge bloquant sans cache.

## Critique de plateforme sur la proposition app — tour 1

- ✅ D'accord :
  - **J'accepte tes deux ❌ sur ma proposition.**
    - L'ambiguïté est vérifiée : `_findTrackByEvidenceBands` renvoie `null` à l'égalité (`track_selection_service.dart`
      l.490). Une intention qui ne contient qu'une langue échoue donc sur un remux « anglais TrueHD + anglais AC3 ».
    - « Mémoriser » est activé par défaut (`settings_service.dart` l.702), donc l'intention n'aurait jamais été créée sur
      une installation neuve.
    - Je retire ma P2 comme mécanisme unique, ainsi que ma Q1 et ma Q3.
  - **Tes crochets** : fonctions pures dans `lib/fork/`, `null` = comportement upstream, placés après la priorité 1,
    sans nouvelle valeur d'enum. C'est la forme la plus facile à fusionner. Je soutiens D11 et les extensions de D4
    (`forkChangedSkip`) et de D6 (surcharge d'une clé upstream).
  - **A2 (ne rien faire si le serveur a déjà choisi la bonne langue)** : c'est ce qui rend la règle inerte pour la
    majorité des fichiers. Cela limite aussi le nombre de tests upstream concernés.
  - **`ForkTrackChoiceMemory` en `JsonPref`** (`SharedPreferencesWithCache`) : environ 500 entrées, soit quelques
    dizaines de Ko chargés au démarrage, ce qui reste négligeable sur la Fire Stick. Les données restent sur l'appareil :
    pas de nouvelle catégorie dans le formulaire « Sécurité des données ». L'Auto Backup d'Android est actif par défaut
    (pas d'`allowBackup` dans le manifeste) ; il traite ces données comme les autres réglages, sans rien de nouveau.
  - **Ton amendement** : l'intention n'alimente **que** `PlaybackInitializationOptions.preferredAudioTrack` (avant
    ouverture), et les crochets décident après. J'ai vérifié que les deux restent cohérents :
    - Jellyfin : `_withSelectedJellyfinAudioStream` (`playback.dart` l.405) marque la piste demandée comme `selected`
      dans le `mediaInfo` renvoyé. Ton A2 voit donc « serveur = anglais » et laisse faire l'upstream ;
    - Plex : `selected` reste français dans `mediaInfo`, mais le crochet choisit la même piste anglaise que celle demandée
      au transcodeur. Le resolver calcule alors les sous-titres pour l'audio réellement envoyé.

- ⚠️ À amender : en transcodage, si le fichier a **plusieurs pistes anglaises**, l'audio envoyé et l'audio supposé ne
  sont plus les mêmes.
  - **Ce qui se passe.** L'intention est refusée avant l'ouverture, donc le transcodeur reçoit le français
    (`_resolveAudioStreamId`, `plex_client.dart` l.4001). Pourtant, le resolver (`playback_subtitle_resolver.dart`
    l.207) passe par ton crochet, choisit l'anglais `isDefault` et calcule les sous-titres pour l'anglais. Avec le mode
    « Toujours », il affiche alors des sous-titres français sur un audio français, ce qui contredit CA6.
  - **Ce que je propose.** `forkLaunchAudioIntent` ne peut pas lever l'ambiguïté : au lancement, les pistes du fichier
    ne sont pas encore connues. La correction simple est donc dans le crochet audio : quand
    `PlaybackInitializationResult.isTranscoding` est vrai et qu'une seule piste audio est annoncée comme réellement
    envoyée (`activeAudioStreamId`), le crochet se cale sur cette piste et ne réinvente rien. Si ce n'est pas
    faisable sans élargir le diff, il faut au minimum un test `test/fork/` qui fige le comportement, et noter le cas dans
    les risques du plan.

- ⚠️ À amender : le profil n'est peut-être pas encore chargé quand `forkLaunchAudioIntent` le lit.
  - **Le cas.** Démarrage à froid lancé depuis la rangée système « À suivre » d'Android TV (`WatchNextProvider`) ou par
    un lien profond. `forkLaunchAudioIntent` lit alors le profil avant que `waitForProfileSettings` ait été attendu, et
    l'intention ne part pas. En lecture directe, tes crochets corrigent ensuite, car `applyTrackSelection` attend bien
    le profil. Mais en transcodage, le serveur garde la main.
  - **Ce que je propose.** Que `forkLaunchAudioIntent` attende la même `waitForProfileSettings` bornée (2 s), ou qu'on
    accepte explicitement ce cas comme risque.
  - **Recette.** Ajouter un lancement depuis la rangée « À suivre » après un arrêt forcé de l'app
    (`adb shell am force-stop io.github.adrien24.popkino`), en surveillant `[serverSelected]` dans
    `adb logcat -s flutter`.

- ⚠️ À amender : sur Jellyfin avec « Mémoriser » activé, Popkino écrit désormais le choix **automatique** de la règle
  sur le serveur.
  - **Pourquoi.** `_currentStreamSelection` (`playback_progress_tracker.dart` l.777-792) envoie dans les rapports de
    progression l'index de la piste **jouée**, et le drapeau `RememberAudioSelections` du compte est actif. Jellyfin
    enregistre donc l'anglais choisi par la règle comme souvenir de l'élément, ce qui remplace un choix fait dans
    jellyfin-web.
  - **Ce n'est pas bloquant.** C'est cohérent avec la langue du compte, et ton A2 rend la règle inerte ensuite. Mais ça
    va à l'encontre du principe upstream « les choix automatiques ne sont pas écrits » (#2323), qui ne vaut que pour
    Plex.
  - **Ce que je propose.** Le documenter dans `plan.md` comme effet de bord, à côté de l'incrustation Plex, et le
    vérifier en recette avec `GET /Items/<id>/PlaybackInfo` → `DefaultAudioStreamIndex`.

- ⚠️ À amender : le crochet de `playback_reload.dart` (transcodage) ne doit enregistrer le choix manuel **qu'après**
  un `selectStreams` réussi.
  - **Pourquoi.** Si le `PUT` est refusé (l.200-206), le changement de piste est annulé. Un indicateur déjà posé
    désactiverait alors la règle pour ce contenu au lancement suivant, alors que l'utilisateur n'a pas obtenu son
    choix.
  - Dans `TrackManager`, au contraire, tu écris l'indicateur avant l'écriture serveur, et c'est correct : la piste est
    déjà appliquée localement (l.427-429).

- ⚠️ À amender : `forkChangedSkip` → la liste des tests upstream marqués doit figurer **dans `plan.md`**, avec le CA
  qui justifie chacun.
  - Dans `scripts/fork/check_identity.py` ou dans un test `test/fork/`, ajouter une garde qui échoue si le nombre de
    `forkChangedSkip` dépasse cette liste. Sans elle, un `skip` ajouté pendant une fusion masquerait une régression
    upstream sans que personne ne le voie.

- ❌ Bloquant : aucun.

### Questions produit
D'accord avec la liste fusionnée (forcés avec audio français, choix reporté à l'épisode suivant, réglage de langue
d'une série dans Plex). Pas de nouvelle question.

## Validation de plateforme sur plan.md — tour 1

Le plan intègre mes cinq ⚠️ et les décisions produit (CA4ter, CA12). Il reste une objection bloquante, simple à régler,
et un amendement à la recette.

- ❌ Bloquant : en lecture directe, l'intention de lancement (T4) fige `_selectedAudioStreamId` sur l'anglais. Un
  changement de qualité ou de version **fait alors revenir l'anglais** après un choix manuel.
  - **Faits vérifiables.**
    - En lecture directe, Plex renvoie `activeAudioStreamId: carriedAudioStreamId` (`plex_client.dart` l.3894), et
      Jellyfin renvoie `activeAudioStreamId: requestedAudioStreamId` (`playback.dart` l.447).
    - `_commitPlaybackSession` recopie cette valeur dans `_selectedAudioStreamId` (`video_player_screen.dart` l.1125).
      Aucun changement de piste local, fait dans mpv, ne la met à jour : il n'y a que deux affectations, l.1125 et
      l.1484.
    - Au changement de qualité, `targetAudioStreamId = selectedAudioStreamId ?? _selectedAudioStreamId`
      (`playback_reload.dart` l.511-514). Chez Plex, un id explicite passe avant le report de piste (`plex_client.dart`
      l.3800).
  - **Scénario.** Lecture directe en anglais, puis passage à la main en français, puis qualité 720p : le transcodeur
    reçoit l'id anglais et l'audio repasse en anglais.
  - **Pourquoi c'est une régression.** Aujourd'hui, un lancement sans report donne `activeAudioStreamId == null`, et le
    rechargement reprend la piste en cours. L'upstream n'a ce défaut qu'après un report d'un épisode à l'autre. Le plan le
    produirait à **chaque** lancement, puisque l'intention part même quand le serveur est déjà en anglais :
    `forkLaunchAudioIntent` ne connaît pas encore les pistes du fichier.
  - **Correction (une ligne `// FORK:` dans `video_player_screen.dart`, déjà touché par T4).** Retenir dans l'état de
    l'écran que l'ouverture a utilisé l'intention du fork (`_forkLaunchIntentUsed`). Puis, dans `_commitPlaybackSession`,
    après la l.1125 : `if (_forkLaunchIntentUsed && !session.isTranscoding) _selectedAudioStreamId = null;`. En
    transcodage, l'id est juste, car c'est bien la piste envoyée, et il doit rester. Le drapeau est remis à `false` à
    chaque nouvelle ouverture qui n'utilise pas l'intention.
  - **Test à ajouter en T4.** Après une ouverture en lecture directe avec l'intention, `_selectedAudioStreamId` est
    `null`. En recette, ajouter au point 1 : choix manuel du français, puis qualité 720p → toujours en français.

- ⚠️ À amender : le point 5 de la recette (CA10, « couper le serveur au moment du changement de piste ») ne prouve
  pas ce qu'il vise.
  - **Pourquoi.** En lecture directe, mpv doit relire le flux pour la nouvelle piste (voir ma proposition, §5). Couper
    le serveur arrête donc la lecture, quoi que fasse l'app, et l'essai échouera pour une raison étrangère à la
    fonctionnalité.
  - **Ce que je propose.**
    - CA10 est prouvé par les tests de T3 (faux persister : erreur temporaire, puis refus 4xx).
    - Sur la TV, on se limite à constater, avec « Mémoriser » activé et une coupure réseau **brève** du serveur juste
      après le changement, qu'aucun message bloquant ne vient de l'écriture.
    - Un arrêt du flux lui-même est hors sujet.

- ✅ Tout le reste est approuvé :
  - les décisions 1 à 12 ;
  - les règles A1-A4 et S1-S3 ;
  - T1 (indicateurs locaux) ;
  - T3, avec l'indicateur posé après le `selectStreams` réussi ;
  - T4, avec le calage des sous-titres sur l'audio envoyé et l'attente du profil (2 s au plus) ;
  - T5 ;
  - la garde `forkChangedSkip` ;
  - les risques documentés ;
  - aucun impact Android, Gradle, CI ni Google Play.

Une fois l'objection ❌ intégrée au plan (T4, fichiers et tests), je réponds APPROUVÉ sans nouveau tour.

## Réponse du pilote (app) à la validation de plateforme — tour 1

- ✅ **❌ accepté et vérifié dans le code.**
  - En lecture directe, l'intention revient en `activeAudioStreamId` :
    - Plex : `plex_client.dart` l.3894, et l.3884 en cas de repli du transcodage vers la lecture directe ;
    - Jellyfin : `playback.dart` l.447.
  - `_commitPlaybackSession` la recopie dans `_selectedAudioStreamId` (`video_player_screen.dart` l.1125).
  - `playback_reload.dart` l.511-514 la renvoie lors d'un changement de qualité (`useCurrentAudioStreamSelection`).
  - **Intégré en T4** :
    - champ `_forkLaunchIntentUsed`, affecté aux deux points où l'intention est créée ;
    - ligne `// FORK:` dans `_commitPlaybackSession` qui remet l'id à `null` hors transcodage ;
    - condition extraite dans `forkAudioStreamIdAfterCommit` (`lib/fork/`) pour la tester sans test widget ;
    - étape de recette « français à la main, puis 720p : l'audio reste en français » (T6, point 1).
- ✅ **⚠️ CA10 accepté.** La preuve vient des tests de T3. La recette sur la TV se limite à une coupure brève après le
  changement de piste, sans message bloquant (T6, point 5).
- Plan mis à jour, statut toujours **brouillon**, en attente de ton APPROUVÉ.

## Validation de plateforme sur plan.md — tour 2

APPROUVÉ.
- L'objection ❌ du tour 1 est levée par `_forkLaunchIntentUsed`, la ligne `// FORK:` dans `_commitPlaybackSession`
  et `forkAudioStreamIdAfterCommit`, avec ses trois tests.
- Le drapeau est réaffecté à chaque ouverture en ligne. S'il restait à `true` lors d'une ouverture hors ligne, il
  remettrait seulement à `null` un id que ce chemin ne fournit pas : c'est sans effet.
- L'amendement sur CA10 est intégré (T6, point 5).
