# What the engine still needs

Quarrowen's rule is that **the engine provides capabilities and mods provide content**. This is the list
of capabilities it does not have yet, in the order that unlocks the most.

It comes from working backwards: taking the things people build on top of voxel games — the machines,
the magic, the economies, the dungeons, the storage systems — and asking not "how would we write that"
but **"what could our engine not express, that whoever built it had to reach past the game to do?"**
About a hundred such things collapse into twenty-three answers, because most of them are different
content over the same few gaps.

**The test each of these has to pass**: could two mods build genuinely *different* things on it, or
does it bake one game's answer into the engine? A capability is a mechanism — the engine propagates,
stores, detects and notifies; the mod decides what any of it means. Where something below still fails
that test, it says so rather than pretending.

Names, recipes, balance and voice are ours throughout. What is taken from the genre is *what a player can
do*, never what somebody else called it — the engine keeps plain descriptive names for its capabilities
(`signals`, `dimensions`, `networks`) and the mods name their own materials. Quarrowen is an independent
project and stays one.

## Where we are

169 mod API functions. Already built: graves, roles and permissions, travel between worlds, cosmetics, a
guidebook, tutorials, milestones, loot tables, structures as data, worlds a mod can ship, crafting
minigames and forging, containers and stations, recipe discovery, held-use charging, ambience,
server-chosen music, weather, a map with markers, "what am I looking at", UGC moderation, and a hub.

Twelve biomes, seventy-five blocks, eleven creatures, a boss, four games.

## The capabilities

### 1. Dimensions

Separate worlds with their own generator, chunk storage and rules, reached through a portal, with
entities and items crossing between them. About a quarter of everything below assumes this exists, and it
changes the save format, so it wants doing early rather than bolted on.

The two the bundled game wants: **the Emberdeep**, hot and dark and under everything, and **the Hush**, a
still strange place at the edge of the map.

### 2. Networks

One capability, stated once: **a quantity that moves between blocks along a network**. Power, items,
fluids and magic are the same problem with different units, so a mod declares its unit and the engine
never learns what electricity is.

If only one thing after dimensions gets built, it is this. It is the foundation of every machine, every
pipe, every storage system and every mana pool anyone will ever want to write here.

**Two kinds of network, and the second was nearly missed.** "A quantity that moves" assumes something
*stored and conserved* — it buffers, fills and runs out. Mechanical power is not that shape. Rotation is
a speed and a twist; it arrives the instant the shaft turns, nothing accumulates in the gearbox, and a
network with two sources fights rather than adds.

Both are wanted (the user, 2026-09-19: gears, shafts, windmills). So `networks` carries two kinds:

- **Stored** — a quantity with a capacity, which fills, drains and can run out. Power, items, fluids, mana.
- **Driven** — a value propagated from a source through everything connected, with no buffer anywhere.
  Speed and direction, resolved each tick, and conflicting sources are an error a mod is told about
  rather than an average the engine invents.

**And a second way of being connected: links.** Everything above assumes a thing is joined to the six
blocks touching it, which is how dust on a floor works and how signals were built. It is the least
interesting way to wire anything, and it makes every machine sit in a paved trench.

A **link** joins two connector blocks *directly*, whatever lies between them, with a cable drawn across
the gap - sagging, because the sag is most of why a strung cable looks like a cable. The quantity jumps
the link rather than walking the cells.

