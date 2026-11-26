# Actions manuelles — nouvelle identité Popkino

Ce que toi seul peux faire : ces étapes demandent ton compte GitHub, tes comptes sur les services, ou créent des clés
secrètes qui ne doivent jamais passer par un agent ni par le dépôt. Compte environ **1 h 30** au total, une seule fois.

Règle d'or : **les fichiers et mots de passe secrets ne vont jamais dans le dossier du projet** et ne se collent jamais
dans une conversation. On les range dans un dossier à part, `~/popkino-secrets`, et dans ton gestionnaire de mots de
passe.

| Étape | Quand | Bloque |
|---|---|---|
| A1 — Renommer le dépôt, activer les Issues | maintenant | les liens « adrien24/popkino » de l'app |
| A2 — Clé de signature Android | avant la 1re release | la release Android (CA1 à CA3) |
| A3 — Clé de mise à jour Mac/Windows | avant la tâche T14 du plan | la mise à jour automatique (CA22b, CA22c) |
| A4 — Applications Trakt, Simkl, MDBList | avant de tester ces services | Trakt, Simkl, MDBList (CA19b…) |
| A5 — Branche `appcast` | rien à faire, à vérifier après A6 | — |
| A6 — Publier la première release | quand toutes les tâches sont fusionnées | CA26 |
| A7 — Tests sur les appareils | après A6 | la recette |

Prérequis sur ton Mac : `gh` connecté à ton compte (`gh auth status`), Flutter installé, et `keytool` (fourni avec
Android Studio : s'il n'est pas trouvé, utiliser
`"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"` à la place de `keytool`).

Crée d'abord le dossier des secrets :

```bash
mkdir -p ~/popkino-secrets && chmod 700 ~/popkino-secrets
```

## A1 — Renommer le dépôt et activer les Issues

1. Sur https://github.com/adrien24/plezy, onglet **Settings** > **General**.
2. « Repository name » : `popkino`, puis **Rename**. GitHub redirige l'ancienne adresse, rien ne se perd.
3. Toujours dans **General**, section **Features** : coche **Issues** ; décoche **Sponsorships** si elle est cochée.
4. En haut de la page d'accueil du dépôt, roue dentée à côté de « About » : description
   « Popkino — client Plex, Jellyfin et Emby pour TV, mobile et ordinateur. Basé sur Plezy, projet indépendant. »
5. Sur ton Mac, dans le dossier du projet :

   ```bash
   git remote set-url origin https://github.com/adrien24/popkino.git
   git remote -v   # doit afficher adrien24/popkino
   ```

6. Préviens l'orchestrateur : `CLAUDE.md` cite encore `adrien24/plezy` dans la section « Dépôt ».

## A2 — Clé de signature Android

Cette clé signe chaque APK. **Si tu la perds, plus aucune mise à jour n'est possible** : il faudrait désinstaller
l'app partout et la réinstaller.

1. Crée la clé (choisis un mot de passe long et note-le tout de suite dans ton gestionnaire de mots de passe ; il est
   demandé deux fois, utilise le même pour le magasin et pour la clé) :

   ```bash
   keytool -genkeypair -v -storetype PKCS12 \
     -keystore ~/popkino-secrets/popkino-release.jks -alias popkino \
     -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Popkino"
   ```

2. Affiche l'empreinte publique (ce n'est pas un secret) :

   ```bash
   keytool -list -v -keystore ~/popkino-secrets/popkino-release.jks -alias popkino | grep SHA256
   ```

   Copie la ligne `SHA256: …` : elle ira dans le README (tâche T16) pour que chacun puisse vérifier l'APK.

   **Fait le 2026-11-26.** Empreinte obtenue (publique) :
   `9F:6F:21:45:72:D5:5E:87:F4:AE:6D:C1:34:C7:F4:AA:DF:47:9A:15:99:8E:A2:79:55:D4:0E:B5:BA:C3:46:24`

3. Range la clé dans les secrets du dépôt (chaque commande `gh secret set` sans `--body` te demande la valeur) :

   ```bash
   base64 -i ~/popkino-secrets/popkino-release.jks | gh secret set ANDROID_KEYSTORE_BASE64 -R adrien24/popkino
   gh secret set ANDROID_STORE_PASSWORD -R adrien24/popkino     # colle le mot de passe
   gh secret set ANDROID_KEY_PASSWORD -R adrien24/popkino       # le même mot de passe
   gh secret set ANDROID_KEY_ALIAS -R adrien24/popkino --body popkino
   ```

