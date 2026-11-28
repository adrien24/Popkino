# Proposition app — demandes-recentes-overseerr

Auteur : architecte-app · 2026-11-28 · Spec : `docs/produit/specs/demandes-recentes-overseerr.md`

## Compréhension de la spec

Dans l'onglet d'accueil d'une bibliothèque Films / Séries / Animés, on ajoute une rangée « Demandes récentes », juste
sous « Continuer à regarder ». Elle contient les 20 dernières demandes Overseerr/Jellyseerr **de l'utilisateur
connecté**, du type de la bibliothèque, chacune avec un badge d'état. Sur OK : la fiche serveur si le titre est
(partiellement) disponible et retrouvé, sinon la fiche Explorer. Les animés (mot-clé TMDB 210024) vont dans la
bibliothèque Animés, reconnue automatiquement.

CA de mon périmètre : tous (CA1 à CA20). Le natif n'est pas concerné : pas de Kotlin, pas de permission, pas de
dépendance ajoutée, aucune différence entre canaux (cf. « Contraintes » de la spec). Le seul point plateforme est la
mesure des performances sur la Fire TV Stick (CA8, CA17).

## Existant (lu dans le code)

**Client Seerr**
- `lib/services/seerr/seerr_client.dart`, `SeerrClient` : toutes les requêtes passent par `_request()` (privé), qui
  gère la ré-authentification silencieuse, le cookie et les sondes `/auth/me`. **Aucune méthode publique ne liste les
  demandes** (`GET /request`). Les méthodes publiques `getMovie` / `getTv` renvoient un `SeerrDetails` typé.
- `lib/services/seerr/seerr_constants.dart` : `SeerrConstants.animeKeywordId = 210024`, déjà utilisé dans
  `lib/widgets/seerr_request_sheet.dart:288` (`tv.keywords?.any((k) => k.id == SeerrConstants.animeKeywordId)`).
- `lib/models/seerr/` : `SeerrDetails` (avec `keywords`, `externalIds`, `mediaInfo`), `SeerrMediaInfo` (statut brut,
  saisons, `requests`), `SeerrRequest` / `SeerrRequestStatus` (1 à 5), `SeerrPage` (sait lire la forme
  `{pageInfo, results}` de `GET /request`), `SeerrSession.userId`. `SeerrMediaInfo` **n'expose pas** `ratingKey`
  (Plex) ni `jellyfinMediaId` (Jellyseerr).
- `lib/services/catalog/seerr_catalog_source.dart`, `SeerrCatalogSource` : la conversion `SeerrDetails` →
  `CatalogItem` (`_toDetailCatalogItem`), l'état serveur (`_serverState`, `_requestState`, `_availability`) et
  l'origine des images (`_tmdbImageOrigin`, proxy d'images de l'instance ou CDN TMDB) sont **privés** (~150 lignes de
  règles fines : codes 6/7 selon le produit, priorité « échec » / « approuvé », saisons).
- `lib/providers/catalog_sources_provider.dart` : `CatalogSourcesProvider.seerrSource` (null si Seerr non relié).

**Rendu des titres du catalogue**
- `CatalogItem.toMediaItem()` (`lib/models/catalog/catalog_item.dart:487`) fabrique un `MediaItem` de rendu (sans
  `serverId`, `raw[CatalogItem.rawKey]`), reconnu par `isCatalogItem` (`lib/media/catalog_item_ref.dart`).
- `MediaCard` (`lib/widgets/media_card.dart:1400`, `_buildCatalogBadgeLabels`) affiche **déjà** les badges d'un
  élément catalogue à partir de `serverState` : `t.explore.badge.available`, `partiallyAvailable`,
  `seasonsAvailable`, `requested`, `pendingApproval`, `processing`, `declined` (« Refusé »), `requestFailed`
  (« Échec de la demande »). C'est exactement le vocabulaire de la fiche Explorer (CA7, CA7b) : rien à créer.
