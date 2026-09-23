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
  `bindings.json` or `unbound.txt` is stale. `unbound.txt` is down to **two**: the only two functions
  that take a GDScript object and genuinely cannot cross JSON. It was 18 until the `Player` and
  `Entity` methods were generated the same way, on 21 September 2026.

  **The generated bindings do not cover the hand-written ones.** `prelude.js` entries win where one
  exists, and they pass their arguments positionally - so reordering a signature in `mod_api.gd`
  silently desynchronises any hand-written entry for it. Reordering `set_block` would have broken
  every JavaScript `setBlock` call this way. Grep `prelude.js` for the name before you reorder.

**The GDExtension is built, never committed.** `native/bin/` is gitignored and no `.dylib`, `.so` or
`.dll` is tracked; CI builds one per platform and the release job bundles them. `tools/run_tests.sh`
rebuilds it when `native/src` is newer and stops if that build fails. It did not always: a Rust file
that did not compile once left the old library in place and the suite reported on physics nobody was
writing any more. (This paragraph said "checked-in build artifact" until 2026-09-23, which was simply
untrue - worth correcting, because the next person to read it would have gone looking for a file that
is not there.)

**So a fresh clone runs on the GDScript fallbacks until something builds the library**, which is one
of several ordinary ways to end up without it - see "When the Rust extension is not there" below.

- **A new registry and `mod_reload._forget`.** Every registry a mod can put something in has to be
  cleared there, or reloading a mod that used it fails with "setup raised errors" on the way back in.
  Conditions, fields, characters, shops, ledgers, objectives, orders, modifiers, links, multiblocks,
  units and drives were all missed, and it went unnoticed until one mod declared all of them at once.
  (2026-09-21)

## When the Rust extension is not there

`Native.enabled()` (`engine/shared/native.gd`) is false whenever `NativeVoxelWorld` is not registered,
and every native feature has a GDScript twin, so the engine runs either way. That is not a theoretical
safety net - **it is the shipping path for at least one target**:

- **iOS/iPad: we have not built one.** `quarrowen_native.gdextension` declares macOS, Linux x86_64,
  Linux arm64 and Windows x86_64, and nothing else. **This is a gap in our build, not a limit of
  Rust** - `aarch64-apple-ios` is an ordinary Rust target and godot-rust documents iOS export - it is
  simply work nobody has done yet (milestone 6 in PROGRESS.md). Until it is done the iPad client runs
  **entirely** on the fallbacks, and their performance is the iPad's performance.
- **Any platform outside that list**: Android, Web, Windows on arm64.
- **A fresh clone**, until `tools/build_native.sh` or the suite builds one.
- **A library that fails to load** - wrong architecture, blocked by Gatekeeper, an ABI mismatch after a
  Godot upgrade. It degrades silently to the fallbacks rather than crashing, which is the kind failure
  and also the kind that hides.

The deployed Linux server is the one place it is guaranteed: `Dockerfile` fails the build unless the
`.so` is present. Anyone running a server from source without building it gets the fallbacks.

**This is why `QW_NATIVE=0 tools/run_tests.sh` is not optional.** It is not testing a contingency; it
is testing what the children's iPads will actually run.


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

`tests/mods/proving/` is one mod that uses every capability the engine has - **measured, see below** -
in GDScript, with a
JavaScript half (`proving_js`) covering the same ground through the bridge. It is the game the
end-to-end tests play, and it ships with nothing.

**Adding a capability means adding it here in the same commit**, and asserting it in
`tests/proving_test.gd`. That is not bookkeeping: until this existed the engine was tested through the
seven games bundled with it, so coverage was whatever the content happened to use - which is how 139
unbound JavaScript functions and 39 undocumented events went unnoticed for weeks.

Two rules that make it work:

- **Its coverage is measured, not asserted.** "Uses every capability" was a sentence in this file for
  weeks and was **wrong**: counted for the first time on 22 September 2026 it was 40 of 56
  `register_*`, with `register_biome`, `register_sound`, `register_structure` and `register_minigame`
  among the missing - not corners, but things games are made of. Nobody had lied; nobody had counted,
  exactly as the JavaScript bridge reached 139 of 262. It is 56 of 56 now, and
  `tests/mods/proving/uncovered.txt` is a ratchet that may only shrink, so a new `register_*` cannot
  land with nothing using it.
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

The sharper form of the rule, after it was broken again on 2026-09-22: **the registries are public and
get found; the readers behind them are private and get reimplemented.** `sources.gd` was walking loot
pools by hand and inventing flat percentages while `LootRegistry.chance_of` computed real ones - and
`api.loot_sources`, which calls it, was twenty lines above the function being written.

