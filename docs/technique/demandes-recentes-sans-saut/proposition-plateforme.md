# Proposition plateforme — demandes-recentes-sans-saut

## Compréhension de la spec

À l'ouverture d'une bibliothèque qui avait des demandes récentes la dernière fois, la place de la rangée est réservée
tout de suite par des affiches grises, que les vraies affiches remplacent sur place. Seul « N demandes pour cette
bibliothèque » est mémorisé sur la TV, y compris après un redémarrage. Rien n'est lu au démarrage, rien de nouveau
n'est collecté.

Critères qui touchent mon périmètre :
- CA1 et CA13 : persistance, contenu limité au nombre, oubli quand il n'y a plus de demandes.
- CA2 : coût des affiches grises sur la Fire Stick.
- CA3 : preuve par captures.
- CA6 : 10 s au plus.
- CA8 : aucune E/S sans Overseerr ou hors film/série.
- CA11 : démarrage inchangé.
- Contraintes Google Play (sécurité des données) et canaux (aucune différence GitHub/Play).

## Existant (lu dans le code)

- **Préférences** : `BaseSharedPreferencesService` (`lib/services/base_shared_preferences_service.dart:88-117`) ouvre
  un `SharedPreferencesWithCache` partagé, sans `allowList`. **Toutes les clés sont donc chargées en mémoire au
  démarrage** : toute clé ajoutée allonge la lecture au démarrage, ce qui viole la contrainte « rien de lu au
  démarrage ». La décision 5 de `demandes-recentes-overseerr/plan.md` (pas de `JsonPref` ni de préférences) s'applique
  toujours.
- **Emplacement disque déjà prévu** : la tâche T9 (non lancée) de `demandes-recentes-overseerr/plan.md` réservait
  `<getApplicationCacheDirectory()>/popkino_recent_requests/`, lu à l'ouverture d'une bibliothèque. `crypto`,
  `path` et `path_provider` sont déjà des dépendances.
- **Sauvegarde Android** : le manifeste (`android/app/src/main/AndroidManifest.xml:36-45`) ne déclare ni
  `allowBackup`, ni `fullBackupContent`, ni `dataExtractionRules`. La sauvegarde automatique est donc **active par
  défaut** pour `shared_prefs/`, `files/` et les bases de données, mais **jamais pour `cache/`** (exclusion du système).
- **Répertoire de cache** : seul son sous-dossier `plexImageCache` est supprimé au démarrage, une seule fois
  (`lib/main.dart:1041-1049`). Le cache d'images (`image_cache_service.dart:43`) gère ses propres fichiers. Aucun code
  ne vide tout le répertoire.
- **Affiches grises upstream** : `SkeletonMediaCard` (`lib/widgets/skeleton_media_card.dart`) et `SkeletonLoader`
  (`lib/widgets/media_card.dart:1617`) sont des `Container` **statiques** (fond `onSurface` à 7,5 %), sans
  animation, sans `AnimationController` ni image. Ils sont utilisés par `hub_section.dart:746`. Leur commentaire les
  dit « non focusables ».
- **Moment de création de la rangée** : `ForkRecentRequestsShelf` n'est construit que dans `buildContent`
  (`library_recommended_tab.dart:277-278`), donc **dans la même image que les rangées upstream**. Une lecture disque
  lancée à ce moment arrive au mieux 1 à 3 images trop tard.
- **Délais du dépôt** (`recent_requests_repository.dart:40-46`) : 8 s pour la liste et 15 s de budget par rangée. On
  peut donc dépasser 10 s, alors que CA6 impose 10 s au plus. `rowFor` renvoie `null` aussi bien quand il n'y a
  « aucune demande » que pour un échec ou un délai dépassé.

## Approche proposée

### 1. Stockage : un petit fichier JSON dans `cache/`, lu à la première ouverture d'une bibliothèque

- **Fichier** : `<getApplicationCacheDirectory()>/popkino_recent_requests/row_sizes.json`, soit le dossier déjà
  réservé par T9.