- `navigateToMediaItem` (`lib/utils/media_navigation_helper.dart:211`) envoie un élément catalogue vers
  `navigateToCatalogItem` → `CatalogItemDetailScreen` ; `navigateToMediaItemDetails` ouvre `MediaDetailScreen` pour
  un élément serveur.

**Correspondance titre externe → bibliothèque**
- `lib/services/catalog/catalog_library_matcher.dart`, `CatalogLibraryMatcher.match(CatalogItem)` : recherche par
  identifiants externes (tmdb/imdb/tvdb) + titres sur tous les serveurs (`findByExternalIdsAcrossServers`), résultats
  vérifiés par identifiant, **mis en cache pour la session** (positifs gardés, négatifs 10 min). Fourni par profil
  dans `lib/navigation/profile_session_screen.dart:249`. C'est celui qu'utilise la fiche Explorer
  (`catalog_item_detail_screen.dart:195`) : le réutiliser partage le cache.

**Onglet d'accueil de bibliothèque**
- `lib/screens/libraries/tabs/library_recommended_tab.dart`, `_LibraryRecommendedTabState` :
  `_loadRecommendedHubs()` charge les hubs serveur et met le hub « Continuer à regarder » en tête ;
  `buildContent(items)` rend `HubSection` (hors TV) ou `_buildTvContent` → `TvSpotlightScaffold` + `TvBrowseRail`
  (TV). La même instance d'état sert à toutes les bibliothèques (`_recommendedTabKey` dans `libraries_screen.dart:453`,
  remise à zéro dans `didUpdateWidget` sur changement de `library.globalKey`).
