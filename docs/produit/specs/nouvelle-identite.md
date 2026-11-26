# Nouvelle identité de l'application : Popkino

Statut : validée         Priorité : Must
Dernière mise à jour : 2026-11-26

Nouveau nom de l'application : **Popkino** (choisi par l'utilisateur le 2026-11-26).

## Problème

Mots de l'utilisateur : « J'aimerais que l'on pense déjà à changer le nom et que l'on fasse le nécessaire pour pouvoir
avoir tous les droits sur l'application pour ensuite la mettre en ligne sur le play store de l'android tv/mobile/fire
stick. C'est un travail préparatoire. L'application sera uniquement disponible via mon repo et lorsque j'aurai fait
toutes les modifications je penserai à la mettre sur un store. »

Aujourd'hui, l'app se présente partout comme Plezy : nom et bannière dans le lanceur Android TV, icône sur téléphone et
ordinateur, logo dans « À propos », une quarantaine de phrases par langue qui citent « Plezy », un bouton « Soutenir
Plezy », le nom « Plezy » dans la liste des appareils Plex et Jellyfin, des liens `plezy://`, des fonctions qui passent
par les serveurs du projet Plezy, et des fichiers de release `plezy-…` (inventaire complet en annexe).

Or le nom et le logo Plezy ne sont pas couverts par la licence libre (voir `TRADEMARKS.md`) : dès que l'app est
distribuée au-delà d'un usage personnel, **y compris par des releases GitHub publiques**, elle doit être clairement une
autre app. Le mainteneur de Plezy l'a confirmé dans un cas proche :
[edde746/plezy#3037](https://github.com/edde746/plezy/issues/3037) (dérogation accordée à un autre fork pour GitHub
uniquement ; « publier sur un store exige le changement complet d'identité »). Plezy est en outre déjà présent sur
Google Play, Amazon Appstore, l'App Store et le Microsoft Store : une copie à l'identique y serait refusée.
Voir aussi [edde746/plezy#2782](https://github.com/edde746/plezy/issues/2782) (demande de renommage de Plezy lui-même,
fermée).

À propos de « tous les droits » : le code reste sous licence GPL-3.0 (public, mentions d'origine conservées). Ce que
l'utilisateur possèdera en propre, c'est **le nom, le logo, les identifiants de l'app, ses clés de signature et ses
propres modifications**. C'est suffisant pour publier gratuitement sur les stores en son nom.

## Objectif

L'utilisateur peut publier sur son dépôt GitHub, pour **toutes les plateformes** (Android TV, téléphone Android,
Fire TV, Windows, Mac, Linux, iPhone/iPad), des versions de l'app qui portent son propre nom et son propre logo,
n'utilisent aucun service du projet Plezy, respectent la licence et peuvent cohabiter avec Plezy officiel sur le même
appareil. Le jour où il voudra passer sur un store, il n'y aura plus rien à changer côté identité.

## Décisions prises avec l'utilisateur (2026-11-26)

- **Nom** : **Popkino** (« pop-corn » + « Kino », cinéma en allemand et en russe). Le dépôt GitHub s'appelle aussi
  `popkino`.
- **Logo** : logo provisoire (« P » blanc sur fond **violet**), utilisé pour l'icône, la bannière TV et l'écran
  « À propos » ; remplacé par un vrai logo avant toute publication sur un store. Les 23 icônes alternatives Plezy sont
  retirées.
- **Services du projet Plezy** : retirés. Cela couvre la synchronisation MyAnimeList et AniList (qui passent par le
  serveur de connexion de Plezy), l'envoi des journaux, et (conséquence, puisque les ordinateurs sont concernés)
  l'affichage « ce que vous regardez » sur Discord, qui passe par l'application Discord de Plezy.
- **Trakt, Simkl et MDBList gardés** (décision de l'utilisateur, 2026-11-26) : ces trois services restent disponibles
  avec toutes leurs fonctions actuelles (suivi de lecture, statut « vu », listes et notes, et pour MDBList les notes
  communautaires Rotten Tomatoes, IMDb, TMDB, Metacritic et Letterboxd sur les fiches). Chacun utilise une application
  gratuite enregistrée par l'utilisateur au nom de Popkino, et non plus celle de Plezy. Pour les trois, la connexion se
  fait par un code à saisir sur le site du service : **elle ne passe par aucun serveur intermédiaire**, il n'y a donc
  rien à héberger ni à payer.
  **Mise à jour (2026-11-26, voir P8)** : les trois services sont reportés ; la 1.0.0 sort sans Trakt, Simkl ni MDBList.
- **Signature** : pas de compte développeur payant pour l'instant. Les avertissements de sécurité à l'installation sur
  Mac, Windows et iPhone sont acceptés et expliqués dans le README.
- **Mises à jour sur ordinateur** : mise à jour automatique sur Windows et Mac, comme Plezy, avec un flux de mises à
  jour et des clés de signature de mise à jour propres à l'utilisateur. Sur Android, l'app signale la nouvelle version
  et propose de la télécharger depuis GitHub, comme aujourd'hui.
- **Thèmes et dons** : les thèmes de couleurs (payants chez Plezy) sont offerts à tous, sans achat ; aucun bouton ni
  lien de don.
- **Plateformes** : toutes celles que Plezy publie sur GitHub (Android, Windows, Mac, Linux, iPhone/iPad). L'Apple TV
  (tvOS) existe dans le code mais Plezy ne la publie pas sur GitHub : son identité est changée aussi, sans fichier de
  release (voir Hors périmètre).

## Parcours utilisateur

1. Sur l'écran d'accueil Android TV, l'utilisateur voit la bannière Popkino (plus celle de Plezy). Focus sur la bannière,
   touche OK : l'app s'ouvre.
2. Les écrans de démarrage, de connexion et de choix de profil affichent Popkino là où ils affichaient Plezy.
3. Dans Paramètres, il descend jusqu'à « À propos » au D-pad, OK : il voit le logo Popkino, le nom, la version, la mention
   « Basé sur Plezy, projet indépendant non affilié », la licence et l'adresse du code source. Le focus arrive sur la
   première entrée sélectionnable ; Retour ramène aux Paramètres, sur l'entrée « À propos ».
4. Dans Paramètres, il ne trouve plus ni « Soutenir Plezy », ni les icônes alternatives, ni MyAnimeList, AniList,
   Discord, ni « Envoyer les journaux ».
4b. **[Reporté — voir P8]** Dans Paramètres > Services, il sélectionne Trakt (ou Simkl, ou MDBList) au D-pad, OK, puis « Se connecter » :
   l'écran affiche un code et l'adresse du site du service (par exemple trakt.tv/activate). Sur son téléphone ou son
   ordinateur, il ouvre cette adresse, saisit le code et voit « Popkino » demander l'accès à son compte ; il accepte.
   Sur la TV, l'écran du service passe tout seul à « Connecté » et le focus reste dans cet écran.
4c. **[Reporté — voir P8]** Avec MDBList connecté, il ouvre la fiche d'un film : les notes Rotten Tomatoes, IMDb, Metacritic… s'affichent
   comme dans Plezy aujourd'hui.
5. Sur son ordinateur, il ouvre son dépôt GitHub : il s'appelle Popkino, le README présente Popkino, et chaque release
   propose des fichiers nommés `popkino-…` pour chaque plateforme. Il installe la version Windows, Mac ou Linux : le
   programme d'installation, le menu Démarrer / le Dock / le menu des applications affichent Popkino et son icône.

## Critères d'acceptation

Lanceur et installation
- CA1 : Étant donné l'APK de release installé sur une Android TV, quand on ouvre l'écran d'accueil, alors la bannière et
  le nom affichés sont ceux de Popkino, sans aucune trace du nom ou du logo Plezy.
- CA2 : Étant donné le même APK installé sur un téléphone Android, quand on ouvre la liste des applications, alors
  l'icône et le nom sont ceux de Popkino.
- CA3 : Étant donné l'APK installé sur un Fire TV Stick (à tester à la main si un appareil est disponible), quand on
  ouvre « Vos applications », alors Popkino apparaît avec son icône, s'ouvre et se pilote à la télécommande Fire TV.
- CA4 : Étant donné la version Windows installée avec le programme d'installation, alors l'assistant d'installation, le
  menu Démarrer, la barre des tâches, la fenêtre et la liste « Applications installées » de Windows affichent Popkino et
  son icône. La version portable affiche aussi Popkino dans sa fenêtre et sa barre des tâches.
- CA5 : Étant donné la version Mac installée depuis son fichier disque, alors la fenêtre du fichier disque, le dossier
  Applications, le Dock et la barre de menus (« À propos de Popkino », « Quitter Popkino ») affichent Popkino et son icône.
- CA6 : Étant donné la version Linux installée par l'un des paquets proposés, alors le menu des applications et la
  fenêtre affichent Popkino et son icône.
- CA7 : Étant donné la version iPhone/iPad installée par sideload (à tester à la main), alors l'écran d'accueil affiche
  Popkino et son icône.
- CA8 : Étant donné un appareil (Android, Windows, Mac, Linux ou iPhone) où Plezy officiel est déjà installé, quand on
  installe Popkino, alors les deux apps apparaissent séparément, chacune avec ses propres réglages, et l'installation ou
  la désinstallation de l'une ne touche pas l'autre.

Textes et écran « À propos »
- CA9 : Étant donné l'app en français puis en anglais, quand on parcourt les écrans listés en annexe (démarrage, erreur
  de démarrage, connexion, profils, paramètres, téléchargements, Regarder ensemble, télécommande depuis un téléphone),
  alors le mot « Plezy » n'apparaît nulle part, sauf dans la mention « basé sur Plezy » de l'écran « À propos ». Les
  autres langues de l'app suivent la même règle.
- CA10 : Étant donné l'écran Paramètres > À propos, alors on y voit : le logo Popkino, le nom Popkino, le numéro de version,
  une phrase indiquant que l'app est basée sur Plezy et n'est ni développée ni soutenue par le projet Plezy, la licence
  GPL-3.0, l'adresse du code source du fork, et l'entrée « Licences open source » qui reste accessible.
- CA11 : Étant donné l'écran « À propos » ouvert à la télécommande, alors toutes ses entrées sélectionnables sont
  atteignables au D-pad, le focus est visible, et Retour ramène aux Paramètres.

Ce que voient les serveurs Plex et Jellyfin
- CA12 : Étant donné un compte Plex connecté, quand on regarde la liste des appareils autorisés sur plex.tv et
  l'activité du serveur pendant une lecture, alors l'app y apparaît sous le nom Popkino, pas « Plezy ».
- CA13 : Étant donné un serveur Jellyfin (ou Emby) connecté, quand on regarde Tableau de bord > Appareils et l'activité
  pendant une lecture, alors l'app y apparaît sous le nom Popkino, pas « Plezy ».

Liens et lecteur externe
- CA14 : Étant donné Plezy officiel et Popkino installés sur le même appareil, quand on ouvre un lien `plezy://…`, alors
  c'est Plezy officiel qui le reçoit, jamais Popkino. Les liens propres à Popkino utilisent son propre préfixe.
- CA15 : Étant donné un lecteur vidéo externe configuré dans Popkino, quand on lit une vidéo avec lui puis qu'on revient,
  alors Popkino reprend la main et enregistre la position de lecture comme avant le changement d'identité.

Services du projet Plezy
- CA16 : Étant donné une utilisation complète de l'app sur Android et sur un ordinateur (connexion, navigation,
  lecture, paramètres), quand on observe le trafic réseau de l'appareil, alors aucune connexion n'est faite vers un
  domaine `plezy.app` (dont `ice.plezy.app` et `bugs.plezy.app`) ni vers Discord.
