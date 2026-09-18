# Parity, and the capabilities it needs

What this project is aiming at, what it has, and what it would take to get the rest. Written 19
September 2026, from a list the user had been carrying in their head since the beginning — which is the
reason it is written down now rather than discussed again.

## The target, and the line through the middle of it

Two goals, and they are not the same shape:

1. **Feature parity with vanilla Minecraft 1.21** — blocks, mobs, animals, plants, biomes, dimensions,
   bosses, and the systems behind them. This is mostly **content**, and almost all of it lands in the
   `vanilla` mod.
2. **The engine can express what today needs plugins and mods** — so that the equivalents of AuraSkills,
   Create, Mekanism, Botania or MythicMobs are *buildable here*, by anyone, without engine changes.

The second is the interesting one, and it is where the project's own rule does the work: **the engine
provides capabilities, mods provide the building blocks, and games are built from those.** So the right
question about a plugin is never "how do we clone it" but "what could the engine not express, that this
plugin had to reach past the game to do?"

Nothing here is a copy. Names, recipes, balance and voice stay ours — Hearthhold is the model. The public
line remains that Quarrowen is independent and unaffiliated, and that stays true as long as what we take
from the genre is *what a player can do*, not *what somebody else called it*.

## Where we are (19 September 2026)

| | Today |
|---|---|
| Mod API | 169 functions |
| Blocks | 75 across all bundled mods |
| Creatures | 11 (pig, cow, sheep, chicken, wolf, zombie, skeleton, spider, slime, night stalker, boomshroom) + the Colossus, + Bramble as an NPC |
| Biomes | 12 (plains, forest, birch forest, taiga, snowy tundra, desert, swamp, savanna, mountains, mushroom fields, shadowwood, ocean) |
| Gear | wood → stone → iron → cobalt, armour, three charms |
| Games | Vanilla, Hearthhold, One Block, Sky Islands, plus arcana / industry / guild |

Already built, and worth knowing before anything is planned twice: graves on death, roles and
permissions, travel between worlds, cosmetics, a guidebook, tutorials, milestones, loot tables,
structures as data and worlds a mod can ship, crafting minigames and forging, containers and stations,
recipe discovery, held-use charging, ambience, server-chosen music, a map with markers, "what am I
looking at", UGC moderation, and a hub.

**Absent entirely** — checked rather than assumed: dimensions (the word appears only as a map-marker
filter), redstone or any signal system, fluids, energy, enchanting, brewing and potions, villagers and
trading, vehicles, and weather (which appears only in code comments).

## Vanilla 1.21: the gaps

Grouped by what each needs from the engine, because that is what decides the order.

| Gap | Needs |
|---|---|
| **The Nether and the End** | Dimensions (capability 1) |
| **Redstone** | Signals (capability 3) |
| **Enchanting** | Item modifiers (capability 4) |
| **Brewing and potions** | Applied effects and a brewing station (capability 11) |
| **Villagers and trading** | NPCs and economy (capabilities 8, 9) |
| **Boats and minecarts** | Vehicles (capability 13) |
| **Weather** | New: rain, thunder, and blocks that notice |
| **Taming: wolves, cats, horses** | Pets (capability 12) |
| **~70 more mobs** | Mostly content; bosses want mob skills (capability 7) |
| **Beacons, conduits** | Multiblocks (capability 6) |
| **Raids, trial chambers, archaeology, sculk** | Content, once the above exist |

## The capabilities, derived from the list

The hundred-odd plugins and mods collapse into a much shorter list, because most of them are different
content over the same few engine gaps. Ordered by how much each unlocks.

### 1. Dimensions
*Nether, End, mining dimensions, Twilight Forest, Xycraft, Multiverse, compact machines.*

Separate worlds, each with its own generator, chunk storage and rules, reached through a portal, with
entities and items crossing. This is the single largest missing piece and roughly a quarter of the list
depends on it. It also changes the save format, so it wants doing carefully and early rather than bolted
on later.

### 2. Resource networks
*Mekanism, Thermal, Powah, EnderIO, Flux Networks, Pipez, XNet, LaserIO, Modular Routers, Modern
Dynamics, Refined Storage, AE2, Simple Storage, Translocators, Botania's mana, Powah, Oritech.*

One capability: **a quantity that moves between blocks along a network**. Energy, items, fluids and mana
are the same problem with different units, and a mod should declare a unit rather than the engine
knowing about electricity. Around thirty mods on the list are this plus content. If only one capability
after dimensions gets built, it is this one.

### 3. Signals
*Redstone parity, RFTools, Super Factory Manager, XNet's logic half, Quark's gadgets.*

Blocks that emit, carry and react to a level, with wires, gates and delays. Needed for vanilla parity on
its own, and everything mechanical assumes it exists.

### 4. Item modifiers
*Enchanting, Apotheosis, MythicEnchantments, Silent Gear, Tinkers' Construct, Mythic Armors.*

Named modifiers on an item that change stats and hook events, applied at a station and readable in the
tooltip. Partly here already — items carry data, quality and stats — so this is an extension rather than
a new system.

### 5. Fluids
*Every industrial mod, plus buckets and cauldrons for parity.*

A fluid as a quantity that can sit in a tank, move through a network (capability 2) and be poured out as
a liquid block. Distinct from the liquid blocks we already have.