- Points d'extension existants **non utilisés** par cet onglet : `TvBrowseRail.onActivateItem`
  (`FutureOr<bool> Function(MediaHub, MediaItem)`, `tv_browse_rail.dart:1203` : si `true`, la navigation upstream
  n'a pas lieu) et `HubSection.onItemTap` (couvre D-pad **et** clic/toucher, `hub_section.dart:427` et `:774`).
- `TvBrowseRail.didUpdateWidget` (`tv_browse_rail.dart:561-583`) conserve le hub actif **par clé** (`serverId:id`)
  quand la liste des hubs change : une rangée insérée tard ne déplace pas le focus.
- L'écran Explorer (`lib/screens/explore_screen.dart`) montre que des `MediaHub` de `MediaItem` catalogue passent tels
  quels dans `TvBrowseRail` et `TvSpotlightScaffold` (affiche, fond, titre au focus).
- `LibrariesProvider.libraries` : toutes les bibliothèques (nom, `kind`, `serverId`) pour reconnaître « Animés ».
- Persistance légère du fork : `JsonPref` (`lib/services/base_shared_preferences_service.dart:603`), déjà utilisé
  par `lib/fork/track_choice_memory.dart`.

**API Overseerr / Seerr vérifiée dans les sources** (`sct/overseerr` `server/routes/request.ts`,
`seerr-team/seerr` `server/entity/Media.ts`)
- `GET /api/v1/request?take&skip&filter&sort&requestedBy` ; `filter` absent = tous les statuts (en attente, approuvé,
  refusé, échec, terminé) ; tri par `request.id DESC` (le plus récent d'abord) ; réponse `{pageInfo, results}` ;
  chaque demande inclut `media` (statut, `status4k`, `tmdbId`, `tvdbId`, `ratingKey` / `jellyfinMediaId`) et
  `requestedBy`. Un compte sans `MANAGE_REQUESTS`/`REQUEST_VIEW` est limité à ses demandes ; **un administrateur voit
  tout sauf s'il passe `requestedBy`** (CA6). Pas de filtre `mediaType` côté Overseerr : le tri par type se fait chez
  nous.
- La demande ne porte ni titre, ni affiche, ni mot-clé : il faut `GET /movie/{id}` ou `GET /tv/{id}` (qui contient
  `keywords` pour les films **et** les séries, `server/models/Movie.ts:147`).

## Approche proposée

### Vue d'ensemble

Tout le code dans `lib/fork/recent_requests/` (D2, D13), tests dans `test/fork/recent_requests/`. Trois fichiers
upstream touchés, ~13 lignes, toutes marquées `// FORK: demandes-recentes-overseerr — …` :

| Fichier upstream | Changement | Pourquoi |
|---|---|---|
| `lib/services/seerr/seerr_client.dart` | +1 méthode publique `Future<dynamic> getJsonForFork(String path, {Map<String, Object?>? query}) => _request('GET', path, query: query);` | Lister les demandes et lire les champs non modélisés (`ratingKey`, `jellyfinMediaId`, `requestedBy`) **avec** la ré-authentification silencieuse. |
| `lib/services/catalog/seerr_catalog_source.dart` | +1 méthode publique `Future<CatalogItem> catalogItemFromDetailsForFork(SeerrDetails d, MediaKind kind) async => _toDetailCatalogItem(d, kind, await _tmdbImageOrigin());` | Réutiliser la conversion et l'état serveur privés au lieu de dupliquer ~150 lignes qui divergeraient. |
| `lib/screens/libraries/tabs/library_recommended_tab.dart` | `buildContent` délègue à un widget du fork ; 3 paramètres ajoutés (`onActivateItem`, `onItemTap`, icône) | Insérer la rangée au rendu et intercepter OK sur ses affiches. |

Ce sont des crochets « null = upstream » au sens de D11 : sans Seerr, sans demande ou en cas d'erreur, le widget du
fork rend exactement la liste de hubs upstream et les rappels renvoient `false` / `null`.

### 1. Données : `ForkRecentRequestsRepository` (`recent_requests_repository.dart`)

Un seul chargement sert les trois bibliothèques (Films, Séries, Animés).

1. `client.getJsonForFork('/request', query: {'take': 100, 'skip': 0, 'sort': 'added', 'requestedBy': session.userId})`.
   On **refiltre aussi côté client** sur `requestedBy.id == session.userId` (défense contre une instance ancienne qui
   ignorerait le paramètre : CA6).
2. Lecture par `parseRecentRequests()` (`recent_request.dart`, pur) → `ForkRecentRequest` : `requestId`, `createdAt`,
   `mediaType`, `tmdbId`, `status` (`SeerrRequestStatus.fromCode`), `is4k`, `mediaJson` (bloc `media` brut). Doublons
   (une demande par saison, HD + 4K) regroupés par `(mediaType, tmdbId)` : on garde la position de la plus récente et
   on joint toutes les demandes de l'utilisateur sur ce média.
3. Fiche du titre pour chaque média (titre, affiche, mot-clé anime) :
   `getJsonForFork('/movie|tv/$tmdbId', query: {'language': LocaleSettings.currentLocale.plexLanguageCode})`, 4 appels
   en parallèle au plus, dans l'ordre des demandes (les plus récentes d'abord). On garde une version **réduite**
   (`id, title, name, originalTitle, originalName, overview, posterPath, backdropPath, releaseDate, firstAirDate,
   voteAverage, imdbId, externalIds`) et le booléen `isAnime = keywords.any(id == SeerrConstants.animeKeywordId)`.
   Un échec sur une fiche fait seulement sauter ce titre pour ce chargement (pas de cache négatif).
4. Construction de l'affiche : `SeerrDetails.fromJson({...ficheRéduite, 'mediaInfo': {...mediaJson, 'requests': [mes
   demandes sur ce média]}})` puis `source.catalogItemFromDetailsForFork(details, kind)` → `CatalogItem` avec
   `serverState` **calculé à partir de la liste fraîche** (CA13) et **de mes seules demandes** (badge Refusé / Échec
   de ma demande, CA7b), puis `toMediaItem()`.

**Caches** (le point qui fait tenir CA8/CA17 sur la Fire TV) :
- Fiches réduites : mémoire + `JsonPref` `fork_recent_requests_details`, clé `<langue>|<movie|tv>:<tmdbId>`, durée
  30 jours, 300 entrées au plus (les plus anciennes sortent). Titre, affiche et mots-clés TMDB ne changent presque
  jamais ; après le premier chargement, un rafraîchissement coûte **un seul appel** (`/request`).
- Dernier instantané de la liste : mémoire + `JsonPref` `fork_recent_requests_snapshot`, clé `baseUrl|userId`. La
  rangée s'affiche **dès la première image** avec l'instantané, puis se met à jour (rafraîchissement « en arrière-plan
  », au plus une fois par 60 s, ou à l'ouverture d'une bibliothèque si l'instantané a plus de 60 s).
- Pas de `ChangeNotifier` global ni de provider : le dépôt est un objet statique de `lib/fork/recent_requests/`, ses
  clés incluent la session Seerr (`baseUrl|userId`), un changement de compte Seerr ne peut donc pas mélanger les
  données. Remplaçable en test par un setter `@visibleForTesting`. **Écart assumé à D13** (qui prévoit un provider
  pour « l'état global ») : ici il n'y a pas d'état observé par plusieurs écrans, seulement un cache ; l'état réactif
  est local au widget de la rangée. Ça évite un crochet dans `main.dart` / `profile_session_screen.dart`.

Premier chargement à froid (aucune fiche en cache) : jusqu'à 100 fiches, 4 en parallèle. La rangée de la bibliothèque
ouverte est publiée **dès que ses 20 éléments sont prêts** ou que la liste est épuisée, sans attendre les autres.

### 2. Classement : `recent_requests_classifier.dart` (fonctions pures)

```dart
enum ForkRequestShelf { movies, shows, anime }

