#!/usr/bin/env bash
#
# Make the development provisioning profile "com.zaitsew.vago.mac MacDev" for THIS Mac, through
# the App Store Connect API. It is what lets a development-signed Vago carry the iCloud
# key-value-store entitlement, so the Mac and the iPhone can share daily totals.
#
#   scripts/make-mac-profile.sh            create what is missing, install the profile
#   scripts/make-mac-profile.sh --refresh  also delete and recreate the profile
#
# What it does, all free (no paid feature, no new certificate):
#   1. registers the bundle id com.zaitsew.vago.mac (macOS) if the team has none;
#   2. turns on the iCloud capability on it;
#   3. finds this Mac's provisioning UDID among the team's devices (registers it if absent);
#   4. picks the team's Apple Development certificate whose private key is in this keychain;
#   5. creates a MAC_APP_DEVELOPMENT profile with that device and certificate and installs it.
#
# Knut's "com.knut.Knut MacDev" was made by hand the same way; this is the same procedure as a
# script. The API helpers come from ~/ops/bin/testflight. The .p8 key is read by those helpers
# and never printed, copied or committed.
set -euo pipefail

TESTFLIGHT="$HOME/ops/bin/testflight"
[ -f "$TESTFLIGHT" ] || { echo "needs $TESTFLIGHT (the shared App Store Connect helper)" >&2; exit 1; }

REFRESH=0
[ "${1:-}" = "--refresh" ] && REFRESH=1

UDID=$(system_profiler SPHardwareDataType | awk -F': ' '/Provisioning UDID/ {print $2; exit}')
[ -n "$UDID" ] || { echo "cannot read this Mac's provisioning UDID" >&2; exit 1; }
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
# SHA-1 fingerprints of the Apple Development identities whose private key is in the keychain.
HASHES=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2}' | paste -sd, -)
[ -n "$HASHES" ] || { echo "no Apple Development identity in the keychain" >&2; exit 1; }

REFRESH="$REFRESH" UDID="$UDID" HOSTNAME_="$HOST" HASHES="$HASHES" TESTFLIGHT="$TESTFLIGHT" \
python3 -I - <<'PY'
import base64, hashlib, importlib.machinery, importlib.util, os, sys

BUNDLE = "com.zaitsew.vago.mac"
NAME = f"{BUNDLE} MacDev"

loader = importlib.machinery.SourceFileLoader("testflight_helpers", os.environ["TESTFLIGHT"])
spec = importlib.util.spec_from_loader("testflight_helpers", loader)
tf = importlib.util.module_from_spec(spec)
loader.exec_module(tf)          # defines the helpers; main() runs only as __main__

cfg = tf.load_config()
api = lambda path, **kw: tf.api(cfg, path, **kw)
refresh = os.environ["REFRESH"] == "1"

# 1. bundle id
ids = {b["attributes"]["identifier"]: b["id"] for b in api("/v1/bundleIds?limit=200")["data"]}
if BUNDLE not in ids:
    created = api("/v1/bundleIds", method="POST", body={"data": {
        "type": "bundleIds",
        "attributes": {"identifier": BUNDLE, "name": "Vago Mac", "platform": "MAC_OS"}}})["data"]
    ids[BUNDLE] = created["id"]
    print(f"· registered bundle id {BUNDLE}")
else:
    print(f"· bundle id {BUNDLE} already registered")
bundle_pk = ids[BUNDLE]

# 2. iCloud capability (a profile freezes the capabilities it was made with, so a new
#    capability means the profile must be recreated)
caps = {c["attributes"]["capabilityType"]
        for c in api(f"/v1/bundleIds/{bundle_pk}/bundleIdCapabilities")["data"]}
if "ICLOUD" not in caps:
    api("/v1/bundleIdCapabilities", method="POST", body={"data": {
        "type": "bundleIdCapabilities",
        "attributes": {"capabilityType": "ICLOUD",
                       "settings": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}]},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_pk}}}}})
    print("· iCloud capability enabled")
    refresh = True
else:
    print("· iCloud capability already on")

# 3. this Mac as a device
udid = os.environ["UDID"].lower()
devices = api("/v1/devices?limit=200&filter[platform]=MAC_OS")["data"]
device = next((d for d in devices if d["attributes"]["udid"].lower() == udid), None)
if device is None:
    device = api("/v1/devices", method="POST", body={"data": {
        "type": "devices",
        "attributes": {"name": os.environ["HOSTNAME_"], "udid": os.environ["UDID"], "platform": "MAC_OS"}}})["data"]
    print("· registered this Mac as a device")
else:
    print(f'· this Mac is registered as "{device["attributes"]["name"]}"')

# 4. an Apple Development certificate whose private key is here
mine = set(os.environ["HASHES"].lower().split(","))
certs = api("/v1/certificates?limit=200")["data"]
usable = [c for c in certs
          if c["attributes"].get("certificateType") in ("DEVELOPMENT", "MAC_APP_DEVELOPMENT")
          and hashlib.sha1(base64.b64decode(c["attributes"]["certificateContent"])).hexdigest() in mine]
if not usable:
    tf.die("no team development certificate matches a key in this keychain",
           hint="Xcode > Settings > Accounts > Manage Certificates, then run this again")
usable.sort(key=lambda c: c["attributes"].get("expirationDate") or "", reverse=True)
cert_id = usable[0]["id"]
print(f'· certificate {usable[0]["attributes"].get("displayName") or cert_id}')

# 5. the profile
for p in api("/v1/profiles?limit=200")["data"]:
    a = p["attributes"]
    if a["name"] != NAME:
        continue
    if not refresh and a.get("profileState") == "ACTIVE" and a.get("profileType") == "MAC_APP_DEVELOPMENT":
        full = api(f'/v1/profiles/{p["id"]}')["data"]["attributes"]
        print(f'· profile "{NAME}" already current ({tf._install_profile(full, ".provisionprofile")})')
        sys.exit(0)
    api(f'/v1/profiles/{p["id"]}', method="DELETE")
data = api("/v1/profiles", method="POST", body={"data": {
    "type": "profiles",
    "attributes": {"name": NAME, "profileType": "MAC_APP_DEVELOPMENT"},
    "relationships": {
        "bundleId": {"data": {"type": "bundleIds", "id": bundle_pk}},
        "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
        "devices": {"data": [{"type": "devices", "id": device["id"]}]}}}})["data"]
print(f'· profile "{NAME}" installed ({tf._install_profile(data["attributes"], ".provisionprofile")})')
PY
