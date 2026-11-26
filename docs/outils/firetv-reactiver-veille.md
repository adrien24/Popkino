# Fire TV : réactiver la veille et le HDMI-CEC

Le 26/11/2026, la Fire TV de test (`AFTMA08C15`, Fire TV 4K Max, Android 11, `192.168.1.173`) a été réglée pour ne
jamais s'éteindre (développement / tests). Ce document permet de revenir aux réglages d'origine.

## Ce qui a été modifié

| Réglage | Valeur d'origine | Valeur actuelle |
|---|---|---|
| `system screen_off_timeout` (extinction écran) | `300000` (5 min) | `2147483647` (jamais) |
| `secure sleep_timeout` (mise en veille) | `1200000` (20 min) | `-1` (jamais) |
| `secure screensaver_enabled` | `0` | `0` (inchangé) |
| `secure screensaver_activate_on_sleep` | `1` | `0` |
| `global stay_on_while_plugged_in` | `0` | `7` (toujours allumée sur secteur) |
| `global hdmi_control_enabled` (HDMI-CEC) | `1` | `0` |
| `secure block_cec_standby` | `0` | `1` |

## Tout réactiver (copier-coller dans un terminal)

```sh
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB connect 192.168.1.173:5555
D=(-s 192.168.1.173:5555)
$ADB "${D[@]}" shell settings put system screen_off_timeout 300000
$ADB "${D[@]}" shell settings put secure sleep_timeout 1200000
$ADB "${D[@]}" shell settings put secure screensaver_activate_on_sleep 1
$ADB "${D[@]}" shell settings put global stay_on_while_plugged_in 0
$ADB "${D[@]}" shell settings put global hdmi_control_enabled 1
$ADB "${D[@]}" shell settings put secure block_cec_standby 0
```

## Vérifier

```sh
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB -s 192.168.1.173:5555 shell dumpsys power | grep -iE "mStayOn=|mScreenOffTimeoutSetting|mSleepTimeoutSetting"
$ADB -s 192.168.1.173:5555 shell settings get global hdmi_control_enabled
```

Attendu : `mStayOn=false`, `mScreenOffTimeoutSetting=300000`, `mSleepTimeoutSetting=1200000`, puis `1`.

Si l'adresse IP de la Fire TV a changé : `$ADB mdns services` ou Paramètres > Ma Fire TV > À propos > Réseau.
Redémarrer la Fire TV après le retour en arrière est conseillé pour que le HDMI-CEC se réinitialise proprement.
