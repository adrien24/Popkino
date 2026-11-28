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

## Release Android seule

Pour publier uniquement les APK (sans passer par le workflow Build), depuis `main` à jour :

1. Monter `version:` dans `pubspec.yaml` (`X.Y.Z+N`) et fusionner, comme ci-dessus.
2. Construire avec la clé de signature **définitive** (`android/key.properties`) et la vérification de mise à jour :

   ```bash
   export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
   flutter build apk --release --split-per-abi --dart-define=ENABLE_UPDATE_CHECK=true \
     --dart-define-from-file=popkino_secrets.json
   ```

3. Renommer chaque APK en `popkino-android-<abi>-<X.Y.Z>.apk` (`arm64-v8a`, `armeabi-v7a`, `x86_64`) :

   ```bash
   cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk popkino-android-armeabi-v7a-X.Y.Z.apk
   ```

4. Vérifier chaque fichier (`BT=$(ls -d ~/Library/Android/sdk/build-tools/* | tail -1)`) :
   - `$BT/apksigner verify --print-certs <apk>` : l'empreinte SHA-256 doit être celle de la clé définitive (cf. `README.md`) ;
   - `$BT/aapt2 dump permissions <apk>` : doit lister `REQUEST_INSTALL_PACKAGES` (sinon le define manquait).
5. Publier en pré-version : `gh release create X.Y.Z --prerelease --title X.Y.Z popkino-android-*-X.Y.Z.apk`.

### Règles à respecter

- Le tag est `X.Y.Z`, sans `v` (D10). Les anciens tags `v0.x` restent et sont acceptés par la vérification.
- `N` (numéro de build) ne redescend jamais sous le plus grand `N` déjà publié et reste inférieur à 1000 (D10 amendé :
  avec `--split-per-abi`, versionCode = ABI × 1000 + N).
- Les APK sont nus, nommés `popkino-android-<abi>-<X.Y.Z>.apk` : l'application choisit le fichier selon l'ABI de
  l'appareil, un autre nom ou un `.tar.gz` ne sera pas proposé.
- Seule une release **publiée** est proposée aux utilisateurs (un brouillon est ignoré).
- Toute pré-version est proposée à **tous** les utilisateurs : `--prerelease` n'est pas un canal de test réservé.
- L'application propose le plus grand numéro de version publié, pas le plus récent par date.

### Cas particulier : la 0.2.0

La 0.2.0 installée est signée avec la clé de debug. La première release signée avec la clé définitive ne peut pas la
remplacer : l'application affiche un message et il faut désinstaller Popkino puis installer la nouvelle version (les
serveurs devront être ajoutés à nouveau). C'est un passage unique.
