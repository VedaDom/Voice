#!/bin/zsh
# Build the self-contained Python runtime that ships inside Voice.app.
# Uses a relocatable python-build-standalone CPython (same builds uv manages),
# installs the engine deps into it, and precompiles bytecode so the bundle
# works read-only (App Translocation).
set -e
cd "$(dirname "$0")"

RUNTIME=runtime/python
PYVER=3.12

if [ -x "$RUNTIME/bin/python3" ]; then
    echo "runtime already present: $($RUNTIME/bin/python3 --version)"
else
    rm -rf runtime && mkdir -p runtime
    # Prefer a uv-managed standalone python (relocatable build) if available
    SRC=$(ls -d "$HOME/.local/share/uv/python/cpython-$PYVER".*-macos-aarch64-none 2>/dev/null | sort -V | tail -1)
    if [ -n "$SRC" ]; then
        echo "copying uv-managed standalone python: $SRC"
        cp -R "$SRC" "$RUNTIME"
    else
        echo "downloading python-build-standalone…"
        URL=$(curl -s https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest \
            | grep browser_download_url \
            | grep "cpython-$PYVER" \
            | grep "aarch64-apple-darwin-install_only.tar.gz\"" \
            | head -1 | cut -d'"' -f4)
        [ -n "$URL" ] || { echo "could not resolve standalone python URL"; exit 1; }
        curl -sL "$URL" -o runtime/python.tar.gz
        tar -xzf runtime/python.tar.gz -C runtime
        rm runtime/python.tar.gz
    fi
    # our private copy is no longer uv-managed
    rm -f "$RUNTIME"/lib/python*/EXTERNALLY-MANAGED
    "$RUNTIME/bin/python3" --version
fi

echo "installing engine dependencies…"
# mlx-lm is pinned to a git SHA until Gemma-4 E-series support ships in a
# PyPI release (needed by the "best"/"max" cleanup tiers)
uv pip install --python "$RUNTIME/bin/python3" --no-cache \
    "git+https://github.com/Blaizzy/mlx-audio.git" soundfile numpy \
    "mlx-lm @ git+https://github.com/ml-explore/mlx-lm@c89c93c33db9b213de9abcfff57c89ed2817a361"

echo "precompiling bytecode (read-only bundles)…"
"$RUNTIME/bin/python3" -m compileall -q "$RUNTIME/lib" 2>/dev/null || true

echo "pruning…"
rm -rf "$RUNTIME"/lib/python*/test "$RUNTIME"/lib/python*/idlelib \
       "$RUNTIME"/lib/python*/tkinter "$RUNTIME"/share 2>/dev/null || true

du -sh runtime
echo "runtime ready."
