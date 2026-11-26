# Backlog

Dernière mise à jour : 2026-11-26

| # | Slug | Besoin (une phrase) | Priorité | Statut |
|---|------|---------------------|----------|--------|
| 1 | nouvelle-identite | Renommer l'app en Popkino (logo provisoire violet), retirer les services Plezy et garder Trakt, Simkl et MDBList avec nos propres enregistrements, sur toutes les plateformes publiées sur GitHub | Must | en recette |
| 2 | logo-definitif | Remplacer le logo provisoire par un vrai logo (icônes, bannière TV, visuels des stores) | Should | idée |
| 3 | publication-stores | Publier l'app sur Google Play (TV, mobile) et Amazon Appstore (Fire TV) : compte, fiche, politique de confidentialité, test fermé | Should | idée |
| 4 | services-suivi | Réactiver MyAnimeList / AniList avec nos propres enregistrements (nécessite d'héberger un serveur de connexion) | Could | idée |
| 5 | traductions-fork | Traduire dans toutes les langues de l'app les phrases ajoutées par le fork (aujourd'hui en français et en anglais seulement) | Could | idée |
| 6 | verification-developpeur-android | Enregistrer l'app auprès de Google (compte développeur, pièce d'identité) pour que les téléphones installent l'APK GitHub sans manipulation après la généralisation de 2027 | Should | idée |

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
- `verification-developpeur-android` : à faire avant 2027, au plus tard avec `publication-stores` ; sans effet sur la TV.
