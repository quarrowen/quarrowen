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

**Seventeen of the twenty-three capabilities below are built** (20 September 2026). Each one is marked
where it appears, so this page stays a list of what is *left* rather than a record of what was wanted.

Before all that: graves, roles and permissions, travel between servers, cosmetics, a guidebook,
tutorials, milestones, loot tables, structures as data, worlds a mod can ship, crafting minigames and
forging, containers and stations, recipe discovery, held-use charging, ambience, server-chosen music,
weather, a map with markers, "what am I looking at", UGC moderation, and a hub.

Twelve biomes, eighty blocks, eleven creatures, a boss, four games.

### What is left, shortest honest answer

- **Six capabilities**: creature abilities, **characters**, applied effects, companions, vehicles,
  instances, and the three small ones (area tools, text in the world, nested inventories).
- **Three known limits** in things that *are* built - see "Where the built things stop" below.
- **Content**, which is not capability: ores worth digging for, creature voices, a reason to build a
  factory, Hearthhold's second phase.
- **Four things for 1.0**: touch controls, instrumenting the network, compressing chunks, interest
  management.

## The capabilities

### 1. Dimensions — built

Separate worlds with their own generator, chunk storage and rules, reached through a portal, with
entities and items crossing between them. About a quarter of everything below assumes this exists, and it
changes the save format, so it wants doing early rather than bolted on.

The two the bundled game wants: **the Emberdeep**, hot and dark and under everything, and **the Hush**, a
still strange place at the edge of the map.

### 2. Networks — built (all three layers)

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

**A link has a *kind*, and the kind decides almost everything.** A mod declares a kind - "cable",
"pipe", "beam" - and with it: what it is drawn as, how far it may reach, what it costs to lay, whether
it needs clear air, and whether it may leave the world it is in. The engine holds links and knows none
of that, which is what keeps it from deciding that everything is a wire.

The three kinds already known to be wanted, and they are not variations of one:

- **Cables sag.** Electricity strung between poles, a catenary, and the sag is most of why it reads as
  a cable at all.
- **Pipes do not.** A fluid line is rigid; drawn with the same droop it would look broken. Which also
  means a pipe wants a *shorter* maximum span than a cable, because a long rigid tube hanging in air
  looks wrong in a way a long cable does not.
- **Wireless has nothing to draw.** Whether it is allowed at all is the mod's business, and so is its
  range - which is not a constant but something a mod may raise with an upgrade, so the engine asks
  rather than stores it.

**Only wireless may leave the world it is in** (the user, 2026-09-19). A cable or a pipe joins two
places in one realm, full stop: a physical thing cannot run through the gap between worlds, and
pretending otherwise makes nonsense of what a portal is for. A wireless link may cross, if the mod
that owns it says so - which is what lets a quarry in the Emberdeep report back to a base in the
overworld without anybody laying a cable through a portal.

That makes a link's endpoints **(realm, position, face)** rather than just a position - and cross-realm
is the one case where the two realms differ.

**The rules, decided with the user before it is built** (2026-09-19):

- **A node is a *face* of a block, not the block.** A machine takes power on one side and pushes items
  out of another, which is how anybody actually builds a factory; one node per block cannot say that.
  It costs more to store and is harder to undo later, which is why it is decided now.
- **Laying a link costs the item it is made of**, by length. A long run is then a decision rather than
  a formality, relays are earned rather than imposed, and copper has a job.
- **A limit on how far apart two connectors may be** - of the order of 8 to 14 blocks for a cable and
  shorter for a pipe, per kind and settable by the host, with a pole or relay needed to go further. Two things at once: it stops a player stringing a
  cable across a continent, and it keeps the **sag** believable, because a catenary over a hundred
  blocks either dips into the ground or is drawn as a straight line and stops looking like a cable.
- **The span has to be clear air.** A cable that clips through a floor or a hillside looks broken, and
  worse, it lets a player run power through a wall as if the wall were not there. So the line is
  checked when the link is made and refused if anything solid is in the way.
- **And it stays clear.** A block placed into an existing span breaks the link and drops the cable, for
  the same reason: the alternative is a cable quietly passing through a wall somebody built later.
  Announced to whoever placed the block, because a link failing silently is a bug report.

- **What a machine does when the network cannot supply it is the mod's business.** Stop dead, or run
  slower, or run badly - the engine says "you asked for twenty and you have seven" and has no opinion
  about what that means. A lamp and a smelter should not have to agree.

What it also needs that nothing here has yet: links saved with the world - they are a record of where
somebody *chose* to run a cable and cannot be re-derived from the blocks the way a signal level can -
broken when either end is mined, a cap on how many one connector may carry, and a client that can draw
a sagging curve between two arbitrary points, which it currently cannot do at all.

