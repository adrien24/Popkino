# Plan technique — lien-lecture-regarder-ensemble

Spec : docs/produit/specs/lien-lecture-regarder-ensemble.md
Statut : approuvé       Pilote : architecte-app (voie courte, seul architecte)

## Résumé de l'analyse

**Le code de l'app ne transforme pas `popkino://play` en salon « Regarder ensemble ».** Aucune régression n'apparaît
entre v0.2.0 et `main`. Les salons observés sur la Freebox viennent, au moins pour le premier, d'une **touche OK
injectée par le protocole de test**. Les deux observations « à froid » restent **non expliquées**, et seulement sur la
Freebox. Elles demandent une reproduction instrumentée (T1) avant tout correctif. Aucun correctif de code n'est
proposé à l'aveugle.

### 1. La chaîne des liens n'a pas changé depuis v0.2.0

`git diff v0.2.0 main` ne touche aucun des fichiers suivants :

| Maillon | Fichier | Rôle |
|---|---|---|
| Manifeste | `android/app/src/main/AndroidManifest.xml` l. 72-80 | intent-filter `VIEW` + `popkino`, sans hôte |
| Natif | `android/app/src/main/kotlin/com/edde746/plezy/deeplink/DeepLinkPlugin.kt` | transmet l'URL telle quelle (`linkFrom`, `notifyLink`, `getInitialLink`) |
| Activité | `PlezyActivity.kt` l. 590-602 (`onCreate`, `onNewIntent`), l. 643-645 (`handleDeepLinkIntent`), l. 1012 (enregistrement) | branche à froid et à chaud |
| Grammaire | `lib/services/deep_links/deep_link.dart` (`DeepLink.tryParse`, `PlayLink._parse`, `PlayTarget._parse`) | `play?server=&id=` → `ItemPlayTarget` |
| File d'attente | `lib/services/deep_links/deep_link_service.dart` (`receive`, `_pump`, `_launch`) | remet le lien à la session de profil |
| Session | `lib/screens/main_screen.dart` l. 872-888 (`_attachDeepLinks`) | appelle `launchDeepLink` |
| Exécution | `lib/services/deep_links/deep_link_launcher.dart` (`_launchPlayLink`, `PlayLinkResolver`) | `navigateToVideoPlayer` |

Entre v0.2.0 et `main`, il n'y a que 6 commits : le bouton de mise à jour (`lib/fork/update/*`, un
`forkUpdateAction` ajouté dans `lib/screens/discover_screen.dart` l. 928, `ForkPlugins.register` dans
`PlezyActivity.kt` l. 881) et les motifs de marqueurs. La PR « nouvelle identité » (`6eb490576`) est **antérieure**
à v0.2.0 : le passage de `plezy` à `popkino` était déjà dans la 0.2.0 qui marchait.

Aucun chemin ne relie les liens à Regarder ensemble :
- `WatchTogetherProvider.createRoom()` n'a qu'un appelant, `_WatchTogetherScreenState._create`
  (`lib/watch_together/screens/watch_together_screen.dart` l. 61), c'est-à-dire le bouton « Créer un salon ».
- `joinRoom(..., create: true)` n'est appelé que par une tuile « Salons récents » (l. 64).
- `showJoinRoomDialog` n'est appelé que par le bouton « Rejoindre un salon » (l. 68).
- `WatchTogetherScreen` n'est ouvert que par l'icône de la barre d'actions de l'accueil
  (`lib/screens/discover_screen.dart` l. 876).
- Le provider ne rejoint jamais de salon tout seul au démarrage. Il n'y a pas non plus de restauration d'état
  Flutter (aucun `restorationScopeId`).

Seule une **activation d'interface** (OK, Entrée, ou « select » d'un `FocusableAction` ou d'un `WatchButton`) peut
donc créer ou rejoindre un salon. `Enter` compte comme « select » hors clavier physique
(`lib/focus/dpad_navigator.dart` l. 20-24 et 35-40).

Le binaire installé sur la Freebox (`freebox-installed.apk`, extrait le 28/11 à 13:02) contient bien les chaînes
`Deep link: …` et le schéma `popkino`. C'est le même code.

