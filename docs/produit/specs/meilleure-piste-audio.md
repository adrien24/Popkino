# Choisir la meilleure piste audio dans la langue préférée

Statut : validée        Priorité : Should
Dernière mise à jour : 2026-11-26

## Problème

Depuis `langues-preferees`, la vidéo démarre bien dans la langue audio préférée. Mais quand le fichier contient
plusieurs pistes dans cette langue, l'app prend la **première**, souvent la stéréo, alors qu'une piste 5.1 existe.
L'utilisateur : « on veut choisir la piste 5.1 plutôt que la stéréo ».

Constaté pendant la recette de `langues-preferees` (Fire Stick, compte Plex) :
- The Handmaid's Tale S3E8 : English 2.0 AAC Stéréo, French 2.0 AAC Stéréo, English « ENG VO - EAC3 DDP 5.1 »,
  French « FRE VFF - EAC3 DDP 5.1 ». L'app démarre sur English 2.0.
- Green Lantern : English 2.0 AAC, French 2.0 AAC, English DTS 5.1, French VFF AC3 5.1. L'app démarre sur English 2.0.

L'app a déjà un réglage Paramètres > Audio > « Canaux audio » (D'origine / Jusqu'à 5.1 / Stéréo) et
« Transmission audio directe ».

Upstream : pas de demande trouvée sur ce point (recherche « audio track channels surround prefer »).

L'utilisateur écoute **sur les haut-parleurs de la télévision seulement** (réponse du 2026-11-26). Sur une sortie
stéréo, une piste 5.1 est réduite à deux canaux à la volée, ce qui donne souvent des voix plus faibles que la piste
stéréo prévue pour ça. Pour lui, la bonne piste est donc la stéréo ; pour quelqu'un qui a une barre de son ou un home
cinéma (futurs utilisateurs des stores, ou lui plus tard), c'est la 5.1.

## Objectif

Parmi les pistes dans la langue préférée, la vidéo démarre sur celle qui convient à l'installation audio : la stéréo
quand le son ne sort qu'en stéréo (télévision seule, ou « Canaux audio » = Stéréo), la piste avec le plus de canaux
(5.1) quand l'installation sait les restituer, sans réglage à faire.

## Parcours utilisateur

1. L'utilisateur lance un épisode depuis la fiche de la série (OK sur l'épisode).
2. La vidéo démarre en anglais, sans action de sa part : en stéréo sur sa télévision seule, en 5.1 sur une
   installation qui restitue la 5.1.
3. Dans le menu « Audio et sous-titres », la piste correspondante est cochée (« English 2.0 » sur sa télévision,
   « ENG VO - EAC3 DDP 5.1 » avec une barre de son 5.1 ou un home cinéma).
4. S'il choisit une autre piste à la main, les règles de `langues-preferees` s'appliquent (mémorisation ou non).

## Critères d'acceptation

Préparation : compte avec audio préféré English, « Choisir l'audio par langue » activé, « Canaux audio » = D'origine.

- CA1 : Étant donné la Fire Stick branchée sur une télévision sans barre de son ni ampli, quand l'utilisateur lance
  S3E8 (English 2.0 et English 5.1), alors la piste English 2.0 est cochée dans le menu audio.
- CA2 : Étant donné une installation qui restitue la 5.1 (barre de son 5.1 ou home cinéma), quand l'utilisateur lance
  S3E8, alors English 5.1 est cochée ; avec Green Lantern, English DTS 5.1 est cochée et le son sort (pas de silence).
- CA3 : Étant donné « Canaux audio » = Stéréo, quelle que soit l'installation, alors la piste English 2.0 est choisie.
- CA3bis : Étant donné une installation dont l'app ne peut pas savoir ce qu'elle restitue, alors la piste choisie est
  la même qu'aujourd'hui (aucune régression).
- CA4 : Étant donné un fichier avec une seule piste anglaise, quand l'utilisateur le lance, alors cette piste est
  choisie, comme aujourd'hui.
- CA5 : Étant donné deux pistes anglaises avec le même nombre de canaux, quand l'utilisateur lance le fichier, alors
  la piste choisie est la même qu'aujourd'hui (la première, ou celle marquée par défaut).
- CA6 : Étant donné un choix fait à la main et « Mémoriser les pistes » activé, quand l'utilisateur relance, alors son
  choix est repris, même si c'est la stéréo (règle de `langues-preferees` inchangée).
