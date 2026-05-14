# Sovereign Zed patch-stack discipline

This fork is maintained as a small semantic patch stack on top of upstream Zed. It is not a normal long-lived feature branch where source edits accumulate directly on `main`.

The short version:

- `main` is the upstream mirror ref. It should match `upstream/main` exactly.
- `sovereign/main` is the recipe branch: scripts, docs, workflows, `sovereign/series`, and `sovereign/upstream-base` live here.
- `topic/<name>` branches are semantic patches.
- `topic-base/<name>` branches delimit patches: `topic-base/<name>..topic/<name>` is the range compose applies.
- `integration` and `develop` are computed refs. Never commit to them.
- `topic-repair-base/<name>` is temporary repair metadata created when compose fails on `topic/<name>`.

Before every edit, ask: **is this recipe, or is this a patch?**

| Change kind | Where it belongs |
| --- | --- |
| Compose/release scripts, fork docs, fork-owned workflows | `sovereign/main` |
| `crates/**`, `assets/**`, `extensions/**`, `nix/**`, `flake.nix`, `Cargo.toml`, `script/bundle-*`, or anything that affects built bytes | `topic/<name>` |
| Adding/removing/reordering active patches | `sovereign/series` on `sovereign/main` |
| Advancing upstream | `sovereign/upstream-base` on `sovereign/main`, then topic repair as needed |

Zed being Nix-based does not make Nix edits recipe by default. If a Nix change affects the resulting app, package, release channel, update behavior, or source closure, it is a source patch and belongs in a topic branch.

## Branch roles

### `main`

`main` is the mirror of upstream Zed. It exists so humans and automation can compare the fork against upstream without wondering which local process touched it.

Do not put Sovereign workflows, docs, or source changes here.

### `sovereign/main`

`sovereign/main` is an orphan recipe branch, not upstream Zed plus metadata. It describes how to construct Sovereign Zed and should contain only recipe material:

- `sovereign/README.md`
- `sovereign/JOURNAL.md`
- `sovereign/scripts/*`
- `sovereign/series`
- `sovereign/upstream-base`
- `.github/workflows/sovereign-*.yml`

Do not put shipping source/product changes here. A source change on `sovereign/main` is just recipe-branch drift unless a topic also carries that change.

### `topic/<name>`

A topic is one semantic patch. Keep it narrow enough that it can be reasoned about, repaired, upstreamed, dropped, or reordered independently.

Rules:

- Keep topics linear; no merge commits.
- Prefer one coherent concern per topic.
- Source changes that should ship must be committed here.
- Topic commits may be rewritten while repairing the patch; use `--force-with-lease` when publishing rewritten refs.

### `topic-base/<name>`

The topic base marks the lower bound of a patch range. Compose applies:

```text
topic-base/<name>..topic/<name>
```

Move a topic base only as part of an intentional repair after the topic successfully composes on its new base.

### `integration`

`integration` is computed from:

```text
sovereign/upstream-base + sovereign/series
```

It is updated only after the full active stack composes successfully. If composition fails, `integration` remains at the last known good composed tree.

Never commit to `integration`.

### `develop`

`develop` is reserved for a computed tree containing `integration` plus extra development topics. It is useful for local experiments that should not yet be release-active.

Never commit to `develop`.

### `topic-repair-base/<name>`

When compose fails on `topic/<name>`, the compose script writes:

```text
topic-repair-base/<name>
```

at the composed prefix immediately before the failing topic. Rebase or recreate the failing topic on top of that repair base, validate composition, then move `topic-base/<name>` to the repair base as part of the successful repair.

## Adding a new source patch

A new topic can normally begin from the latest successful `integration`:

```bash
git fetch origin \
  'refs/heads/integration:refs/remotes/origin/integration' \
  'refs/heads/topic/*:refs/remotes/origin/topic/*' \
  'refs/heads/topic-base/*:refs/remotes/origin/topic-base/*'

git branch topic-base/my-change origin/integration
git switch -c topic/my-change topic-base/my-change

# Edit source/product files.
git commit -m "area: describe the patch"

git push origin topic-base/my-change topic/my-change
```

Then activate it by adding it to `sovereign/series` on `sovereign/main`:

```text
topic/my-change
```

and validate:

```bash
sovereign/scripts/compose.sh
```

If the topic depends on an earlier topic, list it later in `sovereign/series`. The order is semantically real.

## Editing the recipe

Use `sovereign/main` for changes to the recipe itself:

- compose scripts
- fork-owned workflows
- docs and process notes
- `sovereign/series`
- `sovereign/upstream-base`

If a recipe change needs matching source behavior, split it deliberately:

1. source behavior goes in `topic/<name>`;
2. workflow/env/series behavior goes in `sovereign/main`;
3. local compose proves the two halves meet in `.git/sovereign-compose`.

## Validation checklist

For source/product topic changes:

```bash
sovereign/scripts/compose.sh
cd .git/sovereign-compose
nix flake show --accept-flake-config
nix build .#default --accept-flake-config
```

For recipe-only changes:

```bash
git diff --check
bash -n sovereign/scripts/*.sh
```

## Red flags

Stop and reconsider if you are about to:

- commit a shipping source/product/Nix-output change directly to `sovereign/main`;
- commit to `integration` or `develop`;
- create a merge commit inside `topic/*`;
- move a `topic-base/*` ref casually;
- update `integration` after a partial compose failure;
- treat a `/nix/store` install as equivalent to Zed's mutable app-bundle updater path.
