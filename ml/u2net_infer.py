"""Validate the U2NETP weights: run real segmentation and save a visual.

Proves the model produces a genuine foreground mask (coverage well below 100%),
unlike the previous weightless model whose Swift fallback returns an all-white
mask (100% coverage -> no background removed).
"""
from __future__ import annotations

import os

import numpy as np
import torch
from PIL import Image

from u2net_common import SIZE, load_u2netp, SegExport

ART = os.path.join(os.path.dirname(__file__), "artifacts")


def preprocess(img: Image.Image) -> torch.Tensor:
    img = img.convert("RGB").resize((SIZE, SIZE))
    arr = np.asarray(img).astype(np.float32) / 255.0
    return torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0)


def cutout(img: Image.Image, mask: np.ndarray) -> Image.Image:
    rgba = img.convert("RGBA").resize((SIZE, SIZE))
    alpha = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
    rgba.putalpha(alpha)
    return rgba


def main():
    os.makedirs(ART, exist_ok=True)
    export = SegExport(load_u2netp()).eval()

    from datasets import load_dataset
    ds = load_dataset("ashraq/fashion-product-images-small", split="train")
    # A few varied garments.
    idxs = [0, 100, 250, 900]
    tiles = []
    for i in idxs:
        img = ds[i]["image"].convert("RGB")
        with torch.no_grad():
            mask_t = export(preprocess(img))[0, 0].numpy()
        coverage = float((mask_t > 0.5).mean())
        print(f"  item {i}: foreground coverage = {coverage:.1%}")
        base = img.resize((SIZE, SIZE)).convert("RGBA")
        maskimg = Image.fromarray((mask_t * 255).astype(np.uint8), "L").convert("RGBA")
        cut = cutout(img, mask_t)
        checker = Image.new("RGBA", (SIZE, SIZE), (230, 230, 230, 255))
        cut_on_bg = Image.alpha_composite(checker, cut)
        row = Image.new("RGBA", (SIZE * 3, SIZE), (255, 255, 255, 255))
        row.paste(base, (0, 0)); row.paste(maskimg, (SIZE, 0)); row.paste(cut_on_bg, (SIZE * 2, 0))
        tiles.append(row)

    sheet = Image.new("RGBA", (SIZE * 3, SIZE * len(tiles)), (255, 255, 255, 255))
    for r, row in enumerate(tiles):
        sheet.paste(row, (0, SIZE * r))
    out = os.path.join(ART, "u2netp_cutouts.png")
    sheet.convert("RGB").save(out)
    print(f"Saved {out}  (columns: original | mask | cutout)")


if __name__ == "__main__":
    main()
