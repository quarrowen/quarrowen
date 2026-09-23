# Blocks and the world

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.register_block`

GDScript: `api.register_block(block_name: String, def: Dictionary) -> int`

JavaScript: `api.registerBlock(name: string, def: BlockDef): BlockId`

Registers a block. `name` is namespaced to this mod. Texture and model paths are relative to the
mod folder. See BlockRegistry.register for keys (render, light, interactive, model, ...). Extra keys
(e.g. `drops`: "base:cobblestone" or "") are kept server-side.
Returns the runtime block id, or -1 on error.
Beds: `bed: true` (right-click sets the respawn point and sleeps at night). Two-block pieces:
`pair: {block, direction: "back" | "front" | "up" | "down"}` places `block` next to it (relative to
the facing of an `orientation: "horizontal"` block) and removes both together; give the second half
the opposite direction and `placeable: false`.
`contact_damage: {amount, interval, cause}` hurts players and mobs whose body is inside the block
(lava).
`group: "Stone"` names the drawer this sits in in the creative palette. Worth setting once a mod
has more blocks than fit on a screen; without it they all land in one drawer called Blocks.
A block with `placeable: false` is never offered by the palette, so the far half of a `pair` needs
nothing said about it.

```gdscript
ids.wire = api.register_block("wire", {"display_name": "Wire",
	"hardness": 0.5, "signal_carry": true, "connect_group": "proving_signal"})
```

**See also:** `expand_textures`, `is_excluded`, `qualified`, `register`, `register_asset`, `reload`

### `api.register_block_tick`

GDScript: `api.register_block_tick(block_name: String, handler: Callable, options := {}) -> bool`

JavaScript: `api.registerBlockTick(blockName, handler, options)`

Makes blocks of a type change over time. `handler(ctx)` gets {position, block, state, ticks, reason,
payload, elapsed, realm}: "random" ticks come about every options.interval seconds (default 30) per
block, and "scheduled" ticks come from schedule_block_tick. **Use ctx.realm** when reading or
writing blocks: a position does not say which world it is in.

Blocks only tick while somebody is near enough for the server to be running that part of the world.
A block that was asleep - because its chunk was unloaded, or because everybody walked away - is
handed the ticks it missed at once when it wakes (`ticks` > 1) unless options.catch_up is false.
`ticks` is capped, so returning to a world after a week does not run a week of growth in one frame;
`elapsed` is the true number of seconds it stood still, for a handler that would rather work the
answer out itself.

```gdscript
api.register_block_tick("lamp", func(ctx):
	api.set_block_data(ctx.position, {"ticked": int(api.get_block_data(ctx.position).get("ticked", 0)) + 1}),
	{"interval": 5, "random": false})
```

**See also:** `block`, `is_excluded`, `qualified`, `register`

### `api.schedule_block_tick`

GDScript: `api.schedule_block_tick(position: Vector3i, seconds: float, payload := {}) -> void`

JavaScript: `api.scheduleBlockTick(position, seconds, payload)`

Calls the tick handler of the block at `position` after `seconds`, with `payload` (saved with the world).

**See also:** `schedule`

### `api.get_light`

GDScript: `api.get_light(position: Vector3i) -> int`

JavaScript: `api.getLight(position)`

Light level 0-15 at a position right now: block light or sky light scaled by daylight, whichever is
brighter. An estimate (no occlusion) meant for growth and spawning rules.

**See also:** `get_daylight`, `light_at`

### `api.get_light_levels`

GDScript: `api.get_light_levels(position: Vector3i) -> Dictionary`

JavaScript: `api.getLightLevels(position)`

{sky, block} light levels 0-15 (sky not scaled by the time of day).

**See also:** `light_levels`

### `api.get_world_clock`

GDScript: `api.get_world_clock() -> float`

JavaScript: `api.getWorldClock()`

Seconds of world time that have passed (keeps counting across restarts, not while stopped).

### `api.break_block`

GDScript: `api.break_block(position: Vector3i, drop := true, realm_id := "") -> void`

JavaScript: `api.breakBlock(position, drop, realmId)`

Breaks a block as if mined without a player: drops its items (when `drop`) and plays its sound.
Fires block_destroyed {position, block, drops} (drops may be changed).

**See also:** `block_changed`, `block_removed`, `block_state`, `break_block`, `chunk_coord_at`, `clear_block_data`

### `api.block_textures`

GDScript: `api.block_textures(block_name: String) -> Array`

JavaScript: `api.blockTextures(blockName)`

Looks up a block id by name ("base:stone", or "stone" for this mod's own). -1 if unknown.
The texture names a block uses, so a slab or stairs can be made of the same material.

**See also:** `block`, `item`

### `api.require_block`

GDScript: `api.require_block(block_name: String) -> int`

JavaScript: `api.requireBlock(blockName)`

The id of something this mod cannot work without. `block`, `item` and `entity_type` answer a
*question* - "is this installed?" - and return -1 for no, which mods rely on to make optional
content optional (`if api.item("other:thing") > 0`). These state a *requirement* instead: a name
that is not there is an error, said out loud at load with the mod that asked.

**Use these for anything you keep.** A -1 stored in a generator, a cached field or a table becomes
65535 when it is written as the u16 a block id is - and 65535 is UNLOADED, so the world reads as
absent rather than wrong. Three bugs in one day came from that, all of them a question's answer
being used as a contract. (2026-09-21)

```gdscript
ev.player.set_hotbar([api.require_block("proving:plain"), api.require_block("proving:lamp"),
	api.require_block("proving:crate"), api.require_block("proving:rock"),
	api.require_block("proving:step")], 64)
