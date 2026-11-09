#!/usr/bin/env bash
# Fails when a built iPhone binary calls a Foundation `@backDeployed` API.
#
# Why: such a call goes through a thunk that uses the system's copy whenever the OS version is
# new enough. A beta of that OS version may not have the copy yet, and the call then jumps to
# address 0. Vago 0.1.0 (3) died at launch this way on iOS 27.2 beta 24B5084k, in `Date.>=`
# (see Sources/VagoKit/DateOrder.swift). A launch on the simulator cannot catch it: the
# simulator's older runtime takes the thunk's fallback path.
#
# Usage: scripts/check-backdeploy.sh <products dir>   (a .app or a folder holding .app bundles)
set -euo pipefail
dir="${1:?usage: scripts/check-backdeploy.sh <products dir>}"

found=0
while IFS= read -r -d '' bin; do
  # Mach-O executables only: the app, its extensions and frameworks.
  file -b "$bin" | grep -q "Mach-O" || continue
  hits="$(xcrun nm -a "$bin" 2>/dev/null | awk '{print $NF}' | xcrun swift-demangle --simplified \
    | grep -i "back deployment" | sort -u || true)"
  if [ -n "$hits" ]; then
    found=1
    echo "back-deployed API in ${bin#"$dir"/}:"
    echo "$hits" | sed 's/^/  /'
  fi
done < <(find "$dir" -type f -perm -u+x \( -path "*.app/*" -o -path "*.appex/*" \) -print0)

if [ "$found" = 1 ]; then
  echo "check-backdeploy: replace these calls (Date >= and <= have helpers in DateOrder.swift)" >&2
  exit 1
fi
echo "check-backdeploy: no back-deployed API in $dir"
