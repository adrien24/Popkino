#!/usr/bin/env bash
# One-time setup per clone: register the "ours" merge driver used by .gitattributes
# (README.md and NOTICE.md are ours). The driver `true` always succeeds and keeps our
# version of the file, so merging upstream/main never overwrites them.
set -euo pipefail
git config merge.ours.driver true
echo "merge.ours.driver configured."
