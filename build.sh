#!/bin/bash
# Build Sweep.
#
#   ./build.sh            build build/Sweep.app for this Mac
#   ./build.sh install    build, copy to ~/Applications, link the `sweep` command, open it
#   ./build.sh release    universal (Apple silicon + Intel) app, packaged as
#                         build/Sweep-<version>.dmg and .zip with SHA-256 checksums
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' App/Info.plist)"
ARCHS=()
[[ "$MODE" == "release" ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Sweep"
APP="build/Sweep.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sweep"
cp App/Info.plist "$APP/Contents/Info.plist"
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable signing identity lets macOS remember permissions across builds. Uses
# $SWEEP_SIGN_IDENTITY, else an "Apple Development" or "Sweep Local" certificate if one
# exists, else an ad-hoc signature (macOS then asks for folder access after each rebuild).
IDENTITY="${SWEEP_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '"(Apple Development|Sweep Local)' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP $VERSION ($(du -sh "$APP" | cut -f1)), signed with: ${IDENTITY:-ad-hoc}"

case "$MODE" in
install)
    pkill -x Sweep 2>/dev/null || true
    mkdir -p ~/Applications ~/.local/bin
    rm -rf ~/Applications/Sweep.app
    cp -R "$APP" ~/Applications/
    ln -sf ~/Applications/Sweep.app/Contents/MacOS/Sweep ~/.local/bin/sweep
    open ~/Applications/Sweep.app
    echo "Installed to ~/Applications/Sweep.app; 'sweep' command linked in ~/.local/bin"
    ;;
release)
    NAME="Sweep-$VERSION"
    rm -f "build/$NAME.zip" "build/$NAME.dmg" "build/$NAME.sha256"
    ditto -c -k --keepParent "$APP" "build/$NAME.zip"

    # Disk image with the usual "drag Sweep to Applications" layout.
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Sweep $VERSION" -srcfolder "$STAGE" -ov -format UDZO "build/$NAME.dmg" >/dev/null

    (cd build && shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME.sha256")
    echo "Release files:"
    ls -lh "build/$NAME.dmg" "build/$NAME.zip" "build/$NAME.sha256" | awk '{print "  " $5 "\t" $9}'
    ;;
esac
