#!/usr/bin/env bash
# Refreshes README.upstream.md, but only after a merge that actually pulled
# upstream/main into main — not every `git pull`/merge on any branch.
# Wired in as pre-commit's post-merge hook (see .pre-commit-config.yaml).
set -euo pipefail

branch="$(git branch --show-current)"
[ "$branch" = "main" ] || exit 0

git remote get-url upstream >/dev/null 2>&1 || exit 0
[ -f README.upstream.md ] || exit 0

upstream_head="$(git rev-parse upstream/main 2>/dev/null)" || exit 0
head_commit="$(git rev-parse HEAD)"

if [ "$head_commit" = "$upstream_head" ]; then
    # Fast-forward merge landed main exactly on upstream/main's tip.
    merged_upstream=1
else
    # True merge commit: its second parent is the branch that got merged in.
    second_parent="$(git log -1 --pretty=%P HEAD | cut -d' ' -f2)"
    if [ -n "$second_parent" ] && [ "$second_parent" = "$upstream_head" ]; then
        merged_upstream=1
    else
        merged_upstream=0
    fi
fi

[ "$merged_upstream" = "1" ] || exit 0

make sync-upstream-readme