/// Shelf a library displays, or null for music/photos/mixed libraries (CA18).
ForkRequestShelf? shelfForLibrary(MediaLibrary library, {required String? animeLibraryKey});

/// Shelf a request belongs to on [serverId] (CA1-CA3c).
ForkRequestShelf shelfForRequest(ForkRecentRequestEntry e, {required bool serverHasAnimeLibrary});
```

- Bibliothèque : `library.globalKey == animeLibraryKey` → `anime` ; sinon `MediaKind.movie` → `movies`,
  `MediaKind.show` → `shows` ; tout autre `kind` (musique, photos, mixte `unknown`) → `null`, pas de rangée (CA18).
- Demande : animé **et** le serveur a une bibliothèque Animés → `anime` (films et séries mêlés, CA3) ; sinon par type
  (CA3c : rien n'est perdu).
- Rangée = entrées du bon rayon, ordre de la liste (plus récent d'abord), 20 au plus (CA5). Liste vide → pas de hub
  (CA16).

**Reconnaissance de la bibliothèque Animés (CA3d)**, par serveur, `recognizeAnimeLibrary(...)` :
1. *Par les animés arrivés* : parmi les demandes animées disponibles déjà résolues sur le serveur (voir §3), la
   bibliothèque qui en contient le plus. Elle est **rejetée si elle contient aussi un titre non animé du même type
   arrivé par une demande** (bibliothèque mixte, typiquement « Séries ») : sinon l'onglet Séries deviendrait la
   « bibliothèque Animés » et perdrait ses séries. → `QUESTIONS PRODUIT` n° 2.
2. *Sinon par le nom* : première bibliothèque film/série du serveur dont le nom contient `anim`
   (`title.toLowerCase().contains('anim')`, CA3d).
3. Sinon aucune.
Résultat mémorisé (`JsonPref` `fork_recent_requests_anime_library`, `serverId → libraryId`, revalidé si la
bibliothèque disparaît de `LibrariesProvider.libraries` ou après 7 jours) pour que le classement soit stable d'une
ouverture à l'autre et ne coûte rien.

### 3. Résolution vers le titre serveur : `recent_requests_resolver.dart`

- Seules les entrées dont `serverState.availability` (ou `availability4k`) vaut `available` ou `partiallyAvailable`
  sont résolues (CA8, CA10) ; les autres ouvrent la fiche Explorer (CA9, CA7b).
- Résolution = `context.read<CatalogLibraryMatcher?>()?.match(catalogItem)` (identifiants tmdb/imdb/tvdb + titres,
  vérifiés par identifiant, cache de session partagé avec la fiche Explorer). Choix de la copie : même serveur **et**
  même bibliothèque que l'onglet, puis même serveur, puis la première (`compareLibraryCopies`).
- **Pré-résolution en arrière-plan** dès que la rangée est affichée : les entrées disponibles de la rangée, deux à la
  fois, les plus à gauche d'abord. Sur OK, la réponse est en général déjà en cache : ouverture immédiate (CA8 < 3 s).
- Sur OK sans réponse en cache : on attend au plus **2,5 s** ; au-delà, ou si rien n'est trouvé, ou en cas d'erreur
  → fiche Explorer (CA11), jamais d'écran d'erreur. Une seconde pression sur OK pendant l'attente est ignorée.
- Les résolutions d'animés disponibles alimentent aussi la reconnaissance de la bibliothèque Animés (§2.1) : quand
  aucune n'est mémorisée pour un serveur, on résout en arrière-plan jusqu'à 5 animés disponibles, quelle que soit la
  bibliothèque ouverte.

Écarté pour la v1 : utiliser directement `media.ratingKey` / `media.jellyfinMediaId`. Ils désignent l'élément sur
**le** serveur relié à Overseerr, qui n'est pas forcément celui de l'onglet (multi-serveurs), et il faudrait de toute
façon vérifier l'identifiant externe (2 appels, soit le coût du matcher). Le parseur les garde dans `mediaJson` :
c'est une optimisation possible plus tard si la mesure sur la Fire TV l'exige.

### 4. UI : `recent_requests_shelf.dart`

```dart
typedef ForkShelfBuilder = Widget Function(BuildContext context, List<MediaHub> hubs, ForkRequestActivator activator);

