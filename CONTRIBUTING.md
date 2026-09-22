# Contributing

Quarrowen is a voxel **engine**: the engine provides capabilities, and mods provide the content. Most
contributions therefore land in one of two places - a mod, or a capability the engine is missing.

## Making a mod

Start with the wizard: **Create → New mod** in the menu, or

```sh
godot --headless --path . res://tools/mod_tool.tscn -- new my_mod
```

A mod is a folder with `mod.json` and a `main.gd` (or `main.js` - JavaScript mods run sandboxed). The
whole API is in [docs/api/mod-api.md](docs/api/mod-api.md), and the engine's own readers are in
[docs/api/engine.md](docs/api/engine.md) - both generated from the engine source, and the
mods in `mods/` are worked examples: `vanilla` (a full game), `oneblock` and `skyblock` (small games),
`arcana` and `industry` (add-ons), `guild` (JavaScript).

Before opening a pull request:

```sh
godot --headless --path . res://tools/mod_tool.tscn -- validate mods/my_mod   # manifest, files, scripts
tools/run_tests.sh                                                            # the suite, native
QW_NATIVE=0 PORT_BASE=25700 tools/run_tests.sh                             # and the GDScript paths
```

## Changing the engine

- **Both engines must agree.** Anything in `native/src/` has a GDScript twin (`engine/shared/`,
  `engine/client/chunk_mesher.gd`); a change to one needs the same change in the other, and the suite
  runs both.
- **Saves must keep loading.** Nothing persisted may refer to a runtime id, every saved shape carries a
  version, and `tests/fixtures/saves/` holds a world from each release that the suite loads, re-saves
  and reloads. See the save-compatibility section in `PROGRESS.md`.
- **Tests come with the change.** `tests/` has unit-style checks, end-to-end games (a real client
  against a real server), an AI arena, an AI soak on generated terrain and load tests with bots.
- Comments explain *why*, not *what*. Match the surrounding style; no attribution lines in commits.

## Reporting something

Issues are welcome: what happened, what you expected, and the version from the menu. Playtest reports
from people actually playing (especially kids) are the most useful thing there is - most of what the
game does was shaped by exactly that.

## Licence

Contributions are made under the project's licence ([LICENSE](LICENSE), PolyForm Noncommercial 1.0.0):
free for noncommercial use, with commercial use needing a separate licence from the author.
