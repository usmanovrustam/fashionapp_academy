"""Run Nook's garment cutout on any photo — mirrors the on-device pipeline.

  python run_cutout.py /path/to/photo.jpg [out_dir]

Produces, in out_dir (default: alongside the input):
  <name>_mask.png     raw u2netp saliency mask
  <name>_clean.png    cleaned mask (largest component + filled holes)
  <name>_square.jpg   centered square crop (what Storage would keep)
  <name>_cutout.png   transparent cutout (what the app shows)

Use this to see exactly what the model does with a given photo (e.g. to tell a
petticoat apart from background).
"""
import os
import sys
import numpy as np
import torch
from PIL import Image
from scipy import ndimage

from u2net_common import SIZE, load_u2netp, SegExport

PAD = 0.12
THRESH = 128


def saliency_mask(export, img):
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
    comp = labels == (int(np.argmax(sizes)) + 1)
    comp = ndimage.binary_fill_holes(comp)
    return (comp * 255).astype(np.uint8)


def centered_square(W, H, arr):
    ys, xs = np.where(arr > 24)
    if len(xs) == 0:
        side = min(W, H)
        return (W - side) // 2, (H - side) // 2, side
    minX, minY, w, h = xs.min(), ys.min(), xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    x = max(0, minX - w * PAD); y = max(0, minY - h * PAD)
    w2 = min(w + 2 * w * PAD, W - x); h2 = min(h + 2 * h * PAD, H - y)
    midX, midY = x + w2 / 2, y + h2 / 2
    side = min(max(w2, h2), min(W, H))
    ox = min(max(0, midX - side / 2), W - side)
    oy = min(max(0, midY - side / 2), H - side)
    return int(round(ox)), int(round(oy)), int(round(side))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    path = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(path))
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.splitext(os.path.basename(path))[0]

    export = SegExport(load_u2netp()).eval()
    img = Image.open(path).convert("RGB")
    # Match the app: work at up to 1600px.
    scale = 1600 / max(img.size)
    if scale < 1:
        img = img.resize((int(img.width * scale), int(img.height * scale)))
    W, H = img.size

    raw = Image.fromarray(saliency_mask(export, img), "L").resize((W, H))
    clean = Image.fromarray(cleaned(np.asarray(raw)), "L")
    clean_arr = np.asarray(clean)
    ox, oy, side = centered_square(W, H, clean_arr)

    crop = img.crop((ox, oy, ox + side, oy + side))
    cmask = clean.crop((ox, oy, ox + side, oy + side))
    cut = crop.convert("RGBA"); cut.putalpha(cmask)

    raw.save(os.path.join(out_dir, f"{name}_mask.png"))
    clean.save(os.path.join(out_dir, f"{name}_clean.png"))
    crop.save(os.path.join(out_dir, f"{name}_square.jpg"), quality=92)
    cut.save(os.path.join(out_dir, f"{name}_cutout.png"))
    print(f"foreground coverage: {(clean_arr > 24).mean():.1%}")
    print(f"wrote {name}_mask.png, {name}_clean.png, {name}_square.jpg, {name}_cutout.png to {out_dir}")


if __name__ == "__main__":
    main()
