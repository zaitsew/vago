#!/usr/bin/env bash
#
# Build the Mac app signed for THIS Mac, put it in /Applications and open it.
#
#   scripts/install-mac.sh            build, install, open
#   scripts/install-mac.sh --no-open  build and install only
#
# Modelled on Knut's script. Two signing paths:
#   * the development profile "com.zaitsew.vago.mac MacDev" is installed: sign with it and with
#     Mac/VagoMac-iCloud.entitlements, so iCloud sync with the iPhone works;
#   * it is not: sign with Apple Development and Mac/VagoMac.entitlements. Everything works
#     except sync, and the script prints how to make the profile.
#
# Sign with a real identity even without the profile: Accessibility is granted per code
# signature, and an ad-hoc signature changes on every build, which would ask again each time.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

XCODE_DEV=/Applications/Xcode.app/Contents/Developer
[ -d /Applications/Xcode-beta.app/Contents/Developer ] && XCODE_DEV=/Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR="${DEVELOPER_DIR:-$XCODE_DEV}"
unset SDKROOT || true

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not installed — brew install xcodegen" >&2; exit 1; }

PROFILE="com.zaitsew.vago.mac MacDev"
SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development")
if grep -rl "$PROFILE" ~/Library/MobileDevice/Provisioning\ Profiles ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles 2>/dev/null | grep -q .; then
  ENT=Mac/VagoMac-iCloud.entitlements
  SIGN_ARGS+=("PROVISIONING_PROFILE_SPECIFIER=$PROFILE")
  SYNC="iCloud sync on"
else
  ENT=Mac/VagoMac.entitlements
  SYNC="iCloud sync is OFF (no profile \"$PROFILE\"). Make it once: scripts/make-mac-profile.sh, then run this again."
fi
SIGN_ARGS+=("CODE_SIGN_ENTITLEMENTS=$ROOT/$ENT")

# project.yml includes ios.yml. A checkout without it (the Mac branch alone) gets an empty
# placeholder for the generation only.
PLACEHOLDER=0
if [ ! -f ios.yml ]; then echo 'targets: {}' > ios.yml; PLACEHOLDER=1; fi
xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" >/dev/null
[ "$PLACEHOLDER" = 1 ] && rm -f ios.yml

BUILD="${TMPDIR:-/tmp}/vago-mac"
mkdir -p "$BUILD"
LOG="$BUILD/install.log"

build() {
  xcodebuild -project "$ROOT/Vago.xcodeproj" -scheme VagoMac -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD" \
    "${SIGN_ARGS[@]}" build >"$LOG" 2>&1
}
if command -v teyla >/dev/null 2>&1; then teyla load --wait --kind build; fi
if ! build; then
  grep -E "error:" "$LOG" | head -20 >&2
  exit 1
fi

APP="$BUILD/Build/Products/Debug/Vago.app"
codesign --verify --deep --strict "$APP"
pkill -x Vago 2>/dev/null || true; sleep 1
rm -rf /Applications/Vago.app
ditto "$APP" /Applications/Vago.app
VERSION=$(defaults read /Applications/Vago.app/Contents/Info.plist CFBundleShortVersionString)
BUILDNO=$(defaults read /Applications/Vago.app/Contents/Info.plist CFBundleVersion)
echo "installed /Applications/Vago.app ($VERSION ($BUILDNO)) — $SYNC"
[ "${1:-}" = "--no-open" ] || open /Applications/Vago.app
