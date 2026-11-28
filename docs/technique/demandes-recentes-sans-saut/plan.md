# Plan technique — demandes-recentes-sans-saut

Spec : docs/produit/specs/demandes-recentes-sans-saut.md
Statut : brouillon       Pilote : architecte-app

Sources : `proposition-app.md`, `proposition-plateforme.md`, `debat.md` (tour 1), décisions du PO du 2026-11-28 :
- CA2 : deux traits gris, seulement si la rangée garde la hauteur de la vraie (CA3 prime) ;
- CA6b : une réponse arrivée après 10 s est ignorée pendant la visite ;
- CA13 : souvenir propre au compte Overseerr ;
- CA14 : la zone d'aperçu ignore les affiches grises.

Le plan prolonge `docs/technique/demandes-recentes-overseerr/plan.md`, dont les décisions 1, 5 et 6 restent
valables : rangée insérée au rendu sans jamais être attendue, cache mémoire attaché au `SeerrClient`, rien d'affiché
avant une réponse de moins de 30 s. Recette **uniquement sur la Fire TV Stick** (192.168.1.173, `armeabi-v7a`).

## Décisions

1. **Souvenir : `row_sizes.json` dans le répertoire de cache de l'app**
   (`<getApplicationCacheDirectory()>/popkino_recent_requests/row_sizes.json`, le dossier réservé par T9 du plan
   précédent). Raisons :
   - aucune lecture au démarrage, contrairement aux préférences, que `SharedPreferencesWithCache` charge en entier ;
   - le répertoire `cache/` est exclu d'office de la sauvegarde Android, sans toucher au manifeste ;
   - si le fichier est perdu, on retombe simplement sur CA7.

   Format : `{"v":1,"owner":"<16 hex>","rows":{"<library.globalKey>":{"n":7,"d":20420}}}`.
   - `owner` : les 16 premiers caractères hexadécimaux du SHA-256 de `baseUrl|userId` de la session Seerr. S'il
     diffère, la table est considérée comme vide, puis réécrite à la première écriture : c'est CA13, « changer de
     compte l'efface ».
   - `n` : nombre réel d'affiches affichées (au plus 20) ; `d` : jour de la dernière confirmation (jours depuis
     l'epoch).
   - Une entrée expire après 30 jours sans confirmation, et la table est plafonnée à 64 entrées.
