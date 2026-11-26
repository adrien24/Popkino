# Proposition app — sous-titres-mal-etiquetes

Auteur : architecte-app (pilote) · 2026-11-26 · Phase 1 (rédigée sans lire la proposition plateforme)
Spec : `docs/produit/specs/sous-titres-mal-etiquetes.md`. Elle prolonge `langues-preferees` (commit `cc990ad3b`).
À implémenter **après** `meilleure-piste-audio`, qui touche le même fichier `lib/fork/preferred_languages.dart`.

## Compréhension de la spec

Quand le titre d'une piste de sous-titres nomme clairement une langue, cette langue remplace celle qui est indiquée
dans le fichier, pour le **choix automatique** seulement. Exemple : Green Lantern, « French Complet » et
« French Forced » indiqués anglais. Si les deux sources disent la même chose (CA7), la piste bien étiquetée est
préférée. Les libellés affichés ne changent pas (CA8).

Critères de mon périmètre : tous, car tout est en Dart. Il n'y a rien côté natif.

## Existant

- **Choix automatique des sous-titres** : `forkPreferredSubtitle` dans `lib/fork/preferred_languages.dart`. La fonction
  locale `inSubtitleLanguage(t)` compare `t.language` (la langue indiquée) à la langue préférée, par
  `service.languageMatches`. Ce prédicat sert à `forced()`, à `full()` et au test S3 (« une piste de la langue est
  annoncée mais pas encore arrivée », sur `plexMediaInfo.subtitleTracks`).
- **Pistes vues par la règle** :
  - **descripteurs `source:` du resolver** (`PlaybackSubtitleResolver.subtitleTrackForSource`) :
    - leur `language` est `languageCode ?? language` ;
    - leur `title` est `sourceTrack.title ?? playable?.title ?? sourceTrack.displayTitle ?? sourceTrack.language`.
      Sans titre propre, c'est donc le titre d'affichage du serveur (« English (SRT) »), généré à partir de la langue
      indiquée ;
  - **pistes natives mpv** : titre et langue du conteneur ;
  - **lignes serveur** (`MediaSubtitleTrack`) : il y a `title` (titre propre du flux) et `displayTitle` (généré).
- **Pistes « forcées »** : `effectiveForced` (`lib/utils/subtitle_forced_semantics.dart`) lit déjà le titre
  (`titleSaysForced`, mot `FORCED`), donc « French Forced » est bien une piste forcée. CA2 repose dessus.
- **Correspondance des codes** : `languageMatches` accepte 639-1, 639-2/B et 639-2/T (`fr`, `fre`, `fra`).
- **Report à l'épisode suivant** : l'intention (`SubtitleIntent`) garde la langue **indiquée** et le titre. Sur
  l'épisode suivant, `findNativeTrackForIntent` impose la langue indiquée. Une intention « eng / French Complet »
  refuse une vraie piste française, et la règle du fork reprend la main. C'est acceptable et sans effet de bord.

## Approche proposée

Tout se passe dans les fichiers du fork. **Aucun fichier upstream n'est modifié.**

### 1. Langue déduite du titre — `lib/fork/subtitle_title_language.dart` (nouveau)

```dart
/// ISO 639-2 code named by [title], or null when the title names no language or several.
String? forkLanguageNamedByTitle(String? title);
```

- **Découpage** : le titre est mis en minuscules, les accents sont retirés (`français` → `francais`), puis il est
  découpé sur tout ce qui n'est pas une lettre. On obtient des **mots entiers**, jamais des sous-chaînes : « FRE » ne
  doit pas être trouvé dans « Freedom ».
- **Deux niveaux de mots**, pour éviter les faux positifs des codes courts. Un exemple : dans « Sous-titres en
  français », « en » est un mot français, pas le code de l'anglais.
  - **forts** : noms et marqueurs.
    - français : `french`, `francais`, `vf`, `vff`, `vfq`, `vfi`, `vostfr`, `truefrench` ;
    - anglais : `english`, `anglais`.
  - **faibles** : codes.
    - français : `fr`, `fre`, `fra` ;
    - anglais : `en`, `eng`.
- **Règle** :
  - si les mots forts désignent **exactement une** langue, c'est elle ;
  - sinon, si aucun mot fort n'est présent et que les mots faibles désignent exactement une langue, c'est elle ;
  - sinon (aucune langue, ou plusieurs comme dans « English / French »), `null`.

  `vo` et `vost` ne désignent aucune langue (CA4).
- La table est une constante du fichier, facile à étendre à d'autres langues plus tard (Q1).

### 2. Langue effective dans la règle (fichier du fork)

