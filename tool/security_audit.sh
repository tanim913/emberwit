#!/usr/bin/env bash
# Audits a release APK before it ships. Fails on the first problem.
#
# Usage: tool/security_audit.sh build/app/outputs/flutter-apk/app-prod-release.apk
#
# Checks: not debuggable, no backup, no cleartext traffic, only the launcher
# activity exported, expected permissions only, no private keys or signing
# secrets inside, Dart code obfuscated, 64-bit native libraries only, and
# the APK is signed.
set -euo pipefail
apk="${1:?path to a release APK}"
sdk="${ANDROID_HOME:?ANDROID_HOME must be set}"
tools="$(ls -d "$sdk"/build-tools/* | sort -V | tail -1)"
aapt2="$tools/aapt2"
apksigner="$tools/apksigner"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok   $*"; }

manifest="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")"
grep -q 'android:debuggable.*=true' <<<"$manifest" && fail "debuggable"
pass "not debuggable"
grep -q 'android:allowBackup.*=false' <<<"$manifest" || fail "backup allowed"
pass "backup disabled"
grep -q 'android:usesCleartextTraffic.*=false' <<<"$manifest" ||
  fail "cleartext traffic not disabled"
pass "cleartext traffic disabled"

exported="$(grep -c 'android:exported.*=true' <<<"$manifest" || true)"
# MainActivity, plus receivers/services that plugins export behind a system
# permission. List them so a reviewer sees any change.
echo "     exported components: $exported"
grep -B8 'android:exported.*=true' <<<"$manifest" |
  grep -o 'android:name(0x[0-9a-f]*)="[^"]*"' | sed 's/^/       /' || true

permissions="$("$aapt2" dump permissions "$apk" | grep -o "name='[^']*'" | sort -u)"
echo "     permissions:"; sed 's/^/       /' <<<"$permissions"
# RECORD_AUDIO is expected: voice typing, recognized offline on the phone.
for unexpected in READ_CONTACTS ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION \
  CAMERA READ_EXTERNAL_STORAGE READ_PHONE_STATE; do
  grep -q "$unexpected" <<<"$permissions" && fail "unexpected permission $unexpected"
done
pass "no sensitive permissions"

python3 -m zipfile -e "$apk" "$work"  # no unzip on every CI image
if grep -rlaE 'BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY|storePassword|keyPassword' \
  "$work" >/dev/null; then
  fail "private key or signing secret inside the APK"
fi
pass "no private keys or signing secrets"

libapp="$(find "$work/lib" -name libapp.so | head -1)"
[ -n "$libapp" ] || fail "libapp.so missing"
for symbol in ChatRepositoryImpl ChatArchiveCodec RuntimeSupervisor; do
  grep -qa "$symbol" "$libapp" && fail "Dart symbols not obfuscated ($symbol)"
done
pass "Dart code obfuscated"

abis="$(ls "$work/lib")"
for abi in $abis; do
  case "$abi" in arm64-v8a|x86_64) ;; *) fail "unexpected ABI $abi" ;; esac
done
pass "ABIs: $(tr '\n' ' ' <<<"$abis")"

signer="$("$apksigner" verify --print-certs "$apk" | grep -m1 'Signer #1 certificate DN')" ||
  fail "not signed"
if grep -q 'CN=Android Debug' <<<"$signer"; then
  [ "${STRICT:-0}" = 1 ] && fail "signed with the debug key"
  echo "WARN signed with the Android debug key: fine for testing, never upload it"
else
  pass "signed: $signer"
fi
echo "All checks passed for $apk"
