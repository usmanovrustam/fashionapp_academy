"""Validate the embedding output: category-retrieval precision on the test set.

Uses the cached 576-d test features + trained trunk to produce embeddings,
then measures how often a query's nearest neighbours share its category
(a proxy for wardrobe "find similar" quality).
"""
from __future__ import annotations

import json
import os

import numpy as np
import torch

from model import Heads

ART = os.path.join(os.path.dirname(__file__), "artifacts")


def main():
    d = np.load(os.path.join(ART, "feats_test.npz"))
    feats = torch.from_numpy(d["feats"])
    cat = d["category"]

    ckpt = torch.load(os.path.join(ART, "checkpoint.pt"), map_location="cpu", weights_only=False)
    heads = Heads(ckpt["head_dims"])
    heads.load_state_dict(ckpt["heads"])
    heads.eval()
    with torch.no_grad():
        emb = heads(feats)["embedding"].numpy()

    sims = emb @ emb.T
    np.fill_diagonal(sims, -1.0)  # exclude self
    n = emb.shape[0]
    for k in (1, 5, 10):
        nn_idx = np.argpartition(-sims, kth=k, axis=1)[:, :k]
        hits = (cat[nn_idx] == cat[:, None]).mean()
        print(f"  precision@{k:<2d} = {hits:.4f}")

    # Random baseline = probability two random items share a category.
    _, counts = np.unique(cat, return_counts=True)
    p = counts / counts.sum()
    print(f"  random baseline (same-category chance) = {float((p ** 2).sum()):.4f}")

    with open(os.path.join(ART, "metrics.json")) as f:
        m = json.load(f)
    m["similarity_precision_at_5"] = round(float(
        (cat[np.argpartition(-sims, kth=5, axis=1)[:, :5]] == cat[:, None]).mean()), 4)
    with open(os.path.join(ART, "metrics.json"), "w") as f:
        json.dump(m, f, indent=2)


if __name__ == "__main__":
    main()