- CA17 : Étant donné l'écran Paramètres, alors l'entrée « Soutenir Plezy » (don Liberapay au développeur de Plezy)
  n'apparaît pas.
- CA18 : Étant donné l'écran Paramètres > Apparence, alors aucune icône alternative n'est proposée.
- CA18b : Étant donné l'écran Paramètres > Apparence, sur toutes les plateformes, alors tous les thèmes de couleurs
  (préréglés et personnalisés) sont utilisables sans achat ; aucun cadenas, prix, « Pack de thèmes et d'icônes » ni
  bouton d'achat n'apparaît, nulle part dans l'app.
- CA19 : Étant donné l'écran Paramètres > Services, alors MyAnimeList, AniList et Discord n'y apparaissent pas, sur
  aucune plateforme. Les autres réglages de cet écran (par exemple Seerr) restent présents et fonctionnent.
  Pour la 1.0.0, Trakt, Simkl et MDBList n'y apparaissent pas non plus (P8, vérifié par CA19f) ; la phrase d'origine
  « Trakt, Simkl, MDBList […] restent présents et fonctionnent » est reportée avec eux.

Trakt, Simkl et MDBList (chaque critère s'applique aux trois services, sauf mention contraire)
Pour la 1.0.0, CA19b, CA19c, CA19d, CA19e, CA19g, CA19h et CA19i sont **reportés** (P8) : ils ne bloquent pas la
recette et seront vérifiés à la réactivation des services (backlog `services-suivi`). CA19f reste à vérifier : c'est
lui qui décrit le comportement attendu de la 1.0.0 (les trois services absents).
- CA19b : **[Reporté — voir P8]**  Étant donné l'écran Paramètres > Services > [service], quand on lance la connexion, alors un code et
  l'adresse du site du service s'affichent ; après saisie du code sur ce site, la page d'autorisation présente
  l'application sous le nom « Popkino » (jamais « Plezy »), et l'écran de l'app passe à « Connecté » sans autre action à
  la télécommande.
- CA19c (Trakt et Simkl) : **[Reporté — voir P8]**  Étant donné un compte connecté, quand on regarde un film ou un épisode (Plex et Jellyfin),
  alors la lecture remonte sur le service (en cours puis historique) comme avec Plezy aujourd'hui ; et quand on marque
  un élément « vu » dans Popkino avec la synchronisation « vu » activée, alors il est marqué vu sur le service.
- CA19d : **[Reporté — voir P8]**  Étant donné un compte connecté, quand on ouvre la liste des applications autorisées dans son compte sur le
  site du service, alors l'accès apparaît au nom de Popkino ; quand on se déconnecte dans Popkino, alors l'app cesse
  d'envoyer des informations à ce service.
- CA19e : **[Reporté — voir P8]**  Étant donné l'écran de connexion d'un service, quand le code expire ou qu'il n'y a pas de réseau, alors un
  message d'erreur clair s'affiche, la connexion peut être relancée, et le focus reste utilisable.
- CA19f : Étant donné une version de Popkino fabriquée sans les identifiants d'un service (par exemple par un tiers à
  partir du code public, ou si l'utilisateur n'a pas encore créé l'application de ce service), alors l'entrée de ce
  service n'apparaît pas dans Paramètres > Services, ses notes et listes n'apparaissent nulle part, les autres services
  configurés fonctionnent normalement, et l'app n'utilise jamais les identifiants de Plezy.
  Pour la 1.0.0 (P8) : Trakt, Simkl et MDBList sont tous trois absents de Paramètres > Services, aucune note MDBList
  n'apparaît sur les fiches, et aucune erreur ne s'affiche à leur sujet.
- CA19g (MDBList) : **[Reporté — voir P8]**  Étant donné un compte MDBList connecté, quand on ouvre la fiche d'un film ou d'une série connu de
  MDBList, alors les notes communautaires (Rotten Tomatoes critiques et public, IMDb, TMDB, Metacritic, Letterboxd,
  selon ce que MDBList fournit pour ce titre) s'affichent comme dans Plezy aujourd'hui. Sans compte MDBList connecté,
  seules les notes fournies par le serveur Plex/Jellyfin s'affichent, sans message d'erreur.
- CA19h (Simkl) : **[Reporté — voir P8]**  Étant donné un compte Simkl connecté et ni MyAnimeList ni AniList (retirés), quand on regarde un
  anime, alors la lecture remonte sur Simkl si Simkl reconnaît le titre ; aucune erreur n'est affichée sinon.
- CA19i : **[Reporté — voir P8]**  Étant donné l'app utilisée par quelqu'un qui avait connecté Trakt, Simkl ou MDBList dans Plezy, alors
  Popkino ne reprend pas ces connexions : il faut se reconnecter une fois dans Popkino.
- CA20 : Étant donné l'écran Paramètres > Journaux, alors on peut toujours voir, copier et effacer les journaux, et le
  bouton « Envoyer les journaux » n'apparaît pas.
- CA21 : Étant donné l'écran Regarder ensemble, quand on crée une salle sans saisir de nom, alors le nom par défaut et
  le message d'invitation citent Popkino, pas Plezy.

Mise à jour depuis GitHub
- CA22 : Étant donné une version Android de Popkino plus ancienne que la dernière release du dépôt `popkino`, quand
  l'app vérifie les mises à jour, alors elle annonce la release du fork (jamais une version de Plezy officiel) et
  propose de la télécharger depuis GitHub.
- CA22b : Étant donné une version Windows installée (programme d'installation) ou Mac de Popkino plus ancienne que la
  dernière release, quand l'app vérifie les mises à jour, alors elle affiche une fenêtre de mise à jour au nom de
  Popkino ; si l'utilisateur accepte, la nouvelle version Popkino se télécharge depuis le dépôt du fork, s'installe, et
  l'app redémarre sur cette nouvelle version, avec ses réglages et connexions conservés.
- CA22c : Étant donné un fichier de mise à jour qui n'a pas été signé avec la clé de mise à jour de l'utilisateur (par
  exemple une version de Plezy officiel), quand la mise à jour automatique le reçoit, alors elle refuse de l'installer et
  l'app actuelle continue de fonctionner.
- CA22d : Étant donné une version Windows portable (sans installation), alors l'app ne tente pas de se mettre à jour
  toute seule (comme chez Plezy) ; au plus, elle signale la nouvelle version avec un lien vers GitHub.
- CA23 : Étant donné l'absence de réseau, quand l'app vérifie les mises à jour, alors elle n'affiche pas d'erreur
  bloquante et reste utilisable.

Dépôt GitHub, releases et licence
- CA24 : Étant donné la page du dépôt sur GitHub, alors son nom, sa description et le README présentent Popkino ; le
  README dit que l'app est basée sur Plezy et non affiliée, sans badges ni liens de téléchargement vers Plezy officiel ;
  le bouton « Sponsor » de GitHub ne renvoie pas vers le développeur de Plezy.
- CA25 : Étant donné le dépôt, alors le fichier de licence GPL-3.0 et les mentions de copyright d'origine sont présents,
  et un texte visible (README ou fichier dédié) indique que le code a été modifié par rapport à Plezy.
- CA26 : Étant donné une release publiée, alors elle correspond à une étiquette (tag) du dépôt, elle contient les
  fichiers d'Android, Windows, Mac, Linux et iPhone, tous nommés `popkino-…` (aucun `plezy-…`), et sa description ne
  présente pas l'app comme Plezy.
- CA27 : Étant donné une release pour Mac, Windows ou iPhone non signée par un compte développeur (voir Contraintes),
  alors le README explique en quelques lignes comment passer l'avertissement de sécurité affiché à l'installation.

## Hors périmètre

- La publication sur les stores (Google Play, Amazon Appstore, et plus tard éventuellement App Store / Microsoft
  Store) : compte développeur, fiche, captures, politique de confidentialité, formulaire « Sécurité des données », test
  fermé. Sujet `publication-stores` du backlog.
- La publication dans les gestionnaires de paquets (Homebrew, winget, Flathub, AUR…) : Plezy y est présent sous son
  nom, le fork n'y est pas publié pour l'instant.
- Une release Apple TV (tvOS) : Plezy n'en publie pas sur GitHub, et une app Apple TV ne peut s'installer qu'avec un
  compte développeur Apple payant. Le nom et l'icône sont tout de même changés dans le code Apple TV.
- Le site web de Plezy présent dans le dépôt : il n'est ni publié ni adapté.
- Les identifiants internes que l'utilisateur ne voit jamais (noms de code internes) : ils restent tels quels pour
  faciliter la récupération des nouveautés de Plezy, comme l'autorise `TRADEMARKS.md`.
- La récupération des réglages et connexions d'une installation existante de l'app actuelle (qui s'appelle Plezy) :
  Popkino sera une nouvelle app, il faudra se reconnecter une fois à Plex/Jellyfin.
- La réactivation de MyAnimeList et AniList avec nos propres enregistrements (leur connexion passe par un serveur
  intermédiaire, qu'il faudrait héberger) : sujet `services-suivi` du backlog.
- Toute nouvelle fonction Trakt, Simkl ou MDBList : on garde exactement ce que Plezy propose aujourd'hui.
- Le vrai logo définitif : à faire avant `publication-stores`.

## Contraintes

- `regles-fork` §1 (marque) : nom sans « Plezy » ni ressemblance, **sans « Plex »** non plus (marque de Plex Inc. ;
  « pour Plex » reste possible dans une description) ; tous les logos et icônes remplacés sur toutes les plateformes,
  y compris les 23 icônes alternatives ; préfixe de liens propre ; aucun service du projet Plezy (`ice.plezy.app`,
  `bugs.plezy.app`, application Discord, enregistrements Trakt, MyAnimeList, AniList, Simkl, MDBList).
- `regles-fork` §2 (GPL) : code public, licence et copyrights d'origine conservés, modifications signalées, un tag par
  release.
- `regles-fork` §3 (Google Play) : l'app doit être clairement distincte de Plezy. Le nom choisi doit être libre sur
  Google Play et Amazon Appstore ; avant toute publication sur un store, faire aussi une recherche dans les bases de
  marques (INPI / EUIPO). Pas de dons ni d'achat intégré : l'app est gratuite.
- `regles-fork` §4 (TV) : une bannière Android TV propre à Popkino est indispensable ; l'écran « À propos » reste
  utilisable au D-pad.
- `regles-fork` §5 (upstream) : changements d'identité regroupés et localisés pour rester fusionnables avec Plezy.
- **Nom de domaine** : `popkino.com` est déjà enregistré par un tiers (domaine en attente, sans site, depuis 2018).
  Ce n'est pas bloquant : aucune fonction de l'app ne dépend d'un site web, et les stores acceptent une adresse GitHub
  comme site du développeur. Si un site ou une adresse e-mail de contact est voulu plus tard, `popkino.app`, `.fr` et
  `.tv` étaient libres le 2026-11-26 (non réservés).
- **Identifiants définitifs** : l'identifiant de l'app choisi maintenant (Android, et ses équivalents Apple, Windows,
  Linux) ne pourra plus changer une fois l'app publiée sur un store. Le même identifiant sert pour la version GitHub et
  la future version store.
- **Identifiants Trakt, Simkl et MDBList** : chaque application enregistrée par l'utilisateur a un identifiant (et,
  pour Trakt, un code secret). Ils ne sont pas écrits en clair dans le code public du dépôt : ils sont rangés dans les
  réglages secrets du dépôt et ajoutés au moment de fabriquer les releases (ils restent techniquement extractibles d'une
  app installée, comme chez Plezy). S'ils fuitent ou sont abusés, l'utilisateur peut les régénérer sur le site du
  service ; il faudra alors publier une nouvelle version et les utilisateurs devront se reconnecter à ce service.
  Création gratuite ; conditions d'utilisation des API Trakt, Simkl et MDBList à relire avant `publication-stores`
  (notamment les limites d'usage de MDBList, dont dépendent les notes communautaires).
- **Secrets à l'utilisateur, à conserver à vie** (Plezy garde les siens, qui ne sont pas transmis) :
  - la clé de signature Android : la perdre empêche de publier des mises à jour de l'APK (une mise à jour doit être
    signée par la même clé, sinon il faut désinstaller puis réinstaller l'app) ;
  - la clé de signature des mises à jour automatiques Windows et Mac : la perdre empêche les versions déjà installées
    d'accepter les mises à jour suivantes ;
  - ces secrets sont rangés dans les réglages secrets du dépôt GitHub (pour fabriquer les releases) et sauvegardés hors
    de GitHub par l'utilisateur (gestionnaire de mots de passe ou support chiffré). Ils ne sont jamais publiés dans le
    dépôt.
- **Conséquences de « toutes les plateformes » sans comptes développeur payants** :
  - iPhone/iPad : comme chez Plezy, le fichier publié n'est pas signé. Il s'installe seulement par sideload
    (AltStore, Sideloadly…) avec un identifiant Apple ; avec un compte Apple gratuit, l'app doit être réinstallée tous
    les 7 jours. Pas d'autre voie sans compte développeur Apple (99 $/an).
  - Mac : Plezy signe et fait certifier sa version Mac par Apple. Sans compte développeur Apple, la version Mac du fork
    ne sera pas certifiée : macOS affichera « app endommagée » ou « développeur non identifié » et il faudra une
    manipulation pour l'ouvrir.
  - Windows : le programme d'installation n'est pas signé (comme chez Plezy) ; Windows affichera l'avertissement
    « Windows a protégé votre ordinateur » (cliquer « Informations complémentaires » puis « Exécuter quand même »).
  - Mise à jour automatique sur Mac et Windows : chez Plezy, elle dépend d'un flux de mises à jour et d'une clé de
    signature propres au projet Plezy. Le fork a les siens (décision de l'utilisateur).
  - Sur Mac, la mise à jour automatique d'une app non certifiée par Apple peut elle aussi déclencher l'avertissement
    de sécurité de macOS au redémarrage : à tester à la main ; si c'est le cas, l'expliquer dans le README.
  - Linux et Android : aucun point bloquant.

## Questions ouvertes

Aucune.

### Hypothèses retenues, à valider avec la spec

- Télécommande depuis un téléphone : Popkino sur téléphone pilote Popkino sur TV ; la compatibilité avec l'app Plezy
  officielle sur téléphone n'est pas garantie.
- « Regarder ensemble » garde les serveurs publics « Open Watch Party » (indépendants de la marque Plezy, gratuits pour
  les apps open source). Leurs conditions d'utilisation seront relues avant la publication sur un store.

### Actions manuelles qui restent à l'utilisateur

- Renommer le dépôt GitHub `adrien24/plezy` en `popkino` (et sa description).
- **[Reporté — voir P8]** Créer trois applications gratuites nommées « Popkino », chacune en mode « connexion par code » (device code), avec
  un compte (gratuit) sur chaque service : Trakt (page « Your API Apps » de trakt.tv), Simkl (espace développeur de
  simkl.com) et MDBList (page développeur de mdblist.com). Ranger ensuite leurs identifiants (et le code secret Trakt)
  dans les réglages secrets du dépôt. Environ 10 minutes par service, une seule fois ; aucun serveur à héberger, aucun
  coût, aucune maintenance courante. Un service non créé est simplement absent de l'app (CA19f).
- Créer et sauvegarder hors de GitHub la clé de signature Android et la clé de mise à jour Windows/Mac, puis les
  déposer dans les réglages secrets du dépôt.
- Tester à la main ce qui ne peut pas l'être automatiquement : connexion aux trois services (CA19b à CA19i, reportés, P8), Fire TV (CA3), iPhone (CA7), mise à jour automatique
  Mac et Windows (CA22b, CA22c), avertissements de sécurité (CA27).
- Avant `publication-stores` : revérifier le nom « Popkino » sur l'Amazon Appstore, faire une recherche dans les bases
  de marques (INPI, EUIPO), et faire réaliser le logo définitif.

### Vérification du nom (2026-11-26)

| Nom | Sens | Google Play | Domaines libres | GitHub |
|---|---|---|---|---|
| Popkino | « pop(-corn) » + « Kino » (cinéma en allemand / russe) | aucune app de ce nom (proche : « Popkon », drames courts) | .app .fr .tv (.com déjà pris) | nom de compte libre |

Écartés : Sofabri, Cinabri, Fauteo, Kinoya (proposés), Moviora (déjà sur Google Play).
Limites : recherche Amazon Appstore bloquée (recherche web sans résultat), aucune recherche de marque faite.

## Précisions après validation (2026-11-26)

Questions remontées par l'architecture (`docs/technique/nouvelle-identite/proposition-app.md`), tranchées par le PO
au nom des décisions déjà validées. Elles précisent la spec sans en changer le périmètre.

- **P1 — Langues des nouvelles phrases** (mention « Basé sur Plezy… », « Code source », aide du QR code) : rédigées en
  français et en anglais ; dans les 20 autres langues, ces quelques phrases s'affichent en anglais. Raison : l'app est
  d'abord utilisée en français, la mention reste compréhensible partout, et le reste de l'écran reste traduit. La
  traduction complète est notée au backlog (`traductions-fork`, Could). Complète CA9 et CA10 : dans une langue autre
  que le français et l'anglais, ces phrases en anglais sont acceptées ; le mot « Plezy » n'apparaît toujours que dans
  la mention « basé sur Plezy ».
- **P2 — « Code source » sur TV** : la plupart des TV n'ont pas de navigateur. Sur TV, choisir « Code source » dans
  « À propos » ouvre une fenêtre avec un QR code et l'adresse en clair, à scanner avec le téléphone ; Retour ferme la
  fenêtre et le focus revient sur « Code source ». Sur téléphone et ordinateur, l'adresse s'ouvre dans le navigateur.
  Complète CA10 et CA11.
- **P3 — Préférences de compte Jellyfin/Emby enregistrées sur le serveur** : Popkino les enregistre sous son propre nom,
  séparément de Plezy officiel. Changer un de ces réglages dans Popkino ne le change pas dans Plezy officiel, et
  inversement ; entre plusieurs appareils Popkino du même compte, ils restent partagés. Les préférences déjà
  enregistrées par Plezy ne sont pas reprises (cohérent avec le hors-périmètre « pas de reprise des réglages »). Le
  texte d'aide de ce réglage cite « Popkino sur vos autres appareils ». Complète CA8 et CA13.
- **P4 — Écran de réparation au démarrage** : le texte rare qui cite « MAL, AniList » parmi les services enregistrés à
  part reste tel quel. Raison : écran exceptionnel (données de réglages endommagées), texte sans le mot « Plezy »,
  aucune action possible de l'utilisateur ne dépend de cette liste ; le modifier dans 22 langues coûte plus que le
  gain. Exception acceptée à CA19 (qui ne porte que sur Paramètres > Services).

- **P5 — Numéro de la première version** : Popkino repart à **1.0.0**, puis sa numérotation avance à chaque release du
  fork, indépendamment de celle de Plezy. Raison : c'est une nouvelle app (spec : « nouvelle app, il faut se
  reconnecter ») ; garder les numéros de Plezy ferait croire à une continuité et fausserait la détection des mises à
  jour (CA22). Complète CA10 (version affichée) et CA26.
- **P6 — Vérification des développeurs Android** (obligatoire partout en 2027 pour installer un APK hors store sur
  téléphone ou tablette sans manipulation ; les TV ne sont pas concernées) : rien à faire dans ce sujet. Reporté au
  backlog (`verification-developpeur-android`, Should), à faire avant la généralisation de 2027 et au plus tard avec
  `publication-stores`. D'ici là, sur téléphone, l'installation de l'APK GitHub reste possible, avec une étape de
  confirmation supplémentaire dans les pays déjà concernés.
- **P7 — Décisions de l'utilisateur (2026-11-26)** :
  - Identifiant définitif de l'app : `io.github.adrien24.popkino` (gratuit, lié au compte GitHub, aucun nom de domaine
    acheté). Identique pour la version GitHub et les futures versions store ; ne changera plus après la 1re release.
  - Éditeur affiché (Windows « Applications installées », informations Mac et Linux, mention de copyright) :
    `adrien24`.
  - Issues GitHub activées sur le dépôt `popkino`, pour recevoir les signalements des utilisateurs des releases.
- **P8 — Trakt, Simkl et MDBList reportés (décision de l'utilisateur, 2026-11-26)** : « on va mettre de côté pour le
  moment car trop compliqué de les intégrer ». Pendant l'action manuelle A4, le compte Simkl n'a pas pu être créé, et
  l'application Trakt a été créée dans un mode qui ne fournit pas de code secret, alors que la connexion par code de
  Popkino en exige un. La release 1.0.0 sort donc **sans Trakt, Simkl ni MDBList** : ces trois services sont absents de
  Paramètres > Services et des fiches (comportement de CA19f, sans changement de l'app). Critères reportés, conservés
  pour la réactivation : CA19b, CA19c, CA19d, CA19e, CA19g, CA19h, CA19i, ainsi que la partie « Trakt, Simkl, MDBList
  restent présents » de CA19 et les étapes 4b et 4c du parcours. La réactivation est suivie au backlog
  (`services-suivi`).

## Annexe : inventaire de ce qui porte l'identité Plezy aujourd'hui

| Où l'utilisateur le voit | Aujourd'hui | Attendu |
|---|---|---|
| Lanceur Android TV | Nom « Plezy », bannière Plezy | Popkino, bannière Popkino |
| Lanceur téléphone / Fire TV / iPhone | Nom et icône Plezy | Popkino, icône Popkino |
| Windows (installateur, menu Démarrer, barre des tâches, Applications installées) | Plezy | Popkino |
| Mac (fichier disque, Dock, barre de menus) | Plezy | Popkino |
| Linux (menu des applications, paquets) | Plezy | Popkino |
| Apple TV (code seulement, pas de release) | Plezy | Popkino |
| Paramètres > Apparence > Icône de l'app | 23 icônes alternatives Plezy (« Pack de thèmes et d'icônes ») | Retirées |
| Paramètres > À propos | Logo Plezy, titre « Plezy », « Un magnifique client Plex, Jellyfin et Emby » | Logo et nom Popkino, mention « basé sur Plezy », licence, adresse du code source |
| Textes de l'app (22 langues, ~40 phrases chacune) | « Plezy n'a pas pu démarrer », « Ajouter un profil Plezy », « Quitter Plezy », messages de téléchargement en arrière-plan, Regarder ensemble, télécommande, services de suivi… | Popkino |
| Paramètres > Soutenir Plezy | Don Liberapay au développeur de Plezy | Retiré |
| Plex (plex.tv, activité du serveur) | Appareil nommé « Plezy » | Popkino |
| Jellyfin / Emby (tableau de bord) | Client nommé « Plezy » | Popkino |
| Regarder ensemble | Nom par défaut « Plezy », message d'invitation « …dans Plezy » | Popkino |
| Liens d'ouverture de l'app et retour du lecteur externe | Préfixe `plezy://` | Préfixe propre à Popkino |
| Trakt, Simkl, MDBList (dont notes communautaires via MDBList) | Applications enregistrées au nom de Plezy (connexion par code, sans serveur) ; Simkl se présente comme « plezy » | Gardés, avec les applications « Popkino » de l'utilisateur ; absents de la 1.0.0 (reportés, P8) |
| MyAnimeList, AniList | Enregistrés au nom de Plezy, connexion via `ice.plezy.app` | Retirés |
| Paramètres > Journaux > Envoyer | Envoi vers `ice.plezy.app` | Retiré |
| Discord (ordinateur) | Application Discord de Plezy, images via `ice.plezy.app` | Retiré |
| Rapports de plantage | Vers `bugs.plezy.app` (déjà inactif hors dépôt officiel) | Toujours inactif |
| Vérification de mise à jour (Android, Windows, Mac) | Releases et flux de mises à jour de Plezy officiel | Ceux du fork |
| Correspondances d'anime (téléchargées) | Fichier publié sur le GitHub du développeur de Plezy, utilisé par MyAnimeList, AniList et, pour les animes, Simkl (Trakt et MDBList ne s'en servent pas) | Plus téléchargé une fois MAL et AniList retirés ; Simkl reconnaît alors les animes sans lui (CA19h) |
| Dépôt GitHub | Nom « plezy », README Plezy avec badges des stores Plezy, bouton Sponsor vers le développeur de Plezy | Popkino, README propre, Sponsor retiré |
| Fichiers de release | `plezy-…` (APK, IPA, DMG, installateur et portables Windows, paquets Linux) | `popkino-…` |
| Identifiant de l'app sur l'appareil et les stores | Celui de Plezy officiel | Identifiant propre à l'utilisateur |
