#!/bin/sh
# Creates the signing key for the Varelo RustDesk build and hands it to GitHub Actions.
# Prints no secret: the password is random, goes into GitHub secrets through pipes, and a
# copy stays next to the keystore (both readable by you only) for when it is needed again.
set -eu
REPO="erwint/rustdesk"
DIR="$HOME/.rustdesk-varelo-signing"
KS="$DIR/release.p12"
KEYTOOL="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"

if [ -e "$KS" ]; then
    echo "A key exists already in $DIR; not replacing it (installed apps would no longer update)."
    exit 1
fi
mkdir -p "$DIR"
chmod 700 "$DIR"
umask 077
VARELO_KS_PASS=$(openssl rand -hex 24)
export VARELO_KS_PASS
"$KEYTOOL" -genkeypair -keystore "$KS" -storetype PKCS12 -alias varelo -keyalg RSA -keysize 4096 \
    -validity 36500 -dname "CN=Varelo RustDesk" \
    -storepass:env VARELO_KS_PASS -keypass:env VARELO_KS_PASS >/dev/null 2>&1
printf '%s' "$VARELO_KS_PASS" > "$DIR/password"

base64 -i "$KS" | gh secret set ANDROID_SIGNING_KEY -R "$REPO" >/dev/null
printf '%s' varelo | gh secret set ANDROID_ALIAS -R "$REPO" >/dev/null
printf '%s' "$VARELO_KS_PASS" | gh secret set ANDROID_KEY_STORE_PASSWORD -R "$REPO" >/dev/null
printf '%s' "$VARELO_KS_PASS" | gh secret set ANDROID_KEY_PASSWORD -R "$REPO" >/dev/null
unset VARELO_KS_PASS
echo "Signing key created in $DIR and set as secrets of $REPO. Back up that folder."
