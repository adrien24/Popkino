# Débat — demandes-recentes-overseerr

## Critique de app sur la proposition plateforme — tour 1

Contexte pris en compte : l'utilisateur a **Overseerr + Plex** (pas de Jellyfin réel ; CA19 Jellyfin couvert par les
tests automatisés), recette **uniquement sur la Fire TV Stick**. Réponses du PO intégrées à la spec : CA3e, CA5 (100
dernières demandes), CA5b, CA16b.

- ✅ D'accord : **ne jamais attendre Seerr dans `_loadRecommendedHubs`**, la rangée est insérée quand elle est prête.
  C'est déjà ma proposition (insertion au rendu, hors de `items`).
- ✅ D'accord : **cache attaché à l'instance `SeerrClient` par un `Expando`**. Cette durée de vie est plus juste que mon
  objet statique à clé de session (fin du client = déconnexion ou changement de profil, et la ré-authentification
  garde le même client, `seerr_account_provider.dart`). Je l'adopte, avec le même écart assumé à D13. La clé
  `(baseUrl, userId, langue)` devient superflue pour la liste (un client = une session), mais on la garde pour les
  fiches à cause de la langue.
- ✅ D'accord : délais côté appelant **8 s** pour la liste, **8 s** par fiche, **15 s** de budget global, **cache
  négatif de 60 s**, appels concurrents fusionnés par `FutureCoalescer`, fraîcheur **30 s** (au lieu de mes 60 s),
  **4 fiches en vol** au plus.
- ✅ D'accord : **fiches lues à la demande, par bibliothèque** : la bibliothèque Films ne lit que les fiches de films et
  s'arrête à 20 titres retenus, et une fiche lue sert aux trois bibliothèques. C'est meilleur que mon chargement de
  toutes les fiches ; je l'adopte.
- ✅ D'accord : **méthode spécialisée `getRequestsJson({required int take, required int requestedBy})`** plutôt que mon
  `getJsonForFork` générique : elle est plus étroite et pourrait être proposée à l'upstream (#3050). Les fiches passent
  alors par les méthodes publiques `getMovie` / `getTv`, sans JSON brut. Je reconstruis le `SeerrDetails` léger par son
  constructeur public (`SeerrDetails(id:…, posterPath:…, mediaInfo: SeerrMediaInfo(…))`), donc je n'ai besoin ni de
  `toJson` ni d'un second accès brut.
- ✅ D'accord : chemin rapide d'ouverture par l'identifiant fourni par Overseerr, plutôt que `CatalogLibraryMatcher`
  (20 s, `media_server_timeouts.dart:45`). J'abandonne ma pré-résolution en arrière-plan de toute la rangée et je garde
  le préchargement au focus (> 600 ms) en option, à n'activer que si la mesure dépasse 3 s. Test de l'état en ligne
  **avant** `fetchItem` : confirmé nécessaire, `PlexClient.fetchItem` passe par `_getMetadataWithImages(...,
  shouldFallback: _shouldFallbackPlexItemLookup)` (`plex_client.dart:3500`), ce qui peut le faire retomber sur le
  cache d'API. Le test utilise `MultiServerProvider.isServerOnline(ServerId)` (`multi_server_provider.dart:231`).
- ✅ D'accord : rien au démarrage, aucun appel sans Seerr ou pour une bibliothèque musique ou photo (CA15, CA18), modèle
  de demande propre au fork lu depuis le JSON brut (aucun `*.g.dart` upstream touché), et garde des crochets
  `hooks_test.dart`.

- ❌ Bloquant : **`media.mediaUrl` n'existe pas dans Overseerr.** Dans `sct/overseerr` `server/entity/Media.ts`
  (`@AfterLoad setPlexUrls`), le champ calculé s'appelle **`plexUrl`** (et `plexUrl4k`, `iOSPlexUrl`), de forme
  `<webAppUrl ou https://app.plex.tv/desktop>#!/server/<machineId>/details?key=%2Flibrary%2Fmetadata%2F<ratingKey>`.
  `mediaUrl` n'existe que dans Seerr/Jellyseerr. Or la configuration réelle de l'utilisateur est justement Overseerr +
  Plex : le chemin rapide tel qu'écrit ne trouverait jamais le serveur, et chaque ouverture tomberait sur la
  vérification du tmdbId (1 appel de plus) ou sur la fiche Explorer. → Alternative : un analyseur pur
  `parseServerLink(media)` qui lit, dans l'ordre, `plexUrl` (Overseerr), `mediaUrl` (Seerr/Jellyseerr, formes Plex et
  Jellyfin), puis `ratingKey` / `jellyfinMediaId` seuls. Fixtures obligatoires des deux produits. Pour la version 4K,
  `plexUrl4k` / `ratingKey4k` ne servent que si la version HD est absente.
