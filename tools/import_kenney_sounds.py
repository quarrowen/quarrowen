#!/usr/bin/env python3
"""Replaces the generated placeholder sound effects with Kenney's CC0 ones.

  python3 tools/import_kenney_sounds.py            # download (cached), copy, write CREDITS.md
  python3 tools/import_kenney_sounds.py --check    # verify what is committed matches this mapping

Why a script rather than "download these and drag them in": provenance. Every file that ships has to be
traceable to where it came from and under what terms, and the only way that stays true is if the mapping
is the thing in version control and the files are its output. CREDITS.md is generated from the table
below, so it cannot drift from what is actually on disk.

**CC0 is a dedication, not a warranty.** It carries no promise that the uploader had the right to give
the work away. That is the real risk with public asset sites, and it is why everything here comes from
one identifiable author publishing his own work rather than from an anonymous upload, and why the pack
archives are pinned by SHA-256: if upstream changes under us, this script stops rather than quietly
shipping something different. Kenney asks for no credit at all; we record it anyway, because a file
nobody can trace is a file nobody can defend.

A caveat worth writing down: these were chosen by *name*, not by ear. Nothing in this pipeline can hear.
The mapping is conservative - obvious semantic matches, nothing clever - and whether a footstep actually
sounds like a footstep is for somebody playing to say.
"""

import argparse
import hashlib
import os
import shutil
import sys
import urllib.request
import zipfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CACHE = os.path.join(ROOT, "build", "kenney")

# Pinned: URL and the SHA-256 of the archive as retrieved on 2026-09-18. A mismatch is a hard stop.
PACKS = {
    "rpg-audio": (
        "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
        "6dbeaf8544da958d8f2adcb4a4a4b76c1ade34a05f8ab9edccd327da7375f38b"),
    "impact-sounds": (
        "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
        "029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8"),
    "interface-sounds": (
        "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
        "f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232"),
    "digital-audio": (
        "https://kenney.nl/media/pages/assets/digital-audio/216eac4753-1677590265/kenney_digital-audio.zip",
        "24e6ce28b76a6d8c89cff4d331e0965ff5c3de8a73c612028e9d363cc64e4f06"),
}

# destination -> (pack, file inside the pack). Destinations are relative to the repository root.
#
# Deliberately NOT replaced, and why:
#   - every creature voice (pig, cow, zombie, the Colossus...). Kenney has no animals in these packs, and
#     a laser standing in for a wolf is worse than the generated growl. Those are the characterful ones
#     that want doing properly later.
#   - eating, gulping, burping. No equivalent here, and a wrong one is more noticeable than a plain one.
#   - explosion and its fuse. Nothing in these packs is an explosion.
MAPPING = {
    # --- The engine's own sounds; these ship inside the client ---
    "engine/client/sounds/ui_click.ogg": ("interface-sounds", "click_001.ogg"),
    "engine/client/sounds/page.ogg": ("rpg-audio", "bookFlip1.ogg"),
    "engine/client/sounds/pickup.ogg": ("rpg-audio", "handleSmallLeather.ogg"),
    "engine/client/sounds/drop.ogg": ("rpg-audio", "dropLeather.ogg"),
    "engine/client/sounds/equip.ogg": ("rpg-audio", "clothBelt.ogg"),
    "engine/client/sounds/craft.ogg": ("interface-sounds", "confirmation_002.ogg"),
    "engine/client/sounds/discover.ogg": ("interface-sounds", "confirmation_001.ogg"),
    "engine/client/sounds/item_break.ogg": ("impact-sounds", "impactWood_heavy_000.ogg"),
    "engine/client/sounds/swing.ogg": ("rpg-audio", "knifeSlice.ogg"),
    "engine/client/sounds/crit.ogg": ("impact-sounds", "impactPunch_heavy_000.ogg"),
    "engine/client/sounds/hurt.ogg": ("impact-sounds", "impactPunch_medium_000.ogg"),
    # A descending tone rather than anything gory: this plays for an eight-year-old at bedtime.
    "engine/client/sounds/death.ogg": ("digital-audio", "lowDown.ogg"),

    # --- base: the ground under your feet and the blocks you break ---
    "mods/base/sounds/soft_step0.ogg": ("impact-sounds", "footstep_grass_000.ogg"),
    "mods/base/sounds/soft_step1.ogg": ("impact-sounds", "footstep_grass_001.ogg"),
    "mods/base/sounds/soft_step2.ogg": ("impact-sounds", "footstep_grass_002.ogg"),
    "mods/base/sounds/stone_step0.ogg": ("impact-sounds", "footstep_concrete_000.ogg"),
    "mods/base/sounds/stone_step1.ogg": ("impact-sounds", "footstep_concrete_001.ogg"),
    "mods/base/sounds/stone_step2.ogg": ("impact-sounds", "footstep_concrete_002.ogg"),
    "mods/base/sounds/wood_step0.ogg": ("impact-sounds", "footstep_wood_000.ogg"),
    "mods/base/sounds/wood_step1.ogg": ("impact-sounds", "footstep_wood_001.ogg"),
    "mods/base/sounds/wood_step2.ogg": ("impact-sounds", "footstep_wood_002.ogg"),
    "mods/base/sounds/dirt_break0.ogg": ("impact-sounds", "impactSoft_heavy_000.ogg"),
    "mods/base/sounds/dirt_break1.ogg": ("impact-sounds", "impactSoft_heavy_001.ogg"),
    "mods/base/sounds/grass_break0.ogg": ("impact-sounds", "impactSoft_medium_000.ogg"),
    "mods/base/sounds/grass_break1.ogg": ("impact-sounds", "impactSoft_medium_001.ogg"),
    "mods/base/sounds/sand_break0.ogg": ("impact-sounds", "impactSoft_medium_002.ogg"),
    "mods/base/sounds/sand_break1.ogg": ("impact-sounds", "impactSoft_medium_003.ogg"),
    "mods/base/sounds/stone_break0.ogg": ("impact-sounds", "impactMining_000.ogg"),
    "mods/base/sounds/stone_break1.ogg": ("impact-sounds", "impactMining_001.ogg"),
    "mods/base/sounds/wood_break0.ogg": ("impact-sounds", "impactWood_medium_000.ogg"),
    "mods/base/sounds/wood_break1.ogg": ("impact-sounds", "impactWood_medium_001.ogg"),
    "mods/base/sounds/glass_break.ogg": ("impact-sounds", "impactGlass_medium_000.ogg"),

    # --- the rest ---
    "mods/guild/sounds/coin.ogg": ("rpg-audio", "handleCoins.ogg"),
    "mods/arcana/sounds/spark_cast.ogg": ("digital-audio", "zapTwoTone.ogg"),
    "mods/arcana/sounds/spark_hit.ogg": ("digital-audio", "zap1.ogg"),
    "mods/vanilla/sounds/bow.ogg": ("rpg-audio", "drawKnife1.ogg"),
    "mods/vanilla/sounds/shear.ogg": ("rpg-audio", "knifeSlice2.ogg"),
    "mods/vanilla/sounds/fishing_cast.ogg": ("rpg-audio", "cloth1.ogg"),
    "mods/vanilla/sounds/fishing_bite.ogg": ("interface-sounds", "bong_001.ogg"),
}

