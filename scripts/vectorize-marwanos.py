#!/usr/bin/env python3
"""Rebuild MarwanOS.svg without raster payloads (requires Pillow and NumPy).

The reference contains original outline paths and a raster paint layer. Colour
and alpha become continuous, piecewise bilinear SVG gradient patches, retaining
the original paint instead of quantizing its palette or guessing new details.
"""

import argparse
import base64
import io
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image


NS = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
REPO = Path(__file__).resolve().parents[1]
ET.register_namespace("", NS)


def node(tag, **attrs):
    return ET.Element(f"{{{NS}}}{tag}", {
        key.replace("_", "-"): str(value) for key, value in attrs.items()
    })


def gradient_stops(values, tolerance=0.1):
    """Keep channel interpolation within 0.1 of the source's 8-bit values."""
    keep = {0, len(values) - 1}
    pending = [(0, len(values) - 1)]
    while pending:
        start, end = pending.pop()
        if end - start < 2:
            continue
        t = np.linspace(0, 1, end - start + 1)[:, None]
        expected = values[start] * (1 - t) + values[end] * t
        error = np.max(np.abs(values[start:end + 1] - expected), axis=1)
        index = int(np.argmax(error))
        if error[index] > tolerance:
            middle = start + index
            keep.add(middle)
            pending.extend([(start, middle), (middle, end)])
    return sorted(keep)


def vectorize(source, destination):
    root = ET.parse(source).getroot()
    paint = root.find(f"{{{NS}}}image")
    if paint is None:
        raise ValueError("The reference must contain its original PNG paint layer")
    href = paint.get(f"{{{XLINK}}}href", paint.get("href", ""))
    if not href.startswith("data:image/png;base64,"):
        raise ValueError("Expected a self-contained PNG reference")
    image = np.asarray(Image.open(io.BytesIO(base64.b64decode(
        href.split(",", 1)[1]))).convert("RGBA")).astype(float)
    height, width = image.shape[:2]
    defs = node("defs")
    field = node("g", id="psychedelic-fill", color_interpolation="sRGB",
                 transform=f"translate({paint.get('x')} {paint.get('y')}) "
                 f"scale({float(paint.get('width')) / width:g} "
                 f"{float(paint.get('height')) / height:g})")
    root.remove(paint)
    root.insert(0, defs)
    root.insert(1, field)
    root.insert(0, node("desc"))
    root[0].text = (
        "Original graffiti outlines with colour and transparency reconstructed "
        "as continuous SVG gradients. Contains no bitmap or external assets. "
        "Preserves the soft paint texture of the owner's original raster artwork."
    )
    root.insert(0, node("title"))
    root[0].text = "MarwanOS graffiti"

    # Row centres are half-integer coordinates, matching PNG sampling. The
    # opaque bottom field plus an increasing top field implements interpolation
    # without the dark seams produced by overlapping translucent colour patches.
    # Alpha uses the same construction in a separate luminance mask.
    for kind in ["colour", "alpha"]:
        if kind == "alpha":
            mask = node("mask", id="paint-alpha", maskUnits="userSpaceOnUse",
                        x=0, y=0, width=width, height=height,
                        style="mask-type:luminance")
            defs.append(mask)
            target = mask
            values = np.repeat(image[:, :, 3:4], 3, axis=2)
        else:
            target = field
            values = image[:, :, :3]
        for y in range(height):
            gradient = node("linearGradient", id=f"{kind}-{y}",
                            gradientUnits="userSpaceOnUse", x1=0.5, y1=0,
                            x2=width - 0.5, y2=0, color_interpolation="sRGB")
            for x in gradient_stops(values[y]):
                c = values[y, x].astype(int)
                gradient.append(node("stop", offset=f"{x / (width - 1):.7f}",
                                     stop_color=f"#{c[0]:02x}{c[1]:02x}{c[2]:02x}"))
            defs.append(gradient)
        for y in range(-1, height):
            y0, y1 = max(0, y + 0.5), min(height, y + 1.5)
            d = f"M0 {y0}H{width}V{y1}H0Z"
            band = node("g", shape_rendering="crispEdges")
            bottom, top = max(0, y), min(height - 1, y + 1)
            band.append(node("path", d=d, fill=f"url(#{kind}-{bottom})"))
            if bottom != top:
                if kind == "colour":
                    fade = node("linearGradient", id=f"fade-{y}",
                                gradientUnits="userSpaceOnUse", x1=0, y1=y0,
                                x2=0, y2=y1)
                    fade.append(node("stop", offset=0, stop_color="white", stop_opacity=0))
                    fade.append(node("stop", offset=1, stop_color="white", stop_opacity=1))
                    defs.append(fade)
                    fade_mask = node("mask", id=f"row-{y}",
                                     maskUnits="userSpaceOnUse", x=0, y=y0,
                                     width=width, height=y1 - y0)
                    fade_mask.append(node("path", d=d, fill=f"url(#fade-{y})"))
                    defs.append(fade_mask)
                band.append(node("path", d=d, fill=f"url(#{kind}-{top})",
                                 mask=f"url(#row-{y})"))
            target.append(band)
    field.set("mask", "url(#paint-alpha)")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Preserve readable element boundaries without adding whitespace to paths.
    serialized = ET.tostring(root, encoding="unicode").replace("><", ">\n<")
    destination.write_text(serialized + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {destination} ({destination.stat().st_size:,} bytes; no raster assets)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path,
                        default=REPO / "os/branding/reference/MarwanOS-source.svg")
    parser.add_argument("--output", type=Path, default=REPO / "os/branding/MarwanOS.svg")
    args = parser.parse_args()
    vectorize(args.source, args.output)