4. Pour signer aussi tes builds locaux (APK de test pour ta TV), crée le fichier `android/key.properties` (déjà ignoré
   par git, il ne sera jamais commité) :

   ```properties
   storePassword=<le mot de passe>
   keyPassword=<le même mot de passe>
   keyAlias=popkino
   storeFile=/Users/adrien/popkino-secrets/popkino-release.jks
   ```

5. **Sauvegarde** : copie `popkino-release.jks` dans ton gestionnaire de mots de passe (pièce jointe) **et** sur un
   support chiffré hors de ton Mac (clé USB chiffrée par exemple), avec le mot de passe.

## A3 — Clé de mise à jour Mac et Windows

Cette clé signe les mises à jour automatiques. **Si tu la perds, les versions Mac et Windows déjà installées refusent
toutes les mises à jour suivantes.** À faire après la fusion de la tâche T1 du plan (qui ajoute ces fichiers au
`.gitignore`).

1. Dans le dossier du projet :

   ```bash
   flutter pub get
   dart run auto_updater:generate_keys
   mv ed25519_key.pem ed25519_pub.txt ~/popkino-secrets/
   ```

   Le premier fichier est **secret**, le second est **public**.

2. Range la clé secrète dans le dépôt (seulement la partie entre les lignes `-----BEGIN` et `-----END`, c'est le format
   attendu par le workflow) :

   ```bash
   grep -v -- '-----' ~/popkino-secrets/ed25519_key.pem | tr -d '\n' | gh secret set SPARKLE_PRIVATE_KEY -R adrien24/popkino
   ```

3. Donne la clé **publique** à l'orchestrateur pour la tâche T14 (elle n'est pas secrète) :

   ```bash
   cat ~/popkino-secrets/ed25519_pub.txt
   ```

   **Fait le 2026-11-26.** Clé publique obtenue : `8NfzNIZD2KKhYadbFW2hU7ZaZxybnlsi95v3nozYCaI=`

4. **Sauvegarde** `ed25519_key.pem` comme la clé Android (gestionnaire de mots de passe + support chiffré).

## A4 — Applications Trakt, Simkl et MDBList

Environ 10 minutes par service, avec un compte gratuit sur chacun. Partout, l'application s'appelle **Popkino**. Si la
page indiquée a changé, cherche « developer » ou « API » dans les réglages du site.

### Trakt
1. Connecte-toi sur trakt.tv, puis ouvre https://trakt.tv/oauth/applications/new.
2. Name : `Popkino`. Description : « Client Plex et Jellyfin pour TV, mobile et ordinateur ».
3. Redirect uri : `urn:ietf:wg:oauth:2.0:oob`.
4. Permissions : coche `/checkin` et `/scrobble`. Enregistre.
5. Garde la page ouverte : tu as besoin du **Client ID** et du **Client Secret**.

### Simkl
1. Connecte-toi sur simkl.com, puis ouvre https://simkl.com/settings/developer/.
2. Crée une application `Popkino`, de type **« TV, devices & command line »** (connexion par code).
3. Note le **client_id**.

### MDBList
1. Connecte-toi sur mdblist.com, puis ouvre https://mdblist.com/developer.
2. Crée une application `Popkino`, de type **« Device Code »** (ni secret ni adresse de retour).
3. Note le **client ID**.

### Ranger les identifiants
Dans les secrets du dépôt (chaque commande te demande la valeur) :

```bash
gh secret set TRAKT_CLIENT_ID -R adrien24/popkino
gh secret set TRAKT_CLIENT_SECRET -R adrien24/popkino
gh secret set SIMKL_CLIENT_ID -R adrien24/popkino
gh secret set MDBLIST_CLIENT_ID -R adrien24/popkino
```

Pour tes builds locaux, crée `popkino_secrets.json` à la racine du projet (ignoré par git après la tâche T1 ; un modèle
vide `popkino_secrets.example.json` sera fourni) :