CREDITS_HEADER = """# Credits

Everything in Quarrowen that somebody else made, what it is used for, and under what terms.

## Sound effects

By **Kenney Vleugels** ([kenney.nl](https://kenney.nl)), dedicated to the public domain under
[Creative Commons Zero (CC0 1.0)](https://creativecommons.org/publicdomain/zero/1.0/). Kenney asks for
no credit at all; it is recorded here anyway, because a file nobody can trace is a file nobody can
defend - and because CC0 is a dedication rather than a warranty, so provenance is the only thing that
makes it checkable later.

These files remain CC0. Quarrowen's own [licence](LICENSE) does not and cannot restrict them: take them
and use them for anything.

Retrieved {date} from the packs listed below, each pinned by SHA-256 in `tools/import_kenney_sounds.py`,
which is what generated this file.

| In Quarrowen | Kenney pack | Original file |
|---|---|---|
"""

CREDITS_FOOTER = """
### The packs

| Pack | Source |
|---|---|
{packs}

## Music

Placeholder tracks generated by `tools/generate_music.py`, which is part of this project.

## Everything else

Textures, models and the remaining sound effects are generated by the scripts in `tools/` and are part
of this project. The creature voices in particular are still placeholders: Kenney's packs have no
animals in them, and a stand-in that is obviously wrong is worse than a plain one.
"""


def fetch(pack):
    url, want = PACKS[pack]
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"kenney_{pack}.zip")
    if not os.path.exists(path):
        print(f"downloading {pack}...")
        urllib.request.urlretrieve(url, path)
    got = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if got != want:
        sys.exit(f"{pack}: archive does not match the pinned checksum.\n"
                 f"  expected {want}\n  got      {got}\n"
                 "Upstream changed. Check what it is now before updating the pin.")
    return path


def source_bytes(pack, member):
    with zipfile.ZipFile(fetch(pack)) as z:
        names = [n for n in z.namelist() if os.path.basename(n) == member and not n.startswith("__")]
        if not names:
            sys.exit(f"{pack}: no file called {member} in the archive")
        return z.read(names[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify the committed files match this mapping")
    args = ap.parse_args()

    problems = []
    for dest, (pack, member) in sorted(MAPPING.items()):
        data = source_bytes(pack, member)
        full = os.path.join(ROOT, dest)
        if args.check:
            if not os.path.exists(full) or open(full, "rb").read() != data:
                problems.append(dest)
            continue
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(data)
        print(f"{dest} <- {pack}/{member} ({len(data) / 1024:.0f} KB)")

    if args.check:
        if problems:
            sys.exit("these do not match the mapping (re-run without --check):\n  " + "\n  ".join(problems))
        print(f"all {len(MAPPING)} imported sounds match the mapping")
        return

    from datetime import date
    rows = "".join(
        f"| `{dest}` | {pack} | `{member}` |\n"
        for dest, (pack, member) in sorted(MAPPING.items()))
    packs = "\n".join(f"| {p} | <https://kenney.nl/assets/{p}> |" for p in sorted(PACKS))
    with open(os.path.join(ROOT, "CREDITS.md"), "w") as f:
        f.write(CREDITS_HEADER.format(date=date.today().isoformat()) + rows
                + CREDITS_FOOTER.format(packs=packs))
    print(f"\nwrote CREDITS.md ({len(MAPPING)} files)")


if __name__ == "__main__":
    main()
