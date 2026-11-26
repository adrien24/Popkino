# Proposition plateforme — meilleure-piste-audio

Auteur : architecte-plateforme · 2026-11-26 · Phase 1 (rédigée sans lire la proposition app)
Spec : `docs/produit/specs/meilleure-piste-audio.md` · Prolonge `langues-preferees` (commit `cc990ad3b`)

## Compréhension de la spec

Parmi les pistes dans la langue audio préférée, l'app doit choisir la stéréo quand le son ne sort qu'en stéréo
(télévision seule, ou « Canaux audio » = Stéréo), et la piste qui a le plus de canaux quand l'installation sait la
restituer. Si l'app ne peut pas savoir ce que restitue l'installation, la piste reste celle d'aujourd'hui (CA3bis).

Critères dans mon périmètre :
- **CA1, CA2, CA3bis** : peut-on détecter de façon fiable ce que restitue l'installation sur Android et Fire OS ?
- **CA2** : « le son sort » avec une piste DTS, donc la question de la transmission audio directe (passthrough).
- **CA3** : lien avec le réglage existant « Canaux audio ».
- **CA9** : choisir la 5.1 ne doit jamais déclencher de transcodage vidéo.
- Le coût sur la Fire Stick.

## Existant

### Réglages audio déjà présents
- `SettingsService.audioChannelLimit` (`settings_service.dart` l.905, enum `AudioChannelLimit` dans
  `lib/models/audio_channel_limit.dart`) propose `original` (par défaut), `surround51` et `stereo`. Sur mpv, il
  règle `audio-channels` (`player_base.dart` l.1411-1450) : `auto-safe`, `stereo,5.1` ou `stereo`. Sur ExoPlayer,
  `surround51` se comporte comme `original` (`onExoPlayer`). Il est appliqué à l'ouverture
  (`video_player_screen.dart` l.2179-2186). Avec « Stéréo », mpv vide `audio-spdif`, donc tout est décodé puis
  réduit à deux canaux. Avec « Jusqu'à 5.1 », la transmission directe n'est pas touchée.
