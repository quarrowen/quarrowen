#!/usr/bin/env python3
"""Writes vanilla's structure templates (the same JSON format `/struct save` produces):

  python3 tools/generate_structures.py

Each template lists blocks by palette index; "engine:air" cells clear terrain, unlisted cells keep it.
Block data marks loot chests ({"loot": table}) and spawners ({"spawner": {...}}).
"""

import json
import math
import random

OUT = "mods/vanilla/structures/"


class Template:
    def __init__(self, sx, sy, sz):
        self.size = [sx, sy, sz]
        self.cells = {}
        self.data = {}

    def set(self, x, y, z, block):
        if 0 <= x < self.size[0] and 0 <= y < self.size[1] and 0 <= z < self.size[2]:
            self.cells[(x, y, z)] = block

    def box(self, x0, y0, z0, x1, y1, z1, block):
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                for x in range(x0, x1 + 1):
                    self.set(x, y, z, block)

    def mark(self, x, y, z, block, data):
        self.set(x, y, z, block)
        self.data["%d,%d,%d" % (x, y, z)] = data

    def save(self, name):
        palette, index, blocks = [], {}, []
        for (x, y, z), block in sorted(self.cells.items(), key=lambda c: (c[0][1], c[0][2], c[0][0])):
            if block not in index:
                index[block] = len(palette)
                palette.append(block)
            blocks.append([x, y, z, index[block]])
        with open(OUT + name + ".json", "w") as f:
            json.dump({"size": self.size, "palette": palette, "blocks": blocks, "data": self.data}, f, separators=(",", ":"))
        print("%s: %s, %d blocks" % (name, self.size, len(blocks)))


AIR, COBBLE, STONE, PLANKS, LOG, GRAVEL = "engine:air", "base:cobblestone", "base:stone", "base:planks", "base:log", "base:gravel"
CHEST, SPAWNER, TORCH, WEB = "base:chest", "base:spawner", "base:torch", "vanilla:cobweb"


def dungeon():
    rng = random.Random(1)
    t = Template(9, 6, 9)
    t.box(0, 0, 0, 8, 5, 8, COBBLE)
    t.box(1, 1, 1, 7, 4, 7, AIR)
    for x in range(1, 8):
        for z in range(1, 8):
            t.set(x, 0, z, GRAVEL if rng.random() < 0.35 else COBBLE)
    t.mark(4, 1, 4, SPAWNER, {"spawner": {"entity": ["vanilla:zombie", "vanilla:skeleton", "vanilla:spider"], "count": [1, 3], "range": 3}})
    t.mark(1, 1, 4, CHEST, {"loot": "vanilla:dungeon"})
    t.mark(7, 1, 4, CHEST, {"loot": "vanilla:dungeon"})
    t.set(1, 4, 1, WEB)
    t.set(7, 4, 7, WEB)
    t.save("dungeon")