class ForkRecentRequestsShelf extends StatefulWidget {
  const ForkRecentRequestsShelf({required this.library, required this.hubs, required this.builder});
}

/// Activation hooks the upstream rail/sections call; `false` / `null` for every hub not owned by the fork.
class ForkRequestActivator {
  FutureOr<bool> activate(BuildContext context, MediaHub hub, MediaItem item); // TvBrowseRail.onActivateItem
  ValueChanged<MediaItem>? tapFor(BuildContext context, MediaHub hub);          // HubSection.onItemTap
  IconData? iconFor(MediaHub hub);                                               // Symbols.playlist_add_check_rounded
}
```

- Le widget lit `context.watch<CatalogSourcesProvider?>()?.seerrSource` (null → `builder(hubs)` inchangé, CA15),
  `context.read<LibrariesProvider?>()`, `context.read<CatalogLibraryMatcher?>()` (lectures nullables : les tests
  upstream sans ces providers restent verts, cf. `conventions-code`).
- Insertion **au rendu**, jamais dans `items` : le hub du fork n'existe pas pour `updateItemInLists`,
  `onWatchStateChanged`, `_removeItemsFromHubs`, `hasFocusableContent` (aucun effet de bord sur la logique upstream).
  Position : juste après le hub d'index 0 s'il est `isContinueWatchingHub` (CA1), sinon en tête (CA4).
- Hub : `MediaHub(id: 'popkino.recentRequests', identifier: 'popkino.recentRequests', title:
  t.fork.recentRequests.title, type: 'mixed', items: …, serverId: library.serverId, more: false)`. L'identifiant ne
  contient ni `continue`, ni `inprogress`, ni `ondeck` (pas de confusion avec `isContinueWatchingHub`). Pas de
  « Voir tout » (hors périmètre).
- Cycle de vie : chargement dans `initState` et quand `library.globalKey` change (**la rangée de l'ancienne
  bibliothèque est vidée immédiatement** : l'état de l'onglet est réutilisé d'une bibliothèque à l'autre) ; jeton de
  génération pour jeter une réponse arrivée après un changement de bibliothèque ; rafraîchissement limité à 1 / 60 s
  quand la liste `hubs` change (rechargement de l'onglet) ou quand l'onglet redevient visible
  (`TickerMode.getValuesNotifier`, comme `BaseLibraryTab`), ce qui couvre CA13 sans réordonner la rangée au retour
  immédiat d'une fiche (CA12). Toute exception → rangée absente + `appLogger.w` (CA17).
- Focus TV (CA12, CA14) : on ne gère aucun nœud de focus. La rangée est un hub de `TvBrowseRail` comme les autres :
  Haut / Bas / Gauche / Droite, Retour (`onBack`), mémoire de position (`HubFocusMemory`), focus visible. Au retour
  d'une fiche, le `Navigator` rend le focus au rail, resté sur la même affiche ; si l'instantané change, le rail suit
  l'élément par sa clé (`didUpdateWidget`). L'arrivée tardive de la rangée ne vole pas le focus (hub actif conservé par
  clé). Les badges sont ceux de `MediaCard`, déjà dimensionnés pour la TV.
- Ouverture : disponible et résolu → `navigateToMediaItemDetails(context, serverItem)` (fiche serveur avec saisons ou
  bouton Lire) ; sinon → `navigateToCatalogItem(context, catalogItem)` (fiche Explorer, qui recharge l'état à jour,
  CA9). L'appui long garde le menu catalogue upstream (`showCatalogItemMenu`).

Diff prévu dans `library_recommended_tab.dart` (esquisse) :

```dart
// FORK: demandes-recentes-overseerr — "Recent requests" row under Continue Watching.
@override
Widget buildContent(List<MediaHub> items) =>
    ForkRecentRequestsShelf(library: widget.library, hubs: items, builder: _buildContentWith);