- `SettingsService.audioPassthrough` (l.490-509) est activé par défaut sur Android TV. Sur mpv, la liste
  `audio-spdif` vient d'une sonde de la sortie audio : `supportedMpvSpdifCodecs(context)`
  (`exoplayer/AudioOutputPolicy.kt` l.195, appelée par `MpvPlayerPlugin.getAudioSpdifCodecs`). Elle s'appuie sur
  `AudioCapabilities` de media3 et `AudioTrack.isDirectPlaybackSupported` (API 29-32). Les commentaires upstream
  (#1458, #1703) le notent : quand la sortie annonce à tort un format, `ao_audiotrack` échoue sans repli, et on
  obtient un silence.

### Mesures sur la Fire Stick de l'utilisateur (adb, lecture seule, 2026-11-26)

Matériel : AFTMA08C15, Android 11 (API 30), `armeabi-v7a`, branchée sur un téléviseur **LG**
(identifiant CEC `0x00E091`) **sans** barre de son ni ampli. L'utilisateur l'a confirmé.

| Source | Valeur | Ce qu'elle laisse croire |
|---|---|---|
| Diffusion persistante `HDMI_AUDIO_PLUG` | `MAX_CHANNEL_COUNT=8`, `ENCODINGS=[2,4,5,6,18,7,8,13,17]` (PCM, AC3, E-AC3, E-AC3-JOC/Atmos, DTS, DTS-HD, IEC61937, AC4) | « 7.1 et Dolby Atmos disponibles » |
| `dumpsys media.audio_policy`, appareil `HDMI-Out` | PCM : masque `0x0003` (stéréo) uniquement. AC3, E-AC3, DTS : jusqu'à `0x003f` (5.1) et `0x063f` (7.1) | PCM stéréo seulement, formats compressés 5.1 et 7.1 acceptés |
| `settings global` | `surround_sound_supported=1`, `firetv_hdmi_dolby_passthrough_available=1`, `audio_platform_capabilities.atmos.enabled=true`, `encoded_surround_output=0` (auto), `external_surround_sound_enabled=0` | Dolby et Atmos disponibles |
| `settings secure` | `amazon_settings_audio_format_compressed_pref=3` | Réglage Fire OS non documenté |
| `dumpsys hdmi_control` | Aucun système audio CEC (adresse logique 5) sur le bus | Pas d'ampli CEC (API système, inaccessible à une app) |

**Conclusion : on ne peut pas détecter de façon fiable une installation « stéréo seulement ».** Un téléviseur
annonce les formats Dolby et DTS en 5.1 ou 7.1 parce qu'il les **décode lui-même** pour les réduire sur ses
haut-parleurs. Les deux signaux publics qu'utilisent media3 et la sonde mpv actuelle répondent « 8 canaux » ici.
- Le seul signal distinctif est le **PCM multicanal**. Il vaut 2 canaux ici, mais il vaut aussi 2 canaux avec une
  barre de son reliée en ARC, qui est le cas le plus courant de « barre de son 5.1 ». En ARC, la Fire Stick voit le
  téléviseur, pas la barre de son.
- Seul un ampli **branché entre** la Fire Stick et le téléviseur annonce du PCM 6 ou 8 canaux.
- De plus, sur API 30, l'API publique ne donne pas les canaux PCM séparément des formats compressés :
  `AudioDeviceInfo.getAudioProfiles()` n'existe qu'à partir de l'API 31. Il faudrait sonder avec
  `AudioTrack.isDirectPlaybackSupported(PCM 5.1)`, en Kotlin.
- `external_surround_sound_enabled` ne concerne que les téléviseurs Fire TV Edition (guide Dolby d'Amazon).
  `amazon_settings_audio_format_compressed_pref` n'est pas documenté.

Il faut donc s'en tenir au repli que prévoit la spec : le réglage « Canaux audio ».

### CA9 : le choix de piste ne déclenche jamais de transcodage vidéo, c'est structurel
- **Plex.** La décision « lecture directe ou transcodage » est prise par le client
  (`plex_client.dart` l.3809-3812) à partir de trois choses seulement : le **codec vidéo** refusé dans les réglages
  (`_sourceCodecRefused`, l.3937-3942), `forceTranscode` et le préréglage de qualité. La piste audio n'y entre jamais.
  En lecture directe, le changement de piste se fait dans mpv (`aid`), sans le serveur.
- **Jellyfin.** Le profil de lecture directe ne restreint pas les codecs audio (« an omitted list means any codec »,
  `jellyfin_client/parts/playback.dart` l.983). Un `AudioStreamIndex` pointant vers du DTS ou du TrueHD ne fait donc
  pas perdre la lecture directe. En transcodage déjà décidé, le conteneur fMP4 accepte
  `aac,mp3,ac3,eac3,flac,opus,dts,truehd` (l.945), ce qui permet de copier l'audio. TS exclut TrueHD : le serveur
  réencode alors l'audio seulement.
- Conséquence : CA9 ne demande aucun code. Il demande un test qui le verrouille.

## Approche proposée

### P1 — Aucune détection automatique, aucune modification native

La décision repose sur « Canaux audio », lu en Dart (`SettingsService.audioChannelLimit`) par la règle du fork
(`lib/fork/preferred_languages.dart`, déjà accrochée à `selectAudioTrack`). Pas de Kotlin, pas de canal de méthode,
pas de permission. Comme D7 le demande, le comportement est le même sur GitHub et sur Play.

Correspondance proposée, à trancher par le PO (QUESTION 1) :

| « Canaux audio » | Parmi les pistes dans la langue préférée |
|---|---|
| Stéréo | la piste stéréo (2 canaux au plus) s'il y en a une ; sinon la règle actuelle (CA3) |
| Jusqu'à 5.1 | la piste qui a le plus de canaux. mpv réduit déjà la 7.1 en 5.1 (`stereo,5.1`) |
| D'origine | **comportement actuel** (CA3bis), puisque l'installation est inconnue. C'est ce qui donne CA1 pour l'utilisateur : English 2.0 est la première piste sur les deux fichiers de la spec |

À nombre de canaux égal, l'ordre actuel départage les pistes : `isDefault`, puis la première (CA5). Le nombre de
canaux est lu sur `AudioTrack.channels` côté mpv (`lib/mpv/models.dart` l.112) et sur `MediaAudioTrack.channels`
côté serveur. Quand le nombre est inconnu (`null`), la piste ne compte ni comme stéréo ni comme multicanal.

### P2 — La décision doit être la même avant et après l'ouverture

Comme dans `langues-preferees`, l'aperçu de la fiche et le resolver passent par la même règle. Pour l'intention de
lancement (`forkLaunchAudioIntent`, qui ne sert qu'au transcodage), deux options :
- **(a)** ne rien changer : en transcodage, le serveur garde sa piste quand plusieurs pistes anglaises existent (risque
  déjà accepté dans `langues-preferees`) ;
- **(b)** ajouter le nombre de canaux visé à l'intention (`AudioTrack.channels`). `findSourceAudioTrackForIntent`
  l'utilise déjà pour départager les pistes (`extraScore` sur `channels`). Elle **lèverait l'ambiguïté** « deux pistes
  anglaises » laissée ouverte par `langues-preferees`, sans risque pour CA9 (voir Existant).

Je recommande **(b)** quand « Canaux audio » vaut Stéréo ou Jusqu'à 5.1. Avec D'origine, on ne vise aucun nombre de
canaux, donc on garde (a). L'architecte-app arbitre le mécanisme.

### P3 — Transmission directe et silence (CA2)

Choisir la 5.1 plus souvent veut dire envoyer plus souvent du DTS ou de l'E-AC3 en transmission directe à la sortie
HDMI. Sur la Fire Stick mesurée, la sonde `supportedMpvSpdifCodecs` accepte DTS et DTS-HD, car le téléviseur les
annonce. Si un maillon de la chaîne ment (barre de son en ARC sans DTS), on obtient le silence déjà connu de
l'upstream (#1458, #1703). La fonctionnalité ne crée pas ce défaut, mais elle l'expose davantage. Elle ne peut rien
détecter de plus que la sonde actuelle.
- Pas de correctif dans cette fonctionnalité.
- La recette doit vérifier « le son sort » sur Green Lantern (DTS 5.1), avec « Jusqu'à 5.1 » et la transmission
  directe activée, sur le téléviseur de l'utilisateur.
- Le texte de « Transmission audio directe » reste le recours en cas de silence (QUESTION 2).

### P4 — Coût sur la Fire Stick

La règle se limite à comparer des nombres de canaux sur quelques pistes : négligeable. Côté décodage :
- en stéréo, piste AAC : rien de changé ;
- en 5.1 avec transmission directe : aucun décodage, le flux est relayé tel quel ;
- en 5.1 **sans** transmission directe : décodage logiciel E-AC3 ou DTS, puis réduction à deux canaux. Quelques pour
  cent de CPU sur ARMv7, déjà le cas aujourd'hui quand l'utilisateur choisit cette piste à la main.

### P5 — Recette sur la TV

- APK `armeabi-v7a`, journaux de débogage activés,
  `adb logcat -v time -s flutter | grep -E "Audio:|Fork preferred"`.
  - La ligne `Audio: … [profile]` doit nommer la piste retenue.
  - Le libellé du journal du fork doit indiquer le critère retenu (canaux visés, sinon « ordre actuel »).
- CA1 avec « D'origine », CA3 avec « Stéréo », puis « Jusqu'à 5.1 » sur S3E8 (EAC3 5.1) et Green Lantern (DTS 5.1) :
  le son doit sortir sur le téléviseur.
- Pour CA2 au sens strict (installation 5.1 réelle), l'utilisateur n'a pas le matériel. On le vérifie par les tests
  et, en recette, par « Jusqu'à 5.1 », qui simule le choix de quelqu'un qui en a une.
- CA9 :
  - Plex : la ligne de décision de l'ouverture ne doit pas mentionner de transcodage ;
  - les deux serveurs : avant et après, `GET /status/sessions` (Plex) ne doit montrer aucune session de transcodage.

## Alternatives écartées

1. **Détection par `HDMI_AUDIO_PLUG` ou `AudioCapabilities` (media3).** Écartée, mesure à l'appui : le téléviseur
   stéréo de l'utilisateur répond « 8 canaux, Atmos » et la 5.1 serait choisie à tort (CA1 échoue).
2. **Sonde du PCM multicanal** (`AudioTrack.isDirectPlaybackSupported(ENCODING_PCM_16BIT, CHANNEL_OUT_5POINT1)`,
   en Kotlin, via un canal de méthode). Écartée pour cette version :
   - elle ne détecte que l'ampli branché entre la Fire Stick et le téléviseur, et rate les barres de son en ARC, le cas
     le plus courant ;
   - elle demande du Kotlin et un canal de méthode dans un fichier upstream (`MpvPlayerPlugin.kt`, ou un nouveau
     plugin enregistré dans `PlezyActivity.kt`), donc du diff natif.

   Elle pourra compléter « D'origine » plus tard (« ampli détecté → plus de canaux »). Je ne la testerais qu'avec un
   ampli sous la main : l'utilisateur n'en a pas.
3. **Lire les réglages audio de Fire OS** (`amazon_settings_audio_format_compressed_pref`,
   `external_surround_sound_enabled`). Écartée : non documentés (le second ne vaut que pour les téléviseurs Fire TV
   Edition), et sans équivalent sur Android TV standard. Le comportement différerait d'un appareil à l'autre.
4. **Nouveau réglage dédié** (« Mon installation : télévision / 5.1 »). Écartée : la spec l'exclut et « Canaux
   audio » dit déjà la même chose.

## Impact

- **Fichiers upstream modifiés** : aucun fichier Android, natif, Gradle ou CI. Côté Dart, a priori aucun nouveau
  crochet : la règle vit dans `lib/fork/preferred_languages.dart`, déjà appelée par `selectAudioTrack`.
- **Nouveaux fichiers** : tests dans `test/fork/`, dont un test CA9 qui vérifie que la décision de transcodage Plex ne
  dépend pas de la piste audio choisie ni de l'intention, et un test Jellyfin sur le profil de lecture directe.
- **Dépendances** : aucune. **Google Play / marque** : aucun impact.
- **Risques** :
  - *Pas de détection* : quelqu'un qui a une installation 5.1 doit choisir « Jusqu'à 5.1 » pour avoir la 5.1. Ce
    n'est pas le « sans réglage à faire » de l'objectif (QUESTION 1).
  - *« Jusqu'à 5.1 » prend un second sens* : il ne limite plus seulement le PCM, il choisit aussi la piste. C'est
    cohérent, mais le texte du réglage doit le dire (QUESTION 3 ; surcouche i18n, D6).
  - *Silence en transmission directe* (P3) : défaut upstream, davantage exposé.
  - *ExoPlayer* : `surround51` y vaut `original` pour le mixage, mais le choix de piste se fait en Dart. Il
    s'appliquera donc pareil, comportement à vérifier une fois.
  - *Interaction avec la règle A2 de `langues-preferees`* : si le serveur a déjà retenu une piste dans la langue
    préférée, la règle actuelle rend la main à l'upstream. Avec « Stéréo » ou « Jusqu'à 5.1 », A2 doit aussi
    vérifier les canaux, sinon le serveur garde sa piste anglaise stéréo. C'est l'affaire de l'architecte-app, mais
    c'est le point qui ferait échouer CA2 et CA3 en recette.

## QUESTIONS PRODUIT

1. **L'app ne peut pas savoir si l'installation restitue la 5.1** (mesure sur la Fire Stick : un téléviseur seul
   annonce « 8 canaux, Dolby Atmos »). Que doit faire « D'origine », le réglage par défaut ?
   - (a) garder le choix actuel, qui donne la stéréo sur les deux fichiers de la spec (CA1 et CA3bis tenus) ; les
     possesseurs d'une installation 5.1 choisissent « Jusqu'à 5.1 ». **Recommandé.**
   - (b) préférer la 5.1, comme le suggère la note de la spec ; l'utilisateur met alors « Stéréo », et CA1 tel
     qu'écrit (avec « D'origine ») échoue.
2. **Silence possible** : si une piste 5.1 DTS ne donne aucun son sur une installation donnée, le recours est de
   désactiver « Transmission audio directe ». Faut-il le dire quelque part, par exemple dans le texte de ce réglage ?
3. **Texte de « Canaux audio »** : faut-il préciser que « Stéréo » et « Jusqu'à 5.1 » choisissent aussi la piste audio
   quand le fichier en propose plusieurs dans la même langue ?

Sources : [Dolby Integration Guidelines (Fire TV)](https://developer.amazon.com/docs/fire-tv/dolby-integration-guidelines.html),
[version chinoise du même guide](https://developer.amazon.com/zh/docs/fire-tv/dolby-integration-guidelines.html)
(`external_surround_sound_enabled` réservé aux téléviseurs Fire TV Edition).