**That rule had been in this file since 19 September and was broken anyway**, so it is no longer only a
rule. Three things now stand behind it:

- **`docs/api/engine.html`** - the engine's own reference, generated beside the mod API's and grouped by
  the question being asked ("Drops, loot and rewards") rather than by folder, because `server/loot.gd`
  is not where anybody looks for "how likely is this drop". **Search it before writing a reader.** The
  natural experiment that justifies it: the mod API is indexed and has never been reimplemented; the
  engine internals had no index and have been reimplemented twice.
- **`engine/owned.txt`** - who reaches into a nested shape another file owns (`pools` and `entries`
  belong to `loot.gd`, `emitters` to `effect_registry.gd`, `drops` to `entity_registry.gd`). A ratchet
  like `unbound.txt`: the baseline may only shrink, and anything new fails the suite. Both known
  reimplementations began exactly this way.
- **A documentation floor on the twelve reader files.** They were the *worst*-covered files in the
  engine - `effect_registry.gd` at 3 of 9, `item_registry.gd` at 9 of 27 - which is backwards, because
  an undocumented function is not on the reference page at all, so a fruitless search reads as "there is
  no such thing" instead of "nobody wrote it down". Now 120 of 120, and the suite keeps it there.

Deliberately *not* done: documenting all 896 undocumented public functions under `engine/`. Most of them
are `net.gd`'s RPC endpoints, the two orchestrators and boilerplate like `to_network`, and writing that
up would bury the part that matters rather than surface it.

## Things that look safe and are not

- **A name in one shader constant that a different shader constant already uses.** The voxel shader is
  glued together from constants written a hundred lines apart (`LIT_TAPS`, `LIT_WATER`, `LIT_OUT`), so
  a local called `surface` in one and `uniform sampler2D surface` in another is invisible to anybody
  reading either. GLSL refuses it - and **Godot prints the error and then draws the surface with its
  default material, which is opaque white.** So the symptom is not a shader error, it is a lake that
  renders as a flat white sheet. Eight rounds of work went into the water's *look* before anybody
  read the client log. `_shader_names` in `tests/gameplay_test.gd` now fails on this. (2026-09-22)

  The general rule it leaves behind: **when an edit to a shader changes the picture not at all, the
  shader is not running.** "No visible effect" and "wrong value" are indistinguishable in a
  screenshot. Grep the client log for `SHADER ERROR` before the *second* experiment.
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

## Changing the mod API

**Adding a function is free. Changing one is not, and there is a policy.** `MOD_API_VERSION` is
`"1.0.0"` and has never moved; mods declare `"engine": "^1.0"` and the loader refuses anything outside
the range. The rule, which lives in `ModApi.DEPRECATED`:

- **Adding is a minor bump** (1.0 → 1.1). `^1.0` keeps working.
- **A function never changes its signature in place.** Add the new one, leave the old one calling it,
  and list it in `DEPRECATED`. A mod written a year ago keeps running, and its author is told once in
  the dev log which name to move to.
- **A deprecated name survives at least until the next major version**, and only a major bump removes
  it — which is the one action that stops every `^1.0` mod loading, and should be something we do
  roughly never.

The suite checks every name in `DEPRECATED` still exists and still warns, so one cannot be quietly
deleted, and the Proving Ground *uses* the deprecated names deliberately — exercising them is the only
thing that proves they still work, so a deprecation notice is the one warning it is allowed to produce.

Why this matters more than it looks: the loudest complaint about modding in this genre is that every
release rewrites the game's internals, so every mod must be rewritten too. Mods here call
`mod_api.gd` and never touch engine internals, so nothing *forces* that on anybody. The only way it
happens to us is if we do it to ourselves.

## Adding an RPC

**Append it at the end of `engine/net/net.gd`, and bump `Protocol.VERSION`.**

The bump is what actually protects anybody: a mismatch is refused at the door with a readable message,
which is the kind failure. Appending is free insurance on top, in case Godot's RPC method ids depend on
declaration order — **which is not verified.** It was asserted confidently on 2026-09-22 as the cause of
a client stuck on "Connecting to…", the bump was made on that basis, and the actual cause turned out to
be a leftover server process holding the port. The bump was still correct; the reasoning for it was
never tested. So: append because it costs nothing, not because we have proved it matters.

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

That writes **four** files. The Markdown pair is the source of truth (the user, 2026-09-22): a static
site generator will make the site's HTML from them, and unlike a 500KB HTML file they can be searched -
by a person or by a tool, which is the point of a reference nobody could navigate.

- `docs/api/mod-api.md` - the mod API. **Read this one**, not the HTML.
- `docs/api/engine.md` - the engine's own readers, grouped by the question they answer.
- `index.html` / `engine.html` - the same, as pages; kept because README and CONTRIBUTING link them.