Widget _buildContentWith(BuildContext context, List<MediaHub> items, ForkRequestActivator fork) { /* corps actuel */ }
//   HubSection(..., onItemTap: fork.tapFor(context, hub), icon: fork.iconFor(hub) ?? hubIconFor(hub))
//   _buildTvContent(items, fork) → TvBrowseRail(..., onActivateItem: (hub, item) => fork.activate(context, hub, item),
//                                               iconForHub: (hub, _) => fork.iconFor(hub) ?? hubIconFor(hub))
```

### 5. Traductions (CA20)

`lib/fork/i18n/fr.json` / `en.json` : `fork.recentRequests.title` = « Demandes récentes » / « Recent requests ». Puis
`scripts/fork/rebrand_i18n.py` → `scripts/codegen.sh` (D6). Les badges réutilisent `t.explore.badge.*`.

## Alternatives écartées

1. **Résoudre les titres disponibles à l'avance et mettre l'élément serveur dans la rangée.** Tap « natif », mais
   l'affiche serveur n'a pas de badge d'état (CA7 non tenu) et le chargement de la rangée dépendrait de N recherches
   serveur avant affichage.
2. **Crochet dans `navigateToMediaItem` / `navigateToCatalogItem`.** Universel, mais touche le routeur central de
   l'app (fichier très remanié upstream) et ne reçoit qu'un `CatalogItem`, impossible à distinguer d'un même titre
   ouvert depuis Explorer sans marquer `MediaItem.raw`. Les points d'extension `onActivateItem` / `onItemTap` existent
   déjà et restent dans le fichier qu'on modifie de toute façon.
3. **Injecter le hub dans `_loadRecommendedHubs`.** Ferait attendre Overseerr (et ses 100 fiches à froid) avant
   d'afficher les rangées serveur (contraire à CA17) et exposerait le hub du fork à toute la logique upstream sur
   `items` (suppression, état vu, Continuer à regarder).
4. **Dupliquer la conversion Seerr → `CatalogItem` dans le fork.** Zéro ligne upstream de plus, mais ~150 lignes de
   règles (codes 6/7 Overseerr / Jellyseerr, priorité des états de demande, saisons) qui divergeraient en silence.
5. **Créer un `SeerrHttpClient` à part avec le cookie de la session.** Pas de crochet dans `SeerrClient`, mais pas de
   ré-authentification : la rangée est souvent le premier appel Seerr après le démarrage, elle disparaîtrait dès que
   le cookie expire.
6. **Reconnaître les animés par le genre « Animation » + pays/langue JP.** Contraire à CA3b (règle TMDB d'Overseerr)
   et faux pour Les Simpson.
7. **Provider profil (`profile_session_screen.dart`) pour le dépôt.** Une ligne upstream de plus pour un simple cache
   déjà isolé par sa clé de session.

## Impact

**Fichiers upstream modifiés (3, ~13 lignes, toutes `// FORK:`)**
- `lib/services/seerr/seerr_client.dart` (+2)
- `lib/services/catalog/seerr_catalog_source.dart` (+3)
- `lib/screens/libraries/tabs/library_recommended_tab.dart` (~8 : import, `buildContent` délégué, 4 paramètres)

