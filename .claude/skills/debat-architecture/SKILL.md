---
name: debat-architecture
description: Protocole de débat entre architecte-app et architecte-plateforme et gabarits des documents techniques (proposition, critique, plan.md, décisions). À charger pour proposer, critiquer ou consolider un plan technique du fork Plezy.
user-invocable: false
---

# Débat d'architecture

Les deux architectes ne se parlent pas directement : l'orchestrateur fait circuler les **chemins de fichiers**. Tout
passe par `docs/technique/<slug>/`. Le but n'est pas d'avoir raison mais d'obtenir le plan le plus simple, le plus sûr
et le plus facile à fusionner avec l'upstream.

## Phase 1 — Proposition (chacun de son côté, sans lire l'autre)

`docs/technique/<slug>/proposition-<app|plateforme>.md` :

```markdown
# Proposition <app|plateforme> — <slug>

## Compréhension de la spec
En 3 lignes, plus les critères d'acceptation qui touchent ton périmètre.

## Existant
Fichiers, classes et mécanismes actuels concernés (chemins réels, lus dans le code).

## Approche proposée
La solution, et pourquoi elle plutôt qu'une autre.

## Alternatives écartées
Au moins une, avec la raison.

## Impact
- Fichiers upstream modifiés (à minimiser) / nouveaux fichiers
- Dépendances ajoutées
- Risques : Google Play, marque, performances TV, conflits de fusion avec l'upstream
```

## Phase 2 — Critique croisée

Lis la proposition de l'autre, puis **ajoute** (ne réécris pas) ta section à `docs/technique/<slug>/debat.md` :

```markdown
## Critique de <app|plateforme> sur la proposition <autre> — tour N
- ✅ D'accord : …
- ⚠️ À amender : … → proposition concrète
- ❌ Bloquant : … → pourquoi (règle, bug, risque) et alternative
```

Sois exigeant et précis : un ❌ doit citer une raison vérifiable (une ligne de code, une règle Play, une mesure). Pas
d'objection de goût présentée comme bloquante.

## Phase 3 — Plan final (architecte pilote)

`docs/technique/<slug>/plan.md`, qui reprend la meilleure combinaison des deux propositions et règle chaque ❌ :

```markdown
# Plan technique — <slug>

Spec : docs/produit/specs/<slug>.md
Statut : brouillon | approuvé       Pilote : architecte-<app|plateforme>

## Décisions
Les choix structurants, chacun avec sa raison en une ligne.

## Tâches
### T1 — <titre>
- Complexité : S | M | L
- Dépend de : — | T…
- Fichiers : chemins exacts (créer / modifier)
- À faire : instructions précises, assez pour qu'un développeur n'ait aucun choix d'architecture à faire
- Tests : ce qu'il faut tester et où
- Critères d'acceptation couverts : CA…

## Vérification globale
Commandes à lancer et tests manuels sur la TV.

## Risques restants
```

Règles pour les tâches :
- Une tâche = un changement cohérent qu'un développeur peut finir et vérifier seul (idéalement moins de 300 lignes).
- **Complexité** : S = mécanique, sans logique ; M = logique ordinaire ; L = délicat (lecture vidéo, concurrence,
  natif Kotlin, migration de données, CI/signature). Elle détermine le modèle et l'effort du codeur : ne la sous-estime
  pas.
- Deux tâches qui touchent le même fichier doivent être liées par « Dépend de ».

## Phase 4 — Validation croisée

L'autre architecte relit `plan.md` et répond `APPROUVÉ`, ou liste ses objections bloquantes dans `debat.md`. Au maximum
2 tours ; ensuite l'orchestrateur fait trancher l'utilisateur. Une fois approuvé, le pilote passe le statut à
`approuvé`.

## Décisions durables

Si une décision dépasse cette fonctionnalité (par ex. « les fonctions propres au fork vivent dans `lib/fork/` »),
ajoute-la à `docs/technique/decisions.md` :

```markdown
## D<n> — <titre> (AAAA-MM-JJ)
Contexte · Décision · Conséquences
```

Lis ce fichier au début de chaque débat : une nouvelle proposition ne doit pas contredire une décision existante sans
le dire explicitement.