### 2. Reproduction le 2026-11-28 sur la Fire TV, en 0.3.0 (build 10, mêmes fichiers de liens que `main`)

- **À froid** (`am force-stop`, puis `am start -W -a VIEW -d 'popkino://play?server=ceaf…&id=16298'`) : l'épisode se
  lance. Le logcat montre la connexion au serveur, puis `[MPV:…]`, et la capture d'écran montre la vidéo. Aucun
  écran Regarder ensemble. CA1 respecté.
- **À chaud** (app lancée depuis le lanceur, puis lien 10 s plus tard) : logcat `Deep link: PlayLink`, puis MPV
  démarre. CA2 respecté.

**Le défaut ne se reproduit pas avec le code actuel sur la Fire TV.** L'hypothèse d'une régression 0.2.0 → 0.3.0 est
donc écartée : l'écart vient de l'appareil (Freebox) ou des conditions du test, pas de la version.

### 3. Ce qui s'est réellement passé sur la Freebox

Reconstitution à partir des commandes et des captures de la session de test du 2026-11-28 (orchestrateur) :

1. **13:18** : `fb.sh DPAD_UP DPAD_RIGHT DPAD_RIGHT`. Le focus est sur l'icône « Mise à jour disponible » de la
   barre d'actions, voisine de l'icône Regarder ensemble.
2. **Test à chaud** : `am start … "…\&id=16298"`, attente de 12 s, puis **`fb.sh DPAD_CENTER`**. La capture montre
   l'écran Regarder ensemble, dans le salon `EWR-G4G` (« Hôte : adrien.bou1 », Green Lantern en cours). L'agent de
   test l'a noté lui-même : « ma touche OK a créé un salon ». **Cette observation vient de la touche injectée, pas du
   lien.** On ne sait pas pourquoi l'épisode ne s'était pas lancé dans les 12 s (attente du serveur jusqu'à 20 s :
   `deepLinkServerWait`, `deep_link_launcher.dart` l. 28 ?).
3. **À froid, `\&`** : `force-stop`, `am start`, attente de 25 s, capture **sans touche**. On voit l'accueil de
   Regarder ensemble, la boîte « Rejoindre un salon » ouverte avec le clavier, et `EWR-G4G` dans les salons récents.
   Remarque : `\&` entre guillemets doubles sous zsh arrive au shell distant sous la forme `\&`, qui le traduit en
   `&`. Le lien était donc probablement **complet**, contrairement à ce que pense le signalement.
4. **À froid, guillemets corrects** : capture **sans touche** après 25 s. Un nouveau salon `E5S-5W4` est créé,
   « Vous êtes l'hôte », aucune lecture.

Les points 3 et 4 imposent qu'une activation ait eu lieu sans touche envoyée par le test. Avec le code lu, c'est
impossible sans un événement clavier. **Hypothèse principale (H1)** : sur la Freebox, un événement « Entrée » ou
« select » parvient à Flutter après un lancement par intent `VIEW`. Il pourrait venir de l'IME Freebox, du lanceur, du
CEC, ou d'une touche OK restée « enfoncée » côté Flutter après les injections précédentes. Cet événement active
l'élément focalisé, et le premier élément du salon a l'`autofocus` (« Créer un salon », `watch_together_screen.dart`
l. 181). **H2** : il reste quelque chose d'autre côté appareil (session de télécommande compagnon, autre client) qui
pilote l'interface. Aucune de ces deux hypothèses n'est démontrée. La Freebox était injoignable en adb pendant
l'analyse (`Operation timed out`, ping sans réponse).

### Rangées de l'écran d'accueil Android TV (CA5)

Elles passent par le même mécanisme. `WatchNextProvider.kt` l. 743-745 construit
`popkino://play?content_id=plezy_<serveur>_<id>`. Ce lien est relu par `PlayTarget._parse` (branche `content_id`) et
`SystemShelfService.parseContentId` (`lib/services/system_shelf_service.dart` l. 381). Elles se comportent donc
comme le lien manuel : correctes sur Fire TV, à vérifier sur Freebox dans T1.

## Décisions

