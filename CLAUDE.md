# Working on Quarrowen

Quarrowen is a voxel game engine in Godot 4.7 with a Rust extension, built for one family's children and
for anyone else who wants it. This file is the short list of things that are true about this codebase and
are not obvious from reading any one file. Everything else is in `docs/`.

## The one rule the whole design rests on

**The engine provides capabilities; mods provide content.** A feature that names a particular block, item
or story belongs in a mod. A feature that lets *any* mod do that kind of thing belongs in the engine.

When a request sounds like content ("add a bow"), the question to ask first is what capability is missing
(holding a use to draw it) and whether that belongs in the engine. Usually the capability is small and
general and the content is a dozen lines in `mods/`.

## Things that must change together

These pairs have bitten before. Changing one without the other produces a bug that looks like something
else entirely.

- **Physics.** `engine/shared/player_physics.gd` ⇄ `native/src/physics.rs`. The client predicts the same
  step the server runs, so divergence shows up as rubber-banding, not as an error.
- **Block shapes.** `BlockRegistry.SHAPE_BOXES` ⇄ the consts and `boxes_of` match in `native/src/physics.rs`.
  A test (`_shape_twins`) compares them, but it reads the Rust *source*, so it cannot tell you the built
  library is stale - see below.
- **Mesher and pathfinder** have the same GDScript/Rust arrangement.

**The GDExtension is a checked-in build artifact.** `tools/run_tests.sh` rebuilds it when `native/src` is
newer and stops if that build fails. It did not always: a Rust file that did not compile once left the old
library in place and the suite reported on physics nobody was writing any more.

## The tests must not touch the player's folder

`project.godot` sets `use_custom_user_dir`, so `user://` from this checkout **is** the installed app's
folder. Anything the suite writes there lands in somebody's real game. This has bitten three times: it
took the player's identity and settings, and later filled their caches and reset a pinned recipe.

New client paths go through `engine/shared/user_paths.gd`, never a bare `user://`. `tools/run_tests.sh`
sets `QW_USER_DIR`, and a test asserts the mechanism works rather than trusting it.

## Running the tests

Both suites, always. The second one exercises the GDScript fallbacks, which are what run where there is no
native library:

```sh
tools/run_tests.sh
QW_NATIVE=0 PORT_BASE=25700 tools/run_tests.sh
```

`ONLY=gameplay tools/run_tests.sh` narrows it while working; `EXCEPT="e2e:*"` is the inverse. The suite
prints where its logs are - read them rather than guessing, especially for an e2e failure.

A test that waits a fixed number of seconds for the server to do something will pass here and fail on a
small CI runner, which simulates less in that time. Wait for the event, not for a stopwatch.

## Things that look safe and are not

- **Adding a texture in the middle of `tools/generate_textures.gd`.** One RNG, seeded once, drives every
  texture in order: inserting a call changes every texture after it. Append new ones at the end, as the
  file says.
- **Reordering mod registration.** A recipe cannot name an item registered later in the same run.
- **`queue_free()` when rebuilding a panel.** It frees at the end of the frame, so a rebuild that runs
  twice in one frame frees the new children too. Take the child out of the tree first.
- **Changing a block or item id.** Saves are by name (`SAVE_FORMAT 2`); ids shift whenever anything is
  added. Display names are safe to change, ids are not.
- **`:=` on anything reached through an untyped variable.** `var x := _server.thing()` is a *parse*
  error ("Cannot infer the type of x"), and a parse error means the whole script silently fails to
  load, which surfaces as something unrelated much later - a mod that does not register, a client that
  cannot be constructed, a test that fails on an assertion it never reached. `_server`, `api`, `c` and
  `player` are all untyped by convention here, so annotate: `var x: String = ...`. The suite checks
  every script under `engine/`, `mods/` and `tests/` really parses, which is the fast way to find it.
- **`godot --check-only --script <file>`.** It reports success on a file that does not parse. To check a
  script really compiles, `load()` it and ask `can_instantiate()` - which is what the suite does for every
  script under `engine/`.

