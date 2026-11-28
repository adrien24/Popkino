# Proposition plateforme — demandes-recentes-overseerr

Auteur : architecte-plateforme. Périmètre : performances sur Fire TV Stick (Android 11, `armeabi-v7a`, peu de RAM),
appels réseau, cache, images, délais, panne d'Overseerr, impact sur le démarrage, isolement du code fork, tests et
recette sur TV. L'architecture Dart (modèle de la rangée, intégration au rail TV, navigation, focus) revient à
`architecte-app`, qui pilote. Ce document fixe des **contraintes et des budgets** que sa proposition doit respecter.

## Compréhension de la spec

Dans l'onglet d'accueil d'une bibliothèque Films / Séries / Animés, une rangée « Demandes récentes » montre les 20
dernières demandes Overseerr/Jellyseerr de l'utilisateur pour ce type, avec un badge d'état. OK ouvre le titre du
serveur s'il est disponible, sinon sa fiche Explorer. Un titre est un animé s'il porte le mot-clé TMDB anime.

Critères qui touchent mon périmètre :
- **CA8** : fiche serveur ouverte en moins de 3 s sur la Fire TV Stick.
- **CA17** : Overseerr injoignable → les autres rangées s'affichent **dans le même temps qu'aujourd'hui**, rangée
  absente, aucune erreur bloquante.
- **CA15 / CA18** : pas de rangée, donc **aucun appel réseau**, sans Overseerr ou pour une bibliothèque musique/photo.
- **CA6** : uniquement les demandes de l'utilisateur, y compris pour un administrateur (et donc aucune fuite entre
  profils).
- **CA11 / CA13** : repli sans blocage, état à jour à la réouverture (fraîcheur du cache).
- **CA3b / CA3d** : la règle anime impose de lire la fiche de chaque titre, et la reconnaissance de la bibliothèque
  Animés coûte des appels au serveur : ce sont les deux postes de coût réseau.
- Contrainte : aucune différence entre la version GitHub et les versions store ; aucune donnée nouvelle collectée.

## Existant

Lu dans le code :

- `lib/services/seerr/seerr_client.dart` : client authentifié (cookie `connect.sid`, ré-authentification silencieuse
  coalescée, `onSessionInvalidated`). Méthodes publiques utiles : `getMovie(tmdbId)` / `getTv(tmdbId)` (fiche
  complète avec `keywords`, `posterPath`, `mediaInfo`), `getPublicSettings()` (mis en cache pour la vie du client) et
  `tmdbImageProxyUrl()`. **Aucune méthode ne liste les demandes** (`GET /request`) ; `_request` est privé à la
  bibliothèque Dart, donc inaccessible depuis `lib/fork/` (une extension ne le voit pas).
- `lib/services/seerr/seerr_http_client.dart` : `send(..., timeout = SeerrConstants.requestTimeout)`, requête
  abandonnable. `SeerrClient._request` ne transmet **pas** de timeout : chaque appel vit jusqu'à **30 s**
  (`SeerrConstants.requestTimeout`), et la ré-authentification jusqu'à 20 s (`authTimeout`).
- `lib/services/seerr/seerr_constants.dart` : `animeKeywordId = 210024`, `probeTimeout = 8 s`.
- `lib/models/seerr/seerr_request.dart` / `seerr_media.dart` : `SeerrRequest` (id, status, is4k, media, seasons) et
  `SeerrMediaInfo` (tmdbId, status brut, seasons). **Ni `createdAt`, ni `mediaType`, ni `ratingKey`,
  `jellyfinMediaId` ou `mediaUrl`** : ces modèles ne suffisent pas, et les étendre régénère des `*.g.dart` upstream.
- `lib/providers/seerr_account_provider.dart` : `catalogClient` (null si non connecté), un client par liaison de
  profil (nouveau client au changement de profil ; la ré-authentification garde le même client).
