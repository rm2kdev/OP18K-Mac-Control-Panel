#!/bin/zsh
# Builds a universal (Apple silicon + Intel) OP1 Control release and zips it for GitHub.
# Signs with your Developer ID and notarizes when a notarytool keychain profile
# named OP1Control exists:
#   xcrun notarytool store-credentials OP1Control --team-id <TEAM ID>
#
# Usage: ./release.sh        writes dist/OP1Control.zip
set -euo pipefail
here=${0:A:h}
name="OP1Control"
version=$(cat "$here/VERSION")
scratch="$HOME/Library/Developer/$name/release"
dist="$here/dist"
app="$dist/$name.app"
# One file name for every release, so releases/latest/download/OP1Control.zip always works.
zip="$dist/$name.zip"

identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || { echo "no Developer ID Application certificate; set SIGN_IDENTITY"; exit 1; }

echo "==> Building $name $version (arm64 + x86_64)"
swift build -c release --package-path "$here" --scratch-path "$scratch" --arch arm64 --arch x86_64 2>&1 \
  | grep -E "error|Build complete" || true
products="$scratch/out/Products/Release"
[[ -x "$products/$name" && -x "$products/op1ctl" ]] || { echo "build failed"; exit 1; }
"$products/op1ctl" selftest

echo "==> Assembling $app"
rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/$name" "$products/op1ctl" "$app/Contents/MacOS/"
cp "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
cp "$here/LICENSE" "$app/Contents/Resources/"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__VERSION__/$version/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
xattr -cr "$app"

echo "==> Signing with $identity"
codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/MacOS/op1ctl"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --deep "$app"

ditto -c -k --keepParent "$app" "$zip"
if xcrun notarytool history --keychain-profile "$name" >/dev/null 2>&1; then
  echo "==> Notarizing (this takes a few minutes)"
  xcrun notarytool submit "$zip" --keychain-profile "$name" --wait
  xcrun stapler staple "$app"
  rm "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  spctl --assess --type execute --verbose "$app"
else
  echo "==> Not notarized: no notarytool profile named $name"
fi

shasum -a 256 "$zip" | tee "$zip.sha256"
echo "release: $zip"
