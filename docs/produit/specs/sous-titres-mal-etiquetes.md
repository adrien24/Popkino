# Reconnaître les sous-titres mal étiquetés

Statut : validée        Priorité : Could
Dernière mise à jour : 2026-11-26

## Problème

Certains fichiers ont des pistes de sous-titres dont la **langue indiquée** est fausse, alors que leur **titre** est
clair. L'app se fie à la langue indiquée, donc ne trouve pas les sous-titres français et n'en affiche aucun.
L'utilisateur veut que ces sous-titres soient reconnus.

Constaté pendant la recette de `langues-preferees` : Green Lantern a des sous-titres titrés « French Complet » et
« French Forced » mais indiqués « anglais » côté Plex, plus un vrai sous-titre anglais. Avec l'audio anglais et les
sous-titres préférés en français, aucun sous-titre ne s'affiche.

Upstream : [#1443](https://github.com/edde746/plezy/issues/1443) (fermé) traite de la distinction « French » /
« French Forced » de même langue, pas des langues mal indiquées. Rien d'autre trouvé.

## Objectif

Quand le titre d'une piste de sous-titres nomme clairement une langue, l'app la traite comme une piste de cette langue
pour le choix automatique, même si la langue indiquée dans le fichier est autre.

## Parcours utilisateur

1. L'utilisateur lance Green Lantern (audio anglais).
2. La vidéo démarre avec les sous-titres « French Complet ».
3. Dans le menu « Audio et sous-titres », « French Complet » est cochée.

## Critères d'acceptation

Préparation : compte avec audio English, sous-titres French, « Toujours activé ».

- CA1 : Étant donné Green Lantern (« French Complet » et « French Forced » indiqués anglais), quand l'utilisateur le
  lance en anglais, alors « French Complet » est affichée.
- CA2 : Étant donné le même film lu en audio français (choisi à la main), alors « French Forced » est affichée, et pas
  « French Complet » (règle CA12 de `langues-preferees`).
- CA3 : Étant donné le vrai sous-titre anglais du même film, alors il n'est jamais pris pour du français.
- CA4 : Les titres reconnus couvrent au moins, sans tenir compte des majuscules : « French », « Français », « FR »,
  « FRE », « FRA », « VF », « VFF », « VFQ », « VOSTFR », et l'équivalent pour l'anglais (« English », « Anglais »,
  « ENG », « EN », « VO » n'est pas une langue et ne compte pas).
- CA5 : Étant donné une piste dont la langue indiquée et le titre concordent, alors rien ne change.
- CA6 : Étant donné une piste sans titre ou avec un titre qui ne nomme pas de langue, alors seule la langue indiquée
  compte, comme aujourd'hui.
- CA7 : Étant donné un fichier qui a à la fois une vraie piste française bien étiquetée et une piste titrée « French »
  mal étiquetée, alors la piste bien étiquetée est préférée.
- CA8 : Le nom affiché dans le menu des pistes ne change pas (on n'invente pas de libellé).
- CA9 : Plex et Jellyfin (Jellyfin vérifié par les tests).

## Hors périmètre

- Corriger la langue des pistes sur le serveur Plex.
- Deviner la langue en lisant le contenu des sous-titres.
- Reconnaître d'autres langues que le français et l'anglais dans les titres (idée `titres-autres-langues` au
  backlog).
- Même chose pour les pistes audio (à proposer si l'utilisateur le constate).

## Contraintes

- `regles-fork` : modification petite et isolée.
- Même comportement version GitHub et version Play.

## Questions ouvertes

Aucune.

Décisions de l'utilisateur (2026-11-26) :
- Quand le titre nomme clairement une langue, il l'emporte sur la langue indiquée dans le fichier (y compris quand
  celle-ci est renseignée, comme sur Green Lantern).
- Priorité Could, après `meilleure-piste-audio`.

## Précisions après validation (2026-11-26)

- Seuls le français et l'anglais sont reconnus dans les titres pour cette version (tranché par le PO : ce sont les
  langues de l'utilisateur ; les autres langues sont une idée du backlog, utile avant la publication sur les stores).

## Recette (2026-11-27, Fire Stick, APK 0.1.3, compte Plex)

- CA1 : OK sur la TV (Green Lantern, audio English 2.0 → « French Complet » cochée ; avant : aucun sous-titre).
- CA2 : OK par les tests (`preferred_languages_flow_test`, Green Lantern en Plex et Jellyfin) ; pas refait sur la TV
  (il faudrait démarrer en audio français).
- CA3, CA4, CA5, CA6, CA7 : OK par les tests (groupe « mislabeled subtitles » et `subtitle_title_language_test`).
- CA8 : OK sur la TV (libellés inchangés : « French Complet / SRT », « French Forced / SRT », « English / Anglais · SRT »).
- CA9 : OK par les tests (Plex et Jellyfin ; pas de serveur Jellyfin chez l'utilisateur).
- Précision de conception sans effet visible : une piste que le serveur ne décrit pas garde sa langue indiquée.

Reste avant « livré » : commit et fusion validés par l'utilisateur, version publiée.
