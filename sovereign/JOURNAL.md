# Sovereign Zed journal

This journal tracks open questions, decisions, and research findings while the fork-maintenance substrate is being built.

## Current branch model

Decision: `sovereign/main` is an orphan recipe branch, not upstream Zed plus metadata. It owns orchestration only; `topic/*` branches own semantic patch content; `integration` and `develop` are disposable computed refs.

Open operational choice: if GitHub Actions cron is used, the repository default branch probably needs to be `sovereign/main`. GitHub scheduled workflows run only on the default branch, so a byte-for-byte upstream `main` cannot also host Sovereign cron workflows unless we accept a workflow shim on `main` or run cron outside GitHub.

First workflow: `.github/workflows/sovereign-mirror-main.yml` mirrors `zed-industries/zed/main` into this fork's `main` on manual dispatch. It belongs on the orphan recipe branch because it is fork orchestration, not source. Reliable periodic mirroring is now owned by the Gitea-backed `zed-workflows` control plane.

Second workflow: `.github/workflows/sovereign-compose-integration.yml` composes `integration` from mirrored `main` plus `sovereign/series`. It runs on manual dispatch and on pushes to `sovereign/main`. It intentionally does not rely on `topic/*` push triggers because topic branches are source trees and should not contain recipe workflows; reliable periodic recomposition is now owned by the Gitea-backed `zed-workflows` control plane.

Decision update: after moving reliable timing into the Gitea-backed `zed-workflows` control plane, `sovereign/upstream-base` is no longer the normal base selector. The fork's mirrored `main` branch is the rolling upstream base; `compose.sh --base <rev>` remains the escape hatch for pinning, bisecting, or testing a candidate base.

## Open questions

- Should `sovereign/main` become the GitHub default branch, leaving `main` as a mirror ref?
- Should `develop` include all local `topic/*` branches not listed in `sovereign/series`, or should it use an explicit `sovereign/develop-series` file?
- Should distributable Linux bundles be produced by `script/bundle-linux`, by a Nix output that emits the same app-bundle shape, or both?
- What is the first migration-critical topic: memory egress provider or persistent persona/rules?