- `lib/services/catalog/seerr_catalog_source.dart` : conversion vers `CatalogItem` avec affiches en plusieurs largeurs
  (`w342`, `w500`, `w780`), via le proxy d'images Overseerr s'il est activé. `fetchDetail` lance **deux** appels
  (fiche + recommandations) : à ne pas utiliser pour la rangée.
- `lib/services/catalog/catalog_library_matcher.dart` : recherche inverse catalogue → bibliothèques, mémoïsée, avec un
  budget `MediaServerTimeouts.libraryLookup` de **20 s** : incompatible tel quel avec les 3 s de CA8.
- `lib/screens/libraries/tabs/library_recommended_tab.dart` : `loadItems()` → `runLoadTransaction(_loadRecommendedHubs)`
  qui **attend** `fetchLibraryHubs` (budget `libraryHubDeadline` = 20 s) puis remonte « Continuer à regarder » en tête.
  Sur TV, rendu par `TvSpotlightScaffold` + `TvBrowseRail` (liste de `MediaHub`).
- `lib/utils/platform_http_client_io.dart` : sur Android, `IOClient` de `dart:io` (aucune limite de connexions par
  hôte côté client) : c'est à nous de plafonner le parallélisme.
- `lib/widgets/optimized_media_image.dart` : chaîne d'images existante, décodage redimensionné (`memCache*`).
- `lib/utils/app_logger.dart` : `appLogger.d` est émis en release si le réglage « journaux de débogage » est activé
  (`setLoggerLevel`) ; `SeerrHttpClient.send` journalise déjà `Seerr GET <chemin> -> <code> (<ms>ms)`. C'est la base
  de mesure de la recette, sans instrumentation nouvelle.
- Activité upstream des fichiers concernés depuis le 2026-08-01 (`git log --since`) : `tv_browse_rail.dart` 17
  commits, `seerr_client.dart` 10, `library_recommended_tab.dart` 6, `seerr_request.dart` 2. **`tv_browse_rail.dart`
  est le fichier le plus exposé aux conflits.**

API Overseerr/Jellyseerr vérifiée dans les sources (`server/routes/request.ts`, `server/entity/Media.ts`) :
- `GET /api/v1/request?take&skip&filter&sort&requestedBy` : `take` vaut 10 par défaut. Sans les droits
  `MANAGE_REQUESTS`/`REQUEST_VIEW`, le serveur restreint aux demandes de l'appelant ; **avec** ces droits (cas de
  l'administrateur), il renvoie celles de tout le monde **sauf si `requestedBy` est fourni** → `requestedBy=<userId>`
  est obligatoire pour CA6. Les relations `media`, `seasons`, `requestedBy`, `modifiedBy` sont jointes.
- `mediaType` et `sortDirection` n'existent que dans Seerr/Jellyseerr récents, **pas dans Overseerr** (`sct/overseerr`
  `develop`) : le filtrage par type se fait côté app. Tri : Overseerr trie par `request.id` décroissant, Seerr accepte
  `sort=added` (= `createdAt`) ; les deux donnent « plus récente d'abord ».
- Le `media` joint expose `ratingKey` (Plex), `jellyfinMediaId` (Jellyfin/Emby) et `mediaUrl`, calculé à la lecture :
  `…#!/server/<machineId>/details?key=%2Flibrary%2Fmetadata%2F<ratingKey>` pour Plex,
  `…/web/index.html#!/details?id=<jellyfinMediaId>&context=home&serverId=<serverId>` pour Jellyfin. **Le serveur cible
  est donc identifiable sans aucun appel**, ce qui rend CA8 tenable.
- Une demande ne porte ni titre ni affiche : le site d'Overseerr lui-même appelle `/movie/{id}` ou `/tv/{id}` pour
  chaque carte. La règle anime (CA3b) ne coûte donc **aucun appel de plus** : les `keywords` arrivent dans la fiche
  qu'il faut lire de toute façon pour le titre et l'affiche.

## Approche proposée

### 1. Budget réseau : 1 appel de liste + N fiches, partagés par les trois bibliothèques

