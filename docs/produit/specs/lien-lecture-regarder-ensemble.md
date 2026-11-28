# Le lien « lire ce titre » lance la lecture au lieu d'ouvrir « Regarder ensemble »

Statut : validée        Priorité : Should
Dernière mise à jour : 2026-11-28

Correction demandée explicitement par l'utilisateur (« corrige le lien popkino://play qui ouvre regarder ensemble »),
traitée en voie courte, sans spec complète.

## Problème

Le lien `popkino://play?server=<serveur>&id=<élément>` sert à lancer un titre depuis l'extérieur de l'app : étiquette
NFC, domotique, outils de test. C'est une fonction reprise de Plezy. Observé le 2026-11-28 :
- 0.2.0 (Fire TV), app fermée : l'épisode se lance. Comportement correct.
- 0.3.0+9 (Freebox Pop), app ouverte : l'écran « Regarder ensemble » s'ouvre sur un salon créé, sans lecture.
- 0.3.0+9, app fermée, lien correct : un salon est créé (« Vous êtes l'hôte »), sans lecture.
- 0.3.0+9, app fermée, lien mal écrit (`\&` au lieu de `&`) : l'écran « Rejoindre un salon » s'ouvre.

## Critères d'acceptation

- CA1 : Étant donné l'app **fermée** sur la TV, quand on ouvre `popkino://play?server=<serveur>&id=<épisode>`, alors
  la lecture de cet épisode démarre, comme en 0.2.0, et aucun écran « Regarder ensemble » n'apparaît ni aucun salon
  n'est créé.
- CA2 : Étant donné l'app **déjà ouverte** sur n'importe quel écran (accueil, fiche, lecteur), quand on ouvre le même
  lien, alors la lecture de cet épisode démarre, sans écran « Regarder ensemble » ni salon créé.
- CA3 : Étant donné un lien mal écrit ou un élément introuvable, alors l'app reste sur un écran normal (accueil ou
  écran en cours) et ne crée ni ne rejoint aucun salon.
- CA4 : « Regarder ensemble » fonctionne comme avant : créer un salon depuis l'app et rejoindre le salon d'un autre
  appareil (par son invitation) marchent comme en 0.2.0.
- CA5 : Sur l'écran d'accueil d'Android TV, choisir un titre dans une rangée de l'app lance ce titre, sans écran
  « Regarder ensemble » (si ces rangées utilisent le même mécanisme de lien ; sinon, vérifier seulement qu'elles
  marchent encore).

## Hors périmètre

Les autres liens (`popkino://open`, `popkino://live`, liens par identifiant TMDB/IMDb) : non concernés, sauf s'ils
souffrent du même défaut, ce que l'analyse dira.

## Livraison

Clos le 2026-11-28 : **pas de bug**, artefact de test. Les salons venaient d'une touche OK envoyée à l'aveugle pendant
le test, puis du salon ainsi créé qui revenait. Test instrumenté à froid, sans aucune touche, sur la Freebox Pop
(0.3.0+10) et la Fire TV : le lien lance S3E8 et aucun salon n'est créé.

- Couverts par les 6 tests de non-régression ajoutés (code de l'app inchangé) : CA1, CA3, CA5.
- Non retestés à l'écran : CA2 (app déjà ouverte) et CA4 (créer ou rejoindre un salon).
