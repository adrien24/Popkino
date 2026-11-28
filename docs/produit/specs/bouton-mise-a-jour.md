# Mettre à jour l'app depuis la TV

Statut : validée        Priorité : Should
Dernière mise à jour : 2026-11-28

## Problème

L'utilisateur : « j'aimerais rajouter un bouton mise à jour sur l'écran d'accueil à côté du bouton Watch Together, pour
que lorsque je fais une nouvelle release les utilisateurs puissent télécharger cette release directement depuis
l'app ».

Aujourd'hui, sur la Fire TV Stick, mettre à jour Popkino demande un ordinateur : télécharger l'APK sur GitHub puis
l'installer à la main (adb ou appli de type Downloader). Ce que l'app fait déjà, et pourquoi ça ne suffit pas :

- La version GitHub vérifie au démarrage (au plus une fois toutes les 6 heures) s'il existe une nouvelle version et
  affiche alors une fenêtre « Mise à jour disponible ». Paramètres a aussi une ligne « Vérifier les mises à jour ».
- Mais le seul bouton de cette fenêtre, « Voir les notes de version », ouvre la page GitHub dans un navigateur. La
  plupart des TV n'en ont pas, et même avec un navigateur il faut ensuite installer l'APK soi-même.
- La vérification ignore les **pré-versions** GitHub. Or les deux versions publiées à ce jour (0.1.0 et 0.2.0) sont des
  pré-versions : l'app ne trouve donc jamais rien.
- Rien n'est visible sur l'écran d'accueil : on ne sait qu'il existe une mise à jour que si la fenêtre de démarrage
  apparaît.

