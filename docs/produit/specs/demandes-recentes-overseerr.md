# Demandes récentes Overseerr dans les bibliothèques

Statut : validée           Priorité : Should
Dernière mise à jour : 2026-11-28 (badges revus après la recette sur la Fire TV Stick)

## Problème

Quand l'app est reliée à Overseerr (ou Jellyseerr), on peut demander un film ou une série depuis « Explorer », mais
ensuite l'app ne remontre jamais ce qu'on a demandé. Pour savoir si une demande est arrivée sur le serveur, il faut se
souvenir du titre, le rechercher, ouvrir sa fiche, ou prendre son téléphone pour ouvrir le site d'Overseerr.

Mots de l'utilisateur : « si mon Popkino est connecté à un Overseerr je voudrais pouvoir voir les demandes que j'ai
faites. Exemple : je vais sur mes séries, en dessous de "Continuer à regarder" on a "Demandes récentes" qui affiche les
demandes des séries. Si je clique sur une des demandes cela me redirige vers la série du serveur si c'est disponible, et
si ce n'est pas encore disponible ça me redirige vers la fiche de la série que l'on peut retrouver dans "Explorer". On
veut la même chose avec les films et les animés. »

Écran concerné : l'onglet d'accueil d'une bibliothèque (Séries, Films, Animés), celui qui affiche « Continuer à
regarder ».

Upstream :
- [#3050](https://github.com/edde746/plezy/issues/3050) (ouvert, sans réponse) : même besoin, proposé sous forme d'une
  rangée « Mes demandes » dans Explorer.
- [#2410](https://github.com/edde746/plezy/issues/2410) : écran « Mes demandes », **fermé comme non prévu** par
  l'auteur de Plezy. Fonction donc propre à Popkino (candidate aux « fonctions propres » exigées par Google Play).

## Objectif

Dans chaque bibliothèque, l'utilisateur voit en un coup d'œil ses dernières demandes Overseerr du bon type (films dans
Films, séries dans Séries, animés dans Animés) et leur état, et y accède en une pression sur OK : vers le titre du
serveur s'il est arrivé, sinon vers sa fiche « Explorer ».

## Parcours utilisateur

1. Dans le menu, l'utilisateur ouvre la bibliothèque « Séries ». L'onglet d'accueil de la bibliothèque s'affiche, focus
   comme aujourd'hui sur la première affiche de « Continuer à regarder ».
2. Il appuie sur Bas : le focus arrive sur la première affiche de la rangée « Demandes récentes », placée juste sous
   « Continuer à regarder ». Chaque affiche porte un badge d'état (Demandé, Approuvé, En cours, Disponible,
   Partiellement disponible…).
3. Il se déplace à Gauche / Droite dans la rangée. La demande la plus récente est la première à gauche.
4. Il appuie sur OK sur une série **disponible** : la fiche de la série sur son serveur (Plex ou Jellyfin) s'ouvre,
   avec ses saisons et le bouton de lecture, comme s'il l'avait ouverte depuis la bibliothèque.
5. Il appuie sur OK sur une série **pas encore disponible** : la fiche « Explorer » de la série s'ouvre (résumé, état
   de la demande, bouton de demande), la même que s'il l'avait trouvée dans Explorer.
6. Retour le ramène sur la bibliothèque, focus sur l'affiche de la demande qu'il venait d'ouvrir.