| Appel | Quand | Nombre | Cache |
|---|---|---|---|
| `GET /request?take=50&skip=0&sort=added&filter=all&requestedBy=<userId>` | à l'ouverture d'une bibliothèque vidéo, si la liste en mémoire a plus de 30 s | 1 | mémoire, fraîcheur 30 s, appels concurrents fusionnés (`FutureCoalescer`, déjà dans le code) |
| `GET /movie/{tmdbId}` ou `/tv/{tmdbId}` | pour chaque demande utile à la bibliothèque ouverte, dans l'ordre (plus récente d'abord), jusqu'à 20 titres retenus | ≤ 50 à froid, **0** ensuite pour les titres déjà vus | mémoire, durée de vie du client Seerr ; un échec n'est pas mis en cache |
| `getPublicSettings()` (origine des images) | déjà en cache pour la vie du client | 0 ou 1 | existant |
| serveur Plex/Jellyfin, élément d'un animé disponible (bibliothèque Animés, CA3d) | une fois par session, seulement s'il existe une demande d'animé disponible | ≤ 1 (Plex) / ≤ 2 (Jellyfin, ancêtres) | mémoire, durée de vie du client |

- **Une seule liste pour Films, Séries et Animés** : elle est mise en cache au niveau du client Seerr, pas de l'onglet.
  Passer de Films à Séries puis à Animés en moins de 30 s coûte 1 appel de liste, pas 3.
