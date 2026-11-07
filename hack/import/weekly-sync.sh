#!/usr/bin/env bash
# This disposable checkout never replaces the pinned release source or pushes.
set -euo pipefail
root=/work/upstream-sync/kubernetes
mkdir -p /work/upstream-sync /work/evidence/weekly-sync
exec 9>/work/upstream-sync/lock
flock -n 9
if [[ ! -d "$root/.git" ]]; then
 git clone --depth 2 --branch master https://github.com/kubernetes/kubernetes.git "$root"
 git -C "$root" checkout -b domestic-weekly HEAD~1
 git -C "$root" remote rename origin upstream
fi
cd "$root"
git diff --binary > /work/evidence/weekly-sync/previous-branding.patch
git restore --worktree -- .
git rev-parse HEAD > /work/evidence/weekly-sync/before.txt
git fetch --depth 100 upstream master
git merge --ff-only upstream/master
RK_REBRAND_ONLY=1 bash /work/src/rknetes/hack/importozameshchenie.sh "$root"
git diff --exit-code -- '**/LICENSE*' '**/NOTICE*'
git rev-parse HEAD > /work/evidence/weekly-sync/after.txt
git diff --binary > /work/evidence/weekly-sync/rebranding.patch
date -u +%FT%TZ > /work/evidence/weekly-sync/completed.txt
echo 'PASS: actual upstream fetch, fast-forward merge and literal rebranding completed in the disposable checkout'