**Nouveaux fichiers**
- `lib/fork/recent_requests/recent_request.dart` — modèle et parseur de `GET /request`
- `lib/fork/recent_requests/recent_requests_classifier.dart` — rayons, bibliothèque Animés
- `lib/fork/recent_requests/recent_requests_repository.dart` — appels, caches, instantané
- `lib/fork/recent_requests/recent_requests_resolver.dart` — titre serveur, pré-résolution
- `lib/fork/recent_requests/recent_requests_shelf.dart` — widget, insertion, activation
- `lib/fork/i18n/{fr,en}.json` (clés ajoutées) + fichiers générés
- `test/fork/recent_requests/*_test.dart` + une garde des crochets

**Dépendances ajoutées** : aucune.

**Risques**
- *Google Play* : aucune donnée nouvelle collectée ni envoyée hors du serveur Overseerr de l'utilisateur ; pas de
  permission ; identique dans les deux canaux. Les affiches viennent du proxy de l'instance ou de `image.tmdb.org`,
  comme Explorer aujourd'hui.
- *Marque* : aucun texte « Plezy » ; clés `fork.*`.
- *Performances TV* : premier chargement à froid jusqu'à 100 appels `/movie|tv/{id}` (4 en parallèle) sur la Fire
  TV Stick ; sans effet sur les autres rangées (insertion au rendu) mais la rangée peut arriver plusieurs secondes
  après. Ensuite 1 appel par ouverture. Pré-résolution : jusqu'à 20 recherches serveur en arrière-plan, 2 à la fois.
  À mesurer en recette (la cible CA8 < 3 s dépend du cache du matcher).
- *Fusion upstream* : `library_recommended_tab.dart` est le seul fichier UI touché ; le renommage du corps de
  `buildContent` en `_buildContentWith` produira un conflit si l'upstream modifie ces lignes, résolu en replaçant la
  délégation. `SeerrClient` et `SeerrCatalogSource` : une méthode ajoutée en fin de section, conflit improbable. Une
  garde `test/fork/recent_requests/hooks_test.dart` vérifie la présence des trois crochets.
- *Compatibilité API* : les anciennes versions d'Overseerr qui ignoreraient `requestedBy` sont couvertes par le
  filtre côté client ; `take=100` est accepté par les deux produits. Si Overseerr change `GET /request`, la rangée
  disparaît (CA17), sans casse.
