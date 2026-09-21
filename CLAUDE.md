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

Content splits again below that line, settled 21 September 2026: **`base` owns nouns, a game owns
rules.** Blocks, liquids, biomes, flora and fauna are things that *exist* and belong to `base`;
progression, recipes and survival belong to a game. The test of whether the line is holding: **a
creative game ships zero recipes and everything still exists and works.** Machines and gear are their
own packs (`simple_machines`, `simple_gear`), so a game can take the blocks and write its own furnace.

## Things that must change together

These pairs have bitten before. Changing one without the other produces a bug that looks like something
else entirely.

- **Physics.** `engine/shared/player_physics.gd` ⇄ `native/src/physics.rs`. The client predicts the same
  step the server runs, so divergence shows up as rubber-banding, not as an error.
- **Block shapes.** `BlockRegistry.SHAPE_BOXES` ⇄ the consts and `boxes_of` match in `native/src/physics.rs`.
  A test (`_shape_twins`) compares them, but it reads the Rust *source*, so it cannot tell you the built
  library is stale - see below.
- **Mesher and pathfinder** have the same GDScript/Rust arrangement.
- **The two mod APIs.** `engine/server/mod_api.gd` ⇄ the JavaScript bridge. Written by hand, they
  drifted to 139 of 262 functions before anybody counted (2026-09-20), so the bridge is now generated:
  `engine/server/js/bindings.json` comes from the GDScript signatures and both `js_mod.gd` and
  `prelude.js` fall back to it, which means **a new `api.*` function reaches JavaScript the moment it
  exists**. Hand-written entries in `prelude.js` still win where one exists, because several rename or
  reorder on purpose.

  After adding to `mod_api.gd`, run `mod_tool.tscn -- bindings`; the suite fails when
  `bindings.json` or `unbound.txt` is stale. `unbound.txt` is down to the two functions that take a
  GDScript object and genuinely cannot cross JSON.

**The GDExtension is a checked-in build artifact.** `tools/run_tests.sh` rebuilds it when `native/src` is
newer and stops if that build fails. It did not always: a Rust file that did not compile once left the old
library in place and the suite reported on physics nobody was writing any more.

- **A new registry and `mod_reload._forget`.** Every registry a mod can put something in has to be
  cleared there, or reloading a mod that used it fails with "setup raised errors" on the way back in.
  Conditions, fields, characters, shops, ledgers, objectives, orders, modifiers, links, multiblocks,
  units and drives were all missed, and it went unnoticed until one mod declared all of them at once.
  (2026-09-21)

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

Both suites together take about eight minutes. If a run appears to take far longer than that, suspect
the thing watching it rather than the run.

**Never wait for the suite with `pgrep -f` on its own command line.** This:

```sh
while pgrep -f "bash tools/run_tests.sh" >/dev/null; do sleep 20; done   # WRONG
```

