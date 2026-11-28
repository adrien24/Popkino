# Plan technique — demandes-recentes-overseerr

Spec : docs/produit/specs/demandes-recentes-overseerr.md
Statut : approuvé       Pilote : architecte-app

Sources : `proposition-app.md`, `proposition-plateforme.md`, `debat.md` (tour 1), réponses du PO (CA3e, CA5, CA5b,
CA16b). Configuration réelle de l'utilisateur : **Overseerr + Plex** ; Jellyfin et Jellyseerr sont couverts par les tests
automatisés (CA19). Recette **uniquement sur la Fire TV Stick** (192.168.1.173, `armeabi-v7a`).

## Décisions

1. **Rangée insérée au rendu, jamais attendue.** `library_recommended_tab.dart` délègue `buildContent` à
   `ForkRecentRequestsShelf`, qui ajoute le hub quand il est prêt. `_loadRecommendedHubs` et la liste `items` ne
   changent pas. Raison : CA17 (les autres rangées s'affichent dans le même temps qu'aujourd'hui), et aucune logique
   upstream sur `items` (état vu, suppression, Continuer à regarder) ne voit le hub du fork.
2. **Trois fichiers upstream modifiés, environ 14 lignes, toutes marquées `// FORK: demandes-recentes-overseerr`** :
   - `seerr_client.dart` : `getRequestsJson`, pour hériter de l'authentification et de la ré-authentification ;
   - `seerr_catalog_source.dart` : `catalogItemFromDetailsForFork`, pour réutiliser les badges et l'état serveur
     privés (environ 150 lignes) sans les dupliquer ;
   - `library_recommended_tab.dart` : crochet de rendu et d'activation.

   Aucun autre fichier upstream : ni `tv_browse_rail.dart`, ni `media_card.dart`, ni `media_navigation_helper.dart`,
   ni `main.dart`, ni les modèles Seerr générés.
3. **Activation par les points d'extension existants.** `TvBrowseRail.onActivateItem` (TV) et `HubSection.onItemTap`
   (D-pad et toucher hors TV) renvoient `false` / `null` pour tout hub qui n'est pas celui du fork (D11 : « null =
   upstream »).
4. **Badges : ceux de `MediaCard`, sans code nouveau.** Chaque affiche est un `CatalogItem` (source `seerr`) dont
   `serverState` est calculé à partir de la liste fraîche et des seules demandes de l'utilisateur. On obtient ainsi le
   même vocabulaire que la fiche Explorer, y compris « Refusé » et « Échec de la demande » (CA7, CA7b, CA13).

   **Amendement du 2026-11-28 (T10, après la recette ; remplace la décision 4 pour la rangée et ajoute un 4e fichier
   upstream à la décision 2).** Les badges de `MediaCard` ne peuvent pas satisfaire CA7 à CA7e : ils empilent
   disponibilité et demande (`_buildCatalogBadgeLabels`, jusqu'à 3 badges), n'ont aucun texte pour `deleted`, ont des
   textes longs coupés par `overflow: .ellipsis` et un fond noir unique, le tout privé dans `media_card.dart`.
   La rangée affiche donc **son propre badge**, calculé dans `lib/fork/` et dessiné à la place de `_CatalogBadges`
   par un crochet « null = upstream » (D11) d'une ligne dans `media_card.dart`. Le crochet ne réagit qu'à une clé
   propre au fork dans `MediaItem.raw`, que seuls les éléments du hub du fork portent : Explorer, la fiche et toutes
   les autres rangées gardent exactement leurs badges actuels (texte, empilement, couleurs). Aucune autre
   modification upstream : ni `hub_section.dart`, ni `tv_browse_rail.dart`, ni `catalog_labels.dart`.
5. **Cache en mémoire, attaché à l'instance `SeerrClient` par un `Expando`.** Il naît et meurt avec le client
   (déconnexion, changement de profil), sans provider ni ligne dans `main.dart`. **Écart assumé à D13** : il n'y a aucun
   état global observé, seulement un cache, et l'état réactif est local au widget.
   - Pas de `JsonPref` ni de préférences (bloquant plateforme).
   - Un cache disque éventuel est un fichier du répertoire de cache, lu à l'ouverture d'une bibliothèque, jamais au
     démarrage. C'est la tâche conditionnelle T9.
6. **Aucun affichage d'instantané avant une réponse d'Overseerr** (bloquant plateforme).
   - Une rangée n'apparaît pour une bibliothèque qu'à partir d'une liste obtenue il y a moins de 30 s.
   - Seule exception : une rangée **déjà affichée** reste en place pendant son propre rafraîchissement, et après l'échec
     de celui-ci. Elle n'est remplacée que par une réponse plus récente. Sinon le focus disparaîtrait sous
     l'utilisateur (CA12, CA14).
   - Cette exception est bornée : si la dernière réponse réussie date de plus de **5 min** au moment d'un
     rafraîchissement en échec, la rangée est retirée. Un onglet resté vivant ne montre donc pas indéfiniment des états
     périmés quand Overseerr est éteint (remarque plateforme).
7. **Budgets réseau** (plateforme) :
   - liste `GET /request?take=100&skip=0&sort=added&requestedBy=<userId>` (CA5 : 100 dernières demandes ; CA6), avec
     un refiltrage côté client sur `requestedBy.id` ;
   - fraîcheur de la liste 30 s, appels simultanés fusionnés (`FutureCoalescer`), cache négatif de 60 s après un
     échec ;
   - délais côté appelant : 8 s pour la liste, 8 s par fiche, 15 s pour composer une rangée ;
   - 4 fiches au plus en vol, lues **à la demande** pour la bibliothèque ouverte, dans l'ordre, arrêt à 20 titres
     retenus ;
   - rien au démarrage, et aucun appel sans Seerr, hors ligne, ou pour une bibliothèque ni film ni série (CA15, CA18).
8. **Ouverture par le lien serveur fourni par Overseerr**, dans cet ordre :
   - lien `plexUrl` d'Overseerr (le champ `mediaUrl` n'existe pas dans Overseerr, cf. `debat.md`), puis `mediaUrl`
     de Seerr/Jellyseerr, puis `ratingKey` / `jellyfinMediaId` seuls ;
   - le serveur visé doit être en ligne (`MultiServerProvider.isServerOnline`), car `PlexClient.fetchItem` peut se
     rabattre sur le cache d'API ;
   - si le serveur n'est pas identifié, le tmdbId est vérifié ;
   - en dernier recours, `CatalogLibraryMatcher` dans le budget restant ;
   - budget total de 2,5 s, puis la fiche Explorer (CA8, CA10, CA11).

   Pour Plex, l'identifiant de serveur de l'app **est** le `machineIdentifier` (`plex_client.dart:3400`).
9. **Bibliothèque Animés**, reconnue par serveur et une fois par vie du client :
   - d'abord par la bibliothèque d'un animé arrivé, rejetée si un titre non animé arrivé du même type est dans la même
     bibliothèque (CA3e) ;
   - sinon par un nom contenant « anim » (CA3d) ;
   - sinon aucune (CA3c).

   Au plus 2 appels `fetchItem` par serveur.
10. **Même rangée dans toutes les bibliothèques du même type** (CA5b) ; une bibliothèque vide garde son message
    upstream (CA16b, `ContentStateBuilder`).
11. **Modèles propres au fork, lus depuis le JSON brut** pour la liste (`createdAt`, `type`, `requestedBy`,
    `plexUrl`, `mediaUrl`, `ratingKey`, `jellyfinMediaId`). Pour les fiches, on garde les méthodes publiques
    `getMovie` / `getTv` et on conserve un enregistrement léger. Aucun `*.g.dart` upstream n'est régénéré.
12. **Retour visuel à l'ouverture** par un `OverlayEntry` du fork : un indicateur centré, sans focus, affiché si la
    résolution dépasse 300 ms. Un nouvel OK pendant la résolution est ignoré.

Décision durable reportée dans `docs/technique/decisions.md` (D15) :

> **D15 — Accès à une capacité privée d'une classe upstream (2026-11-28)**
> Contexte : le fork a besoin d'appels ou de conversions privés (`SeerrClient._request`,
> `SeerrCatalogSource._toDetailCatalogItem`). Décision : on ajoute à la classe upstream **une** méthode publique
> courte, suffixée `ForFork` ou nommée d'après l'API (`getRequestsJson`), marquée `// FORK:`, qui délègue à
> l'implémentation privée. On ne duplique pas la logique et on ne contourne pas la classe (session,
> ré-authentification). Conséquences : une garde `test/fork/` vérifie la présence de la méthode ; à la fusion, on la
> replace à la fin de sa section.