- **Pas de correctif de production tant que T1 n'a pas identifié la source de l'activation.** Un correctif
  « défensif » (par exemple ignorer les touches pendant N secondes après un lien) masquerait un défaut d'appareil et
  modifierait des fichiers upstream sans preuve.
- **Tests de non-régression du contrat du lien, dans `test/fork/`** (D2, D13). Ils figent le comportement vérifié sur
  la Fire TV, pour que toute future régression réelle (renommage de schéma, fusion upstream) soit attrapée en CI.
- **Le protocole de test sur TV change** : plus d'`input keyevent` dans les 30 s qui suivent un `am start` de lien,
  et toujours un logcat. Ce point relève de la méthode, pas du code (voir Risques).

## Tâches

### T1 — Reproduction instrumentée sur la Freebox (aucun code commité)
- Complexité : M (diagnostic sur appareil, sans code)
- Dépend de : —
- Fichiers : aucun dans le dépôt. Résultats à consigner dans `docs/technique/lien-lecture-regarder-ensemble/diagnostic.md`.
- À faire (Freebox `192.168.1.132:5555`, build `main` armv7 signée debug) :
  1. `adb logcat -c`, puis lancer en arrière-plan `adb logcat -v time > logcat.txt` et
     `adb shell getevent -lt > getevent.txt` (touches matérielles et CEC).
  2. `adb shell am force-stop io.github.adrien24.popkino`, puis
     `adb shell "am start -W -a android.intent.action.VIEW -d 'popkino://play?server=ceaf682febfbec1d59d978c5338dc71dee9ed91b&id=16298'"`.
     **Aucun `input keyevent`**, ne pas toucher la télécommande. Capture d'écran à 5 s, 15 s et 30 s.
  3. Juste après : `adb shell dumpsys input | grep -A30 "RecentQueue\|Last.*Event"` et `adb shell dumpsys input_method`
     pour l'IME actif et sa connexion.
  4. Recommencer à chaud (lancement par le lanceur, attente de 15 s, puis lien), puis depuis une rangée de l'accueil
     Android TV (CA5).
  5. Si un salon apparaît : chercher dans `logcat.txt` la ligne `Deep link: PlayLink` (la remise du lien), les lignes
     `WatchTogether`, et tout `KeyEvent` entre les deux. Recompiler une build **locale** avec
     `TEXT_INPUT_DIAGNOSTICS_ENABLED = true` (`PlezyActivity.kt` l. 63, à ne pas commiter) : elle trace `ENTER`, `DPAD_CENTER`
     et leur périphérique d'origine (`describeDevice`).
  6. Comparer avec la Fire TV (même protocole), qui sert de témoin.
- Issue :
  - Si aucun salon n'apparaît sans touche injectée, le ticket est clos comme « artefact de test ». Garder seulement T2.
  - Si un événement clavier est identifié (IME, CEC, touche restée enfoncée), écrire T3 précisément : source,
    périphérique, code de touche. L'architecte-plateforme doit alors relire T3, car le correctif sera probablement
    natif.
- Tests : sans objet (diagnostic).
- Critères d'acceptation couverts : CA1, CA2, CA3, CA5 (constat).