This belongs here and not with signals (the user, 2026-09-19: *"why not make it look like an actual
wire... why does it need to stick to a block or surface?"*). Power, fluids, items and rotation all want
"these two are joined" without paving the ground between them, so building it once for wires and again
for pipes would be building it twice. Adjacency stays for the cheap early thing a child lays along the
floor; links are what a base looks like once it is a base.

**The rules, decided with the user before it is built** (2026-09-19):

- **A limit on how far apart two connectors may be** - of the order of 8 to 14 blocks, a server
  setting, with a pole or relay needed to go further. Two things at once: it stops a player stringing a
  cable across a continent, and it keeps the **sag** believable, because a catenary over a hundred
  blocks either dips into the ground or is drawn as a straight line and stops looking like a cable.
- **The span has to be clear air.** A cable that clips through a floor or a hillside looks broken, and
  worse, it lets a player run power through a wall as if the wall were not there. So the line is
  checked when the link is made and refused if anything solid is in the way.
- **And it stays clear.** A block placed into an existing span breaks the link and drops the cable, for
  the same reason: the alternative is a cable quietly passing through a wall somebody built later.
  Announced to whoever placed the block, because a link failing silently is a bug report.

What it also needs that nothing here has yet: links saved with the world, broken when either end is
mined, a cap on how many one connector may carry, and a client that can draw a sagging curve between
two arbitrary points - which it currently cannot do at all.

### 3. Signals

A block can emit a level, a block can declare itself able to carry one, and a block can be told when the
level reaching it changes. That is the whole capability, and it is deliberately less than it first
looked: **gates, delays, inverters and latches are blocks a mod writes**, each one reading its
neighbours and emitting accordingly. An engine that ships an AND gate has decided what logic looks like,
which is not its business.

In the bundled game the material is **quickdust**, laid in lines and gathered from **quickstone**, and a
block carrying a signal is *quickened*. (Quick in the old sense: alive.) Another mod's wiring can look
nothing like it.

**Built, and adjacency-only.** A level spreads to the six blocks touching a cell, so quickdust is laid
along a surface. That is the cheap thing worth having early, and it is not the interesting one: a
strung cable between two connectors wants **links** (see capability 2), which signals will use as soon
as they exist rather than growing a second kind of wiring of its own.

### 4. Keeping the world awake

An area that keeps ticking when nobody is standing in it. Small, and not optional once machines exist:
a pump in a far-off place feeding a tank back at the base is the ordinary case, and it is one of the
things that **cannot** be caught up afterwards, because what it did depended on the rest of the world
while it was doing it.

It is small only as an API — a claim on some chunks, by a mod or by a block a player placed. What it
costs is the whole of "How much of the world is running" below, and that section is where the rules
for it are, because a claim that the engine always honours is a claim that one player can use to stop
the server. Note especially that a claim is needed at the end that *decides* something, not along the
whole pipeline: filling a buffer in a sleeping chunk is free.

**Moved here from eleventh place** (19 September 2026) after the user asked what happens to a pump in
another dimension feeding a tank at their base. The honest answer was that it stops — and a machine
that only runs while you stand beside it is most of the point of building it gone. So this belongs
with networks rather than long after them: the two capabilities are only half a feature apart.

### 5. Item modifiers

Named modifiers on an item that change its stats and hook events, applied at a station and readable in
the tooltip. Items already carry data, quality and stats, so this is an extension rather than a new
system.

### 6. Flowing liquids

Water and lava exist as blocks and sit exactly where they are put. They do not spread, do not fall, do
not fill a hollow, and do not meet each other. That absence is larger than it sounds: **a bucket is not
worth carrying** if what comes out of it cannot go anywhere, a cave cannot flood, a moat is a row of
still squares, and the stone that forms where lava meets water — the obvious black glassy block a player
expects to find and mine — has no way to exist.

A block-level flow, with a source, a level that decreases with distance, and a rule for what happens
where two liquids meet. It is the last purely-vanilla system missing, and it is the reason to do it
before the industrial half rather than after.

### 7. Fluids in containers

A fluid as a quantity that can sit in a tank and travel a network — which is a different problem from
the one above, and neither gives you the other. A tank does not spread; a puddle does not pipe.

### 8. Multiblocks

Recognise a shape a player has assembled and treat it as one machine with one inventory and one
controller. Structure templates already describe shapes for world generation; this is noticing one that
somebody built by hand.

### 9. Creature abilities

Data-driven fights: phases, timed abilities, summons, area effects, telegraphs. The AI presets and
attacks exist; what is missing is a mod scripting a fight without writing a brain.

### 10. Characters

People who stand somewhere, have a name and a face, hold a conversation and offer something. Bramble is
one, written by hand; this makes her a capability so a mod can have a hundred.

### 11. Objectives

Steps, conditions and rewards, given and tracked. Tutorials teach and milestones commemorate; this is
neither, and a mod should be able to hang a story, a daily errand or a contract on the same frame.

### 12. Experience

A number that goes up when a player does a thing, with thresholds a mod reads. What counts, what the
levels mean and whether they unlock anything at all is the mod's business — the engine counts and
remembers.

### 13. Balances

A named quantity a player owns, that mods can read and change without agreeing on what it is. Coins,
reputation, contribution, a guild's standing: the engine stores a number against a player and a name,
and never learns that one of them is money.

### 14. Claims

An area with an owner and permissions, which the engine consults before an edit. What may be claimed,
how much, and what it costs are the mod's.

### 15. Companies

Groups of players that other things can be owned by — a claim, a balance, a base. Deliberately separate
from claims: plenty of servers want one without the other.

### 16. Applied effects

Food already applies timed modifiers to any stat. This generalises it to anything that can apply an
effect to anybody, and gives mods a station to brew them at.

### 17. Companions

A creature that follows, is owned, takes instruction and is still there tomorrow.

### 18. Vehicles

Rideable entities that carry a player and change how they move.

### 19. Area tools

Placing or breaking many blocks at once with a preview, respecting permissions and the edit budget.
Mining a whole vein is the same capability with a different rule for choosing the blocks.

### 20. Text in the world

Words that float where a thing is, numbers that fly off a hit, mod-defined corners of the interface, and
a way to put a live value inside a piece of text.

### 21. Inventories inside things

An item that contains an inventory, and a container that is the same container wherever you open it.

### 22. Moving assemblies

A group of blocks that leaves the grid and becomes one moving thing — a platform on a track, a drawbridge
swinging, a windmill's sails, a whole contraption a player built and set going — then sets back down and
becomes blocks again.

**This is the hardest capability on the page**, and it is here because the mechanical half is wanted
properly rather than as decoration. A voxel world is a grid, and this is the one thing that asks it not
to be: the assembly needs its own position and rotation, its own collision, a player able to stand on it
and be carried, and blocks that keep working while they are off the grid. Nothing else on this list
fights the engine's basic shape in that way.

It wants `networks` (driven kind) and `multiblocks` first, since it is what those two are *for*.

### 23. Instances

A private copy of a space, entered and left. Much cheaper once dimensions exist, being a dimension with
a lifetime.

## Touch controls, and the iPad

Wanted for 1.0 (the user, 2026-09-19). An iOS build today would install and be unplayable: everything
assumes a mouse, a keyboard and a captured pointer. What it needs is a control scheme rather than a
port - a thumbstick, a look area, tap-to-break and hold-to-place, a reachable hotbar, and inventory
screens that work with a finger rather than a hover.

Order: touch controls first, then a local build, then TestFlight, then CI. Nothing about it is blocked
by anything else on this page, and it is the only item here that would put the game in a child's hands
somewhere other than a desk.

## How much of the world is running

The other standing concern, and the one dimensions makes urgent (the user, 19 September 2026: *"Might
not be needed for all realms to tick all the time... Otherwise a lot of machines by a bunch of players
in their bases can overwhelm servers"*).

Today the server ticks one world, and everything in it that is loaded. That is affordable because there
is one world, loaded means *near a player*, and the only things in it that move are creatures and a few
crops. Three items on this page change all three of those at once: **dimensions** multiplies the worlds,
**networks** fills them with machines that tick whether or not anyone is watching, and **keeping the
world awake** is a player asking for the machines to keep going after they leave. The family server is
a homelab box, so this is not a theoretical budget.

Four rules, settled before the rest is built, because the ticking model shapes how each one is written.
The first two are in the engine already; what is built is listed at the end of this section.

**1. A realm with nobody in it does not tick at all.** Not cheaply — not at all. Its clock keeps
running, and when somebody arrives its blocks are handed the ticks they missed, which is the mechanism
`block_ticks` already uses for a chunk that was unloaded and came back (`MAX_CATCH_UP`, so crops grow
while nobody is near). Applying it one level up means an empty Hush costs the server nothing, and the
cost of *having* a dimension is close to zero until someone goes there. This is what makes it safe for
a mod to register five realms.

Catch-up is bounded, and that bound is a design statement rather than an optimisation: returning to a
realm after a week must not produce a week of simulation in one tick. A block that has been asleep is
told **how long**, not given that many ticks, and a mod that wants a week of growth computes it.

**1a. Catch-up is not a substitute for running, and knowing which is which is the whole game.** The
user's case, and it is the right one to test the model against (19 September 2026): *a lava pump in a
remote place, sending what it draws to a tank back at the base*.

Crops can be caught up because **what they do is a function of elapsed time and nothing else** — an
hour asleep is twelve stages of wheat, and the answer is the same whether it was computed as it went or
all at once at the end. A pump is not that. What it does depends on whether the tank was full, whether
somebody cut the pipe, and what else was drawing from the network while it ran. There is no sum that
gives the right answer afterwards. **It either runs or it did not happen.**

So a block falls into one of three kinds, and the mod says which:

- **Catches up** — time is the only input. Crops, decay, a fire burning down. Sleeps freely.
- **Resumes** — sleeping loses nothing worth recovering. A spawner, an ambient effect. Sleeps freely.
- **Must run** — the outcome depends on things outside its own chunk. Pumps, sorters, anything feeding
  a network. This one **cannot sleep correctly**, so it has to be kept awake (capability 4) and that
  costs budget (rule 3). That is the honest price, and the player pays it knowingly rather than
  discovering their base quietly stopped.

The `catch_up` option on `register_block_tick` already distinguishes the first two. The third is new
with claims, and a mod that marks everything "must run" is a mod that spends its player's whole budget.

**1b. Delivering into a sleeping chunk is free, because storage is data and not simulation.** The tank
at the base does not need to be running to be filled — the pump is running, and a stored network's job
is to move a quantity into a buffer, which is a number in block data whether anyone is watching or not.
The consequence is the useful one: the player claims **the pump**, not the whole pipeline, and not the
base they are standing in anyway. The same is true across realms, which is what "wirelessly to a tank
in my base" needs — a network may span realms, and only the end that has to *decide* something needs
to be awake.

Driven networks (rotation) are the opposite and it is worth saying so: nothing is stored, so a driven
network that is asleep is simply stopped. A windmill somebody left running in the Hush stops turning
when they leave unless it is claimed, and the roadmap prefers that to pretending.

**2. Simulation distance is not view distance.** They were one number (`VIEW_RADIUS`, 8) answering two
questions: how far can a player *see*, and how far does the world *run*. Seeing costs bandwidth,
running costs the tick, so they are two settings now, simulation defaulting below view — a server owner
who is short of CPU and one who is short of upstream can each turn down the right one.

**3. A chunk kept awake costs somebody a budget.** This is the one that matters, and the answer is
deliberately not a count of chunks. Two force-loaded chunks holding a large sorting machine cost more
than twenty holding a field, so a limit of "four chunks each" is generous to the player causing the
problem and mean to everyone else. Instead the engine **measures what each claim costs in tick time**
and spends a budget the server owner sets.

When the budget is exceeded, the engine sheds — and *which* claim stops is the real decision:

- **Most expensive claim first**, not oldest and not newest. One runaway machine should stop before ten
  modest ones, and the player who built the expensive thing is the one who can fix it.
- **The player is told**, plainly and by name of place: their claim is paused, and why. A world that
  silently stops working is a bug report; a world that says "your workshop is asleep, it was doing too
  much" is a game telling a child something true.
- **Nothing is deleted, ever.** Shedding pauses; the blocks and their contents stay exactly as they
  were. The engine does not get to destroy what a player built because it was slow.

**4. The tick is time-sliced across realms, not divided between them.** With several realms occupied,
each gets a slice of a per-tick simulation budget and a realm that does not finish resumes where it
stopped — the pattern `_drain_save_queue(SAVE_BUDGET_USEC)` already uses for saving. Dividing the tick
evenly instead would mean the realm with one player in it and the realm with eight both getting half,
and a busy realm juddering to protect an idle one.

What this is deliberately *not*: no automatic difficulty on machines, no per-player entity tax, no
naming and shaming of whoever is slowest in chat. The server owner sets a budget, the engine keeps to
it and says what it did.

**Instrument before tuning.** Every number above — the default simulation distance, the budget, the
catch-up bound — is a guess until the server can say where its tick actually goes. It already records
sections per tick (`dev_tools.record`); what is missing is the same breakdown **per realm and per
claim**, which is the first thing to build when this work starts and the cheapest.

**Built so far** (19 September 2026): rules 1 and 2. A realm with nobody in it does nothing;
`view_distance` and `simulation_distance` are separate host settings (`QW_VIEW_DISTANCE`,
`QW_SIMULATION_DISTANCE`, 8 and 6); and a block outside the simulated set sleeps rather than stops —
its chunk keeps the clock and hands it the missed ticks on waking, with the true `elapsed` beside the
capped count. Rules 3 and 4 wait on claims and on more than one occupied realm respectively.

## Sending less, before sending it differently

A standing concern rather than a capability: the server streams a great deal — terrain, assets,
entity snapshots — and lag is the thing a child feels first.

**The transport is already reasonable.** ENet over UDP with DTLS, with three channels delivered
independently, so a burst of terrain does not hold up chat or block changes behind it, and movement is
unreliable-ordered on its own channel because a stale position is worth nothing. That is most of what a
modern transport would buy.

**All four of these are 1.0 work** (agreed 19 September 2026), in this order:

1. **Instrument it.** Bytes per second by message kind, and how long a join actually takes. Everything
   below is guesswork until this exists, and it is the cheapest item here.
2. ~~**Fix what is on the wrong channel.**~~ Done the day it was noticed: `s_asset_piece` was on the
   default channel, where everything small and urgent lives, so the join burst competed with chat, block
   changes and UI. One line.
3. **Compress chunk payloads.** Terrain is highly repetitive and is currently sent raw.
4. **Interest management.** Send what is near a player rather than what exists — of the four, the one
   that changes the shape of the problem rather than trimming it. It is also what makes a busy server
   possible at all, and it will want care: the rule for *what is near* has to answer for entities,
   block changes, sounds and effects, each of which has a different idea of how far away is too far.

Today's lazy asset lane was this kind of win already, and took megabytes out of the join path outright.

**QUIC: decided against** (19 September 2026), rather than deferred. ENet already gives independent
channels, which is the main thing it would buy; DTLS covers the encryption; and the remaining benefit —
better congestion control — is second-order. Against that, Godot's multiplayer sits on `ENetMultiplayerPeer`,
so it means writing a `MultiplayerPeer` of our own: feasible, since the good QUIC libraries are Rust and
there is already a Rust extension here, but a deep change to the one part of the system that currently
works.

The condition for reopening it is specific: **the instrumentation in item 1 showing the transport itself
is the bottleneck**, rather than what is being put through it. Nobody should revisit this on a hunch.

## The content that matters most: what is in the ground

Three ores and two metals is not a survival game. Today: coal, iron and cobalt, plus arcana's mana
crystal — so every tool tree ends at the same place and there is nothing to find at depth that changes
what you can make.

This is **content, not capability**: `add_ore_pass` already places ore by depth, biome and rarity, and
`register_material` already makes a metal into a full set of tools and armour. Nothing in the engine is
in the way. But it is the single biggest thing between the survival game and the depth a child expects,
so it belongs on this page even though no engine work is needed.

What it wants, roughly, and this is a design job rather than a list to copy:

- **A common metal** shallow and everywhere, for the things you make a lot of — wire, pipes, fittings.
  Copper is the obvious one and is a real material with no baggage.
- **A soft precious metal** for decoration and for things that conduct — gold.
- **A hard gem tier** below iron, for the tools you keep. Diamond is a real stone; the name is free.
- **The signal material** — **quickstone**, which capability 3 already needs, found deep and in quantity.
- **Deep variants** of the common ores, so mining *down* is a different activity from mining *along*.
- **The black glass** where lava meets water: unbreakable by ordinary tools, the gate to the Emberdeep,
  and impossible until liquids flow (capability 6). It is the clearest example of why that capability
  comes before the industrial half.

Ores are also where the engine's rules are load-bearing rather than decorative: **saves store block
names, not ids**, so adding a dozen ores to the middle of the registry cannot corrupt an existing world.
That habit was kept for exactly this.

## Content the engine is already ready for

Worth saying plainly, so nobody builds engine support for something that needs none. All of this is
buildable today by anyone, with no engine change at all:

decoration blocks of every kind, carved and coloured variants, ore types and world features, lights and
lamps, chests and furnaces of larger sizes, item magnets and collectors, bins that destroy what is put
in them, faster leaf decay, a block that plays music, teleport stones between places you have visited,
custom menus, permission tiers, and a looking-glass that names what you are pointing at.

The one decoration idea that is *not* content is textures that join up across neighbouring blocks, which
is a rendering capability.

**Seasons belong here too**, which was not obvious. They were on the capability list until the question
was asked properly: a mod already has persistent storage, the world clock, and an event for everything
that happens in it. A long cycle that crops and creatures read is a number a mod keeps and publishes —
no engine change. What is genuinely missing is **weather**, and that is listed on its own below.

## The games and mods to build

Ten, rather than the sprawl this could become:

| Mod | What it is |
|---|---|
| `base` | blocks, tools, crafting — exists |
| `vanilla` | the survival game — exists, and grows to the genre's full depth |
| `deep` | the Emberdeep and the Hush |
| `machines` | power, pipes, automation, storage networks |
| `arcana` | magic: mana, spells, rituals — exists |
| `guild` | economy, objectives, characters, trade — exists |
| `frontier` | claims, companies, waystones |
| `kitchen` | farming, food, bees, orchards |
| `build` | decoration and building tools |
| `hearthhold` | the story game — exists |

## Order

Decided 19 September 2026. The reasoning matters more than the list, because the list will change.

1. **Weather.** Small, visible, blocked by nothing, and absent entirely. Rain over the valley is
   something a player notices the same afternoon. A good thing to do before a long careful piece.
2. **Dimensions.** Before anything else structural, because it is the one change to the *data model*:
   every capability built after it can be dimension-aware from the start, and every capability built
   before it has to be retrofitted. ("Do networks cross worlds?" is a question best answered while
   writing networks, not afterwards.) It breaks the save format, which is free until 1.0.0 — so it gets
   done properly rather than bolted onto a shape that cannot hold it.
3. **Signals.** Small, needed for the survival game on its own account, and machines feel dead without
   it. Touches no saved format.
4. **Networks**, stored kind. The big unlock: around thirty of the things studied are this plus content.
5. **Keeping the world awake.** Immediately after networks rather than with the social half, where it
   used to sit: the first machine anybody builds out of sight of their base stops the moment they walk
   away, and there is no catching it up afterwards. Small, and it makes the previous item real.
6. **Fluids**, which ride on networks and are half of what machines move.
7. **Multiblocks.** Turns `machines` from a demonstration into a game.
8. **Networks**, driven kind, then **moving assemblies**. The mechanical family, left until last of the
   structural work because assemblies are the hardest thing on this page and want the other two behind
   them.
9. **Item modifiers** and **applied effects** — the depth pass on gear and potions.
10. **The social half**: objectives, experience, balances, claims, companies.
    Depends on none of the above and can be taken whenever it is wanted. It is what a *server* needs
    rather than what a *world* needs, and each piece is small.

Everything else — characters, creature abilities, companions, vehicles, area tools, text in the world,
nested inventories, instances — is independent and can be picked up when a game actually needs it,
which is the honest test of whether a capability is worth building.
