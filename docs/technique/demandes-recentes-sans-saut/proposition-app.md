# Proposition app — demandes-recentes-sans-saut

Spec : `docs/produit/specs/demandes-recentes-sans-saut.md` (validée le 2026-11-28).
S'appuie sur `docs/technique/demandes-recentes-overseerr/plan.md`, dont les décisions 1 (rangée insérée au rendu,
jamais attendue), 5 (cache mémoire attaché au `SeerrClient`, pas de `JsonPref`) et 6 (rien d'affiché avant une réponse
de moins de 30 s) restent valables. Décisions durables relues : D2, D3, D11, D13, D15.

> **Après le débat (2026-11-28)** : le plan `plan.md` fait foi. Ce qui a changé par rapport à cette proposition :
> - fichier `row_sizes.json` à propriétaire unique, au lieu d'une clé `userId|globalKey` (CA13) ;
> - pas d'affiches grises insérées en retard ;
> - écriture immédiate, au lieu d'un délai de 2 s ;
> - réponse arrivée après 10 s ignorée pendant la visite (CA6b) ;
> - zone d'aperçu qui ignore les affiches grises (CA14, 2 lignes de plus dans `library_recommended_tab.dart`).

## Compréhension de la spec

À l'ouverture d'une bibliothèque Films ou Séries qui avait des demandes récentes la dernière fois, la rangée « Demandes
récentes » est réservée d'emblée par son titre et des affiches grises, puis remplacée sur place par les vraies affiches.
Seul le nombre d'affiches par bibliothèque est mémorisé sur la TV, lu à l'ouverture d'une bibliothèque et jamais au
démarrage. Les affiches grises disparaissent si Overseerr ne répond pas dans les 10 s, ou s'il n'y a plus de demande.

Critères d'acceptation de mon périmètre : tous, sauf la mesure du démarrage (CA11, recette commune).
- CA1, CA2, CA3, CA4 : rendu.
- CA5, CA6, CA7, CA8, CA9 : cycle de vie.
- CA10, CA10b, CA10c : focus.
- CA13 : contenu mémorisé.
- CA12 : Plex et Jellyfin, par les tests.

## Existant

- `lib/fork/recent_requests/recent_requests_shelf.dart`, classe `ForkRecentRequestsShelf`. Elle enveloppe
  `buildContent` de `_LibraryRecommendedTabState` et insère le hub du fork à l'index 1 (après « Continuer à
  regarder ») ou 0, une fois qu'une réponse fraîche est arrivée (`_apply`).
  - À chaque changement de bibliothèque ou de source, elle remet `_row = null`.
  - `ForkRequestActivator.activate` « avale » déjà l'OK sur un élément du hub du fork qui n'a pas d'entrée
    (`entry == null` → `true`). C'est exactement le comportement voulu sur une affiche grise (CA10).
- `lib/fork/recent_requests/recent_requests_repository.dart`.
  - `ForkRecentRequestsRepository.rowFor` renvoie `ForkRecentRequestsRow?`. `null` y mélange « aucune demande » et
    « échec ou délai dépassé » (liste 8 s, budget de rangée 15 s).
  - Le hub est construit avec `id: '$kRecentRequestsHubIdPrefix${library.globalKey}'`, `type: 'mixed'` et sans
    `serverId`.
- `lib/screens/libraries/tabs/library_recommended_tab.dart`.
  - Sur TV, `_buildTvContent` filtre les hubs vides, puis passe la liste à `TvSpotlightScaffold` et à `TvBrowseRail`
    avec `tallPosterScale: TvBrowseRailLayout.compactTallPosterScale`.
  - Les hubs viennent de `_loadRecommendedHubs`, qui fait un appel réseau à l'ouverture de la bibliothèque.
