---
name: redaction-spec
description: Gabarits et règles du PO pour la vision produit, le backlog et les specs fonctionnelles du fork Plezy (docs/produit/). À charger pour rédiger ou mettre à jour une spec, le backlog ou la vision.
user-invocable: false
---

# Rédiger les documents produit

Tout est en français, sans jargon technique : on décrit ce que l'utilisateur voit et fait avec sa télécommande.

## `docs/produit/vision.md`

Une page au maximum : pour qui est l'app, le problème qu'elle résout mieux que Plezy, 3 à 5 principes de produit (par
ex. « tout se fait à la télécommande en 3 clics maximum »), et ce que l'app ne fera pas. Mets-la à jour quand
l'utilisateur exprime une préférence durable.

## `docs/produit/backlog.md`

Un tableau trié par priorité :

```markdown
| # | Slug | Besoin (une phrase) | Priorité | Statut |
|---|------|---------------------|----------|--------|
| 1 | bouton-mise-a-jour | Mettre à jour l'app depuis la TV sans réinstaller l'APK à la main | Must | spec validée |
```

- Priorité **MoSCoW** : Must / Should / Could / Won't (avec la raison pour Won't).
- Statuts : `idée` → `en spec` → `spec validée` → `en conception` → `en dev` → `livré`.

## `docs/produit/specs/<slug>.md`

```markdown
# <Titre lisible>

Statut : brouillon | en revue | validée        Priorité : Must | Should | Could
Dernière mise à jour : AAAA-MM-JJ

## Problème
Ce qui gêne aujourd'hui, dans quelle situation, sur quel écran. Les mots de l'utilisateur si possible.

## Objectif
Ce qui sera possible une fois la fonctionnalité livrée (1 à 3 phrases).

## Parcours utilisateur
Étapes à la télécommande, de l'écran de départ au résultat. Préciser où le focus arrive à chaque étape.

## Critères d'acceptation
Numérotés et vérifiables, au format « Étant donné… Quand… Alors… ».
- CA1 : …
Inclure les cas d'erreur (pas de réseau, serveur injoignable, rien à afficher) et Plex **et** Jellyfin si concerné.

## Hors périmètre
Ce qu'on ne fait volontairement pas maintenant.

## Contraintes
Règles du skill `regles-fork` qui s'appliquent (marque, Google Play, TV), compatibilité APK GitHub / version Play.

## Questions ouvertes
Ce qui attend une réponse de l'utilisateur. Vide quand la spec est validée.
```

## Règles

- **Un critère d'acceptation doit pouvoir être testé** par quelqu'un qui n'a pas lu la discussion. Pas de « rapide »,
  « intuitif » : chiffre ou décris.
- Une spec ne décrit pas l'implémentation (pas de noms de classes ou de fichiers) : c'est le travail des architectes.
- Avant de rédiger, vérifie dans les issues upstream (`gh issue list -R edde746/plezy --state all --search "<mots>"`)
  si le besoin existe déjà, et cite les liens utiles dans « Problème ».
- En recette, réponds critère par critère : `CA1 : OK / KO / à tester à la main sur la TV (comment)`.