- `take=50` : la liste mélange les trois catégories, et il faut assez de demandes pour en garder 20 par catégorie.
  Au-delà (plus de 50 demandes récentes d'autres types), une rangée peut en montrer moins de 20, ce que CA5 permet
  (« au plus »). Pas de pagination automatique dans la v1.
- **Fiches dans l'ordre et à la demande** : la bibliothèque Films ne lit que les fiches des demandes de films (et
  s'arrête dès 20 retenues) ; la bibliothèque Animés lit les deux types. Le pire cas à froid est donc la bibliothèque
  Animés : 50 fiches. Une fiche déjà lue sert aux trois bibliothèques.
- **Parallélisme plafonné à 4 fiches en vol** : `IOClient` n'a aucune limite, et 50 sockets ouverts d'un coup vers
  Overseerr sur une Fire Stick concurrencent les requêtes de hubs Plex/Jellyfin et le décodage JSON du fil principal.
  4 garde un temps de chargement raisonnable (≈ 50 / 4 × 300 à 600 ms ≈ 4 à 8 s pour le pire cas froid, ≈ 1 à 2 s pour
  20 fiches) sans saturer.
- **Ne garder que l'utile** : une fiche TV Overseerr pèse des dizaines de Ko (distribution complète, saisons, vidéos).
  Elle est convertie aussitôt en un enregistrement léger (tmdbId, type, titre, année, `posterPath`, est-anime) et le
  `SeerrDetails` est abandonné. Mémoire du cache : quelques centaines d'octets par titre, < 100 Ko au total.
- **Clé de cache** : `(baseUrl, userId, langue)`. Le titre est localisé par le paramètre `language` ; la clé empêche
  qu'un changement de profil ou de langue montre les demandes ou titres d'un autre contexte (CA6).

### 2. Où vit le cache : attaché au client Seerr, pas au `MultiProvider`

Proposition : un `Expando<RecentRequestsCache>` indexé par l'instance `SeerrClient` (dans `lib/fork/recent_requests/`).
Le cache naît avec le client et disparaît avec lui (changement de profil, déconnexion), sans écouteur ni nettoyage à
écrire, et **sans ligne dans `lib/main.dart`**. Rien n'est créé au démarrage.

**Écart assumé à D13** (« état global = `ChangeNotifier` singleton dans le `MultiProvider` ») : D13 vise un état observé
par l'interface et réservé à une distribution. Ici, aucun widget n'écoute le cache (la rangée le lit une fois par
ouverture), la fonction existe dans toutes les distributions, et la durée de vie correcte est exactement celle du
client Seerr. Si `architecte-app` préfère un provider, je n'en fais pas un bloquant, à deux conditions : création
paresseuse (aucun appel au démarrage) et invalidation au changement de `catalogClient`.

### 3. Délais et panne d'Overseerr (CA17)

- **La rangée ne retarde jamais les autres rangées.** Le chargement Seerr ne doit **pas** être attendu dans
  `_loadRecommendedHubs` : il démarre en parallèle des hubs, et la rangée est insérée sous « Continuer à regarder »
  quand elle est prête (immédiatement si le cache est chaud). Toute solution qui fait `await` de Seerr avant de rendre
  les hubs est **bloquante** au sens de CA17 : avec le code actuel, un Overseerr qui accepte la connexion sans répondre
  tiendrait l'onglet jusqu'à 30 s (`requestTimeout`), plus 20 s de ré-authentification.
- **Délais côté appelant** (sans toucher `SeerrClient._request`) : `.timeout()` de **8 s** sur la liste, **8 s** par
  fiche, et un budget global de **15 s** pour composer la rangée. Au-delà : la rangée montre les titres déjà résolus
  (au moins 1) ou n'apparaît pas. La requête sous-jacente continue jusqu'à ses 30 s ; si elle aboutit, son résultat
  remplit quand même le cache, et la prochaine ouverture en profite.
- **Cache négatif de 60 s** après un échec de la liste (délai dépassé, réseau, 5xx, proxy d'authentification) : pas de
  nouvel essai pendant 60 s, pour que Films → Séries → Animés avec un Overseerr éteint n'empile pas trois attentes de 8
  à 30 s et leurs sockets.
- **Session expirée** : le chemin existant de `SeerrClient` s'applique tel quel (ré-authentification silencieuse, puis
  `onSessionInvalidated` si elle échoue), comme pour Explorer. La rangée n'affiche rien de plus, et rien n'est
  journalisé au-dessus du niveau `w`.
- **Hors ligne / non connecté** : si `catalogClient` est null, si la bibliothèque n'est pas Films/Séries (CA18), ou si
  l'app est en mode hors ligne, **aucun appel**, aucun objet créé (CA15).

### 4. Ouverture en moins de 3 s (CA8, CA10, CA11)

Chemin rapide, sans recherche :
1. Lire `media.mediaUrl` (fonction pure, testée) : `machineId` + `ratingKey` (Plex) ou `serverId` +
   `jellyfinMediaId` (Jellyfin). Repli sur `media.ratingKey` / `media.jellyfinMediaId` sans serveur identifié.
2. Choisir le serveur de l'app dont l'identifiant correspond (Plex : `machineIdentifier` ; Jellyfin : `serverId` — à
   vérifier dans `MultiServerProvider` à l'implémentation) et **en ligne**. Si aucun ne correspond, essayer le serveur
   de la bibliothèque ouverte en **vérifiant que l'élément renvoyé a le bon tmdbId** : les `ratingKey` sont de petits
   entiers qui se répètent d'un serveur Plex à l'autre.
3. `fetchItem(id)` avec un délai de **2,5 s**.
4. Sinon, fiche Explorer (CA11). La recherche inverse `CatalogLibraryMatcher` (20 s) n'est utilisée qu'avec le budget
   restant (au plus 3 s au total), ou pas du tout si `architecte-app` juge le chemin rapide suffisant.

Points d'attention à transmettre :
- `PlexClient.fetchItem` peut se rabattre sur le cache d'API (la doc de `fetchEditableItem`, juste en dessous, le
  dit) : avec un serveur éteint, il pourrait renvoyer un élément périmé et ouvrir une fiche serveur qui ne charge pas.
  Il faut tester l'état en ligne du serveur avant (étape 2), pour que CA11 tienne.
- **Retour visuel immédiat** (< 100 ms) sur l'affiche pendant la résolution, et OK ignoré tant qu'elle tourne : sur
  Fire Stick, sans ça, l'utilisateur appuie deux fois.
- La même résolution, faite une fois pour un animé disponible, donne la bibliothèque Animés (CA3d) : son `libraryId`
  est mis en cache pour la session. Aucun appel serveur supplémentaire pour les autres titres.
- Option à n'activer que si la recette mesure plus de 3 s : préchargement de l'étape 3 quand une affiche
  « Disponible » garde le focus plus de 600 ms.

### 5. Images

- Réutiliser **la chaîne d'images existante** (`OptimizedMediaImage`, variantes `w342`/`w500`/`w780` déjà produites par
  la conversion Seerr → `CatalogItem`), donc décodage redimensionné à la taille de la carte et cache d'images commun.
  Pas de `Image.network` brut, pas de `precacheImage`.
