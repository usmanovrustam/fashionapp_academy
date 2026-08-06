"""Run Nook's garment cutout on any photo — mirrors the on-device pipeline.

  python run_cutout.py /path/to/photo.jpg [out_dir]

Produces, in out_dir (default: alongside the input):
  <name>_mask.png     raw u2netp saliency mask
  <name>_clean.png    cleaned mask (largest component + filled holes)
  <name>_square.jpg   centered square crop (what Storage would keep)
  <name>_cutout.png   transparent cutout (what the app shows)

Deps: torch, numpy, pillow, huggingface_hub (no scipy / torchvision / coremltools).
"""
import os
import sys
from collections import deque

import numpy as np
import torch
from PIL import Image

from u2net_common import SIZE, load_u2netp, SegExport

PAD = 0.12
THRESH = 128


def saliency_mask(export, img):
    a = np.asarray(img.convert("RGB").resize((SIZE, SIZE)), np.float32) / 255.0
    t = torch.from_numpy(a).permute(2, 0, 1).unsqueeze(0)
    with torch.no_grad():
        m = export(t)[0, 0].numpy()
    return (m * 255).astype(np.uint8)


def clean_mask(mask_u8):
    """Binarize -> keep largest 4-connected component -> fill holes. Pure numpy."""
    binary = mask_u8 >= THRESH
    h, w = binary.shape
    label = np.zeros((h, w), np.int32)
    cur = best_label = best_size = 0
    for sy in range(h):
        for sx in range(w):
            if binary[sy, sx] and label[sy, sx] == 0:
                cur += 1
                size = 0
                dq = deque([(sy, sx)])
                label[sy, sx] = cur
                while dq:
                    y, x = dq.popleft()
                    size += 1
                    if y > 0 and binary[y - 1, x] and label[y - 1, x] == 0:
                        label[y - 1, x] = cur; dq.append((y - 1, x))
                    if y + 1 < h and binary[y + 1, x] and label[y + 1, x] == 0:
                        label[y + 1, x] = cur; dq.append((y + 1, x))
                    if x > 0 and binary[y, x - 1] and label[y, x - 1] == 0:
                        label[y, x - 1] = cur; dq.append((y, x - 1))
                    if x + 1 < w and binary[y, x + 1] and label[y, x + 1] == 0:
                        label[y, x + 1] = cur; dq.append((y, x + 1))
                if size > best_size:
                    best_size = size; best_label = cur
    if best_size == 0:
        return np.zeros_like(mask_u8)
    comp = label == best_label

    # Flood background from the border; enclosed zeros -> foreground.
    exterior = np.zeros((h, w), bool)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not comp[y, x] and not exterior[y, x]:
                exterior[y, x] = True; dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not comp[y, x] and not exterior[y, x]:
                exterior[y, x] = True; dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not comp[ny, nx] and not exterior[ny, nx]:
                exterior[ny, nx] = True; dq.append((ny, nx))
    filled = comp | (~exterior & ~comp)
    return (filled * 255).astype(np.uint8)


def centered_square(W, H, arr):
    ys, xs = np.where(arr > 24)
    if len(xs) == 0:
        side = min(W, H)
        return (W - side) // 2, (H - side) // 2, side
    minX, minY = xs.min(), ys.min()
    w, h = xs.max() - minX + 1, ys.max() - minY + 1
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
    path = os.path.expanduser(sys.argv[1])
    if not os.path.isfile(path):
        print(f"File not found: {path}\nPass a real photo path (tip: drag the file into Terminal).")
        sys.exit(1)
    out_dir = os.path.expanduser(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(path))
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.splitext(os.path.basename(path))[0]

    print("Loading model (first run downloads ~4.7MB weights)...")
    export = SegExport(load_u2netp()).eval()
    img = Image.open(path).convert("RGB")
    scale = 1600 / max(img.size)
    if scale < 1:
        img = img.resize((int(img.width * scale), int(img.height * scale)))
    W, H = img.size

    small = saliency_mask(export, img)
    clean_small = clean_mask(small)
    raw = Image.fromarray(small, "L").resize((W, H))
    clean = Image.fromarray(clean_small, "L").resize((W, H))
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