def ruin(name, seed, sx, sz, height):
    rng = random.Random(seed)
    t = Template(sx, height, sz)
    for x in range(sx):
        for z in range(sz):
            edge = x in (0, sx - 1) or z in (0, sz - 1)
            if rng.random() < 0.8:
                t.set(x, 0, z, COBBLE if edge or rng.random() < 0.5 else PLANKS)
            if edge:
                top = rng.randint(0, height - 1)
                for y in range(1, top + 1):
                    if not (y == 1 and x == sx // 2):  # a gap for a doorway
                        t.set(x, y, z, LOG if (x in (0, sx - 1) and z in (0, sz - 1)) else COBBLE)
    t.mark(1, 1, 1, CHEST, {"loot": "vanilla:ruins"})
    t.save(name)


def watchtower():
    t = Template(5, 14, 5)
    t.box(0, 0, 0, 4, 0, 4, COBBLE)
    for (x, z) in ((0, 0), (4, 0), (0, 4), (4, 4)):
        t.box(x, 1, z, x, 12, z, LOG)
    for y in range(1, 10):
        for x in range(1, 4):
            for z in (0, 4):
                t.set(x, y, z, PLANKS if y % 3 != 2 else AIR)  # windows every third row
        for z in range(1, 4):
            for x in (0, 4):
                t.set(x, y, z, PLANKS if y % 3 != 2 else AIR)
    t.set(2, 1, 0, AIR)
    t.set(2, 2, 0, AIR)  # door
    t.box(1, 1, 1, 3, 9, 3, AIR)
    steps = [(1, 1), (1, 2), (1, 3), (2, 3), (3, 3), (3, 2), (3, 1), (2, 1)]
    for i in range(9):
        x, z = steps[i % len(steps)]
        t.set(x, i + 1, z, PLANKS)  # a spiral of steps up the inside
    t.box(0, 10, 0, 4, 10, 4, PLANKS)
    t.set(2, 10, 1, AIR)
    for i in range(5):
        for (x, z) in ((i, 0), (i, 4), (0, i), (4, i)):
            t.set(x, 11, z, COBBLE)
    t.box(1, 11, 1, 3, 13, 3, AIR)
    t.mark(2, 11, 3, CHEST, {"loot": "vanilla:watchtower"})
    t.set(2, 11, 2, TORCH)
    t.save("watchtower")


def mineshaft():
    # Corridor along +X: 5 long, 3 wide (z 0-2), 3 high, with a timber frame at the start.
    for name, extra in (("mineshaft_corridor", None), ("mineshaft_corridor_chest", "chest"), ("mineshaft_corridor_webs", "webs")):
        t = Template(5, 3, 3)
        t.box(0, 0, 0, 4, 2, 2, AIR)
        t.box(0, 0, 0, 0, 1, 0, LOG)
        t.box(0, 0, 2, 0, 1, 2, LOG)
        t.box(0, 2, 0, 0, 2, 2, PLANKS)
        if extra == "chest":
            t.mark(3, 0, 2, CHEST, {"loot": "vanilla:mineshaft"})
        elif extra == "webs":
            for (x, y, z) in ((2, 2, 1), (3, 1, 0), (4, 2, 2), (1, 0, 1)):
                t.set(x, y, z, WEB)
        t.save(name)
    t = Template(5, 3, 5)
    t.box(0, 0, 0, 4, 2, 4, AIR)
    for (x, z) in ((0, 0), (4, 0), (0, 4), (4, 4)):
        t.box(x, 0, z, x, 2, z, LOG)
    t.set(2, 2, 2, TORCH)
    t.save("mineshaft_crossing")
    t = Template(9, 5, 9)
    t.box(0, 0, 0, 8, 4, 8, AIR)
    t.box(0, 0, 0, 8, 0, 8, "base:dirt")
    t.set(4, 1, 4, TORCH)
    t.save("mineshaft_room")


def colossus_arena():
    size = 25
    c = size // 2
    t = Template(size, 10, size)
    for x in range(size):
        for z in range(size):
            d = math.hypot(x - c, z - c)
            if d <= 12.4:
                t.set(x, 0, z, COBBLE if d > 9 else ("base:sandstone" if (x + z) % 2 == 0 else "base:sand"))
                for y in range(1, 10):
                    t.set(x, y, z, AIR)
    for i in range(8):
        angle = i * math.tau / 8
        px, pz = int(round(c + math.cos(angle) * 10)), int(round(c + math.sin(angle) * 10))
        top = 7 if i % 2 == 0 else 4  # some pillars crumbled
        t.box(px, 1, pz, px, top, pz, COBBLE)
        t.set(px, top, pz, STONE)
    t.box(c - 1, 1, c - 1, c + 1, 1, c + 1, STONE)
    t.mark(c, 2, c, "vanilla:ancient_altar", {"boss": {"entity": "vanilla:colossus"}})
    for (dx, dz) in ((0, -4), (0, 4), (-4, 0), (4, 0)):
        t.mark(c + dx, 1, c + dz, CHEST, {"loot": "vanilla:arena"})
    t.save("colossus_arena")


dungeon()
ruin("ruin_small", 7, 7, 7, 4)
ruin("ruin_long", 11, 9, 5, 3)
watchtower()
mineshaft()
colossus_arena()
