#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sovereign/scripts/compose.sh [options]

Compose Sovereign Zed from the mirrored upstream `main` ref plus topic ranges
listed in sovereign/series. On full success, updates the computed integration
ref. On failure, leaves integration unchanged and writes topic-repair-base/<name>
at the last successfully composed prefix.

Options:
  --base <rev>       Base revision to compose onto. Defaults to origin/main, then main.
  --series <path>    Series file. Defaults to sovereign/series.
  --worktree <path>  Compose worktree. Defaults to .git/sovereign-compose.
  --ref <ref>        Computed ref to update on success. Defaults to integration.
  --force            Remove an existing dirty compose worktree.
  --no-update-ref    Compose only; do not update the computed ref.
  -h, --help         Show this help.
EOF
}

repo_root=$(git rev-parse --show-toplevel)
series_file="$repo_root/sovereign/series"
worktree="$repo_root/.git/sovereign-compose"
output_ref="integration"
force=false
update_ref=true
base=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      base=${2:?"--base requires a revision"}
      shift 2
      ;;
    --series)
      series_file=${2:?"--series requires a path"}
      shift 2
      ;;
    --worktree)
      worktree=${2:?"--worktree requires a path"}
      shift 2
      ;;
    --ref)
      output_ref=${2:?"--ref requires a ref name"}
      shift 2
      ;;
    --force)
      force=true
      shift
      ;;
    --no-update-ref)
      update_ref=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$base" ]]; then
  if [[ -n "${SOVEREIGN_BASE:-}" ]]; then
    base="$SOVEREIGN_BASE"
  elif git -C "$repo_root" rev-parse --verify --quiet "origin/main^{commit}" >/dev/null; then
    base="origin/main"
  elif git -C "$repo_root" rev-parse --verify --quiet "main^{commit}" >/dev/null; then
    base="main"
  elif git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    echo "default base not present locally; fetching origin main" >&2
    git -C "$repo_root" fetch origin '+refs/heads/main:refs/remotes/origin/main'
    base="origin/main"
  elif git -C "$repo_root" remote get-url upstream >/dev/null 2>&1; then
    echo "default base not present locally; fetching upstream main" >&2
    git -C "$repo_root" fetch upstream main --tags
    base=$(git -C "$repo_root" rev-parse FETCH_HEAD)
  fi
fi

if [[ -z "$base" ]]; then
  echo "could not determine default base; fetch origin/main or pass --base <rev>" >&2
  exit 1
fi

if [[ ! -f "$series_file" ]]; then
  echo "missing series file: $series_file" >&2
  exit 1
fi

if ! git -C "$repo_root" rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  case "$base" in
    origin/main)
      git -C "$repo_root" fetch origin '+refs/heads/main:refs/remotes/origin/main'
      ;;
    upstream/main)
      git -C "$repo_root" fetch upstream '+refs/heads/main:refs/remotes/upstream/main' --tags
      ;;
    main)
      git -C "$repo_root" fetch origin '+refs/heads/main:refs/heads/main' || true
      ;;
    *)
      ;;
  esac
fi

git -C "$repo_root" rev-parse --verify --quiet "$base^{commit}" >/dev/null || {
  cat >&2 <<EOF
base does not resolve to a commit: $base
Fetch the mirrored upstream base first, for example:
  git fetch origin '+refs/heads/main:refs/remotes/origin/main'
EOF
  exit 1
}

echo "compose base: $base ($(git -C "$repo_root" rev-parse "$base^{commit}"))"

remove_worktree() {
  if git -C "$repo_root" worktree list --porcelain | grep -Fxq "worktree $worktree"; then
    git -C "$repo_root" worktree remove --force "$worktree"
  elif [[ -e "$worktree" ]]; then
    rm -rf "$worktree"
  fi
}

if [[ -d "$worktree/.git" || -f "$worktree/.git" ]]; then
  if [[ -n $(git -C "$worktree" status --porcelain) && "$force" != true ]]; then
    cat >&2 <<EOF
compose worktree is dirty: $worktree
Use --force to remove it and compose from scratch.
EOF
    exit 1
  fi
  remove_worktree
elif [[ -e "$worktree" ]]; then
  if [[ "$force" != true ]]; then
    echo "compose path exists but is not a git worktree: $worktree" >&2
    echo "Use --force to remove it." >&2
    exit 1
  fi
  rm -rf "$worktree"
fi

mkdir -p "$(dirname "$worktree")"
git -C "$repo_root" worktree add --detach "$worktree" "$base" >/dev/null

last_success=$(git -C "$worktree" rev-parse HEAD)
failed_topic=""

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line=${raw_line%%#*}
  line=$(printf '%s' "$line" | xargs)

  if [[ -z "$line" ]]; then
    continue
  fi

  if [[ "$line" != topic/* ]]; then
    echo "series entries must be topic/<name>; got: $line" >&2
    exit 1
  fi

  topic_ref="$line"
  topic_name=${topic_ref#topic/}
  topic_base_ref="topic-base/$topic_name"

  git -C "$repo_root" rev-parse --verify --quiet "$topic_ref^{commit}" >/dev/null || {
    echo "missing topic ref: $topic_ref" >&2
    exit 1
  }
  git -C "$repo_root" rev-parse --verify --quiet "$topic_base_ref^{commit}" >/dev/null || {
    echo "missing topic base ref: $topic_base_ref" >&2
    exit 1
  }

  commit_count=$(git -C "$repo_root" rev-list --count "$topic_base_ref..$topic_ref")
  if [[ "$commit_count" == "0" ]]; then
    echo "skip $topic_ref: empty range $topic_base_ref..$topic_ref"
    continue
  fi

  echo "apply $topic_ref ($commit_count commit(s))"
  last_success=$(git -C "$worktree" rev-parse HEAD)
  if ! git -C "$worktree" cherry-pick "$topic_base_ref..$topic_ref"; then
    failed_topic="$topic_name"
    repair_ref="refs/heads/topic-repair-base/$topic_name"
    git -C "$repo_root" update-ref "$repair_ref" "$last_success"
    cat >&2 <<EOF
compose failed while applying $topic_ref
repair base written: topic-repair-base/$topic_name -> $last_success
integration left unchanged
EOF
    exit 1
  fi

done < "$series_file"

final_head=$(git -C "$worktree" rev-parse HEAD)

if [[ "$update_ref" == true ]]; then
  git -C "$repo_root" update-ref "refs/heads/$output_ref" "$final_head"
  echo "updated $output_ref -> $final_head"
else
  echo "composed successfully at $final_head"
fi

if [[ -n "$failed_topic" ]]; then
  exit 1
fi
