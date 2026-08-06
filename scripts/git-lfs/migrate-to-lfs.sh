#!/usr/bin/env bash
#
# ONE-TIME, DESTRUCTIVE history migration to move existing Core ML model blobs
# into Git LFS. This rewrites commit SHAs for the whole repo and REQUIRES a
# coordinated force-push plus every collaborator re-cloning afterwards.
#
# Do NOT run this casually. Announce a freeze on merges first.
#
# Prerequisites (all collaborators): `git lfs install` (brew install git-lfs).
set -euo pipefail

if ! command -v git-lfs >/dev/null 2>&1; then
  echo "git-lfs is not installed. Install it first (e.g. brew install git-lfs)." >&2
  exit 1
fi

git lfs install

# Rewrite ALL branches/tags so historical model blobs become LFS objects.
git lfs migrate import --include="weight.bin,*.mlmodel,*.mlmodelc" --everything

cat <<'NEXT'

History rewritten locally. Next steps (coordinate with the team):
  1. Verify:   git lfs ls-files | head
  2. Push:     git push --force-with-lease origin --all
               git push --force-with-lease origin --tags
  3. Everyone else: re-clone (old clones now have divergent history).

NEXT
