# Backlog

Dernière mise à jour : 2026-11-28

| # | Slug | Besoin (une phrase) | Priorité | Statut |
|---|------|---------------------|----------|--------|
| 1 | nouvelle-identite | Renommer l'app en Popkino (logo provisoire violet), retirer les services Plezy (Trakt, Simkl et MDBList reportés à `services-suivi`), sur toutes les plateformes publiées sur GitHub | Must | en recette |
| 7 | langues-preferees | Lancer chaque vidéo dans la langue audio et de sous-titres préférées du compte (anglais sous-titré français), même si le serveur se souvient d'une autre piste | Must | livré |
| 13 | bouton-mise-a-jour | Installer une nouvelle version publiée sur GitHub depuis l'accueil, à la télécommande, sans ordinateur ni navigateur (version GitHub seulement, jamais dans les versions store) | Should | livré |
| 14 | motifs-marqueurs-par-defaut | Passer le récapitulatif en début d'épisode (« Previously on… ») d'une pression sur OK, et reconnaître sans réglage les chapitres d'intro et de générique nommés en anglais ou en français | Should | livré |
| 15 | lien-lecture-regarder-ensemble | Anomalie à analyser : sur la 0.3.0 de test, le lien `popkino://play?server=…&id=…` ouvre « Regarder ensemble » (création d'un salon) au lieu de lancer l'épisode ; il marchait en 0.2.0 | Should | livré (artefact de test, pas de bug) |
| 16 | premier-ok-bouton-saut | Anomalie à vérifier : au tout premier OK après l'ouverture d'un épisode, « Passer l'intro » était visible mais OK a seulement affiché le bandeau du lecteur, sans sauter (vu une fois sur la Fire TV, non reproduit) | Could | idée |
| 17 | demandes-recentes-overseerr | Voir dans chaque bibliothèque (Séries, Films, Animés), sous « Continuer à regarder », ses dernières demandes Overseerr et ouvrir le titre du serveur s'il est arrivé, sinon sa fiche Explorer | Should | en recette (recette OK sur la Fire TV, à commiter) |
| 18 | demandes-recentes-sans-saut | Ne plus voir les rangées d'une bibliothèque sauter vers le bas quand « Demandes récentes » apparaît (~1 s après l'ouverture), en réservant sa place et/ou en montrant aussitôt les dernières demandes connues | Should | idée |
| 2 | logo-definitif | Remplacer le logo provisoire par un vrai logo (icônes, bannière TV, visuels des stores) | Should | idée |
| 3 | publication-stores | Publier l'app sur Google Play (TV, mobile) et Amazon Appstore (Fire TV) : compte, fiche, politique de confidentialité, test fermé | Should | idée |
| 4 | services-suivi | Réactiver les services de suivi avec nos propres enregistrements : d'abord Trakt, Simkl et MDBList (connexion par code, sans serveur), puis MyAnimeList / AniList (nécessite d'héberger un serveur de connexion) | Could | idée |
| 5 | traductions-fork | Traduire dans toutes les langues de l'app les phrases ajoutées par le fork (aujourd'hui en français et en anglais seulement) | Could | idée |
| 6 | verification-developpeur-android | Enregistrer l'app auprès de Google (compte développeur, pièce d'identité) pour que les téléphones installent l'APK GitHub sans manipulation après la généralisation de 2027 | Should | idée |
| 8 | langue-serie-plex | Respecter la langue audio/sous-titres réglée sur une série directement dans Plex (ex. anime en japonais) au lieu de celle du compte | Could | idée |
| 9 | meilleure-piste-audio | Quand plusieurs pistes audio sont dans la langue préférée, prendre la meilleure (5.1 plutôt que stéréo) au lieu de la première | Should | livré |
| 10 | reglage-sous-titres-reinitialise | Couper « Choisir l'audio par langue » ne doit pas faire passer « Activer les sous-titres » en « Sélection manuelle » sans le dire | Could | idée |
| 11 | sous-titres-mal-etiquetes | Reconnaître des sous-titres dont le titre dit « French » mais dont la langue indiquée dans le fichier est fausse | Could | livré |
| 12 | titres-autres-langues | Reconnaître dans le nom des pistes de sous-titres d'autres langues que le français et l'anglais (suite de `sous-titres-mal-etiquetes`) | Could | idée |