## When to bump `Protocol.VERSION`

Whenever the client and the server must agree on something, not only when an RPC changes. The block shape
table and the movement code both count: an older client walks into a different world from the one the
server is simulating, and the player sees rubber-banding rather than a version problem. A mismatch is
refused at the door, which is the kind failure.

## Documentation that is generated

`docs/api/index.html` is built from the engine's own sources, and a test fails when it is out of date:

```sh
godot --headless --path . res://tools/mod_tool.tscn -- docs
```

Run it after touching `engine/server/mod_api.gd`, any `## ` header comment listed in
`tools/docs_generator.gd`, or `engine/server/js/quarrowen.d.ts`.

## Running the game rewrites project.godot

Godot strips the MCP editor plugin's autoloads from `project.godot` whenever the game is run from this
checkout, because `addons/godot_mcp/` is gitignored and it cannot see it. The change looks deliberate
and is not; committing it quietly breaks the editor integration on the machine that has the addon.

**Check `git diff project.godot` before committing after anything that launches the game**, and
`git checkout -- project.godot` if those three autoload lines have gone. It has happened twice.

## Right now: do not tag a release

The children are on 0.41.1 and their clients update themselves from `update.json`, which a `v*` tag
republishes. Tagging mid-playtest moves them to a protocol the family server does not speak. Push to
master as much as you like — that only runs tests — but do not tag until the user says the playtest is
over. (2026-09-19)

## Saves, until 1.0.0

Breaking the save format is **allowed** before 1.0.0 (the user, 2026-09-19: worlds will be reset, and
migrations are not worth writing yet). A break must still be deliberate, announced in the release notes,
and refuse an old world clearly rather than half-loading it. Drop the fixtures that no longer load and
add one for the new version.

Keep doing the four things that cost nothing: save by name not by id, version every saved shape, write
back content whose mod is missing, and add a fixture each release. After 1.0.0 all of this becomes a
promise instead of a habit, and corruption-proofing starts to matter.

## Releases

The checklist is in `docs/distribution.md` ("Cutting a release"). The two steps that are easy to get wrong:
bump the pinned image in `deploy/server/.env.example`, and bring the family server up on the new version
*before* publishing the site - a client that has updated itself cannot join a server that has not.

## Ideas do not evaporate

Work arrives in the middle of other work: a bug report while a feature is half-built, an idea while
chasing a regression. **Write it down before carrying on.** `PROGRESS.md` is the place - a line under the
right heading, with enough of the reasoning that it still makes sense next week.

This applies to the small ones especially. A design decision taken aloud and not written down is one that
gets taken again, differently, a fortnight later. If something is deliberately *not* being done, write
that down too, with why - a rejected idea that leaves no trace comes back.

Before saying a piece of work is finished, check that everything raised during it is either done or
recorded. Nothing should only exist in the conversation.

## House style

- Comments say **why**, not what. If a line needs explaining, explain the reason it is that way, ideally
  with the failure that made it so. `# playtest, 2026-09-18` is a useful thing to write.
- British spelling in prose; code keeps whatever the API uses.
- Commit messages are prose, not bullet lists: what changed, and what it was like before. The first line
  is a sentence, not a category.
- No attribution lines or co-author trailers in commits.
- Player-facing text is for children: plain, kind, never arch. Death messages and hints get read by an
  eight-year-old at bedtime.

## Where things are

- `engine/` - the engine. `client/`, `server/`, `shared/`, `net/`.
- `mods/` - bundled content. `base` (blocks and tools), `vanilla` (the survival game), `hearthhold` (the
  story game), plus add-ons and two game modes.
- `native/` - the Rust extension.
- `deploy/server/` - what the family server runs. Meant to be copied on its own, without the repository.
- `PROGRESS.md` - status, roadmap, playtest findings, and the decisions behind them. Read it first.
- `docs/` - hosting, modding, the engine, distribution, and the generated API reference.
