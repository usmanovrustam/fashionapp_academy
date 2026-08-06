"""Dataset loading, label building, and train/val/test splits."""
from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass, field

import numpy as np
import torch
from torch.utils.data import Dataset

import taxonomy

IMG_SIZE = 128
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


def _clean(v):
    if v is None:
        return None
    s = str(v).strip()
    if s == "" or s.lower() in {"nan", "na", "none"}:
        return None
    return s


@dataclass
class LabelSpace:
    category: list[str] = field(default_factory=list)
    gender: list[str] = field(default_factory=list)
    season: list[str] = field(default_factory=list)
    usage: list[str] = field(default_factory=list)
    color: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        return {
            "category": self.category, "gender": self.gender,
            "season": self.season, "usage": self.usage, "color": self.color,
        }

    @property
    def heads(self) -> dict[str, int]:
        return {
            "category": len(self.category), "gender": len(self.gender),
            "season": len(self.season), "usage": len(self.usage),
            "color": len(self.color),
        }


def _idx(vocab: list[str], value):
    if value is None:
        return -1
    try:
        return vocab.index(value)
    except ValueError:
        return -1


def build_records(hf_dataset, min_category=80, min_color=150, min_usage=60):
    """Return (records, label_space). Each record: dict of int labels + row idx."""
    meta = hf_dataset.remove_columns(["image"])
    cats, genders, seasons, usages, colors = [], [], [], [], []
    rows = []
    for i in range(len(meta)):
        r = meta[i]
        if _clean(r.get("masterCategory")) not in taxonomy.KEEP_MASTER_CATEGORIES:
            continue
        cat = taxonomy.map_category(_clean(r.get("articleType")), _clean(r.get("subCategory")))
        if cat is None or cat == "other":
            continue
        gender = taxonomy.GENDER_MAP.get(_clean(r.get("gender")))
        season = taxonomy.SEASON_MAP.get(_clean(r.get("season")))
        usage = _clean(r.get("usage"))
        color = _clean(r.get("baseColour"))
        rows.append({"row": i, "category": cat, "gender": gender,
                     "season": season, "usage": usage, "color": color})
        cats.append(cat)
        if gender: genders.append(gender)
        if season: seasons.append(season)
        if usage: usages.append(usage)
        if color: colors.append(color)

    cat_counts = Counter(cats)
    keep_cats = {c for c, n in cat_counts.items() if n >= min_category}
    color_counts = Counter(colors)
    keep_colors = sorted(c for c, n in color_counts.items() if n >= min_color)
    usage_counts = Counter(usages)
    keep_usages = sorted(u for u, n in usage_counts.items() if n >= min_usage)

    ls = LabelSpace(
        category=sorted(keep_cats),
        gender=sorted(set(genders)),
        season=["spring", "summer", "autumn", "winter"],
        usage=keep_usages,
        color=keep_colors,
    )

    records = []
    for r in rows:
        if r["category"] not in keep_cats:
            continue
        records.append({
            "row": r["row"],
            "category": ls.category.index(r["category"]),
            "gender": _idx(ls.gender, r["gender"]),
            "season": _idx(ls.season, r["season"]),
            "usage": _idx(ls.usage, r["usage"]),
            "color": _idx(ls.color, r["color"]),
        })
    return records, ls


def split_records(records, seed=42, val_frac=0.1, test_frac=0.1):
    rng = np.random.default_rng(seed)
    idx = np.arange(len(records))
    rng.shuffle(idx)
    n_test = int(len(idx) * test_frac)
    n_val = int(len(idx) * val_frac)
    test = [records[i] for i in idx[:n_test]]
    val = [records[i] for i in idx[n_test:n_test + n_val]]
    train = [records[i] for i in idx[n_test + n_val:]]
    return train, val, test


def make_transform(train: bool):
    from torchvision import transforms
    aug = []
    if train:
        aug = [transforms.RandomHorizontalFlip(),
               transforms.ColorJitter(0.1, 0.1, 0.1)]
    return transforms.Compose([
        transforms.Resize((IMG_SIZE, IMG_SIZE)),
        *aug,
        transforms.ToTensor(),
        transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
    ])


class FashionDataset(Dataset):
    def __init__(self, hf_dataset, records, train: bool):
        self.ds = hf_dataset
        self.records = records
        self.tf = make_transform(train)

    def __len__(self):
        return len(self.records)

    def __getitem__(self, i):
        r = self.records[i]
        img = self.ds[r["row"]]["image"].convert("RGB")
        x = self.tf(img)
        y = {k: torch.tensor(r[k], dtype=torch.long)
             for k in ("category", "gender", "season", "usage", "color")}
        return x, y
