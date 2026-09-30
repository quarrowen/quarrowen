# Site brief: the landing page, rebuilt for the host

Written 30 September 2026 from a review of quarrowen.com as a first-time visitor, and a conversation
with the user about who the site is for. This is the specification for rewriting
`site/landing/index.html` and for a sweep of stale player-facing docs. Where it gives copy, the copy is
a draft to keep the voice of, not a string that must survive word for word - but the *decisions* in
part 1 are settled and are not to be relitigated while implementing.

## 1. The decisions

**Who the page is for, in order.** Every section serves one of these, and the page takes them in this
order:

1. **The host** - somebody deciding whether to run a world for their people: family, friends, a
   group, a class. This is the reader the page must win. They bring their own players, so they are
   the one reader who gets value from Quarrowen with nobody else in the world using it yet.
2. **The invited player** - somebody who was sent the link by a host and told "we are playing
   tonight". Most visitors will arrive this way. They need: download, open, join. Nothing else.
3. **The curious builder** - "can I make things for this?" A teaser and a link to the modding docs.
4. **The writer** - a blogger or reviewer after the story and the facts.

**What the page is not.** It is not trying to win a gamer browsing for their next game. That reader
comes after 1.0, when there are servers worth joining. Nothing on the page should be written for them
at the expense of the host.

**The one idea, in the host's terms.** "Universal client" is our word and never appears on the page.
The player-facing version is: **the world you join brings the game with it - blocks, creatures, rules,
whole games - so nobody installs anything and nothing has to be kept in step.** The differentiator is
not "servers have different games" (every server scene in the genre already feels like that); it is
that a server here can add *real content* and the people joining still install nothing.

**Framing.** Quarrowen is for players and builders of all ages (CLAUDE.md, 28 September 2026). The
page does not say "for children", "a child joins" or "bedtime" anywhere. It began as something for one
family's children and their friends, and that is said **once, in the story section**, as the origin -
not as the audience. Safety features are presented as control for any host ("only people you allow"),
which a group of adults wants just as much.

**Firstlight is sold as a story game.** Fourteen acts, Wick, an ending. "Make it through the night"
describes the genre, not this game, and stops being its pitch.

## 2. Constraints of the build

- `tools/build_landing.py` refuses a placeholder nothing supplies **and** a value the template does not
  use. Any value removed from the template must also be removed from the `landing_values.json` block
  in `tools/make_release.sh`, and any new one added there.
