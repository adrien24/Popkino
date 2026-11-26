# Fusionner les nouveautés de l'upstream (Plezy)

Préparation, une seule fois par clone : `bash scripts/fork/setup_merge.sh` (active le pilote `merge=ours` qui protège
`README.md` et `NOTICE.md`).

## Procédure

```bash
git fetch upstream && git merge upstream/main
```

## Conflits attendus

- Lignes marquées `FORK:` : garder notre version, reprendre à la main les changements upstream autour.
- `version:` du `pubspec.yaml` : garder la nôtre.
- Images (icônes, bannières, logos) : garder les nôtres, puis régénérer :
  `python3 scripts/fork/generate_brand_assets.py`.
- Traductions :

  ```bash
  git checkout --theirs -- lib/i18n/*.i18n.json lib/i18n/*.g.dart \
    && python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh
  ```

## Vérifications après la fusion

```bash
bash scripts/ci_guard_checks.sh
scripts/run_tests.sh test/fork/
scripts/run_tests.sh            # toute la suite
```

Puis construire l'APK (cf. skill `conventions-code`, section Build Android) et le tester sur la TV.