- **Contenu** :

  ```json
  {"v":1,"owner":"<16 hex>","rows":{"<library.globalKey>":{"n":7,"d":20420}}}
  ```

  - `n` : nombre d'affiches affichées (au plus 20) ;
  - `d` : jour de la dernière confirmation (jours depuis l'epoch) ;
  - `owner` : les 16 premiers caractères hexadécimaux du SHA-256 de `baseUrl|userId` de la session Seerr. Ce n'est ni
    un titre ni une donnée lisible (CA13). Si le propriétaire change (autre compte, autre Overseerr), le fichier est
    ignoré puis réécrit. Cela évite d'afficher des affiches grises tirées des demandes d'un autre profil.
- **Pourquoi `cache/`** :
  1. rien n'y est lu au démarrage, contrairement aux préférences ;
  2. le répertoire est exclu d'office de la sauvegarde Android, sans toucher au manifeste ni ajouter de
     `dataExtractionRules` (zéro diff upstream) ;
  3. si Fire OS vide le cache faute de place, on perd seulement les affiches grises à l'ouverture suivante, soit le
     comportement de CA7. C'est une dégradation propre, jamais une erreur.
- **Lecture** :
  - une seule fois par processus, puis gardée en mémoire dans un singleton statique du fork. Ce n'est pas l'`Expando`
    du `SeerrClient`, puisque le fichier survit au client ;
  - déclenchée **uniquement** pour une bibliothèque film ou série, avec une source Seerr présente et le mode hors ligne
    désactivé. Sinon aucune E/S (CA8, CA11).
  - Fichier absent, illisible, `v` différent ou propriétaire différent : on considère la table vide, et le fichier
    illisible est supprimé. Jamais d'exception remontée.
- **Contrainte de calendrier (point clé pour l'architecte app)** : la lecture doit être **lancée avant** que les
  rangées upstream soient rendues, sinon les affiches grises arrivent quelques images après les autres rangées, ce qui
  fait un petit saut. Je propose de la lancer dès la création de l'onglet Recommandé. Il faut pour cela une ligne
  marquée `// FORK:` dans `initState` de `library_recommended_tab.dart`, à côté du crochet existant, ou un mécanisme
  équivalent que l'architecte app jugera moins intrusif. Le chargement des hubs (réseau ou base drift) prend toujours
  plus longtemps que la lecture d'un fichier de moins de 4 Ko : quelques millisecondes sur la Fire Stick, plus un
  appel `path_provider` d'environ 1 à 5 ms la première fois.
- **Filet** : si la table n'est pas encore chargée au premier rendu de la rangée, **pas d'affiches grises pour cette
  ouverture** (comportement CA7). On n'insère jamais d'affiches grises en retard.
- **Écriture limitée** :
  - on n'écrit **que si quelque chose change** : `n` différent, entrée ajoutée ou supprimée, propriétaire changé ;
  - ou si `d` a plus de 7 jours, pour garder vivante une bibliothèque consultée régulièrement.
  - Écriture atomique : fichier `.tmp` puis `rename`. Les écritures passent une à une par une seule chaîne de
    `Future` : pas d'écritures concurrentes, et la dernière gagne.
  - En usage normal, cela fait une écriture lors d'une nouvelle demande, puis plus rien. Aucune usure notable de la
    mémoire flash.
- **Ce qui déclenche une écriture** (l'architecte app doit distinguer les cas dans l'API du dépôt) :
  - rangée affichée avec N affiches → `n = N` ;
  - réponse **concluante** sans aucune demande du type de la bibliothèque → entrée supprimée (CA13, CA5) ;
  - **échec, délai dépassé, cache négatif ou hors ligne → aucune écriture**. Une panne passagère d'Overseerr ne doit
    pas faire oublier la rangée. Il faut donc que `rowFor` (ou une variante) dise « vide » d'un côté et « inconnu »
    de l'autre. Aujourd'hui les deux renvoient `null`.
- **Nettoyage**, à chaque écriture, sans coût supplémentaire au démarrage :
  1. **bibliothèque supprimée** : on retire une entrée dont le serveur figure dans `ctx.libraries` mais dont la
     `globalKey` n'y est plus. On ne retire **pas** les entrées d'un serveur absent de la liste : il peut être
     simplement hors ligne ;
  2. **serveur disparu ou bibliothèque jamais rouverte** : expiration après 30 jours sans confirmation (`d`) ;
  3. **plafond** de 64 entrées : au-delà, on retire les plus anciennes ;
  4. **déconnexion d'Overseerr ou changement de compte** : le nouveau propriétaire réécrit le fichier dès sa première
     écriture. Rien n'est fait à la déconnexion elle-même, ce qui évite un crochet dans le code upstream de Seerr.

### 2. Affiches grises : statiques, réutilisation de `SkeletonMediaCard` / `SkeletonLoader`, nombre plafonné

- **Pas d'animation de miroitement**, pour trois raisons :
  1. CA2 exige « le même aspect que les affiches de chargement de l'accueil », et celles-ci sont statiques ;
  2. un `AnimationController` à 60 images/s ferait redessiner la rangée à chaque image pendant 1 à 10 s, au moment
     le plus chargé : décodage des affiches des autres rangées, budget `CardInflationBudget.maxPerFrame = 1`, calibré
     pour ces TV ;
  3. sur la Fire Stick (environ 35 Mo libres observés), le coût mémoire d'une animation est faible, mais le coût GPU
     et CPU ne l'est pas, et il ferait saccader le D-pad.
- **Coût d'affiches statiques** : quelques `RenderObject` par affiche, aucune texture, aucune image décodée. Avec un
  nombre plafonné à ce qui tient à l'écran (CA2), soit environ 6 à 8 affiches, le coût est négligeable : moins de
  quelques Ko. La mémoire des vraies affiches est inchangée par rapport à aujourd'hui.
- **Focus (CA10)** : `SkeletonMediaCard` n'est pas focusable. L'enveloppe focusable relève de l'architecte app, mais
  côté performances elle doit rester un simple `Focus` sans état lourd, ni `InkWell` ni ondulation (cf.
  `_CardTapRegion`, `media_card.dart:1635-1640`).
- **CA6 (10 s)** : il faut un minuteur de 10 s **côté rangée**, indépendant des délais du dépôt (8 s + 15 s). Un
  seul `Timer`, annulé dans `dispose` et à chaque changement de génération, pour ne garder aucune référence après la
  fermeture de l'onglet. Il est inutile de raccourcir les délais du dépôt, qui servent aussi au cache des résumés.

### 3. Conformité Google Play et canaux

- **Sécurité des données** : Google définit la collecte comme « transmitting data from your app off a user's
  device ». Les données « only processed locally on the user's device and not sent off device » ne sont pas
  concernées. Le fichier reste sur l'appareil et dans `cache/`, donc hors sauvegarde Google : **aucune modification
  du formulaire Sécurité des données**, aucune nouvelle permission, aucun nouvel appel réseau. Le nombre d'appels à
  Overseerr est inchangé.
- **Canaux** : aucun `--dart-define`, aucune différence de manifeste entre GitHub et Play (D7 respectée). Pas de
  constante éliminable nécessaire : la fonction est commune aux deux canaux.
- **Marque** : rien de visible n'est nommé. Préfixe `popkino_`, conforme à T9.

### 4. Recette : prouver l'absence de saut (CA3), sur la Fire TV Stick uniquement

Préparation : APK `armeabi-v7a`, signé avec la clé de debug comme d'habitude, journaux de débogage activés.

1. **Démarrage (CA11)** : même mesure que `demandes-recentes-overseerr`.
   - 5 fois `am force-stop` puis `am start -W`. Médiane de `TotalTime` à ± 10 % de l'APK `main`.
   - Dans `logcat`, la ligne de journal du fork « RecentRequests: row sizes loaded » (à ajouter, niveau debug)
     n'apparaît **qu'après** l'ouverture d'une bibliothèque, jamais au démarrage.
2. **Captures avant/après (CA3)** : pas de `screencap` (1 à 2 s par capture sur la Fire Stick, on raterait la phase
   grise), mais une vidéo.
   - Lancer `adb shell screenrecord --size 1280x720 --time-limit 12 /sdcard/rr.mp4`, ouvrir Séries, puis **ne plus
     toucher la télécommande**.
   - Rapatrier la vidéo et en extraire 10 images/s : `ffmpeg -i rr.mp4 -vf fps=10 f_%03d.png`.
   - Choisir l'image A (affiches grises visibles) et l'image B (vraies affiches arrivées).
   - Comparer **le bandeau du titre de la rangée suivante**, un texte statique, entre les deux images :
     `magick compare -metric AE -fuzz 10% <A rogné> <B rogné> null:`. Attendu : 0 pixel différent, ou une
     différence limitée à l'anticrénelage. Même contrôle pour le titre « Demandes récentes » et la rangée du dessus.
   - **Contrôle négatif obligatoire** : la même mesure sur l'APK `main` doit montrer le saut (une valeur AE élevée).
     Cela prouve que la méthode détecte bien un décalage.
   - ffmpeg, ImageMagick et Pillow sont installés sur le Mac.
3. **Redémarrage (CA1)** : `am force-stop`, ou redémarrage de la TV, puis rouvrir Séries. Les affiches grises sont
   présentes dès la première image où les rangées apparaissent : vérifier sur la vidéo qu'aucune image ne montre les
   rangées sans les affiches grises.
4. **Panne (CA6)** : `docker pause` du conteneur Overseerr (connexions suspendues, contrairement à un arrêt qui
   échoue tout de suite), puis attendre 60 s pour sortir du cache négatif. Ouvrir Séries : les affiches grises
   disparaissent en 10 s au plus (horodatage de la vidéo), et la bibliothèque **n'est pas oubliée** : rouvrir après
   `docker unpause` montre encore les affiches grises.
5. **Oubli (CA13, CA5)** : supprimer les demandes de séries, attendre 30 s, rouvrir. La rangée disparaît. À
   l'ouverture suivante, après force-stop, aucune affiche grise.
6. **Mémoire** : `adb shell dumpsys meminfo <pkg>` (PSS total) sur la bibliothèque ouverte, comparé à l'APK `main`.
   Écart attendu inférieur à 1 Mo.
7. **Fluidité** : pendant la phase grise, Gauche / Droite et Bas restent fluides. Contrôle facultatif :
   `dumpsys gfxinfo <pkg>` pour les images saccadées.

Côté tests automatiques (plan app) : aller-retour du fichier, version ou propriétaire différents, fichier corrompu
supprimé, expiration et plafond, aucune écriture sur un échec, aucune E/S pour une bibliothèque non éligible, et aucune
lecture avant la première ouverture.

## Alternatives écartées

- **Clé dans les préférences** (`SettingsService` / `StorageService`, `JsonPref`) : chargée au démarrage avec toutes
  les autres clés par `SharedPreferencesWithCache` sans `allowList`. Elle viole « rien lu au démarrage » et la
  décision 5 précédente. Elle serait en plus incluse dans la sauvegarde Android.
- **Table drift** : migration de schéma dans `lib/database/` (upstream très actif, conflits de fusion), et la base est
  ouverte au démarrage. Disproportionné pour 64 entiers.
- **Fichier dans `getApplicationSupportDirectory()` (`files/`)** : sauvegardé par défaut. Il faudrait ajouter des
  `dataExtractionRules` / `fullBackupContent` au manifeste upstream, ou accepter une restauration sur un autre
  appareil avec des `globalKey` sans objet. `cache/` offre ce qu'on veut sans diff.
- **Animation de miroitement** : contraire à CA2, et coût de rendu continu sur la Fire Stick (voir § 2).
- **Lecture synchrone (`readAsStringSync`)** au premier rendu : le chemin du répertoire de cache n'est disponible
  que de façon asynchrone (`path_provider`), et une E/S synchrone sur le fil de l'interface peut atteindre des dizaines
  de ms quand la mémoire flash de la Fire Stick est occupée (décodage d'images en cours).

## Impact

- **Fichiers upstream modifiés** :
  - aucun côté Android, manifeste ou Gradle ;
  - côté Dart, éventuellement une ligne `// FORK:` dans `library_recommended_tab.dart` pour lancer la lecture tôt
    (à arbitrer avec l'architecte app).
- **Nouveaux fichiers** :
  - `lib/fork/recent_requests/row_size_memory.dart` (nom indicatif) et son test ;
  - le reste (affiches grises dans la rangée, minuteur) dans `recent_requests_shelf.dart` et
    `recent_requests_repository.dart`, qui sont des fichiers du fork.
- **Dépendances ajoutées** : aucune (`path_provider`, `path` et `crypto` sont déjà présents).
- **Risques** :
  - Google Play : nul, rien n'est collecté et le fichier est hors sauvegarde ;
  - marque : nul ;
  - performances TV : négligeables avec des affiches statiques en nombre plafonné ; le seul risque est la lecture
    tardive (§ 1, filet prévu) ;
  - fusion : au plus une ligne upstream ;
  - fonctionnel : la distinction « vide » / « échec » dans `rowFor` est indispensable, sinon une panne d'Overseerr
    fait oublier toutes les bibliothèques ;
  - Fire OS peut vider `cache/`, avec pour seule conséquence le comportement de CA7.

## QUESTIONS PRODUIT

1. **Réponse tardive après les 10 s (CA6)** : les affiches grises ont disparu à 10 s, mais Overseerr répond à 12 s
   avec des demandes (le dépôt attend jusqu'à 15 s). Faut-il insérer la rangée quand même (nouveau saut, comme
   aujourd'hui), ou l'ignorer jusqu'à la prochaine ouverture de la bibliothèque ? Je recommande de l'ignorer : pas de
   saut tardif, et le focus n'est pas dérangé.
2. **Plusieurs profils ou comptes Overseerr sur la même TV** : je propose que la mémoire soit propre à un compte
   Overseerr. Changer de compte efface la mémoire, et la première ouverture qui suit se fait sans affiches grises.
   Est-ce acceptable ?
