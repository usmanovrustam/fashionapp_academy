#!/usr/bin/env python3
"""
Collect multiple Hugging Face clothes parsers and produce ONE strong Core ML
package for Nook (`fashionapp/ClothesSegFormer.mlpackage`).

Modes
-----
  collect   Download / cache teacher checkpoints + write a manifest.
  distill   Multi-teacher knowledge distillation → single student (ATR 18 cls).
  export    Trace the student (or a chosen teacher) → Core ML mlprogram.
  all       collect → distill → export (default).

Teachers (ATR-compatible 18-class schema unless noted)
------------------------------------------------------
  * mattmdjaga/segformer_b0_clothes
  * mattmdjaga/segformer_b2_clothes   (current production baseline)
  * sayeed99/segformer_b3_clothes     (stronger ATR)
  * fashn-ai/fashn-human-parser       (fashion-tuned; remapped → ATR)

The student defaults to SegFormer-B2 so the on-device size stays close to today's
bundle while absorbing soft labels from larger / fashion-tuned teachers.

Prefer running distill+export on a Mac with Apple Silicon (or any CUDA GPU).
CPU works for a smoke distill but is slow.

Usage
-----
  pip install -r scripts/requirements-ml.txt
  python3 scripts/build_strong_clothes_coreml.py --mode all --steps 800
  python3 scripts/build_strong_clothes_coreml.py --mode export --source teacher:sayeed99/segformer_b3_clothes
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from tqdm import tqdm
from transformers import SegformerForSemanticSegmentation


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "fashionapp" / "ClothesSegFormer.mlpackage"
DEFAULT_LABELS = ROOT / "fashionapp" / "ClothesSegFormerLabels.json"
CACHE_DIR = ROOT / "scripts" / ".clothes_model_cache"
STUDENT_CKPT = CACHE_DIR / "student_strong_b2"

ATR_LABELS = [
    "Background",
    "Hat",
    "Hair",
    "Sunglasses",
    "Upper-clothes",
    "Skirt",
    "Pants",
    "Dress",
    "Belt",
    "Left-shoe",
    "Right-shoe",
    "Face",
    "Left-leg",
    "Right-leg",
    "Left-arm",
    "Right-arm",
    "Bag",
    "Scarf",
]

# FASHN human-parser (18 classes) → ATR index. Unmapped body bits go to nearest wear / bg.
FASHN_TO_ATR = {
    0: 0,   # background
    1: 11,  # face
    2: 2,   # hair
    3: 4,   # top → Upper-clothes
    4: 7,   # dress
    5: 5,   # skirt
    6: 6,   # pants
    7: 8,   # belt
    8: 16,  # bag
    9: 1,   # hat
    10: 17, # scarf
    11: 3,  # glasses → Sunglasses
    12: 14, # arms → Left-arm (symmetric merge OK for distillation)
    13: 14, # hands → arms
    14: 12, # legs → Left-leg
    15: 9,  # feet → Left-shoe (shoe proxy)
    16: 4,  # torso → Upper-clothes
    17: 0,  # jewelry → background (not in ATR garments)
}

TEACHERS = [
    {
        "repo": "mattmdjaga/segformer_b0_clothes",
        "schema": "atr",
        "weight": 0.15,
        "role": "fast ATR prior",
    },
    {
        "repo": "mattmdjaga/segformer_b2_clothes",
        "schema": "atr",
        "weight": 0.30,
        "role": "current Nook baseline",
    },
    {
        "repo": "sayeed99/segformer_b3_clothes",
        "schema": "atr",
        "weight": 0.35,
        "role": "stronger ATR teacher",
    },
    {
        "repo": "fashn-ai/fashn-human-parser",
        "schema": "fashn",
        "weight": 0.20,
        "role": "fashion / try-on tuned",
    },
]


@dataclass
class ManifestTeacher:
    repo: str
    schema: str
    weight: float
    role: str
    loaded: bool
    params_m: float | None = None
    error: str | None = None


class SegformerLogits(torch.nn.Module):
    """Trace-friendly wrapper: pixel_values → logits [1, C, H', W']."""

    def __init__(self, model: SegformerForSemanticSegmentation):
        super().__init__()
        self.model = model

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        return self.model(pixel_values=pixel_values).logits


def _device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda")
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def _count_params(model: torch.nn.Module) -> float:
    return sum(p.numel() for p in model.parameters()) / 1e6


def load_segformer(repo: str) -> SegformerForSemanticSegmentation:
    print(f"  ↓ {repo}", flush=True)
    model = SegformerForSemanticSegmentation.from_pretrained(repo)
    model.eval()
    return model


def remap_fashn_logits_to_atr(logits: torch.Tensor) -> torch.Tensor:
    """logits: [B, 18_fashn, H, W] → [B, 18_atr, H, W] via soft class pooling."""
    b, c, h, w = logits.shape
    atr = torch.full((b, 18, h, w), -20.0, device=logits.device, dtype=logits.dtype)
    # Softmax in FASHN space, accumulate probability mass into ATR bins, then log.
    probs = logits.softmax(dim=1)
    atr_probs = torch.zeros(b, 18, h, w, device=logits.device, dtype=logits.dtype)
    for src, dst in FASHN_TO_ATR.items():
        if src < c:
            atr_probs[:, dst] += probs[:, src]
    atr_probs = atr_probs.clamp_min(1e-8)
    return atr_probs.log()


@torch.no_grad()
def teacher_logits(
    teachers: list[tuple[dict, SegformerForSemanticSegmentation]],
    pixel_values: torch.Tensor,
    out_hw: tuple[int, int],
) -> torch.Tensor:
    """Weighted average of teacher probabilities → log-probs in ATR space."""
    device = pixel_values.device
    blended = torch.zeros(pixel_values.size(0), 18, out_hw[0], out_hw[1], device=device)
    weight_sum = 0.0
    for meta, model in teachers:
        logits = model(pixel_values=pixel_values).logits
        if meta["schema"] == "fashn":
            logits = remap_fashn_logits_to_atr(logits)
        logits = F.interpolate(logits, size=out_hw, mode="bilinear", align_corners=False)
        blended += meta["weight"] * logits.softmax(dim=1)
        weight_sum += meta["weight"]
    blended = (blended / max(weight_sum, 1e-8)).clamp_min(1e-8)
    return blended.log()


def collect_teachers(skip_fashn: bool = False) -> tuple[list[ManifestTeacher], list[tuple[dict, SegformerForSemanticSegmentation]]]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    manifest: list[ManifestTeacher] = []
    loaded: list[tuple[dict, SegformerForSemanticSegmentation]] = []
    for meta in TEACHERS:
        if skip_fashn and meta["schema"] == "fashn":
            manifest.append(
                ManifestTeacher(
                    repo=meta["repo"],
                    schema=meta["schema"],
                    weight=meta["weight"],
                    role=meta["role"],
                    loaded=False,
                    error="skipped (--skip-fashn)",
                )
            )
            continue
        try:
            model = load_segformer(meta["repo"])
            params = _count_params(model)
            loaded.append((meta, model))
            manifest.append(
                ManifestTeacher(
                    repo=meta["repo"],
                    schema=meta["schema"],
                    weight=meta["weight"],
                    role=meta["role"],
                    loaded=True,
                    params_m=round(params, 2),
                )
            )
        except Exception as exc:  # noqa: BLE001
            print(f"  ⚠️ failed {meta['repo']}: {exc}", flush=True)
            manifest.append(
                ManifestTeacher(
                    repo=meta["repo"],
                    schema=meta["schema"],
                    weight=meta["weight"],
                    role=meta["role"],
                    loaded=False,
                    error=str(exc),
                )
            )
    path = CACHE_DIR / "teachers_manifest.json"
    path.write_text(json.dumps([asdict(m) for m in manifest], indent=2))
    print(f"Wrote {path}", flush=True)
    if not loaded:
        raise RuntimeError("No teachers loaded — check network / Hugging Face access.")
    # Renormalize weights over successfully loaded teachers.
    total_w = sum(m["weight"] for m, _ in loaded)
    for meta, _ in loaded:
        meta["weight"] = meta["weight"] / total_w
    return manifest, loaded


def iter_distill_images(limit: int, size: int) -> Iterable[torch.Tensor]:
    """Yield ImageNet-normalized CHW batches from HF parsing dataset or synthetic fallback."""
    mean = torch.tensor([0.485, 0.456, 0.406]).view(3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225]).view(3, 1, 1)

    def normalize(img: Image.Image) -> torch.Tensor:
        img = img.convert("RGB").resize((size, size), Image.BILINEAR)
        arr = np.asarray(img).astype(np.float32) / 255.0
        t = torch.from_numpy(arr).permute(2, 0, 1)
        return (t - mean) / std

    try:
        from datasets import load_dataset

        print("Loading mattmdjaga/human_parsing_dataset (streaming)…", flush=True)
        ds = load_dataset("mattmdjaga/human_parsing_dataset", split="train", streaming=True)
        n = 0
        for row in ds:
            image = row.get("image") or row.get("pixel_values")
            if image is None:
                continue
            if not isinstance(image, Image.Image):
                image = Image.fromarray(np.asarray(image))
            yield normalize(image).unsqueeze(0)
            n += 1
            if n >= limit:
                return
    except Exception as exc:  # noqa: BLE001
        print(f"Dataset stream unavailable ({exc}); using synthetic + cache images.", flush=True)

    # Local cache images if any.
    img_dir = CACHE_DIR / "sample_images"
    img_dir.mkdir(parents=True, exist_ok=True)
    locals_ = sorted(img_dir.glob("*.jpg")) + sorted(img_dir.glob("*.png"))
    for path in locals_[:limit]:
        yield normalize(Image.open(path)).unsqueeze(0)

    # Synthetic colorful blobs so the pipeline always runs.
    remaining = max(0, limit - len(locals_))
    rng = np.random.default_rng(42)
    for _ in range(remaining):
        arr = rng.integers(0, 255, size=(size, size, 3), dtype=np.uint8)
        # Soft rectangle “garment” region.
        y0, x0 = rng.integers(40, size // 3, size=2)
        y1, x1 = rng.integers(size // 2, size - 20, size=2)
        color = rng.integers(30, 220, size=3)
        arr[y0:y1, x0:x1] = color
        yield normalize(Image.fromarray(arr)).unsqueeze(0)


def distill(
    teachers: list[tuple[dict, SegformerForSemanticSegmentation]],
    steps: int,
    batch_images: int,
    size: int,
    lr: float,
    temperature: float,
    student_repo: str,
) -> SegformerForSemanticSegmentation:
    device = _device()
    print(f"Distilling on {device} for {steps} steps…", flush=True)
    student = SegformerForSemanticSegmentation.from_pretrained(student_repo)
    student.train()
    student.to(device)
    for _, teacher in teachers:
        teacher.to(device)
        teacher.eval()
        for p in teacher.parameters():
            p.requires_grad_(False)

    opt = torch.optim.AdamW(student.parameters(), lr=lr, weight_decay=1e-4)
    image_iter = iter_distill_images(limit=max(256, min(steps, 512)), size=size)
    images = list(image_iter)
    print(f"Distill image pool: {len(images)}", flush=True)
    if not images:
        raise RuntimeError("No distillation images available.")

    best_loss = math.inf
    best_state: dict | None = None
    for step in tqdm(range(steps), desc="distill"):
        batch = images[step % len(images)].to(device)
        # Single-image batches keep CPU memory predictable; stack a few if requested.
        if batch_images > 1:
            picks = [images[(step + i) % len(images)] for i in range(batch_images)]
            batch = torch.cat(picks, dim=0).to(device)

        with torch.no_grad():
            # Probe student head spatial size once from a forward, then match teachers.
            probe = student(pixel_values=batch).logits
            th = teacher_logits(teachers, batch, out_hw=probe.shape[-2:])
            t_prob = F.softmax(th / temperature, dim=1)

        s_logits = student(pixel_values=batch).logits
        if s_logits.shape[-2:] != t_prob.shape[-2:]:
            s_logits = F.interpolate(s_logits, size=t_prob.shape[-2:], mode="bilinear", align_corners=False)
        s_log_prob = F.log_softmax(s_logits / temperature, dim=1)
        loss = F.kl_div(s_log_prob, t_prob, reduction="batchmean") * (temperature**2)

        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(student.parameters(), 1.0)
        opt.step()

        loss_value = float(loss.item())
        if loss_value < best_loss and math.isfinite(loss_value):
            best_loss = loss_value
            best_state = {k: v.detach().cpu().clone() for k, v in student.state_dict().items()}

        if step % 50 == 0 or step == steps - 1:
            print(
                f"  step {step}/{steps}  kl={loss_value:.4f}  best={best_loss:.4f}",
                flush=True,
            )

    if best_state is not None:
        student.load_state_dict(best_state)
        print(f"Restored best student checkpoint (kl={best_loss:.4f})", flush=True)

    student.eval()
    student.cpu()
    for _, teacher in teachers:
        teacher.cpu()

    STUDENT_CKPT.mkdir(parents=True, exist_ok=True)
    student.save_pretrained(STUDENT_CKPT)
    (STUDENT_CKPT / "distill_meta.json").write_text(
        json.dumps(
            {
                "steps": steps,
                "temperature": temperature,
                "student_repo": student_repo,
                "best_kl": best_loss if math.isfinite(best_loss) else None,
                "teachers": [
                    {"repo": m["repo"], "weight": m["weight"], "schema": m["schema"]}
                    for m, _ in teachers
                ],
                "device": str(device),
            },
            indent=2,
        )
    )
    print(f"Saved student → {STUDENT_CKPT}", flush=True)
    return student


def rename_output_to_logits(package_path: Path) -> None:
    """Rename the primary output feature to `logits` in-place on disk."""
    try:
        import coremltools as ct
        from coremltools.models.utils import rename_feature

        packaged = ct.models.MLModel(str(package_path))
        spec = packaged.get_spec()
        out_name = spec.description.output[0].name
        if out_name == "logits":
            return
        rename_feature(spec, out_name, "logits")
        weights_dir = package_path / "Data" / "com.apple.CoreML" / "weights"
        renamed = ct.models.MLModel(spec, weights_dir=str(weights_dir))
        scratch = package_path.parent / f"{package_path.stem}.rename.mlpackage"
        if scratch.exists():
            shutil.rmtree(scratch)
        renamed.save(str(scratch))
        shutil.rmtree(package_path)
        scratch.rename(package_path)
        print("Renamed output feature → logits", flush=True)
    except Exception as exc:  # noqa: BLE001
        print(f"Warning: could not rename output to logits ({exc})", flush=True)


def export_coreml(
    model: SegformerForSemanticSegmentation,
    out: Path,
    size: int,
    version: str,
    source_desc: str,
    teachers_meta: list[dict] | None,
) -> None:
    import coremltools as ct

    wrapper = SegformerLogits(model)
    wrapper.eval()
    example = torch.randn(1, 3, size, size)
    print(f"Tracing at {size}x{size}…", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)
        traced = torch.jit.freeze(traced)

    print("Converting to Core ML (mlprogram, float16)…", flush=True)
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="pixel_values",
                shape=(1, 3, size, size),
                dtype=np.float32,
            )
        ],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )

    mlmodel.author = "Nook"
    mlmodel.license = "See upstream Hugging Face model cards for teacher licenses."
    mlmodel.short_description = (
        "Strong clothes segmentation (ATR 18 classes) distilled / selected for Nook. "
        f"Source: {source_desc}. Labels: "
        + ", ".join(f"{i}:{n}" for i, n in enumerate(ATR_LABELS))
    )
    mlmodel.version = version

    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        shutil.rmtree(out)
    mlmodel.save(str(out))
    rename_output_to_logits(out)
    print(f"Saved {out}", flush=True)

    labels = {
        "model": source_desc,
        "coreml_package": out.name,
        "input_size": size,
        "input": "pixel_values",
        "output": "logits",
        "labels": ATR_LABELS,
        "garment_class_ids": [1, 3, 4, 5, 6, 7, 8, 9, 10, 16, 17],
        "teachers": teachers_meta or [],
        "version": version,
        "notes": (
            "Strong Core ML clothes parser for Nook. Built by collecting multiple "
            "Hugging Face teachers (ATR SegFormers + optional FASHN) into one on-device model."
        ),
    }
    DEFAULT_LABELS.write_text(json.dumps(labels, indent=2) + "\n")
    print(f"Saved {DEFAULT_LABELS}", flush=True)


def resolve_export_model(
    source: str,
    teachers: list[tuple[dict, SegformerForSemanticSegmentation]] | None,
) -> tuple[SegformerForSemanticSegmentation, str, list[dict]]:
    """
    source:
      student                         → distilled checkpoint
      teacher:<repo>                  → single teacher export
      best-atr                        → sayeed99/segformer_b3_clothes (or best loaded ATR)
    """
    teachers_meta = (
        [{"repo": m["repo"], "weight": m["weight"], "schema": m["schema"], "role": m["role"]} for m, _ in teachers]
        if teachers
        else []
    )

    if source == "student":
        if not (STUDENT_CKPT / "config.json").exists():
            raise FileNotFoundError(
                f"No distilled student at {STUDENT_CKPT}. Run --mode distill first."
            )
        model = SegformerForSemanticSegmentation.from_pretrained(STUDENT_CKPT)
        model.eval()
        return model, f"distilled:{STUDENT_CKPT.name}", teachers_meta

    if source.startswith("teacher:"):
        repo = source.split(":", 1)[1]
        if teachers:
            for meta, model in teachers:
                if meta["repo"] == repo:
                    return model, repo, teachers_meta
        model = load_segformer(repo)
        return model, repo, [{"repo": repo, "weight": 1.0, "schema": "atr", "role": "direct export"}]

    if source == "best-atr":
        preferred = "sayeed99/segformer_b3_clothes"
        if teachers:
            for meta, model in teachers:
                if meta["repo"] == preferred:
                    return model, preferred, teachers_meta
            # Fall back to largest loaded ATR teacher.
            atr = [(m, mod) for m, mod in teachers if m["schema"] == "atr"]
            if atr:
                meta, model = max(atr, key=lambda x: _count_params(x[1]))
                return model, meta["repo"], teachers_meta
        model = load_segformer(preferred)
        return model, preferred, [{"repo": preferred, "weight": 1.0, "schema": "atr", "role": "best ATR"}]

    raise ValueError(f"Unknown --source {source}")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--mode", choices=["collect", "distill", "export", "all"], default="all")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--size", type=int, default=512)
    p.add_argument("--steps", type=int, default=400, help="Distillation steps")
    p.add_argument("--batch-images", type=int, default=1)
    p.add_argument("--lr", type=float, default=1e-5)
    p.add_argument("--temperature", type=float, default=2.0)
    p.add_argument(
        "--student-repo",
        default="mattmdjaga/segformer_b2_clothes",
        help="HF init weights for the student (keep B2 for mobile size)",
    )
    p.add_argument(
        "--source",
        default="student",
        help="export source: student | best-atr | teacher:<hf_repo>",
    )
    p.add_argument("--skip-fashn", action="store_true", help="Skip FASHN teacher if it fails / too heavy")
    p.add_argument("--version", default="2.0.0")
    p.add_argument(
        "--fallback-best-atr",
        action="store_true",
        help="If distill fails, export best ATR teacher instead of aborting",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    random.seed(42)
    torch.manual_seed(42)

    teachers = None
    if args.mode in {"collect", "distill", "all"} or (
        args.mode == "export" and args.source in {"best-atr", "student"} or args.source.startswith("teacher:")
    ):
        print("Collecting teachers…", flush=True)
        _, teachers = collect_teachers(skip_fashn=args.skip_fashn)

    if args.mode == "collect":
        return 0

    student = None
    if args.mode in {"distill", "all"}:
        assert teachers is not None
        try:
            student = distill(
                teachers=teachers,
                steps=args.steps,
                batch_images=args.batch_images,
                size=args.size,
                lr=args.lr,
                temperature=args.temperature,
                student_repo=args.student_repo,
            )
        except Exception as exc:  # noqa: BLE001
            print(f"Distill failed: {exc}", flush=True)
            if not args.fallback_best_atr:
                raise
            print("Falling back to best-atr export.", flush=True)
            args.source = "best-atr"

    if args.mode in {"export", "all"}:
        source = args.source
        if args.mode == "all" and student is not None and source == "student":
            model, desc, meta = student, f"distilled:{STUDENT_CKPT.name}", [
                {"repo": m["repo"], "weight": m["weight"], "schema": m["schema"], "role": m["role"]}
                for m, _ in (teachers or [])
            ]
        else:
            model, desc, meta = resolve_export_model(source, teachers)
        export_coreml(
            model=model,
            out=args.out,
            size=args.size,
            version=args.version,
            source_desc=desc,
            teachers_meta=meta,
        )

    print("Done.", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        raise SystemExit(130)
