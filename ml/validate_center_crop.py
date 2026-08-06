"""Validate centered-square cropping from a u2netp mask (mirrors the Swift math
in ImageProcessing.centeredSquareCrop). Proves the garment is centered + tightly
framed in the square, using the clean saliency mask instead of SegFormer's."""
import os
import numpy as np
import torch
from PIL import Image
from datasets import load_dataset
from u2net_common import SIZE, load_u2netp, SegExport

ART = os.path.join(os.path.dirname(__file__), "artifacts")
PAD = 0.12


def u2netp_mask(export, img):
    a = np.asarray(img.convert("RGB").resize((SIZE, SIZE)), np.float32) / 255.0
    t = torch.from_numpy(a).permute(2, 0, 1).unsqueeze(0)
    with torch.no_grad():
        m = export(t)[0, 0].numpy()
    return (m * 255).astype(np.uint8)


def centered_square(imgW, imgH, bbox):
    minX, minY, w, h = bbox
    x = minX - w * PAD; y = minY - h * PAD
    w2 = w + 2 * w * PAD; h2 = h + 2 * h * PAD
    x = max(0, x); y = max(0, y)
    w2 = min(w2, imgW - x); h2 = min(h2, imgH - y)
    midX, midY = x + w2 / 2, y + h2 / 2
    maxSide = min(imgW, imgH)
    side = min(max(w2, h2), maxSide)
    ox = min(max(0, midX - side / 2), imgW - side)
    oy = min(max(0, midY - side / 2), imgH - side)
    return int(round(ox)), int(round(oy)), int(round(side))


def main():
    os.makedirs(ART, exist_ok=True)
    export = SegExport(load_u2netp()).eval()
    ds = load_dataset("ashraq/fashion-product-images-small", split="train")

    tiles = []
    for idx in [0, 250, 900, 1500]:
        img = ds[idx]["image"].convert("RGB")
        W, H = img.size
        mask_small = Image.fromarray(u2netp_mask(export, img), "L")
        mask = mask_small.resize((W, H))
        arr = np.asarray(mask)
        ys, xs = np.where(arr > 24)
        if len(xs) == 0:
            continue
        bbox = (xs.min(), ys.min(), xs.max() - xs.min() + 1, ys.max() - ys.min() + 1)
        ox, oy, side = centered_square(W, H, bbox)

        crop = img.crop((ox, oy, ox + side, oy + side)).convert("RGBA")
        cmask = mask.crop((ox, oy, ox + side, oy + side))
        cut = crop.copy(); cut.putalpha(cmask)
        checker = Image.new("RGBA", (side, side), (235, 235, 235, 255))
        on = Image.alpha_composite(checker, cut).resize((SIZE, SIZE))
        tiles.append(on)

    if tiles:
        sheet = Image.new("RGBA", (SIZE * len(tiles), SIZE), (255, 255, 255, 255))
        for i, t in enumerate(tiles):
            sheet.paste(t, (SIZE * i, 0))
        out = os.path.join(ART, "centered_square_crops.png")
        sheet.convert("RGB").save(out)
        print(f"saved {out}  (each tile = centered square cutout)")


if __name__ == "__main__":
    main()
