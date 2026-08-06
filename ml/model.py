"""Multi-task fashion network: one MobileNetV3 backbone, several heads.

  image -> backbone -> 576-d feature -> trunk(256) --> category head
                                                    |-> gender  head
                                                    |-> season  head
                                                    |-> usage   head
                                                    |-> color   head
                                                    `-> L2-normalized embedding (similarity)
"""
from __future__ import annotations

import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision.models import mobilenet_v3_small, MobileNet_V3_Small_Weights

BACKBONE_DIM = 576
TRUNK_DIM = 256


class Backbone(nn.Module):
    """Frozen ImageNet MobileNetV3-Small feature extractor -> 576-d vector."""

    def __init__(self, pretrained=True):
        super().__init__()
        weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1 if pretrained else None
        net = mobilenet_v3_small(weights=weights)
        self.features = net.features
        self.pool = nn.AdaptiveAvgPool2d(1)

    def forward(self, x):
        x = self.features(x)
        x = self.pool(x)
        return torch.flatten(x, 1)


class Heads(nn.Module):
    """Shared trunk + per-task linear heads. Operates on 576-d features."""

    def __init__(self, head_dims: dict[str, int]):
        super().__init__()
        self.trunk = nn.Sequential(
            nn.Linear(BACKBONE_DIM, TRUNK_DIM),
            nn.Hardswish(),
            nn.Dropout(0.2),
        )
        self.heads = nn.ModuleDict(
            {name: nn.Linear(TRUNK_DIM, n) for name, n in head_dims.items()}
        )

    def forward(self, feats):
        z = self.trunk(feats)
        out = {name: head(z) for name, head in self.heads.items()}
        out["embedding"] = F.normalize(z, dim=1)
        return out


class MultiTaskFashionNet(nn.Module):
    """Full image -> {logits per task, embedding} model (for CoreML export)."""

    def __init__(self, head_dims: dict[str, int], pretrained=True):
        super().__init__()
        self.backbone = Backbone(pretrained=pretrained)
        self.heads = Heads(head_dims)

    def forward(self, x):
        return self.heads(self.backbone(x))

    def load_head_state(self, state: dict):
        self.heads.load_state_dict(state)