- `lib/widgets/tv_browse_rail.dart`, lu sans être modifié.
  - La clé d'une rangée est `_hubKey = '${hub.serverId ?? ''}:${hub.id}'`.
  - `didUpdateWidget` retrouve la rangée active par cette clé.
    - Si elle existe encore, le focus suit l'élément (`followFocus`). Sinon il garde sa colonne, ramenée dans les
      bornes (`_itemIndex.clamp`). Donc une affiche grise remplacée par une vraie garde la même position, ou la
      dernière s'il y en a moins (CA10b).
    - Si elle a disparu, `_hubIndex.clamp` désigne la rangée qui a pris sa place (la suivante, ou la précédente si
      c'était la dernière). Mais **la colonne est conservée**, sans remise à la première affiche et sans défilement
      horizontal (`_scrollToItem` n'est pas appelé).
  - La hauteur d'une rangée (`metricsForHub`) ne dépend que de la forme des éléments : des éléments `MediaKind.movie`
    donnent la même hauteur que les vraies affiches (films et séries, format portrait).
  - `TvSpotlightScaffold` calcule la hauteur du rail d'après le **nombre** de rangées (`estimateHeight`) : une rangée
    insérée tard déplace aussi la zone du haut. Une rangée réservée dès le départ supprime les deux sauts.
- `lib/widgets/media_card.dart` porte déjà un crochet du fork (`forkPosterBadge`, D11).
  - `MediaCardState.showContextMenu` ne fait rien si l'élément n'est pas un élément de catalogue et que
    `MediaContextMenu` n'a pas été construit.
  - L'appui long sur une affiche grise ne fait donc rien, à condition que la carte grise court-circuite le reste.
- Affiches de chargement upstream :
  - `lib/widgets/skeleton_media_card.dart` (`SkeletonMediaCard`) et `SkeletonLoader` (`media_card.dart`, public) ;
  - sur TV, l'accueil n'affiche pas de rangées grises (seulement un `CircularProgressIndicator`, dans
    `discover_screen.dart`, `_buildTvContent`). Les affiches grises visibles sur TV sont les `SkeletonMediaCard` des
    rails pendant que leurs cartes se construisent (`card_inflation_budget.dart`) ;
  - les rangées grises de l'accueil hors TV sont dessinées directement dans `discover_screen.dart` (non réutilisables).
- Bordure de focus : `CardFocusBorder` (`lib/focus/card_focus_scope.dart`, public). Le rail délègue la bordure à la
  carte (`delegateFocusBorder: true`) : la carte grise doit donc la dessiner elle-même, sinon le focus est invisible
  (CA10c).

## Approche proposée

### 1. Mémoire du nombre d'affiches : un petit fichier du cache, chargé à l'ouverture d'une bibliothèque

Nouveau fichier `lib/fork/recent_requests/recent_request_counts.dart`, classe `ForkRecentRequestCounts`, singleton
paresseux (`static final instance`).

- **Fichier** : `p.join((await getApplicationCacheDirectory()).path, 'popkino_recent_requests', 'counts.json')`.
  - C'est le même dossier que celui prévu par T9 de `demandes-recentes-overseerr`.
  - Le répertoire de cache est le bon endroit : le perdre est sans conséquence (on retombe sur CA7), et « Vider le
    cache » dans les réglages Android l'efface.
- **Format** : `{"version": 1, "counts": {"<seerrUserId>|<library.globalKey>": 12}}`.
  - Il ne contient que des entiers, sans titre ni identifiant TMDB (CA13).
  - L'identifiant d'utilisateur Seerr (`source.client.session.userId`) sépare les profils d'une même TV. Sans lui,
    deux profils, l'un avec des demandes et l'autre sans, s'effaceraient mutuellement la mémoire à chaque ouverture
    (affiches grises puis disparition pour l'un, insertion tardive pour l'autre).
  - 64 entrées au plus, les plus anciennes écrites étant retirées en premier (`LinkedHashMap`, réinsertion à chaque
    mise à jour). Une version différente ou un fichier illisible sont ignorés, et le fichier est supprimé.
- **Lecture** : `Future<void> ensureLoaded()` mémorisée (une seule lecture par session), puis `int? countFor(key)`
  **synchrone**, qui vaut `null` tant que le fichier n'est pas chargé.
- **Écriture** : `remember(key, n)` et `forget(key)` ne font rien si la valeur ne change pas. Sinon, écriture
  différée de 2 s et regroupée, sérialisée par `SerialFutureQueue` (`lib/utils/serial_future_queue.dart`), dans un
  fichier temporaire renommé ensuite (écriture atomique).
- **Moment de la lecture** :
  - Une ligne upstream marquée lance la lecture **en tête de `_loadRecommendedHubs`**, donc à l'ouverture de la
    bibliothèque et en parallèle de l'appel réseau des rangées. L'appel est
    `unawaited(forkWarmUpRecentRequestCounts(context, widget.library)); // FORK: demandes-recentes-sans-saut`.
  - La fonction ne fait rien sans Seerr, hors ligne, ou pour une bibliothèque qui n'est ni films ni séries.
  - Quand les rangées arrivent (des centaines de ms), un fichier de moins de 2 Ko est lu depuis longtemps : la lecture
    est **synchrone** au premier `build` du shelf, et les affiches grises sortent dans la même image que les autres
    rangées (CA1).
  - Sans cette ligne, le shelf ne naît qu'avec les rangées (`buildContent` n'est appelé qu'une fois les hubs chargés).
    À la première ouverture de chaque session, les affiches grises arriveraient alors une à trois images après les
    rangées : c'est un petit saut, qui contredit CA1.
  - Rien n'est lu au démarrage : la pile d'onglets de `MainScreen` est paresseuse, et `_loadRecommendedHubs` ne
    s'exécute qu'à l'ouverture d'une bibliothèque (CA11).
- **Mise à jour** (dans le shelf, cf. 3) :
  - `remember(key, row.hub.items.length)` quand une rangée fraîche est affichée ;
  - `forget(key)` quand la réponse dit de façon **concluante** qu'il n'y a aucune demande de ce type (CA13) ;
  - rien en cas d'échec ou de délai dépassé : Overseerr éteint ne doit pas effacer la mémoire.
- **Écart assumé à D13**, identique à la décision 5 du plan précédent. Ce n'est pas un état observé mais un cache :
  pas de provider ni de ligne dans `main.dart`.

### 2. Dépôt : distinguer « aucune demande » de « pas de réponse », et rouvrir sans affiches grises

Dans `recent_requests_repository.dart` (fichier du fork) :

- `Future<ForkRowResult> rowResultFor(library, ctx)` renvoie `({ForkRecentRequestsRow? row, bool conclusive})`.
  `rowFor` devient un simple appel à `rowResultFor(...).row`, ce qui garde les tests existants.
- `conclusive` vaut `true` quand la liste a été obtenue et que l'une des conditions suivantes est remplie :
  - la liste est vide ;
  - aucune demande candidate pour ce type de rangée ;
  - toutes les candidates ont été lues, sans dépassement de budget et sans fiche en échec, et aucune n'a été retenue ;
  - au moins une affiche a été produite.

  Dans tous les autres cas, il vaut `false` : liste en échec ou en cache négatif, budget expiré pendant la détection
  Animés ou pendant les lectures, fiche `null`.
- **CA9**, nouvelle méthode synchrone `ForkRecentRequestsRow? recentRowFor(MediaLibrary library)` :
  - elle renvoie la dernière rangée construite pour cette bibliothèque si sa liste date de moins de
    `kRecentRequestsShowWithin` (30 s), en lisant la mémoire `Map<String, ForkRecentRequestsRow>` du dépôt, remplie
    par `rowResultFor` ;
  - c'est de la mémoire seulement, conforme aux décisions 5 et 6 ;
  - aujourd'hui, même une réouverture dans les 30 s passe par une image sans rangée, puis l'insère (un micro-saut).
- La construction du hub est extraite dans une fonction `forkRecentRequestsHub(library, items)`, utilisée à la fois
  par la vraie rangée et par la rangée grise. Les deux ont alors **le même `id`, le même `identifier`, le même titre,
  le même `type` et le même `serverId` (absent)**, donc la même `_hubKey` pour `TvBrowseRail`, qui conserve rangée et
  colonne au remplacement.

### 3. Shelf : rangée grise, délai de 10 s, retrait en deux temps

Dans `recent_requests_shelf.dart` :

- Un seul point de remise à zéro, `_resetFor(library)`, appelé depuis `didChangeDependencies` (changement de source)
  et `didUpdateWidget` (changement de bibliothèque). Il remplace les trois copies actuelles de
  `_generation++ ; _loadingGeneration = null ; _row = null`. Dans l'ordre :
  1. Pas de Seerr, hors ligne ou bibliothèque non éligible : rien (CA8).
  2. `repo.recentRowFor(library)` non nul : `_row` reçoit cette rangée tout de suite, sans affiches grises (CA9). Le
     rafraîchissement `_load()` part quand même ; la fraîcheur de 30 s le rend gratuit.
  3. Sinon, `ForkRecentRequestCounts.instance.countFor(key)` :
     - s'il est supérieur à 0, `_placeholderCount` prend ce nombre et un `Timer` de
       `kRecentRequestsPlaceholderTimeout = Duration(seconds: 10)` démarre, mesuré depuis cet instant, donc depuis
       l'ouverture (CA6) ;
     - s'il vaut `null` (fichier pas encore lu, cas résiduel), `ensureLoaded().then(...)` refait le calcul, à
       condition que la génération n'ait pas changé et qu'aucune vraie rangée ne soit déjà arrivée.
  4. `_load()`.
- `_apply(result)`, avec `result.row` et `result.conclusive` :
  - **rangée fraîche** : `_row = row`, `_placeholderCount = 0`, `Timer` annulé, `remember(key, n)`. La règle actuelle
    « une réponse en retard ne remplace jamais une plus récente » est conservée ;
  - **aucune demande, réponse concluante** : `forget(key)` ; si des affiches grises sont affichées, retrait en deux
    temps (CA5). Une vraie rangée déjà affichée garde la règle actuelle des 5 minutes : pas de changement de
    comportement ;
  - **pas de réponse** : rien, le `Timer` fera le retrait (CA6), et la mémoire reste.
- Le **retrait en deux temps** (`_dropPlaceholder`) respecte CA10b sans toucher `tv_browse_rail.dart` :
  - image 1, la rangée grise passe à **une seule** affiche ; si le focus y était, le rail le ramène sur la colonne 0
    (`_itemIndex.clamp`) ;
  - image 2 (`addPostFrameCallback`), la rangée est retirée ; le rail donne la place à la rangée suivante (ou à la
    précédente si c'était la dernière) avec la colonne 0, c'est-à-dire **sa première affiche** ;
  - si le focus est ailleurs, l'image 1 ne change aucune hauteur (même rangée, même forme) et l'image 2 conserve la
    rangée active par sa clé (CA10c) ;
  - l'image intermédiaire à une affiche dure environ 16 à 33 ms, ce qui est imperceptible.
- **Réponse arrivée après les 10 s** : elle est insérée comme aujourd'hui si elle est fraîche (CA7, saut accepté). À
  confirmer par le PO (question 1).
- **`build`** :
  - si `_row == null` et `_placeholderCount > 0`, on insère au même index que la vraie rangée un hub
    `forkRecentRequestsHub(library, forkSkeletonItems(n))` ;
  - `n = min(_placeholderCount, forkSkeletonVisibleCap(context))` ;
  - l'activateur `ForkRequestActivator._(null, library)` donne l'icône du fork et un OK sans effet (CA10, avec le code
    actuel `entry == null → true`).
- **Plafond « ce qui tient à l'écran »** (CA2), `forkSkeletonVisibleCap(context)` :
  - le calcul utilise uniquement des API publiques upstream : `TvBrowseRailLayout.metricsForHub` (avec les paramètres
    que passe `_buildTvContent` : `compactTallPosterScale`, densité, espacement, `tvFullCardLayout`) et
    `TvLayoutConstants.scaleForSize` ;
  - on obtient `ceil((largeur − 2·railEdgePadding + itemGap) / (cardWidth + itemGap))`, soit environ 7 à 9 cartes
    selon la densité ;
  - hors TV, le plafond est 8 ;
  - le nombre mémorisé reste le nombre réel (≤ 20) : le plafond s'applique à l'affichage, car l'écran peut changer.

### 4. Carte grise : un crochet d'une ligne dans `MediaCard`

Nouveau fichier `lib/fork/recent_requests/recent_requests_skeleton.dart` :

- `const kForkSkeletonRawKey = 'popkinoSkeleton'` ;
- `List<MediaItem> forkSkeletonItems(MediaLibrary library, int n)`, qui produit des
  `MediaItem(id: 'popkino.recentRequests.skeleton:<i>', backend: library.backend, kind: MediaKind.movie, raw: {kForkSkeletonRawKey: true})`.
  Ces éléments ont un `id` stable et différent des vrais éléments, n'ont ni `serverId` ni titre, et ne portent pas la
  clé catalogue, donc aucun menu catalogue ;
- `Widget? forkSkeletonCard(BuildContext context, Object item, {double? width, double? height, required bool fullBleed})`
  renvoie `null` pour tout autre élément (D11). Pour un élément gris, elle reproduit la géométrie de
  `_buildStandardGridCard` :
  - `SizedBox(width)` contient un `Padding(MediaCard.gridCardPadding)` ;
  - celui-ci contient une affiche de hauteur `height`, faite d'un `CardFocusBorder(borderRadius: radiusSm)` autour
    d'un `ClipRRect` qui entoure le `SkeletonLoader` ;
  - sous l'affiche, deux barres grises comme dans `SkeletonMediaCard`, sans texte ;
  - en mode « carte pleine » (`fullBleed`), seule l'affiche est dessinée, à la taille `width × height` ;
  - pas de zone de toucher, pas de `MediaContextMenu`.

Crochet upstream dans `lib/widgets/media_card.dart`, première instruction de `MediaCardState.build` (avant
`SettingsBuilder`, sans dépendance aux réglages) :

```dart
if (forkSkeletonCard(context, widget.item, width: widget.width, height: widget.height, fullBleed: widget.fullBleedImage) case final Widget skeleton) return skeleton; // FORK: demandes-recentes-sans-saut
```

plus une ligne d'import marquée. Ce crochet a plusieurs effets :

- **même apparence** que les affiches de chargement de Plezy (`SkeletonLoader`) ;
- **même taille** que les vraies affiches, puisque le rail fournit `width` et `height` et calcule la hauteur de
  rangée sur des éléments de même forme (CA2, CA3) ;
- **focus visible** grâce à `CardFocusBorder`, que le `CardFocusScope` du rail anime (CA10c) ;
- aucun titre ni badge (CA4) ;
- l'appui long ne fait rien : `showContextMenu` tombe sur un `contextMenuKey` sans état.

`HubSection` (hors TV) passe aussi par `MediaCard` : même rendu, sans code de plus.

### 5. Focus TV, récapitulatif

| Situation | Mécanisme | CA |
|---|---|---|
| Bas depuis « Continuer à regarder » | la rangée grise est une rangée normale du rail | CA10 |
| Gauche / Droite, Bas vers la suivante | idem, éléments focalisables | CA10 |
| OK sur une affiche grise | `ForkRequestActivator.activate` → `true` sans action | CA10 |
| Remplacement par les vraies affiches | même `_hubKey` ; `followFocus` ne trouve pas l'élément → colonne conservée, bornée | CA10b |
| Disparition, focus dans la rangée | retrait en deux temps → colonne 0 de la rangée suivante (ou précédente) | CA10b |
| Disparition, focus au-dessus ou en dessous | rangée active retrouvée par clé, alignée en haut par le rail | CA10c |

Effet visible à signaler : quand le focus est sur une affiche grise, la zone du haut (`TvSpotlightScaffold`) affiche
l'élément gris, c'est-à-dire un fond gris sans titre. L'éviter coûterait une ligne upstream de plus dans
`library_recommended_tab.dart` (filtrer `onFocusedItemChanged`) : voir la question 2.

## Alternatives écartées

- **Préférences (`JsonPref` / `SharedPreferencesWithCache`)**. Pour moins de 200 octets, le coût en taille est
  négligeable, et la lecture synchrone supprimerait la ligne de préchargement. Mais le magasin est chargé en entier
  au démarrage : c'est contraire à la contrainte « l'information mémorisée n'est lue qu'à l'ouverture d'une
  bibliothèque », et au bloquant plateforme déjà accepté (décision 5).
- **Table `drift`** : migration de schéma dans un fichier upstream très actif, et base ouverte au démarrage.
  Disproportionné pour une table clé → entier.
- **Éléments gris sans crochet `MediaCard`**, par exemple des `CatalogItem` vides ou des `MediaItem` sans image :
  - `_buildPosterImage` dessine l'icône de repli (film ou TV) au milieu, ce qui n'est pas l'aspect de chargement
    demandé (CA2) ;
  - un faux élément de catalogue ouvre le menu catalogue à l'appui long, et un faux élément serveur ouvre
    `MediaContextMenu` avec des actions serveur sur un élément inexistant.
- **Superposer la carte grise via le crochet existant `forkPosterBadge`** : il ne couvre que l'affiche (le titre et le
  menu restent), et `SkeletonLoader` est translucide.
- **Modifier `TvBrowseRail`** (constructeur de cartes de substitution, ou remise à la première affiche quand une
  rangée disparaît) : fichier de 2 379 lignes, le plus remanié de l'interface TV, explicitement exclu par la
  décision 2 du plan précédent. Le retrait en deux temps obtient le même résultat depuis `lib/fork/`. Gardé en
  réserve (voir Risques).
- **Retenir le contenu de l'onglet jusqu'à la lecture du fichier** : la logique de focus initial de l'onglet
  (`requestFocusAt(0)`, focus initial du rail) viserait un contenu absent. Ce serait aussi contraire à la décision 1
  (« jamais attendue »).
- **Garder la dernière rangée affichée sur disque** : refusé par l'utilisateur (hors périmètre, CA4).

## Impact

- **Fichiers upstream modifiés : 2, 3 lignes marquées `// FORK: demandes-recentes-sans-saut`.**
  - `lib/widgets/media_card.dart` : 1 import + 1 ligne de crochet (D11).
  - `lib/screens/libraries/tabs/library_recommended_tab.dart` : 1 ligne de préchargement en tête de
    `_loadRecommendedHubs` (l'import du fichier du shelf est déjà là ; la fonction y est réexportée).
  - Aucun changement dans `tv_browse_rail.dart`, `hub_section.dart`, `tv_spotlight_scaffold.dart` ou `main.dart`.
- **Nouveaux fichiers** :
  - `lib/fork/recent_requests/recent_request_counts.dart`, `lib/fork/recent_requests/recent_requests_skeleton.dart` ;
  - tests : `test/fork/recent_requests/recent_request_counts_test.dart`,
    `test/fork/recent_requests/recent_requests_skeleton_test.dart`.
- **Fichiers du fork modifiés** :
  - `recent_requests_repository.dart`, `recent_requests_shelf.dart` ;
  - tests : `recent_requests_repository_test.dart`, `recent_requests_shelf_test.dart`, `hooks_test.dart` (garde des
    2 nouveaux crochets ; le test actuel n'exige le marqueur `demandes-recentes-overseerr` que sur ses propres lignes).
- **Dépendances ajoutées** : aucune (`path_provider`, `path` et `clock` sont déjà là).
- **Tests prévus** :
  - **compteurs** : aller-retour, version différente, fichier corrompu supprimé, plafond de 64, `remember` à valeur
    identique sans écriture, aucune lecture avant `ensureLoaded` ;
  - **dépôt** : table de `conclusive` (liste vide, aucune candidate, budget expiré, fiche en échec, cache négatif),
    `recentRowFor` à 29 s puis 31 s (`clock`) ;
  - **shelf**, avec un constructeur factice qui capture les hubs :
    - CA1, affiches grises dans la même image que les rangées quand le compteur est chargé ;
    - CA7 et CA8, rien sans compteur, sans Seerr, ou pour la musique ;
    - CA9, une réouverture à moins de 30 s donne la vraie rangée au premier `build` ;
    - CA6, retrait à 10 s avec `fakeAsync` ;
    - CA5, `forget` sur réponse concluante et non sur un échec ;
  - **focus** : `TvBrowseRail` réel, avec `onFocusedItemChanged` comme sonde :
    - focus sur la 3e affiche grise, puis 2 vraies affiches → focus sur la 2e vraie ;
    - focus dans la rangée grise, puis retrait → première affiche de la rangée suivante, et de la précédente si la
      rangée grise est la dernière ;
    - focus en dessous, puis retrait → même élément ;
  - **carte** : hauteur de la rangée grise égale à celle de la vraie (`tester.getSize` sur la section), aucun `Text`
    non vide, bordure de focus présente quand le `CardFocusScope` est actif.
- **Risques** :
  - **Google Play** : rien de nouveau n'est envoyé ; le fichier local ne contient que des entiers. Formulaire de
    sécurité des données inchangé.
  - **Marque** : aucun texte nouveau (le titre de rangée existe déjà), donc pas de traduction à ajouter.
  - **Performances TV** :
    - une lecture de moins de 2 Ko par session, à l'ouverture d'une bibliothèque ;
    - écritures regroupées, seulement quand un nombre change ;
    - 7 à 9 cartes grises sans image ni réseau.
  - **Fusion upstream** : 3 lignes. La plus exposée est le crochet en tête de `MediaCardState.build`, une méthode
    courte et stable.
  - **Focus résiduel** :
    - après un retrait, le rail ne fait pas défiler horizontalement la rangée qui reçoit le focus ;
    - si l'utilisateur était allé loin à droite dans la rangée suivante puis était remonté, la colonne 0 peut se
      trouver hors de l'écran jusqu'à la touche suivante. C'est un comportement upstream existant pour toute rangée qui
      disparaît (par exemple « Continuer à regarder » vidé) ;
    - à vérifier en recette. Remède de réserve : un crochet D11 dans `TvBrowseRail.didUpdateWidget`
      (`_scrollToItemAfterLayout(animate: false)` quand la rangée active a disparu), qui pourrait même être proposé à
      l'upstream.
  - **Premier affichage de la session** : si le fichier n'est pas encore lu quand les rangées arrivent (rangées
    servies très vite par le cache d'API), les affiches grises arrivent une à trois images plus tard. C'est un cas
    résiduel, couvert par la ligne de préchargement.

## QUESTIONS PRODUIT

1. **Réponse d'Overseerr après les 10 s** : les affiches grises ont déjà disparu (les rangées en dessous sont
   remontées). Si les vraies demandes arrivent ensuite (par exemple à 12 s), faut-il insérer la rangée (comportement
   actuel, nouveau saut vers le bas), ou attendre la prochaine ouverture de la bibliothèque ?
2. **Zone du haut quand le focus est sur une affiche grise** : sans modification de plus, la grande zone du haut
   (image de fond, titre, résumé) devient vide et grise tant que le focus est sur une affiche grise. Est-ce acceptable,
   ou faut-il qu'elle garde le dernier titre affiché (une ligne de plus dans un écran de Plezy) ?
3. **Aspect des affiches grises (CA2)** : sur la TV, l'accueil de Plezy n'a pas de rangées grises (il affiche une
   roue de chargement). La référence la plus proche est l'affiche grise que Plezy montre pendant qu'une carte se
   construit : un rectangle gris, avec sous lui deux traits gris à la place du titre (sans texte). Faut-il garder ces
   deux traits, ou seulement le rectangle de l'affiche ? CA4 interdit le titre, pas les traits.

## Ajouts proposés au skill `conventions-code` (section TV)

- `TvBrowseRail` identifie une rangée par `serverId:id` (`_hubKey`). Une rangée dont le contenu change doit garder le
  même `MediaHub.id` et le même `serverId` pour que le focus reste dessus.
  - Si la rangée active disparaît, le focus passe à la rangée qui prend son index, **à la même colonne** (bornée),
    sans défilement horizontal.
  - La hauteur d'une rangée ne dépend que de la forme des éléments (portrait, paysage, carré).
- `TvSpotlightScaffold` calcule la hauteur du rail d'après le nombre de rangées : une rangée insérée tardivement
  déplace aussi la zone du haut.
- `MediaCard` en rail TV ne dessine pas la bordure de focus du rail (`delegateFocusBorder`). Tout remplaçant de carte
  doit envelopper son affiche dans `CardFocusBorder`, sinon le focus est invisible.
