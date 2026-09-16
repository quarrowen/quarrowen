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

A mod (or a server's own small mod) adds to or replaces a table without forking the mod that owns it. A
mob's or block's generated table is named `mob:<entity>` or `block:<block>`:

```gdscript
api.extend_loot("mob:vanilla:zombie", {"pools": [{"rolls": 1, "entries": [{"item": "mymod:charm", "weight": 1}]}]})
api.register_loot("mob:vanilla:zombie", {...})   # start again: registering a name again replaces it
```

## 5. What a player notices

- **A rare drop is an event.** Rarity is worked out from the weights, so the engine knows without being
  told. A drop of 6% or less sparkles where it lands, keeps sparkling for a few seconds so it is not lost
  in the grass, plays a sound and is announced in chat. A handler can set `announce: false` on the
  `rare_loot` event to keep a particular find quiet.
- **Shared chests roll per player.** A chest whose data says `personal: true` (every vanilla structure
  chest) rolls separately for each player: what you find is handed straight to you, once each, so nobody
  has to race a sibling for the good item. The chest is then an ordinary chest to keep things in. Doing
  it this way means no per-viewer container view, so it needed no protocol change; the trade is that the
  loot arrives in your pack rather than sitting in the box.
- **Bad luck does not last.** A pity counter gives the table's rarest entry after 40 rolls without a
  find. The first time a player meets a table the engine emits `loot_first_time`, and a `first_time`
  condition can hold a pool back for exactly that moment - vanilla uses it so your first pig, cow, zombie
  and so on leaves something extra.
- **Every item says where it comes from.** Its tooltip ends with "Dropped by Zombie (12%), Stone" - the
  few likeliest sources, worked out from the tables and sent to the client when it joins. The fastest way
  to learn a world, and it costs one line in the payload the server already sends.

## 6. Tuning

Two levels, because an event needs more than one dial:

- **How much loot** (less / normal / lots) is a vanilla mod setting in the admin screen: one multiplier on
  every pool's roll count, for the whole server.
- **One thing at a time**, for an event: `/loot boost base:coal 3 60` makes coal three times as common for
  an hour and then stops on its own; `/loot boost vanilla:dungeon 2` enriches one table until it is
  changed back. Mods do the same with `api.set_loot_boost(target, factor, seconds)`. `/loot` shows what is
  turned up, `/loot clear` puts everything back.

Both are kept with the world. A pool marked `guaranteed: true` ignores them, so a drop something depends
on cannot be tuned away.

## 7. Left for later

Per-player luck as a stat, weather conditions, airdrops on a schedule, fishing tables by biome and
depth, and drop telemetry in the dev dashboard. The table format already has room for all of them.
