# Examples

One capability per mod, small enough to read in a sitting. These are documentation that runs: the test
suite validates every one of them, so they cannot quietly rot the way a code sample in a document does.

They are **not** shipped with the game and never loaded by a real world - they live here, not in `mods/`.
To try one:

```sh
godot --path . -- --host=proving,loot_example --dev --mods-dir=tests/mods
```

| Example | Capability | Where a real mod does it |
|---|---|---|
| [loot_example](loot_example/main.gd) | Loot tables: pools, weights, conditions, nested tables, extending another mod's table ([docs/loot.md](../docs/loot.md)) | `tests/mods/proving/life.gd` |
| [events_example](events_example/main.gd) | Events: react, change a value before it takes effect, cancel outright | every mod; `base/farming.gd` rewrites drops |
| [worldgen_example](worldgen_example/main.gd) | Shaping the world: an ore pass, a surface feature, a biome | `tests/mods/proving/main.gd` (FlatGround) |
| [ui_example](ui_example/main.gd) | Talking to players: a command, a permission, a panel, buttons that call back | `tests/mods/proving/society.gd`, `machines.gd` |
| [js_example](js_example/main.js) | The JavaScript sandbox: the same API in camelCase, events, commands, timers, saved data | `tests/mods/proving_js` |

## Capabilities and where to look

What the engine offers, the example that shows it on its own, and a shipping mod that uses it for real.
Anything in a shipping mod that exists *only* to demonstrate something belongs here instead.

| Capability | Example | In use |
|---|---|---|
| Blocks, items, recipes | `mod_tool -- new <id>` (the starter template) | `base` |
| Block shapes (slabs, stairs, fences) | — | `base/main.gd::_register_shapes` |
| Loot and drops | `loot_example` | `base`, `proving` |
| Events and cancelling | `events_example` | all |
| World generation | `worldgen_example` | `proving` |
| Commands, permissions, UI panels | `ui_example` | `proving` |
| Mod settings a host can change | — (see [docs/distribution.md §6](../docs/distribution.md)) | `proving` |
| JavaScript mods | `js_example` | `tests/mods/proving_js` |
| Mobs, AI and spawning | — | `tests/mods/proving/life.gd` |
| Containers, stations, processing | — | `base/stations.gd`, `proving/machines.gd` |
| Models with moving parts | — | `art/models/` (the archived machines) |
| Guide pages and tutorials | — | `base/guide.gd`, `proving/presentation.gd` |
| Structures and templates | — | `tests/mods/proving/things.gd` |

The dashes are the gaps worth filling next, in that order.

## Writing one

Keep to the shape the existing ones use: a header comment saying what the capability is and how to run
it, then one small function per idea, in the order someone would learn them. If an example needs an image
or a model, point at one another mod already ships (`"icon": "base:textures/coal.png"`) rather than adding
files - an example should be readable as text.
