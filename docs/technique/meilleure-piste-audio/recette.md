# Recette — meilleure-piste-audio

Date : 2026-11-27. Fire Stick de l'utilisateur, TV LG sans barre de son, APK 0.1.2, compte Plex.
Vérification par le menu « Audio et sous-titres » et l'état de la sortie audio Android (adb). Code : T1 à T4
terminées, 8634 tests passent, aucun fichier upstream modifié. Seul échec connu : `check_identity` (sans lien).

| CA | Verdict | Comment |
|---|---|---|
| CA1 | OK | « D'origine » : S3E8 → English 2.0 |
| CA2 | OK (vérifié à l'oreille) | « Jusqu'à 5.1 » : S3E8 → « ENG VO - EAC3 DDP 5.1 », Green Lantern → « English DTS 1509kbps 5.1 » ; sortie Android en flux direct E-AC3 puis DTS, trames qui avancent. Écoute de l'utilisateur (2026-11-27) : son normal sur la TV LG pour les deux (DTS et E-AC3). Variante transmission directe désactivée non testée. |
| CA3 | OK | « Stéréo » : Green Lantern → English 2.0 |
| CA3bis | OK | « D'origine » = choix d'aujourd'hui (S3E8 → English 2.0) |
| CA4 | OK par les tests | `preferred_languages_test` (une seule piste anglaise) |
| CA5 | OK par les tests | `preferred_languages_test` (deux pistes anglaises 5.1 → choix d'aujourd'hui) |
| CA6 | OK par les tests | `preferred_languages_test` (choix manuel → règle muette) ; pas refait sur la TV |
| CA7 | OK | « Jusqu'à 5.1 » : S3E8 → épisode suivant → S3E9 en English 5.1 |
| CA8 | OK par les tests | `preferred_languages_test` « CA8: choosing audio by language off gives null whatever the output » |
| CA9 | OK par les tests | `audio_direct_play_test` (Plex et Jellyfin) ; pas de contrôle des sessions côté serveur |
| CA10 | OK par les tests | `preferred_languages_flow_test`, JSON Jellyfin |
| CA11 | OK par les tests | pas de fichier avec piste de commentaire connu |
| CA12 | OK en français | textes des trois choix vérifiés à l'écran ; anglais non vérifié à l'écran (couvert par les contrôles i18n) |

Réglage « Canaux audio » remis sur « D'origine » après la recette.

Commit cfbd7a1cb sur `feat/meilleure-piste-audio` (2026-11-27). Reste avant « livré » : fusion et version publiée.

Constat annexe : Paramètres > « Services » annonce « Connecter Trakt, Simkl, Seerr et d'autres services » alors que
seul Seerr est proposé dans ce build (identifiants Trakt/Simkl pas encore en place, action A4 de `nouvelle-identite`).
Noté au backlog sous `nouvelle-identite`.
