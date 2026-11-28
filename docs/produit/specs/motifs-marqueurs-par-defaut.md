# Passer le récapitulatif, et reconnaître plus de noms de chapitres pour l'intro et le générique

Statut : validée        Priorité : Should
Dernière mise à jour : 2026-11-28

## Problème

Les mots de l'utilisateur : « j'aimerais rajouter par défaut des motifs de marqueur d'introduction et des motifs de
marqueur générique. Par exemple pour la série que je regarde en ce moment, The Handmaid's Tale, je ne peux pas passer
l'intro car c'est un recap. »

Situation : sur la TV, pendant la lecture d'un épisode de The Handmaid's Tale (La Servante écarlate, saison 3, serveur
Plex), l'épisode commence par un récapitulatif (« Previously on The Handmaid's Tale… »). Aucun bouton « Passer l'intro »
n'apparaît : il faut avancer à la main avec la télécommande.

Ce que fait l'app aujourd'hui (constaté dans le code hérité de Plezy) :

- Le bouton « Passer l'intro » ou « Passer le générique » s'affiche quand le serveur fournit un **marqueur** d'intro ou
  de générique. Plex ne fournit que ces deux types (avec Plex Pass et l'analyse activée sur la bibliothèque) ; il ne
  connaît **pas** les récapitulatifs. Jellyfin connaît un type « Récap », mais l'app l'ignore aujourd'hui.
- À défaut de marqueur, l'app regarde les **noms des chapitres** du fichier vidéo. Elle reconnaît les mots anglais
  « Intro », « Introduction », « Opening », « OP » pour l'intro et « Credits », « Outro », « Ending », « ED » pour le
  générique. Elle ne reconnaît ni le français (« Générique »), ni aucun mot de récapitulatif (« Recap »,
  « Previously », « Résumé », « Précédemment »).
- Paramètres > Lecture contient deux réglages « Motif du marqueur d'introduction » et « Motif du marqueur de
  générique », qu'on ne peut modifier qu'en tapant une formule technique (expression régulière) au clavier de la
  télécommande : inutilisable en pratique sur TV.

Constaté sur la Fire TV (v0.2.0, S3E8) : l'épisode a des chapitres nommés en anglais, « Recap » à 0:00, « Scene 1 »
à 1:19 et « Credits » à 44:42. Le récapitulatif dure donc 1 min 19 et n'est suivi d'aucun chapitre d'intro. Reconnaître
« Recap » dans les noms de chapitres suffit à régler ce cas. Les éventuels marqueurs Plex de ces épisodes n'ont pas pu
être consultés.

Upstream (Plezy) :
- [#3051](https://github.com/edde746/plezy/issues/3051) « Support Skip Recap for Jellyfin media segments » : ouvert,
  sans réponse. Même besoin, côté Jellyfin.
- [#459](https://github.com/edde746/plezy/issues/459) (fermé, réalisé) : la détection par noms de chapitres vient de
  là ; un commentaire y cite déjà le cas des récapitulatifs.
- [#2151](https://github.com/edde746/plezy/issues/2151), [#2235](https://github.com/edde746/plezy/issues/2235),
  [#2734](https://github.com/edde746/plezy/issues/2734) (fermés) : faux positifs corrigés (chapitre « Opening Credits »
  de 10 minutes dans un film, chapitre « Closing Day » au milieu de Shining). Nos nouveaux mots ne doivent pas les
  réintroduire.
- [#389](https://github.com/edde746/plezy/issues/389) (fermé, refusé) : base externe de minutages (TheIntroDB),
  refusée pour des raisons de fiabilité et de vie privée.

## Objectif

Quand un épisode commence par un récapitulatif repérable (marqueur « Récap » de Jellyfin, ou chapitre nommé « Recap »,
« Previously on… », « Résumé »…), le bouton habituel « Passer l'intro » permet de le passer en une pression sur OK (et de passer aussi l'intro qui le
suit immédiatement). Et l'app reconnaît, sans aucun
réglage, les noms de chapitres d'intro et de générique courants en anglais et en français.

## Parcours utilisateur

1. L'utilisateur lance un épisode depuis sa fiche (bouton Lire) ou depuis « Continuer à regarder ».
2. La lecture démarre au début de l'épisode, pendant le récapitulatif. Le bouton de saut apparaît en bas à droite,
   C'est le bouton habituel « Passer l'intro », au même endroit, **avec le focus dessus**.
3. L'utilisateur appuie sur OK : la lecture reprend juste après le récapitulatif. Si une intro (générique de début)
   enchaîne directement après le récapitulatif, ce même OK passe les deux : la lecture reprend après l'intro.
5. S'il n'appuie sur rien, le bouton se comporte exactement comme « Passer l'intro » aujourd'hui : en mode « Bouton »,
   il s'efface au bout de 7 secondes ; une pression sur la télécommande qui affiche le bandeau du lecteur le fait
   revenir tant que le récapitulatif n'est pas fini.
6. En fin d'épisode, si un chapitre « Générique » ou « Générique de fin » existe, le bouton « Passer le générique » (ou
   « Épisode suivant ») apparaît comme aujourd'hui avec les chapitres « Credits ».

## Critères d'acceptation

Récapitulatif :

- CA1 : Étant donné un épisode **Plex** sans marqueur d'intro dont le premier chapitre s'appelle « Recap » et dure
  1 min 30, quand la lecture démarre, alors le bouton « Passer l'intro » est affiché avec le focus, et OK reprend la lecture à
  la fin de ce chapitre (à 2 secondes près).
- CA2 : Même chose pour des chapitres nommés (majuscules ou minuscules indifférentes) : « Previously », « Previously
  on The Handmaid's Tale », « Recap », « Récap », « Récapitulatif », « Résumé », « Précédemment », « Précédemment
  dans… », « Last time on… ».
- CA3 : Étant donné un épisode **Jellyfin** qui a un segment de type « Récap » (Recap), quand la lecture atteint ce
  segment, alors le bouton « Passer l'intro » apparaît et OK le passe.
- CA4 : Étant donné le réglage « Passer l'intro » (Paramètres > Lecture) réglé sur « Désactivé », « Bouton » ou
  « Automatique », alors le récapitulatif suit ce même réglage (pas de bouton / bouton / saut automatique avec le
  compte à rebours habituel). Aucun nouveau réglage n'est ajouté et aucun nouveau libellé n'apparaît.
- CA4b : Étant donné un récapitulatif suivi d'une intro qui commence moins de 5 secondes après sa fin (repères
  serveur ou chapitres, Plex ou Jellyfin), quand l'utilisateur appuie sur OK sur « Passer l'intro » pendant le
  récapitulatif, alors la lecture reprend à la fin de l'intro, en une seule pression. Si l'intro commence plus de
  5 secondes après, OK s'arrête à la fin du récapitulatif et « Passer l'intro » réapparaît au début de l'intro.
- CA5 : Étant donné un chapitre nommé « Recap » qui dure plus de 5 minutes, alors aucun bouton n'est proposé
  pour ce chapitre (ce n'est vraisemblablement pas un récapitulatif).
- CA6 : Étant donné un chapitre nommé « Résumé » ou « Recap » qui commence après le premier quart de l'épisode, alors
  aucun bouton n'est proposé pour ce chapitre (un récapitulatif est en début d'épisode).

Intro et générique par défaut :

- CA7 : Étant donné un épisode sans marqueur serveur dont un chapitre de début s'appelle « Générique », « Générique de
  début » ou « Ouverture », et dure moins de 3 minutes, quand la lecture l'atteint, alors « Passer l'intro » apparaît.
- CA8 : Étant donné un épisode ou un film sans marqueur serveur dont un chapitre du dernier quart s'appelle
  « Générique », « Générique de fin » ou « Fin », alors « Passer le générique » (ou « Épisode suivant » s'il va
  jusqu'à la fin) apparaît.
- CA9 : Les mots déjà reconnus aujourd'hui (Intro, Introduction, Opening, OP, Credits, Outro, Ending, ED) le sont
  toujours.
- CA10 : Les protections actuelles restent : un chapitre d'intro de plus de 3 minutes n'est pas proposé, un chapitre
  de générique situé avant le dernier quart n'est pas proposé (Shining, « Closing Day », reste sans bouton).

Ce qui ne doit pas changer :

- CA11 : Étant donné un épisode Plex qui a un vrai marqueur d'intro fourni par le serveur, alors le bouton « Passer
  l'intro » apparaît au même moment qu'avant cette fonctionnalité.
- CA12 : Étant donné un utilisateur qui avait déjà remplacé un motif dans Paramètres > Lecture, alors son motif est
  conservé après la mise à jour de l'app. Pour ce type (intro ou générique), son motif décide seul : les mots français ajoutés ne
  s'appliquent pas. Le récapitulatif reste reconnu dans tous les cas.
- CA12b : La formule affichée sous « Motif du marqueur d'introduction » et « Motif du marqueur de générique » reste
  celle de Plezy ; elle ne liste pas les mots ajoutés par cette fonctionnalité.
- CA13 : Étant donné un épisode sans aucun chapitre ni marqueur, alors aucun bouton n'apparaît et la lecture se passe
  comme avant (pas de message d'erreur).
- CA14 : Le bouton, pendant un récapitulatif, est utilisable à la télécommande : focus visible, OK le déclenche, Retour se
  comporte comme avec le bouton « Passer l'intro » actuel.

Cas réel :

- CA15 : Étant donné The Handmaid's Tale S3E8 sur le serveur Plex de l'utilisateur (chapitres « Recap » à 0:00,
  « Scene 1 » à 1:19, « Credits » à 44:42), quand la lecture démarre sur la TV, alors « Passer l'intro »
  apparaît avec le focus, et OK reprend la lecture à 1:19 (à 2 secondes près). Même vérification sur S3E9 et S3E10.

## Hors périmètre

- Détecter un récapitulatif **sans** chapitre ni marqueur (par analyse de l'image ou du son) : c'est le travail du
  serveur, Plex ne le fait pas pour les récapitulatifs.
- Interroger une base de minutages sur Internet (type TheIntroDB) : refusé par Plezy (#389), et cela enverrait à un
  tiers ce que l'utilisateur regarde.
- Remplacer les réglages « Motif du marqueur… » par un écran simple (liste de mots à cocher) : idée à part si besoin.
- Les autres segments Jellyfin (publicités, aperçu de l'épisode suivant, #3136).

## Contraintes

- TV : bouton au même endroit et avec le même comportement de focus que « Passer l'intro » ; libellé lisible à
  3 mètres ; traduit au moins en français et en anglais (les autres langues relèvent de `traductions-fork`).
- Plex **et** Jellyfin.
- Compatibilité upstream : changement utile à tous les utilisateurs de Plezy, candidat à une proposition (PR) vers
  l'upstream (#3051 est ouvert). Garder la modification petite pour faciliter les fusions.
- Aucune règle de marque ou Google Play en jeu ; rien n'est envoyé hors du serveur de l'utilisateur.
- Identique dans la version GitHub et les futures versions store.

## Questions ouvertes

Aucune. Décisions de l'utilisateur (2026-11-28) : bouton habituel « Passer l'intro » pour le récapitulatif ; un seul
OK passe récapitulatif et intro enchaînés ; segments « Récap » de Jellyfin inclus.
Précisions du PO après le plan technique (2026-11-28), conformes à la spec validée (bouton « comme aujourd'hui »,
réglages « Motif… » hors périmètre) : disparition après 7 s héritée, motif personnalisé prioritaire, formule affichée
inchangée.