`pgrep -f` matches full command lines, and the waiting shell's command line *contains that string*, so
it finds itself and waits for ever. It cost hours once (2026-09-19): six of these accumulated, and one
of them had the actual test run sequenced behind it, so a verification everybody believed was running
had never started - the poll could not change, so the wait looked like a slow suite rather than a
deadlock. Run the suite in the foreground, or in the background and read its output file when it
reports; if a guard really is needed, match on something the waiter cannot contain (a pidfile, or the
run's own exit).

## The Proving Ground is how a capability gets tested

`tests/mods/proving/` is one mod that uses **every** capability the engine has, in GDScript, with a
JavaScript half (`proving_js`) covering the same ground through the bridge. It is the game the
end-to-end tests play, and it ships with nothing.

**Adding a capability means adding it here in the same commit**, and asserting it in
`tests/proving_test.gd`. That is not bookkeeping: until this existed the engine was tested through the
seven games bundled with it, so coverage was whatever the content happened to use - which is how 139
unbound JavaScript functions and 39 undocumented events went unnoticed for weeks.

Two rules that make it work:

- **It depends on nothing.** Not even `base`. `base` will churn as it grows, and a test mod riding on
  it fails every time somebody adds a bird. It registers its own rock and soil, and has **no textures
  at all** - the client draws a texture-less block as a magenta checker, which is free and honest.
- **The test asks the engine, not the mod.** `mod_tool validate` reported "0 errors" on a Proving
  Ground that threw two script errors during setup, because a mod that fails to register something
  still loads. Assert against the registries.

A test that names content is coupled to the mod that owns it, invisibly, until that mod goes. Prefer
asserting the capability.

## Before adding a capability, look for the one that exists

The mod-facing API is over 260 functions and the generated reference (`docs/api/index.html`) lists all of
them, so what gets reimplemented is never that. It is the **engine-internal shared pieces** — the
readers, registries and helpers that turn mod-supplied data into something usable — because those are
private and no document describes them.

So before writing something that reads, normalises or validates data a mod supplied, grep the registries
in `engine/shared/` for a function that already does it. Weather built its own particle emitter
dictionary by hand and the client then asked it for a key it did not have; `EffectRegistry` had a reader
for exactly that, with the defaults and the clamps already in it. (2026-09-19)

And when a second system does need one of those helpers, **make it public rather than copying it**. A
private function that two things use is a fact about the code that ought to be visible in the code.

## Things that look safe and are not

- **Adding a texture in the middle of `tools/generate_textures.gd`.** One RNG, seeded once, drives every
  texture in order: inserting a call changes every texture after it. Append new ones at the end, as the
  file says.
- **Reordering mod registration.** A recipe cannot name an item registered later in the same run. The
  same trap with a different face: anything that *reads an id at setup time* - a world generator built
  with `api.block(...)`, say - must be constructed after whatever registers that block, or it silently
  gets -1. A -1 block id encodes as 65535 and generates a world made of nothing, which presents as a
  player falling for ever rather than as a registration problem. (2026-09-21)
- **A mod-written name nested inside a definition.** Anything a mod names *inside* a dictionary it
  passes - a sound, an attack's condition, a field's condition, an order's behaviour - has to be
  qualified at the API boundary, the way `register_entity` already does for sounds. Unqualified is not
  an error: it is a bite that quietly does nothing. Four of these have been fixed one at a time; if a
  fifth appears, do one shared walk at registration instead. (2026-09-21)
- **`Thing.new().setup(api)` without keeping the object.** A RefCounted nobody holds is freed as soon
  the line finishes, and any handler it registered goes with it - silently, because registration
  succeeded. Mod submodules are kept as members (`var buckets` ... `buckets = Buckets.new()`) for this
  reason, and it cost an hour the first time. (2026-09-20)
- **`queue_free()` when rebuilding a panel.** It frees at the end of the frame, so a rebuild that runs
  twice in one frame frees the new children too. Take the child out of the tree first.
- **Changing a block or item id.** Saves are by name (`SAVE_FORMAT 2`); ids shift whenever anything is
  added. Display names are safe to change, ids are not.
- **Keeping the answer to `api.block()` / `api.item()` / `api.entity_type()`.** Those three ask a
  *question* - "is this installed?" - and answer -1 for no, which mods rely on to make optional
  content optional. **A -1 you store becomes 65535 when written as the u16 a block id is, and 65535 is
  UNLOADED**, so the world reads as absent rather than wrong: the symptom is a player falling for
  ever, nothing about registration. For anything you keep - a generator, a cached field, a table - use
  `require_block` / `require_item` / `require_entity`, which say so at load and hand back something
  inert. (2026-09-21)
- **`:=` on anything reached through an untyped variable.** `var x := _server.thing()` is a *parse*
  error ("Cannot infer the type of x"), and a parse error means the whole script silently fails to
  load, which surfaces as something unrelated much later - a mod that does not register, a client that
  cannot be constructed, a test that fails on an assertion it never reached. `_server`, `api`, `c` and
  `player` are all untyped by convention here, so annotate: `var x: String = ...`. The suite checks
  every script under `engine/`, `mods/` and `tests/` really parses, which is the fast way to find it.

  In a **tool scene** the same mistake looks like a hang rather than a failure: the script does not
  compile, so the `get_tree().quit()` at the end of it never runs and `mod_tool.tscn` sits there for
  ever. Run tool scenes with `timeout` - and with the full path to Godot, because `godot` is a shell
  function here and `timeout` cannot see it. (2026-09-20)
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

Godot strips the MCP editor plugin's three autoloads from `project.godot` whenever **the game** is run
from this checkout. The change looks deliberate and is not; committing it quietly breaks the editor
integration on the machine that has the addon.

**Check `git diff project.godot` before committing after anything that launches the game**, and
`git checkout -- project.godot` if those three autoload lines have gone.

Measured rather than assumed, after this was blamed on the wrong thing twice (2026-09-19). What is
actually true: `addons/godot_mcp/` **is** present on disk, so "Godot cannot see it" was never the
reason. A headless *tool* run (`mod_tool.tscn -- docs`) leaves the file alone. An **e2e test run strips
it every time**, because those launch the game, and `tools/run_tests.sh` does not touch the file itself
- it is Godot, dropping autoloads it will not load outside the editor and saving the result.

So the open editor is not the culprit and closing it fixes nothing: it is the test suite, and any run
including `e2e:*` will do it again.

## Right now: do not tag a release

The children are on 0.41.1 and their clients update themselves from `update.json`, which a `v*` tag
republishes. Tagging mid-playtest moves them to a protocol the family server does not speak. Push to
master as much as you like — that only runs tests — but do not tag until the user says the playtest is
over. (2026-09-19)

There is now a second and simpler reason: **the games are deleted**, so a release from master would
ship an engine with nothing to play. The children have been told 1.0 will be a fresh game, and that is
what a tag has to wait for. (2026-09-21)

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
- `mods/` - bundled content. **`base` alone.** The seven games were deleted on 21 September 2026 and
  will be rebuilt for 1.0; `art/models/` keeps the models they used, which no script can regenerate.
- `tests/mods/proving/` - **the Proving Ground**, the game the tests play. Not shipped.
- `native/` - the Rust extension.
- `deploy/server/` - what the family server runs. Meant to be copied on its own, without the repository.
- `PROGRESS.md` - status, roadmap, playtest findings, and the decisions behind them. Read it first.
- `docs/` - hosting, modding, the engine, distribution, and the generated API reference.
