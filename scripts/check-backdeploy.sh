#!/usr/bin/env bash
# Fails when a built iPhone binary weak-imports a system symbol that is not on the reviewed list.
#
# Why: an API newer than the deployment target is weak-imported. A `@backDeployed` one is called
# through a thunk that uses the system's copy whenever the OS version is new enough, and a beta
# of that OS version may not have the copy yet: the call jumps to address 0. Vago 0.1.0 (3) died
# at launch this way on iOS 27.2 beta 24B5084k, in `Date.>=` (Sources/VagoKit/DateOrder.swift).
# A launch on the simulator cannot catch it: its older runtime takes the thunk's fallback path.
#
# A new weak import is not always wrong. Check the SDK's .swiftinterface: an API introduced in
# an OS version whose betas are out (or `@backDeployed(before:)` one) is the crash above, so
# replace the call. One introduced in a released version is fine: add its line to
# scripts/weak-imports.allow, as this script prints it.
#
# Usage: scripts/check-backdeploy.sh <products dir>
set -euo pipefail
dir="${1:?usage: scripts/check-backdeploy.sh <products dir>}"
allow="$(dirname "$0")/weak-imports.allow"

actual="$(mktemp -t vago-weak)"
trap 'rm -f "$actual"' EXIT
while IFS= read -r -d '' bin; do
  file -b "$bin" | grep -q "Mach-O" || continue
  { xcrun dyld_info -imports "$bin" 2>/dev/null | grep "weak-import" || true; } | while read -r _ sym _ rest; do
    lib="${rest##*(from }"; lib="${lib%)}"
    printf '%s | %s\n' "$lib" "$(printf '%s\n' "${sym#_}" | xcrun swift-demangle --simplified)"
  done
done < <(find "$dir" -type f -perm -u+x \( -path "*.app/*" -o -path "*.appex/*" \) -print0) | sort -u >"$actual"

[ -s "$actual" ] || { echo "check-backdeploy: no weak imports in $dir"; exit 0; }
new="$(grep -v -x -F -f <(grep -v '^#' "$allow" 2>/dev/null || true) "$actual" || true)"
if [ -n "$new" ]; then
  echo "check-backdeploy: weak imports not on the reviewed list ($allow):" >&2
  echo "$new" | sed 's/^/  /' >&2
  echo "  Date >= and <= have helpers in Sources/VagoKit/DateOrder.swift." >&2
  exit 1
fi
echo "check-backdeploy: $(wc -l <"$actual" | tr -d ' ') weak imports, all on the reviewed list"
