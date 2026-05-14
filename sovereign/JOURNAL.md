# Sovereign Zed journal

This journal tracks open questions, decisions, and research findings while the fork-maintenance substrate is being built.

## Current branch model

Decision: `sovereign/main` is an orphan recipe branch, not upstream Zed plus metadata. It owns orchestration only; `topic/*` branches own semantic patch content; `integration` and `develop` are disposable computed refs.

Open operational choice: if GitHub Actions cron is used, the repository default branch probably needs to be `sovereign/main`. GitHub scheduled workflows run only on the default branch, so a byte-for-byte upstream `main` cannot also host Sovereign cron workflows unless we accept a workflow shim on `main` or run cron outside GitHub.

First workflow: `.github/workflows/sovereign-mirror-main.yml` mirrors `zed-industries/zed/main` into this fork's `main` every ten minutes and on manual dispatch. It belongs on the orphan recipe branch because it is fork orchestration, not source. The scheduled trigger will only fire after GitHub's default branch points at the recipe branch.

## Open questions

- Should `sovereign/main` become the GitHub default branch, leaving `main` as a mirror ref?
- Should `develop` include all local `topic/*` branches not listed in `sovereign/series`, or should it use an explicit `sovereign/develop-series` file?
- Should distributable Linux bundles be produced by `script/bundle-linux`, by a Nix output that emits the same app-bundle shape, or both?
- What is the first migration-critical topic: memory egress provider or persistent persona/rules?
