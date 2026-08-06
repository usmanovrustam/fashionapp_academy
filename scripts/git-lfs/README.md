# Git LFS for Core ML model assets

The repo ships several large CoreML models straight in git history — e.g.
`u2net.mlpackage` (~88 MB), `ClothesSegFormer.mlpackage` (~54 MB, multiple
versions), `FashionMultiTask.mlpackage` (~2 MB). That's why fresh clones/pulls
are large and keep growing. Git LFS keeps these binaries out of the packfile.

## Prerequisites (every collaborator)

```bash
brew install git-lfs   # macOS
git lfs install
```

If someone commits an LFS-tracked file **without** git-lfs installed, they'll
commit a broken pointer — so make sure the whole team installs it before this
is merged.

## What's configured

`.gitattributes` (repo root) routes model binaries to LFS **for new commits**:

```
weight.bin   filter=lfs diff=lfs merge=lfs -text
*.mlmodel    filter=lfs diff=lfs merge=lfs -text
*.mlmodelc   filter=lfs diff=lfs merge=lfs -text
```

This alone does not touch existing history — old blobs stay in the packfile
until you migrate.

## Two adoption paths

1. **Forward-only (safe, gradual):** merge this PR. New model commits go to LFS;
   history size is unchanged. No force-push, nothing breaks.

2. **Full migration (shrinks history, DESTRUCTIVE):** run
   `scripts/git-lfs/migrate-to-lfs.sh`. It rewrites all branches/tags so the
   historical blobs become LFS objects, then you force-push and everyone
   re-clones. Coordinate a merge freeze first — there are several active
   `cursor/*` branches that would need rebasing.

> This PR only adds config + tooling. It intentionally does **not** run the
> migration or force-push.
