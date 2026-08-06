# Nook on-device ML overview

Nook runs several CoreML models on device. They are **complementary**, not
competing — each owns one stage of the clothing pipeline.

| Model | Role | Input → Output | Where |
|---|---|---|---|
| **ClothesSegFormer** | Semantic clothing **segmentation / parsing** (isolate the garment, per-region masks) | image → class masks | `fashionapp/ClothesSegFormer.mlpackage`, `ClothesSegFormerParser.swift` |
| **FashionMultiTask** | Clothing **classification + attributes + embedding** | image → category / gender / season / usage / colour + 256-d embedding | `fashionapp/FashionMultiTask.mlpackage`, `CoreMLFashionModel.swift` (this PR) |
| **U²-Net** | Legacy saliency background remover | image → foreground mask | `fashionapp/u2net.mlpackage` |

## How they fit together in a scan

```
photo ─▶ [segmentation]  ClothesSegFormer / U²-Net  ─▶ garment cutout
      └▶ [understanding]  FashionMultiTask           ─▶ category + attributes + embedding
                                                         │
                                          wardrobe "Find similar" ◀─ embedding
```

- **Detection & metadata**: `CoreMLClothingDetector` + `CoreMLClothingMetadataExtractor`
  (FashionMultiTask) replace the aspect-ratio / pixel-bucket heuristics, wired in
  `AppContainer` with a heuristic fallback.
- **Segmentation / background removal**: unchanged — owned by the SegFormer/U²-Net
  path. This PR does not touch it.
- **Similarity**: `CoreMLWardrobeImageSearch` uses the FashionMultiTask embedding to
  power the wardrobe "Find similar" screen.

## Training pipelines

- `ml/` (this dir): trains **FashionMultiTask** — see `README.md`.
- `scripts/build_strong_clothes_coreml.py` (from the segmentation effort): builds
  **ClothesSegFormer** from HF teachers.

Keeping both training entry points documented here avoids duplicated/competing
segmentation work: extend ClothesSegFormer for parsing, extend `ml/` for
classification/attributes/embedding.