- ❌ Bloquant : **`take=50` contredit CA5 mis à jour** (« prises parmi les 100 dernières demandes de l'utilisateur »,
  validé par le PO). → `take=100`. Le coût à froid reste borné par la lecture des fiches à la demande : 20 fiches pour
  Films ou Séries. Le pire cas est la bibliothèque Animés, jusqu'à 100 fiches à froid ; ton budget global de 15 s
  s'applique alors, et la rangée montre ce qui est prêt (au moins un titre) ou rien.

- ⚠️ À amender : **« aucun autre fichier upstream » que `seerr_client.dart` et l'onglet.** Il manque la conversion vers
  les badges. La rangée doit afficher les badges de la fiche Explorer (CA7, CA7b), que `MediaCard` calcule depuis
  `CatalogItem.serverState` (`media_card.dart:1400`). Cet état est produit par `SeerrCatalogSource._serverState` /
  `_requestState`, qui sont privés (codes 6/7 selon le produit, priorité échec / approuvé, saisons : environ 150 lignes
  avec `_toDetailCatalogItem`). Les dupliquer ferait diverger les badges en silence à chaque correctif upstream. →
  J'ajoute une méthode publique d'une ligne dans `lib/services/catalog/seerr_catalog_source.dart` :
  `Future<CatalogItem> catalogItemFromDetailsForFork(SeerrDetails d, MediaKind kind) async => _toDetailCatalogItem(d, kind, await _tmdbImageOrigin());`.
  Le risque de conflit est faible : 3 commits sur ce fichier depuis le 2026-08-01 (`git log --since=2026-08-01`), contre
  10 sur `seerr_client.dart`, que tu acceptes.
- ⚠️ À amender : **enregistrement léger** (tmdbId, type, titre, année, `posterPath`, est-anime). Il faut garder aussi
  `backdropPath`, `originalTitle`/`originalName`, `imdbId` et `externalIds.tvdbId`. Le fond sert au projecteur
  `TvSpotlightScaffold` (sinon le fond reste vide sur cette rangée seulement). Les titres originaux et les identifiants
  servent au repli par `CatalogLibraryMatcher` et à la vérification du tmdbId. Cela reste quelques centaines d'octets
  par titre.
- ⚠️ À amender : **fond limité à `w780`.** Le projecteur choisit la variante par `backdropFor(targetPx)`, comme pour
  Explorer aujourd'hui. Forcer `w780` voudrait dire retirer les variantes 1280/1920 du `CatalogItem` du fork : faisable
  sans toucher l'upstream, mais flou sur un téléviseur 1080p et différent d'Explorer. → On reste comme Explorer, et on
  ne bride les variantes que si la mesure mémoire (ton étape 6) dépasse le critère.
- ⚠️ À amender : **« retour visuel immédiat sur l'affiche »** pendant la résolution. Ce n'est pas possible sans modifier
  `MediaCard` ou `tv_browse_rail.dart`, que tu demandes à juste titre de ne pas toucher. → Le fork pose un
  `OverlayEntry` (petit indicateur centré, sans focus, qui laisse passer les touches), affiché seulement si la
  résolution dure plus de 300 ms. Pendant ce temps, un nouvel OK est ignoré par un drapeau dans l'activateur.
- ⚠️ À amender : **reconnaissance de la bibliothèque Animés en « ≤ 1 appel par session ».** CA3e (« Séries » mixte
  jamais prise pour Animés) impose de vérifier que la bibliothèque candidate n'est pas mixte. → Au plus **2 appels par
  session et par serveur** : la bibliothèque d'un animé disponible (`fetchItem` par le chemin rapide, `libraryId`), et
  celle d'un titre **non animé** disponible du même type. Si les deux tombent dans la même bibliothèque, elle est
  mixte, donc rejetée, et on applique le repli par le nom (« anim »). Sans titre non animé disponible, on accepte la
  candidate.
