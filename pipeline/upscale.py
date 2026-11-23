#!/usr/bin/env python3
"""Local upscaling CLI — Ilaria engines in-process (no server, no Gradio).

Wraps engines.process() from TheStingerX/Ilaria-Upscaler at the pinned SHA
(see ../pins.txt). The engine code is the runner; the .pth files under
/opt/ilaria/models/ (baked in at build) are the actual upscaler.

Verify the --mode/--model keys against engines.model_catalog() on first run —
they are data-driven in the upstream repo.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, "/opt/ilaria")


def main() -> None:
    p = argparse.ArgumentParser(
        description="Upscale an image using the pinned Ilaria engines (in-process)."
    )
    p.add_argument("input", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument(
        "--mode",
        default="fast",
        help="Engine lane name (see engines.model_catalog()).",
    )
    p.add_argument(
        "--model",
        default="realesrgan-x2",
        help="Model key within the lane (default realesrgan-x2 = RealESRGAN_x2plus, "
        "the model custom.conf uses).",
    )
    p.add_argument(
        "--scale",
        type=float,
        default=4.0,
        help="Upscale factor (custom.conf currently passes 4).",
    )
    p.add_argument("--tile", type=int, default=0, help="Tile size; 0 = engine default.")
    a = p.parse_args()

    import engines  # deferred: pulls in torch

    def progress(i: int, s: str) -> None:
        print(f"[{i:3d}] {s}", file=sys.stderr)

    result = engines.process(a.input, a.output, a.mode, a.model, a.scale, a.tile, progress)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
