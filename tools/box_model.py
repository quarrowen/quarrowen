#!/usr/bin/env python3
"""Writes a simple glTF binary built from colored boxes, for block models that don't need artwork
(cable cores and arms, pylons, ...).

  python3 tools/box_model.py <dest.glb> <box> [<box> ...]

Each box is "x0,y0,z0,x1,y1,z1,#rrggbb" in block units. The engine places a model's origin at the
block's bottom center (or its center for blocks with a connect_group), so model coordinates usually
span -0.5..0.5 horizontally.

Animated entity models are split into parts: "@name:px,py,pz" starts a part pivoting around that point
(boxes that follow still use model coordinates). Entities swing parts whose names start with leg_a,
leg_b, arm_a and arm_b while walking; the model faces -Z.
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
    srgb = [int(color[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # glTF color factors are linear; hex colors are sRGB.
    rgb = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return lo, hi, rgb


def parse_parts(args):
    parts = []  # [name, pivot, boxes]
    for arg in args:
        if arg.startswith("@"):
            name, pivot = arg[1:].split(":")
            parts.append([name, [float(v) for v in pivot.split(",")], []])
        else:
            if not parts:
                parts.append(["body", [0.0, 0.0, 0.0], []])
            parts[-1][2].append(parse_box(arg))
    return [p for p in parts if p[2]]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    dest, parts = sys.argv[1], parse_parts(sys.argv[2:])
    binary = bytearray()
    doc = {
        "asset": {"version": "2.0", "generator": "quarrowen box_model.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(parts)))}],
        "nodes": [],
        "meshes": [],
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

    boxes = 0
    for part_index, (part_name, pivot, part_boxes) in enumerate(parts):
      doc["nodes"].append({"name": part_name, "mesh": part_index, "translation": pivot})
      doc["meshes"].append({"name": part_name, "primitives": []})
      for lo, hi, rgb in part_boxes:
        index = len(doc["materials"])
        boxes += 1
        lo = [lo[a] - pivot[a] for a in range(3)]
        hi = [hi[a] - pivot[a] for a in range(3)]
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
        doc["meshes"][part_index]["primitives"].append({"attributes": {"POSITION": acc, "NORMAL": acc + 1}, "indices": acc + 2, "material": index})

    binary.extend(b"\0" * (-len(binary) % 4))
    doc["buffers"] = [{"byteLength": len(binary)}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(dest, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)
    print(f"{dest}: {len(parts)} parts, {boxes} boxes, {len(binary)} bytes")


if __name__ == "__main__":
    main()
