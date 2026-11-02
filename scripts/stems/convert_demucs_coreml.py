"""Converts the Demucs v4 models (htdemucs, htdemucs_6s) to Core ML for jGlancer's stem splitter on the Mac (D-97).

Developer machine only (needs PyTorch, demucs, coremltools; downloads the weights from Meta once):

    python scripts/stems/convert_demucs_coreml.py <output folder> [fp32|compact|fp16]

The app offers fp32 (Full, `<name>.mlpackage`) and compact (`<name>-compact.mlpackage`: float16 weights computing in
float32, half the size, inaudibly different, like the Windows compact models). fp16 is for measuring only: the Neural
Engine and half precision garble this network (below 0 dB to 63 dB against Demucs).

Like the Windows ONNX models (`convert_demucs.py` in the Windows repository), Core ML gets only the network: the
spectrogram (STFT) before it and the inverse (iSTFT) after it run in the app's own Swift code. The model takes

    mix  float32 [1, 2, L]            the normalized stereo piece (L = 343980 samples, 7.8 s at 44.1 kHz)
    spec float32 [1, 4, 2048, 336]    its spectrogram as (left re, left im, right re, right im)

and returns

    freq float32 [1, S, 4, 2048, 336] each source's spectrogram, same layout (to be inverted and added)
    time float32 [1, S, 2, L]         each source's time-branch waveform

For each compute unit (Neural Engine, GPU, CPU) it prints the time of one piece and the signal-to-difference ratio
of the separated stems against Demucs' own forward, in dB (fp32 on the GPU: 79-122 dB; the Windows models 66-92 dB).
The app then gets each model as `<name>-coreml.zip` (`ditto -c -k --keepParent <name>.mlpackage`).
"""

import hashlib
import math
import sys
import time
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.mil import types
from coremltools.converters.mil.mil.scope import ScopeInfo, ScopeSource
from demucs.pretrained import get_model


class Core(torch.nn.Module):
    """HTDemucs.forward from the magnitude to just before the mask, for a full training-length piece."""

    def __init__(self, model):
        super().__init__()
        self.m = model

    def forward(self, mix, spec):
        m = self.m
        x = spec
        B, C, Fq, T = x.shape
        mean = x.mean(dim=(1, 2, 3), keepdim=True)
        std = x.std(dim=(1, 2, 3), keepdim=True)
        x = (x - mean) / (1e-5 + std)
        xt = mix
        meant = xt.mean(dim=(1, 2), keepdim=True)
        stdt = xt.std(dim=(1, 2), keepdim=True)
        xt = (xt - meant) / (1e-5 + stdt)
        saved, saved_t, lengths, lengths_t = [], [], [], []
        for idx, encode in enumerate(m.encoder):
            lengths.append(x.shape[-1])
            inject = None
            if idx < len(m.tencoder):
                lengths_t.append(xt.shape[-1])
                tenc = m.tencoder[idx]
                xt = tenc(xt)
                if not tenc.empty:
                    saved_t.append(xt)
                else:
                    inject = xt
            x = encode(x, inject)
            if idx == 0 and m.freq_emb is not None:
                frs = torch.arange(x.shape[-2], device=x.device)
                emb = m.freq_emb(frs).t()[None, :, :, None].expand_as(x)
                x = x + m.freq_emb_scale * emb
            saved.append(x)
        if m.crosstransformer:
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = x.reshape(b, c, f * t)
                x = m.channel_upsampler(x)
                x = x.reshape(b, -1, f, t)
                xt = m.channel_upsampler_t(xt)
            x, xt = m.crosstransformer(x, xt)
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = x.reshape(b, c, f * t)
                x = m.channel_downsampler(x)
                x = x.reshape(b, -1, f, t)
                xt = m.channel_downsampler_t(xt)
        for idx, decode in enumerate(m.decoder):
            skip = saved.pop(-1)
            x, pre = decode(x, skip, lengths.pop(-1))
            offset = m.depth - len(m.tdecoder)
            if idx >= offset:
                tdec = m.tdecoder[idx - offset]
                length_t = lengths_t.pop(-1)
                if tdec.empty:
                    pre = pre[:, :, 0]
                    xt, _ = tdec(pre, None, length_t)
                else:
                    skip = saved_t.pop(-1)
                    xt, _ = tdec(xt, skip, length_t)
        S = len(m.sources)
        x = x.view(B, S, -1, Fq, T)
        x = x * std[:, None] + mean[:, None]
        xt = xt.view(B, S, -1, mix.shape[-1])
        xt = xt * stdt[:, None] + meant[:, None]
        return x, xt


def spectrogram(model, mix):
    z = model._spec(mix)
    return model._magnitude(z), z


def separate(model, mix, freq, time_branch):
    _, z = spectrogram(model, mix)
    zout = model._mask(z, torch.from_numpy(freq))
    return model._ispec(zout, mix.shape[-1]) + torch.from_numpy(time_branch)