- *Onglet vide* : une bibliothèque sans aucun hub serveur affiche l'état vide upstream (`ContentStateBuilder`) et
  donc pas la rangée (cas d'une bibliothèque Animés neuve et vide). → `QUESTIONS PRODUIT` n° 5.

## Découpage prévisionnel (pour le plan)

| Tâche | Contenu | Complexité |
|---|---|---|
| T1 | Crochets `SeerrClient.getJsonForFork` et `SeerrCatalogSource.catalogItemFromDetailsForFork` + garde des crochets | S |
| T2 | `recent_request.dart` (parseur, regroupement, filtre `requestedBy`) + `recent_requests_classifier.dart` (rayons, Animés par votes / par nom, CA18) + tests purs | M |
| T3 | `recent_requests_repository.dart` : appels, concurrence 4, caches `JsonPref` (TTL, plafond), instantané, construction `CatalogItem` + tests `MockClient` (paramètre `requestedBy`, Overseerr et Jellyseerr, échec → vide) | M |
| T4 | `recent_requests_resolver.dart` : matcher, choix de la copie, délai 2,5 s, pré-résolution, mémorisation de la bibliothèque Animés + tests avec matcher factice | M |
| T5 | Traductions `fork.recentRequests.*` (script + codegen) | S |
| T6 | `recent_requests_shelf.dart` + crochet `library_recommended_tab.dart` : insertion, génération, rafraîchissement, activation TV / hors TV + tests widget (CA1, CA4, CA12, CA14 à CA18) | L (focus TV et chargement asynchrone concurrent) |

Dépendances : T3 ← T1, T2 ; T4 ← T2, T3 ; T6 ← T3, T4, T5.

## Proposition de décision durable (pour `decisions.md`, à valider au plan)

**D15 — Accéder à une capacité privée d'un service upstream** : quand le fork a besoin d'un appel ou d'une conversion
privés d'une classe upstream, on ajoute **une** méthode publique d'une ligne, suffixée `ForFork`, qui délègue à
l'implémentation privée, marquée `// FORK:` ; on ne duplique pas la logique et on ne contourne pas la classe (session,
ré-authentification). Premier cas : `SeerrClient.getJsonForFork`, `SeerrCatalogSource.catalogItemFromDetailsForFork`.

## Ajouts proposés au skill `conventions-code`

- Pour intercepter l'activation d'une affiche sans toucher au routeur : `TvBrowseRail.onActivateItem` (renvoyer `true`
  annule la navigation upstream) et `HubSection.onItemTap` (D-pad et toucher).
- Un `CatalogItem` avec `serverState` reçoit automatiquement dans `MediaCard` les badges Disponible / Partiellement
  disponible / Demandé / Refusé / Échec (`_buildCatalogBadgeLabels`) : ne pas recréer de badge.
- `TvBrowseRail` garde le hub actif par clé `serverId:id` quand la liste change : une rangée ajoutée de façon
  asynchrone doit avoir un `id` stable et ne pas réutiliser un identifiant serveur.
- `LibraryRecommendedTab` réutilise le même `State` pour toutes les bibliothèques (`_recommendedTabKey`) : tout état du
  fork attaché à cet onglet se réinitialise sur changement de `library.globalKey`.
- Rapprocher un titre externe d'une bibliothèque : `CatalogLibraryMatcher.match` (cache de session partagé avec la
  fiche Explorer), jamais un appel `findByExternalIds` direct.

## QUESTIONS PRODUIT

1. **Plusieurs bibliothèques du même type** (par ex. « Séries » et « Séries enfants », ou deux serveurs) : la rangée
   s'affiche-t-elle dans chacune avec les mêmes demandes ? Ma proposition par défaut : oui, dans toutes.
2. **Animés rangés dans « Séries »** (pas de bibliothèque Animés dédiée) : je propose de considérer qu'il n'y a pas de
   bibliothèque Animés (les animés restent dans Séries/Films, CA3c), plutôt que de faire de « Séries » la bibliothèque
   Animés. D'accord ?
3. **Nom contenant « Anim »** : une bibliothèque « Films d'animation » (Pixar, Disney) serait reconnue comme
   bibliothèque Animés selon CA3d tant qu'aucun animé n'y est arrivé ; les films d'animation non japonais demandés
   resteraient alors dans Films. Acceptable ?
4. **Profondeur** : la rangée est calculée sur les 100 dernières demandes de l'utilisateur ; un animé demandé avant
   ces 100 demandes n'apparaît pas même si la rangée Animés en compte moins de 20. Acceptable ?
5. **Bibliothèque totalement vide** côté serveur : l'onglet garde son message « vide » upstream et la rangée n'apparaît
   pas. Acceptable, ou faut-il la montrer quand même ?
