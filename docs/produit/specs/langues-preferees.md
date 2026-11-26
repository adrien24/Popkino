# Langues préférées respectées au lancement d'une vidéo

Statut : validée        Priorité : Must
Dernière mise à jour : 2026-11-26

## Problème

L'utilisateur veut que, par défaut, ses vidéos se lancent **en anglais avec les sous-titres en français**. Ses mots :

- « je voudrais que par défaut la langue des vidéo soit l'anglais avec les sous titres activé en français »
- « actuellement je suis sur ma série The Handmaid's Tale : la servante écarlate et il y a bien un audio anglais mais
  c'est le français qui a été mis de base »
- « j'ai changé la langue, quitté la vidéo puis je suis revenu et la langue est repassée en français »

Ce qu'on a constaté sur la Fire Stick (Popkino 0.1.0, compte Plex) :

- Les réglages sont déjà bons : Paramètres > Préférences du compte indique Langue audio préférée = English,
  « Choisir l'audio par langue » = activé, Langue de sous-titres préférée = French, « Activer les sous-titres » =
  Toujours activé.
- Malgré cela, l'épisode démarre en français. Raison : le serveur Plex se souvient, pour chaque fichier, de la dernière
  piste utilisée (par exemple un épisode déjà lancé en français, dans Popkino ou dans une autre app Plex). Aujourd'hui,
  ce souvenir du serveur passe **avant** les langues préférées du compte.
- Quand l'utilisateur change la piste pendant la lecture, ce choix n'est pas gardé (l'option « Mémoriser les pistes
  choisies pour chaque série ou film » de Paramètres > Lecture vidéo est désactivée) : au retour, le français revient.
- Défaut annexe : sous l'interrupteur « Choisir l'audio par langue », **activé**, le texte affiché est « Désactivé : la
  piste audio marquée par défaut dans le fichier est conservée », ce qui fait croire que l'option est coupée.

Existant chez Plezy (upstream) :