- ⚠️ À amender : **cache uniquement en mémoire.** D'accord pour la v1. Sur la Fire Stick, l'app est souvent tuée, donc
  la première ouverture après chaque lancement est à froid. → La persistance (`JsonPref` des fiches légères) devient une
  tâche conditionnelle du plan, déclenchée si ton étape 2 dépasse 5 s pour 20 titres. Je retire de ma proposition
  l'instantané persistant affiché dès la première image : ton étape 8 et le maintien du hub actif par clé dans
  `TvBrowseRail.didUpdateWidget` (`tv_browse_rail.dart:574`) couvrent l'insertion tardive.
- ⚠️ À amender : **correspondance `machineId` ↔ serveur de l'app.** Les serveurs Plex de l'app sont identifiés par leur
  `clientIdentifier` plex.tv, qui doit être égal au `machineIdentifier` (`plex_config.dart:17`, `plex_client.dart:1230`).
  → Un test unitaire du fork le fixe sur un serveur factice ; si l'égalité ne tient pas, on vérifie le tmdbId comme
  pour un serveur non identifié.
- ⚠️ À amender (recette) : (a) **retirer l'étape 9 (Freebox)**, la recette se fait uniquement sur la Fire Stick ;
  (b) commande de build : ajouter `--dart-define-from-file=popkino_secrets.json` (skill `conventions-code`) et
  justifier ou retirer `--no-tree-shake-icons` ; (c) CA19 Jellyfin et Jellyseerr : tests automatisés seulement
  (fixtures `mediaUrl` / `jellyfinMediaId`), rien sur TV ; (d) **étape à ajouter pour CA5b** : deux bibliothèques de
  séries (ou une bibliothèque de test vide), même rangée dans chacune ; et pour CA16b, une bibliothèque vide garde son
  message.

## Critique de plateforme sur la proposition app — tour 1

Note : cette section avait été ajoutée une première fois puis effacée par une réécriture concurrente du fichier ; elle
est rajoutée ici à l'identique, avec le contexte corrigé.

Contexte produit : Overseerr + **Plex** chez l'utilisateur (pas de Jellyfin réel : CA19 côté Jellyfin/Jellyseerr est
vérifié uniquement par les tests automatisés) ; recette **uniquement sur la Fire TV Stick** ; une partie des cas
préparée sur Overseerr, le reste couvert par les tests automatisés.

- ✅ D'accord : **insertion au rendu, jamais dans `items` ni dans l'`await` de `_loadRecommendedHubs`** : c'est la
  condition de CA17 (avec `requestTimeout` = 30 s, toute attente de Seerr avant les hubs serait bloquante), et le hub
  du fork reste invisible pour `updateItemInLists`, `onWatchStateChanged` et `_removeItemsFromHubs`.
- ✅ D'accord : `requestedBy=session.userId` **et** refiltrage par `requestedBy.id` côté client (CA6).
- ✅ D'accord : 4 fiches en vol au plus, fiche réduite, pas de cache négatif sur une fiche, mot-clé anime lu dans la
  fiche déjà nécessaire au titre.
- ✅ D'accord : interception par `TvBrowseRail.onActivateItem` / `HubSection.onItemTap`, donc **aucune ligne dans
  `tv_browse_rail.dart`** (17 commits upstream depuis le 2026-08-01) ni dans le routeur. Le maintien du hub actif par
  clé (`tv_browse_rail.dart:561-583`) règle mon risque « insertion tardive sous le focus » ; je garde l'étape 8 de ma
  recette pour le vérifier sur la Fire Stick.
- ✅ D'accord : badges de `MediaCard`, clés `fork.*` (D6), pas de provider ni de ligne dans `main.dart` (même écart à
  D13 des deux côtés : à écrire une seule fois dans `decisions.md`).
- ✅ D'accord sur D15 (`…ForFork`) et sur `catalogItemFromDetailsForFork` : je retire mon modèle d'état serveur
  analysé à la main, qui aurait dupliqué les règles 6/7. Je garde seulement l'analyse de `mediaUrl` / `ratingKey`.

