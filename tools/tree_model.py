#!/usr/bin/env python3
"""Writes tree models as smooth glTF geometry, for block models that should not look like boxes.

  python3 tools/tree_model.py <dest.glb> <shape> [--height=7] [--radius=2.2] [--trunk=#6d5637] ...

Shapes: cone (a fir), dome (a broadleaf), layered (tiered fir), willow (drooping), palm (a few fronds).

`tools/box_model.py` is the right tool for a machine, a cable or a lamp - things that *are* boxes. It
is the wrong tool for a tree: a canopy built from a ring of boxes is still a ring of boxes when you
look at it, which is what the first round of tree silhouettes proved by looking crude. The difference
here is not more polygons, it is **smooth vertex normals** - a cone whose normals point outward and
are shared between neighbouring faces reads as a curved surface, and the same cone with per-face
normals reads as a fan of flat panels. (2026-09-21)

Model coordinates are block units, origin at the block's bottom centre, so a tree of height 7 spans
y 0..7 and its canopy spreads either side of x = z = 0.
"""

import json
import math
import struct
import sys


def ring(y, radius, sides):
    """One horizontal ring of vertices."""
    return [(math.cos(i / sides * math.tau) * radius, y, math.sin(i / sides * math.tau) * radius)
            for i in range(sides)]


def normalize(v):
    length = math.sqrt(sum(c * c for c in v)) or 1.0
    return [c / length for c in v]


def tube(rings, sides, close_top=False, close_bottom=False):
    """Skins a stack of rings into a surface, with normals pointing away from the axis.

    Smooth because a vertex has one normal shared by every face that meets there. The outward
    direction is taken from the vertex's own position rather than from the faces, which is what
    makes a cone look like a cone and not like a paper fan.
    """
    positions, normals, indices = [], [], []
    for r_index, r in enumerate(rings):
        for (x, y, z) in r:
            positions.append([x, y, z])
            # Slope matters: a steep cone's surface normal tilts upward, not straight out.
            if r_index + 1 < len(rings):
                nxt = rings[r_index + 1][0]
                rise = nxt[1] - r[0][1]
                run = math.hypot(nxt[0], nxt[2]) - math.hypot(x, z)
            else:
                rise, run = 1.0, 0.0
            horiz = math.hypot(x, z) or 1e-6
            normals.append(normalize([x / horiz, -run / (rise or 1e-6), z / horiz]))
    for r_index in range(len(rings) - 1):
        a, b = r_index * sides, (r_index + 1) * sides
        for i in range(sides):
            j = (i + 1) % sides
            indices += [a + i, b + i, b + j, a + i, b + j, a + j]
    if close_top:
        top = rings[-1][0][1]
        apex = len(positions)
        positions.append([0.0, top, 0.0])
        normals.append([0.0, 1.0, 0.0])
        base = (len(rings) - 1) * sides
        for i in range(sides):
            indices += [base + i, apex, base + (i + 1) % sides]
    if close_bottom:
        bottom = rings[0][0][1]
        centre = len(positions)
        positions.append([0.0, bottom, 0.0])
        normals.append([0.0, -1.0, 0.0])
        for i in range(sides):
            indices += [i, (i + 1) % sides, centre]
    return positions, normals, indices


def cone(height, radius, sides, y0=0.0, steps=8):
    """A fir: wide at the bottom, a point at the top, curved slightly inwards on the way up."""
    rings = []
    for s in range(steps):
        t = s / (steps - 1)
        # Slightly concave rather than a straight cone - a real fir's outline curves.
        rings.append(ring(y0 + t * height, radius * (1.0 - t) ** 1.25, sides))
    return tube(rings, sides, close_top=True, close_bottom=True)


def dome(height, radius, sides, y0=0.0, steps=9):
    """A broadleaf: a ball flattened a little, sitting on its trunk."""
    rings = []
    for s in range(steps):
        t = s / (steps - 1)
        angle = t * math.pi * 0.92
        rings.append(ring(y0 + (1.0 - math.cos(angle)) * height * 0.5, math.sin(angle) * radius, sides))
    return tube(rings, sides, close_top=True, close_bottom=True)


def layered(height, radius, sides, y0=0.0, tiers=4):
    """A tiered fir: several cones, each smaller, with gaps between them."""
    out = []
    for i in range(tiers):
        t = i / max(1, tiers - 1)
        out.append(cone(height * (0.42 - t * 0.06), radius * (1.0 - t * 0.72),
                        sides, y0 + t * height * 0.62))
    return out