2. **Lecture une seule fois par processus, lancée en tête de `_loadRecommendedHubs`** (une ligne upstream). Raisons :
   - l'onglet n'a pas d'`initState`, et son état est réutilisé d'une bibliothèque à l'autre ;
   - cet endroit s'exécute à chaque ouverture ou changement de bibliothèque, avant l'appel réseau des rangées, et
     jamais au démarrage (pile d'onglets paresseuse) ;
   - aucune E/S sans Seerr, hors ligne, ou pour une bibliothèque qui n'est ni films ni séries (CA8, CA11).

   **Filet** : si la table n'est pas chargée au premier rendu de la rangée, il n'y a pas d'affiches grises pour cette
   ouverture. On n'en insère jamais en retard (ce serait un saut).
3. **Écriture immédiate, seulement en cas de changement.**
   - Écriture atomique (`.tmp` puis `rename`), une à la fois (`SerialFutureQueue`), sans minuteur. Raison : Fire OS
     tue vite l'app en arrière-plan, et une écriture différée serait perdue (amendement plateforme).
   - Il y a changement quand `n` change, qu'une entrée est ajoutée ou retirée, que le propriétaire change, ou que `d`
     a plus de 7 jours.
   - Quand écrire :
     - rangée fraîche affichée → `n` ;
     - réponse **concluante** sans demande → entrée retirée (CA13) ;
     - échec, délai dépassé ou cache négatif → rien.
4. **Le dépôt distingue « vide » d'« inconnu »** : `rowResultFor` renvoie `({row, conclusive})`. Raison : une panne
   d'Overseerr ne doit pas effacer le souvenir.
5. **CA9 par la mémoire seulement** : `recentRowFor(library)` donne, sans attendre, la dernière rangée construite
   pour cette bibliothèque si sa liste a moins de 30 s. Raison : la réouverture rapide passe directement aux vraies
   affiches, sans image intermédiaire.
6. **La rangée grise est un `MediaHub` identique à la vraie** : même `id`, même `identifier`, même titre, même
   `type`, `serverId` absent, construit par la même fonction `forkRecentRequestsHub`. Ses éléments sont des
   `MediaKind.movie`, donc des affiches portrait. Raisons :
   - `TvBrowseRail` identifie une rangée par `serverId:id`, et garde donc rangée et colonne au remplacement (CA10b) ;
   - la hauteur de rangée et la hauteur du rail (`TvSpotlightScaffold.estimateHeight`) ne bougent pas (CA3).

   Aucun changement dans `tv_browse_rail.dart`.
7. **Carte grise rendue par un crochet d'une ligne en tête de `MediaCardState.build`** (D11). Elle reprend
   `SkeletonLoader` (CA2) dans la géométrie de `_buildStandardGridCard` (`MediaCard.gridCardPadding`, hauteur fournie
   par le rail), avec un `CardFocusBorder`. Raisons :
   - le rail délègue la bordure de focus à la carte (`tv_browse_rail.dart:1819`) ;
   - `SkeletonMediaCard` a une autre géométrie (`padding: .all(8)`) et pas de bordure (bloquant app accepté) ;
   - pas de `MediaContextMenu` ni de zone de toucher : l'appui long ne fait rien ;
   - aucun nœud de focus par affiche.
8. **Nombre d'affiches grises** = `min(n, ce qui tient à l'écran)`. Ce plafond est calculé avec les API publiques
   `TvBrowseRailLayout.metricsForHub` et `TvLayoutConstants.scaleForSize`, avec les paramètres que passe
   `_buildTvContent`. Hors TV, le plafond vaut 8.
9. **10 s au plus après l'ouverture (CA6), puis visite close (CA6b).**
   - Un `Timer` côté rangée, indépendant des délais du dépôt (8 s et 15 s).
   - L'heure d'ouverture est notée par la ligne de préchargement. Le minuteur dure `10 s − (maintenant − ouverture)`.
     Si la rangée apparaît après plus de 10 s, pas d'affiches grises.
   - À l'expiration, les affiches grises sont retirées et la **visite est close** : aucune rangée n'est plus affichée
     pour cette visite, mais le souvenir est encore mis à jour.
   - La visite se rouvre par un changement de bibliothèque ou de source, ou par le retour de l'onglet au premier plan.
     **Un rechargement des rangées de Plezy** (nouveaux `hubs` dans `didUpdateWidget`) **ne rouvre pas la visite**
     (amendement plateforme).
   - Au retour de l'onglet au premier plan, quand la visite est close, l'heure d'ouverture est notée de nouveau
     (`clock.now()`) avant `_resetFor()`. Sans cela, l'heure de la visite précédente rendrait le minuteur nul et les
     affiches grises ne reviendraient jamais (écart T4, voir `debat.md`).
10. **Retrait en deux temps** (CA5, CA6). La rangée grise passe d'abord à une seule affiche (si le focus y était, le
    rail le ramène sur la colonne 0), puis elle est retirée à l'image suivante. Le rail donne alors le focus à la
    première affiche de la rangée suivante, ou de la précédente si c'était la dernière (CA10b), sans modifier le rail.
11. **Zone d'aperçu (CA14) : deux lignes dans `library_recommended_tab.dart`.**
    - `resolveSpotlight` reçoit les hubs sans la rangée grise : à l'ouverture, le premier vrai titre s'affiche.
    - `_setSpotlightItem` ignore un élément gris : le dernier vrai titre reste affiché.
12. **Fichiers upstream : 2 fichiers, 5 lignes marquées `// FORK: demandes-recentes-sans-saut`.**
    - `media_card.dart` : un import et le crochet.
    - `library_recommended_tab.dart` : le préchargement et les deux lignes de la zone d'aperçu. Ses nouvelles
      fonctions sont réexportées par `recent_requests_shelf.dart`, déjà importé : pas de nouvel import.
    - Aucune dépendance ajoutée (`path_provider`, `path`, `crypto` et `clock` sont déjà présents).

Décision durable ajoutée à `docs/technique/decisions.md` : **D16**, cache disque du fork.

## Tâches

Ordre : **vague 1** T1, T2 et T3, qui touchent des fichiers disjoints → **vague 2** T4 → **vague 3** T5 → **vague 4**
T6 → T7 (recette).

### T1 — Souvenir des tailles de rangée
- Complexité : M
- Dépend de : —
- Fichiers :
  - créer `lib/fork/recent_requests/recent_requests_row_sizes.dart` ;
  - créer `test/fork/recent_requests/recent_requests_row_sizes_test.dart`.