def snr(expected, got):
    noise = (got - expected).pow(2).mean().sqrt().item()
    signal = expected.pow(2).mean().sqrt().item()
    return 20 * math.log10(signal / max(noise, 1e-12))


def test_signal(model, length):
    """A tone, a beat and noise, so every stem gets something."""
    torch.manual_seed(0)
    t = torch.arange(length) / model.samplerate
    tone = 0.3 * torch.sin(2 * math.pi * 220 * t) + 0.15 * torch.sin(2 * math.pi * 55 * t)
    beat = 0.5 * torch.exp(-((t % 0.5) * 30)) * torch.randn(length)
    left = tone + beat + 0.05 * torch.randn(length)
    right = tone + 0.8 * beat + 0.05 * torch.randn(length)
    return torch.stack([left, right])[None].float()


def compact(traced, mix, spec):
    """Each large weight stored as float16 and cast to float32 before use: the computing stays at full precision."""
    prog = ct.convert(
        traced,
        inputs=[ct.TensorType(name="mix", shape=mix.shape), ct.TensorType(name="spec", shape=spec.shape)],
        outputs=[ct.TensorType(name="freq"), ct.TensorType(name="time")],
        convert_to="milinternal",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
    )
    func = prog.functions["main"]
    with func:
        for op in list(func.operations):
            if op.op_type != "const":
                continue
            var = op.outputs[0]
            if var.dtype != types.fp32 or var.val is None or np.size(var.val) < 2048:
                continue
            with mb.scope(
                ScopeInfo(source=ScopeSource.TORCHSCRIPT_MODULE_TYPE, data=["half"]),
                ScopeInfo(source=ScopeSource.TORCHSCRIPT_MODULE_NAME, data=["half"]),
            ):
                half = mb.const(val=np.asarray(var.val).astype(np.float16), before_op=op)
                back = mb.cast(x=half, dtype="fp32", before_op=op)
            op.enclosing_block.replace_uses_of_var_after_op(anchor_op=op, old_var=var, new_var=back)
            op.enclosing_block.remove_ops([op])
    pipeline = ct.PassPipeline.DEFAULT
    pipeline.remove_passes(["common::const_elimination", "common::cast_optimization"])
    return ct.convert(
        prog, convert_to="mlprogram", compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14, pass_pipeline=pipeline,
    )


def convert(name, folder, precision):
    torch.backends.mha.set_fastpath_enabled(False)
    model = get_model(name).models[0].eval()
    length = int(model.segment * model.samplerate)
    mix = test_signal(model, length)
    spec, _ = spectrogram(model, mix)
    with torch.no_grad():
        expected = model(mix)
        traced = torch.jit.trace(Core(model), (mix, spec))
    if precision == "compact":
        mlmodel = compact(traced, mix, spec)
    else:
        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="mix", shape=mix.shape), ct.TensorType(name="spec", shape=spec.shape)],
            outputs=[ct.TensorType(name="freq"), ct.TensorType(name="time")],
            convert_to="mlprogram",
            compute_precision=ct.precision.FLOAT16 if precision == "fp16" else ct.precision.FLOAT32,
            minimum_deployment_target=ct.target.macOS14,
        )
    suffix = {"fp32": "", "compact": "-compact", "fp16": "-fp16"}[precision]
    out = Path(folder) / f"{name}{suffix}.mlpackage"
    mlmodel.save(str(out))
    size = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
    print(f"{name} {precision}: {size / 1e6:.1f} MB, sources {model.sources}, segment {length}")
    feed = {"mix": mix.numpy(), "spec": spec.numpy()}
    for unit in (ct.ComputeUnit.CPU_AND_GPU,):
        loaded = ct.models.MLModel(str(out), compute_units=unit)
        loaded.predict(feed)
        began = time.time()
        result = loaded.predict(feed)
        seconds = time.time() - began
        got = separate(model, mix, result["freq"], result["time"])
        per_stem = [snr(expected[0, s], got[0, s]) for s in range(len(model.sources))]
        # Against the mix: how loud the error is next to the song (a quiet stem makes the per-stem ratio small).
        to_mix = min(snr(mix[0], got[0, s] - expected[0, s] + mix[0]) for s in range(len(model.sources)))
        print(f"  {unit.name:12} {seconds:.2f} s per piece, SNR {min(per_stem):.1f}-{max(per_stem):.1f} dB, "
              f"error below the mix {to_mix:.1f} dB; " + " ".join(f"{s} {v:.0f}" for s, v in zip(model.sources, per_stem)))


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    precision = sys.argv[2] if len(sys.argv) > 2 else "fp32"
    Path(target).mkdir(parents=True, exist_ok=True)
    for model_name in ("htdemucs", "htdemucs_6s"):
        convert(model_name, target, precision)