Côté Plezy, le besoin est connu et **refusé** : [#2868](https://github.com/edde746/plezy/issues/2868) (téléchargement et
installation de l'APK depuis l'app, fermé « non prévu »), [#1782](https://github.com/edde746/plezy/issues/1782) (fermé),
[#3125](https://github.com/edde746/plezy/issues/3125) (ouvert, sans réponse). C'est donc une fonction propre à
Popkino, qui ne reviendra pas par les fusions upstream.

## Objectif

Sur une TV Android ou Fire TV qui a installé Popkino depuis GitHub, quand une nouvelle version est publiée,
l'utilisateur la voit depuis l'écran d'accueil et l'installe entièrement à la télécommande, sans ordinateur ni
navigateur, en gardant ses comptes et réglages.

## Parcours utilisateur

1. **Accueil (Découvrir)**. Une nouvelle version existe. Dans la barre d'icônes en haut à droite, un bouton « Mise à
   jour » apparaît juste à droite du bouton Watch Together, avec un signe visible (pastille de couleur) qui indique
   qu'il y a du nouveau. Le focus de départ de l'écran ne change pas (il reste sur le contenu).
2. L'utilisateur remonte dans la barre d'icônes avec la flèche Haut et se déplace jusqu'au bouton avec Gauche/Droite.
   Le bouton a la même taille et le même effet de focus que ses voisins ; s'y arrêter affiche son nom
   « Mise à jour disponible ».
3. **OK** ouvre une fenêtre : « Version X.Y.Z disponible », « Version installée : A.B.C », puis la description de la
   version rédigée sur GitHub (ce qui a changé). Boutons : « Plus tard » et « Télécharger et installer ». Le focus est
   sur « Télécharger et installer ».
4. **OK sur « Télécharger et installer »** : la fenêtre affiche une barre de progression (pourcentage) et un bouton
   « Annuler ». Retour ou « Annuler » arrêtent le téléchargement et ramènent à l'accueil, focus sur le bouton
   « Mise à jour ».
5. **Première fois seulement** : Android/Fire OS exige d'autoriser Popkino à installer des applications. L'app
   l'explique en une phrase (« Pour installer la mise à jour, autorisez Popkino à installer des applications ») avec
   un bouton « Ouvrir les réglages ». L'utilisateur active l'autorisation et appuie sur Retour. Popkino peut alors
   redémarrer (le système le ferme sur Android 11) : la fenêtre de mise à jour se rouvre avec un bouton « Installer »
   (focus dessus), sans retélécharger.
6. **Écran d'installation du système** (Android/Fire OS, hors de l'app) : « Voulez-vous mettre à jour cette
   application ? » ; l'utilisateur choisit « Installer ».
7. Une fois installée, le système propose « Ouvrir ». Popkino redémarre dans la nouvelle version, toujours connecté
   aux mêmes serveurs, avec les mêmes réglages. Le bouton « Mise à jour » a disparu de l'accueil.

## Critères d'acceptation

Sauf mention contraire, « version GitHub » = l'APK Android téléchargé depuis les releases GitHub de Popkino, testé sur
la Fire TV Stick à la télécommande.

Affichage du bouton
- CA1 : Étant donné la version GitHub installée et une version plus récente publiée sur GitHub, quand on ouvre l'app
  et qu'on arrive sur l'accueil, alors le bouton « Mise à jour » apparaît à droite du bouton Watch Together, avec une
  pastille, en moins de 10 secondes après l'arrivée sur l'accueil.
- CA2 : Étant donné la version GitHub déjà à la dernière version, quand on arrive sur l'accueil, alors aucun bouton
  « Mise à jour » n'est visible et la barre d'icônes est identique à celle d'aujourd'hui.
- CA3 : Étant donné l'accueil avec le bouton « Mise à jour », quand on navigue dans la barre d'icônes avec
  Gauche/Droite, alors le bouton reçoit le focus comme ses voisins, le focus est visible, et on peut en sortir dans
  toutes les directions comme depuis le bouton Watch Together (Gauche vers les icônes précédentes, Bas vers le
  contenu).
- CA4 : Étant donné une app qui reste ouverte sur l'accueil, quand une nouvelle version est publiée pendant ce temps,
  alors le bouton apparaît au plus tard au prochain lancement de l'app (pas d'exigence d'apparition en direct).
- CA5 : Étant donné une version publiée sur GitHub comme **pré-version** et plus récente que la version installée,
  alors elle est proposée exactement comme une version normale (bouton, fenêtre de démarrage, Paramètres). Une version
  encore en **brouillon** n'est jamais proposée. Si plusieurs versions plus récentes existent, c'est la plus récente
  (au plus grand numéro) qui est proposée.

Fenêtre et téléchargement
- CA6 : Étant donné le bouton « Mise à jour » au focus, quand on appuie sur OK, alors une fenêtre affiche le numéro de
  la nouvelle version, celui de la version installée et la description de la version publiée sur GitHub ; si la
  description est plus longue que la fenêtre, on la fait défiler avec Haut/Bas ; la description s'affiche en texte
  simple et lisible (pas de symboles de mise en forme visibles, les listes à puces restent des listes, les liens
  apparaissent comme du texte non cliquable) ; le focus initial est sur
  « Télécharger et installer ».
- CA7 : Étant donné cette fenêtre, quand on appuie sur « Plus tard » ou sur Retour, alors elle se ferme sans rien
  télécharger et le focus revient sur le bouton « Mise à jour ».
- CA8 : Étant donné « Télécharger et installer » choisi, alors l'app télécharge le fichier qui correspond au processeur
  de l'appareil (la Fire TV Stick 32 bits reçoit l'APK armeabi-v7a, un appareil 64 bits reçoit l'APK arm64-v8a), et
  une progression en pourcentage avance à l'écran.
- CA9 : Étant donné un téléchargement en cours, quand on appuie sur « Annuler » ou sur Retour, alors le téléchargement
  s'arrête, la fenêtre se ferme, le focus revient sur le bouton « Mise à jour », et aucun fichier partiel ne reste
  sur l'appareil.

Installation
- CA10 : Étant donné que Popkino n'a pas encore l'autorisation d'installer des applications, quand le téléchargement
  se termine, alors l'app affiche une phrase d'explication et un bouton « Ouvrir les réglages » qui mène directement
  à l'écran d'autorisation de Popkino ; après l'avoir activée et appuyé sur Retour, la fenêtre de mise à jour est de
  nouveau affichée avec un bouton « Installer » au focus (y compris si Popkino a redémarré entre-temps), et « Installer »
  ouvre l'écran d'installation du système sans retélécharger le fichier. Si le système ne sait pas ouvrir directement
  le réglage de Popkino (il ouvre un écran de réglages général), la phrase d'explication indique en plus le chemin
  complet à suivre (sur Fire TV : « Options pour les développeurs > Installer des applis inconnues > Popkino »).
- CA11 : Étant donné l'autorisation refusée (l'utilisateur revient sans l'activer), alors l'app affiche « Installation
  impossible sans autorisation », propose « Réessayer », et rien d'autre ne change. « Réessayer » rouvre directement l'écran d'autorisation de
  Popkino, sans retélécharger le fichier.
- CA12 : Étant donné l'écran d'installation du système affiché, quand on choisit « Installer », alors la nouvelle
  version s'installe ; à la réouverture, Paramètres > À propos affiche le nouveau numéro de version, les serveurs Plex
  **et** Jellyfin déjà ajoutés sont toujours connectés et les réglages (langues préférées, etc.) sont conservés.
- CA13 : Étant donné l'écran d'installation du système, quand on choisit « Annuler », alors on revient dans Popkino,
  sur l'accueil, le bouton « Mise à jour » est toujours là et peut être réutilisé.
- CA14 : Étant donné une installation réussie ou abandonnée, alors le fichier téléchargé ne reste pas stocké sur
  l'appareil (l'espace libre ne diminue pas d'une mise à jour à l'autre).