- Seules les affiches visibles sont décodées (rail paresseux). 20 affiches de rail compact ≈ 150 × 225 px × 4 o ≈
  135 Ko décodées chacune, soit < 3 Mo dans le pire cas : acceptable.
- Pas d'image de fond (backdrop) propre à la rangée : si le projecteur TV (`TvSpotlightScaffold`) affiche le fond de
  l'élément sélectionné, utiliser la plus petite variante `w780`, pas `original`.

### 6. Démarrage

**Aucun appel ni aucune initialisation au démarrage de l'app** : rien n'est fait avant l'ouverture d'une bibliothèque
vidéo. Je refuse explicitement le préchargement de la liste au lancement : la Fire Stick est déjà occupée à cette
étape par la liaison des serveurs et l'appel `/auth/me` de `SeerrAccountProvider`, et 1 + N appels de plus
ralentiraient le premier écran pour une rangée qui n'est pas encore visible.

### 7. Isolement du code fork et compatibilité upstream

- Code dans `lib/fork/recent_requests/` (D2, D13 : plus de 2 fichiers), tests dans `test/fork/recent_requests/`.
- **Modèle de demande propre au fork**, analysé à la main depuis le JSON brut (`createdAt`, `media.mediaType`,
  `media.tmdbId`, `status`, `media.status`, `ratingKey`, `jellyfinMediaId`, `mediaUrl`) : on ne touche ni à
  `seerr_request.dart`, ni à `seerr_media.dart`, ni à leurs `*.g.dart`.
- **Unique ajout dans `seerr_client.dart`** : une méthode publique, marquée `// FORK: demandes-recentes-overseerr`, qui
  renvoie le corps JSON brut de la liste, par exemple
  `Future<Map<String, dynamic>> getRequestsJson({required int take, required int requestedBy})`, placée en fin de la
  section `Requests` (environ 6 lignes). C'est le seul moyen d'hériter de l'authentification et de la
  ré-authentification sans les dupliquer. Une telle méthode serait d'ailleurs acceptable upstream (#3050 est ouvert).
- **Ne pas modifier `tv_browse_rail.dart`** (17 commits upstream en 4 mois). Le crochet dans
  `library_recommended_tab.dart` doit rester de quelques lignes marquées (D11), les détails relèvent
  d'`architecte-app`.
- Textes : clés `fork.*` dans la surcouche `lib/fork/i18n/` (D6), jamais dans `lib/i18n/*.json` à la main. Les badges
  réutilisent les libellés existants de la fiche Explorer quand ils existent (CA7).
- Une garde `test/fork/recent_requests/hooks_test.dart` (sur le modèle de `skip_markers_hooks_test.dart`) vérifie que
  les crochets `FORK:` sont toujours présents, pour qu'une fusion qui les perd fasse échouer la CI.

### 8. Tests automatisés (`test/fork/recent_requests/`, avec `package:http/testing` `MockClient`, déjà fourni par `http`)

- Analyse : JSON réels Overseerr et Jellyseerr (fixtures), `mediaUrl` Plex et Jellyfin, `ratingKey` absent,
  statuts 6/7 selon le produit, demande sans `media`.
