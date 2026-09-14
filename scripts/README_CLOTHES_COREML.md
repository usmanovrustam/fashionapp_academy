# Strong clothes Core ML (Nook)

Build **one** on-device clothes parser by collecting multiple Hugging Face teachers
and either distilling them into a SegFormer-B2 student or exporting the best ATR
teacher. Output replaces `fashionapp/ClothesSegFormer.mlpackage` (same I/O the
iOS scanner already expects: `pixel_values` → `logits`, ATR 18 labels).

## Teachers

| Repo | Role |
|------|------|
| `mattmdjaga/segformer_b0_clothes` | Fast ATR prior |
| `mattmdjaga/segformer_b2_clothes` | Current Nook baseline |
| `sayeed99/segformer_b3_clothes` | Stronger ATR |
| `fashn-ai/fashn-human-parser` | Fashion-tuned (labels remapped → ATR) |

## Setup

```bash
pip install -r scripts/requirements-ml.txt
```

Prefer **Mac + Apple Silicon** (or CUDA) for distillation. Core ML conversion
with `coremltools` is most reliable on macOS.

## Commands

```bash
# Download teachers + write manifest
python3 scripts/build_strong_clothes_coreml.py --mode collect

# Distill multi-teacher → student (GPU recommended)
python3 scripts/build_strong_clothes_coreml.py --mode distill --steps 800

# Export distilled student to Core ML
python3 scripts/build_strong_clothes_coreml.py --mode export --source student

# One shot (collect → distill → export), fall back to B3 if distill fails
python3 scripts/build_strong_clothes_coreml.py --mode all --steps 800 --fallback-best-atr

# Skip distill — ship strongest ATR teacher as Core ML
python3 scripts/build_strong_clothes_coreml.py --mode export --source best-atr --skip-fashn

# Include FASHN fashion teacher (remapped → ATR). Omit --skip-fashn
python3 scripts/build_strong_clothes_coreml.py --mode all --steps 1500
```

The distilled student keeps **SegFormer-B2 size** (~53MB float16 Core ML) while absorbing
soft labels from B0/B2/B3 (+ optional FASHN). Best KL checkpoint is restored automatically.

On a Mac GPU / CUDA box, prefer `--steps 1500+` before shipping a new `.mlpackage`.

Legacy single-model exporter: `scripts/export_clothes_segformer_coreml.py`.

## iOS contract

Do not change tensor names or label indices without updating
`ClothesSegFormerParser.swift` and `ClothesSegFormerLabels.json`.
