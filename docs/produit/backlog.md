# Backlog

Dernière mise à jour : 2026-11-26

| # | Slug | Besoin (une phrase) | Priorité | Statut |
|---|------|---------------------|----------|--------|
| 1 | nouvelle-identite | Renommer l'app en Popkino (logo provisoire violet), retirer les services Plezy (Trakt, Simkl et MDBList reportés à `services-suivi`), sur toutes les plateformes publiées sur GitHub | Must | en recette |
| 2 | logo-definitif | Remplacer le logo provisoire par un vrai logo (icônes, bannière TV, visuels des stores) | Should | idée |
| 3 | publication-stores | Publier l'app sur Google Play (TV, mobile) et Amazon Appstore (Fire TV) : compte, fiche, politique de confidentialité, test fermé | Should | idée |
| 4 | services-suivi | Réactiver les services de suivi avec nos propres enregistrements : d'abord Trakt, Simkl et MDBList (connexion par code, sans serveur), puis MyAnimeList / AniList (nécessite d'héberger un serveur de connexion) | Could | idée |
| 5 | traductions-fork | Traduire dans toutes les langues de l'app les phrases ajoutées par le fork (aujourd'hui en français et en anglais seulement) | Could | idée |
| 6 | verification-developpeur-android | Enregistrer l'app auprès de Google (compte développeur, pièce d'identité) pour que les téléphones installent l'APK GitHub sans manipulation après la généralisation de 2027 | Should | idée |

Notes :
- `nouvelle-identite` (2026-11-26) : en recette. Reste avant « livré » : clés A2 (Android) et A3 (Mac/Windows), tâches
  T14 et T16 (version 1.0.0, README, licence), première release (A6) et tests
  sur appareils (A7).
  Décisions de recette (2026-11-26) : checklist TV faite tout de suite par l'utilisateur ; « Licence » et « Licences
  open source » restent tels quels dans À propos ; Fire TV testé, téléphone Android (CA2) non testé pour cette recette.
  Décision (2026-11-26, remplace « A4 faite avant la 1.0.0 ») : A4 reportée, la 1.0.0 sort sans Trakt, Simkl ni
  MDBList (spec P8) ; CA19b à CA19e et CA19g à CA19i reportés, CA19f vérifie leur absence.
- `publication-stores` dépend de `nouvelle-identite` et de `logo-definitif` : aucun store n'acceptera l'app tant
  qu'elle ressemble à Plezy.
- `services-suivi` : MyAnimeList et AniList retirés dans `nouvelle-identite` (2026-11-26). Trakt, Simkl et MDBList
  y étaient prévus puis ont été reportés (2026-11-26, « trop compliqué de les intégrer » pour le moment) ; l'app les
  masque tant que leurs identifiants manquent, rien n'est à changer dans l'app. Points appris pour la réactivation :
  - Trakt : créer l'application en type « confidentielle », qui délivre un Client Secret (pas le mode PKCE, sans
    secret, qui ne marche pas avec la connexion par code de l'app). État actuel : aucun secret Trakt dans GitHub
    (TRAKT_CLIENT_ID supprimé le 2026-11-26), donc Trakt reste masqué ; l'application Trakt actuelle est à recréer ou à corriger.
  - Simkl : demande un compte Simkl (sa création a échoué lors de l'essai) ; secret SIMKL_CLIENT_ID supprimé.
  - MDBList : application pas encore créée.
  - Réactiver = créer les secrets GitHub du service, puis publier une nouvelle version. Critères à recetter alors :
    CA19b à CA19e et CA19g à CA19i de la spec `nouvelle-identite`.
- `publication-stores` : le règlement anti-spam de Google Play exige que l'app apporte plus qu'une copie de Plezy ;
  il faudra quelques fonctions propres à Popkino avant de publier (à définir dans la vision).
- `verification-developpeur-android` : à faire avant 2027, au plus tard avec `publication-stores` ; sans effet sur la TV.