- Requête : `requestedBy=<userId>` toujours présent (CA6), `take=50`.
- Compteurs d'appels (client factice) : Films puis Séries puis Animés en moins de 30 s → **1** `/request` ; deuxième
  ouverture → **0** fiche ; jamais plus de **4** fiches en vol ; non connecté ou bibliothèque musique → **0** appel
  (CA15, CA18).
- Délais (horloge factice ou `fakeAsync`) : liste qui ne répond pas → rangée absente au bout de 8 s, et **les hubs sont
  rendus sans attendre** (test de widget de l'onglet avec une liste Seerr en attente infinie : CA17) ; cache négatif
  respecté pendant 60 s puis nouvel essai.
- Isolation : changement de `userId` ou de langue → aucune donnée de l'ancien contexte.
- Ouverture : correspondance par `machineId`, refus d'un `ratingKey` dont le tmdbId diffère, délai de 2,5 s → Explorer,
  serveur hors ligne → Explorer (CA11).
- Toute la suite (`scripts/run_tests.sh`) : l'onglet upstream est modifié, ses tests doivent rester verts sans
  provider Seerr.

### 9. Protocole de recette sur la Fire TV Stick (192.168.1.173)

Préparation (côté utilisateur, sur Overseerr ou Jellyseerr) : au moins une demande de chaque sorte, faite **par le
compte de l'app** : film, série, série animée japonaise, film d'animation japonais (Ghibli), série d'animation
américaine (Les Simpson), une demande disponible, une partiellement disponible, une refusée, une en échec, une
« disponible » dont le titre a été supprimé du serveur. Un compte administrateur doit aussi avoir **une demande faite
par un autre utilisateur** (CA6).

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
ADB=~/Library/Android/sdk/platform-tools/adb
PKG=io.github.adrien24.popkino
$ADB connect 192.168.1.173:5555
flutter build apk --release --split-per-abi --no-tree-shake-icons --dart-define=ENABLE_UPDATE_CHECK=true
APK=build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
$(ls -d ~/Library/Android/sdk/build-tools/* | tail -1)/apksigner sign --ks ~/.android/debug.keystore \
  --ks-pass pass:android --ks-key-alias androiddebugkey "$APK"
$ADB -s 192.168.1.173:5555 install -r "$APK"
```

Le build modifie `pubspec.lock` : ne pas le commiter. La restauration revient à l'orchestrateur ; un agent ne lance
jamais `git checkout`.

Activer « journaux de débogage » dans les réglages de l'app, puis `$ADB logcat -c` et garder
`$ADB logcat -v time | grep -E "Seerr (GET|POST)|RecentRequests"` dans un second terminal.

1. **Démarrage (pas de régression)** : 5 fois `$ADB shell am force-stop $PKG` puis
   `$ADB shell am start -W -n $PKG/com.edde746.plezy.MainActivity` ; relever `TotalTime`. Même mesure avec l'APK
   précédent (`main`) installé juste avant. Critère : médiane à ± 10 %, et **aucune ligne `Seerr GET /request`**
   avant l'ouverture d'une bibliothèque.
2. **Premier chargement à froid** : ouvrir Séries. Critère : les rangées habituelles apparaissent comme avant ;
   logcat = 1 `GET /request` puis des `GET /tv/…`, jamais plus de 4 en parallèle (horodatages) ; rangée visible en
   moins de 5 s pour 20 titres ; pendant le chargement, Gauche/Droite dans « Continuer à regarder » reste fluide.
3. **Partage du cache** : Films puis Animés puis Séries en moins de 30 s. Critère : aucun nouveau `/request` ; seules
   les fiches jamais lues sont demandées ; rouvrir Séries → **0** fiche.
4. **Ouverture (CA8, CA10, CA11)** : `$ADB shell screenrecord --time-limit 15 /sdcard/ok.mp4` pendant un OK sur une
   série disponible, puis `$ADB pull /sdcard/ok.mp4` et mesurer image par image le temps entre la réaction de
   l'affiche et la fiche avec ses saisons. Critère : < 3 s, 5 essais sur des titres différents (cache froid). Même
   chose pour une série partiellement disponible, puis pour le titre supprimé du serveur (→ Explorer sans écran
   d'erreur).
5. **Panne (CA17)** : arrêter Overseerr (conteneur ou service), attendre 60 s, ouvrir Films. Critère : les rangées
   s'affichent dans le même temps qu'à l'étape 2, rangée absente, aucun message. Puis Séries et Animés aussitôt :
   **aucun nouveau** `GET /request` (cache négatif). Redémarrer Overseerr, attendre 60 s, rouvrir : rangée de retour.
   Variante : Wi-Fi coupé sur la Fire Stick (`Paramètres > Réseau`) pendant que l'app est ouverte.
6. **Mémoire** : `$ADB shell dumpsys meminfo $PKG | grep -E "TOTAL PSS|TOTAL:"` après l'étape 2, puis après 5 cycles
   Films → Séries → Animés avec ouverture et fermeture d'une demande à chaque cycle. Critère : moins de 10 Mo d'écart
   entre le premier et le cinquième cycle (pas de fuite), et moins de 20 Mo par rapport à la même navigation avec
   Overseerr déconnecté.
7. **Fraîcheur (CA13)** : marquer une demande comme disponible côté serveur, attendre 30 s, rouvrir la bibliothèque.
   Critère : badge « Disponible » et OK vers la fiche serveur.
8. **Insertion tardive** : vider le cache (force-stop), ouvrir Séries et appuyer immédiatement sur Bas plusieurs fois
   avant que la rangée arrive. Critère : le focus ne saute pas, n'est jamais perdu, et Retour se comporte normalement.

Si l'étape 2 ou 4 échoue sur les budgets, la mesure fine se fait avec un build profile
(`flutter run --profile -d 192.168.1.173:5555`) et la frise des images de DevTools (images du fil UI > 32 ms pendant le
chargement de la rangée).

## Alternatives écartées

- **Attendre Seerr dans `_loadRecommendedHubs`** (même avec un délai court) : enfreint CA17 (« dans le même temps
  qu'aujourd'hui ») dès qu'Overseerr est lent, et lie le temps d'affichage de l'onglet à un service tiers. Rejetée.
- **Précharger au démarrage de l'app** : 1 + jusqu'à 50 appels pendant la phase la plus chargée sur Fire Stick, pour
  une rangée invisible. Rejetée (§6).
- **Deviner l'anime sans lire la fiche** (dossier racine ou profil Sonarr de la demande, `rootFolder`/`profileId`) :
  zéro appel, mais différent de la règle TMDB de CA3b, faux pour les films (Radarr n'a pas de réglage anime dans
  Overseerr) et dépendant de la configuration. Rejetée ; de toute façon, la fiche est lue pour le titre.
- **Passer par `SeerrCatalogSource.fetchDetail`** : 2 appels par titre (fiche + recommandations). Rejetée.
- **Recherche inverse `CatalogLibraryMatcher` comme chemin principal à l'ouverture** : jusqu'à 20 s de budget et
  plusieurs requêtes par serveur, alors que `mediaUrl` donne le serveur et l'identifiant gratuitement. Gardée en
  dernier recours seulement.
- **Étendre `SeerrRequest` / `SeerrMediaInfo`** : régénère des `*.g.dart` upstream et multiplie les zones de conflit ;
  remplacé par un modèle du fork analysé depuis le JSON brut.
- **Cache persistant sur disque** (SharedPreferences) : supprimerait les fiches à froid au lancement suivant, mais
  ajoute versionnage, clé et invalidation. Reporté : à ajouter seulement si l'étape 2 de la recette dépasse 5 s pour
  20 titres (ou 8 s pour la bibliothèque Animés).
- **Décodage JSON dans un isolate** : coût de lancement d'isolate à chaque fiche, gain incertain. Reporté : à ajouter
  seulement si DevTools montre des images > 32 ms sur le fil UI pendant le chargement.
- **Flavor ou `--dart-define` pour la fonction** : la spec veut la même chose partout ; aucune bascule de build.

## Impact

- **Fichiers upstream modifiés** (à minimiser) :
  - `lib/services/seerr/seerr_client.dart` : + 1 méthode publique `// FORK:` (~6 lignes).
  - `lib/screens/libraries/tabs/library_recommended_tab.dart` : crochet de quelques lignes, défini par
    `architecte-app`, qui **ne doit pas** mettre Seerr dans l'`await` des hubs.
  - Aucun autre, en particulier ni `tv_browse_rail.dart`, ni `lib/main.dart`, ni les modèles Seerr générés.
- **Nouveaux fichiers** : `lib/fork/recent_requests/` (modèle analysé, cache attaché au client, résolution de
  l'ouverture, analyse de `mediaUrl`) ; `test/fork/recent_requests/` (unités, widget de l'onglet, garde des crochets,
  fixtures JSON) ; clés `fork.*` dans `lib/fork/i18n/`.
- **Dépendances ajoutées** : aucune (`package:http/testing` fait partie de `http`).
- **Android / Gradle / manifeste / CI** : aucun changement. Pas de permission (INTERNET existe déjà), pas de nouveau
  workflow : les tests passent par `scripts/run_tests.sh`.
- **Risques** :
  - **Google Play** : aucun. Pas de permission, pas de code téléchargé, aucune donnée nouvelle collectée ; les demandes
    sont lues sur le serveur de l'utilisateur, déjà déclaré dans le formulaire « Sécurité des données ». Fonction
    absente de Plezy (#2410 refusé) : elle aide à rendre l'app distincte (règle « contenu répétitif »).
  - **Marque** : aucun ; « Overseerr / Jellyseerr » est le nom du service tiers, déjà présent dans l'app.
  - **Performances TV** : premier chargement à froid de la bibliothèque Animés (jusqu'à 50 fiches) ; décodage JSON
    sur le fil principal pendant la navigation ; insertion tardive de la rangée sous le focus. Tous les trois sont
    mesurés par la recette (étapes 2, 3 et 8) et ont un remède prévu (cache persistant, isolate, garde de focus).
  - **Conflits de fusion** : faibles (1 méthode dans `seerr_client.dart`, un crochet dans l'onglet, gardés par un
    test).
  - **Compatibilité serveur** : Overseerr (non maintenu, sans `mediaType`/`sortDirection`) et Seerr/Jellyseerr
    diffèrent ; les fixtures des deux sont obligatoires dans les tests.

## QUESTIONS PRODUIT

Réponses reçues le 2026-11-28 : (1) l'utilisateur prépare une partie des cas sur Overseerr, le reste est couvert par
les tests automatisés ; (2) Overseerr + Plex, pas de Jellyfin réel (CA19 côté Jellyfin/Jellyseerr vérifié seulement
par les fixtures des tests) ; (3) recette **uniquement sur la Fire TV Stick**, pas sur la Freebox Pop : l'ancienne étape 9 (Freebox) est retirée.

1. **Données de recette** : l'utilisateur peut-il préparer sur son Overseerr les demandes listées au §9 (dont une
   refusée, une en échec, un titre « disponible » supprimé du serveur, et une demande d'un autre utilisateur), et
   arrêter puis relancer Overseerr pendant la recette ? Sinon, CA6, CA7b, CA11 et CA17 ne seront vérifiés que par les
   tests automatisés.
2. **Overseerr ou Jellyseerr / Seerr ?** Lequel tourne chez l'utilisateur, avec Plex ou Jellyfin ? CA19 demande les
   deux serveurs ; la recette sur TV ne couvrira que la configuration réelle de l'utilisateur.
3. **Freebox Pop** : la spec demande une vérification rapide sur la Freebox, alors que la note de l'utilisateur du
   2026-11-28 réserve désormais les tests à la Fire Stick. On garde l'étape 9 du protocole ?