### 3. Signals — built

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

### 4. Keeping the world awake — built

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

### 5. Item modifiers — built

Named modifiers on an item that change its stats and hook events, applied at a station and readable in
the tooltip. Items already carry data, quality and stats, so this is an extension rather than a new
system.

### 6. Flowing liquids — built

Water and lava exist as blocks and sit exactly where they are put. They do not spread, do not fall, do
not fill a hollow, and do not meet each other. That absence is larger than it sounds: **a bucket is not
worth carrying** if what comes out of it cannot go anywhere, a cave cannot flood, a moat is a row of
still squares, and the stone that forms where lava meets water — the obvious black glassy block a player
expects to find and mine — has no way to exist.

A block-level flow, with a source, a level that decreases with distance, and a rule for what happens
where two liquids meet. It is the last purely-vanilla system missing, and it is the reason to do it
before the industrial half rather than after.

### 7. Fluids in containers — built

A fluid as a quantity that can sit in a tank and travel a network — which is a different problem from
the one above, and neither gives you the other. A tank does not spread; a puddle does not pipe.

### 8. Multiblocks — built

Recognise a shape a player has assembled and treat it as one machine with one inventory and one
controller. Structure templates already describe shapes for world generation; this is noticing one that
somebody built by hand.

### 9. Creature abilities — built

**This entry was badly out of date.** Phases (`ai.phases`, gated on health, changing speed, aggression
and the attack list), boss bars (`ai.boss`), summons, explode, charge, leap, slam and a wind-up
telegraph on every attack all existed already. What was genuinely missing was one thing: an attack
could not **apply a condition**, which was not possible until conditions were built the same day.

So a spider that poisons and a boss that slows you are now data - `"condition": {"condition":
"vanilla:poison", "seconds": 8, "chance": 0.5}` on any attack - where before they meant a mod catching
`entity_damage` and reaching for the victim itself. Ranged attacks carry it on the projectile, because
by the time an arrow lands the mob may be dead or shooting at somebody else.

The remainder - **lingering areas** - was built straight after as `fields.gd`, and `"lingers"` on an
attack is how a slam leaves a pool burning where it landed.

### 9a. Fields — built

Ground that does something to whoever stands in it, for a while. Not on the original list and needed
the moment creature abilities were finished: a slam hurts what is near it at that instant, and a pool
of fire left burning had nowhere to live. Useful well beyond fights - a campfire's warmth, gas from a
cracked pipe, a healing circle in a village.

Always visible: placing one starts a running effect and letting it go stops it, because an invisible
thing on the floor that hurts a child is not a hazard but a trick. Each field keeps its own next-tick
time, so forty campfires cost forty radius searches a second between them rather than forty a frame.

### 10. Characters — built

People who stand somewhere, have a name and a face, hold a conversation and offer something. A character
is a name, a colour and lines with options; the engine draws every one of them the same way, so a child
who has learned to talk to one has learned to talk to all. `goes_to` moves along, `does` hands anything
at all to the mod, and two shortcuts cover what characters are overwhelmingly for: `gives` hands over an
objective, `sells` opens a shop. Bramble was rewritten on top of it and her hand-built panel is gone.

### 10a. Shops — built

Not on the original list, and needed the moment characters existed: a village stall, a pedlar, a vending
block. Prices are paid out of a ledger, or in goods, or both, so a game with no money barters; `sells`
turns an offer round and the player is paid. The half that matters is **stock** - a shop with unlimited
everything is a creative menu with an extra step - and it refills on the way past, so a village of forty
stalls is not forty things ticking for nobody.

### 11. Objectives — built

Steps, conditions and rewards, given and tracked. Tutorials teach and milestones commemorate; this is
neither, and a mod should be able to hang a story, a daily errand or a contract on the same frame.

### 12. Experience — built, as one thing with balances

A number that goes up when a player does a thing, with thresholds a mod reads. What counts, what the
levels mean and whether they unlock anything at all is the mod's business — the engine counts and
remembers.

### 13. Balances — built (see 12: they are one capability)

A named quantity a player owns, that mods can read and change without agreeing on what it is. Coins,
reputation, contribution, a guild's standing: the engine stores a number against a player and a name,
and never learns that one of them is money.

### 14. Claims — built, as *plots*

An area with an owner and permissions, which the engine consults before an edit. What may be claimed,
how much, and what it costs are the mod's.

### 15. Companies — built

Groups of players that other things can be owned by — a claim, a balance, a base. Deliberately separate
from claims: plenty of servers want one without the other.

### 16. Applied effects — built

