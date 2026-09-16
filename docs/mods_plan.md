# The mod catalogue: what we keep, what we grow, what we retire

The mods grew as proofs that an engine capability works. Before they are published as downloads
(docs/distribution.md), here is what each one actually is, what it should become, and the order of work.

## Where they stand

| Mod | Size | Content | What it proved | State |
|---|---|---|---|---|
| **base** | 928 lines, 42 blocks, 15 items, 203 textures | terrain and building blocks, tools, food, stations, beds, graves | block/item/recipe registration, containers, stations, mining rules | **Library.** Everything depends on it. Not a game, never published as one. |
| **vanilla** | 1057 lines, 17 blocks, 19 items, 12 entities, 60 models | biomes, mobs, day/night, the survival loop, the guide, tutorials | the whole engine, end to end | **Flagship game.** Where new content goes by default. |
| **oneblock** | 190 lines | one block over the void, phases, crates | that a game can be tiny and still fun | **Game.** New; watch whether the kids play it. |
| **skyblock** | 217 lines, 1 block | island start, cobble generator, 3 challenges | custom world generation, spawn handlers, void rules | **Game, thin.** Three challenges is a demo, not a game. Grow it or let One Block cover this ground. |
| **arcana** | 414 lines, 6 blocks, 7 items | mana, wands, crystals, pylons, a HUD | items with behaviour, projectiles, effects, per-player HUD, generation passes | **Add-on, keep.** The magic pillar; kids like wands. |
| **industry** | 512 lines, 3 blocks, 24 models | generator, cable, lamp, machine screens | model blocks with arms, machine UI, processing, power | **Add-on, thin as content.** Three blocks. Either it grows into a tech tier or it becomes an example. |
| **guild** | 517 lines (JavaScript), 5 blocks, 3 items | quests, coins, a shop, a leaderboard, a meteor event | the JavaScript sandbox, mod storage, UI, economy | **Add-on, keep.** The only JS mod and the best "quests" content we have. |

`tests/mods/*` (ai_arena, buggy, reloadme...) stay where they are: fixtures for the test suite, never published.

## What the catalogue should look like

Four kinds, and the index (`mods.json`) carries the kind so the download page and the in-game list can
group them:

- **library** - `base`. Ships inside the app, never chosen directly.
- **game** - `vanilla`, `oneblock`, `skyblock`. What "New world" offers. Ships inside the app.
- **add-on** - `arcana`, `industry`, `guild`. Downloaded, added to a world that already has a game.
- **example** - a handful of small mods, one capability each, in `examples/` (see its README for the
  capability matrix). Not published, not shipped, never loaded by a real world, but validated and loaded
  by the test suite so they stay true.

That last kind is the fix for the real problem: today the add-ons carry two jobs at once (be fun, and
show how the engine works), and the second job keeps them thin.

## Decisions to take (my recommendation)

1. **industry**: keep it as an add-on for now, but stop treating it as the machine showcase. The showcase
   moves to `examples/model_block` and `examples/machine`. If the kids ignore industry after alpha 2,
   retire it and keep the examples.
2. **skyblock**: keep, and grow it to about fifteen challenges with rewards that lead somewhere (island
   themes, a second island, a shop). If that work does not happen before alpha 3, fold it into One Block
   as a "classic island" start and retire the mod.
3. **arcana and guild**: keep and polish. Both have real content; both need a guide page and sounds.
4. **base**: split nothing. It is a library and it is allowed to be large.
5. **vanilla**: the default home for anything the kids ask for that is not clearly a side mode
   (stairs, chests, food, mobs). Add-ons stay optional.

## Rollout

**Phase 0 - catalogue metadata. Done (0.39.0).** Every `mod.json` carries `kind` (library / game / addon /
example), `ModLoader` reads it, the validator checks it agrees with `game:`, `mod_tool -- new` writes it,
the index (`mods.json`) carries it, and both the in-game Mods page and the download page group by it.

**Phase 1 - ship the split. Deferred, on purpose.** The idea was that the app carries base and the games
while the add-ons are downloads. Measured, the three add-ons are 736 KB of a 62 MB app - about 1% - so the
saving is not real, while the cost is: a child whose local world uses arcana would find it broken until
they installed it again. The decision this phase was really meant to force (does anyone play industry?)
needs playtest evidence we do not have yet. Revisit when the alpha 3 feedback says who plays what; the
mod list makes the install one click whenever we do.

**Phase 2 - mod settings. Done (0.39.0).** Schema, values in the world, a section per mod in the admin
screen, `mod_settings.json` for a headless server, `/modsettings`. See docs/distribution.md §6. vanilla
uses it for monsters, day length, how much things drop and whether zombies burn.

**Phase 3 - the in-game mod list. Done (0.39.0).** Menu → Mods: installed / available / updates, install
and remove, dependencies pulled in, the index signed like the update manifest. New world lists whatever is
installed and re-reads it after a change.

**Phase 4 - examples and the capability matrix. Done (0.39.0).** `examples/` holds one small mod per
capability - loot, events, world generation, commands and UI, and a JavaScript one - with a table in
`examples/README.md` mapping each engine capability to the example that shows it and the shipping mod that
uses it for real. The test suite validates and loads them, so they cannot rot. The gaps the table shows
(mobs and spawning, containers and stations, models with moving parts, guide pages, structures) are the
next examples to write, in that order.

**Phase 5 - quality pass.** Per kept mod: a guide page, sounds for every action, a tutorial entry where it
makes sense, and an e2e test that plays its loop (arcana, industry, guild and skyblock already have one).
Waiting on alpha 3 feedback, so the effort goes to whichever mods the kids actually open.

**Phase 6 - community mods.** Only after the list works: the advanced install path, what a submission looks
like, and how a "verified" mark is earned.
