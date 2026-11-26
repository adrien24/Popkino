# Débat — meilleure-piste-audio

## Critique de app sur la proposition plateforme — tour 1

- ✅ D'accord :
  - **Pas de détection automatique pour cette version, et rien en natif.** La mesure est probante : la TV LG seule
    annonce 8 canaux, Atmos et DTS, et le PCM multicanal à 2 ne distingue pas une TV seule d'une barre de son en ARC.
    Je retire de ma proposition la sonde `ForkAudioRouteProbe` et le `refresh()` dans `forkLaunchAudioIntent`.
    `forkAudioOutput()` ne lit plus que « Canaux audio » :
    - Stéréo → `stereo` ;
    - Jusqu'à 5.1 → `multichannel` ;
    - D'origine → `unknown`, c'est-à-dire le choix d'aujourd'hui (CA3bis).

    C'est ta recommandation (a), qui rejoint ma Q2.
  - **P2 (b)** : l'intention de lancement porte `channels` (2 ou 6) quand le réglage vaut Stéréo ou Jusqu'à 5.1, et rien
    avec D'origine. C'est déjà prévu dans ma proposition (§3).
  - **Interaction avec A2** : c'est bien le point critique. Ma proposition l'assouplit : avec une sortie connue, A2 ne
    rend la main que si la piste du serveur est déjà celle que viserait la règle des canaux.
  - **CA9** : il est garanti par la structure (la décision de lecture directe ignore l'audio, Plex l.3809-3812 et
    Jellyfin l.983). On le verrouille par des tests Plex et Jellyfin dans `test/fork/`.
  - **P3 (silence en transmission directe)** : c'est un défaut upstream, plus exposé mais pas créé par la
    fonctionnalité. Recette de Green Lantern en DTS avec « Jusqu'à 5.1 ».
  - **P4, P5** : le journal du fork nomme le critère retenu : « channels: stereo/most/current order ».
  - **ExoPlayer** : le choix de piste se fait en Dart. `surround51` donne donc aussi `multichannel` pour le choix,
    même si le mixage d'ExoPlayer l'ignore.
- ⚠️ À amender :
  - **Les pistes de commentaire et d'audiodescription ne sont pas traitées.** Sur un fichier « English 5.1 + English
    2.0 Commentary », la règle « Stéréo » choisirait le commentaire. Proposition : les exclure de la règle des canaux
    par des mots entiers du titre (Commentary, Commentaire, Audio Description, Audiodescription, Descriptive, AD).
    Cette question produit (ma Q1) est en cours chez le PO.
  - **Pistes à nombre de canaux inconnu** : elles sont ignorées. S'il reste moins de deux candidates connues, on
    applique l'ordre actuel. Cela rejoint ta règle (« ni stéréo ni multicanal »).
  - **Textes de « Canaux audio »** (ta Q3) et de « Transmission audio directe » (ta Q2) : s'ils changent, c'est par la
    surcouche i18n (extension de D6), sans Dart, comme pour CA9 de `langues-preferees`. On attend la réponse du PO.
- ❌ Bloquant : aucun.

## Critique de plateforme sur la proposition app — tour 1

- ✅ D'accord :
  - **Trois états `stereo / multichannel / unknown`**, avec cette correspondance : « Stéréo » → `stereo`,
    « Jusqu'à 5.1 » → `multichannel`, « D'origine » → `unknown`. C'est exactement le repli que je propose.
  - **A2 assoupli seulement quand la sortie est connue**, ce qui garantit CA3bis. La spec ne précise pas le cas 7.1
    contre 5.1 ; je suis d'accord pour laisser la 7.1 l'emporter.
  - **Intention de lancement enrichie** (`channels: 2` ou `6`) : elle lève l'ambiguïté « deux pistes anglaises » en
    transcodage. CA9 reste sûr :
    - chez Plex, la décision de transcodage ne dépend que du codec **vidéo** (`plex_client.dart` l.3809-3812 et
      l.3937-3942), du préréglage de qualité et de `forceTranscode`. Aucun codec audio ne déclenche de transcodage ;
    - chez Jellyfin, le profil de lecture directe ne restreint pas les codecs audio (`playback.dart` l.983).
  - **Q1 (commentaires et audiodescription exclus)**, avec Q2 en version (a) : garder le choix d'aujourd'hui pour
    « D'origine ». Ma question produit 1 est la même, on peut les fusionner.
  - **Aucune ligne upstream ajoutée.**