Each entry is laid out the way the great vendor API libraries of the nineties laid out a page:
signature, then the Remarks the `##` comment carries,
then a **See Also** derived from what the function actually calls - following *through* private
helpers, because the useful link usually runs through one. `api.sources_of` lists `chance_of` for
exactly that reason, and not knowing `chance_of` existed is what caused the bug that started all this.
Run it after touching `engine/server/mod_api.gd`, any `## ` header comment listed in
`tools/docs_generator.gd`, `engine/server/js/quarrowen.d.ts`, or any doc comment in a reader file.

`engine/owned.txt` is generated separately, and only needs regenerating when something stops reaching
into a shape it does not own:

```sh
godot --headless --path . res://tools/mod_tool.tscn -- owned
```

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

**The games are deleted**, so a release from master would ship an engine with nothing to play. The
children have been told 1.0 will be a fresh game, and that is what a tag waits for. Push to master as
much as you like — that only runs tests.

The older reason — that the children were playing 0.41.1 and would be auto-updated into a protocol the
family server did not speak — **no longer applies**, and believing it made protocol bumps feel more
dangerous than they are. The user, 2026-09-22: *"kids are not playing quarrowen currently. they wont be
playing it till 1.0 is available... the only person running the built client is me on my own laptop."*

So `Protocol.VERSION` may be bumped freely for now; only a laptop build is affected and it is rebuilt.
It is at 50 through ordinary churn, and **resets to 1 when 1.0 is cut**, not before: freezing it early
would be actively harmful, because that number is the only thing that refuses a mismatched client at
the door. Freeze it while the wire still changes and two incompatible builds shake hands and then talk
past each other, which presents as an unexplained hang rather than as a version problem.

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
- **Do not name other companies' products anywhere in code, documentation, comments or commit
  messages.** Not as a compliment, not as shorthand for a genre, not in a commit saying we do not look
  like them. Say "the genre's best-known game", or describe the thing itself.

  **It is products, not just games.** Written as "games" until 22 September 2026, and the narrower
  wording is exactly how the next one got through: a documentation library was named repeatedly - in
  PROGRESS, in CLAUDE.md, in doc comments and in two commit messages - because it was not a game and
  so the rule appeared not to cover it. It does. Engines, modloaders, documentation sites, storefronts
  and tools are all somebody's product. "The great vendor API libraries of the nineties" says the same
  thing and names nobody. This was a standing instruction for
  weeks and was not written down here, so it was broken repeatedly on 21 September 2026 - in commit
  messages, in PROGRESS and in a mod's comments - while a look was being discussed and comparisons
  were the easiest thing to reach for. Writing it down is the fix.

  **The exception is the trademark notices**, which have to name a mark to disclaim it: LICENSE,
  README, `docs/faq.md`, the in-game about box and the release page. Those are the only places, and
  `tools/generate_icon.py` explaining what the icon deliberately is not.

## Where things are

- `engine/` - the engine. `client/`, `server/`, `shared/`, `net/`.
- `mods/` - bundled content. **`base` alone.** The seven games were deleted on 21 September 2026 and
  will be rebuilt for 1.0; `art/models/` keeps the models they used, which no script can regenerate.
- `tests/mods/proving/` - **the Proving Ground**, the game the tests play. Not shipped.
- `native/` - the Rust extension.
- `deploy/server/` - what the family server runs. Meant to be copied on its own, without the repository.
- `PROGRESS.md` - status, roadmap, playtest findings, and the decisions behind them. Read it first.
- `docs/` - hosting, modding, the engine, distribution, and the generated API reference.

## Parameter order, and where a default may not point

Two rules that came out of an afternoon of transpositions (2026-09-21):

- **Past two required arguments, take an options dictionary.** GDScript has no named arguments, so a
  third positional is a guess at the call site. The JavaScript API does this everywhere, which is why
  no JavaScript mod has ever hit one of these.
- **A common parameter goes in the same place in every sibling.** `realm_id` sits straight after the
  required arguments in all eight block functions; `set_block` was the exception and it was the one
  that got called wrong. Cross-type mistakes do fail loudly - GDScript names the file, the line and
  the mod, and aborts the call - so the cost is a confusing afternoon, not a silent bug. **Read the
  log before reading signatures.**

And since the games were deleted, **nothing may default to a game**. `--mods`, `--host` and the menu
backdrop all named `vanilla`, so a missing argument was reported as a missing mod - a message about
something nobody asked for. They now say what is actually missing, and the backdrop generates from
the first installed game or stays a still image. `base` cannot stand in: it is `"kind": "library"`
and registers no entities.