Built as **conditions** (`engine/server/conditions.gd`), named that way because `effect_registry.gd`
already means particles. A condition is a stat change, or something that repeats on a timer, or both -
and the timer is the half a plain timed modifier could never express, which is what poison,
regeneration and burning all are. Creatures get the ticking half; they have no stat table, so
swiftness on a cow does nothing yet.

A station to brew them at is still content, and nothing in the engine is in the way of it.

### 17. Companions — built

**Three of the four parts already existed in `taming.gd`**: a tamed creature follows, belongs to
somebody, and does not despawn, so it is still there tomorrow. Taking instruction was one boolean,
`sitting`, toggled by right-clicking - fine for a dog, and out of room the moment there is a third
thing to say.

Orders now. Three are the engine's own because all three are about *where*: follow, stay and guard.
Anything else a mod registers maps to a behaviour, so the engine sets the order and the behaviour
decides what it looks like. Right-clicking a companion opens a panel rather than toggling, the same
way talking to a character opens a conversation - a child cannot discover what they cannot see.

`sitting` was kept rather than replaced: the sit behaviour and its pose were proven, and "stay" is
exactly what they already did.

### 18. Vehicles — built (capability; no bundled vehicle yet)

An entity type with a `vehicle` block becomes rideable. **Protocol 47.**

The design decision that matters: **a rider stops simulating themselves**. That is the third case of a
shape the server already had twice - a dead player and a sleeping one both drain their input queue and
stay put - so riding slots in beside them instead of threading a new idea through the physics. It also
means `player_physics.gd` and `physics.rs` were not touched at all, which is the difference between a
vehicle that might break walking and one that cannot.

Steering reuses the input fields that already exist: throttle forward and back, the vehicle turns
towards wherever the rider looks, sneak gets off. Nothing new crosses the wire except "you are riding
that" - and the client needs that one message, because otherwise it predicts walking, the server puts
it back, and that is rubber-banding.

**Not finished: there is no vehicle to ride.** A boat needs a model, and nothing bundled has one. The
server half is covered by fourteen checks; the client half is only covered negatively, in that every
e2e test still passes with riding never switched on. Until a bundled vehicle exists, the riding path
has not been driven by a real client.

### 19. Area tools

Placing or breaking many blocks at once with a preview, respecting permissions and the edit budget.
Mining a whole vein is the same capability with a different rule for choosing the blocks.

### 20. Text in the world — built

Half of this entry already existed: **mod-defined corners of the interface** are `show_ui` with an
anchor, all four corners included, and **a live value inside a piece of text** is calling `show_ui`
again with the new number, which is how every other panel here updates.

What was missing was words in the *world*, and that is `api.float_text` - a `Label3D` that rises,
fades and goes. Drawn through walls on purpose: a damage number that disappears because the thing you
hit stepped behind a post is a number nobody can read, and being readable at a glance is the whole
value of it. It can follow a player or a creature, so a number stays with what it came off rather than
hanging where the blow landed.

Damage numbers themselves are **content, in vanilla**, because a quieter survival game might want
none. The engine only knows how to make a word float. **Protocol 48.**

### 21. Inventories inside things

An item that contains an inventory, and a container that is the same container wherever you open it.

### 22. Moving assemblies — built, with limits

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

## The content that matters most: what is in the ground — done

**Built 20 September.** Copper, gold and sunstone went in, with deep variants of coal, iron, copper and
gold set in deepstone rather than stone. Quickstone and blackglass had already landed with the signal
and liquid capabilities. The ladder is now wood → stone/copper → iron/gold → cobalt → sunstone, with
copper and gold as sidegrades rather than rungs: copper shortens the long stretch where a child has a
stone pickaxe and nothing better, and gold is quicker than anything short of cobalt and breaks while
you watch, which is a lesson about trade-offs that costs nothing to learn.

Named sunstone rather than the obvious thing: a stone that holds the light, found where there is none.

What is below is the original entry, kept because the reasoning still explains the shape.

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

## The mod architecture, settled 21 September 2026

Until now the engine shipped seven games and was tested through them, so every engine change dragged
seven mods behind it and coverage was whatever the content happened to use. That is being undone.

**`base` owns nouns. Games own rules.** Things that *exist* in a world - blocks, liquids, terrain,
biomes, trees, crops, flowers, grass, mobs, animals, birds - are `base`. Progression, survival,
recipes, what a player is *for* - that is a game. The test of whether the line is real: **a creative
game ships zero recipes and everything still exists and works.**

`base` therefore has no furnace, no logic gates and no tools. Those live in content packs a game pulls
in - `simple_gear` (things you hold or wear) and `simple_machines` (things that do something). Two
rather than four: splitting later is easy, merging after people depend on the ids is not.

