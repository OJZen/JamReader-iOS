#!/usr/bin/env python3
"""Convert the official Real-CUGAN 2x PyTorch weights to Core ML.

Expected source checkout:
  git clone --depth 1 --filter=blob:none --sparse https://github.com/bilibili/ailab.git /tmp/ailab
  git -C /tmp/ailab sparse-checkout set Real-CUGAN

Expected weights:
  https://github.com/bilibili/ailab/releases/download/Real-CUGAN/updated_weights.zip
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
import types
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

DEFAULT_TILE_CONTEXT = 24


def load_state_dict(weights_path: Path):
    try:
        return torch.load(weights_path, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(weights_path, map_location="cpu")


def crop(x: torch.Tensor, amount: int) -> torch.Tensor:
    return x[:, :, amount:-amount, amount:-amount]


def unet1_forward_coreml(self: nn.Module, x: torch.Tensor) -> torch.Tensor:
    x1 = self.conv1(x)
    x2 = self.conv1_down(x1)
    x1 = crop(x1, 4)
    x2 = F.leaky_relu(x2, 0.1, inplace=False)
    x2 = self.conv2(x2)
    x2 = self.conv2_up(x2)
    x2 = F.leaky_relu(x2, 0.1, inplace=False)
    x3 = self.conv3(x1 + x2)
    x3 = F.leaky_relu(x3, 0.1, inplace=False)
    return self.conv_bottom(x3)


def unet2_forward_coreml(self: nn.Module, x: torch.Tensor, alpha: float = 1.0) -> torch.Tensor:
    x1 = self.conv1(x)
    x2 = self.conv1_down(x1)
    x1 = crop(x1, 16)
    x2 = F.leaky_relu(x2, 0.1, inplace=False)
    x2 = self.conv2(x2)
    x3 = self.conv2_down(x2)
    x2 = crop(x2, 4)
    x3 = F.leaky_relu(x3, 0.1, inplace=False)
    x3 = self.conv3(x3)
    x3 = self.conv3_up(x3)
    x3 = F.leaky_relu(x3, 0.1, inplace=False)
    x4 = self.conv4(x2 + x3)
    x4 = x4 * alpha
    x4 = self.conv4_up(x4)
    x4 = F.leaky_relu(x4, 0.1, inplace=False)
    x5 = self.conv5(x1 + x4)
    x5 = F.leaky_relu(x5, 0.1, inplace=False)
    return self.conv_bottom(x5)


class RealCUGAN2xTileWrapper(nn.Module):
    """Traceable 2x Real-CUGAN tile wrapper.

    The official forward path accepts runtime tile/cache parameters and returns
    uint8. JamReader feeds a fixed tile plus 18px edge context, so this wrapper
    converts the network to a stable float tensor contract:
    input 1x3xINPUTxINPUT RGB 0...1 -> output 1x3xOUTPUTxOUTPUT RGB 0...1.
    """

    def __init__(self, realcugan_root: Path, weights_path: Path, output_crop: int) -> None:
        super().__init__()
        self.output_crop = output_crop
        sys.path.insert(0, str(realcugan_root))
        from upcunet_v3 import UpCunet2x  # pylint: disable=import-outside-toplevel

        state = load_state_dict(weights_path)
        if "pro" in state:
            del state["pro"]

        self.base = UpCunet2x().eval()
        self.base.load_state_dict(state, strict=True)
        self.base.unet1.forward = types.MethodType(unet1_forward_coreml, self.base.unet1)
        self.base.unet2.forward = types.MethodType(unet2_forward_coreml, self.base.unet2)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.base.unet1.forward(x)
        residual = self.base.unet2.forward(y, 1.0)
        y = crop(y, 20)
        y = torch.clamp(torch.add(residual, y), 0.0, 1.0)
        if self.output_crop > 0:
            y = crop(y, self.output_crop)
        return y


def convert(args: argparse.Namespace) -> None:
    realcugan_root = args.realcugan_root.resolve()
    weights_path = args.weights.resolve()
    output_path = args.output.resolve()
    valid_tile_size = args.input_size - args.tile_context * 2
    output_size = valid_tile_size * 2
    if args.input_size <= args.tile_context * 2:
        raise ValueError("input-size must be larger than the tile context.")
    if args.input_size % 2 != 0 or valid_tile_size % 2 != 0:
        raise ValueError("input-size and valid tile size must be even for the 2x network.")

    if output_path.exists():
        if output_path.is_dir():
            shutil.rmtree(output_path)
        else:
            output_path.unlink()

    raw_output_size = (args.input_size - 36) * 2
    output_crop = (raw_output_size - output_size) // 2
    if output_crop < 0 or raw_output_size - output_crop * 2 != output_size:
        raise ValueError(
            f"Cannot crop raw output size {raw_output_size} to requested output size {output_size}."
        )

    model = RealCUGAN2xTileWrapper(realcugan_root, weights_path, output_crop).eval()
    example = torch.rand(1, 3, args.input_size, args.input_size)

    with torch.no_grad():
        torch_output = model(example).detach().numpy()
    if list(torch_output.shape) != [1, 3, output_size, output_size]:
        raise ValueError(
            f"Unexpected PyTorch output shape {torch_output.shape}; expected "
            f"(1, 3, {output_size}, {output_size})."
        )

    traced = torch.jit.trace(model, example)
    precision = ct.precision.FLOAT32 if args.float32 else ct.precision.FLOAT16
    io_dtype = np.float16 if args.io_float16 else float

    started = time.time()
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=precision,
        inputs=[ct.TensorType(name="input", shape=example.shape, dtype=io_dtype)],
        outputs=[ct.TensorType(name="output", dtype=io_dtype)],
    )

    mlmodel.author = "Real-CUGAN by bilibili/ailab; converted for JamReader testing"
    mlmodel.short_description = (
        "Real-CUGAN 2x conservative tile model. Input/output are RGB float tensors "
        "in NCHW with values 0...1."
    )
    mlmodel.input_description["input"] = (
        f"RGB float tensor, shape 1x3x{args.input_size}x{args.input_size}, values 0...1. "
        f"Includes {args.tile_context}px edge context around a {valid_tile_size}x{valid_tile_size} tile."
    )
    mlmodel.output_description["output"] = (
        f"RGB float tensor, shape 1x3x{output_size}x{output_size}, values 0...1."
    )
    mlmodel.save(str(output_path))

    if args.validate:
        loaded = ct.models.MLModel(str(output_path))
        coreml_output = loaded.predict({"input": example.numpy()})["output"]
        print(f"validation diff max={np.max(np.abs(torch_output - coreml_output)):.6f}")
        print(f"validation diff mean={np.mean(np.abs(torch_output - coreml_output)):.6f}")

    size_mb = sum(p.stat().st_size for p in output_path.rglob("*") if p.is_file()) / 1024 / 1024
    print(f"saved {output_path}")
    print(f"size_mb={size_mb:.2f} elapsed_seconds={time.time() - started:.2f}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--realcugan-root", required=True, type=Path)
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--input-size", default=432, type=int)
    parser.add_argument("--tile-context", default=DEFAULT_TILE_CONTEXT, type=int)
    parser.add_argument("--float32", action="store_true")
    parser.add_argument("--io-float16", action="store_true")
    parser.add_argument("--validate", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    convert(parse_args())
