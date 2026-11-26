---
name: nouvelle-fonctionnalite
description: Déroulé complet pour livrer une fonctionnalité ou une correction du fork Plezy avec les agents du projet (po → architectes → codeur → vérification → recette), avec le modèle et l'effort à utiliser à chaque étape. À utiliser par l'orchestrateur dès que l'utilisateur demande une fonctionnalité, une amélioration ou une correction, ou tape /nouvelle-fonctionnalite.
---

# Livrer une fonctionnalité

Tu es l'orchestrateur. Chaque étape a une **porte** : ne passe pas à la suivante sans la condition indiquée. Tiens
l'utilisateur au courant en une ou deux lignes à chaque changement d'étape.

Choisis d'abord la voie :

- **Voie complète** : nouvelle fonctionnalité, changement visible, nouvelle dépendance, ou tout ce qui touche au build,
  à la distribution, aux mises à jour ou aux données stockées.
- **Voie courte** : bug localisé, ajustement de texte ou de style, sans choix d'architecture. Étape 1 réduite à une
  confirmation du comportement attendu par le `po`, étape 2 confiée au **seul architecte concerné** avec
  `effort: "medium"`, qui écrit directement `plan.md`. Dans le doute, prends la voie complète.

Choisis un `slug` court en kebab-case (par ex. `bouton-mise-a-jour`) et utilise-le partout.

## Étape 1 — Spec (agent `po`)

1. Lance `po` avec la demande brute de l'utilisateur (ses mots exacts) et le slug.
2. Boucle de questions : tant que la réponse contient des `QUESTIONS POUR L'UTILISATEUR`, relaie-les mot pour mot
   (AskUserQuestion pour les choix), puis renvoie les réponses au **même** agent avec SendMessage.
3. Quand `docs/produit/specs/<slug>.md` est prêt, présente à l'utilisateur un résumé (objectif, critères
   d'acceptation, hors périmètre) et demande sa validation.

**Porte** : l'utilisateur a validé et la spec est en statut `validée`.

## Étape 2 — Débat d'architecture (`architecte-app` + `architecte-plateforme`)

Suis le protocole du skill `debat-architecture`. En résumé :

1. **Propositions en parallèle** : lance les deux architectes dans le même message (en arrière-plan), chacun avec le
   chemin de la spec. Chacun écrit `docs/technique/<slug>/proposition-<app|plateforme>.md`.
2. **Critique croisée** : envoie à chacun (SendMessage) le chemin de la proposition de l'autre. Chacun ajoute sa
   critique dans `docs/technique/<slug>/debat.md`.
3. **Synthèse** : l'architecte **pilote** écrit `plan.md`. Le pilote est `architecte-app` si l'essentiel du travail est
   dans `lib/`, sinon `architecte-plateforme`.
4. **Validation croisée** : l'autre architecte relit `plan.md` et répond `APPROUVÉ` ou liste ses objections bloquantes.
   Au maximum **2 tours** d'objections ; au-delà, présente les options restantes à l'utilisateur avec ta
   recommandation.
5. Les `QUESTIONS PRODUIT` des architectes passent par le `po` (puis éventuellement l'utilisateur), jamais tranchées
   par toi.

**Porte** : `plan.md` est approuvé par les deux architectes. Montre à l'utilisateur un résumé du plan (approche, tâches,
risques). Attends son accord **seulement** si le plan ajoute une dépendance, change l'identité de l'app, migre des
données stockées, touche à la signature ou à la publication, ou s'il reste un désaccord. Sinon, continue en le
prévenant.

## Étape 3 — Code (agent `codeur`)

Pour chaque tâche de `plan.md`, dans l'ordre des dépendances, lance `codeur` avec : le chemin du plan, l'identifiant
de la tâche, et le rappel « implémente uniquement cette tâche ».

Ajuste modèle et effort selon la **complexité** indiquée dans le plan (ce skill t'autorise explicitement à passer
`model` et `effort` à l'outil Agent) :

| Complexité | Exemples | `model` | `effort` |
|---|---|---|---|
| S | traductions, constantes, renommage, réglage simple | `haiku` | `low` |
| M | écran ou widget, service simple, paramètre, test | défaut (sonnet) | défaut (medium) |
| L | lecture vidéo, synchro, concurrence, code natif Kotlin, migration drift, CI | défaut (sonnet) | `high` |

- Si une tâche échoue deux fois au même niveau, relance-la avec `model: "opus"` et `effort: "high"`.
- Des tâches **indépendantes qui ne touchent pas les mêmes fichiers** peuvent être lancées en parallèle.
- `BLOQUÉ` : renvoie le problème à l'architecte pilote (SendMessage). Il corrige `plan.md` (en notant le changement
  dans `debat.md`), puis relance la tâche. Ne corrige jamais le plan toi-même.

**Porte** : toutes les tâches sont `TERMINÉ`.

## Étape 4 — Vérification (toi)

Lance toi-même les vérifications globales du skill `conventions-code` (formatage, codegen `--check`, analyse, tests).
En cas d'échec, renvoie au `codeur` l'erreur exacte et la tâche concernée, avec le même modèle et le même effort. Si
l'échec révèle un défaut du plan, passe par l'architecte pilote.

**Porte** : tout est vert.

## Étape 5 — Recette (agent `po` puis utilisateur)

1. Renvoie au `po` (SendMessage, même agent qu'à l'étape 1) : le diff (`git diff --stat` et le chemin des fichiers)
   et le résultat des tests. Il vérifie chaque critère d'acceptation et liste ce qui doit être testé à la main.
2. Donne à l'utilisateur la commande pour construire l'APK et la liste de tests manuels du `po` sur la TV.
3. Sur son accord : commit sur `feat/<slug>`, puis le `po` passe l'élément du backlog à `livré`.
