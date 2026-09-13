#!/usr/bin/env python3
"""Writes a simple glTF binary built from colored boxes, for block models that don't need artwork
(cable cores and arms, pylons, ...).

  python3 tools/box_model.py <dest.glb> <box> [<box> ...]

Each box is "x0,y0,z0,x1,y1,z1,#rrggbb" in block units. The engine places a model's origin at the
block's bottom center (or its center for blocks with a connect_group), so model coordinates usually
span -0.5..0.5 horizontally.
"""

import json
import struct
import sys

# Face order with outward normals; corners counter-clockwise when viewed from outside (glTF front).
FACES = [
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 1), (0, 1, 1), (0, 1, 0), (0, 0, 0)]),
    ((0, 1, 0), [(0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(1, 0, 1), (1, 1, 1), (0, 1, 1), (0, 0, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


def parse_box(spec):
    parts = spec.split(",")
    lo = [float(v) for v in parts[0:3]]
    hi = [float(v) for v in parts[3:6]]
    color = parts[6].lstrip("#")
    rgb = [int(color[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return lo, hi, rgb


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    dest, boxes = sys.argv[1], [parse_box(b) for b in sys.argv[2:]]
    binary = bytearray()
    doc = {
        "asset": {"version": "2.0", "generator": "voxelcraft box_model.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": []}],
        "materials": [],
        "accessors": [],
        "bufferViews": [],
        "buffers": [],
    }

    def add_view(data, target):
        binary.extend(b"\0" * (-len(binary) % 4))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data), "target": target})
        binary.extend(data)
        return len(doc["bufferViews"]) - 1

    for index, (lo, hi, rgb) in enumerate(boxes):
        positions, normals, indices = [], [], []
        for normal, corners in FACES:
            base = len(positions)
            for c in corners:
                positions.append([lo[a] if c[a] == 0 else hi[a] for a in range(3)])
                normals.append(list(normal))
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        pos_view = add_view(b"".join(struct.pack("<3f", *p) for p in positions), 34962)
        nrm_view = add_view(b"".join(struct.pack("<3f", *n) for n in normals), 34962)
        idx_view = add_view(b"".join(struct.pack("<H", i) for i in indices), 34963)
        acc = len(doc["accessors"])
        doc["accessors"] += [
            {"bufferView": pos_view, "componentType": 5126, "count": len(positions), "type": "VEC3", "min": lo, "max": hi},
            {"bufferView": nrm_view, "componentType": 5126, "count": len(normals), "type": "VEC3"},
            {"bufferView": idx_view, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        ]
        doc["materials"].append({"pbrMetallicRoughness": {"baseColorFactor": rgb + [1.0], "metallicFactor": 0.1, "roughnessFactor": 0.8}})
        doc["meshes"][0]["primitives"].append({"attributes": {"POSITION": acc, "NORMAL": acc + 1}, "indices": acc + 2, "material": index})

    binary.extend(b"\0" * (-len(binary) % 4))
    doc["buffers"] = [{"byteLength": len(binary)}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(dest, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)
    print(f"{dest}: {len(boxes)} boxes, {len(binary)} bytes")


if __name__ == "__main__":
    main()
