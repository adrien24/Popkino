
## Critique de architecte-app sur la proposition plateforme — tour 1

Prise en compte des décisions du PO du 2026-11-28 : CA6b (réponse arrivée après 10 s ignorée pendant la visite),
CA13 (souvenir propre au compte Overseerr, effacé au changement de compte) et CA2 (affiches fixes).

- ✅ D'accord : **fichier dans `cache/`**, lu une seule fois par processus et seulement pour une bibliothèque film ou
  série avec Seerr et en ligne. L'argument de la sauvegarde Android (`cache/` est exclu d'office, sans changer le
  manifeste) complète le mien : je le reprends.
- ✅ D'accord : **le fichier a un propriétaire**, les 16 premiers caractères hexadécimaux du SHA-256 de
  `baseUrl|userId`, et il est ignoré puis réécrit quand ce propriétaire change. C'est exactement CA13 tel que le PO
  l'a tranché.
  - **Je retire** ma clé `"<userId>|<globalKey>"`, qui gardait les souvenirs de plusieurs comptes au lieu de les
    effacer et ne distinguait pas deux serveurs Overseerr.
  - Je reprends aussi le nom `row_sizes.json` et le format `{"v":1,"owner":…,"rows":{…}}`.
- ✅ D'accord : **filet « jamais d'affiches grises en retard »**. Si le fichier n'est pas encore lu au premier rendu,
  aucune affiche grise ne s'affiche pendant cette ouverture. Je retire mon nouveau calcul après `ensureLoaded()`, qui
  aurait produit le petit saut qu'on cherche à éviter.
- ✅ D'accord sur :
  - des affiches **fixes**, sans animation (CA2, coût de rendu sur la Fire Stick) ;
  - une écriture seulement si quelque chose change, de façon atomique (`.tmp` puis `rename`) et une écriture à la
    fois ;
  - la distinction obligatoire entre une réponse **vide concluante** et une réponse **inconnue** (ma méthode
    `rowResultFor`, avec un champ `conclusive`) ;
  - un minuteur de 10 s côté rangée, sans toucher aux délais du dépôt.
- ✅ D'accord sur la recette CA3 : vidéo `screenrecord`, extraction d'images avec `ffmpeg`, puis
  `magick compare -metric AE` sur le bandeau du titre de la rangée suivante. Le **contrôle négatif sur l'APK `main`**
  est indispensable.

- ⚠️ À amender : **emplacement du préchargement**. `_LibraryRecommendedTabState` n'a pas d'`initState` : il n'a qu'un
  `didUpdateWidget` (`library_recommended_tab.dart:62`). L'y ajouter coûte 4 lignes upstream au lieu d'une. Surtout,
  l'état de l'onglet est **réutilisé d'une bibliothèque à l'autre**, ce qui fait échouer le préchargement dans un cas
  précis :
  1. on ouvre d'abord une bibliothèque Musique, qui ne déclenche aucune lecture (CA8) ;
  2. on passe ensuite à Films : `initState` ne repasse pas, donc rien n'est préchargé ;
  3. la rangée Films tombe alors dans le filet et n'a pas d'affiches grises.

  → Une seule ligne, en tête de `_loadRecommendedHubs` (`library_recommended_tab.dart:191`) :
  `unawaited(forkWarmUpRecentRequestCounts(context, widget.library)); // FORK: demandes-recentes-sans-saut`.
  `_loadRecommendedHubs` s'exécute à chaque ouverture ou changement de bibliothèque, avant l'appel réseau des hubs, et
  jamais au démarrage. La fonction est mémorisée et vérifie elle-même les conditions de CA8.
- ⚠️ À amender : **nettoyage**. La règle 1, qui retire les bibliothèques supprimées d'après `ctx.libraries`, oblige à
  passer la liste des bibliothèques au module de stockage pour un gain nul : une bibliothèque supprimée n'est plus
  jamais ouverte, donc son entrée ne sert à rien, et le plafond de 64 entrées plus l'expiration à 30 jours (`d`) la
  font disparaître de toute façon.
  → Garder `d`, l'expiration à 30 jours, le rafraîchissement à 7 jours et le plafond de 64. Abandonner la règle 1.