- ⚠️ À amender : **supprimer la sonde native et la façade `ForkAudioRouteProbe`** (T1 en partie, T3 en entier) →
  « D'origine » donne toujours `unknown`.
  - **Mesure (adb, lecture seule) sur la Fire Stick de l'utilisateur, téléviseur LG seul.** La diffusion
    `HDMI_AUDIO_PLUG` annonce `MAX_CHANNEL_COUNT=8`, avec AC3, E-AC3, Atmos et DTS. `audio_platform_capabilities`
    annonce Atmos. Seul le PCM est limité à 2 canaux, mais c'est aussi le cas avec une barre de son en ARC. Et l'API 30
    ne donne pas le PCM à part : `getAudioProfiles` n'existe qu'à partir de l'API 31.
  - **Conséquence.** Aucune sonde sûre ne détecterait autre chose qu'un ampli branché entre la Fire Stick et le
    téléviseur. Cette sonde serait du code natif (diff dans `MpvPlayerPlugin.kt` ou `PlezyActivity.kt`) pour un cas que
    l'utilisateur ne peut pas tester.
  - **Ce qu'on y gagne.** On évite aussi un `await refresh()` à délai dans `forkLaunchAudioIntent`, donc sur le chemin
    de chaque ouverture.
  - **Si on la veut un jour**, ce sera une fonctionnalité à part : `AudioTrack.isDirectPlaybackSupported` en PCM 5.1,
    testée avec un ampli.

- ⚠️ À amender : **piste dont le nombre de canaux est inconnu**. `forkBestTrackForOutput` ignore les pistes dont
  `channels` vaut `null`, c'est bien. Il faut un test où **seule la 5.1** a un nombre de canaux connu (côté mpv,
  `demux-channel-count` peut manquer sur certains flux).
  - Attendu : en `stereo`, on rend `null` (choix d'aujourd'hui), on ne prend pas la 5.1.
  - Les candidates sont alors comptées **après** ce filtre, d'où la règle « moins de 2 candidates → `null` ».

- ⚠️ À amender : **CA2 « le son sort »**. Préférer la 5.1 envoie plus souvent du DTS ou de l'E-AC3 en transmission
  directe.
  - Sur la Fire Stick mesurée, `supportedMpvSpdifCodecs` accepte DTS et DTS-HD, parce que le téléviseur les annonce.
  - Si un maillon ment (barre de son en ARC sans DTS), on retombe sur le silence connu de l'upstream (#1458, #1703).
    La fonctionnalité ne le corrige pas, mais elle l'expose davantage.
  - À mettre dans les risques du plan, avec une étape de recette : Green Lantern DTS 5.1, « Jusqu'à 5.1 »,
    transmission directe activée, le son sort sur le téléviseur.
  - Ma question produit 2 (dire que désactiver « Transmission audio directe » est le recours) reste ouverte.

- ⚠️ À amender : **texte de « Canaux audio »**. « Jusqu'à 5.1 » prend un second sens : choisir aussi la piste
  multicanale. Comme pour CA9 de `langues-preferees`, la surcouche i18n (D6) devrait le dire. C'est ma question
  produit 3, à soumettre.

- ❌ Bloquant : aucun.

## Validation de plateforme sur plan.md — tour 1

APPROUVÉ.
- Aucune sonde native ni ligne upstream. CA9 est verrouillé par un test ou par la recette. Le risque DTS/E-AC3 est en
  recette (T5, point 3).
- Remarque non bloquante sur la vérification globale :
  - `git diff main --stat -- lib ':!lib/fork' ':!lib/i18n'` ne sera **pas** vide, car `main` ne contient pas encore
    `langues-preferees` (`cc990ad3b` n'est que sur `feat/langues-preferees`). Il listerait donc ses crochets upstream ;
  - remplacer `main` par `feat/langues-preferees` (ou `cc990ad3b`), comme le plan `sous-titres-mal-etiquetes` le fait
    avec sa branche de départ.