- CA7 : Étant donné un épisode qui enchaîne sur le suivant, quand le précédent était en 5.1 choisie automatiquement,
  alors le suivant démarre aussi en 5.1 s'il en a une (même règle pour la stéréo).
- CA8 : Étant donné « Choisir l'audio par langue » désactivé, alors rien ne change par rapport à aujourd'hui.
- CA9 : Le choix de la 5.1 ne fait pas perdre la lecture directe de la vidéo : si la vidéo démarrait sans conversion
  par le serveur avec la stéréo, elle démarre aussi sans conversion vidéo avec la 5.1.
- CA10 : Plex et Jellyfin (Jellyfin vérifié par les tests, l'utilisateur n'a pas de serveur Jellyfin).

## Hors périmètre

- Préférer un format précis (Atmos, TrueHD, DTS:X) à un autre à nombre de canaux égal.
- Préférer la 7.1 à la 5.1 de façon particulière (la règle « le plus de canaux » s'applique telle quelle).
- Nouvel écran de réglages : on réutilise « Canaux audio ».

## Contraintes

- `regles-fork` : modification petite et isolée du choix de piste, comme pour `langues-preferees`.
- TV : rien à faire à la télécommande, le menu des pistes reste juste.
- Même comportement version GitHub et version Play.

## Questions ouvertes

Aucune.

Décisions de l'utilisateur (2026-11-26) : il écoute sur la télévision seule ; la stéréo est choisie automatiquement
quand le son ne sort qu'en stéréo, la 5.1 quand une barre de son ou un home cinéma la restitue. Spec validée.

Note pour les architectes : si l'app ne peut pas savoir de façon fiable ce que restitue l'installation, le dire ; le
repli serait « Canaux audio » (D'origine → 5.1, Stéréo → stéréo), et l'utilisateur mettrait « Stéréo ».

## Précisions après validation (2026-11-26, questions des architectes)

Constat mesuré sur la Fire Stick de l'utilisateur (TV LG sans barre de son) : l'app **ne peut pas savoir** si le son
ne sort qu'en stéréo (la TV annonce 8 canaux, Dolby et DTS ; une barre de son branchée à la TV lui ressemble). La
détection automatique de l'objectif est donc remplacée par le réglage existant Paramètres > Audio > « Canaux audio » :

- « D'origine » (valeur par défaut) : choix d'aujourd'hui, inchangé. Sur S3E8 et Green Lantern, cela donne English
  2.0 : la décision de l'utilisateur (stéréo sur sa télévision seule) est tenue sans qu'il règle quoi que ce soit.
- « Jusqu'à 5.1 » : la piste de la langue préférée qui a le plus de canaux (5.1).
- « Stéréo » : la piste stéréo de la langue préférée.

Critères ajustés en conséquence :
- CA1 : télévision seule, « Canaux audio » = D'origine → S3E8 démarre en English 2.0.
- CA2 : « Canaux audio » = Jusqu'à 5.1 → S3E8 démarre en English 5.1 ; Green Lantern en English DTS 5.1, avec du son
  sur une installation qui restitue le DTS.
- CA3 : « Canaux audio » = Stéréo → toujours la stéréo.
- CA3bis : « Canaux audio » = D'origine → même piste qu'aujourd'hui, quelle que soit l'installation.
- CA11 (nouveau) : les pistes de commentaire et d'audiodescription ne sont jamais choisies par la règle des canaux,
  même si elles ont plus de canaux.
- CA12 (nouveau) : les textes des choix de « Canaux audio » disent qu'ils décident aussi de la piste choisie au
  lancement (au moins en français et en anglais).

Tranché par le PO :
- « D'origine » garde le choix actuel : c'est ce qui donne la stéréo à l'utilisateur sans réglage.
- Commentaires et audiodescription exclus (personne ne les veut par défaut).
- Pas de message supplémentaire sur le silence : le texte de « Transmission audio directe » dit déjà « Désactivez cette
  option en l'absence de son ».
- Texte de « Canaux audio » précisé (CA12), sinon la fonction serait invisible.
- Conséquence acceptée : avec une barre de son ou un home cinéma, il faut choisir « Jusqu'à 5.1 » une fois pour avoir
  la 5.1 ; ce n'est plus automatique.