### T2 — Tests de non-régression du lien `popkino://play`
- Complexité : S
- Dépend de : —
- Fichiers : créer `test/fork/deep_link_play_link_test.dart`
- À faire : tests purement Dart, sans modifier le code de production. S'inspirer de
  `test/services/deep_links/deep_link_service_test.dart` (`DeepLinkService.forTesting`, `DeepLinkSession`, faux
  `DeepLinkProfileHost`). Construire les URL avec `ForkIdentity.urlScheme`, jamais avec la chaîne `'popkino'` en dur
  (convention « constantes par leur nom »).
  1. `DeepLink.tryParse('${ForkIdentity.urlScheme}://play?server=ceaf…&id=16298')` renvoie un `PlayLink` dont la
     `target` vaut `ItemPlayTarget(serverId: ServerId('ceaf…'), itemId: '16298')` et dont `mode` vaut `PlayMode.next`.
  2. Le même lien sans `id` (`…play?server=ceaf…`) renvoie `null`.
  3. Le lien d'une rangée d'accueil, `…://play?content_id=plezy_<server>_16298`, renvoie le même `ItemPlayTarget`
     (contrat partagé avec `WatchNextProvider.kt`).
  4. Service : `service.receive(<lien complet>)` avec une session attachée et un hôte au bon profil. La session
     reçoit **exactement un** lien, de type `PlayLink`, et `report` n'est pas appelé.
  5. Service : `service.receive(<lien sans id>)`. Aucun lien n'est remis à la session, et `report` reçoit
     `t.deepLinks.invalid` (le lien invalide reste sur l'écran courant, CA3).
  6. Garde statique : le fichier `lib/services/deep_links/deep_link_launcher.dart` ne référence pas
     `watch_together` (lecture du fichier source, comme `fork_update_hooks_guard_test.dart`). Ce test échouera si
     une fusion upstream ou un changement du fork branche un lien sur Regarder ensemble.
- Tests : `scripts/run_tests.sh test/fork/deep_link_play_link_test.dart`, puis
  `scripts/run_tests.sh test/services/deep_links/`.
- Critères d'acceptation couverts : CA1, CA2, CA3 (contrat Dart), CA5 (contrat `content_id`).

### T3 — Correctif de la source d'activation (conditionnel, à préciser après T1)
- Complexité : L (probablement natif ou lié à la saisie TV)
- Dépend de : T1
- Fichiers : à déterminer par T1. Piste la plus probable : `android/app/src/main/kotlin/com/edde746/plezy/PlezyActivity.kt`
  (`consumeLeakedImeNavigationKey`, `installTextEditorProxy`) ou un fichier du fork sous
  `android/app/src/main/kotlin/com/edde746/plezy/fork/` (D14), avec `// FORK:`.
- À faire : rédigé seulement si T1 montre un événement parasite. Ce correctif devra s'accompagner d'un test (Kotlin
  sous `android/app/src/test/` ou Dart) qui rejoue l'événement observé.
- Critères d'acceptation couverts : CA1, CA2, CA3.

**Test qui « aurait attrapé le bug »** : tel que le bug est observable aujourd'hui, il ne vient d'aucun code Dart ou
Kotlin du dépôt, et aucun test unitaire ne pouvait l'attraper. Ce qui l'aurait évité, c'est le protocole (pas de
touche injectée après le lien, logcat systématique). T2 verrouille le contrat. T3, s'il existe, apportera le test
qui rejoue l'événement fautif.

## Vérification globale

```bash
export PATH="$HOME/development/flutter-3.47.1/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
dart format test/fork/deep_link_play_link_test.dart
dart run scripts/checks/check_analyzer.dart
scripts/run_tests.sh test/fork/deep_link_play_link_test.dart
scripts/run_tests.sh test/services/deep_links/
```

Sur TV, sans toucher la télécommande ni envoyer de touche pendant 30 s, avec `adb logcat` actif :
- Fire TV (témoin) et Freebox, à froid puis à chaud :
  `adb shell "am start -a android.intent.action.VIEW -d 'popkino://play?server=<machineId>&id=<ratingKey>'"`.
  On attend la lecture de l'épisode et la ligne `Deep link: PlayLink` dans le logcat (CA1, CA2).
- Lien sans `id` : message « lien invalide », l'app reste sur l'accueil (CA3).
- Créer un salon, puis rejoindre par code depuis l'autre TV (CA4, non touché par ce plan).
- Choisir un titre dans la rangée Popkino de l'accueil Android TV (CA5).

## Risques restants

- **Freebox injoignable pendant l'analyse** : la cause des deux observations à froid reste une hypothèse (H1/H2).
  Si T1 reproduit le problème sans touche injectée, il s'agit d'un vrai défaut, propre à la Freebox, qui touche toute
  activation au focus. Il dépasse alors le cas des liens.
- **Protocole de test** : les scripts d'automatisation (`fb.sh`) envoient `DPAD_CENTER` à l'aveugle. Sur l'accueil,
  le focus peut être dans la barre d'actions, à côté de l'icône Regarder ensemble. À proscrire après un lien.
- **Message du signalement** : le cas « `&` mal échappé » ne retirait sans doute pas `id` (voir §3.3). Ne pas en
  tirer de conclusion sur l'analyse du lien.