Notes :
- `demandes-recentes-sans-saut` (2026-11-28) : demandé après la recette de `demandes-recentes-overseerr` (« mettre en cache et également mettre un skeleton […] pour pas que ça clip »). Contrainte héritée : jamais d'état périmé affiché comme actuel si Overseerr ne répond pas (CA17), rien de lu au démarrage de la Fire TV. Réponses de l'utilisateur (2026-11-28) : traité après la livraison de `demandes-recentes-overseerr`, comme élément séparé ; affiches grises pendant le chargement seulement si la bibliothèque avait des demandes la dernière fois (elles disparaissent s'il n'y a plus rien ou si Overseerr ne répond pas) ; pas de dernières demandes en cache, seulement les affiches grises. Spec à rédiger.
- `demandes-recentes-overseerr` (2026-11-28) : demandé par l'utilisateur. Upstream : #3050 ouvert (rangée « Mes demandes » dans Explorer), #2410 fermé « non prévu » : fonction propre à Popkino. Recette uniquement sur la Fire TV Stick (plus sur la Freebox, correction du 2026-11-28). Animés reconnus par les infos TMDB (mot-clé anime), films animés dans Animés, partiellement disponible = fiche serveur, refusées affichées avec badge , bibliothèque Animés reconnue automatiquement (animés arrivés, sinon nom « Anim »). Spec validée par l'utilisateur le 2026-11-28.
- `lien-lecture-regarder-ensemble` (2026-11-28) : clos, **pas de bug**. Les salons créés venaient du test lui-même (une touche OK envoyée à l'aveugle, puis le salon créé qui revenait). Test instrumenté à froid, sans aucune touche : le lien lance S3E8 sur la Freebox (0.3.0+10) et la Fire TV. 6 tests de non-régression ajoutés, code de l'app inchangé.
- `motifs-marqueurs-par-defaut` (2026-11-28) : livré (commit 81691e3b2, fusion 3271b78ff). Recette : S3E8 OK sur la Fire TV ; S3E9 et S3E10 non essayés ; Jellyfin et mots français validés par les tests automatiques (pas de serveur Jellyfin, pas de fichier à chapitres français).
- `premier-ok-bouton-saut` (2026-11-28) : vu pendant la recette de `motifs-marqueurs-par-defaut`. Pour vérifier : ouvrir un épisode, ne rien toucher, un seul OK quand le bouton apparaît, 3 fois ; refaire sur une série avec une vraie intro Plex sans récap. Si le défaut y est aussi, il vient de Plezy (peut-être la première touche qui fait passer l'app en mode télécommande).
- `lien-lecture-regarder-ensemble` (2026-11-28) : constaté par l'orchestrateur en test. Ce lien n'est pas qu'un outil de test : c'est une fonction de Plezy (liens « lire ce titre » pour étiquettes NFC, domotique, et rangées de l'écran d'accueil Android TV qui lancent un titre). Une régression entre 0.2.0 et 0.3.0 peut donc toucher l'utilisateur ; à analyser (vérifier aussi les rangées de l'accueil Android TV).
- `motifs-marqueurs-par-defaut` (2026-11-28) : demandé à cause de The Handmaid's Tale (S3, Plex) dont le récapitulatif ne peut pas être passé. Plex ne fournit jamais de marqueur de récapitulatif : seuls les noms de chapitres du fichier (ou les segments « Récap » de Jellyfin) le permettent. Vérifié sur la Fire TV : S3E8 a un chapitre « Recap » (0:00 à 1:19), donc la reconnaissance des noms de chapitres règle ce cas. Besoin connu upstream côté Jellyfin (#3051, ouvert) : candidat à une PR.
- `bouton-mise-a-jour` (2026-11-28) : livré (72fac63c2, fusion 41c39c5e7), recette sur la Freebox Pop, Fire TV pas encore essayée. Spec validée (bouton seulement si mise à jour, pré-versions proposées, fenêtre de démarrage gardée, téléphone et TV). Fonction temporaire : à retirer lors de `publication-stores`. Refusé par Plezy (#2868, #1782 fermés ; #3125 sans réponse), donc fonction propre à Popkino. Constat : la vérification actuelle ignore les pré-versions (0.1.0 et 0.2.0 n'ont jamais été proposées) et sa fenêtre ouvre un navigateur, absent des TV. La 1re version signée avec la clé définitive (A2) ne pourra pas s'installer par-dessus la 0.2.0.
- `langues-preferees`, `meilleure-piste-audio`, `sous-titres-mal-etiquetes` (2026-11-27) : livrés, fusionnés dans
  main (94b778407) et publiés dans la pré-version de test v0.2.0, installée sur la Fire Stick.
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
