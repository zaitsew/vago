#!/usr/bin/env bash
# Everything that can be verified from the shell, in one run: the VagoKit build and tests,
# then (once mac.yml and ios.yml exist) both app builds.
# The pre-push hook runs this; there is no CI on push or pull request (POLICY section 10).
set -euo pipefail
cd "$(dirname "$0")"

# --- usage mode: real-usage counters, read by `teyla products` --------------
# The Mac app writes ~/Library/Application Support/Vago/usage.json (docs/ARCHITECTURE.md);
# every top-level key becomes one `key=value` line. No file yet is not a failure.
case "${1:-}" in
  usage)
    usage_file="$HOME/Library/Application Support/Vago/usage.json"
    if [ -f "$usage_file" ]; then
      if command -v python3 >/dev/null 2>&1; then
        python3 -I - "$usage_file" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
if not isinstance(data, dict):
    print("usage_probe=bad_format")
else:
    for key, value in data.items():
        if isinstance(value, bool):
            value = str(value).lower()
        elif isinstance(value, (dict, list)):
            value = json.dumps(value, separators=(",", ":"))
        print(f"{key}={value}")
PY
      else
        echo "usage_probe=needs_python3"
      fi
    else
      echo "usage_probe=no_data_yet"
    fi
    exit 0 ;;
esac

# Xcode-beta wins when it is installed, as in Knut's scripts/install-mac.sh.
XCODE_DEV=/Applications/Xcode.app/Contents/Developer
[ -d /Applications/Xcode-beta.app/Contents/Developer ] && XCODE_DEV=/Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR="${DEVELOPER_DIR:-$XCODE_DEV}"
unset SDKROOT

# One shared machine: heavy commands wait for a free slot when teyla is installed (POLICY section 13).
guarded() {
  if command -v teyla >/dev/null 2>&1; then
    teyla load --wait --kind build && "$@"
  else
    "$@"
  fi
}

# --- package: VagoKit build and tests ---------------------------------------
if command -v swift >/dev/null 2>&1; then
  guarded swift build
  # A green run prints the last five lines. A red one also names every failing test,
  # which the tail alone cuts off.
  log="$(mktemp -t vago-test)"
  if guarded swift test >"$log" 2>&1; then
    tail -5 "$log"
    rm -f "$log"
  else
    status=$?
    echo "--- failing tests ---"
    grep -E "✘|recorded an issue|error:" "$log" || true
    echo "--- tail ---"
    tail -5 "$log"
    echo "full output: $log"
    exit "$status"
  fi
elif [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  # A cloud session has no Mac: say so, and the PR gets the needs-mac label.
  echo "skip: swift not available (needs a Mac)"
  exit 0
else
  echo "check.sh: swift is not on PATH; install Xcode or its command line tools" >&2
  exit 1
fi

# --- app builds -------------------------------------------------------------
# project.yml includes mac.yml and ios.yml, and XcodeGen fails on a missing include, so the
# project is generated only when both specs exist. Until the two apps land, this is skipped.
if [ -f mac.yml ] && [ -f ios.yml ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "check.sh: xcodegen is not on PATH (brew install xcodegen)" >&2
    exit 1
  fi
  xcodegen generate --quiet
  guarded xcodebuild -scheme VagoMac -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO -quiet
  guarded xcodebuild -scheme Vago -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -quiet
else
  echo "skip: app builds (mac.yml and ios.yml are not both here yet)"
fi