### 6. Multiblock structures
*Extreme Reactors, Immersive Engineering, Draconic Evolution, Compact Machines, beacons, conduits.*

Detect an assembled shape and treat it as one machine with one inventory and one controller. Structure
templates already describe shapes for worldgen; this is recognising one that a player built.

### 7. Mob skills
*MythicMobs, MythicDungeons, and every boss worth fighting.*

Data-driven abilities: phases, timed skills, summons, area effects, telegraphs. The AI presets and
attacks exist; what is missing is a mod being able to script a fight without writing a brain.

### 8. NPCs and dialogue
*FancyNPCs, villagers, MythicRPG shops, BeautyQuests' givers.*

Standing characters with a name, a look, a conversation and something to offer. Bramble is one, written
by hand; this makes her a capability.

### 9. Quests, skills and economy
*BeautyQuests, DailyQuests, AuraSkills, MythicRPG, Vault, Jobs.*

Three related things that all want the same plumbing: **objectives** with steps and rewards (beyond
tutorials and milestones, which are teaching and achievement respectively), **experience per activity**
with levels and perks, and **a balance** mods can share so an economy is not re-invented per mod.

### 10. Claims, teams and chunk loading
*WorldGuard, FTB Chunks, FTB Teams.*

Areas with an owner and permissions, groups of players who share them, and keeping an area ticking when
nobody is standing in it. The last one is not optional once machines exist.

### 11. Applied effects and brewing
*Potions for parity, plus anything that buffs.*

Food effects already exist (`hunger.gd` applies timed modifiers to any stat). This generalises them to
anything that can apply an effect, plus a station to make them at.

### 12. Pets and companions
*MyPet, SimplePets, taming for parity.*

A creature that follows, is owned, can be told what to do, and persists.

### 13. Vehicles
*Boats, minecarts, Simple Jetpacks.*

Rideable entities that carry a player and change how they move.

### 14. Player area tools
*Building Gadgets, Construction Wands, FTB Ultimine, WorldEdit.*

Placing or breaking many blocks at once, with a preview, respecting permissions and the edit budget.
Vein mining is the same capability with a different selection rule.

### 15. World-anchored text and HUD
*FancyHolograms, DamageIndicator, MythicHUD, PlaceholderAPI.*

Text that floats in the world, numbers that fly off a hit, and mod-defined HUD corners. Placeholders —
`%player_level%` and the like — belong here too, since they exist to put a number in a piece of text.

### 16. Nested inventories
*Sophisticated Backpacks, Pocket Storage, Ender Storage, shulker-box parity.*

An item that contains an inventory, and a container that is the same container everywhere.

### 17. Seasons and long cycles
*SeasonsPlus.*

World state on a longer clock than day and night, which crops, mobs and weather can read.

### 18. Instanced areas
*MythicDungeons, Compact Machines.*

A private copy of a space, entered and left. Cheaper once dimensions exist, because it is a dimension
with a lifetime.

### Already possible today

Worth saying, so nobody builds engine support for something that needs none: **death chests** (graves),
**DeluxeMenus** (`show_ui`), **LuckPerms** (roles), **Multiverse** (travel), **MythicCosmetics**
(cosmetics), **The One Probe** ("what am I looking at"), **Jukebox** (music), **Waystones** (portals and
arrival points), **iron chests and furnaces** (containers), **all the ores and Geore** (ore passes),
**trash cans, magnets, item collectors, fast leaf decay** (blocks and entities), and every decoration
mod on the list — Chisel, Chipped, Macaw's, Supplementaries, Xtones, Simply Light — which is content and
nothing else. **Connected textures** is the one decoration item that is a rendering capability.

## The mods to build, consolidated

A hundred mods is somebody else's packaging problem, not ours. Ten cover the same ground:

| Mod | What it is | Absorbs |
|---|---|---|
| `base` | blocks, tools, crafting | exists |
| `vanilla` | the survival game, at 1.21 parity | exists, grows |
| `deep` | dimensions: a mining world and a strange one | mining dimensions, Twilight Forest, Xycraft |
| `machines` | power, pipes, automation, storage networks | Mekanism, Thermal, AE2, Refined Storage, EnderIO, Create, Immersive, the ~30 |
| `arcana` | magic: mana, spells, rituals | exists; Botania, Ars Nouveau, Forbidden & Arcanus, ProjectE |
| `guild` | economy, quests, NPCs, trading, jobs | exists; Vault, BeautyQuests, Jobs, MythicRPG |
| `frontier` | claims, teams, waystones, chunk loading | WorldGuard, FTB Chunks/Teams, Waystones |
| `kitchen` | farming, food, bees, trees | Farmer's Delight, Mystical/Industrial Agriculture, Productive * |
| `build` | decoration and building tools | Chisel, Chipped, Macaw's, Supplementaries, Building Gadgets |
| `hearthhold` | the story game | exists |

## Order of work

Dimensions and resource networks first, because everything else assumes one or the other. Signals third,
because vanilla parity needs it and machines are poor without it. Then item modifiers, fluids and
multiblocks, which together turn `machines` from a demo into a game. The social half — quests, skills,
economy, claims, teams — is independent of all of that and can be done whenever it is wanted; it is what
a *server* needs rather than what a *world* needs.

Weather is small, visible, and unblocked by anything. It is the cheapest thing on this page.
