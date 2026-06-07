#!/usr/bin/env python3
"""Convert the official SwinIR JPEG artifact reduction model to Core ML.

Expected source checkout:
  git clone --depth 1 https://github.com/JingyunLiang/SwinIR.git /tmp/SwinIR

Expected weights:
  https://github.com/JingyunLiang/SwinIR/releases/download/v0.0/006_CAR_DFWB_s126w7_SwinIR-M_jpeg30.pth

The 006_CAR grayscale JPEG model is scale=1. JamReader applies it to luma only
and keeps chroma from the source image, so the Core ML contract is:
  input  1x1xINPUTxINPUT float grayscale, values 0...1
  output 1x1xINPUTxINPUT float grayscale, values 0...1
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from torch import nn


MODEL_INPUT_SIZE = 126
WINDOW_SIZE = 7
TOKENS_PER_WINDOW = WINDOW_SIZE * WINDOW_SIZE
WINDOWS_PER_IMAGE = (MODEL_INPUT_SIZE // WINDOW_SIZE) * (MODEL_INPUT_SIZE // WINDOW_SIZE)


def configure_fixed_shape(input_size: int) -> None:
    global MODEL_INPUT_SIZE, WINDOWS_PER_IMAGE
    if input_size <= 0 or input_size % WINDOW_SIZE != 0:
        raise ValueError(f"input-size must be a positive multiple of {WINDOW_SIZE}.")
    MODEL_INPUT_SIZE = input_size
    WINDOWS_PER_IMAGE = (MODEL_INPUT_SIZE // WINDOW_SIZE) * (MODEL_INPUT_SIZE // WINDOW_SIZE)


def coreml_window_partition(x: torch.Tensor, window_size: int, channels: int) -> torch.Tensor:
    windows_per_axis = MODEL_INPUT_SIZE // window_size
    x = x.view(1, windows_per_axis, window_size, windows_per_axis, window_size, channels)
    return x.permute(0, 1, 3, 2, 4, 5).contiguous().view(-1, window_size, window_size, channels)


def coreml_window_reverse(windows: torch.Tensor, window_size: int, height: int, width: int) -> torch.Tensor:
    # The converted model has a fixed 1x126x126 tensor contract, so avoid the
    # dynamic int(shape) path from the official helper that Core ML cannot lower.
    del height, width
    windows_per_axis = MODEL_INPUT_SIZE // window_size
    x = windows.view(1, windows_per_axis, windows_per_axis, window_size, window_size, -1)
    return x.permute(0, 1, 3, 2, 4, 5).contiguous().view(1, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE, -1)


def coreml_patch_unembed_forward(self: nn.Module, x: torch.Tensor, x_size) -> torch.Tensor:
    del x_size
    return x.transpose(1, 2).view(1, self.embed_dim, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE)


def coreml_swin_transformer_block_forward(self: nn.Module, x: torch.Tensor, x_size) -> torch.Tensor:
    del x_size
    shortcut = x
    x = self.norm1(x)
    x = x.view(1, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE, self.dim)

    if self.shift_size > 0:
        shifted_x = torch.roll(x, shifts=(-self.shift_size, -self.shift_size), dims=(1, 2))
    else:
        shifted_x = x

    x_windows = coreml_window_partition(shifted_x, self.window_size, self.dim)
    x_windows = x_windows.view(-1, self.window_size * self.window_size, self.dim)
    attn_windows = self.attn(x_windows, mask=self.attn_mask)
    attn_windows = attn_windows.view(-1, self.window_size, self.window_size, self.dim)
    shifted_x = coreml_window_reverse(attn_windows, self.window_size, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE)

    if self.shift_size > 0:
        x = torch.roll(shifted_x, shifts=(self.shift_size, self.shift_size), dims=(1, 2))
    else:
        x = shifted_x

    x = x.view(1, MODEL_INPUT_SIZE * MODEL_INPUT_SIZE, self.dim)
    x = shortcut + self.drop_path(x)
    return x + self.drop_path(self.mlp(self.norm2(x)))


def coreml_window_attention_forward(self: nn.Module, x: torch.Tensor, mask=None) -> torch.Tensor:
    channels = self.dim
    head_dim = channels // self.num_heads
    qkv = self.qkv(x).reshape(
        WINDOWS_PER_IMAGE,
        TOKENS_PER_WINDOW,
        3,
        self.num_heads,
        head_dim,
    ).permute(2, 0, 3, 1, 4)
    q, k, v = qkv[0], qkv[1], qkv[2]

    q = q * self.scale
    attn = q @ k.transpose(-2, -1)

    relative_position_bias = self.relative_position_bias_table[self.relative_position_index.view(-1)].view(
        TOKENS_PER_WINDOW,
        TOKENS_PER_WINDOW,
        -1,
    )
    relative_position_bias = relative_position_bias.permute(2, 0, 1).contiguous()
    attn = attn + relative_position_bias.unsqueeze(0)

    if mask is not None:
        attn = attn.view(1, WINDOWS_PER_IMAGE, self.num_heads, TOKENS_PER_WINDOW, TOKENS_PER_WINDOW)
        attn = attn + mask.unsqueeze(1).unsqueeze(0)
        attn = attn.view(-1, self.num_heads, TOKENS_PER_WINDOW, TOKENS_PER_WINDOW)

    attn = self.softmax(attn)
    attn = self.attn_drop(attn)
    x = (attn @ v).transpose(1, 2).reshape(WINDOWS_PER_IMAGE, TOKENS_PER_WINDOW, channels)
    x = self.proj(x)
    return self.proj_drop(x)


def load_state_dict(weights_path: Path):
    try:
        return torch.load(weights_path, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(weights_path, map_location="cpu")


class SwinIRJPEGArtifactWrapper(nn.Module):
    def __init__(self, swinir_root: Path, weights_path: Path) -> None:
        super().__init__()
        sys.path.insert(0, str(swinir_root))
        import models.network_swinir as swinir_network  # pylint: disable=import-outside-toplevel
        from models.network_swinir import SwinIR  # pylint: disable=import-outside-toplevel

        swinir_network.window_reverse = coreml_window_reverse
        swinir_network.WindowAttention.forward = coreml_window_attention_forward
        swinir_network.PatchUnEmbed.forward = coreml_patch_unembed_forward
        swinir_network.SwinTransformerBlock.forward = coreml_swin_transformer_block_forward

        self.base = SwinIR(
            upscale=1,
            in_chans=1,
            img_size=MODEL_INPUT_SIZE,
            window_size=7,
            img_range=255.0,
            depths=[6, 6, 6, 6, 6, 6],
            embed_dim=180,
            num_heads=[6, 6, 6, 6, 6, 6],
            mlp_ratio=2,
            upsampler="",
            resi_connection="1conv",
        ).eval()

        state = load_state_dict(weights_path)
        params = state["params"] if "params" in state else state
        params = {key: value for key, value in params.items() if not key.endswith("attn_mask")}
        load_result = self.base.load_state_dict(params, strict=False)
        missing_keys = [key for key in load_result.missing_keys if not key.endswith("attn_mask")]
        unexpected_keys = list(load_result.unexpected_keys)
        if missing_keys or unexpected_keys:
            raise RuntimeError(
                "Unexpected SwinIR checkpoint structure. "
                f"missing_keys={missing_keys} unexpected_keys={unexpected_keys}"
            )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        mean = self.base.mean.type_as(x)
        x = (x - mean) * self.base.img_range
        first = self.base.conv_first(x)
        residual = self.base.conv_after_body(self.forward_features_fixed(first)) + first
        y = x + self.base.conv_last(residual)
        y = y / self.base.img_range + mean
        return torch.clamp(y, 0.0, 1.0)

    def forward_features_fixed(self, x: torch.Tensor) -> torch.Tensor:
        x_size = (MODEL_INPUT_SIZE, MODEL_INPUT_SIZE)
        x = self.base.patch_embed(x)
        x = self.base.pos_drop(x)

        for layer in self.base.layers:
            x = layer(x, x_size)

        x = self.base.norm(x)
        return self.base.patch_unembed(x, x_size)


def convert(args: argparse.Namespace) -> None:
    configure_fixed_shape(args.input_size)
    swinir_root = args.swinir_root.resolve()
    weights_path = args.weights.resolve()
    output_path = args.output.resolve()

    if output_path.exists():
        if output_path.is_dir():
            shutil.rmtree(output_path)
        else:
            output_path.unlink()

    model = SwinIRJPEGArtifactWrapper(swinir_root, weights_path).eval()
    example = torch.rand(1, 1, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE)

    with torch.no_grad():
        torch_output = model(example).detach().numpy()

    expected_shape = [1, 1, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE]
    if list(torch_output.shape) != expected_shape:
        raise ValueError(f"Unexpected PyTorch output shape {torch_output.shape}; expected {expected_shape}.")

    traced = torch.jit.trace(model, example)
    precision = ct.precision.FLOAT32 if args.float32 else ct.precision.FLOAT16

    started = time.time()
    if args.convert_to == "neuralnetwork":
        minimum_deployment_target = ct.target.iOS14
    else:
        minimum_deployment_target = ct.target.iOS17

    conversion_kwargs = {
        "convert_to": args.convert_to,
        "minimum_deployment_target": minimum_deployment_target,
        "inputs": [ct.TensorType(name="input", shape=example.shape, dtype=float)],
        "outputs": [ct.TensorType(name="output", dtype=float)],
    }
    if args.convert_to == "mlprogram":
        conversion_kwargs["compute_precision"] = precision

    mlmodel = ct.convert(
        traced,
        **conversion_kwargs,
    )

    mlmodel.author = "SwinIR by Jingyun Liang et al.; converted for JamReader testing"
    mlmodel.short_description = (
        "SwinIR-M grayscale JPEG artifact reduction, jpeg30. Input/output are "
        "luma float tensors in NCHW with values 0...1 and no spatial scaling."
    )
    mlmodel.input_description["input"] = (
        f"Grayscale/luma float tensor, shape 1x1x{MODEL_INPUT_SIZE}x{MODEL_INPUT_SIZE}, values 0...1."
    )
    mlmodel.output_description["output"] = (
        f"Enhanced luma float tensor, shape 1x1x{MODEL_INPUT_SIZE}x{MODEL_INPUT_SIZE}, values 0...1."
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
    parser.add_argument("--swinir-root", required=True, type=Path)
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--input-size", default=MODEL_INPUT_SIZE, type=int)
    parser.add_argument("--convert-to", choices=("mlprogram", "neuralnetwork"), default="mlprogram")
    parser.add_argument("--float32", action="store_true")
    parser.add_argument("--validate", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    convert(parse_args())
