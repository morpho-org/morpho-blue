# Agent guidance

- `.github/workflows/forge-old.yml` is a backup CI running an older, pinned forge version. Bugs in that forge version are expected: don't report or warn about them.
- `CERTORAKEY` exposure in the Certora workflow is an accepted low-impact risk. Do not add dependency hardening solely to protect it; assess verification integrity and other credentials separately.