## Tâches

Ordre et parallélisme : **vague 1** T1, T2, T6 (fichiers disjoints) → **vague 2** T3, T5 → **vague 3** T4 →
**vague 4** T7 et T4b (fichiers disjoints, parallélisables) → **vague 5** T8 (recette) → T9 seulement si la recette
le déclenche. **Après la recette du 2026-11-28** : T10 (badges de la rangée), puis T10b (reprise de la recette des
badges), puis T11 (« En cours » seulement pendant un téléchargement réel, CA7g) et sa recette.

### T1 — Crochets Seerr upstream
- Complexité : S
- Dépend de : —
- Fichiers :
  - modifier `lib/services/seerr/seerr_client.dart`
  - modifier `lib/services/catalog/seerr_catalog_source.dart`
  - créer `test/fork/recent_requests/seerr_hooks_test.dart`
- À faire :
  - `seerr_client.dart`, à la fin de la section `// ---------- Requests ----------`, juste après `createRequest` :
    ```dart
    // FORK: demandes-recentes-overseerr — raw `GET /request` page (fields the shared models omit) through the authenticated path.
    Future<Map<String, dynamic>> getRequestsJson({required int take, required int requestedBy}) async =>
        await _request('GET', '/request', query: {'take': take, 'skip': 0, 'sort': 'added', 'requestedBy': requestedBy})
            as Map<String, dynamic>;
    ```
    Ne pas passer `filter` : son absence vaut « tous les statuts » dans Overseerr et dans Seerr.
  - `seerr_catalog_source.dart`, juste après `fetchDetail` :
    ```dart
    // FORK: demandes-recentes-overseerr — detail mapping (badges, server state) without the recommendations call.
    Future<CatalogItem> catalogItemFromDetailsForFork(SeerrDetails details, MediaKind kind) async =>
        _toDetailCatalogItem(details, kind, await _tmdbImageOrigin());
    ```
- Tests (`MockClient` de `package:http/testing`, modèle `test/services/seerr/seerr_client_test.dart`) :
  - la requête part sur `/api/v1/request` avec `take=100`, `skip=0`, `sort=added`, `requestedBy=7`, sans `filter` ;
  - un 403 de session déclenche la ré-authentification puis une seconde tentative, comme les autres appels ;
  - `catalogItemFromDetailsForFork` sur un `SeerrDetails` dont `mediaInfo.requests` contient une demande `declined`
    donne `serverState.request == CatalogRequestState.declined` ; avec un statut média 5, il donne
    `availability == available` ;
  - garde de fichier : les deux fichiers contiennent `FORK: demandes-recentes-overseerr` et le nom de la méthode.
- Critères d'acceptation couverts : CA6 (requête), CA7, CA7b (base).

### T2 — Modèles du fork : demande, lien serveur, résumé de titre
- Complexité : M
- Dépend de : —
- Fichiers à créer :
  - `lib/fork/recent_requests/recent_request.dart`
  - `lib/fork/recent_requests/server_link.dart`
  - `lib/fork/recent_requests/title_summary.dart`
  - `test/fork/recent_requests/recent_request_test.dart`
  - `test/fork/recent_requests/server_link_test.dart`
  - `test/fork/recent_requests/fixtures/overseerr_requests.json`
  - `test/fork/recent_requests/fixtures/seerr_requests.json`
- À faire (fonctions pures, pas de Flutter, en-tête `// FORK: demandes-recentes-overseerr — …`) :
  - `server_link.dart` :
    - type `ForkServerLink({required ForkServerLinkBackend backend, String? serverId, required String itemId})`, avec
      `enum ForkServerLinkBackend { plex, jellyfin }` ;
    - fonction `ForkServerLink? parseServerLink(Map<String, dynamic> media, {bool is4k = false})`, qui essaie dans
      l'ordre, avec les suffixes `4k` quand `is4k` est vrai :
      1. `plexUrl` (Overseerr), motif `#!/server/<machineId>/details?key=%2Flibrary%2Fmetadata%2F<ratingKey>` ;
      2. `mediaUrl` (Seerr), même forme Plex, ou forme Jellyfin `…details?id=<id>…serverId=<serverId>` ;
      3. `ratingKey` seul → Plex, `serverId` null ;
      4. `jellyfinMediaId` seul → Jellyfin, `serverId` null.

      Tolérer les deux encodages (`%2F` et `/`). Rien d'exploitable → `null`.
  - `recent_request.dart` :
    - classe `ForkRecentRequest`, avec les champs `latestRequestId`, `createdAt` (`DateTime?`), `kind`
      (`MediaKind.movie` / `MediaKind.show`), `tmdbId`, `tvdbId`, `mediaStatusCode`, `mediaStatus4kCode`,
      `seasons` (`List<SeerrSeasonInfo>`), `myRequests` (`List<SeerrRequest>` : id, statut, is4k, saisons), `link`,
      `link4k` ;
    - accesseur `SeerrMediaInfo mediaInfo` qui reconstruit `SeerrMediaInfo(tmdbId, tvdbId, statusCode,
      status4kCode, seasons, requests: myRequests)` par le constructeur public ;
    - fonction `List<ForkRecentRequest> parseRecentRequests(Object? json, {required int userId})` :
      - lit `results` et garde les éléments dont `requestedBy.id == userId` ;
      - type pris dans `media.mediaType`, sinon dans `type` de la demande (`movie` / `tv`) ;
      - ignore les éléments sans `media` ou sans `tmdbId`, et ne lève jamais d'exception sur un élément malformé ;
      - regroupe par `(kind, tmdbId)` en gardant la position de la plus récente et en cumulant `myRequests` ;
      - conserve l'ordre reçu (le plus récent d'abord).
  - `title_summary.dart` :
    - classe `ForkTitleSummary`, avec les champs `tmdbId`, `kind`, `title`, `name`, `originalTitle`,
      `originalName`, `overview`, `posterPath`, `backdropPath`, `releaseDate`, `firstAirDate`, `voteAverage`,
      `imdbId`, `tvdbId`, `isAnime` ;
    - constructeur `ForkTitleSummary.fromDetails(SeerrDetails d, MediaKind kind)`, où `isAnime = d.keywords?.any((k)
      => k.id == SeerrConstants.animeKeywordId) ?? false` (même règle que `seerr_request_sheet.dart:288`, CA3b) ;
    - méthode `SeerrDetails toDetails(SeerrMediaInfo mediaInfo)` par le constructeur public de `SeerrDetails`
      (`externalIds: SeerrExternalIds(imdbId:, tvdbId:)`).
  - Fixtures : JSON réalistes, au moins 8 demandes chacune.
    - Overseerr : `plexUrl`, demandes d'un autre utilisateur, une série en deux demandes de saisons, HD + 4K, statuts
      1 à 5, un élément sans `media`.
    - Seerr : `mediaUrl` Plex et Jellyfin, `jellyfinMediaId`.
- Tests :
  - filtre `requestedBy` (CA6), regroupement, ordre, éléments malformés ignorés ;
  - `parseServerLink` sur chaque forme, en HD et en 4K ;
  - `isAnime` vrai avec le mot-clé 210024, faux sans lui (exemple « Les Simpson », CA3b) ;
  - `toDetails` conserve le `mediaInfo` fourni.
- Critères d'acceptation couverts : CA3b, CA5 (ordre), CA6, CA19 (lecture Jellyseerr).

### T3 — Classement par rayon et choix de la bibliothèque Animés (pur)
- Complexité : M
- Dépend de : T2
- Fichiers à créer :
  - `lib/fork/recent_requests/recent_requests_classifier.dart`
  - `test/fork/recent_requests/recent_requests_classifier_test.dart`