def trunk(height, bottom, top, sides):
    """A tapered trunk, thicker at the root."""
    rings = [ring(0.0, bottom, sides), ring(height * 0.35, bottom * 0.78, sides),
             ring(height, top, sides)]
    return tube(rings, sides, close_bottom=True)


def build(shape, height, radius, sides, trunk_colour, leaf_colour):
    """Returns [(positions, normals, indices, rgba), ...] - one entry per material."""
    leaf = leaf_colour
    dark = [c * 0.82 for c in leaf[:3]] + [1.0]
    parts = []
    if shape == "cone":
        parts.append(trunk(height * 0.34, 0.20, 0.13, sides) + (trunk_colour,))
        parts.append(cone(height * 0.78, radius, sides, height * 0.22) + (leaf,))
    elif shape == "dome":
        parts.append(trunk(height * 0.55, 0.22, 0.15, sides) + (trunk_colour,))
        parts.append(dome(height * 0.62, radius, sides, height * 0.45) + (leaf,))
    elif shape == "layered":
        parts.append(trunk(height * 0.30, 0.19, 0.12, sides) + (trunk_colour,))
        for i, piece in enumerate(layered(height * 0.85, radius, sides, height * 0.18)):
            parts.append(piece + (leaf if i % 2 == 0 else dark,))
    elif shape == "willow":
        # A dome with a second, wider and lower skirt: the drooping outline.
        parts.append(trunk(height * 0.5, 0.21, 0.14, sides) + (trunk_colour,))
        parts.append(dome(height * 0.5, radius * 0.85, sides, height * 0.48) + (leaf,))
        parts.append(dome(height * 0.34, radius * 1.12, sides, height * 0.34) + (dark,))
    elif shape == "palm":
        parts.append(trunk(height * 0.82, 0.17, 0.12, sides) + (trunk_colour,))
        parts.append(dome(height * 0.22, radius * 0.9, sides, height * 0.78) + (leaf,))
    else:
        sys.exit("unknown shape '%s'" % shape)
    return parts


def write(dest, parts):
    binary = bytearray()
    doc = {"asset": {"version": "2.0", "generator": "quarrowen tree_model.py"}, "scene": 0,
           "scenes": [{"nodes": [0]}], "nodes": [{"name": "tree", "mesh": 0}],
           "meshes": [{"name": "tree", "primitives": []}], "materials": [], "accessors": [],
           "bufferViews": [], "buffers": []}

    def add_view(data, target):
        binary.extend(b"\0" * (-len(binary) % 4))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data), "target": target})
        binary.extend(data)
        return len(doc["bufferViews"]) - 1

    for positions, normals, indices, rgba in parts:
        lo = [min(p[a] for p in positions) for a in range(3)]
        hi = [max(p[a] for p in positions) for a in range(3)]
        pos_view = add_view(b"".join(struct.pack("<3f", *p) for p in positions), 34962)
        nrm_view = add_view(b"".join(struct.pack("<3f", *n) for n in normals), 34962)
        idx_view = add_view(b"".join(struct.pack("<H", i) for i in indices), 34963)
        acc = len(doc["accessors"])
        doc["accessors"] += [
            {"bufferView": pos_view, "componentType": 5126, "count": len(positions), "type": "VEC3", "min": lo, "max": hi},
            {"bufferView": nrm_view, "componentType": 5126, "count": len(normals), "type": "VEC3"},
            {"bufferView": idx_view, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        ]
        material = len(doc["materials"])
        doc["materials"].append({"pbrMetallicRoughness": {"baseColorFactor": rgba, "metallicFactor": 0.0, "roughnessFactor": 0.9}})
        doc["meshes"][0]["primitives"].append({"attributes": {"POSITION": acc, "NORMAL": acc + 1}, "indices": acc + 2, "material": material})

    binary.extend(b"\0" * (-len(binary) % 4))
    doc["buffers"] = [{"byteLength": len(binary)}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(dest, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)
    print("%s: %d parts, %d bytes" % (dest, len(parts), len(binary)))


def rgb(text):
    text = text.lstrip("#")
    return [int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    dest, shape = sys.argv[1], sys.argv[2]
    options = {"height": 7.0, "radius": 2.2, "sides": 14, "trunk": "#6d5637", "leaf": "#4f8f3a"}
    for arg in sys.argv[3:]:
        key, _, value = arg.lstrip("-").partition("=")
        if key in options:
            options[key] = value
    write(dest, build(shape, float(options["height"]), float(options["radius"]), int(options["sides"]),
                      rgb(str(options["trunk"])), rgb(str(options["leaf"]))))


if __name__ == "__main__":
    main()