Testing moves to **the Proving Ground** (`tests/mods/proving`), one mod that uses every capability, in
GDScript and JavaScript. It depends on nothing, because `base` will churn constantly as it grows and a
test mod that rides on it fails for the wrong reasons.

### Three capabilities this architecture needs and does not have

**24. Extending another mod's definitions.** `extend_loot` already exists and its comment states the
principle - "adds pools to a table another mod owns, without forking it" - but it is the only registry
with one. The same is needed for entities, blocks, recipes, containers and stations: adding an attack
to somebody's creature, a slot to their machine. **Additive only.** Adding a pool is commutative and
three mods can do it safely; "set health to 40" means last-loaded wins, which is a conflict system
nobody asked to design.

**25. Excludes.** A game wanting 80% of a pack must be able to refuse the rest. Not as
`remove_block()`: registering and then deleting shifts every id after it, leaves every recipe and loot
table that referenced it dangling, and cannot work anyway because a game loads *after* the mod it
depends on. Instead, **declared in `mod.json` and read before any mod registers anything**:

    {"id": "my_game", "depends": ["base@^1.0"],
     "excludes": ["base:cobalt_*", "base:sunstone_ore", "#base:charms"]}

Never registered is safe where registered-then-removed is not: no id churn, and anything referencing a
missing name is dropped with a warning at load, which is when you want to hear about it. Wildcards and
tags do the bulk work. `remove_mod` is the same mechanism with a wider wildcard, and mostly a non-need
- if you do not want a mod, do not depend on it.

**26. Flight.** Mob AI has `can_swim` and `climb` and nothing for flying: no air movement mode, no air
pathfinding. Birds need it, and it is engine work rather than content.

## What is still only half-decided: which content

`docs/parity.local.md` (19 September) derived fifteen capabilities from a gap analysis, and that list
is essentially this roadmap - nearly all of it is now built. What it never answered is **which blocks,
creatures and biomes actually get built**, and that is the long programme.

Worth scoping as a deliberate subset with a stated principle rather than a checklist to exhaust:
*every biome type that needs a different generation technique, one creature per AI behaviour, one
block per shape and material class*. That way `base` proves the engine's range instead of chasing a
count, and breadth comes after 1.0 when a real game asks for it.

## Order

**The 19 September list is done.** Weather, dimensions, signals, networks, keeping the world awake,
fluids, multiblocks, driven networks and moving assemblies were built in that order over the two days
after it was written, and item modifiers, objectives, ledgers, plots and companies with them. What
follows is what is left, in the order that now unlocks the most.

**Characters and shops went first** and are done, which leaves a **village** with no missing capability
at all: structures, facilities, jobs, ownership, conversation and trade all exist. What a village needs
now is content - somebody to write the villagers.

1. **The small three**: area tools, text in the world, inventories inside things. Independent, and each
   one an afternoon.
2. **Instances.** Much cheaper now dimensions exist, being a dimension with a lifetime.

## Where the built things stop

Limits in capabilities that *are* built, recorded so they are found on purpose rather than discovered.

- **A moving assembly is not solid.** You can stand on one and be carried; you can walk through its
  side. Making it collide means teaching the voxel physics about boxes that are not on the grid, which
  is the physics/Rust twin pair, for a platform that is already rideable.
- **A moving assembly does not turn.** A drawbridge travels along an arc; its blocks do not rotate.
- **Liquid depth is two states, not eight.** A flow past a few blocks becomes a thin slab. Per-level
  heights need block states sent to the mesher and its greedy-merging key re-cut, in the GDScript
  mesher *and* the Rust one, which must agree exactly - a great deal of risk for a cosmetic gain.
- **Belts scroll, conveyed items do not slide.** The belt surface moves; what is being carried is a
  parcel in flight with no position of its own to draw.

## Content the capabilities are waiting for

None of this needs engine work. All of it is what makes the engine worth having.

- **Ores worth digging for** - copper, gold, a hard gem, deep variants. Quickstone landed with signals;
  the rest did not.
- **A reason to build a factory.** Power, pipes, belts, machines and rotation all exist; what is
  missing is a progression that makes a child want one.
- **Twenty-five creature voices**, still generated. The clearest brief the AI-audio phase could have,
  and `stalker_screech` and `colossus_roar` are the two that would change the game most.
- **Hearthhold's second phase.** Settlers, dwellings and a charter exist at phase one.

## For 1.0

- **Touch controls**, and then an iPad build - see above; the only item that puts the game in a child's
  hands somewhere other than a desk.
- **Instrument the network**, then **compress chunk payloads**, then **interest management** - in that
  order, because the first makes the other two answerable rather than guesswork.
- **Migration and corruption-proofing** become real work the day 1.0.0 ships, and not before.