- [#2649](https://github.com/edde746/plezy/issues/2649) (ouvert) : « Choisir l'audio par langue » sans effet sur
  Jellyfin, une vidéo anglais + allemand démarre en allemand. Même symptôme que le nôtre.
- [#1615](https://github.com/edde746/plezy/issues/1615) (fermé) : le choix de piste est perdu en quittant puis en
  relançant un épisode. Réponse du mainteneur : comportement voulu, les épisodes lancés à la main utilisent les
  pistes enregistrées sur le serveur puis les langues préférées ; il reconnaît que le libellé de l'option
  « Mémoriser… » est trompeur.
- [#1993](https://github.com/edde746/plezy/issues/1993) (fermé) : demande d'un réglage de langue par défaut ; refusé
  car les réglages du compte serveur suffisent selon le mainteneur.
- [#2531](https://github.com/edde746/plezy/issues/2531) et [#2382](https://github.com/edde746/plezy/issues/2382)
  (fermés) : mémoire des pistes par série gardée dans l'app, « pas prévue » chez Plezy.

Plezy ne corrigera donc probablement pas ce point : c'est un vrai plus pour Popkino.

## Objectif

Quand l'utilisateur lance un film ou un épisode depuis n'importe quel écran, la vidéo démarre dans sa langue audio
préférée (ici l'anglais) avec les sous-titres dans sa langue préférée (ici le français), dès que le fichier contient ces
pistes, sans qu'il ait à toucher la télécommande. Un choix fait à la main n'est gardé d'un lancement à l'autre que si
l'utilisateur a activé « Mémoriser les pistes choisies pour chaque série ou film ».

## Parcours utilisateur

1. Sur la fiche d'une série (ou sur l'accueil, « Reprendre »), l'utilisateur sélectionne un épisode et appuie sur OK.
2. Le lecteur s'ouvre. La vidéo démarre directement avec l'audio anglais et les sous-titres français.
3. S'il ouvre le menu des pistes (audio / sous-titres), la piste anglaise et les sous-titres français y sont marqués
   comme sélectionnés.
4. S'il change de piste à la main, la vidéo bascule immédiatement. Au prochain lancement : si « Mémoriser les pistes
   choisies » est désactivé, l'anglais sous-titré français revient ; s'il est activé, son dernier choix pour ce fichier
   est repris.
5. Il appuie sur Retour, revient à la fiche, relance le même épisode ou un autre : les pistes suivent la même règle.

## Critères d'acceptation

Préparation commune : compte réglé comme sur la Fire Stick (audio préféré English, « Choisir l'audio par langue »
activé, sous-titres préférés French, « Activer les sous-titres » = Toujours activé). Fichier de test : un épisode avec
audio français + anglais et sous-titres français, que le serveur a déjà retenu en audio français (par exemple lancé une
fois en français depuis une autre app Plex ou depuis Plex Web).

- CA1 : Étant donné ce fichier sur Plex et « Mémoriser les pistes » désactivé, quand l'utilisateur le lance depuis la
  fiche de la série, alors la lecture démarre en audio anglais avec les sous-titres français, sans action de sa part.
- CA2 : Étant donné la même situation, quand l'utilisateur ouvre le menu audio, alors la piste anglaise est celle
  indiquée comme sélectionnée (et les sous-titres français dans le menu sous-titres).
- CA3 : Étant donné le même fichier sur un serveur **Jellyfin** avec des préférences équivalentes dans le compte
  Jellyfin, quand l'utilisateur le lance, alors il démarre en anglais sous-titré français.
- CA4 : Étant donné « Mémoriser les pistes » **désactivé** et un épisode lancé en anglais, quand l'utilisateur passe
  l'audio en français à la main, quitte avec Retour puis relance le même épisode, alors il redémarre en anglais
  sous-titré français.
- CA4bis : Étant donné « Mémoriser les pistes » **activé** et un épisode lancé en anglais, quand l'utilisateur passe
  l'audio en français à la main, quitte avec Retour puis relance le même épisode, alors il redémarre en français (son
  dernier choix pour ce fichier). Les autres épisodes qu'il n'a pas modifiés à la main démarrent toujours en anglais
  sous-titré français.
- CA4ter : Étant donné « Mémoriser les pistes » **activé**, l'épisode 1 passé en français à la main et l'épisode 2
  enchaîné automatiquement en français, quand l'utilisateur quitte l'épisode 2 puis le relance depuis la fiche de la
  série, alors l'épisode 2 reprend en français. Avec « Mémoriser » désactivé, il reprend en anglais sous-titré
  français (CA4).
- CA5 : Étant donné un épisode qui se termine et enchaîne automatiquement sur le suivant (ou « Épisode suivant »),
  quand l'utilisateur avait changé de piste à la main, alors l'épisode suivant garde ce choix, comme aujourd'hui.
- CA6 : Étant donné un fichier **sans piste anglaise** (par exemple un film uniquement en français), quand
  l'utilisateur le lance, alors la lecture démarre sur la piste audio marquée par défaut dans le fichier, sans message
  d'erreur. Si cette piste est en français (la langue des sous-titres préférés), aucun sous-titre complet n'est
  affiché (seule une piste française « forcée » peut l'être, voir CA12) ; si
  elle est dans une autre langue (par exemple allemand), les sous-titres français sont affichés s'ils existent.
- CA7 : Étant donné un fichier avec audio anglais mais **sans sous-titres français**, quand l'utilisateur le lance,
  alors la lecture démarre en anglais, sans sous-titres d'une autre langue imposés, sans message d'erreur.
- CA8 : Étant donné « Choisir l'audio par langue » **désactivé**, quand l'utilisateur lance le fichier de test, alors le
  comportement est celui d'aujourd'hui (pas de changement pour qui n'a pas choisi de langue).
- CA9 : Étant donné l'écran Paramètres > Préférences du compte, quand « Choisir l'audio par langue » est activé, alors
  le texte sous l'interrupteur décrit ce que fait l'option activée (ou décrit les deux états sans ambiguïté) ; il
  n'affiche plus « Désactivé : … » alors que l'interrupteur est activé.
- CA10 : Étant donné un serveur injoignable au moment d'enregistrer un choix de piste, quand l'utilisateur change de
  piste, alors la lecture continue normalement avec la nouvelle piste, sans message bloquant.
- CA11 : Tous les parcours ci-dessus se font uniquement à la télécommande, le focus reste visible dans les menus de
  pistes et la touche Retour referme le menu puis quitte le lecteur.

- CA12 : Étant donné un fichier en audio français qui contient une piste de sous-titres français « forcés » (elle
  ne traduit que les passages dans une autre langue : panneaux, dialogues étrangers), quand l'utilisateur le lance,
  alors cette piste forcée est affichée, et aucune piste de sous-titres français complète ne l'est. Sans piste forcée,
  aucun sous-titre n'est affiché.

## Hors périmètre

- Réglages de langue par bibliothèque ou par série (demandes upstream #2792 et #2382).
- Langue réglée sur une série directement dans Plex (par exemple un anime réglé en japonais dans Plex Web) : elle
  n'est pas prise en compte dans cette version, la langue du compte passe avant (idée `langue-serie-plex` au backlog).
- Choix fin du type de sous-titres (forcés, SDH, image ou texte) au-delà de la langue.
- Recherche et téléchargement de sous-titres en ligne.
- Nouvel écran de réglages de langues propre à Popkino : on s'appuie sur les préférences déjà présentes dans
  Paramètres > Préférences du compte.

## Contraintes

- `regles-fork` : changement du comportement de lecture partagé avec Plezy ; garder la modification petite et isolée
  pour pouvoir continuer à récupérer les nouveautés de Plezy.
- TV : tout au D-pad, focus visible, Retour conforme.
- Même comportement dans la version GitHub et la future version Play (aucune contrainte store particulière).
- Plex et Jellyfin.
- Le texte corrigé (CA9) doit exister au moins en français et en anglais (cf. backlog `traductions-fork`).

## Questions ouvertes

Aucune.

Décisions de l'utilisateur (2026-11-26) :
- Choix à la main : gardé d'un lancement à l'autre seulement si « Mémoriser les pistes choisies » est activé ; sinon la
  langue préférée revient à chaque lancement.
- Pas de sous-titres quand l'audio joué est déjà dans la langue des sous-titres préférés (français).
- Priorité Must, juste après `nouvelle-identite`.

Précisions après validation (2026-11-26, questions des architectes) :
- Sous-titres « forcés » : tranché par le PO dans l'esprit de la décision de l'utilisateur (pas de sous-titres pour
  ce qu'il comprend déjà, mais traduction des passages étrangers) : la piste française forcée est affichée (CA12).
- Langue réglée sur une série dans Plex : tranché par le PO, ignorée dans cette version (déjà hors périmètre :
  réglages par série) ; ajoutée au backlog en Could.
- Choix reporté à l'épisode suivant (décision de l'utilisateur) : quand « Mémoriser » est activé, un choix reporté
  automatiquement sur l'épisode suivant (CA5) compte comme un choix fait à la main sur cet épisode (CA4ter).

## Recette (2026-11-26, Fire Stick, APK 0.1.1 de la branche, compte Plex)

- CA1 : OK au menu (S3E8, serveur sur le français → English 2.0 + French Full) ; écoute par l'utilisateur à faire.
- CA2 : OK.
- CA3 : OK par les tests seulement (pas de serveur Jellyfin chez l'utilisateur).
- CA4 : OK. CA4bis : OK (S3E8 relancé en français, S3E10 en anglais). CA4ter : OK (S3E9 relancé en français).
- CA5 : OK (épisode suivant depuis S3E8 en français → S3E9 en français).
- CA6 : OK (Jack in the Box : Résurrection, français seul → pas de sous-titres ; My Hero Academia : Heroes Rising,
  japonais seul → sous-titres français).
- CA7 : OK (Green Lantern → anglais, pas de sous-titres).
- CA8 : OK (option coupée → piste retenue par le serveur, comme avant).
- CA9 : OK.
- CA10 : OK par les tests (pas de coupure réseau sur la TV).
- CA11 : OK. Retour ferme le menu des pistes ; il faut 3 appuis pour sortir (menu, commandes, lecteur) : comportement
  habituel du lecteur, inchangé par cette fonctionnalité.
- CA12 : OK (Prodigieuses → français + forcé français).
- En plus : même résultat en lançant par un lien `popkino://play`.

Constats hors critères (ajoutés au backlog) : choix entre plusieurs pistes de la même langue (stéréo prise avant la
5.1), sous-titres mal étiquetés dans le fichier, mode des sous-titres modifié quand on coupe « Choisir l'audio par
langue ». À noter : Plex propose déjà un mode de sous-titres « Avec l'audio en langue étrangère », qui va dans le même
sens que la règle de CA6.