Erreurs
- CA15 : Étant donné l'appareil sans connexion Internet (ou GitHub injoignable) au démarrage, alors aucun message
  d'erreur n'apparaît sur l'accueil et le bouton n'apparaît pas ; l'app fonctionne normalement.
- CA16 : Étant donné une coupure réseau pendant le téléchargement, alors la fenêtre affiche « Le téléchargement a
  échoué. Vérifiez la connexion. » avec « Réessayer » et « Fermer » ; « Réessayer » relance le téléchargement.
- CA17 : Étant donné une release GitHub qui ne contient aucun APK pour le processeur de l'appareil, alors le bouton
  n'apparaît pas (on ne propose pas une mise à jour qu'on ne peut pas installer), même si une version intermédiaire,
  plus récente que la version installée, contient un APK adapté : on ne propose que la version la plus récente.
- CA18 : Étant donné un espace de stockage insuffisant, alors un message le dit clairement (« Espace insuffisant pour
  télécharger la mise à jour ») au lieu d'un échec silencieux.
- CA19 : Étant donné une nouvelle version signée avec une autre clé que la version installée (cas du passage de la
  clé de test à la clé définitive), quand le système refuse l'installation, alors l'app affiche un message qui
  explique qu'il faut désinstaller puis réinstaller Popkino une fois (et que les comptes devront être ajoutés à
  nouveau), au lieu d'un échec sans explication.

Canaux de distribution
- CA20 : Étant donné une version construite pour un store (Google Play, Amazon Appstore), alors aucun bouton
  « Mise à jour », aucune fenêtre de mise à jour, aucune ligne « Vérifier les mises à jour » dans Paramètres, et l'app
  ne demande jamais l'autorisation d'installer des applications.
- CA21 : Étant donné la version GitHub, quand on va dans Paramètres > Mises à jour > « Vérifier les mises à jour » et
  qu'une version existe, alors on arrive dans la même fenêtre qu'en CA6, avec le même parcours d'installation.
- CA22 : Étant donné les versions ordinateur (Mac, Windows, Linux), alors leur fonctionnement de mise à jour actuel
  est inchangé.

