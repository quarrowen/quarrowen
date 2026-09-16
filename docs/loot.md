# Loot and drops

One way to say "what comes out of this", used by every source: a mob that dies, a block that breaks, a
chest in a dungeon, a fishing line, a reward. Before this, those were three unrelated pieces of code with
three shapes, none of which a host could tune or another mod could extend.

## 1. A table

```gdscript
api.register_loot("zombie", {
    "pools": [
        # Almost always some flesh.
        {"rolls": [0, 2], "entries": [
            {"item": "base:rotten_flesh", "count": [1, 2], "weight": 3},
            {"empty": true, "weight": 1},
        ]},
        # Only when a player did it, and rarely.
        {"rolls": 1, "when": {"killed_by": "player"}, "entries": [
            {"item": "base:iron_ingot", "weight": 1},
            {"table": "vanilla:junk", "weight": 4},   # roll another table instead
            {"empty": true, "weight": 45},
        ]},
    ],
})
```

- **pools** roll independently, so "always some flesh, and separately a small chance of something good"
  needs no arithmetic. `rolls` is a number or a `[min, max]` range.
- **entries** carry a `weight` (relative, within the pool), and one of `item`, `table` (roll another
  table) or `empty: true` (the miss - this is how a chance below 1 is written).
- **count** is a number or `[min, max]`.
- **data** is the item data a dropped stack carries (durability, quality, a part's material).
- **when** is a condition, on a pool or a single entry (§2).
- A table with no `pools` may use the old `{rolls, entries}` shape; it is read as a single pool.

Tables can also be **JSON files** in a mod: every `loot/*.json` in the mod folder is registered under
`<mod>:<file name>`, so a creator tunes numbers without touching code.

## 2. Conditions

`when` takes any of these; all of them have to hold:

| Condition | Meaning |
|---|---|
| `killed_by` | `"player"`, `"mob"`, `"fire"`, `"fall"`, … - what caused it |
| `tool` | an item name, or `{"material": "iron"}` / `{"tier": 2}` - what it was broken with |
| `biome`, `depth`, `time` | where and when it happened (`depth` is a `[min, max]` of Y) |
| `chance` | a plain 0-1 roll, for when weights are overkill |
| `first_time` | the first time *this player* gets this (per mob type, per chest) |

The **context** a source passes in carries the player, the tool, the position and what did the killing,
so a mod's condition sees the same facts the engine does.

## 3. Sources

| Source | Table | Context |
|---|---|---|
| a mob dies | the entity's `loot`, or one generated from its old `drops` | killer, tool, position, biome, depth |
| a block breaks | the block's `loot`, or one from its `drops` | player, tool, position, biome, depth |
| a chest is opened | the container's `loot` block data | player, position; seeded so the same chest holds the same loot |
| a mod asks | `api.roll_loot(name, context)` | whatever the mod passes |

An entity or block that still declares `drops: [[item, count, chance]]` keeps working: it is turned into
a table with one pool per line at load, so every old mod gets conditions, tuning and extension for free.

## 4. Extending someone else's table

A mod (or a server's own small mod) adds to or replaces a table without forking the mod that owns it:

```gdscript
api.extend_loot("vanilla:zombie", {"pools": [{"rolls": 1, "entries": [{"item": "mymod:charm", "weight": 1}]}]})
api.replace_loot("vanilla:zombie", {...})   # start again
```

## 5. What a player notices

- **A rare drop is an event.** Rarity is worked out from the weights, so the engine knows without being
  told: a sparkle, a sound, a beam of light on the item so it is not lost in the grass, and a line in
  chat when it is rare enough.
- **Shared chests roll per player.** Everyone who opens the dungeon chest gets their own loot, so
  nobody has to race a sibling for the good item.
- **Bad luck does not last.** A pity counter guarantees the rare drop after a long enough run without
  one, and the first time a player kills a kind of mob it gives a little extra.
- **The guide answers "what drops this?"** - every item lists the mobs, blocks and chests it comes from,
  which is the fastest way to learn a world.

## 6. Tuning

`vanilla` exposes a **How much loot** setting (less / normal / lots) through the mod settings screen, so
a host changes drop rates for their family's server without editing anything. It multiplies pool roll
counts, never the guaranteed part of a drop.

## 7. Left for later

Per-player luck as a stat, weather conditions, airdrops on a schedule, fishing tables by biome and
depth, and drop telemetry in the dev dashboard. The table format already has room for all of them.
