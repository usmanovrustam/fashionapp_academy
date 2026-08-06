"""Validate mask cleanup (binarize + largest connected component + fill holes)
then centered square crop. Mirrors the Swift ImageProcessing.cleanedMask logic.
Removes stray background blobs and centers the garment tightly in the square."""
import os
import numpy as np
import torch
from PIL import Image
from scipy import ndimage
from datasets import load_dataset
from u2net_common import SIZE, load_u2netp, SegExport

ART = os.path.join(os.path.dirname(__file__), "artifacts")
PAD = 0.12
THRESH = 128


def u2netp_mask(export, img):
    a = np.asarray(img.convert("RGB").resize((SIZE, SIZE)), np.float32) / 255.0
    t = torch.from_numpy(a).permute(2, 0, 1).unsqueeze(0)
    with torch.no_grad():
        m = export(t)[0, 0].numpy()
    return (m * 255).astype(np.uint8)


def cleaned(mask_u8):
    binary = mask_u8 >= THRESH
    labels, n = ndimage.label(binary)
    if n == 0:
        return np.zeros_like(mask_u8)
    sizes = ndimage.sum(binary, labels, range(1, n + 1))
    largest = int(np.argmax(sizes)) + 1
    comp = labels == largest
    comp = ndimage.binary_fill_holes(comp)
    return (comp * 255).astype(np.uint8)


def centered_square(W, H, bbox):
    minX, minY, w, h = bbox
    x = max(0, minX - w * PAD); y = max(0, minY - h * PAD)
    w2 = min(w + 2 * w * PAD, W - x); h2 = min(h + 2 * h * PAD, H - y)
    midX, midY = x + w2 / 2, y + h2 / 2
    side = min(max(w2, h2), min(W, H))
    ox = min(max(0, midX - side / 2), W - side)
    oy = min(max(0, midY - side / 2), H - side)
    return int(round(ox)), int(round(oy)), int(round(side))


def main():
    os.makedirs(ART, exist_ok=True)
    export = SegExport(load_u2netp()).eval()
    ds = load_dataset("ashraq/fashion-product-images-small", split="train")

    rows = []
    for idx in [250, 900, 1500, 42]:
        img = ds[idx]["image"].convert("RGB")
        W, H = img.size
        raw = Image.fromarray(u2netp_mask(export, img), "L").resize((W, H))
        raw_arr = np.asarray(raw)
        clean_arr = cleaned(np.asarray(Image.fromarray(u2netp_mask(export, img), "L").resize((W, H))))
        ys, xs = np.where(clean_arr > 24)
        if len(xs) == 0:
            continue
        bbox = (xs.min(), ys.min(), xs.max() - xs.min() + 1, ys.max() - ys.min() + 1)
        ox, oy, side = centered_square(W, H, bbox)
        cmask = Image.fromarray(clean_arr, "L").crop((ox, oy, ox + side, oy + side))
        crop = img.crop((ox, oy, ox + side, oy + side)).convert("RGBA")
        cut = crop.copy(); cut.putalpha(cmask)
        checker = Image.new("RGBA", (side, side), (235, 235, 235, 255))
        on = Image.alpha_composite(checker, cut).resize((SIZE, SIZE))
        rawvis = raw.convert("RGBA").resize((SIZE, SIZE))
        row = Image.new("RGBA", (SIZE * 2, SIZE), (255, 255, 255, 255))
        row.paste(rawvis, (0, 0)); row.paste(on, (SIZE, 0))
        rows.append(row)

    sheet = Image.new("RGBA", (SIZE * 2, SIZE * len(rows)), (255, 255, 255, 255))
    for i, r in enumerate(rows):
        sheet.paste(r, (0, SIZE * i))
    out = os.path.join(ART, "clean_centered.png")
    sheet.convert("RGB").save(out)
    print(f"saved {out}  (raw mask | cleaned + centered cutout)")


if __name__ == "__main__":
    main()
