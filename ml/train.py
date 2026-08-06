"""Train the multi-task fashion model and report held-out metrics.

Backbone (ImageNet MobileNetV3-Small) is frozen; we precompute its 576-d
features once, then train the shared trunk + task heads on those features.
This keeps the whole run fast on CPU while using real fashion photos.

Usage:
  python train.py --epochs 40                # full run
  python train.py --epochs 5 --limit 4000    # quick smoke run
"""
from __future__ import annotations

import argparse
import json
import os
import time

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader

import data as datamod
from model import Backbone, Heads

# Containers often have a tiny /dev/shm, which crashes DataLoader workers.
torch.multiprocessing.set_sharing_strategy("file_system")
torch.set_num_threads(max(1, os.cpu_count() or 1))

ART = os.path.join(os.path.dirname(__file__), "artifacts")
TASKS = ["category", "gender", "season", "usage", "color"]
TASK_WEIGHTS = {"category": 1.0, "gender": 0.5, "season": 0.5, "usage": 0.5, "color": 0.7}
DEVICE = "cpu"


@torch.no_grad()
def compute_features(hf, records, backbone, batch=128, workers=0):
    ds = datamod.FashionDataset(hf, records, train=False)
    loader = DataLoader(ds, batch_size=batch, shuffle=False, num_workers=workers)
    feats, labels = [], {t: [] for t in TASKS}
    backbone.eval()
    done = 0
    for x, y in loader:
        feats.append(backbone(x).cpu().numpy().astype(np.float32))
        for t in TASKS:
            labels[t].append(y[t].numpy())
        done += x.shape[0]
        print(f"   features {done}/{len(records)}", end="\r", flush=True)
    print()
    feats = np.concatenate(feats)
    labels = {t: np.concatenate(labels[t]) for t in TASKS}
    return feats, labels


def cached_features(hf, split_name, records, backbone):
    path = os.path.join(ART, f"feats_{split_name}.npz")
    if os.path.exists(path):
        d = np.load(path)
        return d["feats"], {t: d[t] for t in TASKS}
    feats, labels = compute_features(hf, records, backbone)
    np.savez_compressed(path, feats=feats, **labels)
    return feats, labels


def category_class_weights(y, n):
    counts = np.bincount(y[y >= 0], minlength=n).astype(np.float32)
    w = counts.sum() / (n * np.maximum(counts, 1))
    return torch.tensor(w, dtype=torch.float32)


def evaluate(heads, feats, labels, label_space):
    heads.eval()
    with torch.no_grad():
        out = heads(torch.from_numpy(feats))
    metrics = {}
    for t in TASKS:
        y = labels[t]
        mask = y >= 0
        if mask.sum() == 0:
            continue
        pred = out[t].argmax(1).numpy()
        acc = float((pred[mask] == y[mask]).mean())
        metrics[t] = {"accuracy": round(acc, 4), "n": int(mask.sum())}
    return metrics


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--limit", type=int, default=0, help="subsample N records (0=all)")
    args = ap.parse_args()

    os.makedirs(ART, exist_ok=True)
    from datasets import load_dataset
    print("Loading dataset ...")
    hf = load_dataset("ashraq/fashion-product-images-small", split="train")
    print(f"  rows: {len(hf)}")

    records, ls = datamod.build_records(hf)
    if args.limit:
        records = records[: args.limit]
    print(f"  wardrobe-relevant records: {len(records)}")
    print(f"  categories ({len(ls.category)}): {ls.category}")
    print(f"  colors ({len(ls.color)}), usages ({len(ls.usage)}), genders {ls.gender}")

    train_r, val_r, test_r = datamod.split_records(records)
    print(f"  split: train={len(train_r)} val={len(val_r)} test={len(test_r)}")

    backbone = Backbone(pretrained=True).to(DEVICE)
    for p in backbone.parameters():
        p.requires_grad_(False)

    tag = f"_lim{args.limit}" if args.limit else ""
    print("Extracting backbone features ...")
    Xtr, Ytr = cached_features(hf, "train" + tag, train_r, backbone)
    Xva, Yva = cached_features(hf, "val" + tag, val_r, backbone)
    Xte, Yte = cached_features(hf, "test" + tag, test_r, backbone)

    heads = Heads(ls.heads).to(DEVICE)
    opt = torch.optim.AdamW(heads.parameters(), lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=args.epochs)
    cat_w = category_class_weights(Ytr["category"], len(ls.category))
    losses = {t: nn.CrossEntropyLoss(ignore_index=-1,
                                     weight=cat_w if t == "category" else None)
              for t in TASKS}

    Xtr_t = torch.from_numpy(Xtr)
    Ytr_t = {t: torch.from_numpy(Ytr[t]).long() for t in TASKS}
    n = Xtr_t.shape[0]
    best_val, best_state = -1.0, None
    print("Training heads ...")
    for epoch in range(args.epochs):
        heads.train()
        perm = torch.randperm(n)
        total = 0.0
        for i in range(0, n, args.batch):
            idx = perm[i:i + args.batch]
            out = heads(Xtr_t[idx])
            loss = sum(TASK_WEIGHTS[t] * losses[t](out[t], Ytr_t[t][idx]) for t in TASKS)
            opt.zero_grad()
            loss.backward()
            opt.step()
            total += float(loss) * len(idx)
        sched.step()
        val_m = evaluate(heads, Xva, Yva, ls)
        val_cat = val_m["category"]["accuracy"]
        if val_cat > best_val:
            best_val = val_cat
            best_state = {k: v.clone() for k, v in heads.state_dict().items()}
        if epoch % 5 == 0 or epoch == args.epochs - 1:
            print(f"  epoch {epoch:3d}  loss={total/n:.4f}  val_cat_acc={val_cat:.4f}")

    heads.load_state_dict(best_state)
    test_m = evaluate(heads, Xte, Yte, ls)
    print("\n=== TEST METRICS ===")
    for t in TASKS:
        if t in test_m:
            print(f"  {t:9s} acc={test_m[t]['accuracy']:.4f}  (n={test_m[t]['n']})")

    torch.save({"heads": heads.state_dict(), "labels": ls.to_json(),
                "head_dims": ls.heads}, os.path.join(ART, "checkpoint.pt"))
    with open(os.path.join(ART, "labels.json"), "w") as f:
        json.dump(ls.to_json(), f, indent=2)
    with open(os.path.join(ART, "metrics.json"), "w") as f:
        json.dump({"val_best_category_acc": best_val, "test": test_m,
                   "train_size": len(train_r), "test_size": len(test_r),
                   "epochs": args.epochs}, f, indent=2)
    print(f"\nSaved checkpoint + metrics to {ART}")


if __name__ == "__main__":
    main()
