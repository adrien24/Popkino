---
name: regles-fork
description: Contraintes non négociables du fork Plezy — marque et logo Plezy (TRADEMARKS.md), licence GPL-3.0, politique Google Play (auto-mise à jour interdite, permissions sensibles), exigences Android TV et maintien de la compatibilité avec l'upstream. À charger pour toute spec ou décision touchant au nom, aux icônes, aux services externes, aux mises à jour, aux permissions ou à la publication.
user-invocable: false
---

# Règles du fork

Sources : `TRADEMARKS.md` et `LICENSE` à la racine du dépôt, et les règles Google Play (à revérifier en ligne quand une
décision en dépend, elles évoluent).

## 1. Marque Plezy (TRADEMARKS.md)

Le code est sous GPL, mais **pas le nom ni le logo**. Dès que l'app est distribuée au-delà d'un usage personnel
(Play Store, releases GitHub publiques, site) :

- **Nom** : rien qui contienne ou rappelle « Plezy » (nom affiché, fiche du store, `applicationId`, site, nom des
  fichiers de release). Pas de « Plex » non plus dans le nom de l'app (marque de Plex Inc.) ; « pour Plex » dans une
  description reste possible.
- **Logo et icônes** : tous remplacés, y compris les icônes alternatives de `assets/app_icons/`.
- **Schéma d'URL** : le nôtre à la place de `plezy://`.
- **Services du projet Plezy interdits** : `ice.plezy.app` (proxy OAuth des trackers, envoi de logs, posters Discord),
  `bugs.plezy.app` (rapports de crash), l'application Discord de Plezy et les enregistrements d'app Trakt,
  MyAnimeList, AniList, Simkl et MDBList. Il faut les désactiver ou enregistrer les nôtres (et héberger notre propre
  `server/` pour le proxy OAuth).
- **Autorisé** : garder les identifiants internes invisibles (nom du package Dart `plezy`, package Kotlin
  `com.edde746.plezy`), ce qui facilite les fusions ; écrire « basé sur Plezy » dans le README, la fiche du store et
  l'écran « À propos », sans laisser croire à un soutien du projet Plezy.

## 2. Licence GPL-3.0

- Le code du fork reste public et sous GPL-3.0 ; les mentions de copyright d'origine sont conservées.
- Les fichiers modifiés doivent indiquer qu'ils ont été modifiés (l'historique git public suffit en pratique ; un
  `NOTICE` ou une section du README le rend explicite).
- Chaque version distribuée doit correspondre à un code source accessible (un tag par release).

## 3. Google Play

- **Pas d'auto-mise à jour hors Play** : une app distribuée par Google Play ne peut ni se mettre à jour, ni se
  remplacer, ni télécharger du code exécutable par un autre canal. La version Play ne doit donc **pas** contenir le
  téléchargement d'APK depuis GitHub, ni la permission `REQUEST_INSTALL_PACKAGES`. Pour proposer une mise à jour dans la
  version Play, utiliser l'**API In-App Updates** de Google Play.
- **Deux distributions, un seul code** : la version « GitHub/sideload » peut avoir le bouton de mise à jour par APK.
  L'upstream a déjà ce mécanisme de bascule : `--dart-define=ENABLE_UPDATE_CHECK=true` et
  `lib/services/update_service.dart` (`_githubRepo = 'edde746/plezy'` à pointer vers le fork). Partir de là avant
  d'inventer des flavors.
- **Autres `--dart-define` upstream à revoir pour le fork** : `ENABLE_SENTRY` (activé seulement pour le dépôt
  edde746), `ENABLE_DONATIONS` (dons vers le projet Plezy, à désactiver ou rediriger), `SUPPORTER_MODE`.
- **Nouveaux comptes développeur personnels** : test fermé obligatoire (au moins 12 testeurs pendant 14 jours d'affilée)
  avant la production. Politique de confidentialité et formulaire « Sécurité des données » obligatoires.
- **Pas d'usurpation ni de contenu répétitif** : l'app doit être clairement distincte de Plezy, qui est déjà sur le
  Play Store.

## 4. Android TV (qualité exigée par Google Play pour les apps TV)

- Bannière pour le launcher Android TV, `LEANBACK_LAUNCHER` déclaré, écran tactile non requis
  (`android.hardware.touchscreen required=false`).
- **Toute l'app utilisable au D-pad** : focus toujours visible, jamais bloqué, la touche Retour se comporte comme
  attendu.
- Textes lisibles à 3 mètres, marges de sécurité sur les bords de l'écran.

## 5. Compatibilité avec l'upstream

Le fork doit pouvoir récupérer régulièrement les nouveautés de Plezy (`git fetch upstream && git merge upstream/main`).
- Préférer de **nouveaux fichiers** aux modifications de fichiers upstream.
- Quand un fichier upstream doit changer, garder le diff petit et localisé, et le signaler par un commentaire
  `// FORK: <raison>` pour repérer ces endroits lors des fusions.
