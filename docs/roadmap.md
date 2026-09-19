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
server-chosen music, a map with markers, "what am I looking at", UGC moderation, and a hub.

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

### 3. Signals

A block can emit a level, a block can declare itself able to carry one, and a block can be told when the
level reaching it changes. That is the whole capability, and it is deliberately less than it first
looked: **gates, delays, inverters and latches are blocks a mod writes**, each one reading its
neighbours and emitting accordingly. An engine that ships an AND gate has decided what logic looks like,
which is not its business.

In the bundled game the material is **quickdust**, laid in lines and gathered from **quickstone**, and a
block carrying a signal is *quickened*. (Quick in the old sense: alive.) Another mod's wiring can look
nothing like it.

### 4. Item modifiers

Named modifiers on an item that change its stats and hook events, applied at a station and readable in
the tooltip. Items already carry data, quality and stats, so this is an extension rather than a new
system.

### 5. Flowing liquids

Water and lava exist as blocks and sit exactly where they are put. They do not spread, do not fall, do
not fill a hollow, and do not meet each other. That absence is larger than it sounds: **a bucket is not
worth carrying** if what comes out of it cannot go anywhere, a cave cannot flood, a moat is a row of
still squares, and the stone that forms where lava meets water — the obvious black glassy block a player
expects to find and mine — has no way to exist.

A block-level flow, with a source, a level that decreases with distance, and a rule for what happens
where two liquids meet. It is the last purely-vanilla system missing, and it is the reason to do it
before the industrial half rather than after.

### 6. Fluids in containers

A fluid as a quantity that can sit in a tank and travel a network — which is a different problem from
the one above, and neither gives you the other. A tank does not spread; a puddle does not pipe.

### 7. Multiblocks

Recognise a shape a player has assembled and treat it as one machine with one inventory and one
controller. Structure templates already describe shapes for world generation; this is noticing one that
somebody built by hand.

### 8. Creature abilities

Data-driven fights: phases, timed abilities, summons, area effects, telegraphs. The AI presets and
attacks exist; what is missing is a mod scripting a fight without writing a brain.

### 9. Characters

People who stand somewhere, have a name and a face, hold a conversation and offer something. Bramble is
one, written by hand; this makes her a capability so a mod can have a hundred.

### 10. Objectives

Steps, conditions and rewards, given and tracked. Tutorials teach and milestones commemorate; this is
neither, and a mod should be able to hang a story, a daily errand or a contract on the same frame.

### 11. Experience

A number that goes up when a player does a thing, with thresholds a mod reads. What counts, what the
levels mean and whether they unlock anything at all is the mod's business — the engine counts and
remembers.

### 12. Balances

A named quantity a player owns, that mods can read and change without agreeing on what it is. Coins,
reputation, contribution, a guild's standing: the engine stores a number against a player and a name,
and never learns that one of them is money.

### 13. Claims

An area with an owner and permissions, which the engine consults before an edit. What may be claimed,
how much, and what it costs are the mod's.

### 14. Companies

Groups of players that other things can be owned by — a claim, a balance, a base. Deliberately separate
from claims: plenty of servers want one without the other.

### 15. Keeping the world awake

An area that keeps ticking when nobody is standing in it. Small, and not optional once machines exist.

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
  and impossible until liquids flow (capability 5). It is the clearest example of why that capability
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
| `frontier` | claims, companies, waystones, keeping the world awake |
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
5. **Fluids**, which ride on networks and are half of what machines move.
6. **Multiblocks.** Turns `machines` from a demonstration into a game.
7. **Networks**, driven kind, then **moving assemblies**. The mechanical family, left until last of the
   structural work because assemblies are the hardest thing on this page and want the other two behind
   them.
8. **Item modifiers** and **applied effects** — the depth pass on gear and potions.
9. **The social half**: objectives, experience, balances, claims, companies, keeping the world awake.
   Depends on none of the above and can be taken whenever it is wanted. It is what a *server* needs
   rather than what a *world* needs, and each piece is small.

Everything else — characters, creature abilities, companions, vehicles, area tools, text in the world,
nested inventories, instances — is independent and can be picked up when a game actually needs it,
which is the honest test of whether a capability is worth building.