Fenêtre au démarrage
- CA23 : Étant donné la version GitHub, une version plus récente publiée et « Vérifier automatiquement les mises à
  jour au démarrage » activé, quand on lance l'app, alors la fenêtre « Mise à jour disponible » s'ouvre toute seule
  (au plus une fois toutes les 6 heures, comme aujourd'hui) avec trois boutons : « Plus tard », « Ignorer cette
  version » et « Télécharger et installer » (focus sur ce dernier). « Télécharger et installer » suit le même parcours
  que CA8 à CA19 ; elle n'ouvre plus de navigateur.
- CA24 : Étant donné la fenêtre de démarrage, quand on choisit « Ignorer cette version », alors la fenêtre ne s'ouvre
  plus au démarrage pour cette version-là, mais le bouton « Mise à jour » reste visible sur l'accueil ; quand une
  version encore plus récente est publiée, la fenêtre de démarrage réapparaît.
- CA25 : Étant donné « Vérifier automatiquement les mises à jour au démarrage » désactivé, alors la fenêtre ne
  s'ouvre jamais toute seule, et le bouton de l'accueil apparaît quand même quand une version existe.

Téléphones
- CA26 : Étant donné la version GitHub installée sur un téléphone Android, alors le bouton, la fenêtre et
  l'installation fonctionnent comme sur la TV (CA1 à CA25), au toucher : le bouton est à côté de Watch Together dans
  la barre en haut de l'écran Découvrir.

## Hors périmètre

- Mise à jour automatique sans action de l'utilisateur (le système demande de toute façon une confirmation).
- Mise à jour dans la version Google Play (par le mécanisme de mise à jour propre à Play) : à traiter avec
  `publication-stores`.
- Revenir à une version précédente.
- Gérer le cas « désinstaller / réinstaller » à la place de l'utilisateur (CA19 se contente de l'expliquer).

## Contraintes

- **Fonction temporaire** (utilisateur, 2026-11-28) : « cette fonctionnalité sera supprimée lorsqu'on déploiera
  l'application sur les stores » ; elle sert tant que Popkino n'est distribué que par GitHub. Son retrait sera décidé
  avec `publication-stores`.

- **Google Play (`regles-fork` §3)** : la version Play ne doit contenir ni le téléchargement d'APK depuis GitHub ni
  l'autorisation d'installer des applications. Même règle de prudence pour Amazon Appstore. La décision D7 fixe déjà
  la séparation : seules les versions GitHub ont la vérification des mises à jour (CA20). Si l'autorisation
  d'installer doit figurer dans la description de l'app, les versions store doivent en être exemptes : c'est aux
  architectes de dire comment, sans dupliquer le code.
- **Marque** : textes au nom de Popkino, téléchargement uniquement depuis le dépôt GitHub de Popkino, aucun service
  du projet Plezy.
- **TV** : tout au D-pad, focus toujours visible, Retour ferme la fenêtre ou annule le téléchargement, textes lisibles
  à 3 mètres.
- **Fusion upstream** : fonction refusée par Plezy, donc à garder dans des ajouts propres au fork autant que possible ;
  l'écran d'accueil et la fenêtre de mise à jour sont des fichiers upstream à modifier peu.
- **Process de release** : pour être proposée, une version doit être publiée (pas en brouillon), contenir les APK par
  processeur et avoir un numéro plus grand que la version installée. Les tags actuels sont `v0.1.0` et `v0.2.0` alors
  que la décision D10 prévoit des tags sans « v » : à harmoniser par les architectes, la vérification acceptant les
  deux aujourd'hui.
- **Clé de signature** : la 0.2.0 est signée avec la clé de test. La première version signée avec la clé définitive
  ne pourra pas s'installer par-dessus (CA19) ; seules les mises à jour suivantes profiteront pleinement du bouton.
- Pré-versions proposées à tous : quiconque installe la version GitHub recevra aussi les versions de test. Avant
  d'ouvrir l'app au public, il faudra choisir de ne publier en pré-version que ce qu'on accepte de voir installé.
- Téléphones Android et TV : même APK GitHub, même fonction.

## Décisions de l'utilisateur (2026-11-28)

1. Le bouton n'apparaît que quand une nouvelle version existe, avec une pastille.
2. Les pré-versions sont proposées comme les versions normales.
3. La fenêtre de démarrage est gardée, avec « Télécharger et installer » et « Ignorer cette version ».
4. Même fonction sur téléphone Android et sur TV.

## Questions ouvertes

Aucune. Spec validée par l'utilisateur le 2026-11-28 (proposition CA24 acceptée). Précisions du PO (2026-11-28,
sans changement de fond) : CA6 texte simple, CA11 « Réessayer », CA17 version intermédiaire ; CA10 fenêtre rouverte avec « Installer » et
chemin complet si besoin ; CA19 réinstallation unique plutôt que de garder la clé de test liée à l'app ; les
releases publient des APK prêts à installer (plus d'archive à extraire, liens du README à mettre à jour).
