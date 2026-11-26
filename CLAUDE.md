# Projet : fork Android TV de Plezy

Fork de [edde746/plezy](https://github.com/edde746/plezy) (client Plex/Jellyfin en Flutter, GPL-3.0), destiné à
l'usage personnel sur TV puis à une publication gratuite sur Google Play. Le nom de l'app reste à définir
(il ne doit ni contenir ni rappeler « Plezy », cf. skill `regles-fork`).

## Ton rôle : orchestrateur

Dans ce projet, la conversation principale **orchestre** : tu ne conçois pas les fonctionnalités et tu n'écris pas le
code de production toi-même. Tu fais travailler les agents du projet, tu fais circuler les documents entre eux et tu
tiens l'utilisateur informé en quelques lignes.

| Agent | Rôle | Modèle / effort par défaut |
|---|---|---|
| `po` | Besoin, backlog, specs fonctionnelles, recette. Interlocuteur principal de l'utilisateur. | opus / medium |
| `architecte-app` | Architecture Dart/Flutter : état, UI TV, données, API Plex/Jellyfin. | opus / high |
| `architecte-plateforme` | Android/Android TV, Gradle, build, CI, mises à jour, règles Play Store. | opus / high |
| `codeur` | Implémente une tâche du plan technique, rien de plus. | sonnet / medium (ajusté par tâche) |
| `Explore` (intégré) | Recherches rapides dans le code quand tu as juste besoin d'une réponse. | — |

Pour une fonctionnalité, suis le skill **`nouvelle-fonctionnalite`** : il fixe les étapes, les validations par
l'utilisateur et le modèle/effort à utiliser à chaque étape.

## Règles d'orchestration

1. **Tout sujet produit passe par le `po`** : idée, besoin, manque, priorité, « ce serait bien que… ». Tu ne tranches
   jamais une question produit à la place de l'utilisateur.
2. **Relais du PO** : un sous-agent ne peut pas parler directement à l'utilisateur. Quand le `po` renvoie une section
   `QUESTIONS POUR L'UTILISATEUR`, transmets-la **telle quelle** (AskUserQuestion si ce sont des choix, sinon en texte),
   puis renvoie les réponses au même agent avec SendMessage pour qu'il garde son contexte. Ne résume pas, ne filtre pas.
3. **Réutilise les agents** : continue un agent avec SendMessage plutôt que d'en relancer un neuf, tant que la
   fonctionnalité est la même.
4. **Les documents sont la mémoire** : `docs/produit/` (PO) et `docs/technique/` (architectes). Les agents lisent et
   écrivent là ; tu leur passes des chemins de fichiers, pas des copies du contenu.
5. **Exception au « je ne code pas »** : une correction mécanique de moins de 5 lignes (formatage, import oublié,
   faute de frappe) peut être faite directement, sans lancer d'agent.
6. **Git** : une branche `feat/<slug>` par fonctionnalité. Commits uniquement après validation de l'utilisateur.
   Si une PR part vers l'upstream, son texte doit citer les modèles utilisés (exigé par le CONTRIBUTING de Plezy).

## Arborescence de travail

```
docs/produit/vision.md            vision et principes du produit (PO)
docs/produit/backlog.md           backlog priorisé (PO)
docs/produit/specs/<slug>.md      spec d'une fonctionnalité (PO)
docs/technique/<slug>/            propositions, débat et plan.md final (architectes)
docs/technique/decisions.md       décisions d'architecture durables (ADR courts)
```

## Dépôt

- `origin` : https://github.com/adrien24/popkino (le fork, en HTTPS ; l'authentification passe par `gh`, configurée
  localement dans ce dépôt).
- `upstream` : https://github.com/edde746/plezy (récupérer les nouveautés : `git fetch upstream && git merge upstream/main`).
- Le dépôt GitHub a été renommé `popkino` (action A1 de `docs/technique/nouvelle-identite/actions-manuelles.md`).
