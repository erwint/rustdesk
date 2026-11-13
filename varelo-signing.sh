#!/bin/sh
# Creates the signing key for the Varelo RustDesk build (varelo-build.sh signs with it).
# Prints no secret: the password is random and stays next to the keystore, both readable by
# you only. Every build must use this same key, or an installed copy no longer updates.
set -eu
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

unset VARELO_KS_PASS
echo "Signing key created in $DIR. Back up that folder."
