"""Shared U2NETP loading + preprocessing for validation and CoreML export."""
from __future__ import annotations

import os

import torch
import torch.nn as nn
import torch.nn.functional as F
from huggingface_hub import hf_hub_download

from u2net_arch import U2NETP

SIZE = 320
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


def load_u2netp() -> U2NETP:
    path = hf_hub_download("netradrishti/u2net-saliency", "models/u2netp.pth")
    net = U2NETP(3, 1)
    state = torch.load(path, map_location="cpu", weights_only=True)
    net.load_state_dict(state)
    net.eval()
    return net


class SegExport(nn.Module):
    """0-1 image in -> single foreground mask out (normalization baked in)."""

    def __init__(self, net: U2NETP):
        super().__init__()
        self.net = net
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))

    def forward(self, x):
        x = (x - self.mean) / self.std
        d0 = self.net(x)[0]  # forward returns 7 sigmoid outputs; d0 is primary
        return d0