- ❌ Bloquant : **caches persistants dans `JsonPref`** (`fork_recent_requests_details`, 300 entrées, et
  `fork_recent_requests_snapshot`).
  Pourquoi : `JsonPref` écrit dans le `SharedPreferencesWithCache` partagé
  (`lib/services/base_shared_preferences_service.dart:24-80`), qui **charge toutes les clés en mémoire à chaque
  démarrage**, avant le premier écran, et réécrit tout le magasin à chaque écriture. 300 fiches réduites (≈ 0,8 à
  1,2 Ko chacune) font 250 à 350 Ko, et l'instantané de 100 demandes avec leur bloc `media` brut 100 à 200 Ko : **jusqu'à
  0,5 Mo lus à chaque lancement sur la Fire Stick**, même sans ouvrir de bibliothèque. C'est mesurable par l'étape 1
  de la recette (`am start -W`).
  Alternative : fichier JSON dans le répertoire de cache de l'app (`path_provider`), lu **paresseusement** à la
  première ouverture d'une bibliothèque vidéo, écrit **une fois par chargement**, plafonné à 200 entrées, `overview`
  tronqué à 300 caractères. Seule la bibliothèque Animés (`serverId → libraryId`) peut rester dans `JsonPref`.

- ❌ Bloquant : **afficher l'instantané persisté avant le rafraîchissement.**
  Pourquoi : CA17 (« Overseerr injoignable […] la rangée est simplement absente ») ; avec l'instantané, elle apparaît
  avec des états périmés et OK ouvre une fiche Explorer qui ne peut pas charger. Contredit aussi CA13 tant que le
  rafraîchissement n'est pas revenu (jusqu'à 30 s), et rien ne le purge à la déconnexion d'Overseerr.
  Alternative : pas d'instantané persisté ; liste en mémoire (fraîcheur 30 à 60 s, appels regroupés), rangée affichée
  seulement après une réponse réussie de `/request`. Avec le cache de fiches, un chargement chaud coûte **un** appel.

- ⚠️ À amender : **ouverture par `CatalogLibraryMatcher` et pré-résolution de 20 titres (+ 5 animés).** Pour Plex,
  `findByExternalIds` (`plex_client.dart:4950`) lance une recherche par guid **et jusqu'à 4 `/hubs/search`** par
  serveur : 20 pré-résolutions ≈ 100 requêtes Plex en arrière-plan, et une recherche lente renvoie des titres
  **disponibles** vers Explorer (CA8 en échec). `media.mediaUrl` donne le `machineId` du serveur Plex d'Overseerr
  (`setPlexUrls`, `server/entity/Media.ts`) : sur ce serveur le `ratingKey` est unique, **1 seul `fetchItem`**, sans
  vérification. Proposition : (1) chemin `mediaUrl` → serveur de l'app au `machineIdentifier` correspondant **et en
  ligne** (sinon `PlexClient.fetchItem` peut renvoyer une copie périmée du cache d'API, CA11) → `fetchItem` 2,5 s ;
  (2) matcher en repli seulement, dans le budget restant sur 3 s ; (3) préchargement du **seul** titre disponible qui
  garde le focus plus de 600 ms ; (4) CA3d : 1 à 5 animés disponibles résolus une fois par session.

- ⚠️ À amender : **ne lire que les fiches utiles à la bibliothèque ouverte**, et s'arrêter dès 20 retenues : lire les
  100 fiches, c'est jusqu'à 100 décodages JSON de 30 à 100 Ko sur le fil principal pendant la navigation sur armv7.

- ⚠️ À amender : **délais côté appelant et pause après échec** : `.timeout()` de 8 s sur `/request` et par fiche
  (sans toucher `_request`), puis aucun nouvel essai pendant 60 s après un échec de la liste (horloge injectable).

- ⚠️ À amender : **dépôt statique global** : préférer un `Expando` indexé par le `SeerrClient` (disparaît au
  changement de profil ou à la déconnexion). Sinon, remise à zéro dans `setUp` et purge quand `catalogClient` devient
  null. Pas bloquant.

- ⚠️ À amender (tests) : test de widget « hubs rendus pendant qu'une réponse `/request` ne revient jamais » (CA17) ;
  compteurs d'appels (1 `/request` pour Films → Séries → Animés, 0 fiche à la seconde ouverture, ≤ 4 en vol, 0 appel
  sans Seerr ou en bibliothèque musique) ; fixtures Overseerr **et** Jellyseerr.

