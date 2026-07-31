#!/usr/bin/env bash
# Builds an unsigned IPA. Sign it with Sideloadly / AltStore / Xcode afterwards.
#
#   tools/build_ipa.sh [path-to-godot]
#
# Why this script exists instead of `godot --export-debug "iOS"`:
#
# Godot's iOS export ends by invoking xcodebuild, which fails on this machine at
# CompileAssetCatalog. `actool` (asset catalog) and `ibtool` (launch storyboard)
# BOTH require a simulator runtime even when targeting a physical device, and no
# iOS runtime is installed. Nothing else needs one — the binary compiles fine.
#
# So: let Godot generate the Xcode project, remove the two resources that need
# those tools, ship icons as loose PNGs instead, and package the .app by hand.
# That is exactly the shape of an IPA built here previously (unsigned, no
# Assets.car, loose icons), so it is a known-good route rather than a guess.
set -uo pipefail
GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/ios"
APP_TMP="$(mktemp -d)/app"

echo "=== 1. generate the Xcode project (xcodebuild step is expected to fail) ==="
rm -rf "$OUT"; mkdir -p "$OUT"
"$GODOT" --headless --export-debug "iOS" "$OUT/polarity.ipa" 2>&1 \
  | grep -iE "CompileAssetCatalog|BUILD FAILED" | head -2 || true
[ -d "$OUT/polarity.xcodeproj" ] || { echo "!! no Xcode project generated"; exit 1; }

echo "=== 2. drop the two resources that need a simulator runtime ==="
python3 - "$OUT" <<'PY'
import sys, re, os
out = sys.argv[1]
p = os.path.join(out, 'polarity.xcodeproj/project.pbxproj')
s = open(p).read()
# Remove them from the Resources build phase, and from PBXBuildFile.
for label in ['Images.xcassets', 'Launch Screen.storyboard']:
    s = re.sub(r'^\t*[0-9A-F]{24} /\* %s in Resources \*/,\n' % re.escape(label), '', s, flags=re.M)
    s = re.sub(r'^\t*[0-9A-F]{24} /\* %s in Resources \*/ = \{[^}]*\};\n' % re.escape(label), '', s, flags=re.M)
# Universal, not iPad-only: an iPhone is device family 1 and refuses a [2]-only app.
s = s.replace('TARGETED_DEVICE_FAMILY = "2";', 'TARGETED_DEVICE_FAMILY = "1,2";')
open(p, 'w').write(s)
print('   pbxproj patched')
PY

echo "=== 3. declare icons the way iOS 7+ actually reads them ==="
python3 - "$OUT" <<'PY'
import sys, os, glob, plistlib
out = sys.argv[1]
icons = sorted(os.path.basename(f)[:-4]
               for f in glob.glob(os.path.join(out, 'polarity/Images.xcassets/AppIcon.appiconset/Icon-*.png')))
p = os.path.join(out, 'polarity/polarity-Info.plist')
with open(p, 'rb') as f:
    pl = plistlib.load(f)
# The TOP-LEVEL CFBundleIconFiles key is iOS 3.2 and modern iOS ignores it. The
# icon list has to live under CFBundleIcons -> CFBundlePrimaryIcon, which Godot
# leaves empty because it expects the asset catalog we just removed.
primary = {'CFBundleIconFiles': icons, 'UIPrerenderedIcon': False}
pl['CFBundleIcons'] = {'CFBundlePrimaryIcon': primary}
pl['CFBundleIcons~ipad'] = {'CFBundlePrimaryIcon': primary}
pl['CFBundleIconFiles'] = icons
pl['UIDeviceFamily'] = [1, 2]
# No storyboard to launch from any more; the dictionary form needs no compilation.
pl.pop('UILaunchStoryboardName', None)
pl.setdefault('UILaunchScreen', {'UIColorName': ''})
with open(p, 'wb') as f:
    plistlib.dump(pl, f)
print('   %d icons declared under CFBundlePrimaryIcon' % len(icons))
PY

echo "=== 4. build ==="
( cd "$OUT" && xcodebuild -project polarity.xcodeproj -target polarity \
    -sdk iphoneos -configuration Debug CONFIGURATION_BUILD_DIR="$APP_TMP" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | tail -3 )
[ -f "$APP_TMP/polarity.app/polarity" ] || { echo "!! no binary produced"; exit 1; }

echo "=== 5. stage icons + pck, then package ==="
cp "$OUT"/polarity/Images.xcassets/AppIcon.appiconset/Icon-*.png "$APP_TMP/polarity.app/"
rm -rf "$APP_TMP/polarity.app/Launch Screen.storyboardc"
[ -f "$APP_TMP/polarity.app/polarity.pck" ] || cp "$OUT/polarity.pck" "$APP_TMP/polarity.app/"
PAY="$(mktemp -d)/Payload"; mkdir -p "$PAY"
cp -R "$APP_TMP/polarity.app" "$PAY/"
rm -f "$OUT/polarity.ipa"
( cd "$(dirname "$PAY")" && zip -qr "$OUT/polarity.ipa" Payload )

echo "=== 6. verify what actually shipped ==="
python3 - "$OUT/polarity.ipa" <<'PY'
import sys, zipfile, plistlib
z = zipfile.ZipFile(sys.argv[1])
names = {n.split('/')[-1] for n in z.namelist()}
pl = plistlib.loads(z.read('Payload/polarity.app/Info.plist'))
icons = pl.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconFiles', [])
missing = [i for i in icons if i + '.png' not in names]
fails = []
if not icons: fails.append('CFBundlePrimaryIcon has no icons — the app will show blank')
if missing: fails.append('icons declared but absent from the bundle: %s' % missing)
if pl.get('UIDeviceFamily') != [1, 2]: fails.append('UIDeviceFamily is %s, not [1, 2]' % pl.get('UIDeviceFamily'))
if 'polarity.pck' not in names: fails.append('no .pck — the app has no game in it')
if 'polarity' not in names: fails.append('no binary')
for f in fails: print('   !! ' + f)
print('   ok: %d icons, device family %s, pck present' % (len(icons), pl.get('UIDeviceFamily'))
      if not fails else '   FAILED VERIFICATION')
sys.exit(1 if fails else 0)
PY
echo
ls -la "$OUT/polarity.ipa" | awk '{printf "IPA: %.0f MB  %s\n", $5/1048576, $9}'
