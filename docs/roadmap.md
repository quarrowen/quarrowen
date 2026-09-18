# What the engine still needs

Quarrowen's rule is that **the engine provides capabilities and mods provide content**. This is the list
of capabilities it does not have yet, in the order that unlocks the most.

It comes from working backwards: taking the things people build on top of voxel games — the machines,
the magic, the economies, the dungeons, the storage systems — and asking not "how would we write that"
but **"what could our engine not express, that whoever built it had to reach past the game to do?"**
About a hundred such things collapse into twenty-one answers, because most of them are different
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

**Where this does not reach, and it should be decided rather than discovered.** "A quantity that moves"
assumes something *stored and conserved*, which buffers, fills and runs out. Mechanical power is not
that shape: rotation is a speed and a twist, it arrives the instant the shaft turns, nothing accumulates
in the gearbox, and a network with two sources fights rather than adds. A mod wanting gears, shafts and
windmills cannot build them on this. Either the capability covers propagation-without-storage as a
second kind of network, or it is written down as a thing the engine will not do — but not left to be
found out by whoever tries.

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

### 5. Fluids

A fluid as a quantity that can sit in a tank, travel a network and be poured out as a liquid block —
distinct from the liquid blocks that already exist.

### 6. Multiblocks

Recognise a shape a player has assembled and treat it as one machine with one inventory and one
controller. Structure templates already describe shapes for world generation; this is noticing one that
somebody built by hand.

### 7. Creature abilities

Data-driven fights: phases, timed abilities, summons, area effects, telegraphs. The AI presets and
attacks exist; what is missing is a mod scripting a fight without writing a brain.

### 8. Characters

People who stand somewhere, have a name and a face, hold a conversation and offer something. Bramble is
one, written by hand; this makes her a capability so a mod can have a hundred.

### 9. Objectives

Steps, conditions and rewards, given and tracked. Tutorials teach and milestones commemorate; this is
neither, and a mod should be able to hang a story, a daily errand or a contract on the same frame.

### 10. Experience

A number that goes up when a player does a thing, with thresholds a mod reads. What counts, what the
levels mean and whether they unlock anything at all is the mod's business — the engine counts and
remembers.

### 11. Balances

A named quantity a player owns, that mods can read and change without agreeing on what it is. Coins,
reputation, contribution, a guild's standing: the engine stores a number against a player and a name,
and never learns that one of them is money.

### 12. Claims

An area with an owner and permissions, which the engine consults before an edit. What may be claimed,
how much, and what it costs are the mod's.

### 13. Companies

Groups of players that other things can be owned by — a claim, a balance, a base. Deliberately separate
from claims: plenty of servers want one without the other.

### 14. Keeping the world awake

An area that keeps ticking when nobody is standing in it. Small, and not optional once machines exist.

### 15. Applied effects

Food already applies timed modifiers to any stat. This generalises it to anything that can apply an
effect to anybody, and gives mods a station to brew them at.

### 16. Companions

A creature that follows, is owned, takes instruction and is still there tomorrow.

### 17. Vehicles

Rideable entities that carry a player and change how they move.

### 18. Area tools

Placing or breaking many blocks at once with a preview, respecting permissions and the edit budget.
Mining a whole vein is the same capability with a different rule for choosing the blocks.

### 19. Text in the world

Words that float where a thing is, numbers that fly off a hit, mod-defined corners of the interface, and
a way to put a live value inside a piece of text.

### 20. Inventories inside things

An item that contains an inventory, and a container that is the same container wherever you open it.

### 21. Instances

A private copy of a space, entered and left. Much cheaper once dimensions exist, being a dimension with
a lifetime.

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

Dimensions and networks first; nearly everything assumes one or the other. Signals third, because the
survival game needs wiring on its own account and machines are poor without it. Then item modifiers,
fluids and multiblocks, which together turn `machines` from a demonstration into a game.

The social half — objectives, experience, balances, claims, companies — depends on none of that and can
happen whenever it is wanted. It is what a *server* needs rather than what a *world* needs, and each of
those five is small on its own, which is why they are listed separately: bundled together they looked
like one large job and put themselves off.

**Weather** is small, visible, blocked by nothing, and does not exist at all. It is the cheapest thing on
this page.
