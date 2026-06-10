#!/bin/zsh
# Build Voice.dmg — the themed single-file installer (design: voice.pen).
# Renders the background art, then lays out the volume with dmgbuild
# (background image, icon positions, drag-to-Applications).
set -e
cd "$(dirname "$0")/.."

[ -d Voice.app ] || { echo "Voice.app not built — run app/bundle.sh first"; exit 1; }

PY=.venv/bin/python
"$PY" scripts/render_dmg_bg.py
rm -f Voice.dmg
"$PY" -m dmgbuild -s scripts/dmg_settings.py "Voice" Voice.dmg
ls -lh Voice.dmg