- ⚠️ À amender : **enveloppe focusable**. Il ne faut **aucun** `Focus` par affiche. Dans `TvBrowseRail`, toute la
  rangée partage un seul nœud (`LockedFocusRowNode`). La position du focus est un index (`_focusModel`), et la
  bordure est dessinée par la carte grâce à `CardFocusScope`. Une affiche grise rendue par le crochet de `MediaCard`
  (ma proposition, § 4) reçoit donc le focus sans nœud supplémentaire, sans `InkWell` ni zone de toucher, ce qui va
  dans le sens de l'objectif de performances de la plateforme.
- ⚠️ À amender : **CA6b dans la recette**. Ajouter à l'étape 4 : pendant la même visite, après `docker unpause`
  intervenu après les 10 s, la rangée **ne doit pas** apparaître. Elle doit apparaître à la réouverture suivante.
  Côté app, cela se traduit ainsi :
  - à l'expiration du minuteur, un drapeau « visite close » est posé, puis levé par `_resetFor` (changement de
    bibliothèque ou de source) et par le retour de l'onglet au premier plan ;
  - une réponse tardive met encore à jour la mémoire : `n` si elle contient des demandes, suppression de l'entrée si
    elle est concluante et vide. Ainsi, la prochaine ouverture a les bonnes affiches grises.
- ⚠️ À amender : **recette du focus**, absente. Ajouter CA10b sur la Fire Stick :
  - Bas sur la 2e affiche grise, puis attendre l'arrivée des vraies : le focus doit être sur la 2e vraie affiche ;
  - avec Overseerr en pause, le focus sur une affiche grise : au bout de 10 s, il doit être sur la 1re affiche de la
    rangée suivante, et rester visible (CA10c).

- ❌ Bloquant : **réutiliser `SkeletonMediaCard` telle quelle** pour les affiches de la rangée, si c'est bien ce que
  propose le § 2. Deux raisons vérifiables :
  1. **Géométrie différente.** `SkeletonMediaCard` a un remplissage de 8 de chaque côté
     (`skeleton_media_card.dart:14`, `padding: .all(8)`). La carte réelle a un remplissage de 3, 3, 3 et 1
     (`MediaCard.gridCardPadding`, `media_card.dart:279`), et une affiche de hauteur fixe (`height:` fournie par le
     rail). L'affiche grise serait plus étroite et plus courte que la vraie, à l'opposé de CA2 (même taille).
     Comme `SkeletonMediaCard` place son affiche dans un `Expanded`, elle prend sa hauteur dans la cellule de 36 px
     de légende du rail, ce qui la rend en plus dépendante de la mise en page.
  2. **Focus invisible.** Le rail délègue la bordure de focus à la carte (`delegateFocusBorder: true`,
     `tv_browse_rail.dart:1819`). `SkeletonMediaCard` ne contient aucun `CardFocusBorder`. Une affiche grise
     focalisée n'aurait donc aucune bordure, ce qui enfreint CA10c et la règle Android TV « focus toujours visible »
     (`regles-fork` § 4).

  → Alternative : réutiliser la **brique** `SkeletonLoader` (même couleur, même aspect fixe, donc CA2 respecté), dans
  la géométrie de `_buildStandardGridCard` :
  - `Padding(MediaCard.gridCardPadding)`, puis une affiche de hauteur `height` dans un `CardFocusBorder` ;
  - le tout dessiné par le crochet d'une ligne de `MediaCard.build` (proposition app, § 4).

  Un test de non-régression compare la taille de la section grise à celle de la vraie (`tester.getSize`) et vérifie
  la présence de la bordure quand le `CardFocusScope` est actif.

## Critique de architecte-plateforme sur la proposition app — tour 1

Décisions du PO prises en compte : CA6b (une réponse qui arrive après 10 s est ignorée pendant la visite), CA13
(souvenir propre au compte, effacé quand on change de compte). Lu aussi : la critique de l'architecte app ci-dessus, où
il reprend déjà le fichier `row_sizes.json` avec son propriétaire et le filet « jamais d'affiches grises en retard ».

