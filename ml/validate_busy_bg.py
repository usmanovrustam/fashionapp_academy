"""Validate u2netp cutout on a garment over a BUSY background (the flat-lay case).

Composites a solid garment onto a patterned backdrop (like the user's floral
duvet), runs u2netp, and shows it isolates the garment vs. the background.
"""
import os
import numpy as np
import torch
from PIL import Image
from datasets import load_dataset
from u2net_common import SIZE, load_u2netp, SegExport

ART = os.path.join(os.path.dirname(__file__), "artifacts")


def preprocess(img):
    a = np.asarray(img.convert("RGB").resize((SIZE, SIZE)), np.float32) / 255.0
    return torch.from_numpy(a).permute(2, 0, 1).unsqueeze(0)


def main():
    os.makedirs(ART, exist_ok=True)
    export = SegExport(load_u2netp()).eval()
    ds = load_dataset("ashraq/fashion-product-images-small", split="train")

    # Foreground garment (solid) + a patterned garment used as a "busy" backdrop.
    fg = ds[900]["image"].convert("RGB").resize((260, 340))
    pattern = ds[12]["image"].convert("RGB").resize((512, 512))
    canvas = pattern.copy()
    # Paste garment roughly centered over the patterned backdrop.
    canvas.paste(fg, (126, 90))
    composite = canvas.resize((SIZE, SIZE))

    with torch.no_grad():
        mask = export(preprocess(composite))[0, 0].numpy()
    coverage = float((mask > 0.5).mean())
    print(f"foreground coverage on busy background = {coverage:.1%}")

    base = composite.convert("RGBA")
    alpha = Image.fromarray((mask * 255).astype(np.uint8), "L")
    cut = base.copy(); cut.putalpha(alpha)
    checker = Image.new("RGBA", (SIZE, SIZE), (235, 235, 235, 255))
    cut_on = Image.alpha_composite(checker, cut)
    maskimg = alpha.convert("RGBA")

    sheet = Image.new("RGBA", (SIZE * 3, SIZE), (255, 255, 255, 255))
    sheet.paste(base, (0, 0)); sheet.paste(maskimg, (SIZE, 0)); sheet.paste(cut_on, (SIZE * 2, 0))
    out = os.path.join(ART, "u2netp_busy_bg.png")
    sheet.convert("RGB").save(out)
    print(f"saved {out}  (busy composite | mask | clean cutout)")


if __name__ == "__main__":
    main()
