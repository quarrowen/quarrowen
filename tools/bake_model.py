#!/usr/bin/env python3
"""Bakes a glTF binary into a self-contained, block-sized model for a mod.

  python3 tools/bake_model.py <source.glb> <dest.glb> [--fill 0.9]

- Embeds externally referenced images (e.g. Kenney's Textures/colormap.png) into the GLB so a client
  can load the model from downloaded bytes alone.
- Wraps the scene in a root node that scales the model to fit a 1x1x1 block (footprint `fill`),
  keeping its bottom-center at the origin. The engine places that origin at the block's bottom center.
- Switches samplers to nearest filtering to match the voxel art style.
"""

import json
import os
import struct
import sys

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
NEAREST = 9728


def read_glb(path):
    data = open(path, "rb").read()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        sys.exit(f"{path}: not a GLB file")
    offset, doc, binary = 12, None, b""
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + length]
        if kind == CHUNK_JSON:
            doc = json.loads(chunk)
        elif kind == CHUNK_BIN:
            binary = bytes(chunk)
        offset += 8 + length
    return doc, bytearray(binary)


def write_glb(path, doc, binary):
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(js), CHUNK_JSON) + js)
        f.write(struct.pack("<II", len(binary), CHUNK_BIN) + binary)


def model_bounds(doc):
    lo, hi = [float("inf")] * 3, [float("-inf")] * 3
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            acc = doc["accessors"][prim["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, acc["min"])]
            hi = [max(a, b) for a, b in zip(hi, acc["max"])]
    return lo, hi


def main():
    args = sys.argv[1:]
    fill = 0.9
    if "--fill" in args:
        i = args.index("--fill")
        fill = float(args[i + 1])
        del args[i : i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    source, dest = args
    doc, binary = read_glb(source)
    if any("matrix" in n or "rotation" in n or "scale" in n or "translation" in n for n in doc["nodes"]):
        print("warning: source nodes have transforms; bounds assume identity transforms")

    for image in doc.get("images", []):
        uri = image.pop("uri", None)
        if uri is None:
            continue
        png = open(os.path.join(os.path.dirname(source), uri), "rb").read()
        binary += b"\0" * (-len(binary) % 4)
        doc.setdefault("bufferViews", []).append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(png)})
        binary += png
        image["bufferView"] = len(doc["bufferViews"]) - 1
        image["mimeType"] = "image/png"
    doc["buffers"] = [{"byteLength": len(binary)}]
    for sampler in doc.get("samplers", []):
        sampler["minFilter"] = NEAREST
        sampler["magFilter"] = NEAREST

    lo, hi = model_bounds(doc)
    size = [h - l for h, l in zip(hi, lo)]
    scale = min(fill / max(size[0], size[2], 1e-6), 1.0 / max(size[1], 1e-6))
    center = [(hi[0] + lo[0]) / 2, lo[1], (hi[2] + lo[2]) / 2]
    scene = doc["scenes"][doc.get("scene", 0)]
    doc["nodes"].append({
        "name": "block_root",
        "scale": [scale] * 3,
        "translation": [-center[0] * scale, -center[1] * scale, -center[2] * scale],
        "children": scene["nodes"],
    })
    scene["nodes"] = [len(doc["nodes"]) - 1]
    write_glb(dest, doc, binary)
    print(f"{dest}: scale {scale:.3f}, size {[round(s * scale, 2) for s in size]}, {len(binary)} bytes")


if __name__ == "__main__":
    main()
