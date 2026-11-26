# Identité visuelle (logo provisoire)

Tout ce qui est image dans l'application (icônes, bannière Android TV, images tvOS, icône Windows, calques des icônes
Apple) est **généré** à partir de ce dossier par `scripts/fork/generate_brand_assets.py`.

## Fichiers

| Fichier | Rôle |
|---|---|
| `brand.json` | Nom, couleur de fond (`backgroundColor`), couleur du signe (`markColor`), texte de la bannière (`bannerText`). |
| `mark.svg` | Le signe : un seul `<path>` sur un canevas 1024 x 1024, contenu dans le cercle centré de 61 % (zone sûre des icônes adaptatives Android). Le script lit son attribut `d` tel quel. |
| `banner.svg` (optionnel) | Remplace la bannière Android TV composée automatiquement (rendu 16:9). |
| `background.svg` (optionnel) | Remplace le fond uni (icône carrée, calque Back tvOS, top shelf). |
| `monochrome.svg` (optionnel) | Remplace le signe pour l'icône monochrome Android et l'icône de notification (même règle que `mark.svg` : un `<path>`, canevas 1024). |

`banner.svg` et `background.svg` sont rendus avec `rsvg-convert` (`brew install librsvg`), uniquement s'ils existent.

## Remplacer le logo par le logo définitif

1. Remplacer `branding/mark.svg` (canevas 1024 x 1024, un seul `<path>`, tracés uniquement, aucune police, signe dans le
   cercle de 61 %). Ajouter au besoin `banner.svg`, `background.svg`, `monochrome.svg`.
2. Ajuster `brand.json` si les couleurs ou le nom changent. Si le fond change, mettre aussi à jour à la main
   `ic_launcher_background` dans `android/app/src/main/res/values/colors.xml`.
3. Lancer, depuis la racine du dépôt :

   ```bash
   python3 -I scripts/fork/generate_brand_assets.py          # régénère les images
   python3 -I scripts/fork/generate_brand_assets.py --check  # compare sans écrire (code 1 si différent)
   ```

   Dépendance : Pillow (`pip install pillow`, de préférence dans un venv local `.venv/` ignoré par git).

Le script est idempotent : une deuxième exécution ne change aucun fichier.