Même parcours dans « Films » (demandes de films) et « Animés » (demandes d'animés).

## Critères d'acceptation

Rangée
- CA1 : Étant donné l'app reliée à Overseerr et au moins une demande de série faite par l'utilisateur, quand il ouvre
  la bibliothèque Séries, alors une rangée intitulée « Demandes récentes » apparaît juste sous « Continuer à regarder »
  et ne contient que des séries (aucun film, aucun animé).
- CA2 : Étant donné des demandes de films, quand l'utilisateur ouvre la bibliothèque Films, alors la rangée « Demandes
  récentes » ne contient que des films.
- CA3 : Étant donné des demandes d'animés (séries **et** films), quand l'utilisateur ouvre la bibliothèque Animés,
  alors la rangée contient ces animés, séries et films mélangés, et ils n'apparaissent ni dans la rangée de Séries ni
  dans celle de Films. Exemple : un film Ghibli demandé apparaît dans Animés, pas dans Films.
- CA3b : Un titre est un animé s'il porte la marque « anime » dans ses informations TMDB, la même règle que celle
  qu'Overseerr applique au moment de la demande. Exemple à vérifier : une série animée japonaise demandée va dans
  Animés ; une série d'animation américaine (ex. Les Simpson) reste dans Séries.
- CA3c : Étant donné aucune bibliothèque Animés reconnue, alors les animés vont dans Séries ou dans Films selon leur
  type, comme les autres titres (rien n'est perdu).
- CA3e : Étant donné des animés rangés dans la bibliothèque « Séries » (pas de bibliothèque Animés à part), alors
  « Séries » n'est jamais prise pour la bibliothèque Animés : les animés restent dans Séries et Films (CA3c).
- CA3d : La bibliothèque Animés est reconnue sans aucun réglage : c'est la bibliothèque où se trouvent les animés déjà
  demandés et arrivés sur le serveur ; tant qu'aucun n'est arrivé, c'est la bibliothèque dont le nom contient « Anim »
  (majuscules ou minuscules, ex. « Animés », « Anime », « Animations japonaises »).
- CA4 : Étant donné une bibliothèque sans « Continuer à regarder » (rien en cours), quand elle s'ouvre, alors « Demandes
  récentes » est la première rangée de l'onglet.
- CA5 : La rangée est triée de la demande la plus récente à la plus ancienne et montre au plus les 20 dernières
  demandes du type concerné, prises parmi les 100 dernières demandes de l'utilisateur (une demande plus ancienne que
  ces 100 n'apparaît pas).
- CA5b : Étant donné plusieurs bibliothèques du même type (ex. « Séries » et « Séries enfants », ou deux serveurs),
  alors chacune affiche la rangée avec les mêmes demandes.
- CA6 : Seules les demandes faites par l'utilisateur connecté à Overseerr apparaissent, même si ce compte est
  administrateur et voit les demandes des autres sur le site d'Overseerr.
- CA7 : Chaque affiche montre le titre (au focus, comme les autres rangées) et **exactement un** badge d'état,
  entièrement lisible à 3 mètres sur la Fire TV Stick (aucun texte coupé par « … »). Le badge reflète l'état actuel du
  titre dans Overseerr : un titre disponible affiche seulement « Disponible », jamais « Disponible » et « Demandé »
  empilés. Dans la rangée, les textes longs sont raccourcis : « En attente » (au lieu de « En attente d'approbation »),
  « Partiel » (au lieu de « Partiellement disponible »), « En cours » (au lieu de « En cours de traitement »).
  Explorer garde ses textes actuels.
- CA7b : Les demandes refusées ou en échec apparaissent aussi dans la rangée, avec un badge « Refusé » ou « Échec »
  distinct des autres états. OK sur l'une d'elles ouvre la fiche Explorer.
- CA7c : Un titre marqué « Supprimé » dans Overseerr apparaît avec un badge « Supprimé » (jamais sans badge). OK ouvre
  la fiche Explorer, avec le bouton de demande, sans écran d'erreur.
- CA7d : Dans la rangée « Demandes récentes » seulement, chaque badge a une couleur de fond selon l'état, le texte
  restant affiché (la couleur seule ne suffit pas) : vert = Disponible, bleu = Partiel, jaune = En attente,
  violet = Demandé, orange = En cours, rouge = Échec, Refusé et Supprimé. Les badges d'Explorer ne changent pas.
- CA7e : Si plusieurs états s'appliquent, un seul badge est montré, dans cet ordre de priorité : Disponible, Partiel,
  En cours, Demandé, En attente, Échec, Refusé, Supprimé. Exception : un titre supprimé du serveur affiche
  « Supprimé » même si une ancienne demande est restée « approuvée » (comme un titre disponible n'affiche pas
  « Demandé ») ; seule une nouvelle demande en attente d'approbation (« En attente ») passe devant.
- CA7g : Les badges suivent les libellés d'Overseerr. Un titre accepté et transmis au gestionnaire de téléchargement
  (Sonarr, Radarr), mais dont le téléchargement n'a pas commencé, affiche « Demandé » (violet), comme sur le site
  d'Overseerr. « En cours » (orange) est réservé à un téléchargement réellement en cours, c'est-à-dire quand Overseerr
  affiche lui-même « Processing / En cours ». Si l'app ne peut pas savoir qu'un téléchargement est en cours, elle
  affiche « Demandé ». Exemple à vérifier : Invincible, « Demandé » sur Overseerr, affiche « Demandé » dans la rangée.
- CA7f : Cas rares sans état prévu ci-dessus : un titre bloqué dans Jellyseerr affiche « Bloqué » en rouge ; un titre
  dont Overseerr ne donne aucun état reconnaissable n'a pas de badge (seule exception à « exactement un » de CA7).

Ouverture d'une demande
- CA8 : Étant donné une demande dont le titre est disponible sur le serveur, quand l'utilisateur appuie sur OK, alors la
  fiche du titre sur le serveur s'ouvre (série : avec ses saisons ; film : avec le bouton Lire), en moins de 3 secondes
  sur la Fire TV Stick.
- CA9 : Étant donné une demande pas encore disponible (demandée, approuvée, en cours de téléchargement), quand
  l'utilisateur appuie sur OK, alors la fiche Explorer du titre s'ouvre, avec son état de demande à jour.
- CA10 : Étant donné une demande partiellement disponible (une partie des saisons seulement), quand l'utilisateur appuie
  sur OK, alors la fiche de la série sur le serveur s'ouvre, avec les saisons déjà arrivées.
- CA11 : Étant donné un titre annoncé « disponible » par Overseerr mais introuvable sur le serveur (serveur éteint,
  titre supprimé ou non reconnu), quand l'utilisateur appuie sur OK, alors la fiche Explorer s'ouvre à la place, sans
  écran d'erreur ni blocage.
- CA12 : Depuis la fiche ouverte (serveur ou Explorer), Retour revient sur la bibliothèque avec le focus sur l'affiche
  qui venait d'être ouverte.
- CA13 : Étant donné un titre qui vient d'arriver sur le serveur, quand l'utilisateur rouvre la bibliothèque, alors son
  badge affiche « Disponible » et OK ouvre la fiche du serveur.

Télécommande
- CA14 : Toute la rangée se parcourt au D-pad : Bas depuis « Continuer à regarder » arrive sur la rangée, Haut y
  revient, Bas mène à la rangée suivante ; le focus est toujours visible et jamais bloqué.

Cas où la rangée n'apparaît pas ou échoue
- CA15 : Étant donné l'app non reliée à Overseerr, quand l'utilisateur ouvre une bibliothèque, alors aucune rangée
  « Demandes récentes » n'apparaît et l'onglet est identique à aujourd'hui.
- CA16 : Étant donné aucune demande du type de la bibliothèque, alors la rangée n'apparaît pas (pas de rangée vide).
- CA17 : Étant donné Overseerr injoignable (éteint, pas de réseau, session expirée), quand l'utilisateur ouvre une
  bibliothèque, alors les autres rangées s'affichent normalement et dans le même temps qu'aujourd'hui, la rangée
  « Demandes récentes » est simplement absente, sans message d'erreur bloquant.
- CA16b : Étant donné une bibliothèque totalement vide sur le serveur, alors elle garde son message « bibliothèque
  vide » actuel, sans rangée.
- CA18 : Les bibliothèques de musique, photos et autres types n'affichent jamais cette rangée.
- CA19 : Le comportement est le même avec un serveur Plex et un serveur Jellyfin (Overseerr ou Jellyseerr).
- CA20 : Les textes ajoutés existent au moins en français et en anglais.

Recette uniquement sur la Fire TV Stick (192.168.1.173), jamais sur la Freebox (demande de l'utilisateur : « fait tes
tests sur la Firestick et plus sur la Freebox », c'est-à-dire plus du tout sur la Freebox). Pas de serveur Jellyfin chez l'utilisateur : CA19 côté Jellyfin
est vérifié par les tests automatiques.

## Hors périmètre

- La rangée ne distingue pas la 4K : « Disponible » s'affiche aussi quand seule la version 4K est arrivée.
- Limite connue acceptée : une bibliothèque nommée par exemple « Films d'animation » (Pixar, Disney) est prise pour la
  bibliothèque Animés tant qu'aucun animé n'y est arrivé (règle du nom, CA3d).

- Écran complet « Toutes mes demandes » (lien « Voir tout »), filtres, recherche dans les demandes.
- Annuler, modifier ou approuver une demande depuis la rangée.
- Les demandes des autres utilisateurs d'Overseerr.
- La rangée dans l'écran d'accueil général ou dans Explorer (seulement dans les bibliothèques pour l'instant).
- La progression du téléchargement (pourcentage, heure d'arrivée estimée).
- Notifications quand une demande devient disponible.

## Contraintes

- Marque : rien de spécifique ; le nom « Overseerr / Jellyseerr / Seerr » est celui du service tiers, déjà utilisé
  dans l'app.
- TV : navigation complète au D-pad, focus visible, Retour qui ramène sur la bonne affiche, badges lisibles à 3 mètres.
- Fonction absente de Plezy (#2410 refusé) : ajouter le moins possible de modifications aux écrans existants pour
  garder les fusions avec Plezy faciles.
- Aucune différence entre la version GitHub et les futures versions store.
- Google Play : aucune donnée nouvelle collectée ; l'app ne fait que lire les demandes sur le serveur Overseerr de
  l'utilisateur.

## Questions ouvertes

Aucune. Ajouts CA7 à CA7e validés par l'utilisateur le 2026-11-28, après la recette : couleurs dans la rangée
seulement, textes courts, « En cours » en orange, « Refusé » et « Échec » en rouge, ordre de priorité accepté.
Décisions du PO dans la logique de ces réponses (questions de l'architecte app, 2026-11-28) : « Supprimé » passe
devant une ancienne demande approuvée (CA7e) ; « Bloqué » en rouge, pas de badge si l'état est inconnu (CA7f) ;
4K non distinguée dans la rangée (hors périmètre).
Recette T10b (2026-11-28) : Invincible affichait « En cours » dans la rangée et « Demandé » sur Overseerr. Overseerr
n'affiche « Processing » que pendant un téléchargement réel, sinon « Requested ». La rangée suit Overseerr (CA7g),
conformément au retour de l'utilisateur.

Spec validée une première fois par l'utilisateur le 2026-11-28.

Constats de la recette (2026-11-28, Fire TV Stick, Overseerr + Plex) qui motivent ces ajouts :
- titres « Supprimé » dans Overseerr affichés sans badge (CA7c) ;
- « Disponible » et « Demandé » empilés sur des titres disponibles : Overseerr garde la demande « approuvée » après
  l'arrivée du titre, ce qui n'est pas une nouvelle demande (CA7, CA7e) ;
- badges coupés sur la TV : « En attente d'appr… », « Partiellement dis… », « En cours de traite… » (CA7).

Décisions du PO, cohérentes avec la spec validée (2026-11-28, questions de l'architecte app) : rangée dans toutes
les bibliothèques du même type (CA5b) ; « Séries » mixte jamais prise pour Animés (CA3e) ; limite « Films
d'animation » acceptée ; calcul sur les 100 dernières demandes (CA5) ; bibliothèque vide sans rangée (CA16b).

Recette : l'utilisateur utilise **Overseerr** avec **Plex**. Il pourra préparer une partie des cas de test (demande
refusée, en échec, titre supprimé du serveur, demande d'un autre compte, Overseerr coupé) : lui demander au moment de
la recette lesquels ; les autres sont couverts par les tests automatiques.

Réponses de l'utilisateur (2026-11-28) :
- Films d'animation japonais : dans Animés (CA3).
- Série partiellement disponible : fiche du serveur (CA10).
- Demandes refusées ou en échec : affichées, avec badge (CA7b).
- Reconnaissance des animés : par les informations TMDB du titre (CA3b) ; bibliothèque Animés reconnue
  automatiquement, d'abord par les animés arrivés, sinon par son nom (CA3d).

Note pour les architectes : l'app connaît déjà le mot-clé TMDB anime (utilisé au moment de faire une demande pour
choisir les réglages animés). Une demande Overseerr ne porte pas de marque « anime » ; il faut lire la fiche du titre.
