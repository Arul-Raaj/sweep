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

# Package managers that clean their own caches. These are fake tools inside the demo
# home (with SWEEP_HOME set, Sweep only looks for tools there, never in /opt/homebrew);
# they answer like the real ones and prune only the demo's files.
tool() { mkdir -p "$(dirname "$1")"; cat > "$1"; chmod +x "$1"; }

file ".cache/uv/archive-v0/7Fq2/torch/x" 384; file ".cache/uv/wheels-v5/pypi/requests/x" 48; age ".cache/uv" 5
tool "opt/homebrew/bin/uv" <<'TOOL'
#!/bin/sh
case "$1 $2" in
"cache dir") echo "$HOME/.cache/uv" ;;
"cache prune") rm -rf "$HOME/.cache/uv/archive-v0"; echo "Removed 1 directory" ;;
*) exit 2 ;;
esac
TOOL

file "Library/Caches/Homebrew/downloads/node--22.1.0.arm64_sequoia.bottle.tar.gz" 96
file "Library/Caches/Homebrew/downloads/node--23.3.0.arm64_sequoia.bottle.tar.gz" 96
file "opt/homebrew/Cellar/node/22.1.0/bin/node" 160
file "opt/homebrew/Cellar/node/23.3.0/bin/node" 160
age "Library/Caches/Homebrew" 12; age "opt/homebrew/Cellar" 12
tool "opt/homebrew/bin/brew" <<'TOOL'
#!/bin/sh
C="$HOME/Library/Caches/Homebrew"
case "$*" in
"--cache") echo "$C" ;;
"cleanup --dry-run")
    echo "Would remove: $C/downloads/node--22.1.0.arm64_sequoia.bottle.tar.gz (96.0MB)"
    echo "Would remove: $HOME/opt/homebrew/Cellar/node/22.1.0 (1 file, 160.0MB)"
    echo "==> This operation would free approximately 256.0MB of disk space." ;;
"cleanup") rm -rf "$C/downloads/node--22.1.0.arm64_sequoia.bottle.tar.gz" "$HOME/opt/homebrew/Cellar/node/22.1.0" ;;
*) exit 2 ;;
esac
TOOL

file "Library/pnpm/store/v10/files/00/unused" 512; file "Library/pnpm/store/v10/files/01/used" 128; age "Library/pnpm/store" 9
tool "Library/pnpm/pnpm" <<'TOOL'
#!/bin/sh
case "$1 $2" in
"store path") echo "$HOME/Library/pnpm/store/v10" ;;
"store prune") rm -rf "$HOME/Library/pnpm/store/v10/files/00"; echo "Removed 1 package" ;;
*) exit 2 ;;
esac
TOOL

# Review: an old Xcode archive. Personal files that must never be listed.
file "Library/Developer/Xcode/Archives/2025-03-14/Acme 1.0.xcarchive/dSYMs/x" 256
age "Library/Developer/Xcode/Archives" 150
file "Documents/Taxes 2025.pdf" 2;   age "Documents" 200
file "Downloads/Contracts/agreement.pdf" 1

rm "$BASE"
echo "Demo home ready at $DEMO"
echo "Run: SWEEP_HOME=\"$DEMO\" \"$ROOT/build/Sweep.app/Contents/MacOS/Sweep\""