**Réponses à la critique de l'architecte app :**
- ❌ sur `SkeletonMediaCard` : **accepté**. On réutilise la brique `SkeletonLoader` dans la géométrie de
  `_buildStandardGridCard` (`MediaCard.gridCardPadding`, `CardFocusBorder`), rendue par le crochet de
  `MediaCard.build`.
- ⚠️ sur le préchargement : **accepté**. La ligne va en tête de `_loadRecommendedHubs` : l'état de l'onglet est
  réutilisé d'une bibliothèque à l'autre, et l'onglet n'a pas d'`initState`.
- ⚠️ sur le nettoyage : **accepté**. On abandonne la règle 1 ; on garde l'expiration à 30 jours, le rafraîchissement à
  7 jours et le plafond de 64.
- ⚠️ sur l'absence de `Focus` par affiche, et sur les ajouts à la recette (CA6b, CA10b) : **acceptés**.

**Ma critique de la proposition app :**
- ✅ D'accord : **`rowResultFor` avec `conclusive`**. C'est la condition pour qu'une panne d'Overseerr n'efface pas
  la mémoire. La table des cas `conclusive` (budget expiré, fiche `null` ou cache négatif donnent `false`) est la
  bonne.
- ✅ D'accord : **même `id`, même `identifier` et même `serverId` absent** pour la rangée grise et la vraie, grâce à
  `forkRecentRequestsHub`. Le rail garde ainsi rangée et colonne au remplacement, sans toucher
  `tv_browse_rail.dart`.
- ✅ D'accord : **le crochet en tête de `MediaCardState.build`**. Côté performances, c'est un gain : l'affiche grise
  sort avant `SettingsBuilder`, l'image, les badges et le menu. Pour les autres cartes, le coût est un test de type et
  une lecture dans `raw`, négligeable même sur la Fire Stick. `initState` (`_cacheCatalogItem`) n'a aucun effet de
  bord pour un élément gris.
- ✅ D'accord : **`recentRowFor`** (CA9) garde en mémoire seulement quelques `MediaHub` d'au plus 20 éléments, sans
  image retenue. Le plafond d'affichage est calculé avec les API publiques du rail. Le retrait en deux temps ne
  modifie pas le code upstream.
- ⚠️ À amender : **écriture différée de 2 s** (§ 1).
  - Sur la Fire Stick (environ 35 Mo libres observés), Fire OS tue l'app très vite après la touche Accueil.
  - Or les 2 s qui suivent l'arrivée de la rangée sont justement le moment où l'utilisateur, qui a vu ce qu'il
    voulait, peut quitter l'app.
  - L'écriture serait alors perdue : pas d'affiches grises à l'ouverture suivante (CA1), ou affiches grises de trop
    (CA5).
  - Les écritures n'ont lieu que sur un changement, donc elles sont rares, et le regroupement ne rapporte presque
    rien.
  - → **Écrire tout de suite**, toujours une écriture à la fois (`SerialFutureQueue`, `.tmp` puis `rename`). Pas de
    minuteur ni d'écoute du cycle de vie de l'app.
- ⚠️ À amender : **zone du haut grise dès l'ouverture**, un cas plus fréquent que celui de la question 2 de l'app.
  - Dans une bibliothèque sans « Continuer à regarder », la rangée grise est à l'index 0.
  - `TvSpotlightController.resolve` (`tv_spotlight_scaffold.dart:40-52`) prend alors comme élément de repli
    `hub.items.first`, c'est-à-dire **une affiche grise**.
  - La grande zone du haut est donc vide pendant environ 1 s à chaque ouverture, puis change de titre : un saut
    visuel dans la zone la plus visible.
  - Aujourd'hui, elle montre un vrai titre dès l'ouverture.
  - → Dans `library_recommended_tab.dart`, ignorer les éléments gris :
    - dans `resolveSpotlight: () => _spotlight.resolve(tvHubs)` (`library_recommended_tab.dart:339`), passer les
      hubs filtrés par une fonction du fork ;
    - dans `_setSpotlightItem` (ligne 59), ignorer un élément gris, ce qui règle aussi la question 2 de l'app en
      gardant le dernier titre affiché.
  - Coût : 2 lignes `// FORK:` dans un fichier déjà touché. Cette décision d'aspect revient au PO : à joindre à la
    question 2.
