# Procédure de release

Les clés et secrets (signature Android, clé de mise à jour Mac/Windows, identifiants des services) sont décrits dans
[`nouvelle-identite/actions-manuelles.md`](nouvelle-identite/actions-manuelles.md).

1. Monter `version:` dans `pubspec.yaml` (`X.Y.Z+N`, le numéro de build `N` augmente toujours).
2. Fusionner sur `main` (le workflow Build refuse un ref non protégé).
3. Lancer le workflow **Build** (GitHub Actions) avec `release_tag` = `X.Y.Z`.
4. Vérifier le brouillon de release créé : fichiers `popkino-*` attendus pour chaque plateforme, `appcast.xml`.
5. Rédiger la description de la release.
6. Publier le brouillon.
7. Vérifier l'appcast (branche `appcast`) : il doit pointer vers la nouvelle version.