- À faire :
  - Type `enum ForkRequestShelf { movies, shows, anime }`.
  - Fonction `ForkRequestShelf? shelfForLibrary(MediaLibrary library, {required String? animeLibraryGlobalKey})` :
    `library.globalKey == animeLibraryGlobalKey` → `anime` ; `MediaKind.movie` → `movies` ; `MediaKind.show` →
    `shows` ; tout autre cas → `null` (CA18).
  - Fonction `bool belongsTo(ForkRequestShelf shelf, MediaKind kind, bool isAnime, {required bool serverHasAnimeLibrary})` :
    - `anime` ⇔ `isAnime && serverHasAnimeLibrary` (films et séries mêlés, CA3) ;
    - `movies` ⇔ `kind == movie && !(isAnime && serverHasAnimeLibrary)` ;
    - `shows` : même règle pour les séries (CA1, CA2, CA3c).
  - Fonction `String? decideAnimeLibrary({required List<MediaLibrary> serverLibraries, String? arrivedAnimeLibraryId,
    String? arrivedNonAnimeSameKindLibraryId})` :
    1. `arrivedAnimeLibraryId` non nul, différent de `arrivedNonAnimeSameKindLibraryId`, et présent dans
       `serverLibraries` avec un `kind` film ou série → son `globalKey` (CA3d) ;
    2. si les deux identifiants sont égaux, la bibliothèque est mixte et rejetée (CA3e) ;
    3. sinon, première bibliothèque film ou série (dans l'ordre de `serverLibraries`) dont
       `title.toLowerCase().contains('anim')` ;
    4. sinon `null` (CA3c).
  - Constante `kRecentRequestsRowLimit = 20` (CA5).
- Tests :
  - Films, Séries, Animés, musique, photos, mixte (CA18) ;
  - film Ghibli animé avec et sans bibliothèque Animés (CA3, CA3c) ;
  - noms « Animés », « Anime », « Animations japonaises », « ANIME » ;
  - bibliothèque mixte rejetée, ce qui laisse jouer le nom puis `null` (CA3e) ;
  - bibliothèque votée disparue → repli sur le nom.
- Critères d'acceptation couverts : CA1, CA2, CA3, CA3c, CA3d, CA3e, CA5, CA18.

### T4 — Dépôt : liste, fiches, caches, délais, bibliothèque Animés
- Complexité : L (concurrence, délais, fusion d'appels, cache négatif)
- Dépend de : T1, T2, T3
- Fichiers à créer :
  - `lib/fork/recent_requests/recent_requests_repository.dart`
  - `test/fork/recent_requests/recent_requests_repository_test.dart`
- À faire :
  - Accès : `static ForkRecentRequestsRepository of(SeerrClient client)`, par un `Expando` privé.
    `@visibleForTesting static ForkRecentRequestsRepository Function(SeerrClient)? debugOverride` permet de le
    remplacer en test.
  - API :
    ```dart
    Future<ForkRecentRequestsRow?> rowFor(MediaLibrary library, ForkRowContext ctx);
    class ForkRowContext { SeerrCatalogSource source; List<MediaLibrary> libraries;
      MediaServerClient? Function(String serverId) clientFor; bool Function(String serverId) isServerOnline; }
    class ForkRecentRequestsRow { MediaHub hub; Map<String, ForkRecentRequestEntry> entriesByItemId; DateTime fetchedAt; }
    class ForkRecentRequestEntry { ForkRecentRequest request; CatalogItem catalogItem; }
    ```
  - Dans `rowFor`, dans l'ordre :
    1. `library.serverId == null` → `null`.
    2. Liste :
       - si elle est en mémoire depuis moins de 30 s, la réutiliser ;
       - sinon, si un échec date de moins de 60 s, renvoyer `null` ;
       - sinon `FutureCoalescer.run(() => client.getRequestsJson(take: 100, requestedBy:
         client.session.userId).timeout(8 s))`, puis `parseRecentRequests`.

       En cas d'échec, noter l'heure (cache négatif), `appLogger.w`, renvoyer `null`. Le résultat d'un appel qui
       aboutit après le délai remplit quand même le cache.

       « Échec » veut dire **toute** erreur, pas seulement les exceptions Seerr. Par exemple, un intermédiaire qui
       renvoie un 200 non JSON fait lever une `TypeError` au `as Map<String, dynamic>` de `getRequestsJson`. On
       attrape donc avec un `catch (e)` sans type, de même pour l'analyse de la liste.
    3. Bibliothèque Animés du serveur de `library`, calculée une fois par dépôt et par serveur (`Map<String,
       Future<String?>>`) :
       - parmi les entrées disponibles ou partiellement disponibles (statut média 4 ou 5, HD ou 4K), dans l'ordre,
         lire les fiches à la demande (point 4) pour trouver le premier animé et le premier non-animé du même
         `kind` que cet animé ;
       - pour chacun, si son lien désigne ce serveur, ou si le lien n'a pas de serveur et que c'est le serveur de
         la bibliothèque, et que `isServerOnline` est vrai : `clientFor(serverId).fetchItem(itemId)` avec un délai
         de 2,5 s, pour lire `libraryId` ;
       - enfin `decideAnimeLibrary`. Au plus 2 `fetchItem`.
    4. `shelfForLibrary`, puis `null` si le résultat est `null` (déjà filtré par l'appelant, mais on reste sûr).
       Parcourir les entrées dans l'ordre et ne lire que les fiches dont le `kind` peut appartenir au rayon (film
       seulement pour `movies`, série seulement pour `shows`, les deux pour `anime`). Les fiches passent par
       `KeyedFutureCoalescer` avec la clé `'$lang|${kind.id}:$tmdbId'`, où `lang =
       LocaleSettings.currentLocale.plexLanguageCode`. Chacune : `source.client.getMovie` / `getTv` avec un délai de
       8 s, puis `ForkTitleSummary.fromDetails`, gardé en mémoire. Un échec n'est pas mis en cache et fait seulement
       sauter le titre. Au plus 4 en vol : file d'attente maison à 4 ouvriers, sur le modèle de
       `data_aggregation_service.dart:751`. Arrêt dès 20 titres retenus.
    5. Budget global de 15 s pour les points 3 et 4 : à l'échéance, on renvoie les titres déjà retenus, au moins
       un, sinon `null`.
    6. Pour chaque titre retenu :
       - `CatalogItem` par `source.catalogItemFromDetailsForFork(summary.toDetails(request.mediaInfo), kind)` ;
       - `MediaItem` par `catalogItem.toMediaItem()`.
    7. Hub :
       ```dart
       MediaHub(id: 'popkino.recentRequests:${library.globalKey}', identifier: 'popkino.recentRequests',
         title: t.fork.recentRequests.title, type: 'mixed', items: …, size: items.length)
       ```
       Ni `serverId`, ni `more` (comme les hubs d'Explorer). Liste vide → `null` (CA16).
  - Rien ne doit être créé ni appelé tant que `rowFor` n'est pas invoqué (pas d'initialisation au démarrage).
- Tests (client `SeerrClient` réel sur `MockClient`, compteurs d'appels, `fakeAsync`) :
  - Films puis Séries puis Animés en moins de 30 s → 1 seul `/request` ; une deuxième ouverture → 0 fiche ;
  - jamais plus de 4 fiches en vol ; Films ne lit aucune fiche de série ;
  - liste sans réponse → `null` après 8 s ; nouvel essai bloqué pendant 60 s, puis autorisé ;
  - 200 avec un corps non JSON, ou un JSON qui n'est pas un objet → `null`, cache négatif et aucune exception
    propagée ;
  - une fiche en échec saute un titre sans faire échouer la rangée ;
  - rangée limitée à 20 et ordonnée (CA5) ; CA5b : deux bibliothèques de séries donnent les mêmes éléments ;
  - bibliothèque Animés : animé arrivé dans « Animés » → reconnue ; animé et non-animé arrivés dans « Séries » →
    rejet puis repli sur le nom (CA3e) ; serveur hors ligne → aucun `fetchItem` ;
  - changement de langue → nouvelles fiches ; nouveau `SeerrClient` → aucune donnée de l'ancien (CA6) ;
  - badges : une demande refusée donne `serverState.request == declined` (CA7b) ; statut 5 donne `available`
    (CA13) ;
  - fixture Seerr / Jellyfin traitée comme celle d'Overseerr (CA19).
- Critères d'acceptation couverts : CA1 à CA3e, CA5, CA5b, CA6, CA7, CA7b, CA13, CA15 (aucun appel), CA16, CA17,
  CA19.

### T4b — Ne pas mémoriser un repli de la bibliothèque Animés dû à une panne
- Complexité : M
- Dépend de : T4 (même fichier ; indépendant de T7, qui ne touche pas au dépôt)
- Fichiers :
  - modifier `lib/fork/recent_requests/recent_requests_repository.dart`
  - modifier `test/fork/recent_requests/recent_requests_repository_test.dart`
- Problème (remarque du codeur T4) : si le serveur est hors ligne, ou si `fetchItem` échoue ou dépasse son délai
  pendant la reconnaissance, le repli sur le nom est mémorisé pour toute la vie du client Seerr. Un serveur Plex lent
  à se réveiller au premier chargement fausse alors le classement (CA3d, CA3e) jusqu'à la reconnexion à Overseerr,
  donc potentiellement pendant des jours sur une Fire TV qui ne tue pas l'app.
- À faire, sans changer l'API publique du dépôt :
  - la reconnaissance renvoie, en interne, le résultat **et** un indicateur `conclusive`. Elle est non concluante dès
    qu'un `fetchItem` nécessaire a été sauté parce que le serveur était hors ligne, ou a levé une exception, ou a
    dépassé son délai ;
  - un `fetchItem` qui renvoie `null` (élément absent) ou un élément sans `libraryId` reste concluant ;
  - un résultat concluant est mémorisé comme aujourd'hui, pour la vie du client ;
  - un résultat non concluant sert **pour ce chargement seulement** (repli sur le nom, comme aujourd'hui). Le
    dépôt retient l'heure de cette tentative pour ce serveur et refait la reconnaissance au premier `rowFor` qui
    suit d'au moins **60 s** (même pas que le cache négatif de la liste). Avant ces 60 s, il réutilise le repli sans
    nouvel appel ;
  - aucun nouveau `fetchItem` tant que le serveur reste hors ligne (`isServerOnline` testé avant chaque essai) ;
  - les appels simultanés restent fusionnés par serveur (un seul essai en vol).
- Tests (`fakeAsync`, compteurs d'appels) :
  - serveur hors ligne au premier `rowFor`, donc repli sur le nom et 0 `fetchItem` ; serveur de retour en ligne et
    `rowFor` 61 s plus tard → reconnaissance par vote, mémorisée ; un `rowFor` suivant ne fait aucun `fetchItem` ;
  - `fetchItem` qui lève une exception, puis `rowFor` 30 s plus tard → 0 nouvel appel ; 61 s plus tard → nouvel
    essai ;
  - `fetchItem` qui renvoie `null` → résultat concluant, mémorisé, sans nouvel essai ;
  - délai de 2,5 s dépassé → non concluant.
- Critères d'acceptation couverts : CA3c, CA3d, CA3e, CA17 (pas d'appels répétés vers un serveur en panne).

### T5 — Ouverture d'une demande (résolution vers le titre serveur)
- Complexité : M
- Dépend de : T2
- Fichiers à créer :
  - `lib/fork/recent_requests/recent_request_opener.dart`
  - `test/fork/recent_requests/recent_request_opener_test.dart`
- À faire :
  - Fonction pure et testable :
    ```dart
    Future<MediaItem?> resolveServerItem({required ForkRecentRequest request, required CatalogItem item,
      required bool isAvailable, required MediaLibrary library, required MediaServerClient? Function(String) clientFor,
      required bool Function(String) isServerOnline, Future<List<MediaItem>> Function(CatalogItem)? matchLibraries,
      Duration budget = const Duration(milliseconds: 2500)})
    ```
    1. Résoudre seulement si `isAvailable` est vrai. L'appelant le calcule ainsi : statut média HD ou 4K
       `partiallyAvailable` ou `available` selon `SeerrMediaStatus.resolve(code, client.session.product)`. Sinon
       `null` (CA9, CA7b).
    2. `link ?? link4k` :
       - lien avec `serverId` d'un serveur de l'app en ligne → `fetchItem(itemId)` ; élément non nul et de type film
         ou série attendu → le renvoyer ;
       - lien sans `serverId` → serveur de la bibliothèque s'il est en ligne, `fetchItem`, puis vérifier par
         `fetchExternalIds(item.id)` que `tmdb == request.tmdbId`, sinon rejeter (les `ratingKey` se répètent d'un
         serveur Plex à l'autre).
    3. Repli : `matchLibraries(item)` (en production, `context.read<CatalogLibraryMatcher?>()?.match(item)` →
       `.items`), dans le budget restant. Choisir d'abord une copie du même serveur **et** de la même bibliothèque
       que l'onglet, puis du même serveur, puis la première.
    4. Budget dépassé, exception ou rien trouvé → `null`. Ne jamais lever d'exception.
  - Fonction d'interface :
    ```dart
    Future<void> openRecentRequest(BuildContext context, ForkRecentRequestEntry entry, MediaLibrary library)
    ```
    - drapeau statique « en cours » : un nouvel OK pendant une ouverture est ignoré ;
    - `OverlayEntry` centré (`CircularProgressIndicator` dans un `IgnorePointer`, sans `Focus`), inséré après 300 ms
      s'il n'y a pas encore de résultat, retiré dans un `finally` ;
    - élément trouvé → `navigateToMediaItemDetails(context, serverItem)` ; sinon → `navigateToCatalogItem(context,
      entry.catalogItem)` (CA11). Vérifier `context.mounted` après chaque `await`.
- Tests :
  - lien `plexUrl` avec un serveur en ligne → l'élément ; même lien avec le serveur hors ligne → `null`, sans
    `fetchItem` (CA11) ;
  - `ratingKey` seul avec un mauvais tmdbId → rejeté ;
  - délai de 2,5 s dépassé (`fakeAsync`) → `null` ;
  - partiellement disponible → l'élément serveur (CA10) ; demandé, approuvé ou refusé → `null` sans aucun appel
    (CA9, CA7b) ;
  - choix de la copie ; lien Jellyfin `mediaUrl` (CA19).
  - Test de widget de `openRecentRequest` avec un `Navigator` : route `MediaDetailScreen` ou
    `CatalogItemDetailScreen` poussée selon le cas (vérifier le type de la route ou utiliser un `NavigatorObserver`).
- Critères d'acceptation couverts : CA8, CA9, CA10, CA11, CA19.

### T6 — Traductions
- Complexité : S
- Dépend de : —
- Fichiers :
  - modifier `lib/fork/i18n/fr.json`, `lib/fork/i18n/en.json`
  - fichiers régénérés : `lib/i18n/*.i18n.json`, `lib/i18n/strings*.g.dart`
- À faire :
  - ajouter `fork.recentRequests.title` : « Demandes récentes » / « Recent requests » ;
  - lancer `python3 scripts/fork/rebrand_i18n.py`, puis `scripts/codegen.sh` (D6) ;
  - ne jamais éditer `lib/i18n/*.json` à la main.
- Tests : `python3 scripts/checks/clean_translations.py --check --strict` et `scripts/codegen.sh --check`.
- Critères d'acceptation couverts : CA20.

### T7 — Rangée dans l'onglet de bibliothèque (widget du fork + crochet upstream)
- Complexité : L (chargement asynchrone concurrent, focus TV, réutilisation de l'état entre bibliothèques)
- Dépend de : T4, T5, T6
- Fichiers :
  - créer `lib/fork/recent_requests/recent_requests_shelf.dart`
  - modifier `lib/screens/libraries/tabs/library_recommended_tab.dart`
  - créer `test/fork/recent_requests/recent_requests_shelf_test.dart`
  - créer `test/fork/recent_requests/hooks_test.dart`
- À faire dans `recent_requests_shelf.dart` :
  - Signatures :
    ```dart
    typedef ForkShelfBuilder = Widget Function(BuildContext context, List<MediaHub> hubs, ForkRequestActivator fork);
    class ForkRecentRequestsShelf extends StatefulWidget { MediaLibrary library; List<MediaHub> hubs; ForkShelfBuilder builder; }
    class ForkRequestActivator {
      FutureOr<bool> activate(BuildContext context, MediaHub hub, MediaItem item);
      ValueChanged<MediaItem>? tapFor(BuildContext context, MediaHub hub);
      IconData? iconFor(MediaHub hub); // Symbols.playlist_add_check_rounded for the fork hub, else null
    }
    ```
    `ForkRequestActivator.none` est un activateur neutre qui renvoie `false` / `null`.
  - `build` :
    - lit `context.watch<CatalogSourcesProvider?>()?.seerrSource` ;
    - si la source est nulle, si `library.kind` n'est ni `MediaKind.movie` ni `MediaKind.show` (aucun chargement
      lancé, CA18), ou si aucune rangée n'est chargée : `builder(context, hubs, activator)`, avec la liste upstream
      inchangée ;
    - sinon, insérer le hub du fork après `hubs[0]` si `hubs.first.isContinueWatchingHub` (CA1), sinon en tête
      (CA4), sans modifier la liste reçue (copie).
  - Chargement :
    - déclencheurs : `initState` ; `didUpdateWidget` quand `library.globalKey` change (vider **immédiatement** la
      rangée : l'état de l'onglet est réutilisé d'une bibliothèque à l'autre, `_recommendedTabKey`) ; changement
      d'identité de `hubs` (rechargement de l'onglet) ; passage de l'onglet à « visible »
      (`TickerMode.getValuesNotifier(context)`, comme `BaseLibraryTab`) ; changement de `seerrSource`.
    - Chaque chargement appelle `ForkRecentRequestsRepository.of(source.client).rowFor(library, ctx)`, qui porte les
      règles de fraîcheur et de cache négatif.
    - `ctx` est construit à partir de `context.read<LibrariesProvider?>()?.libraries`,
      `context.read<MultiServerProvider?>()` (`isServerOnline(ServerId(id))`) et
      `context.tryGetMediaClientForServer`.
    - Un jeton de génération jette les réponses arrivées après un changement de bibliothèque ou un `dispose`.
  - Règle d'affichage (décision 6) :
    - une rangée n'est affichée que si `row.fetchedAt` date de moins de 30 s au moment où elle arrive ;
    - une rangée déjà affichée pour la **même** bibliothèque reste en place jusqu'à la réponse suivante, y compris
      quand le rafraîchissement échoue ou renvoie `null` à cause du cache négatif, **sauf** si `row.fetchedAt` date de
      plus de 5 min à ce moment-là : la rangée est alors retirée (décision 6) ;
    - si le rafraîchissement réussit et que la rangée est vide, elle disparaît (CA16).
  - Aucun appel ni aucun `rowFor` hors ligne : vérifier l'état hors ligne exposé par l'app, à repérer par le codeur
    autour de `OfflineModeProvider` / `_offlineSource` ; s'il n'est pas accessible simplement, se fier au cache
    négatif.
  - `activate` : hub dont l'`id` ne commence pas par `popkino.recentRequests:` → `false`. Sinon, chercher l'entrée
    par `item.id` dans `row.entriesByItemId`, lancer `unawaited(openRecentRequest(...))` (T5) et renvoyer `true`.
    `tapFor` : `null` pour les autres hubs.
- À faire dans `library_recommended_tab.dart` (chaque ligne modifiée ou ajoutée porte `// FORK:
  demandes-recentes-overseerr`) :
  1. ajouter l'import `../../../fork/recent_requests/recent_requests_shelf.dart` ;
  2. renommer l'actuel `Widget buildContent(List<MediaHub> items) {` en
     `Widget _buildContentWith(BuildContext context, List<MediaHub> items, ForkRequestActivator fork) {`, sans
     toucher au corps, et ajouter au-dessus :
     ```dart
     @override
     Widget buildContent(List<MediaHub> items) =>
         ForkRecentRequestsShelf(library: widget.library, hubs: items, builder: _buildContentWith);
     ```
  3. dans le corps, dans `HubSection(` : `icon: fork.iconFor(hub) ?? hubIconFor(hub),` et ajouter
     `onItemTap: fork.tapFor(context, hub),` ;
  4. `builder: (context) => _buildTvContent(items)` devient `_buildTvContent(items, fork)` ; la signature devient
     `Widget _buildTvContent(List<MediaHub> items, ForkRequestActivator fork)` ; dans `TvBrowseRail(` :
     `iconForHub: (hub, _) => fork.iconFor(hub) ?? hubIconFor(hub),` et ajouter
     `onActivateItem: (hub, item) => fork.activate(context, hub, item),`.

  Ne rien changer d'autre : ni `_loadRecommendedHubs`, ni `items`, ni `focusFirstItem`.
- Tests :
  - `recent_requests_shelf_test.dart`, avec un dépôt factice par `debugOverride` et un `builder` de test qui affiche
    les identifiants de hubs :
    - insertion après « Continuer à regarder » (CA1) ou en tête (CA4) ;
    - pas de provider Seerr → liste identique et aucun appel (CA15) ; bibliothèque musique → aucun appel (CA18) ;
    - `rowFor` en attente infinie → hubs upstream rendus à la première image (CA17) ; `rowFor` en erreur → absence ;
    - changement de bibliothèque → rangée vidée tout de suite, et réponse tardive de l'ancienne bibliothèque ignorée ;
    - rafraîchissement en échec → rangée affichée conservée ; même échec avec une dernière réponse de plus de 5 min →
      rangée retirée ;
    - activateur : hub étranger → `false` / `null`.
  - Test TV, sur le modèle de `test/widgets/tv_browse_rail_test.dart` : `TvBrowseRail` avec un hub « Continuer à
    regarder » et le hub du fork :
    - Bas, Haut, puis Bas vers la rangée suivante, focus jamais perdu (CA14) ;
    - focus sur le 3e hub, puis arrivée tardive de la rangée : le focus reste sur le même hub (clé) ;
    - OK sur une affiche du fork appelle `activate` et pas `navigateToMediaItem`.
  - `hooks_test.dart` : `library_recommended_tab.dart` contient `ForkRecentRequestsShelf(`, `fork.activate(` et
    `fork.tapFor(`, et chaque ligne porte le marqueur `FORK:`.
  - Lancer `scripts/run_tests.sh test/screens/libraries/` : les tests upstream de l'onglet restent verts sans
    provider Seerr.
- Critères d'acceptation couverts : CA1, CA4, CA5b, CA12, CA14, CA15, CA16, CA16b, CA17, CA18.

### T8 — Vérification globale et recette sur la Fire TV Stick
- Complexité : M
- Dépend de : T7
- Fichiers : aucun fichier de code ; compte rendu dans la réponse de l'agent.
- À faire : tout le bloc « Vérification globale » ci-dessous, puis la recette, avec les mesures relevées. La commande
  de build garde `--no-tree-shake-icons` : sans cette option, le build release échoue sur ce Mac
  (`IconTreeShakerException`). L'étape 10 vérifie les deux critères de mémoire.
- Critères d'acceptation couverts : tous, sur l'appareil réel (CA19 Jellyfin : tests automatisés seulement).

### T9 — (conditionnelle) Cache disque des résumés de titres
- Complexité : M
- Dépend de : T8, à ne lancer **que si** l'étape 2 de la recette dépasse 5 s pour 20 titres
- Fichiers :
  - créer `lib/fork/recent_requests/title_summary_disk_cache.dart`
  - modifier `lib/fork/recent_requests/recent_requests_repository.dart`
  - modifier `lib/fork/recent_requests/title_summary.dart` (`toJson` / `fromJson`)
  - créer `test/fork/recent_requests/title_summary_disk_cache_test.dart`
- À faire :
  - stocker uniquement les `ForkTitleSummary` (jamais la liste des demandes, jamais d'instantané affiché, décision
    6) dans `p.join((await getApplicationCacheDirectory()).path, 'popkino_recent_requests', 'titles_<lang>.json')` ;
  - lecture paresseuse au premier `rowFor` (ouverture d'une bibliothèque), jamais au démarrage ;
  - écriture différée de 2 s et regroupée ; 300 entrées au plus ; 30 jours ;
  - champ `version: 1` (fichier ignoré s'il est différent) ; fichier illisible → supprimé et ignoré ;
  - aucun `JsonPref` ni préférence.
- Tests : aller-retour, version différente, fichier corrompu, plafond et expiration, aucune lecture avant `rowFor`.
- Critères d'acceptation couverts : CA8, CA17 (performances à froid).

### T10 — Badges de la rangée
- Complexité : M (logique d'états avec priorité, crochet dans un fichier upstream très actif, contraste vérifié par
  test)
- Dépend de : T7 (et T4, T4b : même fichier `recent_requests_repository.dart`), T6 (mêmes fichiers de traduction)
- Fichiers :
  - créer `lib/fork/recent_requests/recent_request_badge.dart`
  - modifier `lib/fork/recent_requests/recent_requests_repository.dart` (fork)
  - modifier `lib/widgets/media_card.dart` (**upstream**, 2 lignes marquées)
  - modifier `lib/fork/i18n/fr.json`, `lib/fork/i18n/en.json` ; fichiers régénérés `lib/i18n/*.i18n.json`,
    `lib/i18n/strings*.g.dart`
  - créer `test/fork/recent_requests/recent_request_badge_test.dart`
  - modifier `test/fork/recent_requests/recent_requests_repository_test.dart`,
    `test/fork/recent_requests/hooks_test.dart`
- À faire dans `recent_request_badge.dart` (en-tête `// FORK: demandes-recentes-overseerr — …` comme les voisins) :
  - `const String kForkRequestBadgeRawKey = 'popkinoRequestBadge';`
  - `enum ForkRequestBadge { available, partial, processing, requested, pending, failed, declined, deleted, blocked }`,
    déclaré dans l'ordre de base de CA7e, plus `blocked` (CA7f). L'exception de CA7e (« Supprimé ») fait que
    l'index n'est **pas** un rang suffisant : la priorité est l'algorithme ci-dessous, figé par la table de tests.
  - Fonction pure `ForkRequestBadge? forkRequestBadgeFor(ForkRecentRequest r, SeerrProduct product)`. Les codes média
    se lisent par `SeerrMediaStatus.resolve(code, product)` (6 et 7 diffèrent entre Overseerr et Jellyseerr), sur
    `mediaStatusCode` **et** `mediaStatus4kCode` (le badge ne distingue pas la 4K dans la rangée). Les demandes
    sont `r.myRequests` (toutes, HD et 4K). États applicables, calqués sur
    `SeerrCatalogSource._requestState` / `_availability` pour garder le même sens qu'Explorer :
    - `available` : un des deux statuts vaut `available` ;
    - `partial` : un des deux statuts vaut `partiallyAvailable` ;
    - `processing` (**règle remplacée par T11, CA7g**) : un des deux statuts vaut `processing`, **sauf** si, pour ce palier (`is4k`), il existe une
      demande `failed` et aucune `approved` (statut périmé, même règle que `_requestState`) ;
    - `requested` : une demande `approved`, ou un statut média `pending` (code 2 = demande approuvée en file) ;
    - `pending` : une demande `pending` (attente d'approbation) ;
    - `failed` : une demande `failed` ; `declined` : une demande `declined` ;
    - `deleted` : un des deux statuts vaut `deleted` ;
    - `blocked` : un des deux statuts vaut `blocklisted` (Jellyseerr code 6, ou code 6/7 quand le produit est
      `SeerrProduct.unknown`, cf. `SeerrMediaStatus.resolve`) ;
    - `completed` et `unknown` ne rendent aucun état applicable.

    Choix du badge, dans cet ordre (premier qui s'applique) :
    1. `available`, puis `partial`, puis `processing` ;
    2. si `deleted` s'applique : `pending` s'il y a une demande en attente d'approbation, sinon `deleted`
       (exception CA7e : une ancienne demande `approved`, `failed` ou `declined` ne passe pas devant) ;
    3. si `blocked` s'applique : `blocked` (CA7f, sans exception) ;
    4. `requested`, puis `pending`, puis `failed`, puis `declined` ;
    5. sinon `null` : aucun badge (CA7f, seule exception à « exactement un »).

    La priorité règle « Disponible + Demandé » : une demande restée `approved` après l'arrivée du titre donne
    `available` ; après la suppression du titre, elle donne `deleted`.
  - `extension ForkRequestBadgeX on ForkRequestBadge` avec `String get label` (via
    `t.fork.recentRequests.badge.*`), `Color get background` et `Color get foreground`, constantes **opaques**
    (le contraste ne dépend jamais de l'affiche) :

    | État | Fond | Texte | Contraste calculé |
    |---|---|---|---|
    | available | `0xFF1B7F3B` (vert) | blanc | 5,1:1 |
    | partial | `0xFF1565C0` (bleu) | blanc | 5,8:1 |
    | processing | `0xFFFB8C00` (orange) | `0xFF000000` | 8,9:1 |
    | requested | `0xFF6A1B9A` (violet) | blanc | 9,4:1 |
    | pending | `0xFFF9C80E` (jaune) | `0xFF000000` | 13:1 |
    | failed, declined, deleted, blocked | `0xFFC62828` (rouge) | blanc | 5,6:1 |

    Le blanc sur orange (2,4:1) échoue : l'orange et le jaune ont un texte noir.
  - `Widget? forkPosterBadge(Object item)` : `null` si `item` n'est pas un `MediaItem` ou si
    `item.raw?[kForkRequestBadgeRawKey]` n'est pas le `name` d'une valeur de l'enum (`ForkRequestBadge.values
    .asNameMap()`). Sinon, un `Positioned(key: Key('fork-request-badge'), top: 6, left: 6, right: 6)` (mêmes marges
    que `_CatalogBadges`, pour rester enfant direct du `Stack`) contenant, aligné à gauche, **un seul** badge :
    `DecoratedBox` (fond de l'état, rayon 4), padding horizontal 6 / vertical 3, `Text(label, maxLines: 1,
    softWrap: false)` en `fontSize: 11`, `fontWeight: .w700`, `height: 1`, couleur `foreground`, **sans
    ellipsis**, enveloppé dans `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft)` : un texte trop
    large rapetisse au lieu d'être coupé (CA7). Pas de `Semantics` propre : l'overlay est déjà sous
    `ExcludeSemantics` dans `MediaCard`.
- À faire dans `recent_requests_repository.dart` (boucle `for (final (request, summary) in retained)` de `rowFor`) :
  - calculer `final badge = forkRequestBadgeFor(request, client.session.product);` (même source du produit que
    `_isAvailable`) ;
  - remplacer `final item = catalogItem.toMediaItem();` par
    `final base = catalogItem.toMediaItem();` puis
    `final item = badge == null ? base : base.copyWith(raw: {...?base.raw, kForkRequestBadgeRawKey: badge.name});`
    L'`id` ne change pas (clé de `entriesByItemId`) ; `entry.catalogItem` reste complet, la fiche Explorer ouverte par
    T5 garde donc ses badges et son bouton de demande (CA7c).
- À faire dans `lib/widgets/media_card.dart` (upstream, D3/D11), exactement :
  1. ajouter l'import `import '../fork/recent_requests/recent_request_badge.dart'; // FORK: demandes-recentes-overseerr`
  2. dans `_buildPosterStack`, remplacer la ligne
     `if (badgeLabels.isNotEmpty) _CatalogBadges(labels: badgeLabels),` par
     ```dart
     if (forkPosterBadge(item) case final Widget forkBadge) forkBadge else if (badgeLabels.isNotEmpty) _CatalogBadges(labels: badgeLabels), // FORK: demandes-recentes-overseerr — single short colored badge in the recent-requests row
     ```
     `dart format` peut couper la ligne : remettre alors le marqueur sur chaque ligne produite.
  Ne rien changer d'autre : ni `_buildCatalogBadgeLabels`, ni `_CatalogBadges`, ni `_catalogBadgeLimit`, ni les
  textes `t.explore.badge.*`.
- Traductions (D6 : jamais d'édition de `lib/i18n/*.json`) : ajouter sous `fork.recentRequests` un objet `badge`,
  dans cet ordre de clés :

  | Clé | fr | en |
  |---|---|---|
  | available | Disponible | Available |
  | partial | Partiel | Partial |
  | processing | En cours | In progress |
  | requested | Demandé | Requested |
  | pending | En attente | Pending |
  | failed | Échec | Failed |
  | declined | Refusé | Declined |
  | deleted | Supprimé | Deleted |
  | blocked | Bloqué | Blocked |

  puis `python3 scripts/fork/rebrand_i18n.py` et `scripts/codegen.sh`, comme T6.
- Tests :
  - `recent_request_badge_test.dart`, pur (sans réseau) :
    - table de cas sur `forkRequestBadgeFor` : statut 5 + demande `approved` → `available` (constat de recette) ;
      statut 4 + `approved` → `partial` ; statut 3 → `processing` ; statut 3 + `failed` sans `approved` → `failed` ;
      statut 2 → `requested` ; statut 1 + `pending` → `pending` ; `pending` + `approved` → `requested` (CA7e) ;
      `declined` seul → `declined` ; 4K seule disponible (HD 1) → `available` (4K non distinguée) ;
    - « Supprimé » (CA7e) : Overseerr code 6 seul → `deleted` ; Jellyseerr code 7 → `deleted` ; Overseerr 6 +
      `approved` → `deleted` ; 6 + `failed` → `deleted` ; 6 + `declined` → `deleted` ; 6 + `pending` → `pending` ;
      6 + `approved` + `pending` → `pending` ; HD 6 + 4K 5 → `available` ;
    - « Bloqué » (CA7f) : Jellyseerr code 6 → `blocked`, y compris avec `approved` ou `pending` ; produit `unknown`
      et code 6 ou 7 → `blocked` ; Overseerr code 7 → `null` ;
    - aucun badge (CA7f) : statut 1 + `completed` → `null` ; aucun statut ni demande → `null`, et le dépôt ne pose
      alors pas la clé ;
    - contraste : pour chaque valeur, `(L1 + 0,05) / (L2 + 0,05)` calculé par `Color.computeLuminance()` ≥ 4,5 ;
      fonds opaques (`alpha == 255`) ; `failed`, `declined`, `deleted`, `blocked` partagent le rouge, les cinq
      autres couleurs sont distinctes ;
    - libellés : en `fr` puis en `en` (`LocaleSettings.setLocale`), chaque `label` est non vide et ne contient ni
      « … » ni plus de 11 caractères ;
    - widget : `MediaCard` (TV et non-TV) sur un `MediaItem` portant la clé, largeur de carte 100 px, pour chaque
      valeur et chaque langue : exactement un `Key('fork-request-badge')`, aucun `Key('catalog-badges')`, le texte
      complet trouvé par `find.text(label)`, et aucun `Text` du badge avec `overflow: TextOverflow.ellipsis` ;
    - non-régression Explorer : le **même** `CatalogItem` (statut 5 + demande `approved`) sans la clé affiche
      `Key('catalog-badges')` avec « Disponible » **et** « Demandé » (empilement upstream inchangé) et aucun
      `Key('fork-request-badge')` ; clé inconnue (`'foo'`) → comportement upstream.
  - `recent_requests_repository_test.dart` : les éléments du hub portent `raw[kForkRequestBadgeRawKey]` attendu
    (dont `available` pour statut 5 + `approved`, `deleted` pour code 6 Overseerr + `approved`) ; un élément sans
    état reconnaissable n'a pas la clé et reste dans la rangée sans badge (CA7f) ; `entriesByItemId[item.id]` est
    toujours trouvé ; `entry.catalogItem.serverState` inchangé.
  - `hooks_test.dart` : `lib/widgets/media_card.dart` contient `forkPosterBadge(item)` et l'import, chaque ligne
    porte `FORK: demandes-recentes-overseerr`, et `_CatalogBadges(labels: badgeLabels)` est toujours présent.
  - Upstream : `scripts/run_tests.sh test/widgets/` (dont les `media_card_*_test.dart`) et `test/screens/` restent
    verts ; puis toute la suite (fichier upstream partagé modifié).
  - Contrôles : `dart format` des fichiers touchés, `scripts/codegen.sh --check`,
    `python3 scripts/checks/clean_translations.py --check --strict`, `dart run scripts/checks/check_analyzer.dart`,
    `bash scripts/ci_guard_checks.sh` (dont `check_hardcoded_strings.py`).
- Critères d'acceptation couverts : CA7, CA7b (textes « Refusé », « Échec »), CA7c (badge ; l'ouverture reste T5),
  CA7d, CA7e (dont l'exception « Supprimé »), CA7f, CA13 (badge recalculé à chaque liste fraîche). La 4K n'est pas
  distinguée dans la rangée (hors périmètre de la spec).

### T10b — Reprise de la recette TV des badges
- Complexité : M
- Dépend de : T10
- Fichiers : aucun fichier de code ; compte rendu dans la réponse de l'agent, avec photos ou `screencap` des rangées.
- À faire :
  - bloc « Vérification globale » (le décompte `FORK: demandes-recentes-overseerr` compte désormais **4** fichiers
    upstream), build et installation sur la Fire TV Stick comme T8 (`armeabi-v7a`, `--no-tree-shake-icons`) ;
  - préparation Overseerr (utilisateur) : au moins un titre par état, dont un « Supprimé » dont la demande est
    restée « approuvée », un disponible dont la demande est restée « approuvée », un partiellement disponible, un en attente d'approbation, un en cours, un
    refusé et un en échec ; une série et un film au minimum ;
  - `adb exec-out screencap -p` de chaque rangée (Films, Séries, Animés), puis contrôle **à 3 m** sur la TV :
    1. CA7 : chaque affiche a exactement un badge, texte entier (« En attente », « Partiel », « En cours », jamais
       de « … ») ; le titre disponible à demande « approuvée » montre seulement « Disponible » ;
    2. CA7c, CA7e : le titre supprimé montre « Supprimé » en rouge, même avec sa demande « approuvée » ; OK ouvre la fiche Explorer avec le bouton de demande,
       sans écran d'erreur ; Retour revient sur la même affiche (CA12) ;
    3. CA7d : couleurs conformes (vert, bleu, jaune, violet, orange, rouge), texte lisible sur chaque fond, y compris
       avec le focus sur l'affiche ; ouvrir **Explorer** et vérifier que ses badges sont inchangés (fond noir,
       textes longs, « Disponible » + « Demandé » empilés possibles) ;
    4. CA7e : faire évoluer un titre (approbation d'une demande en attente, arrivée d'un titre), attendre 30 s,
       rouvrir la bibliothèque : le badge suit l'ordre de priorité (CA13) ;
    5. langue de l'app en anglais : badges courts entiers (« In progress », « Available »…).
  - reprendre aussi les étapes 6 (D-pad) et 9 (insertion tardive) de la recette T8 : le badge ne change ni le focus
    ni la taille des affiches.
  - « Bloqué » (CA7f, Jellyseerr) n'est couvert que par les tests automatisés : l'utilisateur n'a pas de Jellyseerr.
- Critères d'acceptation couverts : CA7, CA7b, CA7c, CA7d, CA7e sur l'appareil réel ; CA7f par les tests (plus
  CA12, CA13, CA14 en non-régression).

### T11 — « En cours » seulement pendant un téléchargement réel (CA7g)
- Complexité : S
- Dépend de : T10 (mêmes fichiers)
- Constat : Overseerr affiche « Processing » seulement si `inProgress`, c'est-à-dire si
  `media.downloadStatus` (ou `downloadStatus4k` pour une demande 4K) est une liste non vide ; sinon il affiche
  « Requested » (`src/components/StatusBadge/index.tsx`, `src/components/RequestList/RequestItem/index.tsx`). Ces deux
  champs sont calculés à chaque chargement du média (`@AfterLoad getDownloadingItem`, `server/entity/Media.ts`, à
  partir du suivi Sonarr/Radarr) et **sont déjà présents dans la réponse `GET /request`** que la rangée lit (la page
  « Demandes » d'Overseerr s'en sert). Jellyseerr a les mêmes champs. **Aucun appel réseau supplémentaire.**
- Fichiers :
  - modifier `lib/fork/recent_requests/recent_request.dart`
  - modifier `lib/fork/recent_requests/recent_request_badge.dart`
  - modifier `test/fork/recent_requests/recent_request_test.dart`,
    `test/fork/recent_requests/recent_request_badge_test.dart`,
    `test/fork/recent_requests/recent_requests_repository_test.dart`
- À faire :
  - `ForkRecentRequest` : ajouter `final bool downloading;` et `final bool downloading4k;` (défaut `false`).
    `_build` les lit dans le JSON brut du média : `media['downloadStatus'] is List && (… as List).isNotEmpty`, idem
    `downloadStatus4k`. Champ absent, `null` ou d'un autre type → `false`, sans exception. La fusion de
    `parseRecentRequests` reprend les valeurs de l'entrée la plus récente (`existing`), comme les statuts.
    `mediaInfo` ne change pas (ces champs n'existent pas dans `SeerrMediaInfo`, aucun modèle upstream touché).
  - `forkRequestBadgeFor`, par palier (HD : `mediaStatusCode` / `downloading` ; 4K : `mediaStatus4kCode` /
    `downloading4k`) :
    - `processing` : statut `processing` **et** téléchargement en cours sur ce palier. Un téléchargement réel
      l'emporte sur la règle du statut périmé (Overseerr affiche alors « Processing ») ;
    - statut `processing` **sans** téléchargement : contribue à `requested` (violet), sauf si la règle du statut périmé
      s'applique sur ce palier (demande `failed` sans `approved`), auquel cas rien n'est ajouté et `failed` sort plus
      bas, comme aujourd'hui ;
    - `requested` devient : demande `approved` **ou** statut `pending` **ou** statut `processing` sans téléchargement
      et non périmé ;
    - l'ordre de choix de T10 ne change pas (`processing` reste juste après `partial`). Si l'app ne peut pas savoir
      (champ absent, vieille version d'Overseerr, Sonarr/Radarr injoignable) → « Demandé » (CA7g).
  - Mettre à jour le commentaire de tête de `forkRequestBadgeFor` (règle CA7g, en anglais).
- Tests :
  - `recent_request_test.dart` : `downloadStatus` non vide → `downloading == true` ; liste vide, absent, `null`,
    objet ou chaîne → `false` ; idem `downloadStatus4k` ; fusion de deux demandes du même titre → valeurs de la plus
    récente.
  - `recent_request_badge_test.dart` : statut 3 sans téléchargement + `approved` → `requested` (cas Invincible) ;
    statut 3 sans téléchargement ni demande → `requested` ; statut 3 + `downloading` → `processing` ; statut 3 HD sans
    téléchargement + 4K statut 3 + `downloading4k` → `processing` ; statut 3 + `downloading4k` seul (HD non
    `processing`) → pas `processing` ; statut 3 + `failed` sans `approved`, sans téléchargement → `failed` ; même cas
    avec `downloading` → `processing` ; statut 3 sans téléchargement + `pending` → `requested` (Demandé avant En
    attente, CA7e) ; les autres cas de T10 inchangés (reprendre la table, en corrigeant ceux qui attendaient
    `processing` sans téléchargement).
  - `recent_requests_repository_test.dart` : une fixture `GET /request` réelle d'Overseerr avec `downloadStatus: []`
    et statut 3 donne `raw[kForkRequestBadgeRawKey] == 'requested'` ; avec un élément dans `downloadStatus`,
    `'processing'`.
  - `scripts/run_tests.sh test/fork/recent_requests/`, `dart format`, `dart run scripts/checks/check_analyzer.dart`.
- Recette TV (Fire TV Stick, build comme T8) :
  1. Invincible : « Demandé » sur violet dans la rangée, comme sur Overseerr (CA7g) ;
  2. lancer la demande d'un petit film, puis rouvrir la bibliothèque toutes les 30 s : « Demandé » (violet) tant que
     Radarr n'a pas commencé, « En cours » (orange) pendant le téléchargement **en même temps qu'Overseerr affiche
     « Processing »**, puis « Disponible » ; noter le décalage observé (fraîcheur 30 s de la liste, plus le suivi
     d'Overseerr) ;
  3. vérifier sur Overseerr que chaque titre de la rangée a le même libellé (aux textes courts près).
- Critères d'acceptation couverts : CA7g (et CA7e, CA13 en non-régression).

## Vérification globale

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
dart format <fichiers modifiés>
scripts/codegen.sh && scripts/codegen.sh --check
python3 scripts/checks/clean_translations.py --check --strict
dart run scripts/checks/check_analyzer.dart
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh test/fork/recent_requests/
scripts/run_tests.sh            # toute la suite : un fichier upstream de l'onglet est modifié
grep -rn "FORK: demandes-recentes-overseerr" lib | wc -l   # 3 fichiers upstream + en-têtes du fork
```

**Build et installation (Fire TV Stick, `armeabi-v7a`, sans `--dart-define-from-file` : pas de
`popkino_secrets.json` sur le Mac ; `--no-tree-shake-icons` est obligatoire sur ce Mac, et sans effet sur la CI)**

```bash
ADB=~/Library/Android/sdk/platform-tools/adb; PKG=io.github.adrien24.popkino
$ADB connect 192.168.1.173:5555
flutter build apk --release --split-per-abi --no-tree-shake-icons --dart-define=ENABLE_UPDATE_CHECK=true
APK=build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
$(ls -d ~/Library/Android/sdk/build-tools/* | tail -1)/apksigner sign --ks ~/.android/debug.keystore \
  --ks-pass pass:android --ks-key-alias androiddebugkey "$APK"
$ADB -s 192.168.1.173:5555 install -r "$APK"
```

Si le build modifie `pubspec.lock`, ne pas le commiter et prévenir l'orchestrateur (aucun `git checkout`).
Activer « journaux de débogage » dans l'app, puis `$ADB logcat -c` ; garder
`$ADB logcat -v time | grep -E "Seerr (GET|POST)|RecentRequests"` dans un second terminal.

**Préparation sur Overseerr (par l'utilisateur, avec le compte de l'app)** :
- demandes : un film, une série, une série animée japonaise, un film Ghibli, Les Simpson ;
- états : une demande disponible, une partiellement disponible, une refusée, une en échec, une « disponible » dont le
  titre a été supprimé de Plex ;
- une demande faite par **un autre** utilisateur ;
- côté Plex : deux bibliothèques de séries si possible (CA5b), et une bibliothèque vide de test si possible (CA16b).

**Recette** (comparer à l'APK `main` pour les étapes 1 et 2) :
1. Démarrage : 5 fois `am force-stop` puis `am start -W -n $PKG/com.edde746.plezy.MainActivity`.
   - Médiane de `TotalTime` à ± 10 % de celle de l'APK `main`.
   - Aucun `Seerr GET /request` avant l'ouverture d'une bibliothèque.
2. Premier chargement de Séries.
   - Les rangées habituelles apparaissent comme avant.
   - Le journal montre 1 `GET /request`, puis des `GET /tv/…`, jamais plus de 4 en parallèle.
   - Rangée visible en moins de 5 s pour 20 titres (sinon lancer T9).
   - Gauche / Droite reste fluide pendant le chargement.
3. Films, Animés, puis Séries en moins de 30 s : aucun nouveau `/request` ; rouvrir Séries ne lit aucune fiche.
4. Contenu des rangées (CA1 à CA3e, CA5, CA5b, CA6, CA7, CA7b) :
   - le film Ghibli est dans Animés et pas dans Films ; Les Simpson sont dans Séries ;
   - la demande de l'autre utilisateur est absente ;
   - les badges sont lisibles à 3 m, dont « Refusé » et « Échec de la demande » ;
   - même rangée dans les deux bibliothèques de séries ; la bibliothèque vide garde son message.
5. Ouverture (CA8, CA10, CA11) : `screenrecord` pendant OK, 5 titres disponibles différents. Mesurer image par image
   le temps jusqu'à la fiche avec ses saisons ou le bouton Lire : moins de 3 s. Puis une série partiellement
   disponible, puis le titre supprimé (→ Explorer, sans écran d'erreur).
6. Retour (CA12) : depuis la fiche serveur et depuis la fiche Explorer, le focus revient sur la même affiche.
   D-pad (CA14) : Bas, Haut, Bas, focus toujours visible.
7. Panne (CA17) : arrêter Overseerr, attendre 60 s, ouvrir Films.
   - Les rangées s'affichent dans le même temps qu'à l'étape 2, sans la rangée et sans message.
   - Séries et Animés aussitôt après : aucun nouveau `/request`.
   - Redémarrer Overseerr et attendre 60 s : la rangée revient.
8. Fraîcheur (CA13) : rendre une demande disponible, attendre 30 s, rouvrir : badge « Disponible », et OK ouvre la
   fiche serveur.
9. Insertion tardive : force-stop, ouvrir Séries et appuyer aussitôt plusieurs fois sur Bas. Le focus ne saute pas,
   n'est jamais perdu, et Retour reste normal.
10. Mémoire : `dumpsys meminfo $PKG | grep -E "TOTAL PSS|TOTAL:"` après l'étape 2, puis après 5 cycles Films →
    Séries → Animés avec ouverture d'une demande :
    - moins de 10 Mo d'écart entre le premier et le cinquième cycle (pas de fuite) ;
    - moins de 20 Mo d'écart avec la même navigation quand Overseerr est déconnecté (coût de la fonction).
11. Sans Overseerr (déconnecté dans les réglages) : aucune rangée et aucun appel (CA15) ; bibliothèque musique :
    aucune rangée (CA18).

## Risques restants

- **Lien `plexUrl` quand Overseerr est relié à un autre serveur Plex que celui de l'app** : le `machineId` ne
  correspond à rien, et l'on passe par la vérification du tmdbId (un appel de plus) ou par le repli
  `CatalogLibraryMatcher`, plus lent. Si l'ouverture dépasse 3 s, on active le préchargement au focus (> 600 ms)
  par l'existant `TvBrowseRail.onFocusedItemChanged`, en tâche complémentaire.
- **Bibliothèque Animés sous Jellyfin** : `fetchItem` Jellyfin peut ne pas renseigner `libraryId` ; la
  reconnaissance retombe alors sur le nom. C'est acceptable (pas de Jellyfin réel), et couvert par un test.
- **Bibliothèque nommée « Films d'animation »** prise pour la bibliothèque Animés tant qu'aucun animé n'y est arrivé :
  limite acceptée par le PO.
- **Premier chargement à froid de la bibliothèque Animés** : jusqu'à 100 fiches, sous le budget de 15 s, avec une
  rangée partielle possible. Le remède prévu est T9.
- **Fusion upstream** : le renommage de `buildContent` en `_buildContentWith` est l'endroit le plus exposé (6 commits
  upstream sur ce fichier depuis août) ; on résout en replaçant la délégation, et `hooks_test.dart` signale un
  crochet perdu. Les deux méthodes Seerr sont en fin de section, avec un conflit improbable.
- **Crochet de badge dans `media_card.dart`** (T10) : fichier upstream très actif (14 commits depuis août). Le
  crochet tient sur la ligne de `_CatalogBadges` ; en conflit, la replacer devant l'overlay upstream.
  `hooks_test.dart` signale un crochet perdu. Si l'upstream renomme `_CatalogBadges` ou déplace les overlays, le test
  de non-régression Explorer de T10 casse au lieu de laisser passer un double badge.
- **Compatibilité API** : une version d'Overseerr qui ignorerait `requestedBy` est couverte par le refiltrage côté
  client. Un changement de forme de `GET /request` fait disparaître la rangée (CA17), sans casse.