```json
{
  "POPKINO_TRAKT_CLIENT_ID": "…",
  "POPKINO_TRAKT_CLIENT_SECRET": "…",
  "POPKINO_SIMKL_CLIENT_ID": "…",
  "POPKINO_MDBLIST_CLIENT_ID": "…"
}
```

Un service dont l'identifiant manque est simplement absent de l'app : tu peux en créer un seul pour commencer.

## A5 — Branche `appcast` (rien à créer)

Le flux de mise à jour Mac/Windows vit sur une branche `appcast` du dépôt. Elle est **créée automatiquement** par le
workflow « Update Packages » à la première release publiée (A6). Après A6, vérifie :

1. https://github.com/adrien24/popkino/tree/appcast contient `appcast.xml`.
2. https://cdn.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml affiche le même fichier. Si c'est encore l'ancienne
   version (cache jusqu'à 12 h), ouvre https://purge.jsdelivr.net/gh/adrien24/popkino@appcast/appcast.xml pour forcer la
   mise à jour.

## A6 — Publier la première release (1.0.0)

Quand toutes les tâches du plan sont fusionnées sur `main` et que A2 et A3 sont faits :

1. Onglet **Actions** du dépôt. Si GitHub demande d'activer les workflows, accepte.
2. Workflow **Build** > **Run workflow** : branche `main`, `release_tag` = `1.0.0`, toutes les plateformes cochées.
3. Compte 1 à 2 h. À la fin, une release **brouillon** `1.0.0` apparaît dans **Releases**.
4. Vérifie la liste des fichiers : tous commencent par `popkino-` (APK Android ×3, `popkino-ios.ipa`,
   `popkino-macos.dmg`, installeur et portables Windows, paquets Linux), plus `appcast.xml`.
5. Écris la description (en français ou en anglais) : nouveautés, et la phrase « Popkino est basé sur Plezy ; projet
   indépendant, ni développé ni soutenu par le projet Plezy. » Pas de lien de téléchargement vers Plezy.
6. **Publish release**. Le workflow « Update Packages » se lance seul (le job winget est ignoré, c'est normal).
7. Fais la vérification A5.

## A7 — Tests sur les appareils (recette)

À faire avec la release 1.0.0 (ou un APK de test pour Android). Coche au fur et à mesure :

- [ ] Android TV : bannière et nom Popkino, l'app s'ouvre (CA1). Avec Plezy installé à côté : les deux apparaissent
      et fonctionnent séparément (CA8).
- [ ] Téléphone Android : icône et nom (CA2). Fire TV si disponible (CA3).
- [ ] Windows : installeur, menu Démarrer, barre des tâches, « Applications installées » avec l'éditeur `adrien24`
      (CA4) ; avec Plezy installé, les deux coexistent, chacun avec ses réglages (CA8). Avertissement SmartScreen :
      « Informations complémentaires » > « Exécuter quand même » (CA27).
- [ ] Mac : fichier disque, dossier Applications, Dock, menus « À propos de Popkino » / « Quitter Popkino » (CA5).
      Première ouverture bloquée : Réglages Système > Confidentialité et sécurité > « Ouvrir quand même » (CA27).
- [ ] Linux : menu des applications et fenêtre (CA6).
- [ ] iPhone/iPad par AltStore ou Sideloadly (CA7).
- [ ] Connexion Trakt, Simkl, MDBList : la page du service affiche « Popkino » (CA19b à CA19g).
- [ ] Mise à jour automatique Mac et Windows : publier une `1.0.1`, vérifier la fenêtre de mise à jour et le
      redémarrage sur la nouvelle version, réglages conservés (CA22b). Sur Mac, noter si macOS redemande « Ouvrir quand
      même » après la mise à jour (à mentionner alors dans le README).
- [ ] Une mise à jour signée avec une autre clé est refusée (CA22c) : se fait avec l'aide du codeur (appcast de test).

## Récapitulatif des secrets à sauvegarder hors GitHub

| Élément | Où il est | Sauvegarde |
|---|---|---|
| `popkino-release.jks` + mot de passe | `~/popkino-secrets/` | gestionnaire de mots de passe + support chiffré |
| `ed25519_key.pem` | `~/popkino-secrets/` | gestionnaire de mots de passe + support chiffré |
| Client ID / secret Trakt, Simkl, MDBList | sites des services | régénérables à tout moment (il faudra alors publier une nouvelle version et se reconnecter) |