Dans `forkPreferredSubtitle` :
- la **langue effective** de la piste vaut `forkLanguageNamedByTitle(t.title) ?? t.language`, et
  `inSubtitleLanguage(t)` la compare à la langue préférée. Le titre l'emporte sur la langue indiquée, y compris
  quand celle-ci est renseignée (décision de l'utilisateur) :
  - CA1 : « French Complet » (eng) devient français ;
  - CA3 : le vrai « English » (eng) reste anglais ;
  - CA5 : titre et langue concordants, rien ne change ;
  - CA6 : sans titre ou titre neutre, la langue indiquée seule compte, comme aujourd'hui ;
- **les pistes bien étiquetées passent d'abord (CA7)**. Avant `forced()` et `full()`, les candidates sont triées de
  façon stable :
  1. langue **indiquée** égale à la langue préférée ;
  2. langue tirée du titre seulement.

  Les règles existantes (`isDefault`, puis la première) s'appliquent ensuite dans chaque groupe ;
- **S3** : pour les lignes serveur, on utilise `forkLanguageNamedByTitle(row.title) ?? (row.languageCode ??
  row.language)`. On prend bien `row.title` et **jamais** `displayTitle`, qui est généré à partir de la langue
  indiquée et masquerait l'erreur d'étiquetage.

Pour un descripteur `source:` sans titre propre, le titre vaut `displayTitle` (« English (SRT) »). Il concorde avec
la langue indiquée, donc le résultat est le même qu'aujourd'hui (CA6).

Le crochet de `TrackSelectionService` et la correspondance de la piste choisie avec la piste native ne changent pas.
La correspondance se fait par identité de source (`source:<id>`) ou par la langue indiquée **des deux côtés**, qui
est la même : on ne touche pas aux métadonnées des pistes (CA8).

### 3. Hors de la règle du fork

L'upstream (Jellyfin, priorité 3 `_selectSubtitleTrackByProfile`) continue d'utiliser la langue indiquée quand la
règle du fork ne s'applique pas, par exemple avec « Choisir l'audio par langue » désactivé (S1). C'est voulu : CA8 de
`langues-preferees` garantit qu'on ne change rien pour qui n'a pas choisi de langue.

### Tests (`test/fork/`)

- `subtitle_title_language_test.dart` :
  - chaque mot de CA4, en majuscules et en minuscules ;
  - « Sous-titres en français » → fr ;
  - « English / French » → `null` ;
  - « VO » → `null` ;
  - « Freedom » → `null` ;
  - « VOSTFR » → fr ;
  - `null` ou vide → `null`.
- `preferred_languages_test.dart`, à compléter :
  - Green Lantern (French Complet / French Forced indiqués eng + English eng) :
    - audio anglais → French Complet (CA1) ;
    - audio français → French Forced (CA2) ;
    - le vrai anglais n'est jamais pris (CA3) ;
  - français bien étiqueté et « French » mal étiqueté → le premier (CA7) ;
  - pas de titre (CA6) ;
  - S3 avec une ligne serveur dont seul le `title` dit « French ».
- `preferred_languages_flow_test.dart` : JSON Plex (`Part.Stream[]`, `title` et `languageCode`) et Jellyfin
  (`MediaStreams`, `Title` et `Language`) pour Green Lantern (CA9), avec `PlaybackSubtitleResolver.resolve`. Vérifier
  `primarySourceStreamId` et que le libellé d'origine du descripteur est conservé (CA8).

### Découpage pressenti

- T1 (S) : `subtitle_title_language.dart` et ses tests (fonction pure).
- T2 (M, dépend de T1 et de la fin de `meilleure-piste-audio`) : intégration dans `forkPreferredSubtitle` (langue
  effective, tri CA7, S3) et tests de parcours.
- T3 : recette de Green Lantern sur la Fire Stick.

## Alternatives écartées

1. **Corriger la langue dans les mappers** (`plex_mappers`, `jellyfin_media_info_mapper`). Cela toucherait des fichiers
   upstream, changerait les libellés et la correspondance des pistes partout (CA8), et ferait diverger aussi l'aperçu,
   le menu et le report. Le diff est trop large pour un besoin de choix automatique.
2. **Recherche de sous-chaînes ou expression régulière libre** (« fr » dans le titre). Faux positifs garantis
   (« Freedom », « en » dans un titre français).
3. **Utiliser `TrackLabelBuilder` ou les noms de toutes les langues de `lib/data/iso_639_data.dart`**. C'est tentant
   pour la couverture, mais les codes de 2 lettres (« de », « it », « es ») sont aussi des mots courants. Le risque de
   faux positifs n'est pas maîtrisé sans une table de mots forts par langue. Repoussé (Q1).

## Impact

- **Fichiers upstream modifiés** : aucun.
- **Nouveaux fichiers** :
  - `lib/fork/subtitle_title_language.dart` ;
  - `test/fork/subtitle_title_language_test.dart`.
- **Fichiers du fork modifiés** : `lib/fork/preferred_languages.dart` et ses tests. C'est le même fichier que
  `meilleure-piste-audio`, donc la tâche vient après.
- **Dépendances** : aucune.
- **Risques** :
  - *Faux positif* : un titre qui nomme une langue sans parler de la piste. Le cas est rare, et la règle des deux
    niveaux et des mots entiers le limite. L'effet est au pire celui d'aujourd'hui inversé : des sous-titres d'une
    autre langue affichés, que l'on corrige à la main.
  - *Langues non couvertes* : seuls le français et l'anglais sont reconnus (CA4 : « au moins »). Une langue préférée
    autre (par exemple l'espagnol) garde le comportement d'aujourd'hui.
  - *Report d'épisode* : un choix manuel d'une piste mal étiquetée garde la langue indiquée dans l'intention. Sur
    l'épisode suivant, la piste bien étiquetée en français n'est pas reprise par le report, mais la règle du fork la
    choisit quand même. Aucun effet visible attendu, à vérifier en recette si possible.
  - *Fusions* : aucune ligne upstream.

## QUESTIONS PRODUIT

- **Q1 — Autres langues.** Faut-il reconnaître, dès cette version, les titres d'autres langues (par exemple « Español »,
  « Deutsch », « Italiano ») ? Recommandation : non. On s'en tient au français et à l'anglais demandés par CA4, la
  table pouvant être étendue plus tard sans changement d'architecture.