- ⚠️ À amender : **CA6b, sens de « visite »**. Le drapeau « visite close » ne doit être levé que par `_resetFor` ou
  par le retour de l'onglet au premier plan (`_onVisibilityChanged`). Il ne doit **pas** l'être par un rechargement
  des hubs upstream (`didUpdateWidget` avec de nouveaux `hubs`, par exemple après une tirette de rafraîchissement ou
  une mise à jour de l'état vu), sinon une réponse tardive réinsère la rangée pendant la même visite. → Un test de
  la rangée : expiration à 10 s, puis nouveaux `hubs`, puis réponse fraîche, et la rangée doit rester absente.
- ⚠️ À amender : **mesure du démarrage (CA11)**. Si l'app est réglée pour s'ouvrir directement sur une bibliothèque,
  `_loadRecommendedHubs`, et donc la lecture du fichier, a lieu pendant le démarrage. C'est conforme à la spec (« à
  l'ouverture d'une bibliothèque »), mais il faut mesurer dans la même configuration que pour
  `demandes-recentes-overseerr`, et noter laquelle dans le compte rendu de la recette.
- Aucune objection bloquante.

## Validation de architecte-plateforme sur plan.md — tour 1

**APPROUVÉ.** Toutes mes remarques du tour 1 sont reprises :
- écriture immédiate ;
- CA14 par 2 lignes ;
- visite non rouverte par un rechargement des rangées ;
- configuration de démarrage notée pour CA11.

D16 est cohérente avec D7 (aucune différence entre les canaux) et avec la sécurité des données Play (rien ne quitte
l'appareil, `cache/` est hors sauvegarde).

Remarques non bloquantes pour T7 (recette) :
- Étape 8 : `run-as` ne marche pas sur l'APK release de la recette, qui n'est pas débogable. Soit on l'omet, puisque
  le contenu du fichier est déjà vérifié par le test de T1, soit on le fait sur un APK debug distinct. Dans ce
  second cas, il faut désinstaller avant de réinstaller l'APK release, parce que les données de l'APK debug ne sont
  pas celles qu'on veut mesurer.
- Étape 3 : après `adb reboot`, il faut refaire `adb connect 192.168.1.173:5555` une fois la Fire Stick redémarrée.
  Si l'adresse a changé, la relever dans Paramètres > Ma Fire TV > À propos > Réseau.
- Étape 2 : faire la vidéo sans journaux de débogage verbeux. `screenrecord` et `logcat` en même temps chargent la
  Fire Stick et peuvent décaler les images. Faire la mesure du saut et le relevé du journal dans deux passes
  séparées.

## Écart d'implémentation T4 — validé par architecte-app (pilote)
- Constat du codeur T4 : la décision 9 calcule le minuteur comme `10 s − (maintenant − ouverture)`, où l'heure
  d'ouverture est notée par le préchargement (`_loadRecommendedHubs`).
  - Au retour de l'onglet au premier plan, aucun rechargement n'a lieu, et cette heure date de la visite précédente
    (plus de 10 s).
  - Le temps restant serait donc nul et les affiches grises ne réapparaîtraient jamais, ce qui contredit « nouvelle
    visite » (CA6b, CA1).
- Correction retenue : `_onVisibilityChanged` note `clock.now()` comme heure d'ouverture avant `_resetFor()`.
  - **Seulement dans la branche « visite close »** : quand une rangée est affichée, rien ne change, et `_load()`
    suffit.
  - Test « onglet masqué puis visible ». Ajout de `forkDebugResetOpenedAt()` `@visibleForTesting` pour isoler les
    tests de la `Map` statique.
- Validé : le retour au premier plan est bien une nouvelle ouverture au sens de la spec. Le reste du comportement est
  inchangé : un rechargement des rangées ne rouvre pas la visite, et une vraie rangée affichée n'est jamais
  réinitialisée. `plan.md` a été amendé en conséquence (décision 9 et T4).
