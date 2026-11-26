# Backlog

Dernière mise à jour : 2026-11-26

| # | Slug | Besoin (une phrase) | Priorité | Statut |
|---|------|---------------------|----------|--------|
| 1 | nouvelle-identite | Renommer l'app en Popkino (logo provisoire violet), retirer les services Plezy et garder Trakt, Simkl et MDBList avec nos propres enregistrements, sur toutes les plateformes publiées sur GitHub | Must | en recette |
| 7 | langues-preferees | Lancer chaque vidéo dans la langue audio et de sous-titres préférées du compte (anglais sous-titré français), même si le serveur se souvient d'une autre piste | Must | en recette |
| 2 | logo-definitif | Remplacer le logo provisoire par un vrai logo (icônes, bannière TV, visuels des stores) | Should | idée |
| 3 | publication-stores | Publier l'app sur Google Play (TV, mobile) et Amazon Appstore (Fire TV) : compte, fiche, politique de confidentialité, test fermé | Should | idée |
| 4 | services-suivi | Réactiver MyAnimeList / AniList avec nos propres enregistrements (nécessite d'héberger un serveur de connexion) | Could | idée |
| 5 | traductions-fork | Traduire dans toutes les langues de l'app les phrases ajoutées par le fork (aujourd'hui en français et en anglais seulement) | Could | idée |
| 6 | verification-developpeur-android | Enregistrer l'app auprès de Google (compte développeur, pièce d'identité) pour que les téléphones installent l'APK GitHub sans manipulation après la généralisation de 2027 | Should | idée |
| 8 | langue-serie-plex | Respecter la langue audio/sous-titres réglée sur une série directement dans Plex (ex. anime en japonais) au lieu de celle du compte | Could | idée |
| 9 | meilleure-piste-audio | Quand plusieurs pistes audio sont dans la langue préférée, prendre la meilleure (5.1 plutôt que stéréo) au lieu de la première | Should | en recette |
| 10 | reglage-sous-titres-reinitialise | Couper « Choisir l'audio par langue » ne doit pas faire passer « Activer les sous-titres » en « Sélection manuelle » sans le dire | Could | idée |
| 11 | sous-titres-mal-etiquetes | Reconnaître des sous-titres dont le titre dit « French » mais dont la langue indiquée dans le fichier est fausse | Could | en recette |
| 12 | titres-autres-langues | Reconnaître dans le nom des pistes de sous-titres d'autres langues que le français et l'anglais (suite de `sous-titres-mal-etiquetes`) | Could | idée |

Notes :
- `nouvelle-identite` (2026-11-26) : en recette. Reste avant « livré » : clés A2 (Android) et A3 (Mac/Windows), tâches
  T14 et T16 (version 1.0.0, README, licence), applications Trakt/Simkl/MDBList (A4), première release (A6) et tests
  sur appareils (A7).
  Décisions de recette (2026-11-26) : checklist TV faite tout de suite par l'utilisateur ; « Licence » et « Licences
  open source » restent tels quels dans À propos ; A4 (Trakt, Simkl, MDBList) faite avant la 1.0.0 ; Fire TV testé,
  téléphone Android (CA2) non testé pour cette recette.
- `publication-stores` dépend de `nouvelle-identite` et de `logo-definitif` : aucun store n'acceptera l'app tant
  qu'elle ressemble à Plezy.
- `services-suivi` : MyAnimeList et AniList retirés dans `nouvelle-identite` (2026-11-26) ; Trakt, Simkl et MDBList
  y sont gardés (connexion par code, sans serveur).
- `publication-stores` : le règlement anti-spam de Google Play exige que l'app apporte plus qu'une copie de Plezy ;
  il faudra quelques fonctions propres à Popkino avant de publier (à définir dans la vision).
- `langues-preferees` (2026-11-26) : recette OK sur la Fire Stick (tous les CA ; CA3 et CA10 par les tests). Reste avant
  « livré » : écoute par l'utilisateur (CA1), commit et fusion validés par l'utilisateur, version publiée. Spec validée, Must juste après `nouvelle-identite`. Problème connu upstream (#2649 ouvert, #1615 « comportement voulu ») ;
  candidat naturel pour les « fonctions propres à Popkino » exigées par Google Play.
- `meilleure-piste-audio` (2026-11-27) : recette OK sur la Fire Stick (voir docs/technique/meilleure-piste-audio/recette.md).
  CA2 vérifié à l'oreille, commit cfbd7a1cb. Reste avant « livré » : fusion et version publiée.
- `sous-titres-mal-etiquetes` (2026-11-27) : recette OK (CA1 et CA8 sur la TV, le reste par les tests). Reste avant
  « livré » : commit et fusion validés, version publiée.
- `nouvelle-identite` : Paramètres > Services annonce « Trakt, Simkl, Seerr… » alors que seul Seerr apparaît tant que
  A4 n'est pas fait ; à revérifier après A4 (si Trakt/Simkl restent absents, corriger le texte).
- `meilleure-piste-audio`, `reglage-sous-titres-reinitialise`, `sous-titres-mal-etiquetes` : constatés pendant la
  recette de `langues-preferees` (S3E8 et Green Lantern). Le 2e (`reglage-sous-titres-reinitialise`) est sans doute un comportement de Plezy/Plex, à vérifier
  en spec. `meilleure-piste-audio` et `sous-titres-mal-etiquetes` passés en spec à la demande
  de l'utilisateur (2026-11-26).
- `verification-developpeur-android` : à faire avant 2027, au plus tard avec `publication-stores` ; sans effet sur la TV.
