# Proposition plateforme — sous-titres-mal-etiquetes

Auteur : architecte-plateforme · 2026-11-26 · Phase 1 (rédigée sans lire la proposition app)
Spec : `docs/produit/specs/sous-titres-mal-etiquetes.md`

## Compréhension de la spec

Quand le **titre** d'une piste de sous-titres nomme clairement une langue (« French Complet »), il l'emporte sur la
langue déclarée dans le fichier pour le choix automatique. Une piste bien étiquetée reste préférée (CA7), et le libellé
affiché ne change pas (CA8). Mon périmètre est mince : c'est de la logique Dart pure. Je ne traite que la provenance
des titres côté serveur et lecteur, les effets de bord serveur et la recette.

## Existant

Le titre d'une piste a trois origines possibles. Toutes ne portent pas le titre écrit par l'auteur du fichier :
- **mpv, piste intégrée au fichier** : `SubtitleTrack.title` est le nom de piste du conteneur (le `Name` d'un MKV).
  C'est le vrai titre de l'auteur, celui qui contient « French Complet ».
- **Plex** : `title` est le titre de la piste ; `displayTitle` et `extendedDisplayTitle` sont **calculés par le
  serveur à partir de la langue déclarée** (« English (SRT) », « French Complet (English SRT) »). `plex_mappers.dart`
  l.131 remplit `displayTitle` avec `displayTitle ?? extendedDisplayTitle`.
- **Jellyfin** : `Title`, et `DisplayTitle`, calculé de la même façon.

Point d'attention : les descripteurs de piste fabriqués à partir des lignes du serveur se rabattent sur
`displayTitle`, puis sur la langue, quand il n'y a pas de titre (`playback_subtitle_resolver.dart` l.348 et l.417 :
`title: track.title ?? track.displayTitle ?? track.language`). Ce texte de repli **reflète la langue déclarée**, pas
le titre de l'auteur.

## Approche proposée

- **Aucune modification Android, native, Gradle ou CI.** Aucun impact Google Play ni marque.
- **Exigence sur la source du titre.** La reconnaissance doit lire le titre de l'auteur : le `title` de mpv, ou le
  `title` de la ligne serveur. Jamais `displayTitle`, `extendedDisplayTitle`, ni le `title` d'un descripteur rempli par
  repli.
  - Ce repli est sans danger pour CA6 tant qu'il concorde avec la langue déclarée.
  - Mais un `extendedDisplayTitle` du type « French Complet (English SRT) » contient deux langues. S'il était lu, il
    rendrait la reconnaissance ambiguë et violerait CA3 (« le vrai anglais n'est jamais pris pour du français »).
  - Je demande un test avec des JSON Plex et Jellyfin réels, contenant `displayTitle` et `extendedDisplayTitle`.
- **Effet de bord serveur à documenter, sans le corriger** : en transcodage Plex, un sous-titre image reconnu par son
  titre puis incrusté déclenche le `PUT` de `selectSubtitleStreamForBurn` (`plex_client.dart` l.2995). C'est le même
  effet de bord connu que dans `langues-preferees` ; il s'appliquera aussi à ces pistes.
- **Coût sur la Fire Stick** : quelques comparaisons de chaînes par piste, négligeable. Prévoir des expressions
  régulières compilées une seule fois (`static final`), pas à chaque passage.
- **Recette** : Green Lantern, `adb logcat -v time -s flutter | grep -E "Subtitle:|Fork preferred"`.
  - Le journal du fork doit dire quand une langue a été déduite du titre, par exemple « title says fr, declared en ».
  - CA1 et CA2 sur la TV.
  - CA3 vérifié en choisissant la vraie piste anglaise dans le menu : elle reste marquée anglaise.

## Alternatives écartées

- **Corriger la langue sur le serveur Plex** (`PUT` sur la piste) : hors périmètre, et ce serait écrire dans les
  données que voient les autres apps.

## Impact

- Fichiers upstream modifiés : aucun côté plateforme. Les éventuels crochets Dart sont l'affaire de l'architecte-app ;
  je recommande qu'ils restent dans `lib/fork/preferred_languages.dart`.
- Dépendances : aucune.
- Risques :
  - lire `displayTitle` ou `extendedDisplayTitle` au lieu du titre de l'auteur (CA3) ;
  - un faux positif sur un titre court (« EN », « FR ») contenu dans un autre mot. La reconnaissance doit porter sur
    des mots entiers, ce qui relève de l'architecte-app.

## QUESTIONS PRODUIT

Aucune.
