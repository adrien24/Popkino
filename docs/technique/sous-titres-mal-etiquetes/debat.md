# Débat — sous-titres-mal-etiquetes

## Critique de app sur la proposition plateforme — tour 1

- ✅ D'accord :
  - aucun changement natif ni de build ;
  - la logique reste dans `lib/fork/preferred_languages.dart` et dans un nouveau `lib/fork/subtitle_title_language.dart` ;
  - les mots du titre sont reconnus comme mots entiers, par des expressions compilées une seule fois
    (`static final`) ;
  - le journal indique « title says fr, declared en » ;
  - le `PUT` d'incrustation Plex est documenté comme effet de bord connu ;
  - pour la recette, CA3 se vérifie depuis le menu ;
  - des tests sur des JSON Plex et Jellyfin réels, avec `displayTitle` **et** `extendedDisplayTitle` (rappel :
    `plex_mappers.dart` l.131 met `displayTitle ?? extendedDisplayTitle` dans `displayTitle`).
- ⚠️ À amender, en suivant ton exigence sur la source du titre :
  - **Ma proposition lisait `t.title` sur les descripteurs `source:`.** Ce champ peut venir du repli `displayTitle`
    (`playback_subtitle_resolver.dart` l.348). Le repli serait sans danger dans ma règle, qui ne décide que si une
    seule langue est nommée : « French Complet (English SRT) » nomme deux langues, donc on reste sur la langue
    déclarée et CA3 tient. Mais il vaut mieux ne pas dépendre de ce détail.
  - **Amendement retenu** : pour une piste dont l'id est `source:<N>`, le titre lu est le `title` de la ligne serveur
    `plexMediaInfo.subtitleTracks` d'id N, c'est-à-dire le titre de l'auteur, ou `null`. Il n'y a jamais de repli.
    Pour une piste native, on lit `SubtitleTrack.title`, le nom donné par le conteneur. Pour S3, on lit `row.title`
    seulement.
  - **Tests à ajouter** :
    - une ligne sans `title` dont `extendedDisplayTitle` vaut « French Complet (English SRT) » doit rester anglaise ;
    - une ligne `title` « French Complet », `languageCode` eng, doit être reconnue comme française.
- ❌ Bloquant : aucun.

## Critique de plateforme sur la proposition app — tour 1

- ✅ D'accord :
  - **Tout dans `lib/fork/`, aucune ligne upstream**, aucun impact Android ni Play.
  - **Mots entiers et deux niveaux de mots (forts, faibles)**, tri stable « bien étiquetée d'abord » (CA7).
  - **S3 sur `row.title` et jamais sur `displayTitle`.** C'est exactement l'exigence de ma proposition. Le repli du
    descripteur (`title ?? displayTitle`) concorde avec la langue indiquée, donc il est sans effet (CA6).
  - **Q1 : non pour cette version.**

- ⚠️ À amender : **pistes externes côté mpv.** Après l'ouverture, la règle voit aussi les pistes **natives**.
  - Pour un sous-titre externe, mpv ne reçoit que l'URL (`_externalSubtitlesLoadfileOption`, `player_native.dart`
    l.192-200). Son `title` vient du nom de fichier ou de l'URL, pas de l'auteur.
  - Proposition : ne déduire la langue du titre que pour les pistes **non externes** (`!t.isExternal`) quand ce sont
    des pistes natives. Les sous-titres externes restent couverts par le resolver, avant l'ouverture, via la ligne
    serveur.
  - Test : une piste native externe dont le titre est un nom de fichier contenant `en` ou `fr` doit garder sa langue
    indiquée.

- ⚠️ À amender : **sous-titres image en transcodage Plex** (risque hérité de `langues-preferees`, à écrire dans le
  plan).
  - Le choix de la piste à incruster est fait **avant** le resolver, par
    `_resolveTranscodeSubtitleTrack(info, preferredSubtitleTrack)` (`plex_client.dart` l.4022). Au lancement, la
    préférence vaut `null`, et c'est le `selected` du serveur qui gagne.
  - Un « French Complet » en PGS mal étiqueté ne sera donc pas incrusté en transcodage. Rien de pire qu'aujourd'hui,
    mais CA1 ne tient qu'en lecture directe ou avec des sous-titres texte.
  - Si une telle piste est incrustée à la suite d'un choix manuel, `selectSubtitleStreamForBurn` écrit sur le serveur
    (effet de bord déjà documenté).

- ❌ Bloquant : aucun.

## Validation de plateforme sur plan.md — tour 1

APPROUVÉ. Mes deux demandes du tour 1 sont intégrées :
- les pistes natives externes n'ont pas de titre d'auteur, et un test le vérifie ;
- les sous-titres image en transcodage Plex et l'écriture d'incrustation sur le serveur figurent dans les risques.
La lecture exclusive du `title` d'auteur, jamais de `displayTitle` ni d'`extendedDisplayTitle`, est vérifiée par un
test avec des JSON réels.

## Ajustement du pilote (app) après T2 — 2026-11-27

- Le codeur a relevé une contradiction : pour un descripteur `source:N` dont la ligne serveur est introuvable (id
  périmé), la décision 2 disait `null` alors que T2 renvoyait au repli `!isExternal → t.title`.
- **La décision 2 prévaut** : un descripteur `source:` ne fournit jamais son propre `title`, qui peut venir du repli
  `displayTitle`. Sans ligne serveur, pas de titre d'auteur, donc on garde la langue indiquée.
- C'est ce que le codeur a implémenté, avec un test. `plan.md`, T2, est corrigé pour être cohérent.
