#!/usr/bin/env python3
"""Writes Hearthhold's structure templates (the same JSON `/struct save` produces):

  python3 tools/generate_hearthhold.py

Two places, and both are meant to be read before they are used. The outpost is where a player arrives:
a wall with a gap in it, a cold hearth, and a board with the last warden's handwriting still on it -
everything says somebody kept this place and then stopped. The cold camp is where Bramble is found:
a fire that went out days ago and two bowls still on the stones, which is the whole of her story told
without a word of it.
"""

import json
import random

OUT = "mods/hearthhold/structures/"

AIR = "engine:air"
COBBLE, STONE, PLANKS, LOG, GRAVEL = "base:cobblestone", "base:stone", "base:planks", "base:log", "base:gravel"
TORCH, CHEST, BED = "base:torch", "base:chest", "base:bed"
SLAB, STAIRS = "base:cobblestone_slab", "base:cobblestone_stairs_north"
HEARTH, BOARD = "hearthhold:cold_hearth", "hearthhold:charter_board"


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
            json.dump({"size": self.size, "palette": palette, "blocks": blocks, "data": self.data},
                      f, separators=(",", ":"))
        print("%s: %s, %d blocks" % (name, self.size, len(blocks)))


def outpost():
    """Where you arrive. A yard inside a broken wall, with the hearth at its middle."""
    rng = random.Random(7)
    t = Template(13, 7, 13)
    # The yard: flagstones worn through to gravel in places.
    for x in range(1, 12):
        for z in range(1, 12):
            t.set(x, 0, z, GRAVEL if rng.random() < 0.3 else COBBLE)
    # The wall, with courses knocked out of it so the place reads as unkept rather than abandoned.
    for i in range(13):
        for (x, z) in [(i, 0), (i, 12), (0, i), (12, i)]:
            height = 3 if rng.random() > 0.35 else 2
            for y in range(1, height + 1):
                t.set(x, y, z, COBBLE)
            if rng.random() < 0.2:
                t.set(x, height, z, AIR)  # a course fallen off the top
    # The gap somebody never got round to mending: the wall is open to the south.
    t.box(5, 1, 12, 7, 3, 12, AIR)
    for x in range(5, 8):
        t.set(x, 1, 12, SLAB)  # rubble where it fell
    # The hearth at the middle, cold, with a ring of seats round it.
    t.set(6, 1, 6, HEARTH)
    for (x, z) in [(4, 6), (8, 6), (6, 4), (6, 8)]:
        t.set(x, 1, z, SLAB)
    # The charter board on the north wall, where anyone coming in would see it.
    t.mark(6, 2, 2, BOARD, {"charter": True})
    # A lean-to against the east wall: a bed, a roof, somewhere to start from.
    t.box(9, 1, 3, 11, 3, 6, AIR)
    t.box(9, 4, 3, 11, 4, 6, PLANKS)
    for z in range(3, 7):
        t.set(9, 1, z, PLANKS)
        t.set(9, 2, z, PLANKS)
    t.set(10, 1, 4, BED)
    t.set(11, 2, 5, TORCH)
    # A chest of what the last warden left behind. Not much, and enough.
    t.mark(10, 1, 6, CHEST, {"loot": "hearthhold:warden", "personal": True})
    t.save("outpost")


def cold_camp():
    """Where Bramble is. A fire gone out, a shelter of branches, and two bowls still on the stones."""
    t = Template(7, 4, 7)
    for x in range(1, 6):
        for z in range(1, 6):
            t.set(x, 0, z, GRAVEL)
    # The fire, long dead, ringed with stones.
    for (x, z) in [(2, 3), (4, 3), (3, 2), (3, 4)]:
        t.set(x, 1, z, COBBLE)
    t.set(3, 3, 1, AIR)
    # A lean-to of logs and planks, open to the fire.
    for z in range(2, 5):
        t.set(5, 1, z, LOG)
        t.set(5, 2, z, PLANKS)
    t.box(4, 3, 2, 5, 3, 4, PLANKS)
    t.set(4, 1, 2, SLAB)  # something to sit on
    # Her things: one chest, and nothing else worth carrying.
    t.mark(4, 1, 4, CHEST, {"loot": "hearthhold:camp", "personal": True})
    t.save("cold_camp")


outpost()
cold_camp()
