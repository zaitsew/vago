# Vago — agent notes

- Read `docs/PRODUCT.md` (the owner's words and the rules) and `docs/ARCHITECTURE.md` (the
  VagoKit contract) before changing anything.
- Ownership: `Sources/VagoKit` + `Tests` (core), `Mac/` + `mac.yml` (Mac app), `iOS/` +
  `ios.yml` (iPhone app). One PR touches one part, except a contract change in VagoKit.
- `./check.sh` is the gate (package tests and both app builds). The pre-push hook runs it:
  `git config core.hooksPath .githooks` once per clone. No CI on push or PR (POLICY §10).
- Heavy work waits for the machine: `teyla load --wait --kind build && <command>`.
- Primary platform: iOS (POLICY §14). The Mac app ships with it from the kickoff, because the
  owner asked for "across my devices" and the live timer lives in the Mac menu bar.
- Everything in the repo is in English (POLICY §12).
