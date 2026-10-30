#!/bin/zsh
# Builds OP1 Control and installs it to ~/Applications/OP1Control.app.
# The op1ctl command-line tool goes inside the bundle, next to the app binary.
# Build products live in ~/Library/Developer/OP1Control, outside the repo.
#
# Usage: ./build.sh            release build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="OP1Control"
scratch="$HOME/Library/Developer/$name/build"
config=release

# Sign with your Apple Development certificate when you have one. Otherwise sign
# ad hoc, which is fine for your own Mac. Input Monitoring permission is tied to
# the signature, so an ad hoc build asks again after every rebuild.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v -e "^\[" -e "search path" || true
bin="$scratch/$config/$name"
[[ -x "$bin" && -x "$scratch/$config/op1ctl" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  exit 1
fi

"$scratch/$config/op1ctl" selftest

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$scratch/$config/op1ctl" "$app/Contents/MacOS/"
mkdir -p "$app/Contents/Resources"
cp "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__VERSION__/$(cat "$here/VERSION")/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