- **Game cards come from `mod.json`** (`{{game_cards}}`, built in `make_release.sh` from each
  `kind: game` mod's `name` and `description`). So the new game copy goes into the mods' `mod.json`
  descriptions, not the template - which also means the in-game list says the same thing as the site.
  Keep that property; do not hand-write the game list into the template (the comment at that loop says
  why).
- `make_release.sh` copies `site/screenshots/*.jpg` to `shots/`. A video needs the same copy step for
  `*.mp4` / `*.webm` added beside it.
- Player-facing text follows the house style: plain, kind, never arch; British spelling; **no other
  company's product named** except in the trademark footer. That includes the page, the alt text and
  the meta description.

## 3. The page, section by section

### 3.1 Hero

Media: the **portal clip** (see 4.1), autoplaying, muted, looping, with `shots/hero.jpg` as its poster
and as the fallback. Until the clip exists, the poster alone - but it should be a new Realistic-preset
shot, not the current valley.

> **Run a world for your people.**
>
> Start a world and everyone you invite just clicks Join. The world brings the game with it - its
> blocks, creatures, rules, whole games - so there are no mod folders, no accounts, and nothing to keep
> in step between friends. Free, for Mac and Windows.

Buttons: `{{mac_url}}` Download for Mac, `{{win_cta}}`, and a ghost button **Host a world →**
(`#host`).

Directly under the buttons, for the invited reader - short, and the only instructions in the hero:

> **Sent here by a friend?** Download it, open it, and choose **Multiplayer**. Their world will be
> there, or they will give you a short code to type in.

`{{win_button}}` (the Windows *More info → Run anyway* note) and the Mac line ("signed and notarised,
keeps itself up to date") stay directly beneath - the invited reader is the one who needs them. Check
the Multiplayer wording against what the menu actually shows today (LAN tab, invite codes via a hub)
and say what is true.

Meta description: *"Run a world for your friends and family: they click Join and the game arrives with
it. Four games in one free download, for Mac and Windows."*

### 3.2 One app, every world

The idea, shown rather than argued. Three screenshots side by side (see 4.2), each captioned with the
world it came from, and one line under them:

> **Same app. Three worlds. Nothing installed in between.**
>
> Each world on a server can run a different game. Walk through a portal from a survival world into a
> fairground of short games, and the app becomes that game on the way through.

This section replaces "The server decides the game" and its six-card grid. The points from those cards
that still earn a place move to 3.4 (hosts) and 3.6 (builders).

### 3.3 What comes with it

`{{game_cards}}`, with a screenshot per game if the card layout allows it. New `mod.json`
descriptions:

- **Firstlight** (`mods/firstlight/mod.json`):
  *"A survival game with a story. Wake in a meadow beside Wick the lamplighter, who cannot fight, and
  follow the old lights down to what is under the world. Fourteen acts and an ending, and nothing is
  timed or can be failed."*
  Check every claim against `mods/firstlight/story.gd` and `acts.gd` before shipping it.
- **The Fairground**: keep the current description. It is the best one for a group evening, and the
  section intro should say so.
- **One Block**: *"One block over the void. Break it and something else takes its place - soil, then
  stone and ores, then creatures and crates - until what you are building is a factory."* (The
  roadmap calls it the factory on-ramp; say it.)
- **Creative**: keep.

Section intro:

> All four come in the download. Play one on your own, or run them side by side on a server and let
> your people walk between them.

### 3.4 Host a world (`id="host"`)

Two halves: why, then how.

**Why** - four short points, one line each, then a link:

- **Only the people you allow.** A world lets in the names on its list, and nobody else.
- **No accounts anywhere.** No sign-up, no email, no telemetry. A player is a key on their own
  computer.
- **The server sends data, never code.** There is no mod runtime in the app. What a server may send is
  checked and size-limited. *[Security →](/docs/security/)*
- **Your worlds are files on your machine.** Back them up, move them, keep them.

**How** - honest about what it takes:

> A spare Linux machine with Docker is enough. Three worlds and a hub, running side by side, in about
> ten minutes.

Then the existing `QW_IMAGE` / `QW_HUB_IMAGE` / `docker compose` block, then *[Hosting →](/docs/hosting/)*.

And one plain sentence about reach, because it is the first wall a host hits: players in the same house
find the server by themselves; players elsewhere need the host to open a port, or to put everybody on a
private network. (**Open decision for the user:** whether to name a specific mesh-VPN product here. The
house rule forbids naming products for comparison; this would be naming one as a recommendation. Ask.)

### 3.5 (removed) Mods in this release

The zip tables leave the landing page. They are for somebody adding a mod by hand, the in-game Mods
page already does that, and on the page they read as "these games are a few kilobytes". Replace
`{{mod_sections}}` with one line in 3.6: *"The mod files for this release are on the release page"*,
linking `https://github.com/quarrowen/quarrowen/releases/tag/v{{version}}`. Remove the `mod_sections`
value and the table-building loop's row output from `make_release.sh` (keep `game_cards`).

### 3.6 Make something

Short. A teaser, not the docs.

> **Anything a bundled game does, yours can do.** Blocks, creatures and their behaviour, world
> generation, machines, crafting, whole games - in GDScript, or in JavaScript that runs in a sandbox.
> Put it on your server and everyone gets it the next time they join.

A real snippet of about five lines from the JavaScript API that registers one block (take it from
`docs/modding.md` or the Proving Ground so it is known to work).

> **Written once, kept working.** Mods call the mod API and never the engine's insides, and the API
> only grows: a function never changes in place, and an old name keeps working until a major version.

*[Modding →](/docs/modding/)* · the release-page link from 3.5.

### 3.7 The story

Replaces "Built with Claude Code" and absorbs "Made for a family to play together".

> Quarrowen began as something for one family's children and their friends: a world they could all
> join without anybody sorting out files first. It grew from there.
>
> **Every line of it was written with Claude Code, from an empty folder** - the renderer and its Rust
> mesher, the server and its protocol, creature behaviour, the mod API and its sandbox, world
> generation, the tests and the tooling. No engine template and no asset packs: the textures, models
> and music are made by scripts. The decisions and the bugs are written down as they happen, in
> `PROGRESS.md`, and the bugs are mostly more interesting than the features.

(**Open decision for the user:** first person - "I built it for my children" - reads warmer to a
writer, but the repository has kept personal names out on purpose. The draft stays third person.)

Keep the licence sentence and the GitHub link.

### 3.8 At a glance (`id="facts"`)

Keep the table. Changes:

- **What it is**: *"A voxel game where the world you join brings the game with it, so nobody installs
  anything to join a friend. Four games in one free download: a survival game with a story, a
  fairground of short games, a creative world, and a single block over the void."*
- **Platforms**: say what the tablet build is (touch controls done, not released) rather than
  "iOS builds".
- **Made with**: the current row (and the current "Built with Claude Code" section) says *every sound*
  is generated by a script. `README.md` and `CREDITS.md` say the sound effects are Kenney's, under
  CC0. Say what is true - e.g. "textures, models and music are generated by scripts; sound effects are
  CC0 and credited" - because a writer who checks will find it.
- **Screenshots**: list every file in `shots/`, not a hard-coded two. If that wants a value from
  `make_release.sh`, add one.

### 3.9 Removed

- "Where to go" - its links now live in the sections they belong to (playing in the hero, hosting in
  3.4, modding in 3.6, FAQ in the footer).
- The `menu.jpg` screenshot. A menu is the least interesting thing the game can show.

Footer: the trademark notice unchanged, plus links to Playing, Hosting, Modding, FAQ, Security, Source.

## 4. Pictures

All taken with the project's own harness, interface hidden, on the **Realistic** preset
(`QW_GRAPHICS=realistic`, read by `engine/client/settings/client_settings.gd`). `tools/descent_shots.sh`
is the pattern to copy: a server per shot with the right mods, then `tests/screenshot.tscn` with
`--yaw`, `--pitch`, `--commands`, `--hud=0`. Output to `site/screenshots/` as JPG. Before trusting any
picture, grep the client log for `SHADER ERROR` - a surface drawn in opaque white is the known symptom.

### 4.1 The portal clip (the user records this; not the harness)

10-15 seconds, looped, muted. A player walks out of a Firstlight world at dusk, steps through a portal,
and arrives in the Fairground as a round of The Floor is Lava begins. One cut at most. Target under
4 MB as MP4 (H.264) with a WebM beside it, 1280 wide, and a poster frame saved as `hero.jpg`.

### 4.2 Stills, in priority order

1. **Firstlight** - Wick and the player in the meadow at golden hour, or a lamp being lit at dusk.
   Sells "a story", not "a block world".
2. **The Fairground** - several avatars mid-round, name tags visible. This is the "for a group" picture.
3. **One Block** - an island part way to a factory: machines, belts or cables sagging between poles.
4. **Water and light** - Realistic preset showing reflections and haze. The picture a writer uses.
5. **A group of avatars together** in any world, for 3.4.

## 5. Stale docs to fix in the same change

A writer who clicks through will find these in two clicks, and they contradict the page:

- `README.md` line 5 - "A sandbox, an island to survive on, a story to play through": name the games
  that ship. Line 8 - the family line moves to match 3.7. The download link says Mac only; Windows
  exists.
- `docs/faq.md` - line 8 "an island puzzle or a story"; "Is it safe for children?" (29-43) becomes "Is
  it safe to join someone's server?" and "Who can join my world?" without the age framing; line 39
  "an eight-year-old at bedtime" goes; "Can my children play together?" (45-49) becomes "Can my
  friends and family play together?" and names the worlds that actually ship. The FAQ's own note about
  Hearthhold (84-86) can go once the rest is true.
- `docs/playing.md` line 108 - the Hearthhold commands (`/charter`, `/valley`, `/bramble`). Replace
  with Firstlight's, if it has any.
- `docs/hosting.md` - **the largest.** It still walks through `hearthhold`, `skyblock`, `vanilla`,
  `arcana`, `industry` and `guild` (lines 4, 73-95, 171-205, 244-271). `deploy/server/compose.yaml`
  runs `firstlight`, `oneblock`, `fairground` and a hub; the guide should describe exactly that.
- `grep -rn -i "hearthhold" docs/*.md README.md` for the rest (`modding.md`, `engine.md`, `loot.md`,
  `distribution.md`). Historical references in design notes can stay; anything that tells a reader
  what to type or what they will see must be true.

## 6. Write the decision down

Add to CLAUDE.md, under House style, so the next session writing player-facing text does not drift
back:

> **The site is written for the host first.** quarrowen.com speaks, in order, to somebody deciding
> whether to run a world for their people, to a player a host has invited, to somebody curious about
> building for it, and to a writer (the user, 30 September 2026; the reasoning is in
> `docs/site-brief.md`). "Universal client" is our term, not a player's: on the page it is "the world
> you join brings the game with it". Firstlight is described as a story game.

## 7. Done means

- The hero has the two download buttons, **Host a world**, and the "Sent here by a friend?" line.
- No mod zip tables, no `docker` block outside 3.4, and no `menu.jpg` on the landing page.
- `grep -i -E "child|bedtime|eight-year" site/landing/index.html` finds nothing.
- `grep -i "hearthhold" README.md docs/faq.md docs/playing.md docs/hosting.md` finds nothing that tells
  a reader what to do or see.
- Firstlight's `mod.json` description is the story pitch, and the claims in it are true of the mod.
- `tools/build_landing.py` merges with no missing or unused values.
- Nothing on the page says every sound is generated.
- At least three new Realistic-preset screenshots in `site/screenshots/`, none showing a white
  surface, and the facts table lists them all.
- The page reads correctly at phone width.
- CLAUDE.md carries the paragraph from part 6.

## 8. Not in this change, and worth deciding

- **A public showcase server** with a Join button on the page, so a reader who knows no host can see
  the idea for themselves. The strongest single thing for writers; it needs a machine and a decision.
- **Port forwarding** is the first wall a non-technical host hits. Nothing here fixes it.
- **Windows code signing**, so the *Run anyway* instruction can go.
- **A real playthrough of Firstlight by a person** before the page promises fourteen acts to strangers.
  The friends' test is the natural place for it.

