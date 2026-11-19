#!/bin/bash
# Builds a fake home folder full of realistic junk, for demos, screenshots and trying
# Sweep without touching your own files:
#
#   tools/make-demo-home.sh /tmp/sweep-demo
#   SWEEP_HOME=/tmp/sweep-demo build/Sweep.app/Contents/MacOS/Sweep
#
# Large files are APFS clones of one 256 MB file, so the demo looks like several GB
# but uses about 256 MB of real disk space.
set -euo pipefail

DEMO="${1:?usage: make-demo-home.sh <folder>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$DEMO" == "$HOME" || "$DEMO" == "/" ]] && { echo "Refusing to use $DEMO"; exit 1; }
rm -rf "$DEMO"
mkdir -p "$DEMO"
cd "$DEMO"

BASE=".base"
mkfile 256m "$BASE"

# file <path> [MB]: a file of about that size (a clone of the base, or small random data).
file() {
    mkdir -p "$(dirname "$1")"
    if [[ "${2:-0}" -ge 256 ]]; then
        cp -c "$BASE" "$1"
        for ((i = 1; i < $2 / 256; i++)); do cp -c "$BASE" "$1.$i"; done
    else
        head -c "$(( ${2:-0} * 1048576 + 4096 ))" /dev/urandom > "$1"
    fi
}
# age <path> <days>: backdate a file or a whole folder tree.
age() { find "$1" -exec touch -t "$(date -v-"$2"d +%Y%m%d%H%M)" {} +; }

# Electron apps: real Chromium cache layout next to profile files that must survive.
electron() {
    local app="Library/Application Support/$1"
    file "$app/Local Storage/leveldb/000003.log" 1
    file "$app/Preferences" 0
    file "$app/Cache/Cache_Data/data_1" "$2"
    file "$app/Code Cache/js/index" 40
    file "$app/GPUCache/index" 8
    age "$app" 4
}
electron "Slack" 512
electron "Discord" 256
electron "Notion" 256

# App caches, old logs, automation profiles.
file "Library/Caches/com.example.PhotoEditor/thumbnails.db" 256; age "Library/Caches/com.example.PhotoEditor" 9
file "Library/Caches/com.example.Browser/blobs" 120;             age "Library/Caches/com.example.Browser" 6
file "Library/Caches/com.apple.Safari/x" 20;                     age "Library/Caches/com.apple.Safari" 30   # Apple: kept
file "Library/Logs/Updater/update-2025-11-02.log" 12;            age "Library/Logs/Updater" 21
file "tmp/cdp-k2J8sQ/Default/Preferences" 30;                    age "tmp/cdp-k2J8sQ" 3
file "tmp/cdp-x81LmA/Default/Preferences" 30;                    age "tmp/cdp-x81LmA" 2

# JavaScript projects: two unused for weeks, one active today.
project() {
    file "dev/$1/package.json" 0
    file "dev/$1/src/index.ts" 0
    file "dev/$1/node_modules/react/index.js" "$2"
    [[ "${3:-0}" -gt 0 ]] && file "dev/$1/.next/cache/webpack/client.pack" "$3"
    [[ "${4:-0}" -gt 0 ]] && age "dev/$1" "$4"
    return 0
}
project "acme-dashboard" 768 512 41
project "marketing-site" 512 256 23
project "todo-app" 256 0 0     # active: kept

# Package and Xcode caches.
file ".npm/_cacache/content-v2/sha512/aa" 768;          age ".npm" 2
file "Library/Developer/Xcode/DerivedData/Acme-fx2/Build/x" 512; age "Library/Developer/Xcode/DerivedData" 2

# Review: an old Xcode archive. Personal files that must never be listed.
file "Library/Developer/Xcode/Archives/2025-03-14/Acme 1.0.xcarchive/dSYMs/x" 256
age "Library/Developer/Xcode/Archives" 150
file "Documents/Taxes 2025.pdf" 2;   age "Documents" 200
file "Downloads/Contracts/agreement.pdf" 1

rm "$BASE"
echo "Demo home ready at $DEMO"
echo "Run: SWEEP_HOME=\"$DEMO\" \"$ROOT/build/Sweep.app/Contents/MacOS/Sweep\""