- À faire. En-tête `// FORK: demandes-recentes-sans-saut — …`, comme les fichiers voisins. Classe
  `ForkRowSizeMemory`, avec `static final ForkRowSizeMemory instance = ForkRowSizeMemory();`.
  - Points d'injection pour les tests :
    - `@visibleForTesting static Future<Directory> Function()? debugDirectory`, qui remplace
      `getApplicationCacheDirectory` ;
    - `@visibleForTesting static void debugReset()`, qui vide la mémoire et le `Future` de chargement.
  - Constantes :
    - `kRowSizesFileName = 'row_sizes.json'`, dans le dossier `popkino_recent_requests` ;
    - `_kVersion = 1`, `_kMaxEntries = 64`, `_kExpiryDays = 30`, `_kRefreshDays = 7`.
  - `static String ownerOf(SeerrSession s)` : les 16 premiers caractères de
    `sha256.convert(utf8.encode('${s.baseUrl}|${s.userId}')).toString()` (`package:crypto`).
  - `Future<void> ensureLoaded()` : `Future` mémorisé, une seule lecture par processus, sans jamais lever
    d'exception.
    - Un fichier absent donne une table vide.
    - Un JSON illisible, ou de `v` différent de 1, donne une table vide et le fichier est supprimé (erreurs de
      suppression ignorées).
    - Une ligne `appLogger.d('RecentRequests: row sizes loaded (<k> entries)')` sert de repère pour la recette.
    - Garder `owner` et `rows` dans une `LinkedHashMap<String, ({int n, int d})>`.
  - `bool get isLoaded`.
  - `int? sizeFor(SeerrSession s, MediaLibrary library)`, **synchrone** :
    - `null` si la table n'est pas chargée ;
    - `0` si le propriétaire diffère, si l'entrée est absente, ou si elle est expirée
      (`today − d > _kExpiryDays`, `today` venant de `clock.now()` en UTC, en jours depuis l'epoch) ;
    - sinon `n`.
  - `Future<void> remember(SeerrSession s, MediaLibrary library, int n)` :
    - attend `ensureLoaded()` ;
    - si le propriétaire diffère, vide la table et adopte le nouveau ;
    - s'il y a changement (décision 3), réinsère l'entrée en fin de table avec `d = today`, retire les entrées
      expirées, ramène la table à 64 entrées en retirant les premières, puis écrit.
  - `Future<void> forget(SeerrSession s, MediaLibrary library)` : idem. Elle écrit seulement si une entrée a été
    retirée ou si le propriétaire a changé.
  - Écriture :
    - dans une `SerialFutureQueue` (`lib/utils/serial_future_queue.dart`) ;
    - créer le dossier, écrire `row_sizes.json.tmp` (`flush: true`), puis `rename` vers `row_sizes.json` ;
    - toute erreur est consignée en `appLogger.w` et ignorée ;
    - pas de minuteur.
  - Aucun titre ni identifiant TMDB, seulement des entiers (CA13).
- Tests (répertoire temporaire, `withClock`) :
  - aller-retour `remember` puis `debugReset` puis `sizeFor`, qui renvoie `n` ;
  - `sizeFor` vaut `null` avant `ensureLoaded` ;
  - autre propriétaire : `sizeFor` vaut 0, puis `remember` réécrit le fichier avec le nouveau propriétaire seul ;
  - `v: 2` ou JSON corrompu : table vide et fichier supprimé ;
  - expiration à 31 jours ; plafond de 64, la plus ancienne étant retirée ;
  - `remember` avec la même valeur et `d` récent : pas d'écriture (date de modification inchangée), puis écriture
    après 8 jours ;
  - `forget` d'une entrée absente : pas d'écriture ;
  - deux `remember` lancés sans attente : le fichier final contient le second ;
  - le fichier ne contient que les clés `v`, `owner` et `rows`, avec `n` et `d`.
- Critères d'acceptation couverts : CA1 (persistance), CA13, CA11 (rien sans appel).

### T2 — Dépôt : réponse concluante, rangée récente, construction du hub
- Complexité : M
- Dépend de : —
- Fichiers :
  - modifier `lib/fork/recent_requests/recent_requests_repository.dart` ;
  - modifier `test/fork/recent_requests/recent_requests_repository_test.dart`.
- À faire :
  - Extraire une fonction de niveau supérieur `MediaHub forkRecentRequestsHub(MediaLibrary library, List<MediaItem> items)`
    qui reprend exactement la construction actuelle :
    - `id: '$kRecentRequestsHubIdPrefix${library.globalKey}'`, `identifier: kRecentRequestsHubIdentifier` ;
    - `title: t.fork.recentRequests.title`, `type: 'mixed'`, `items`, `size: items.length`, sans `serverId`.

    `rowFor` l'utilise.
  - `typedef ForkRowResult = ({ForkRecentRequestsRow? row, bool conclusive});`, puis
    `Future<ForkRowResult> rowResultFor(MediaLibrary library, ForkRowContext ctx)`. Le corps actuel de `rowFor` y
    est déplacé, et `rowFor` devient `async => (await rowResultFor(library, ctx)).row`.
  - `conclusive: true` seulement dans les cas suivants :
    - rangée non nulle ;
    - liste obtenue (`snapshot != null`) et vide ;
    - liste obtenue sans candidate pour ce type de rangée ;
    - toutes les candidates consommées par `_readOrdered`, sans expiration du budget, sans résumé `null`, et sans
      aucune retenue.

    Pour ce dernier cas, `_readOrdered` doit renvoyer `({bool complete})` : `true` si toutes les entrées ont été
    consommées sans arrêt par le budget. Le rappel compte les résumés `null`. Si la conversion
    `catalogItemFromDetailsForFork` échoue pour toutes les retenues (`items` vide), le résultat n'est pas concluant.

    Tout le reste vaut `false` : `serverId` nul, liste en échec ou en cache négatif, budget expiré pendant la
    détection Animés, `shelf == null`.
  - CA9 : `final Map<String, ForkRecentRequestsRow> _lastRowByLibrary = {}`, rempli par `rowResultFor` quand une
    rangée est produite. Le même appel retire l'entrée quand la réponse est concluante et vide.

    `ForkRecentRequestsRow? recentRowFor(MediaLibrary library)` renvoie l'entrée si
    `clock.now().difference(row.fetchedAt) < kRecentRequestsShowWithin`. Pour ne pas créer d'import circulaire,
    déplacer `kRecentRequestsShowWithin` dans le dépôt et le réexporter depuis le shelf.
- Tests :
  - table de `conclusive` : liste vide, aucune candidate, toutes lues et aucune retenue, fiche en échec, budget expiré
    (`fakeAsync`), échec de liste puis cache négatif, rangée produite ;
  - `recentRowFor` à 29 s puis à 31 s (`withClock`), et `null` pour une autre bibliothèque ;
  - les tests existants de `rowFor` restent verts sans modification.
- Critères d'acceptation couverts : CA5, CA6 et CA13 (base), CA9 (base), CA12 (cas Jellyfin des fixtures existantes).

### T3 — Carte grise et crochet `MediaCard`
- Complexité : M (géométrie qui doit égaler la vraie carte, crochet dans un fichier upstream très actif)
- Dépend de : —
- Fichiers :
  - créer `lib/fork/recent_requests/recent_requests_skeleton.dart` ;
  - modifier `lib/widgets/media_card.dart` (**upstream**, 2 lignes marquées) ;
  - créer `test/fork/recent_requests/recent_requests_skeleton_test.dart` ;
  - modifier `test/fork/recent_requests/hooks_test.dart`.
- À faire dans `recent_requests_skeleton.dart` :
  - `const String kForkSkeletonRawKey = 'popkinoSkeleton';`
  - `bool forkIsSkeletonItem(Object item) => item is MediaItem && item.raw?[kForkSkeletonRawKey] == true;`
  - `List<MediaItem> forkSkeletonItems(MediaLibrary library, int n)` : `n` éléments
    `MediaItem(id: 'popkino.recentRequests.skeleton:$i', backend: library.backend, kind: MediaKind.movie, raw: const {kForkSkeletonRawKey: true})`,
    sans titre, sans `serverId` et sans clé catalogue.
  - `Widget? forkSkeletonCard(BuildContext context, Object item, {double? width, double? height, required bool fullBleed})` :
    - `null` si `!forkIsSkeletonItem(item)` ;
    - l'affiche est un `CardFocusBorder(borderRadius: tokens(context).radiusSm, child: ClipRRect(borderRadius: BorderRadius.circular(tokens(context).radiusSm), child: const SkeletonLoader(child: SizedBox.expand())))` ;
    - si `fullBleed` : `SizedBox(width: width, height: height, child: affiche)` ;
    - sinon : `SizedBox(width: width, child: Padding(padding: MediaCard.gridCardPadding, child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [...])))`.
      Les enfants de la colonne sont :
      - une affiche de hauteur `height` (`SizedBox(width: double.infinity, height: height)`) ou, si `height` est
        nul, un `AspectRatio(2/3)` ;
      - `SizedBox(height: 2)` ;
      - les deux traits de `SkeletonMediaCard` : `SkeletonLoader` de hauteur 11 sur toute la largeur, espace de 3,
        puis `SkeletonLoader` de hauteur 9 sur 60 % de la largeur, avec un rayon de 4.

      Le tout est enveloppé dans un `ClipRect`, pour qu'un dépassement ne dessine jamais de bande d'erreur.
    - Ni `Semantics` de bouton, ni zone de toucher, ni `MediaContextMenu`. Ajouter un `ExcludeSemantics`.
  - `int forkSkeletonVisibleCap(BuildContext context, MediaHub skeletonHub)` :
    - hors TV (`!PlatformDetector.isTV()`), renvoie `8` ;
    - sur TV, prend `size = MainScreenFocusScope.foregroundSizeOf(context)` (`lib/navigation/main_screen_scope.dart`),
      puis `metrics = TvBrowseRailLayout.metricsForHub(...)` avec :
      - `hub: skeletonHub`, `availableWidth: size.width` ;
      - les réglages `libraryDensity`, `episodePosterMode`, `tvFullCardLayout` et `gridSpacing` (lus par
        `SettingsService.instance.read`) ;
      - `scale: TvLayoutConstants.scaleForSize(size)`, `tallPosterScale: TvBrowseRailLayout.compactTallPosterScale`,
        `widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale`.

      Renvoie `((size.width - 2 * metrics.railEdgePadding + metrics.itemGap) / (metrics.cardWidth + metrics.itemGap)).ceil().clamp(1, kRecentRequestsRowLimit)`.
- À faire dans `media_card.dart` :
  - import marqué : `import '../fork/recent_requests/recent_requests_skeleton.dart'; // FORK: demandes-recentes-sans-saut` ;
  - première instruction de `MediaCardState.build`, avant `return SettingsBuilder(` :
    ```dart
    if (forkSkeletonCard(context, widget.item, width: widget.width, height: widget.height, fullBleed: widget.fullBleedImage) case final Widget skeleton) return skeleton; // FORK: demandes-recentes-sans-saut — loading placeholder of the recent-requests row
    ```
- Tests :
  - `TvBrowseRail` réel avec deux versions de la même rangée, l'une avec 5 éléments gris, l'autre avec 5
    `CatalogItem.toMediaItem()` portrait. Pour chaque taille d'écran TV (960×540, 1280×720, 1920×1080), en mode
    standard et en mode carte pleine :
    - la hauteur de la section (`tester.getSize` sur la section de la rangée) est **identique** ;
    - la position du titre de la rangée suivante est identique ;
    - aucune exception de dépassement (`tester.takeException()` nul).

    **Si une configuration échoue à cause des traits, les retirer** : CA3 prime sur CA2, décision du PO. Le noter
    dans le compte rendu de la tâche.
  - aucun `Text` non vide sous une carte grise (CA4) ;
  - avec un `CardFocusScope(showFocus: true)` ancêtre, un `CardFocusBorder` est présent et sa `foregroundDecoration`
    n'est pas nulle (CA10c) ;
  - `MediaCardState.showContextMenu()` sur une carte grise ne lève rien et n'ouvre aucune route (CA10) ;
  - `forkSkeletonVisibleCap` : entre 6 et 10 à 1920×1080 pour les densités 1, 3 et 5, et décroissant quand la
    densité augmente ;
  - `hooks_test.dart` : nouveau test « media_card.dart carries the skeleton hook ». Il vérifie la présence de
    `forkSkeletonCard(context, widget.item` et de `recent_requests_skeleton.dart`, et que chacune de ces lignes
    contient `FORK: demandes-recentes-sans-saut`. Le test existant du badge ne change pas.
- Critères d'acceptation couverts : CA2, CA3 (géométrie), CA4, CA10 (appui long), CA10c (bordure).

### T4 — Rangée : affiches grises, délai, visite, retrait en deux temps, souvenir
- Complexité : L (cycle de vie concurrent : générations, minuteur, réponses tardives, focus par retrait en deux
  temps)
- Dépend de : T1, T2, T3
- Fichiers :
  - modifier `lib/fork/recent_requests/recent_requests_shelf.dart` ;
  - modifier `test/fork/recent_requests/recent_requests_shelf_test.dart`.
- À faire :
  - **Constante** `const Duration kRecentRequestsPlaceholderTimeout = Duration(seconds: 10);`
  - **Réexports** du shelf, déjà importé par l'onglet, ce qui évite un import upstream :
    `export 'recent_requests_skeleton.dart' show forkIsSkeletonItem;`, `kRecentRequestsShowWithin`.
  - **Fonctions de niveau supérieur**, dans le shelf :
    - `Future<void> forkWarmUpRecentRequestCounts(BuildContext context, MediaLibrary library)` :
      - elle note `_openedAt[library.globalKey] = clock.now()` dans une `Map` statique privée, limitée à
        16 entrées ;
      - si `CatalogSourcesProvider?.seerrSource` est non nul, que `OfflineModeProvider?.isOffline` est faux et que
        la bibliothèque est éligible, elle appelle `ForkRowSizeMemory.instance.ensureLoaded()` ;
      - toutes les lectures de providers se font par `context.read<T?>()`, avant tout `await`.
    - `Iterable<MediaHub> forkSpotlightHubs(Iterable<MediaHub> hubs)` : `hubs` sans les hubs dont tous les éléments
      sont gris.
  - **État ajouté** :
    - `int _placeholderCount = 0` ;
    - `Timer? _placeholderTimer` ;
    - `bool _visitClosed = false` ;
    - `bool _dropping = false`.
  - **`_resetFor()`**, appelé à la place des remises à zéro actuelles dans `didChangeDependencies` (changement de
    source) et `didUpdateWidget` (changement de bibliothèque) :
    1. `_generation++`, `_loadingGeneration = null`, `_row = null`, minuteur annulé, `_placeholderCount = 0`,
       `_visitClosed = false`, `_dropping = false`.
    2. Pas de source, hors ligne ou bibliothèque non éligible : arrêt.
    3. `final recent = ForkRecentRequestsRepository.of(source.client).recentRowFor(library)`. S'il est non nul,
       `_row = recent` (CA9).
    4. Sinon, `final n = ForkRowSizeMemory.instance.sizeFor(source.client.session, library)`. Si `n` est nul ou vaut
       0, pas d'affiches grises (filet de la décision 2, et CA7).
    5. Sinon, `remaining = kRecentRequestsPlaceholderTimeout - (clock.now() - (_openedAt[key] ?? clock.now()))`,
       ramené à 10 s au plus. S'il reste un temps positif : `_placeholderCount = n` et
       `_placeholderTimer = Timer(remaining, _onPlaceholderTimeout)`. Sinon, pas d'affiches grises.
    6. `_load()`.

    Pas de `setState` dans `_resetFor` : il s'exécute pendant `didUpdateWidget` ou `didChangeDependencies`, suivis
    d'un `build`.
  - **`didUpdateWidget` avec de nouveaux `hubs`** (même bibliothèque) : `_load()` seulement. **Ne pas** toucher
    `_visitClosed` (CA6b).
  - **`_onVisibilityChanged`**, quand l'onglet redevient visible : si `_visitClosed`, noter
    `_openedAt[key] = clock.now()` (écart T4), puis appeler `_resetFor()` et `setState`. C'est une nouvelle visite, avec affiches grises selon le souvenir mis à jour, ou la vraie rangée par
    CA9. Sinon, `_load()` comme aujourd'hui. Ne jamais appeler `_resetFor` quand une vraie rangée est affichée, car
    le focus pourrait disparaître.
  - **`_load()`** appelle `rowResultFor` à la place de `rowFor`. Un `catch` donne
    `(row: null, conclusive: false)`.
  - **`_apply(ForkRowResult result)`**, où `session = _source!.client.session` :
    - **rangée fraîche** (`row != null`, éléments non vides, `fetchedAt` de moins de 30 s), sans régression
      d'ancienneté :
      - `unawaited(ForkRowSizeMemory.instance.remember(session, library, row.hub.items.length))` ;
      - si `_visitClosed`, arrêt (CA6b, la rangée n'est pas affichée) ;
      - sinon, minuteur annulé, `_placeholderCount = 0`, `_dropping = false`, `_row = row` et `setState`.
    - **concluante et vide** (`row == null && conclusive`) :
      - `unawaited(ForkRowSizeMemory.instance.forget(session, library))` ;
      - si `_placeholderCount > 0`, minuteur annulé et `_dropPlaceholder()` (CA5) ;
      - une vraie rangée déjà affichée suit la règle actuelle des 5 minutes, sans changement.
    - **non concluante** : souvenir inchangé. Une rangée affichée suit la règle actuelle. Les affiches grises
      restent jusqu'au minuteur.
  - **`_onPlaceholderTimeout()`** : si le widget est monté et que `_row == null && _placeholderCount > 0`, alors
    `_visitClosed = true` et `_dropPlaceholder()` (CA6).
  - **`_dropPlaceholder()`** : si `_dropping` vaut déjà `true`, arrêt. Sinon :
    1. `_dropping = true`, `setState(() => _placeholderCount = 1)`, puis noter la génération courante ;
    2. dans `addPostFrameCallback`, si le widget est monté, que la génération est la même et que `_dropping` est
       toujours vrai : `setState(() { _placeholderCount = 0; _dropping = false; })`.
  - **`dispose`** : annuler le minuteur.
  - **`build`** : si `_row == null && _placeholderCount > 0` et que la source et l'éligibilité sont réunies :
    - `skeleton = forkRecentRequestsHub(library, forkSkeletonItems(library, …))`, où `…` vaut `1` pendant
      `_dropping`, sinon
      `min(_placeholderCount, forkSkeletonVisibleCap(context, forkRecentRequestsHub(library, forkSkeletonItems(library, 1))))` ;
    - l'insérer au même index que la vraie rangée (1 après « Continuer à regarder », sinon 0) ;
    - activateur `ForkRequestActivator._(null, widget.library)`. L'OK est avalé par la règle actuelle
      `entry == null → true` (CA10).
- Tests (constructeur factice qui capture `hubs`, `fakeAsync`, `withClock`, fausse `SeerrCatalogSource` et faux dépôt
  par `ForkRecentRequestsRepository.debugOverride`, `ForkRowSizeMemory.debugDirectory`) :
  - **CA1** : avec le souvenir chargé à 7, le premier `build` contient la rangée grise, au bon index, avec
    `min(7, cap)` éléments gris ;
  - **CA7** : souvenir absent ou nul, ou table non chargée : aucune rangée grise, et pas d'insertion grise ensuite
    même quand le chargement se termine ;
  - **CA8** : sans Seerr, hors ligne, ou pour une bibliothèque de musique : aucune rangée grise, et aucun accès
    disque (`ensureLoaded` non appelé par `forkWarmUpRecentRequestCounts`) ;
  - **CA9** : `recentRowFor` non nul donne la vraie rangée au premier `build`, sans rangée grise ;
  - **CA3** : la réponse fraîche remplace la rangée grise par la vraie, au même index, avec le même `id`, et
    `remember(…, n)` est appelé ;
  - **CA5** : une réponse concluante et vide déclenche `forget`, une image à 1 élément gris, puis l'absence de rangée
    à l'image suivante ;
  - **CA6** : sans réponse, le retrait se fait à 10 s, en deux images. Si l'ouverture notée par le préchargement date
    de 3 s, le retrait se fait 7 s après le premier `build`. Pas de `forget` ;
  - **CA6b** : retrait à 10 s, puis nouveaux `hubs` (`didUpdateWidget`), puis réponse fraîche : **pas de rangée**,
    mais `remember` est appelé. L'onglet masqué puis de nouveau visible (`TickerMode`) donne une nouvelle visite
    (rangée grise selon le souvenir, ou rangée réelle par CA9) ;
  - **réponse en retard d'une bibliothèque précédente** (génération) : ignorée ;
  - **minuteur annulé** au `dispose` et au changement de bibliothèque (aucun `setState` après `dispose`) ;
  - **CA13** : un échec (`conclusive: false`) n'appelle ni `remember` ni `forget` ;
  - **CA12** : un cas avec une bibliothèque Jellyfin (`MediaBackend.jellyfin`) et une session Jellyseerr.
- Critères d'acceptation couverts : CA1, CA3, CA5, CA6, CA6b, CA7, CA8, CA9, CA13, CA12.

### T5 — Crochets de l'onglet Recommandé (préchargement et zone d'aperçu)
- Complexité : S
- Dépend de : T4 (fonctions réexportées), T3 (même fichier `hooks_test.dart`)
- Fichiers :
  - modifier `lib/screens/libraries/tabs/library_recommended_tab.dart` (**upstream**, 3 lignes marquées) ;
  - modifier `test/fork/recent_requests/hooks_test.dart`.
- À faire :
  - première instruction de `_loadRecommendedHubs` :
    `unawaited(forkWarmUpRecentRequestCounts(context, widget.library)); // FORK: demandes-recentes-sans-saut — read the row-size memory while the hubs load`
  - ligne 59 :
    `void _setSpotlightItem(MediaItem item) { if (!forkIsSkeletonItem(item)) _spotlight.select(item); } // FORK: demandes-recentes-sans-saut — spotlight keeps the last real title`
    (sur une ligne, le corps en accolades évite d'utiliser une valeur `void` dans une expression conditionnelle)
  - dans `_buildTvContent` :
    `resolveSpotlight: () => _spotlight.resolve(forkSpotlightHubs(tvHubs)), // FORK: demandes-recentes-sans-saut — spotlight ignores the placeholder row`.
    Ne pas changer `hubs: tvHubs`, qui sert à la hauteur du rail.
- Tests : `hooks_test.dart`, nouveau test « library_recommended_tab.dart carries the placeholder hooks ». Il vérifie
  la présence des trois appels (`forkWarmUpRecentRequestCounts(`, `forkIsSkeletonItem(item)`,
  `forkSpotlightHubs(tvHubs)`), chacun sur une ligne qui contient `FORK: demandes-recentes-sans-saut`.
- Critères d'acceptation couverts : CA1 (lecture à temps), CA11 (lecture à l'ouverture seulement), CA14.

### T6 — Test de bout en bout du focus et de la zone d'aperçu sur TV
- Complexité : M
- Dépend de : T5
- Fichiers : créer `test/fork/recent_requests/recent_requests_tv_focus_test.dart`.
- À faire : monter `ForkRecentRequestsShelf` avec un constructeur qui reproduit `_buildTvContent` :
  - `TvSpotlightScaffold`, `TvBrowseRail` réel, `TvSpotlightController` ;
  - `onFocusedItemChanged` qui ignore les éléments gris, comme T5 ;
  - `resolveSpotlight` sur `forkSpotlightHubs`.

  Simuler le D-pad (`tester.sendKeyEvent`). La sonde est `onFocusedHubItemChanged` (hub et élément focalisés), plus
  la valeur de `TvSpotlightController`.
- Tests :
  - **CA10** : Bas depuis « Continuer à regarder » mène à la rangée grise, colonne 0. Droite donne la colonne 1. Bas
    mène à la rangée suivante. OK sur une affiche grise : aucune navigation (`Navigator` sans nouvelle route) ;
  - **CA10b** : focus sur la 3e affiche grise, puis réponse à 2 vraies affiches : focus sur la 2e vraie. Focus sur la
    2e grise, puis 5 vraies : focus sur la 2e vraie ;
  - **CA10b** : focus sur la 3e grise, puis retrait (minuteur) : focus sur la 1re affiche de la rangée suivante.
    Même chose quand la rangée grise est la dernière : 1re affiche de la rangée précédente ;
  - **CA10c** : focus sur la rangée du dessous, puis retrait : même élément focalisé. Focus au-dessus, puis
    remplacement : même élément focalisé ;
  - **CA14** : sans « Continuer à regarder », la rangée grise est à l'index 0. À l'ouverture, `resolveSpotlight()`
    renvoie le premier élément de la rangée suivante, jamais un élément gris. Avec le focus sur une affiche grise, la
    zone garde le dernier vrai titre. Dès que la vraie affiche focalisée arrive, la zone passe à son titre.
- Critères d'acceptation couverts : CA10, CA10b, CA10c, CA14.

### T7 — Recette sur la Fire TV Stick
- Complexité : M (mesures vidéo, Overseerr mis en pause)
- Dépend de : T6
- Fichiers : aucun (compte rendu dans la réponse de l'agent).
- À faire : voir « Vérification globale », partie 2.
- Critères d'acceptation couverts : CA1, CA3, CA5, CA6, CA6b, CA10, CA10b, CA10c, CA11, CA13, CA14.

## Vérification globale

### 1. Contrôles automatiques

Préfixe de chaque commande :
`export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21`.

```bash
dart format <fichiers modifiés>
scripts/codegen.sh --check
dart run scripts/checks/check_analyzer.dart
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh test/fork/recent_requests/
scripts/run_tests.sh                       # toute la suite (media_card.dart est partagé)
```

Aucune traduction ajoutée : le titre de la rangée existe déjà, et `check_hardcoded_strings.py` doit rester vert.

### 2. Recette sur la Fire TV Stick uniquement (192.168.1.173, jamais la Freebox)

Préparation :
- APK `flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true --dart-define-from-file=popkino_secrets.json` ;
- installer `app-armeabi-v7a-release.apk`, signé avec la clé de debug ;
- `adb logcat` filtré sur `RecentRequests`.

1. **Démarrage (CA11)** :
   - 5 fois `am force-stop` puis `am start -W`, en relevant la médiane de `TotalTime` ;
   - comparer à l'APK `main`, dans **la même configuration que pour `demandes-recentes-overseerr`** (même écran de
     démarrage, à noter dans le compte rendu). Tolérance : ± 10 % ;
   - `RecentRequests: row sizes loaded` n'apparaît qu'après l'ouverture d'une bibliothèque Films ou Séries.
2. **Absence de saut (CA1, CA3)** :
   - première ouverture de « Séries » pour remplir le souvenir, puis `am force-stop` ;
   - lancer `adb shell screenrecord --size 1280x720 --time-limit 12 /sdcard/rr.mp4`, ouvrir « Séries », puis ne plus
     toucher la télécommande ;
   - extraire les images : `ffmpeg -i rr.mp4 -vf fps=10 f_%03d.png` ;
   - image A (affiches grises) et image B (vraies affiches) : `magick compare -metric AE -fuzz 10%` sur le bandeau du
     titre de la rangée suivante, sur le titre « Demandes récentes » et sur la rangée du dessus. Attendu : environ
     0 pixel ;
   - **contrôle négatif** avec l'APK `main` : AE élevé ;
   - vérifier aussi qu'aucune image ne montre les rangées sans la rangée grise (CA1).
3. **Après redémarrage de la TV (CA1)** : `adb reboot`, puis rouvrir « Séries » : les affiches grises sont présentes
   dès la première image.
4. **Aspect (CA2, CA4)** : affiches grises de la taille des vraies, sans titre ni badge ; deux traits gris
   seulement si T3 les a gardés.
5. **Focus (CA10, CA10b, CA10c)** :
   - Bas sur la 2e affiche grise, puis attendre : le focus est sur la 2e vraie affiche ;
   - OK sur une affiche grise : rien ;
   - appui long : rien.
6. **Zone d'aperçu (CA14)** :
   - bibliothèque sans « Continuer à regarder » (ou Animés si elle convient) : à l'ouverture, la zone du haut montre
     un vrai titre ;
   - focus sur une affiche grise : la zone garde le dernier vrai titre.
7. **Panne (CA6, CA6b)** :
   - `docker pause` du conteneur Overseerr, puis attendre 60 s (fin du cache négatif) ;
   - ouvrir « Séries » avec le focus sur une affiche grise : retrait en 10 s au plus (horodatage de la vidéo), puis
     focus sur la 1re affiche de la rangée suivante, visible ;
   - `docker unpause` pendant la même visite : **la rangée ne revient pas**. Une tirette de rafraîchissement ou le
     retour de lecture d'un épisode ne la fait pas revenir non plus ;
   - quitter puis rouvrir la bibliothèque : affiches grises, puis vraies affiches (la bibliothèque n'a pas été
     oubliée).
8. **Oubli (CA5, CA13)** :
   - supprimer les demandes de séries dans Overseerr, attendre 30 s, rouvrir : retrait de la rangée ;
   - après `am force-stop`, rouvrir : aucune affiche grise ;
   - `adb shell run-as <pkg> cat cache/popkino_recent_requests/row_sizes.json` (APK debug ou build profilé) :
     uniquement `v`, `owner` et `rows` avec `n` et `d`.
9. **Réouverture rapide (CA9)** : quitter puis rouvrir « Séries » en moins de 30 s : vraies affiches directement.
10. **Changement de compte (CA13)** : se reconnecter à Overseerr avec un autre compte, puis ouvrir « Séries » :
    aucune affiche grise.
11. **Mémoire et fluidité** :
    - `dumpsys meminfo <pkg>` : PSS à moins de 1 Mo de l'APK `main` ;
    - D-pad fluide pendant la phase grise.

## Risques restants

- **Colonne 0 hors de l'écran après un retrait** : le rail ne fait pas défiler horizontalement la rangée qui reçoit
  le focus.
  - Si l'utilisateur était allé loin à droite dans la rangée suivante puis était remonté, la première affiche peut
    rester hors de l'écran jusqu'à la touche suivante.
  - C'est un comportement upstream existant pour toute rangée qui disparaît.
  - Remède de réserve, seulement si la recette le montre : un crochet D11 dans `TvBrowseRail.didUpdateWidget`
    (`_scrollToItemAfterLayout(animate: false)` quand la rangée active a disparu), à proposer aussi à l'upstream.
- **Première ouverture de la session** : si les rangées sont servies plus vite que la lecture d'un fichier de
  quelques Ko (cache d'API), pas d'affiches grises pour cette ouverture (filet). C'est un saut identique à
  aujourd'hui, jamais pire.
- **Traits gris** : leur maintien dépend du test de géométrie de T3 (CA3 prime).
- **Fusion upstream** : 5 lignes dans 2 fichiers.
  - Le crochet en tête de `MediaCardState.build` est le plus exposé, si l'upstream restructure `build`.
  - Les lignes de `library_recommended_tab.dart` (`_setSpotlightItem`, `resolveSpotlight`, `_loadRecommendedHubs`)
    touchent du code stable.
  - Les gardes de `hooks_test.dart` signalent toute perte de crochet.
- **Cache vidé par Fire OS** : on retombe sur le comportement de CA7, sans erreur.
