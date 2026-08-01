#!/usr/bin/env bash
# Signed release AAB for Google Play.
#
#   POLARITY_KEYSTORE=~/polarity-upload.jks POLARITY_KEYSTORE_PASS='...' \
#     bash tools/build_aab.sh
#
# The password is read from the environment and never written to disk. Godot 4.2+
# reads GODOT_ANDROID_KEYSTORE_RELEASE_* when the export preset's own fields are
# blank, which is why they are blank — export_presets.cfg is committed, and a
# signing password in it is the same class of mistake as a leaked service key.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="build/android/polarity.aab"

POLARITY_KEYSTORE="${POLARITY_KEYSTORE:-$HOME/polarity-upload.jks}"
[ -f "$POLARITY_KEYSTORE" ] || { echo "!! no keystore at $POLARITY_KEYSTORE"; exit 1; }

# Prompt rather than requiring the caller to export it. Passing a password on the
# command line puts it in shell history in plaintext, and the read-and-export
# one-liner that avoids that is fiddly enough to get wrong.
if [ -z "${POLARITY_KEYSTORE_PASS:-}" ]; then
  read -rsp "Keystore password: " POLARITY_KEYSTORE_PASS
  echo
fi
[ -n "$POLARITY_KEYSTORE_PASS" ] || { echo "!! no password given"; exit 1; }

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$POLARITY_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${POLARITY_KEYSTORE_ALIAS:-upload}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$POLARITY_KEYSTORE_PASS"

mkdir -p build/android
"$GODOT" --headless --export-release "Android" "$OUT"

# Verify what actually shipped, rather than trusting the exit code — an earlier
# Android export "succeeded" while silently producing an unsigned artifact.
[ -f "$OUT" ] || { echo "!! no AAB produced"; exit 1; }
echo "AAB: $(du -h "$OUT" | cut -f1)  $OUT"
# jarsigner, not a grep for META-INF: `grep -q` exits on first match, unzip takes
# SIGPIPE, and `set -o pipefail` turns that into a failure — so a correctly signed
# bundle was reported UNSIGNED. jarsigner also actually verifies the signature
# rather than checking that some file with the right name exists.
if jarsigner -verify "$OUT" 2>/dev/null | grep -q "jar verified"; then
  echo "   signed: yes"
else
  echo "!! UNSIGNED — do not upload"
  exit 1
fi