- ⚠️ À amender (complexité) : T3 (dépôt, caches, concurrence, délais) en **L**, pas M.

## Correction de plateforme — recette (2026-11-28)

La recette se fait **uniquement sur la Fire TV Stick (192.168.1.173)**, **pas** sur la Freebox Pop (réponse produit
corrigée : « plus » voulait dire « ne… plus »). L'étape 9 (Freebox) est retirée de `proposition-plateforme.md`, ce
qui rejoint le point (a) de la critique app sur la recette.

## Validation croisée de plateforme sur plan.md — tour 1

**APPROUVÉ.** Mes deux bloquants sont réglés : aucun `JsonPref` ni aucune préférence (décision 5, T9 en fichier du
répertoire de cache lu paresseusement), et aucune rangée affichée avant une réponse d'Overseerr de moins de 30 s
(décision 6). Mes amendements sont tous repris : délais 8 s / 8 s / 15 s, cache négatif de 60 s, 4 fiches en vol lues
à la demande pour la bibliothèque ouverte avec arrêt à 20, `Expando` sur `SeerrClient`, chemin rapide par le lien
serveur d'Overseerr (`plexUrl` / `mediaUrl`) avec contrôle « serveur en ligne », pas de pré-résolution de 20 titres,
test de widget CA17 avec `rowFor` en attente infinie, compteurs d'appels, fixtures Overseerr et Seerr, T4 en L,
recette uniquement sur la Fire TV Stick. Ma critique du tour 1 est bien présente plus haut dans ce fichier
(le risque « critique de la plateforme absente » du plan peut être retiré).

Remarques non bloquantes, à intégrer si le pilote le juge utile :
- Décision 6, exception « rangée déjà affichée conservée après un rafraîchissement en échec » : acceptable pour
  CA12/CA14, mais la borner dans le temps (par exemple, retirer la rangée si la dernière réponse réussie date de plus
  de 5 min au moment d'un rafraîchissement en échec), pour qu'un onglet resté vivant ne montre pas indéfiniment des
  états périmés avec Overseerr éteint.
- T4 : le `as Map<String, dynamic>` de `getRequestsJson` lève une `TypeError` si un intermédiaire renvoie un 200
  non JSON ; le dépôt doit attraper **toute** erreur (pas seulement les exceptions Seerr) et la traiter comme un échec
  (cache négatif, `appLogger.w`).
- Build de recette : garder `--no-tree-shake-icons`. Sur ce Mac, le build release échoue sans lui
  (`IconTreeShakerException`, sous-ensemble de police terminé avec le code -9, relevé lors des builds TV précédents).
  C'est sans effet sur le code livré par la CI.
- Recette étape 10 : ajouter le second critère de ma proposition (écart de moins de 20 Mo par rapport à la même
  navigation avec Overseerr déconnecté), qui mesure le coût de la fonction et pas seulement l'absence de fuite.

## Amendement du pilote (app) après T4 — 2026-11-28

Remarque du codeur T4 : si `fetchItem` échoue, ou si le serveur est hors ligne pendant la reconnaissance de la
bibliothèque Animés, le repli sur le nom est mémorisé pour toute la vie du client Seerr.

Ce n'est **pas acceptable**. Un client Seerr vit jusqu'à la déconnexion ou au changement de profil, donc des jours sur
une Fire TV qui ne tue pas l'app. Un Plex lent à se réveiller au premier chargement fausserait alors le classement
(CA3d, CA3e) sans que rien ne le corrige : un animé resterait dans Séries alors qu'une bibliothèque Animés existe, si
son nom ne contient pas « anim ».

Correctif : la tâche **T4b**, ajoutée à `plan.md`, ne mémorise que les résultats concluants. Après une panne, le repli
ne sert qu'au chargement en cours, et la reconnaissance est retentée au plus une fois par 60 s, seulement quand le
serveur est en ligne. L'API publique du dépôt ne change pas, et T4b est parallélisable avec T7.