```

**See also:** `block`

### `api.block`

GDScript: `api.block(block_name: String) -> int`

JavaScript: `api.block(name: string): BlockId`

### `api.block_name`

GDScript: `api.block_name(id: int) -> String`

JavaScript: `api.blockName(id: BlockId): string`

The full name ("mod:name") of a block id, or "".

### `api.block_display_name`

GDScript: `api.block_display_name(id: int) -> String`

JavaScript: `api.blockDisplayName(id)`

The name players see for a block id.

### `api.register_multiblock`

GDScript: `api.register_multiblock(pattern_name: String, def: Dictionary) -> bool`

JavaScript: `api.registerMultiblock(patternName, def)`

A machine somebody assembles out of blocks. Described as layers of characters, bottom first, the
way anybody would draw it on paper:

api.register_multiblock("forge", {
"layers": [["BBB", "BBB", "BBB"],
["B B", " C ", "B B"]],
"key": {"B": "base:brick", "C": "base:furnace"},
"controller": "C"})

A space means "do not care". A key may name a **tag** with `#`, so "any log" works and a mod adding
a tree joins in. The controller is where the machine's data lives - where a player right-clicks and
where the inventory hangs.

You are told when one is finished or spoiled (`multiblock_formed`, `multiblock_broken`), and can ask
at any time with `multiblock_at`. The engine does not *remember* which are built: that would mean
saving a fact that can be worked out from the blocks, and a saved fact can disagree with them.

```gdscript
api.register_multiblock("engine", {
	"layers": [["PPP", "PCP", "PPP"]],
	"key": {"P": "#proving:stone_like", "C": "proving:core"},
	"controller": "C"})
```

**See also:** `qualified`, `register`

### `api.multiblock_at`

GDScript: `api.multiblock_at(controller: Vector3i, pattern_name := "", realm_id := "") -> Dictionary`

JavaScript: `api.multiblockAt(controller, patternName, realmId)`

The machine whose controller is at this position, or {}: {name, controller, origin, cells}.

**See also:** `at`, `qualified`, `register_instance`, `register_liquid`

### `api.extend_block`

GDScript: `api.extend_block(block_name: String, additions: Dictionary) -> bool`

JavaScript: `api.extendBlock(blockName, additions)`

Adds to a block another mod owns. `drops` is the one list a block has; everything else about a block
is baked into lookup tables at registration and cannot change afterwards.

**See also:** `block`, `is_excluded`, `qualified`

### `api.get_block`

GDScript: `api.get_block(pos: Vector3i, realm_id := "") -> int`

JavaScript: `api.getBlock(position: Vec3): BlockId`

Loads the chunk if needed. Use get_loaded_block when scanning large areas.

```gdscript
if api.get_block(at, realm_id) != int(ids.slime):
```

**See also:** `get_block_loaded`, `qualified`, `register_instance`

### `api.get_loaded_block`

GDScript: `api.get_loaded_block(pos: Vector3i, realm_id := "") -> int`

JavaScript: `api.getLoadedBlock(position: Vec3): BlockId`

Block id without loading anything; BlockRegistry.UNLOADED (255) if the chunk is not in memory.

**See also:** `collides`, `get_block_v`, `qualified`, `register_instance`

### `api.is_solid`

GDScript: `api.is_solid(block: int) -> bool`

JavaScript: `api.isSolid(id: BlockId): boolean`

Whether a block id collides (unloaded space counts as solid).

### `api.is_breakable`

GDScript: `api.is_breakable(block: int) -> bool`

JavaScript: `api.isBreakable(block)`

Whether players can break a block id.

### `api.get_drops`

GDScript: `api.get_drops(block: int) -> Array`

JavaScript: `api.getDrops(id: BlockId): [ItemId, number][]`

What breaking this block yields by default: [[item id, count], ...].

**See also:** `get_block`, `set_block`

### `api.set_block`

GDScript: `api.set_block(pos: Vector3i, id: int, realm_id := "", keep_data := false, state := 0) -> void`

JavaScript: `api.setBlock(position: Vec3, id: BlockId, options?: { realm?: string; keepData?: boolean; state?: number }): void`

Sets a block authoritatively (loading its chunk if needed) and replicates it to players. Block
data at the position is cleared when the block type changes unless `keep_data` is true.

