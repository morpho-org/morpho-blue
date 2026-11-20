# Agent guidance

- `.github/workflows/forge-old.yml` is a backup CI running an older, pinned forge version. Bugs in that forge version are expected: don't report or warn about them.
- `CERTORAKEY` exposure in the Certora workflow is an accepted low-impact risk. Do not add dependency hardening solely to protect it; assess verification integrity and other credentials separately.

## Regular CI check

Pinned versions should not be updated unless certora-cli requires new versions or a pinned program has a bug that affects the CI. certora-cli can float.

Software installed from the runner image does not need to be checked, since we trust the image in the first place.

The goal is to avoid a wrongly green CI. Leaking keys & repo content is not critical.

If the CI or the CI check section of AGENTS.md of one of the repos has changed since your last check, propagate the change to the other repos if it makes sense. Otherwise the difference should be justified by a comment.

Do not report:
- A download failure that passes on a later run.
- A change applied the same way in every repo.

Allowed differences:
- Fork-test RPC secret: `MORPHO_RPC_KEY` (deployments) vs `PROTOCOL_ALCHEMY_KEY` (morpho-blue-oracles, morpho-token).
- CI or foundry.toml settings where the difference is explained by a comment above, or that follow from what the repo contains (like no Certora, different solc versions, compiler settings, Makefile needs, etc.).
- `certora/Makefile` layouts.
