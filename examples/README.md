# Examples

One capability per mod, small enough to read in a sitting. These are documentation that runs: the test
suite validates every one of them, so they cannot quietly rot the way a code sample in a document does.

They are **not** shipped with the game and never loaded by a real world - they live here, not in `mods/`.
To try one:

```sh
godot --path . -- --host=vanilla,loot_example --dev
```

| Example | Capability | Where a real mod does it |
|---|---|---|
| [loot_example](loot_example/main.gd) | Loot tables: pools, weights, conditions, nested tables, extending another mod's table ([docs/loot.md](../docs/loot.md)) | `vanilla` mob and block drops, `vanilla/structures.gd` chests |
| [events_example](events_example/main.gd) | Events: react, change a value before it takes effect, cancel outright | every mod; `base/farming.gd` rewrites drops, `vanilla` gates apples |
| [worldgen_example](worldgen_example/main.gd) | Shaping the world: an ore pass, a surface feature, a biome | `vanilla/biomes.gd`, `arcana` crystal pass |
| [ui_example](ui_example/main.gd) | Talking to players: a command, a permission, a panel, buttons that call back | `skyblock` challenges, `industry` machine screens, `arcana` HUD |
| [js_example](js_example/main.js) | The JavaScript sandbox: the same API in camelCase, events, commands, timers, saved data | `guild` (a full game-sized JavaScript mod) |

## Capabilities and where to look

What the engine offers, the example that shows it on its own, and a shipping mod that uses it for real.
Anything in a shipping mod that exists *only* to demonstrate something belongs here instead.

| Capability | Example | In use |
|---|---|---|
| Blocks, items, recipes | `mod_tool -- new <id>` (the starter template) | `base` |
| Block shapes (slabs, stairs, fences) | — | `base/main.gd::_register_shapes` |
| Loot and drops | `loot_example` | `vanilla`, `base` |
| Events and cancelling | `events_example` | all |
| World generation | `worldgen_example` | `vanilla`, `arcana` |
| Commands, permissions, UI panels | `ui_example` | `skyblock`, `industry` |
| Mod settings a host can change | — (see [docs/distribution.md §6](../docs/distribution.md)) | `vanilla` |
| JavaScript mods | `js_example` | `guild` |
| Mobs, AI and spawning | — | `vanilla/animals.gd`, `vanilla/monsters.gd` |
| Containers, stations, processing | — | `base/stations.gd`, `industry` |
| Models with moving parts | — | `industry` (cable arms, machines) |
| Guide pages and tutorials | — | `vanilla/guide.gd`, `vanilla/tutorial.gd` |
| Structures and templates | — | `vanilla/structures.gd` |

The dashes are the gaps worth filling next, in that order.

## Writing one

Keep to the shape the existing ones use: a header comment saying what the capability is and how to run
it, then one small function per idea, in the order someone would learn them. If an example needs an image
or a model, point at one another mod already ships (`"icon": "base:textures/coal.png"`) rather than adding
files - an example should be readable as text.