**`realm_id` comes third, like everywhere else.** It used to sit fifth, behind `keep_data` and
`state`, which made this the only one of the eight block functions that did not take the realm
straight after its required arguments - `get_block`, `get_block_state`, `get_block_data`,
`set_block_data`, `clear_block_data`, `sees_sky` and `fill` all do. Anyone who had learned
`get_block(pos, realm)` wrote `set_block(pos, id, realm)` and put a realm where a bool goes.

That mistake is loud (GDScript refuses the conversion, names the file and line, and aborts the
call), so nothing was ever silently wrong. It was simply a trap the signature laid, and there is no
reason for the odd one out to stay odd. (2026-09-21)

```gdscript
api.set_block(at, 0, realm_id)
```

**See also:** `qualified`, `register_instance`, `set_block_authoritative`

### `api.get_block_state`

GDScript: `api.get_block_state(pos: Vector3i, realm_id := "") -> int`

JavaScript: `api.getBlockState(position: Vec3): number`

Per-block state byte (e.g. facing 0-3 for "orientation": "horizontal" blocks).

```gdscript
if api.get_block_state(at, realm_id) != 0:
```

**See also:** `block_state`, `chunk_coord_at`, `index`, `qualified`, `register_instance`

### `api.facing_from_yaw`

GDScript: `api.facing_from_yaw(yaw: float) -> int`

JavaScript: `api.facingFromYaw(yaw: number): number`

Facing (0-3) an oriented block gets when placed by someone looking along `yaw`.

**See also:** `block`

### `api.facing_direction`

GDScript: `api.facing_direction(state: int) -> Vector3i`

JavaScript: `api.facingDirection(state)`

Front direction of an oriented block (+Z/+X/-Z/-X for facing 0-3).

### `api.get_block_data`

GDScript: `api.get_block_data(pos: Vector3i, realm_id := "") -> Dictionary`

JavaScript: `api.getBlockData<T = Record<string, unknown>>(position: Vec3): T`

Block data ("block entities"): a Dictionary of JSON-compatible values stored with the world and
removed automatically when the block is broken or replaced.

**See also:** `chunk_coord_at`, `qualified`, `register_instance`

### `api.set_block_data`

GDScript: `api.set_block_data(pos: Vector3i, data: Dictionary, realm_id := "") -> void`

JavaScript: `api.setBlockData(position: Vec3, data: Record<string, unknown>): void`

Replaces the data dictionary stored with the block at a position (saved with the world).

```gdscript
api.set_block_data(ctx.position, {"level": int(ctx.level)}))
```

**See also:** `add_chunk`, `block`, `chunk_coord_at`, `chunk_path`, `decorate`, `generate`

### `api.clear_block_data`

GDScript: `api.clear_block_data(pos: Vector3i, realm_id := "") -> void`

JavaScript: `api.clearBlockData(position: Vec3): void`

Removes the data stored with the block at a position.

**See also:** `chunk_coord_at`, `qualified`, `register_instance`

### `api.find_block_data`

GDScript: `api.find_block_data(block := -1, realm_id := "") -> Array[Vector3i]`

JavaScript: `api.findBlockData(block?: BlockId): Vec3[]`

Loaded positions that carry block data, optionally filtered to one block id.

**See also:** `get_block_v`, `qualified`, `register_instance`

### `api.set_world_time`

GDScript: `api.set_world_time(time_of_day: float, day_length := -1.0) -> void`

JavaScript: `api.setWorldTime(timeOfDay: number, dayLength?: number): void`

time_of_day: 0 = midnight, 0.25 = sunrise, 0.5 = noon. day_length in seconds (0 freezes time).

**See also:** `daylight`, `get_day_length`, `phase`

### `api.get_time_of_day`

GDScript: `api.get_time_of_day() -> float`

JavaScript: `api.getTimeOfDay()`

The time of day from 0 to 1 (0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset).

### `api.get_daylight`

GDScript: `api.get_daylight() -> float`

JavaScript: `api.getDaylight()`

Sky brightness in [0.12, 1] for the current time of day.

**See also:** `block`, `daylight`, `get_time_of_day`

### `api.sees_sky`

GDScript: `api.sees_sky(pos: Vector3i, realm_id := "") -> bool`

JavaScript: `api.seesSky(position: Vec3): boolean`

True if nothing opaque or solid is above the block (it can see the sky).

**See also:** `area_cells`, `get_block`

### `api.fill`

GDScript: `api.fill(from: Vector3i, to: Vector3i, id: int, realm_id := "") -> void`

JavaScript: `api.fill(from: Vec3, to: Vec3, id: BlockId): void`

Sets every block in the box between two corners (inclusive) to a block id.

**Admin, not a player action**: no permission check, no events, no budget, no drops. For a tool a
player holds, use `area_edit`, which asks all of those.

### `api.surface_y`

GDScript: `api.surface_y(x: int, z: int, realm_id := "") -> int`

JavaScript: `api.surfaceY(x: number, z: number): number`

Y of the highest non-air block in the column, or -1.

**See also:** `qualified`, `register_instance`, `surface_height`
