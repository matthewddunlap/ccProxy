#!/usr/bin/env python3
"""Pixel digest of PNG file(s): sha256 of the decoded RGBA pixel bytes.

The card PNGs are encoded by the browser's canvas PNG encoder
(`cardCanvas.toDataURL('image/png')`, see ccAutomator's _capture_via_card_canvas);
the deflate stream of IDENTICAL pixels can differ from run to run (threaded
compression), so raw sha256 is NOT a stable identity for the image. The decoded
pixel bytes are. Usage: pngphash.py PNG...  ->  '<hex> <nbytes> <path>' per file.
"""
import sys
import hashlib
from PIL import Image

for p in sys.argv[1:]:
    px = Image.open(p).convert("RGBA").tobytes()
    print(hashlib.sha256(px).hexdigest(), len(px), p)
