#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")"
echo "==================================================="
echo "            AlphaSteg 0.5 Server"
echo "==================================================="
echo ""
if [ ! -f .venv/bin/activate ]; then
    echo "Virtual environment not found. Please run the installer first."
    exit 1
fi
# Prefer portable FFmpeg binaries in the app folder if present
export PATH="$PWD:$PATH"
source .venv/bin/activate
python main.py
