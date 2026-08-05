# Sylyo on-device ML pipeline

Trains **one multi-task CoreML model** for the clothing scanner and wardrobe
search, replacing the aspect-ratio / pixel-bucket heuristics in
`fashionapp/Infrastructure/Vision/ClothingClassifier.swift`.

```
image ─▶ MobileNetV3-Small backbone ─▶ 256-d trunk ─┬─▶ category   (13 classes)
                                                     ├─▶ gender     (4)
                                                     ├─▶ season     (4)
                                                     ├─▶ usage       (5)
                                                     ├─▶ base colour (23)
                                                     └─▶ 256-d embedding (similarity)
```

The backbone is ImageNet-pretrained and frozen; we precompute its features once
and train the shared trunk + task heads on top. Everything runs on CPU in a
couple of minutes. Inference on device is pure **CoreML on a `CVPixelBuffer`** —
no Vision framework.

## Data

[`ashraq/fashion-product-images-small`](https://huggingface.co/datasets/ashraq/fashion-product-images-small)
(~44k real product photos with `articleType`, `gender`, `baseColour`, `season`,
`usage` labels). `taxonomy.py` maps those onto the app's `ClothingCategory` /
`Season` enums and drops non-wardrobe master categories (Personal Care, etc.).

## Results (held-out test set, 4,177 items)

| Task | Test accuracy |
|---|---|
| **Category** (13) | **95.8%** |
| Gender (4) | 91.0% |
| Usage (5) | 90.5% |
| Base colour (23) | 66.4% |
| Season (4) | 71.3% |
| Similarity retrieval | precision@5 = **92.6%** (random baseline 19.9%) |

See `artifacts/metrics.json`.

## Reproduce

```bash
python -m venv .venv && source .venv/bin/activate
pip install --index-url https://download.pytorch.org/whl/cpu torch==2.5.1 torchvision==0.20.1
pip install -r requirements.txt

python train.py --epochs 60          # -> artifacts/checkpoint.pt + metrics.json
python export_coreml.py              # -> artifacts/FashionMultiTask.mlpackage
python eval_similarity.py            # embedding retrieval metrics
```

Quick smoke run: `python train.py --epochs 5 --limit 4000`.

## Files

| File | Purpose |
|---|---|
| `taxonomy.py` | dataset label → app enum mapping |
| `data.py` | filtering, label vocab, splits, transforms |
| `model.py` | `MultiTaskFashionNet` (backbone + heads + embedding) |
| `train.py` | feature extraction, head training, evaluation |
| `export_coreml.py` | Torch → CoreML `.mlpackage` (image input, softmax + embedding outputs) |
| `eval_similarity.py` | embedding retrieval precision |

## Using the model in the app

`export_coreml.py` writes `artifacts/FashionMultiTask.mlpackage`; a copy is
committed at `fashionapp/FashionMultiTask.mlpackage`. To ship it:

1. In Xcode, drag `fashionapp/FashionMultiTask.mlpackage` into the app target
   (same as `u2net.mlpackage`) so it compiles to `FashionMultiTask.mlmodelc`.
2. `AppContainer` already prefers `CoreMLClothingDetector` /
   `CoreMLClothingMetadataExtractor` and exposes `imageSearch`
   (`CoreMLWardrobeImageSearch`) when the compiled model is bundled, and falls
   back to the heuristics otherwise.

Labels are embedded in the model metadata (`labels_json`) and also committed at
`fashionapp/labels.json` as a fallback resource.

## Notes / limits

- Trained on CPU with a frozen backbone. For a stronger production model, run on
  a GPU box, unfreeze the backbone, and swap in a larger dataset
  (DeepFashion2 / Fashionpedia) — the pipeline is dataset-agnostic via `taxonomy.py`.
- Source photos are low-res (60×80), which caps colour/season accuracy; real
  camera captures should do better.
- CoreML **inference** can only be executed on macOS; this pipeline validates the
  PyTorch model (real accuracy) and the CoreML export structurally (Torch
  eager-vs-traced parity = 0, spec I/O verified). On-device numerical validation
  must be done in Xcode on a Mac.
