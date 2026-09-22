# Engine reference

Every documented function inside the engine, grouped by the question it answers rather
than by the folder it lives in. This is the half with no other index, and the half that
kept getting reimplemented: search here before writing anything that reads, normalises or
validates data a mod supplied. For the functions a mod calls, see [mod-api.md](mod-api.md).


## Drops, loot and rewards

### `position: Vector3i  (property)`

*server/container.gd*

Where this container is, for a block. Vector3i.ZERO for a bag or a shared store, which are
nowhere - use `key` to say *which* container this is.

### `key: String  (property)`

*server/container.gd*

The container's address (see Containers.block_key / item_key / store_key). Held so `changed()` can
tell viewers about a container that has no position: marking one by `position` sent every bag in
the world to whoever was looking at the chest at the origin. (2026-09-21)

### `state: Dictionary  (property)`

*server/container.gd*

Mod-owned data saved with the container (e.g. how long the fuel still burns).

### `get_item(slot: int) -> Dictionary`

*server/container.gd*

{item, count, data} for a slot (item 0 when empty).

**See also:** `total`

### `group(group_name := "") -> Array`

*server/container.gd*

Slot indices of a named group, or every slot for "".

### `group_of(slot: int) -> Dictionary`

*server/container.gd*

The group a slot belongs to ({} if none).

**See also:** `group`

### `add(item: int, count: int, item_data := {}, group_name := "") -> int`

*server/container.gd*

Adds items to a group (or to every slot players may insert into), merging stacks first. Returns
how many did not fit.

### `take(slot: int, count: int) -> Dictionary`

*server/container.gd*

Removes up to `count` items from a slot and returns what was removed as {item, count, data}.

**See also:** `coop`, `get_item`, `max_stack`, `may_take`, `set_item`, `sync_inventory`

### `set_progress(bar: String, value: float) -> void`

*server/container.gd*

Sets a progress bar of the container type (0-1) for viewers.

**See also:** `changed`

### `changed() -> void`

*server/container.gd*

Shows the current contents to everyone viewing (called automatically by the setters above).

**See also:** `at_key`, `block_key`, `is_block_key`, `position_of`

### `to_network() -> Dictionary`

*server/container.gd*

Network form: ids and counts packed, item data by slot, progress values.

### `static block_key(pos: Vector3i) -> String`

*server/containers.gd*

What a container screen is showing, as one string. Three kinds live behind it:

b:12,64,-3   a block - the store is that block's data
i:7          the bag in the viewer's own inventory slot 7 - the store is that item's data
s:mod:vault  a shared store - the store is `stores[name]`, saved with the world

**One type rather than a Vector3i that is sometimes something else.** The addressing used to be a
position everywhere, which is why "a container that is the same wherever you open it" had nowhere
to live. A tagged string keeps every viewer map, dirty set and open-screen field a single type,
and the tag says which kind you have rather than leaving it to be inferred. (2026-09-21)

### `stores := {}  (property)`

*server/containers.gd*

Shared stores: name -> the dictionary a container view is backed by. Saved with the world.

The engine does not decide whose a store is - the *name* does. A mod wanting one vault for the
server asks for "vault"; a mod wanting one each asks for "vault_" + player_id. That keeps the
sharing rule where the rule belongs and this table a plain dictionary. (2026-09-21)

### `register(type_name: String, def: Dictionary) -> bool`

*server/containers.gd*

Registers a container type. Returns false when invalid.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `type_of_block(block: int) -> Dictionary`

*server/containers.gd*

The container type of a block, or {}.

### `get_container(pos: Vector3i, player = null)`

*server/containers.gd*

The container at a position (loads its chunk), or null if the block there is not a container.

**See also:** `block_key`, `get_block_data`, `get_block_loaded`, `realm_of`, `set_block_data`, `type_of_block`

### `at_key(key: String, player = null)`

*server/containers.gd*

The container a key names, whoever it belongs to, or null. The one place that knows where each
kind of store lives; everything else works in keys.

**See also:** `get_container`, `get_def`, `is_block_key`, `item_key`, `store_key`

### `declare_store(store_name: String, type_name: String) -> bool`

*server/containers.gd*

Declares a shared store, if it does not exist yet. Returns false if the type is unknown.

### `open_item(p, slot: int) -> bool`

*server/containers.gd*

Opens the bag in one of a player's own inventory slots.

**See also:** `at_key`, `close`, `is_block_key`, `item_key`, `merge`, `position_of`

### `open_store(p, store_name: String) -> bool`

*server/containers.gd*

Opens a shared store by name.

**See also:** `at_key`, `close`, `is_block_key`, `merge`, `position_of`, `store_key`

### `close(p, tell_client := true) -> void`

*server/containers.gd*

Closes the player's container screen (`tell_client`: the server decided, e.g. it was broken).

**See also:** `input`, `is_block_key`, `leave`, `player_by_id`, `position_of`, `remove_realm`

### `mark_changed(pos: Vector3i, p = null, slot := -1) -> void`

*server/containers.gd*

Every write to a container passes through here - a player clicking, a hopper, a parcel arriving, a
station consuming its inputs, loot filling a chest, a mod.

`container_changed` is raised from here, so automation is visible: a hopper, a parcel arriving, a
station taking its inputs, loot filling a chest. It used to fire only from the two player-click
handlers.

**Immediate, not deferred.** Deferring it to the end of the tick was tried and it broke the furnace:
lighting when fuel goes in is gameplay and has to happen now. The re-entrancy that made deferring
look necessary was never the engine's problem - a QuickJS runtime cannot be re-entered, and that is
handled in `_invoke` in js_mod.gd, where it belongs. (2026-09-21)

**See also:** `changed`

### `changed(key: String, p = null, slot := -1) -> void`

*server/containers.gd*

The same, for any container: a bag or a shared store has no position to be marked at.

**See also:** `at_key`, `block_key`, `is_block_key`, `position_of`

### `update(delta: float) -> void`

*server/containers.gd*

Sends changed contents to viewers and closes screens players walked away from.

### `block_removed(pos: Vector3i, store: Dictionary, old_block: int, into = null) -> void`

*server/containers.gd*

A container block was removed: close screens and spill the contents.

**See also:** `block_key`, `close`, `drop_item`, `get_item`, `type_of_block`

### `holds_open_bag(p, slot: int) -> bool`

*server/containers.gd*

Whether this inventory slot is the bag the player currently has open.

**See also:** `item_key`

### `click(p, slot: int, button: int, shift: bool) -> void`

*server/containers.gd*

A click on container slot `slot` by a player whose screen shows it. Returns true if handled.

**See also:** `accepts`, `at_key`, `changed`, `clear_slot`, `get_def`, `get_item`

### `quick_move_in(p, slot: int) -> bool`

*server/containers.gd*

Shift-click on a backpack slot while a container is open: move the stack into the container.

**See also:** `accepts`, `at_key`, `changed`, `clear_slot`, `item`, `sync_inventory`

### `announce_rare := true  (property)`

*server/loot.gd*

Set false to stop the engine announcing rare finds (a server that would rather stay quiet).

### `rate := 1.0  (property)`

*server/loot.gd*

Multiplies how many times every pool rolls: a host's "how much loot" setting (see ModApi.set_loot_rate).

### `boosts := {}  (property)`

*server/loot.gd*

Temporary changes on top of `rate`, for events ("double coins this weekend", "pumpkins all October"):
"table:<name>" -> how much more often that table's pools roll, "item:<name>" -> how much more often that
item comes up in any table. Each is {factor, until} where `until` is a unix time, or 0 for no end.

### `register(table_name: String, def: Dictionary) -> void`

*server/loot.gd*

Declares a table. Entries naming an item that does not exist are left out with a warning rather than
dropping nothing at all later.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `extend(table_name: String, def: Dictionary, owner := "") -> void`

*server/loot.gd*

Adds pools to a table another mod owns, without forking it. Unknown tables are created. `owner` is the
mod adding them, so reloading that mod takes its pools away again instead of stacking another copy on
every save.

### `forget(owner: String) -> void`

*server/loot.gd*

Takes back everything a mod added to other mods' tables, for a reload.

**See also:** `path_for`

### `has(table_name: String) -> bool`

*server/loot.gd*

Whether a table is registered under this name. Generated tables (`mob:`, `block:`) only exist once
something has asked for them, so this answers false for a creature nothing has killed yet.

### `roll(table_name: String, context := {}) -> Array`

*server/loot.gd*

Rolls a table. `context` says what the loot came out of, so conditions can look at it:
seed        an int to make the roll repeatable (a chest); left out, the roll is random
player      who caused it (their luck, what they have already found)
cause       "player", "mob", "fire", "fall", … for a mob's death
tool        the item id in the hand that did it
position    where it happened (depth and biome come from this)
Returns [[item id, count, data], …].

**See also:** `awarded`, `factor_for`, `get_time_of_day`

### `preview(table_name: String, context := {}) -> Array`

*server/loot.gd*

Rolls without any of the consequences of actually getting the loot. Use this when the drop might still
be thrown away - a creative player breaking a block, or a handler that may cancel the break - and call
`awarded` once it is really handed over.

**See also:** `factor_for`, `get_time_of_day`

### `awarded(table_name: String, out: Array, context := {}) -> void`

*server/loot.gd*

What getting the loot means for this player: they have now met this table, a long run of bad luck pays
out, and a find worth announcing is announced. Called for you by `roll`; call it yourself after a
`preview` that really happened.

**See also:** `announce_rare_loot`, `is_rare`, `rarest`

### `from_drops(drops: Array) -> Dictionary`

*server/loot.gd*

A mob's or block's `drops` list as a table: [[item, count, chance]] becomes one pool per line, each
rolling once, so an old definition behaves exactly as it did.

### `load_files(mod_id: String, mod_dir: String) -> void`

*server/loot.gd*

Registers every loot/*.json in a mod folder as "<mod>:<file name>", so a creator can tune what drops
without touching code. A file may hold one table, or {"<name>": {table}, …} for several.

**See also:** `open`, `register`

### `table_for_entity(def: Dictionary) -> String`

*server/loot.gd*

The table a mob's or block's drops come from: the one its definition names in `loot`, or one made from
its old `drops` list the first time it is needed (so mods written before tables keep working and still
get conditions, tuning and rare finds). Generated tables are named "mob:<name>" and "block:<name>".

**See also:** `from_drops`

### `table_for_block(block: int, default_drops: Array) -> String`

*server/loot.gd*

The name of the table a block drops from, building it from `default_drops` the first time.

As with `table_for_entity`, the table does not exist until this is called - so anything asking what
a block can drop has to call this first, or the registry will honestly report that it has never
heard of it. (2026-09-22)

**See also:** `from_drops`

### `fill(container, player = null) -> void`

*server/loot.gd*

Fills a container from its `loot` block data, once. `player` is whoever opened it, when known.

A chest whose data says `personal: true` is rolled for each player separately: everyone who opens it
gets their own loot, handed straight to them, so nobody has to race a sibling for the good item. The
chest is then an ordinary chest to keep things in. Any other chest is filled once and shared.

### `set_boost(target: String, factor: float, seconds := 0.0) -> String`

*server/loot.gd*

Makes something more (or less) common for a while: `target` is a table name, an item name, or either
with its "table:"/"item:" prefix; `factor` is how much more often; `seconds` ends it on its own (0: it
stays until changed). Setting the factor back to 1 clears it.

### `factor_for(key: String) -> float`

*server/loot.gd*

What `target` is multiplied by right now, 1.0 when nothing applies. Expired events clear themselves.

### `active_boosts() -> Array`

*server/loot.gd*

Everything a host turned up or down, for the admin screen and /loot: [{target, factor, ends_in}].

**See also:** `factor_for`

### `chance_of(table_name: String, item_id: int) -> float`

*server/loot.gd*

How likely this table is to give `item_id` at all, as 0-1. Used to tell a find worth announcing from
an everyday one, so nothing has to be marked "rare" by hand.
Boosts and the loot rate count here: during a "coal everywhere" event, coal is common, and announcing
every lump of it as a rare find would drown the chat the event is supposed to liven up.

**See also:** `factor_for`

### `sources_of(item_id: int) -> Array`

*server/loot.gd*

Everywhere an item can come from: [{table, kind ("mob" | "block" | "table"), source, chance, count}],
likeliest first. This is what the guide's "what drops this?" is built from, so a player can find out
where something comes from without being told by an adult.

**See also:** `chance_of`, `describe`, `kind_of`, `of_item`

### `sources_index(limit := 3) -> Dictionary`

*server/loot.gd*

Where things come from, small enough to send a client once: {item id: [[source, percent], …]}, at most
a few sources each. The tooltip's "Dropped by" line is built from this.

**See also:** `chance_of`, `describe`

### `kind_of(table_name: String) -> String`

*server/loot.gd*

Whether a table belongs to a mob, a block, or is a table in its own right (a chest, a reward).

### `describe(table_name: String) -> String`

*server/loot.gd*

The name a player would recognise a table by: the mob or block it belongs to, or the table's own name.

**See also:** `kind_of`

### `is_rare(table_name: String, item_id: int) -> bool`

*server/loot.gd*

True when getting this item from this table is a find worth making a fuss about.

**See also:** `chance_of`

### `rarest(table_name: String) -> Dictionary`

*server/loot.gd*

The least likely thing a table can give, as {item, count}: what a run of bad luck eventually pays out.

**See also:** `chance_of`

### `set_accepts(node: Dictionary, filter: Dictionary) -> void`

*server/parcels.gd*

What a face will take. `items` and `tags` name what is allowed; an empty filter takes anything.
`deny` turns it inside out, which is how a mod writes "everything except cobblestone".

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `send(from: Dictionary, item_name: String, count: int, data := {}) -> bool`

*server/parcels.gd*

Sends something from a face to whichever connected face will take it. Returns true if it is on its
way; false if nothing would take it, which is the answer a mod needs to decide whether to keep
holding the thing or to stop trying.

**See also:** `key_name`, `node_key`, `reachable`

### `would_accept(from: Dictionary, item_name: String) -> bool`

*server/parcels.gd*

Whether anything connected to this face would take this item, without sending it.

**See also:** `key_name`, `node_key`, `qualified`, `reachable`, `tag`

### `update(delta: float) -> void`

*server/parcels.gd*

Moves everything in flight along, and delivers what has arrived.

### `in_transit() -> int`

*server/parcels.gd*

How many parcels are in flight, for the dev tools and for tests.


## World generation

### `setup() -> void`

*server/spawners.gd*

Hooks every spawner block up to block ticks (after all mods registered their blocks). One shared
handler table, so a realm added later gets them too.

### `load_saved() -> void`

*server/structure_tools.gd*

Loads templates saved in this world's structures/ folder as "world:<name>".

**See also:** `add_template`, `folder`, `key_name`, `node_key`, `open`, `place`

### `place(template_name: String, at: Vector3i, rotation := 0, into = null) -> bool`

*server/structure_tools.gd*

Places a template now (world edits and block data), corner at `at`.

**See also:** `get_block`, `rotate`, `set_block`, `set_block_authoritative`, `set_block_data`, `start_effect`

### `carvers: Array = []  (property)`

*server/worldgen/biome_generator.gd*

Carvers and other passes: objects with carve(chunk, generator) run after terrain, before features.

### `structures: Structures  (property)`

*server/worldgen/biome_generator.gd*

Templates and structure sets placed after features (see worldgen/structures.gd).

### `freeze() -> void`

*server/worldgen/biome_generator.gd*

Called once every mod has registered its blocks: snapshots block tables for the worker threads.

### `climate(x: int, z: int) -> Dictionary`

*server/worldgen/biome_generator.gd*

{t, h, w, p, c} at a column.

### `weights(c: Dictionary) -> Dictionary`

*server/worldgen/biome_generator.gd*

Blend weights {biome index: weight} for a climate, normalized. Weights are relative to the closest
biome, so every column has a clear winner and borders blend over a short distance.

### `column(x: int, z: int) -> Dictionary`

*server/worldgen/biome_generator.gd*

{biome (index), height} for a column.

**See also:** `climate`, `weights`

### `static resolve(def: Dictionary, block_id: Callable) -> Dictionary`

*server/worldgen/features.gd*

Resolves block names in a data feature to ids. Returns {} if the feature is invalid.

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `add_template(template_name: String, doc: Dictionary) -> bool`

*server/worldgen/structures.gd*

Parses a template dictionary (from JSON). Unknown blocks are skipped. Returns false if invalid.

### `static rotate(p: Vector3i, size: Vector3i, rotation: int) -> Vector3i`

*server/worldgen/structures.gd*

Rotates a local template position (y unchanged) inside a template of `size`.

### `start_for(s: Dictionary, region: Vector2i, gen) -> Dictionary`

*server/worldgen/structures.gd*

The structure a region holds, or {} (cached; safe to call from worker threads).

**See also:** `column`, `rotated_size`, `unlock`

### `place_in_chunk(chunk, gen, writer, data: Dictionary) -> void`

*server/worldgen/structures.gd*

Writes every structure piece that overlaps this chunk. `data` collects block data {Vector3i: dict}.

**See also:** `get_block`, `rotate`, `set_block`, `set_state`, `start_for`

### `static capture(server, lo: Vector3i, hi: Vector3i, keep_air := false) -> Dictionary`

*server/worldgen/structures.gd*

A template dictionary (JSON-ready) from a region of a world. `keep_air`: leave air cells out (the
structure then keeps the terrain there). Block data in the region (chest contents, spawner settings)
goes into `data`.

**See also:** `get_block_data`, `get_block_loaded`, `get_block_state`


## Blocks and the world

### `static make_context(registry, atlas_uv: Dictionary) -> Dictionary`

*client/chunk_mesher.gd*

Builds the read-only context meshing threads need from the registry and atlas.

**See also:** `enabled`, `index`

### `static build(chunks: Array, ctx: Dictionary) -> Array`

*client/chunk_mesher.gd*

`chunks`: 9 PackedByteArrays for the 3x3 neighbourhood, index (dx + 1) + (dz + 1) * 3, empty where
not loaded. Returns [solid_arrays, translucent_arrays, models]; models is a PackedInt32Array of
(block id, x, y, z, sky light, block light) per model block.

**See also:** `add_handler`, `agent_for`, `area_cells`, `at`, `attach`, `body_font`

### `rules := {}  (property)`

*server/area_edits.gd*

Rules a mod registered, name -> Callable(ctx) -> Array[Vector3i].

### `problem := ""  (property)`

*server/area_edits.gd*

Why the last call refused, in words a player can be shown. A selection that silently does nothing
is indistinguishable from a broken tool. (2026-09-21)

### `register_rule(rule_name: String, chooser: Callable) -> void`

*server/area_edits.gd*

Registers a way of choosing cells. The callable is handed the context dictionary the mod passed to
`area_cells` and returns an Array of Vector3i.

### `cells(rule_name: String, ctx: Dictionary) -> Array`

*server/area_edits.gd*

The cells a rule chooses, capped and de-duplicated. Always returns something a caller can loop
over, so a mod never has to check for null.

### `apply(player, cell_list: Array, options := {}) -> Dictionary`

*server/area_edits.gd*

Applies one change to every cell a player is allowed to change.

options: {block (id to set; 0 or absent breaks instead), drops (default true), realm}.

Returns {changed, skipped, refused, reason}. **`skipped` is not a failure** - a selection that
crosses into somebody's garden does the part outside it and says how much it left alone, which is
friendlier than refusing the lot and lets a vein run up to a boundary and stop.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `preview(player, cell_list: Array, options := {}) -> void`

*server/area_edits.gd*

Outlines a selection for one player, before they commit to it. `seconds` 0 leaves it up until the
next call clears it, which is what a tool holding a selection wants.

**See also:** `factor_for`, `get_time_of_day`

### `clear_preview(player) -> void`

*server/area_edits.gd*

Takes the outline away.

**See also:** `preview`

### `realm  (property)`

*server/block_ticks.gd*

The world these blocks are in. Everything here is indexed by chunk coordinate, and every realm has
a chunk (0, 0), so the table has to belong to one world rather than to the server.

### `clock := 0.0  (property)`

*server/block_ticks.gd*

Seconds of simulated world time (persists across restarts).

### `handlers := {}  (property)`

*server/block_ticks.gd*

Block id -> {handler, interval, catch_up}.

### `cost_by_chunk := {}  # Vector2i -> int  (property)`

*server/block_ticks.gd*

Microseconds spent in handlers, by chunk, since it was last read. This is what makes a claim's cost
a measurement rather than a guess: machines are block ticks, and a block tick knows where it is.

### `register(block: int, handler: Callable, options := {}, owner := "engine") -> void`

*server/block_ticks.gd*

options.random: false gives a block a handler for *scheduled* ticks only, and keeps it out of the
per-chunk index of randomly-ticked blocks. That index is also what marks a chunk as one that has to
be saved, so indexing a block as common as water means every chunk with a puddle in it is written
on every save. Liquids are driven entirely by scheduling, so they ask for this. (2026-09-19)

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `schedule(pos: Vector3i, seconds: float, payload := {}) -> void`

*server/block_ticks.gd*

Calls the handler of the block at `pos` after `seconds` (reason "scheduled"). One per position; a
new schedule replaces the old one.

**See also:** `chunk_coord_at`, `index`

### `static scan(blocks: PackedByteArray, ids: PackedInt32Array) -> Dictionary`

*server/block_ticks.gd*

Worker thread: local indices of the given block ids in a chunk's block array.

### `scan_ids() -> Array`

*server/block_ticks.gd*

Block ids the chunk jobs should index: [tickable ids, light-emitting ids].

### `save_chunk(coord: Vector2i)`

*server/block_ticks.gd*

What to save with a chunk (null when nothing).

### `ticking_chunks() -> Array`

*server/block_ticks.gd*

Chunks whose tick state must be saved.

### `update(delta: float, simulated: Dictionary) -> void`

*server/block_ticks.gd*

`simulated` is the set of chunk coordinates close enough to somebody to be run; everything else
that is loaded is left alone. The clock advances either way, so a chunk that comes back is told how
long it was asleep rather than losing the time.

### `light_levels(pos: Vector3i) -> Dictionary`

*server/block_ticks.gd*

{sky, block} light levels (0-15) at a position; sky is not scaled by the time of day.

**See also:** `block_light`, `sky_light`

### `light_at(pos: Vector3i, daylight: float) -> int`

*server/block_ticks.gd*

Light plants and mobs care about: block light or daylight-scaled sky light, whichever is brighter.

### `refresh_around(pos: Vector3i, into = null) -> void`

*server/connect.gd*

Called when a block is placed or broken: fixes up that cell and the four around it.

**See also:** `refresh`

### `refresh(pos: Vector3i, into = null) -> void`

*server/connect.gd*

Puts the right form of a connecting block at `pos`, if what is there is one.

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `explode(center: Vector3, power: float, options := {}) -> Dictionary`

*server/explosions.gd*

options.realm: the world it goes off in (a Realm, or null for the overworld). An explosion is a
thing that happens in a place, and a position alone no longer says where.

**See also:** `blast_resistance`, `break_block`, `cast`, `damage`, `damage_player`, `get_block_v`

### `kinds := {}  (property)`

*server/fields.gd*

Name -> {name, display_name, radius, seconds, tick, condition, effect, affects, except_owner, owner}

### `fields := {}  (property)`

*server/fields.gd*

id -> {id, kind, realm, position, radius, expires, next_tick, level, owner, handle}

### `place(field_name: String, position: Vector3, options := {}) -> int`

*server/fields.gd*

Puts one down. `options`: seconds, radius, level (multiplies damage, heal and the condition's
level), owner (a player or a creature), realm.

**See also:** `get_block`, `rotate`, `set_block`, `set_block_authoritative`, `set_block_data`, `start_effect`

### `at(position: Vector3, realm_id := "") -> Array`

*server/fields.gd*

Every field a point is inside, for a mod that wants to ask rather than be told.

**See also:** `get_block_v`

### `to_saved() -> Array`

*server/fields.gd*

Fields are saved: a village campfire that went out because somebody restarted the server would be a
puzzle rather than a feature. Written as how long is *left*, since server time restarts with it.

### `kinds := {}  (property)`

*server/instances.gd*

Kinds a mod registered: name -> def.

### `live := {}  (property)`

*server/instances.gd*

Instances that exist now: id -> {kind, realm_id, members, empty_since, data}.

### `problem := ""  (property)`

*server/instances.gd*

Why the last call refused, in words somebody can be shown.

### `register(kind_name: String, def: Dictionary) -> bool`

*server/instances.gd*

Declares a kind of instance. `generator` is the terrain (the same object `set_world_generator`
takes); without one the instance is empty air, which is what a mod building its own room wants.

def: {generator, passes, empty_seconds, max_players, display_name}.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `open(kind_name: String, options := {}) -> String`

*server/instances.gd*

Makes one, and returns its id ("" if it could not be made).

options: {seed, data (anything the mod wants to keep with it)}.

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `enter(player, instance_id: String, position: Vector3) -> bool`

*server/instances.gd*

Sends a player in, remembering where they were so `leave` can put them back.

**See also:** `send_to_realm`

### `leave(player) -> bool`

*server/instances.gd*

Puts a player back where they were before they entered. Returns false if they were not in one.

**See also:** `allowed`, `close`, `finish`, `get_block`, `send_to_realm`, `sign`

### `close(instance_id: String) -> bool`

*server/instances.gd*

Closes one now: everybody inside goes back, and the realm is thrown away.

**See also:** `input`, `is_block_key`, `leave`, `player_by_id`, `position_of`, `remove_realm`

### `id_of(player) -> String`

*server/instances.gd*

The instance a player is in, or "".

### `data_of(instance_id: String) -> Dictionary`

*server/instances.gd*

What a mod kept with an instance when it opened it.

### `update(_delta: float) -> void`

*server/instances.gd*

Closes instances that have been empty long enough. Called each tick.

### `kinds := {}  (property)`

*server/liquids.gd*

Block id -> {range, falls, speed, name}

### `meetings := {}  (property)`

*server/liquids.gd*

Two block ids meeting -> the block that forms. Keyed "lower:higher" so the pair is order-free.

### `register(block: int, def: Dictionary) -> void`

*server/liquids.gd*

`shallow` is the block id to use once it has travelled `shallow_from` blocks (0 for none). Both ids
are the same liquid as far as flowing, drying and meeting are concerned.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `register_meeting(a: int, b: int, result: int) -> void`

*server/liquids.gd*

What forms where these two meet. The mod decides; the engine has never heard of obsidian.

### `family_of(block: int) -> int`

*server/liquids.gd*

The deep form of whatever liquid this is, so the two forms are one thing everywhere it matters.

### `block_changed(pos: Vector3i, old: int, block: int) -> void`

*server/liquids.gd*

A block was placed or broken: whatever was flowing near it may now have somewhere to go, or nothing
holding it up.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `step(pos: Vector3i) -> void`

*server/liquids.gd*

One step for the liquid at `pos`. Called from a scheduled block tick.

**See also:** `block`, `block_state`, `box`, `collides`, `family_of`, `get_block`

### `patterns := {}  (property)`

*server/multiblocks.gd*

Name -> {name, owner, cells: [{offset, spec}], controller: Vector3i, size}

### `register(pattern_name: String, def: Dictionary, owner := "engine") -> bool`

*server/multiblocks.gd*

def: layers (bottom first, each a list of rows of characters), key (character -> block name or
"#tag"), controller (which character is the controller; default the first key that matches one cell).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `at(controller_pos: Vector3i, pattern_name := "") -> Dictionary`

*server/multiblocks.gd*

Is a machine of this pattern standing with its controller here? Worked out now rather than looked up.

**See also:** `get_block_v`

### `block_changed(pos: Vector3i, _old: int, _block: int) -> void`

*server/multiblocks.gd*

A block was placed or broken: a machine near it may have just been finished, or just been spoiled.

Every pattern is tried with this block as each of its cells in turn, which is why a pattern is
capped: the work is cells squared, and a machine is a handful of blocks.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `plots := {}  (property)`

*server/plots.gd*

id -> {id, realm, from, to, owner_player, owner_company, name, members: {player_id: true}, open}

### `problem := ""  (property)`

*server/plots.gd*

Why the last claim was refused, in words somebody can be shown.

### `claim(realm_id: String, from: Vector3i, to: Vector3i, options := {}) -> int`

*server/plots.gd*

Marks out a plot. `owner` is a player id, or use `company` for one owned by a group.

**See also:** `coop`

### `at(realm_id: String, pos: Vector3i) -> Dictionary`

*server/plots.gd*

The plot a block is in, or {}.

**See also:** `get_block_v`

### `add_member(id: int, player_id: String) -> bool`

*server/plots.gd*

Lets somebody else build here. A plot owned by a company already admits its members.

### `may_build(player, realm_id: String, pos: Vector3i) -> bool`

*server/plots.gd*

Whether this player may change a block here. Everything outside a plot is allowed: the engine does
not decide that the world is closed by default, because most of it is not anybody's.

**See also:** `at`, `may_build_in`, `qualified`

### `of_player(player_id: String) -> Array`

*server/plots.gd*

Every plot somebody has a say in, for a screen or a command.

**See also:** `is_member`, `rank_of`

### `id := ""  (property)`

*server/realm.gd*

What a mod called it ("overworld", "mymod:emberdeep"). The overworld's name is "" for the world a
server has always had, so a save written before realms existed is still where it was.

### `ephemeral := false  (property)`

*server/realm.gd*

An instance's realm: made on demand, thrown away when it empties. Never written to disk, so a
dungeon run leaves no folder behind and a crash mid-run leaves nothing to clean up. (2026-09-21)

### `generator = null  (property)`

*server/realm.gd*

Set once the mods have run: the terrain this realm is made of. Realms differ mostly by this, and it
is what a chunk job is handed. A mod supplies it with set_world_generator, or asks for the engine's
biome generator, which is then usually - but not always - the same object.

### `biome_generator = null  (property)`

*server/realm.gd*

The engine biome generator, if this realm uses one. **Not** the same field as `generator`: a game can
use its own world generator and still want biomes for spawning and for "what biome am I in", which
is why conflating the two broke chunk generation for the games that do. (2026-09-19)

**See also:** `block`, `qualified`, `register_instance`

### `block_ticks: BlockTicks  (property)`

*server/realm.gd*

Blocks that change over time in this realm, and the light it is lit by. One per realm rather than
one per server, because everything in it is indexed by chunk coordinate and every realm has a
chunk (0, 0) - a single table would have the Emberdeep's furnaces and the overworld's sharing a key.

### `signals: Signals  (property)`

*server/realm.gd*

Levels spreading from block to block in this realm (see engine/server/signals.gd). Per realm for
the same reason as everything else here: a position alone does not say which world.

### `liquids: Liquids  (property)`

*server/realm.gd*

Liquids flowing in this realm (see engine/server/liquids.gd).

### `multiblocks: Multiblocks  (property)`

*server/realm.gd*

Machines assembled out of blocks (see engine/server/multiblocks.gd).

### `block_data := {}  # Vector2i chunk -> {Vector3i: Dictionary}  (property)`

*server/realm.gd*

Blocks that differ from freshly generated terrain, and which chunks still need writing.

### `deltas := {}  # Vector2i chunk -> {local index: block id}  (property)`

*server/realm.gd*

Delta persistence: what each chunk's terrain was when generated, and how it differs now.

### `save_queue := {}  # Vector2i chunk -> true  (property)`

*server/realm.gd*

Chunks waiting to be serialized, and chunks being loaded or generated on a worker thread. Both are
per realm for the same reason as block_ticks: the coordinate alone does not say which world.

### `entity_chunks := {}  # Vector2i chunk -> true  (property)`

*server/realm.gd*

Chunks whose saved file lists persistent creatures; resaved so ones that walked away are dropped.

### `save_dir := ""  (property)`

*server/realm.gd*

Where this realm's chunks live. The overworld keeps the folder it always had; every other realm gets
one of its own beside it, so an old save is still a valid new save.

### `simulated := {}  # Vector2i chunk -> true  (property)`

*server/realm.gd*

Chunks close enough to somebody to be run. Everything else that is loaded is still there - a player
can still see it, it is still saved - it simply does not tick. Empty means the realm is asleep: its
clock keeps running and nothing in it does, which is what makes it cheap for a mod to register five
realms nobody is standing in. (2026-09-19, and see docs/roadmap.md "How much of the world is running")

### `attach() -> void`

*server/realm.gd*

Built after the realm is in place rather than inside _init, because the creatures reach back through
the server for the world they are standing in - and during _init the server does not yet know this
realm exists, so it would hand them somebody else's.

**See also:** `config_for`

### `is_awake() -> bool`

*server/realm.gd*

Whether anything in this realm should be run this tick. A claim on a chunk (keeping a machine going
after its owner leaves) will wake a realm too, which is why this asks about the simulated set rather
than counting players.

### `is_overworld() -> bool`

*server/realm.gd*

Whether this is the world a server has always had. Kept as a question rather than a comparison
scattered about, because "" meaning the overworld is a compatibility decision and not an obvious one.

### `block_state(pos: Vector3i) -> int`

*server/realm.gd*

The block state (its rotation, its stage, whatever the block means by it) at a position in *this*
world. On the realm rather than the server because a position alone does not say which world.

**See also:** `chunk_coord_at`, `index`

### `set_storage(world_dir: String) -> void`

*server/realm.gd*

Decides where this realm keeps its chunks, under the world's folder, and makes the folder.

The overworld keeps `<world>/chunks`, which is the folder every save already has; every other realm
gets `<world>/realms/<id>/chunks` beside it. That is the whole of why the overworld's id is "": a
world written before realms existed is still a valid world afterwards, with no migration.

**See also:** `is_overworld`

### `chunk_path(coord: Vector2i) -> String`

*server/realm.gd*

`<save dir>/chunks/x_z.json`.

### `shape_lut := PackedByteArray()  (property)`

*shared/block_registry.gd*

Which shape each block fills its cell with (Shape); FULL for almost everything.

### `hazard_lut := PackedByteArray()  (property)`

*shared/block_registry.gd*

Blocks mobs never path into or onto (e.g. lava, spikes). Server-side only.

### `register(def: Dictionary, replace := false) -> int`

*shared/block_registry.gd*

Server-only keys: drops, hazard, support ("solid" or [block names] the block must stand on; it breaks
when that block goes away and cannot be placed elsewhere).
Definition keys: name, display_name, render ("opaque" | "cutout" | "translucent" | "invisible" | "plant"),
solid, liquid, cull_same, breakable, placeable, textures as a String (all faces), a Dictionary
{all, side, top, bottom} or an Array of 6 names, light (0-15 emitted), interactive (right-click
fires block_interact instead of placing), model (glTF asset name, with render "model"),
orientation ("none" | "horizontal": the block state stores a facing 0-3 set on placement so the
model faces the player), connect_group and model_arm (a model with an arm is centred on the block
and draws the arm toward each neighbour sharing its connect_group, e.g. cables into machines).
Returns the id, or -1 on error.
`replace`: an existing block of that name gets the new definition in place (same id; mod reloads).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `static facing_from_yaw(yaw: float) -> int`

*shared/block_registry.gd*

Facing (0-3) for a horizontally oriented block placed by a player looking along `yaw`: the block's
front (+Z in model space) turns toward the player.

**See also:** `block`

### `static facing_direction(facing: int) -> Vector3i`

*shared/block_registry.gd*

Direction the front of a block with this facing points to.

### `id_of(block_name: String) -> int`

*shared/block_registry.gd*

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid(id: int) -> bool`

*shared/block_registry.gd*

Whether anything is registered under this id.

### `display_name(id: int) -> String`

*shared/block_registry.gd*

The name to show a player, or "?" for an id nothing registered. Display names are safe to change;
ids are not, because saves are written by name and ids shift whenever anything is added.

### `static expand_textures(value) -> Array`

*shared/block_registry.gd*

A mod's `textures` normalised to one asset name per face, always six, in face order.

A mod may write one name for every face, `{all, side, top, bottom}`, or all six. Use this rather
than reading the value a mod wrote - three of those four shapes are not an Array, and code that
assumes the sixth-element form gets a block with no texture rather than an error.

### `to_network() -> Array`

*shared/block_registry.gd*

The block table as the client receives it, trimmed to `NETWORK_FIELDS`. Sent once on joining.

### `load_network(data) -> bool`

*shared/block_registry.gd*

Rebuilds this (fresh) registry from server data. Returns false if the data is malformed.

### `static boxes_of(block: int, shapes: PackedByteArray) -> Array`

*shared/block_shapes.gd*

The boxes a block fills, or the whole cell when it has no shape of its own.

### `static overlaps(position: Vector3, half_width: float, height: float, world, solid: PackedByteArray, shapes: PackedByteArray) -> bool`

*shared/block_shapes.gd*

True when the box at `position` overlaps any solid block.

**See also:** `boxes_of`, `get_block`

### `static sweep(position: Vector3, half_width: float, height: float, axis: int, delta: float, world, solid: PackedByteArray, shapes: PackedByteArray) -> Dictionary`

*shared/block_shapes.gd*

Moves the box along one axis as far as the blocks allow. Returns the distance actually travelled;
`hit` is true when something stopped it short.

**See also:** `boxes_of`, `get_block`, `move`, `prune`

### `static step_target(position: Vector3, half_width: float, height: float, direction: Vector3, world, solid: PackedByteArray, shapes: PackedByteArray, reach := STEP_HEIGHT) -> float`

*shared/block_shapes.gd*

The highest surface under the box within `reach`, or -INF: where a step up would put the feet.

**See also:** `boxes_of`, `get_block`, `overlaps`

### `states := {}  (property)`

*shared/chunk.gd*

Sparse block states: local index -> state (1..255). Missing means 0.

### `dirty := false  (property)`

*shared/chunk.gd*

Server only: modified since last save.

### `generated_data := {}  (property)`

*shared/chunk.gd*

Server only: block data written by world generation (structure chests, spawners): Vector3i -> Dictionary.

### `static contains(blocks: PackedByteArray, id: int) -> bool`

*shared/chunk.gd*

True if any cell holds `id`. Uses a native byte search, then confirms the id at cell boundaries.

### `encode_states() -> PackedInt32Array`

*shared/chunk.gd*

[index, state, index, state, ...] for the network.

### `static decode_blocks(payload: PackedByteArray) -> PackedByteArray`

*shared/chunk.gd*

Returns an empty array if the payload is malformed.

### `static content_id(kind: String, category: String, payload: PackedByteArray) -> String`

*shared/creations.gd*

The id for a creation's content.

**See also:** `finish`, `start`

### `static make(kind: String, category: String, payload: PackedByteArray, name: String, author := "", author_name := "", extra := {}) -> Dictionary`

*shared/creations.gd*

Builds a manifest for new content (the id comes from the payload).

**See also:** `content_id`, `finish`, `key_id`, `sign`, `start`

### `static validate(manifest, payload: PackedByteArray) -> Dictionary`

*shared/creations.gd*

Checks a manifest and its payload. Returns {ok, error, manifest (cleaned), info} where info carries
what was measured (triangles, texture sizes, box count).

**See also:** `check_files`, `check_manifest`, `check_references`, `check_scripts`, `check_structures`, `check_unused_files`

### `static measure_model(bytes: PackedByteArray) -> Dictionary`

*shared/creations.gd*

Triangles and the largest texture in a GLB, or {error}.

### `static to_cosmetic(manifest: Dictionary, payload: PackedByteArray) -> Dictionary`

*shared/creations.gd*

The cosmetic definition that draws a creation. `asset` is the texture or model asset name clients load
(by default the id itself).

**See also:** `asset_name`

### `static cast(world, targetable: PackedByteArray, origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary`

*shared/voxel_raycast.gd*

`targetable` is BlockRegistry.targetable_lut. Returns {hit, position, normal, block}.

**See also:** `get_block`


## Items, crafting and recipes

### `station := {}  (property)`

*client/crafting_screen.gd*

{name ("" = by hand), title, position}

### `stock := {}  (property)`

*client/crafting_screen.gd*

Items the station can draw from nearby chests: {item id: count}.

### `processes := {}  (property)`

*client/crafting_screen.gd*

Smelting and other processes for lookups: {kind: {input id: {output, count, seconds}}}.

### `stations := {}  (property)`

*client/crafting_screen.gd*

Every station's titles, tiers and upgrades (from the server) to explain recipe requirements.

### `icons  (property)`

*client/crafting_screen.gd*

ItemIcons (composed icons for parts and built tools); set by the client.

### `session := {}  (property)`

*client/crafting_screen.gd*

The shared state at this station: {players, tray, jobs, project, owner, speedup}.

### `known := {}  (property)`

*client/crafting_screen.gd*

Recipe ids this player has discovered, and whether the server uses discovery at all.

### `minigames := {}  (property)`

*client/crafting_screen.gd*

Crafting minigames by name (from the server) and the player's relaxed-timing choice.

### `assembly := Assembly.new()  (property)`

*client/crafting_screen.gd*

Materials, parts and tools built from parts (shared definitions from the server).

### `set_experiment_result(result: Dictionary) -> void`

*client/crafting_screen.gd*

Shows what an experiment did: the discovered or known result, or a hint.

**See also:** `area_cells`, `at_station`, `box_mesh`, `count_of`, `craftable_times`, `icon_of`

### `open(station_info: Dictionary, station_stock: Dictionary) -> void`

*client/crafting_screen.gd*

Opens (or refreshes) the book for a station and its stock.

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `show_lookup(item: int, mode: String) -> void`

*client/crafting_screen.gd*

Filters the book to recipes making (`mode` "make") or using ("use") an item; item 0 clears.

**See also:** `at_station`, `count_of`, `craftable_times`, `in_category`, `is_blocked`, `is_builtin`

### `craftable_times(index: int) -> int`

*client/crafting_screen.gd*

How many times a recipe could be crafted now (999 in creative).

**See also:** `at_station`, `count_of`, `crafting_stock`, `get_block_v`, `get_eye_position`, `have`

### `have_all(index: int) -> bool`

*client/crafting_screen.gd*

Whether you hold every ingredient (ignoring where the recipe must be crafted).

**See also:** `have`

### `requirement_text(r: Dictionary) -> String`

*client/crafting_screen.gd*

What a recipe needs, in words: "Needs a Sturdy Workbench with Metalwork (an Anvil nearby)".

**See also:** `station_title`

### `set_session(view: Dictionary) -> void`

*client/crafting_screen.gd*

Applies a station session update; rebuilds the co-op panel only when more than progress changed.

**See also:** `at_station`, `count_of`, `craftable_times`, `have`, `heading`, `icon_of`

### `static station_title(station_name: String) -> String`

*client/crafting_screen.gd*

Short text for a station name ("crafting_table" -> "Crafting Table").

### `stat_preview(item: int) -> PackedStringArray`

*client/crafting_screen.gd*

BBCode lines describing an item and how it compares to what you hold (tools, weapons) or wear (armor).

**See also:** `equipment_index`, `get_def`, `selected_item`

### `icons  (property)`

*client/inventory_screen.gd*

ItemIcons (composed icons for stacks built from parts); set by the client.

### `container := {}  (property)`

*client/inventory_screen.gd*

The open container ({} when none): {title, size, groups, bars, slots, data, progress}.

### `set_container(view: Dictionary) -> void`

*client/inventory_screen.gd*

Shows a container above the inventory (or hides it with {}).

**See also:** `refresh`

### `update_container(view: Dictionary) -> void`

*client/inventory_screen.gd*

Applies {slots, data, progress} for the open container.

**See also:** `merge`, `refresh`

### `build_equipment(slot_defs: Array) -> void`

*client/inventory_screen.gd*

Builds one slot per equipment slot the server defined (called once content is known).

### `partner_event(action: String, t: float, arg: int) -> void`

*client/minigame_screen.gd*

The partner's input (team games).

**See also:** `rate_strike`

### `assemblies := {}  (property)`

*server/assemblies.gd*

id -> {realm, origin (Vector3i the cells are relative to), offset (Vector3), cells, riders}

### `problem := ""  (property)`

*server/assemblies.gd*

Why the last lift or settle was refused, in words a player can be shown.

### `lift(realm_id: String, positions: Array, options := {}) -> int`

*server/assemblies.gd*

Takes a set of world positions out of the world and holds them as one moving thing. Returns the
assembly id, or 0 with the reason in `problem`.

**See also:** `block_state`, `get_block_data`, `get_block_v`, `set_block_authoritative`, `tell_assembly`

### `move(id: int, by: Vector3) -> bool`

*server/assemblies.gd*

Moves it, and carries whoever is standing on it. `by` is in blocks and may be fractional - that is
the whole point of being off the grid.

**See also:** `realm_of`, `teleport`, `tell_assembly_moved`

### `settle(id: int) -> bool`

*server/assemblies.gd*

Puts it back into the world at wherever it has got to, and stops being an assembly.

Refused if anything solid is in the way. Forcing it would mean deleting whatever was there, and an
engine that destroys what somebody built because a machine arrived is not one to build with.

**See also:** `describe`, `drive_changed`, `get_block_v`, `node_of`, `qualified`, `reachable`

### `cancel(id: int) -> bool`

*server/assemblies.gd*

Puts an assembly back exactly where it was lifted from, for a mod that wants to give up cleanly.

**See also:** `broadcast_player_event`, `cancel_task`, `settle`

### `config_of(item: int) -> Dictionary`

*server/charging.gd*

Whether this item is held rather than clicked.

**See also:** `config`, `get_def`

### `start(p, item: int) -> bool`

*server/charging.gd*

Begins a draw. Returns false when the item is not a charging one or a mod refused it.

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `release(p) -> void`

*server/charging.gd*

Let go. Fires item_released when it was held long enough, and tells everyone the draw is over either way.

**See also:** `broadcast_player_event`, `config_of`, `look_direction`

### `cancel(p) -> void`

*server/charging.gd*

Drops the draw without firing: the item left their hand, or they died holding it.

**See also:** `broadcast_player_event`, `cancel_task`, `settle`

### `update(p) -> void`

*server/charging.gd*

Called every tick: a draw belongs to the item that started it, so swapping slots or losing the item
lets it go rather than leaving a player drawing something they are no longer holding.

### `experiment(p, grid: Array) -> Dictionary`

*server/experiments.gd*

`grid`: 9 item ids (0 = empty), row by row. Returns {status: "discovered" | "known" | "blueprint" |
"close" | "nothing" | "invalid", recipe (index or -1), hint}.

**See also:** `count_of`, `get_block_v`, `get_eye_position`, `knows_recipe`, `learn_recipe`, `play_sound_to`

### `kinds := {}  (property)`

*server/modifiers.gd*

Name -> {name, display_name, max_level, per_level, applies_to, owner}

### `allows(modifier_name: String, item_name: String) -> bool`

*server/modifiers.gd*

Whether this mark may go on this item.

### `level_of(item_data: Dictionary, modifier_name: String) -> int`

*server/modifiers.gd*

The level of a mark on an item, or 0.

**See also:** `level_for`, `qualified`, `value_of`

### `marks_on(item_data: Dictionary) -> Array`

*server/modifiers.gd*

Every mark on an item, as [{name, level, display_name}].

### `apply(item_data: Dictionary, item_name: String, modifier_name: String, level: int) -> Dictionary`

*server/modifiers.gd*

Puts a mark on an item, returning the new item data. `level` 0 takes it off again.

Returns the data unchanged if the mark does not exist or does not belong on that item, so a mod
calling this with something silly gets an item back rather than a broken one.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `time_override := -1.0  (property)`

*server/skill_crafting.gd*

Tests set this to control the clock (seconds); < 0 uses real time.

### `start(p, product: Dictionary, assist := false, with_partner := false) -> int`

*server/skill_crafting.gd*

Starts crafting by hand. product: {recipe: index} or {assembly: name, slots: [backpack slot per
assembly slot]}. Returns the game id, or 0 if it could not start.

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `invites_at(pos: Vector3i) -> Array`

*server/skill_crafting.gd*

Invitations waiting at a station: [{id, by_name, title}].

### `join(p, game_id: int) -> bool`

*server/skill_crafting.gd*

Joins a waiting team game as the bellows.

### `start_alone(p) -> void`

*server/skill_crafting.gd*

Starts a waiting team game without a partner.

**See also:** `game_of`, `mark`, `now`, `role_of`

### `input(p, action: String, t: float, arg := 0) -> void`

*server/skill_crafting.gd*

An input from a player: "strike", "hold" (arg 1 pressed / 0 released), "key" (arg = direction
index) or "quit". `t` is the game time the client saw.

**See also:** `complete`, `finish`, `game_of`, `now`, `peer_rtt`, `role_of`

### `finish(g: Dictionary) -> void`

*server/skill_crafting.gd*

Ends the game: scores it, gives the item with its quality and tells the players.

**See also:** `apply_quality`, `give_crafted`, `mark`, `quality_for`, `score`, `time_limit`

### `apply_quality(item: int, data: Dictionary, quality: Dictionary, names: Array) -> Dictionary`

*server/skill_crafting.gd*

Quality raises durability, tool speed, weapon damage and armor, renames the item and credits the
makers. Standard leaves the item unchanged.

**See also:** `get_def`, `max_durability`, `tool_of`, `weapon_of`

### `coop(pos: Vector3i) -> Dictionary`

*server/station_sessions.gd*

The co-op state of a station: {owner, owner_name, owner_team, tray: [...], jobs: [...], project: {}}.

**See also:** `get_block_data`, `set_block_data`

### `claim(pos: Vector3i, p) -> void`

*server/station_sessions.gd*

Records who placed a station (they own its tray).

**See also:** `coop`

### `static speedup(helpers: int, station_speed: float) -> float`

*server/station_sessions.gd*

How much faster timed crafts go with `helpers` players present.

### `deposit(p, pos: Vector3i, slot: int) -> bool`

*server/station_sessions.gd*

Moves the stack in a backpack slot into the tray. Returns true if anything moved.

**See also:** `clear_slot`, `coop`, `max_stack`, `sync_inventory`

### `usable_tray(p, pos: Vector3i) -> Dictionary`

*server/station_sessions.gd*

Tray items this player may use: {item id: count}.

**See also:** `coop`, `may_take`

### `consume_tray(p, pos: Vector3i, item: int, count: int) -> int`

*server/station_sessions.gd*

Removes up to `count` of an item from the tray stacks the player may use. Returns how many.

**See also:** `coop`, `may_take`

### `contribute(p, pos: Vector3i) -> int`

*server/station_sessions.gd*

Delivers whatever the project still needs from the player's inventory. Returns items delivered.

**See also:** `broadcast_chat`, `coop`, `count_of`, `drop_item`, `index_of`, `play_effect`

### `view(pos: Vector3i) -> Dictionary`

*server/station_sessions.gd*

What session members see: players and the recipes they look at, tray, jobs with speed, project.

**See also:** `coop`, `index_of`, `invites_at`, `members`, `merge`, `project_fraction`

### `station_of_block(block: int) -> String`

*server/stations.gd*

Station name of a block: from a registered station's tiers or multiblock core, or the block's own
`station` key. "" when the block is not a station.

### `evaluate(pos: Vector3i) -> Dictionary`

*server/stations.gd*

Everything about the station at a position: {name, title, tier, tier_title, features, speed,
quality, pull_radius, hints, detected: [...], available: [...], next: {...}, structure: {...}}.

**See also:** `apply_condition`, `damage`, `damage_player`, `get_block_v`, `heal`, `station_of_block`

### `static usable(info: Dictionary) -> bool`

*server/stations.gd*

Whether the station is usable: multiblock stations must be complete.

### `structure_missing(core_pos: Vector3i, m: Dictionary) -> Array`

*server/stations.gd*

The best rotation's missing blocks as [[position, block id], ...] (empty when the structure is
complete). The core is the block at "C".

**See also:** `close`, `get_block_loaded`, `open`

### `upgrade(p, pos: Vector3i) -> bool`

*server/stations.gd*

Uses the next tier's kit from the player's inventory on the station. Returns true if it upgraded.

**See also:** `evaluate`, `get_block_state`, `play_effect`, `play_sound_at`, `realm_of`, `set_block_authoritative`

### `to_network() -> Dictionary`

*server/stations.gd*

For clients: every station's titles, tiers, upgrades and structure so recipe requirements can be
explained anywhere.

### `part_data(part_name: String, material_name: String) -> Dictionary`

*shared/assembly.gd*

Item data for a part made of a material.

### `build(assembly_name: String, chosen: Dictionary) -> Dictionary`

*shared/assembly.gd*

The finished tool's item data from {slot name: material name}, or {} if something is invalid.

**See also:** `add_handler`, `agent_for`, `area_cells`, `at`, `attach`, `body_font`

### `creative := false  (property)`

*shared/inventory.gd*

Creative players place without consuming and do not collect drops.

### `equipment_slots: PackedStringArray = []  (property)`

*shared/inventory.gd*

Names of the equipment slots after the backpack (index SIZE + i).

### `total() -> int`

*shared/inventory.gd*

Total slots including equipment.

### `selected_block() -> int`

*shared/inventory.gd*

The selected item if it is a block, else 0.

**See also:** `selected_item`

### `consume_selected() -> void`

*shared/inventory.gd*

Consumes one item from the selected slot (no-op in creative).

**See also:** `clear_slot`

### `add(id: int, count: int, max_stack := MAX_STACK, item_data := {}) -> int`

*shared/inventory.gd*

Adds to matching stacks first, then to empty slots (hotbar before the main inventory). Items with
data only merge with stacks carrying identical data. Returns how many items did not fit.

### `space_for(id: int, max_stack := MAX_STACK, item_data := {}) -> int`

*shared/inventory.gd*

How many of an item would fit (without changing anything).

**See also:** `available`

### `remove(id: int, count: int) -> bool`

*shared/inventory.gd*

Removes `count` items of `id` if available (any data). Returns false (and removes nothing) otherwise.

### `click(slot: int, button: int, shift: bool, max_stack_of: Callable, accepts := Callable()) -> bool`

*shared/inventory.gd*

Inventory screen click on `slot` with the mouse `button` (1 = left, 2 = right):
left picks up / puts down / merges / swaps whole stacks, right picks up half or puts down one.
`shift` moves the stack between the hotbar and the main inventory, or into and out of equipment.
`max_stack_of(id)` gives stack limits; `accepts(slot_index, id)` says whether an equipment slot
takes an item (backpack slots take anything). Returns true if anything changed.

**See also:** `accepts`, `at_key`, `changed`, `clear_slot`, `get_def`, `get_item`

### `to_packed() -> PackedInt32Array`

*shared/inventory.gd*

[ids..., counts..., cursor id, cursor count] for every slot including equipment.

### `data_to_network() -> Dictionary`

*shared/inventory.gd*

Item data for the network: {slot index: Dictionary} for slots that have data, cursor as -1.

**See also:** `to_packed`, `total`

### `load_packed(packed: PackedInt32Array) -> bool`

*shared/inventory.gd*

Reads what to_packed() wrote: ids then counts, optionally followed by the held cursor stack. The
length has to match this inventory exactly, which is what makes a mismatch a refusal rather than a
silently half-filled backpack.

**See also:** `total`

### `load_network_data(network: Dictionary) -> void`

*shared/inventory.gd*

Client side: applies data from data_to_network, rejecting anything malformed or oversized.

**See also:** `total`

### `slots: Array[Dictionary] = []  (property)`

*shared/item_registry.gd*

Equipment slots in inventory order: {name, display_name}.

### `static is_block_item(id: int) -> bool`

*shared/item_registry.gd*

Whether an id is a block rather than a registered item. Every block is also an item, and block ids
run below `FIRST_ITEM` while item ids start there.

**See also:** `attack_damage`, `max_stack`, `place`, `sweep`

### `register(def: Dictionary, replace := false) -> int`

*shared/item_registry.gd*

def keys:
name, display_name, icon (asset name), max_stack (default 64; 1 for items with durability)
usable: right-click fires item_use
charge: {seconds, minimum, sound, cancel_on_switch} hold use to draw it; releasing fires
item_released with how far it got (see engine/server/charging.gd)
durability: uses before it breaks (0 = never); wear is stored in item data as `damage`
tool: {type: "pickaxe" | "axe" | "shovel" | any mod type, tier, speed}
weapon: {damage, cooldown, reach, crit_chance, knockback, sweep (fraction dealt to nearby mobs)}
armor: {armor, toughness, knockback_resistance}
equip_slot: equipment slot it goes in ("head", "chest", ...; mods can register more)
modifiers: [{stat, amount, op}] applied while equipped, or while held for tools and weapons
model: glTF asset for held rendering; lore: tooltip lines
armor_texture: worn look in the 64x64 skin layout (the slot picks which regions show)
glow: {color, energy, light} emissive glow when held or worn (light: radius in blocks, 0 = none)
trail: {color, width, seconds} a ribbon behind the item while swinging; width is the part of the
item it covers, from the tip (0.1-1, default 0.5)
effects: {swing, hit, use, held, break} effect names: on swings, on hits (at the target), on use,
continuously while held, and when it wears out
Item data may also override durability, tool and weapon (see tool_of), and set icon_layers:
[{sprite (asset), color}] to draw the stack's icon from tinted layers (tools built from parts).
teaches: [recipe ids] a blueprint: using it teaches those recipes and uses it up (item data
`teaches` works too, so one generic blueprint item can carry any recipe)
Item data may override glow, trail and effects per stack (e.g. a sword that glows as it levels).
attack_damage (legacy shorthand for weapon.damage)
Returns the item id or -1.
`replace`: an existing item of that name gets the new definition in place (same id; mod reloads).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `register_slot(def: Dictionary) -> int`

*shared/item_registry.gd*

def: name, display_name. Items whose equip_slot matches go in it (the offhand takes anything).

**See also:** `slot_index`

### `slot_index(slot_name: String) -> int`

*shared/item_registry.gd*

Where a named equipment slot sits in `slots`, or -1 if there is no such slot.

### `slot_names() -> PackedStringArray`

*shared/item_registry.gd*

Every equipment slot's name, in the order they were registered.

### `register_stat(stat_name: String, base: float) -> void`

*shared/item_registry.gd*

Declares a stat and the value it has before any modifier applies. First registration wins, so a mod
cannot change the base another mod set.

**See also:** `can_see_target`, `health_fraction`

### `fits_slot(id: int, slot_name: String) -> bool`

*shared/item_registry.gd*

Whether an item may be placed in the named equipment slot. The offhand takes anything.

**See also:** `get_def`

### `id_of(item_name: String) -> int`

*shared/item_registry.gd*

Resolves block or item names.

### `is_valid(id: int) -> bool`

*shared/item_registry.gd*

Whether anything is registered under this id, block or item.

### `get_def(id: int) -> Dictionary`

*shared/item_registry.gd*

An item's definition, or `{}` for a block id or an id nothing registered. Blocks keep their
definitions in `BlockRegistry`, so this answers `{}` for them rather than failing.

### `name_of(id: int) -> String`

*shared/item_registry.gd*

The internal name (`mod:thing`), for blocks and items alike. This is what saves are written with,
because ids shift whenever anything is added and names do not.

### `display_name(id: int) -> String`

*shared/item_registry.gd*

The name to show a player. Safe to change at any time, unlike the internal name.

### `max_stack(id: int) -> int`

*shared/item_registry.gd*

How many fit in one slot. Blocks are always 64; an item says so in its definition, and anything with
durability normally says 1.

**See also:** `get_def`

### `max_durability(id: int, item_data := {}) -> int`

*shared/item_registry.gd*

Item data may override `durability`, `tool` and `weapon` per stack (tools built from parts).

**See also:** `get_def`

### `tool_of(id: int, item_data := {}) -> Dictionary`

*shared/item_registry.gd*

The tool stats in force for this particular stack: `{type, tier, speed}`, or `{}` if it is not a tool.

**Per-stack data wins over the definition**, which is what makes a tool built from parts possible -
two stacks of the same item can mine at different speeds. Read this rather than `get_def(id).tool`,
or a part-built tool silently reports the stats of the plain one.

**See also:** `get_def`

### `weapon_of(id: int, item_data := {}) -> Dictionary`

*shared/item_registry.gd*

The weapon stats in force for this particular stack: `{damage, cooldown, reach, crit_chance,
knockback, sweep}`, or `{}` if it is not a weapon. Per-stack data wins, as with `tool_of`.

**See also:** `get_def`, `item`

### `attack_damage(id: int, item_data := {}) -> float`

*shared/item_registry.gd*

Damage dealt when attacking while holding this item (bare hand and blocks: 1).

**See also:** `heal`, `weapon_of`

### `static clean_food(value) -> Dictionary`

*shared/item_registry.gd*

food: {hunger (points, 20 = full), saturation, eat_time (seconds holding use), always (edible when
full), heal (health), remainder (item left over, e.g. a bottle), color (crumbs), style ("plate":
served on a plate, "hand": eaten from the hand, "drink": swigged from the item), sound (played per
bite or gulp; default engine:munch or engine:gulp), effects: [{stat, amount, op, seconds, chance, message}]}.

### `is_usable(id: int) -> bool`

*shared/item_registry.gd*

Whether right-clicking with it fires `item_use`.

**See also:** `get_def`

### `icon_of(id: int) -> String`

*shared/item_registry.gd*

Texture asset for inventory icons.

**See also:** `get_def`

### `to_network() -> Array`

*shared/item_registry.gd*

The item table as the client receives it. Sent once on joining, so the client can name and draw
everything without the server being asked again.

### `load_network(data, slot_data = null, stat_data = null) -> bool`

*shared/item_registry.gd*

Rebuilds the table on the client from what the server sent. False when the data is not the shape we
expect, which is refused at the door rather than half-loaded.

### `visuals(id: int, item_data := {}) -> Dictionary`

*shared/item_registry.gd*

The look of one stack: {glow, trail, effects} from the definition, overridden by item data.

**See also:** `clean_effects`, `clean_glow`, `clean_trail`, `get_def`, `merge`

### `static clean_glow(value) -> Dictionary`

*shared/item_registry.gd*

A mod's `glow` normalised: `{color, energy 0-8, light 0-16}`, or `{}` if there is none.

Use this rather than reading the dictionary a mod wrote. The clamps are the point - an item asking
for a light level of 400 is a mod bug, not a reason for the world to light up.

### `static clean_trail(value) -> Dictionary`

*shared/item_registry.gd*

A mod's `trail` normalised: `{color, width 0.1-1, seconds 0.05-1}`, or `{}` if there is none.

### `static clean_effects(value) -> Dictionary`

*shared/item_registry.gd*

A mod's `effects` normalised to the hooks the engine actually plays (`EFFECT_HOOKS`), with anything
else dropped. An effect named under a hook nobody fires is a quiet nothing, so this is where it goes.

### `static clean_modifiers(list) -> Array`

*shared/item_registry.gd*

A mod's stat modifiers normalised: `[{stat, amount, op}]`, `op` either "add" or "multiply", capped at
sixteen. Anything without a `stat` name is dropped rather than carried as a half-modifier.

### `static time_limit(g: Dictionary) -> float`

*shared/minigame.gd*

Seconds after which the game ends even without more input.

**See also:** `speed`, `window`

### `static complete(g: Dictionary, t: float) -> bool`

*shared/minigame.gd*

Whether the game has everything it needs (all strikes, prompts or the full duration).

**See also:** `sequence_progress`

### `static marker(g: Dictionary, t: float) -> float`

*shared/minigame.gd*

Marker position 0..1 at time t (sweeping back and forth, faster as the work cools).

**See also:** `speed`

### `static zone_width(g: Dictionary, i: int, t := -1.0) -> float`

*shared/minigame.gd*

Zone width for strike i (narrower each strike; the station's quality bonus widens it).

**See also:** `heat`

### `static heat(g: Dictionary, t: float) -> float`

*shared/minigame.gd*

Solo with `cool`: 1 falling to 0. Team: simulated from the bellows' presses and releases.

### `static rate_strike(g: Dictionary, i: int, t: float) -> Dictionary`

*shared/minigame.gd*

{grade: "perfect" | "good" | "miss" | "burnt", score, synced} for strike i at time t.

**See also:** `heat`, `zone_center`, `zone_width`

### `static band_center(g: Dictionary, t: float) -> float`

*shared/minigame.gd*

The band's center at time t (drifts slowly).

### `static gauge(g: Dictionary, t: float) -> float`

*shared/minigame.gd*

Gauge value at time t: rises while held, falls otherwise.

**See also:** `heat`

### `static sequence_progress(g: Dictionary, t := INF) -> Dictionary`

*shared/minigame.gd*

{index (current prompt), hits, started (when the current prompt appeared)} replaying key presses.

**See also:** `prompt`, `window`

### `static score(g: Dictionary, t: float) -> float`

*shared/minigame.gd*

0..1 (team timing can reach a little over 1 with sync).

**See also:** `hold_fraction`, `is_alive`, `order_of`, `post_of`, `rate_strike`

### `static break_time(block: Dictionary, tool: Dictionary, mining_speed := 1.0) -> float`

*shared/mining.gd*

Seconds to break `block` (a BlockRegistry def) holding `tool` ({type, tier, speed} or {}),
with the player's `mining_speed` stat. 0 = instant.

**See also:** `can_harvest`

### `static can_harvest(block: Dictionary, tool: Dictionary) -> bool`

*shared/mining.gd*

True if breaking the block with this tool yields its drops.

### `static stage(progress: float) -> int`

*shared/mining.gd*

Crack animation stage 0-9 for progress 0-1.

### `register_category(def: Dictionary) -> bool`

*shared/recipe_registry.gd*

Declares a tab for the crafting screen, or joins one that already exists. False only when the name
is unusable.

**Category names are a shared namespace on purpose**, and are the one registry key that is not
namespaced per mod. They have to be: the engine owns `tools`, `weapons`, `blocks` and the rest from
`_init`, recipes name a category as a plain string, and a mod qualified to `mymod:tools` could never
put anything in the engine's Tools tab - it would only ever make a second tab with the same label.

**Joining counts as succeeding.** This used to return false when the name was taken, which a mod
author could not tell apart from "you passed an empty name" - while the recipes went into the tab
anyway, which is what they asked for. First registration still wins the *label*, so a mod whose
display_name is dropped is told at the API boundary rather than left to wonder. (2026-09-22)

**See also:** `category`, `has_category`

### `has_category(cat_name: String) -> bool`

*shared/recipe_registry.gd*

Whether a tab of this name is already declared, by the engine or by a mod that loaded earlier.

### `add(def: Dictionary, items = null) -> int`

*shared/recipe_registry.gd*

Adds a recipe. `items` (an ItemRegistry) picks a category when none is given. Returns its index.

### `begin_reload(owner: String) -> void`

*shared/recipe_registry.gd*

Starts watching one mod's recipes so `end_reload` can tell which have gone.

Reloading cannot simply drop the owner's recipes and re-add them: a recipe is referred to by index
elsewhere, so they are marked removed instead and the indices stay put.

### `end_reload() -> int`

*shared/recipe_registry.gd*

Marks the owner's recipes that were not registered again as removed. Returns how many changed.

### `clear() -> void`

*shared/recipe_registry.gd*

Forgets every recipe (clients rebuild the book from a content update).

### `index_of(recipe_id: String) -> int`

*shared/recipe_registry.gd*

Where a recipe sits in `recipes`, or -1. The index is what everything else refers to a recipe by,
because it survives a reload while the array position of a rebuilt list would not.

### `producing(item: int) -> Array`

*shared/recipe_registry.gd*

Recipes whose output is `item`.

### `using(item: int) -> Array`

*shared/recipe_registry.gd*

Recipes that use `item` as an ingredient.

### `static guess_category(output: int, items) -> String`

*shared/recipe_registry.gd*

Which crafting tab a recipe belongs in when the mod did not say: worked out from what it makes -
blocks, armor, tools, weapons, food, else materials.

**See also:** `get_def`

### `to_network() -> Dictionary`

*shared/recipe_registry.gd*

The recipe book as the client receives it.

### `load_network(data) -> bool`

*shared/recipe_registry.gd*

Rebuilds the book on the client. False when the data is not the shape we expect.


## Creatures and AI

### `setup(id: int, def: Dictionary, parts: Array, sprite: Texture2D, pos: Vector3, yaw: float) -> void`

*client/entity_view.gd*

`parts`: [{name, mesh, transform}] from ModelLibrary.load_parts, or empty. `sprite`: texture for
items, projectiles and model-less entities.

### `update_plate(camera_position: Vector3) -> void`

*client/entity_view.gd*

{scale, hide: [part prefixes], tint: {part prefix: "#rrggbb"}} from the server (babies, sheared or
dyed sheep, ...).
Where the camera is, so the plate can fade with distance. Set by the client each frame.

**See also:** `update_for_camera`

### `windup() -> void`

*client/entity_view.gd*

The mob is about to attack: arms rise and it glows, so players can react.

### `despawn() -> void`

*client/entity_view.gd*

Server despawn: plays out a running death or pickup animation first.

**See also:** `category_of`

### `aabb() -> AABB`

*client/entity_view.gd*

Hit box for client-side targeting.

### `custom_behaviors := {}  (property)`

*server/ai/mob_ai.gd*

name -> {score: Callable(brain) -> float, update: Callable(brain, delta), stop: Callable(brain)}

### `edge_distance(e, t) -> float`

*server/ai/mob_ai.gd*

Horizontal gap between the mob's box and the target's box (0 when touching), plus any height gap.

**See also:** `aabb`, `aabb_of`

### `enemies_near(brain: MobBrain, center: Vector3, radius: float) -> Array`

*server/ai/mob_ai.gd*

Enemies (survival players and mobs of enemy groups) within `radius`.

**See also:** `brains_near`, `is_alive`, `is_enemy`

### `surround_slot(brain: MobBrain, t, ring: float) -> Vector3`

*server/ai/mob_ai.gd*

Melee mobs fighting the same target spread around it instead of piling up on one side.
Returns this brain's slot position, or Vector3.INF when it is the only attacker.

**See also:** `key_of`, `position_of`

### `static can_reach(brain, target) -> bool`

*server/ai/mob_attacks.gd*

A melee blow needs an opening: some line from the mob to the target not blocked by blocks (no hits
through walls, floors or closed doors).

**See also:** `chest_of`, `eye_of`, `line_of_sight`, `position_of`

### `static apply_condition(server, victim, condition: Dictionary) -> void`

*server/ai/mob_attacks.gd*

What an attack leaves behind on whoever it hit. Applied after the damage, so a condition that kills
does not race the blow that would have.

**See also:** `give`

### `target = null  (property)`

*server/ai/mob_brain.gd*

Current enemy (a ServerPlayer or an entity) or null.

### `behavior := "idle"  (property)`

*server/ai/mob_brain.gd*

Name of the running behavior.

### `phase := -1  (property)`

*server/ai/mob_brain.gd*

Index of the boss phase reached (-1 = none).

### `home := Vector3.INF  (property)`

*server/ai/mob_brain.gd*

Where the mob returns to when leashed (Vector3.INF = roams freely).

### `tune(values: Dictionary) -> void`

*server/ai/mob_brain.gd*

Changes this mob's AI settings (any MobConfig key, including attacks and phases).

**See also:** `agent_for`, `sanitize`

### `alert(position: Vector3) -> void`

*server/ai/mob_brain.gd*

Makes the mob notice a position (walks there to investigate).

### `move_to(goal: Vector3, speed := 1.0, radius := 0.8) -> void`

*server/ai/mob_brain.gd*

Walks toward a position (pathfinding as needed). Custom behaviors call this each think.

**See also:** `node_of`, `request_path`, `walkable_line`

### `at_path_end() -> bool`

*server/ai/mob_brain.gd*

True when the goal cannot be reached and the mob stands at the end of the best partial path (or found no
way at all from where it stands): as close as it can get. Behaviors treat that like arriving instead of pushing against the obstacle.

### `static resolve(ai, def: Dictionary, resolve_entity: Callable) -> Dictionary`

*server/ai/mob_config.gd*

Returns the resolved config. `ai` is a preset name, a Dictionary, or anything else (-> "wander").
`resolve_entity` maps entity type names to ids (for projectiles and summons).

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `static condition_of(value) -> Dictionary`

*server/ai/mob_config.gd*

{condition, seconds, level, chance} or {} - read here rather than where it is applied, so a malformed
one is a dull default at load instead of a surprise mid-fight.

Public because `fields.gd` needs exactly this reader: a field and a bite leave the same kind of thing
behind, and a second copy would drift from this one.

### `set_tables(solid_lut: PackedByteArray, liquid_lut: PackedByteArray, sight_blockers: PackedByteArray, hazards: PackedByteArray) -> void`

*server/ai/pathfinder.gd*

`sight_blockers`: 1 for blocks that stop line of sight; `hazards`: 1 for blocks mobs avoid.

### `find_path(start: Vector3i, goal: Vector3i, radius: float, agent: PackedInt32Array, max_nodes := -1) -> Dictionary`

*server/ai/pathfinder.gd*

{status: Status, nodes: Array[Vector3i]} from start to the end node.

**See also:** `chapter_pages`, `get_block`, `sorted_chapters`

### `settle(position: Vector3, agent: PackedInt32Array) -> Vector3i`

*server/ai/pathfinder.gd*

Standable node at or near `position` (scans a few cells up and down).

**See also:** `describe`, `drive_changed`, `get_block_v`, `node_of`, `qualified`, `reachable`

### `feed(p, e) -> bool`

*server/breeding.gd*

A player right-clicked `e` holding `item`. Returns true if it was eaten.

**See also:** `clear_slot`, `config_of`, `is_alive`, `is_baby`, `is_food`, `play_effect`

### `update(delta: float) -> void`

*server/breeding.gd*

Once a second: babies grow, love and cooldowns run out.

### `mate(a, b) -> Object`

*server/breeding.gd*

Spawns a baby between two parents and starts their cooldowns.

**See also:** `config_of`, `play_effect`, `spawn`

### `kinds := {}  (property)`

*server/companions.gd*

Name -> {name, display_name, behavior, owner}

### `order_of(entity) -> String`

*server/companions.gd*

What it is being told to do now. Everything defaults to following, which is what a creature that has
just been tamed should do without anybody saying so.

### `post_of(entity) -> Vector3`

*server/companions.gd*

Where it was told to hold, for guard. Vector3.INF when it has no post.

### `give(entity, order_name: String, options := {}) -> bool`

*server/companions.gd*

Tells it something. `options.at` is where, for orders that need a place; it defaults to where the
creature is standing, which is what "guard this spot" means when somebody says it out loud.

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `wake`

### `orders_for(entity) -> Array`

*server/companions.gd*

The orders this creature can be given: the engine's three, plus any a mod registered for its type.
A mod restricts them by handling `companion_orders`, which is cheaper than a registry of which
creature may be told what.

### `show(player, entity) -> bool`

*server/companions.gd*

The panel. Drawn by the engine so every companion in every mod is told what to do the same way.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `heat`, `hold_fraction`

### `score(brain) -> float`

*server/companions.gd*

Registered into the AI the way sit and follow-owner are. Guarding is holding a spot: it fights what
comes to it, and walks back when whatever it was fighting drew it away.

**See also:** `hold_fraction`, `is_alive`, `order_of`, `post_of`, `rate_strike`

### `on_changed(unit: String, handler: Callable) -> void`

*server/drives.gd*

Told when what a face is driven at changes: {realm, position, face, unit, value, jammed}.

### `set_source(unit: String, node: Dictionary, value: float) -> void`

*server/drives.gd*

This face drives at `value` - a speed, and a sign for which way round. 0 stops driving.

**See also:** `get_block_v`, `key_name`, `node_key`, `reaching`, `record`

### `value_at(unit: String, node: Dictionary) -> float`

*server/drives.gd*

What this face is being driven at. Zero when nothing drives it, and zero when the line is jammed -
a jammed line does not turn.

**See also:** `key_name`, `node_key`

### `jammed_at(unit: String, node: Dictionary) -> bool`

*server/drives.gd*

Whether this face is on a line that two sources are fighting over.

**See also:** `key_name`, `node_key`

### `projectiles: Array = []  (property)`

*server/entities.gd*

Live projectiles (mobs watch these to dodge).

### `spawning  (property)`

*server/entities.gd*

Natural spawning rules, category caps and despawning.

### `breeding  (property)`

*server/entities.gd*

Feeding, love, babies and growing up (see engine/server/breeding.gd).

### `taming  (property)`

*server/entities.gd*

Owners, following, sitting and defending (see engine/server/taming.gd).

### `realm  (property)`

*server/entities.gd*

The realm these creatures are in.

### `spawn(type_id: int, pos: Vector3, options := {}) -> Entity`

*server/entities.gd*

options: yaw, velocity (Vector3), data (Dictionary), owner, item (id), count, pickup_delay

**See also:** `attach`

### `drop_item(item: int, count: int, pos: Vector3, velocity := Vector3.INF, pickup_delay := ITEM_PICKUP_DELAY, item_data := {}) -> Entity`

*server/entities.gd*

Drops an item stack at `pos` with a small random toss.

**See also:** `max_stack`, `qualified`, `register_instance`, `spawn`

### `last_sections := {}  (property)`

*server/entities.gd*

Microseconds spent in each part of the last tick (read by the server's --metrics).

### `damage(e: Entity, amount: float, cause: String, attacker = null, direction := Vector3.ZERO) -> bool`

*server/entities.gd*

Returns true if damage was applied. `direction` pushes the entity (defaults to away from attacker).

**See also:** `broadcast_entity_event`, `damage_player`, `is_alive`, `kill`, `on_hurt`, `play_sound`

### `add_spawn_rule(rule: Dictionary) -> void`

*server/entities.gd*

See engine/server/spawning.gd for rule keys.

**See also:** `add_rule`, `block`, `entity_type`, `is_excluded`, `qualified`

### `replicate(players: Array) -> void`

*server/entities.gd*

Called every snapshot interval. Sends spawns/despawns for entities entering or leaving each
player's view, and compact position updates for visible entities that moved.

### `look_changed(e: Entity) -> void`

*server/entities.gd*

An entity's look changed (Entity.set_look): tell players who can see it.

### `serialize_chunk(coord: Vector2i) -> Array`

*server/entities.gd*

Persistent entities standing in `coord` as JSON-safe dictionaries.

**See also:** `chunk_coord_of`, `is_alive`

### `unload_chunk(coord: Vector2i) -> Array`

*server/entities.gd*

Removes every entity in the chunk (called when it unloads). Returns the persistent ones' records.

**See also:** `chunk_coord_at`, `chunk_coord_of`, `serialize_chunk`

### `type := 0  (property)`

*server/entity.gd*

Type id (EntityRegistry index) and its full server-side definition.

### `health := 0.0  (property)`

*server/entity.gd*

Health is a property rather than a plain field so the label over its head cannot go stale. A mod
writing `e.health = 5` is not a rare case - it is how half the tests and several mods change it -
and hooking the two places the engine happens to change it left every other writer silent.
(2026-09-20, after the user asked why this was not event driven: there is no entity_healed event to
listen to, and entity_damage fires *before* the change.)

### `data := {}  (property)`

*server/entity.gd*

Free-form data owned by mods; saved with persistent entities. Namespace your keys.

### `age := 0.0  (property)`

*server/entity.gd*

Seconds since spawning.

### `owner = null  (property)`

*server/entity.gd*

Projectiles: the ServerPlayer or entity that fired it (never persisted).

### `item_id := 0  (property)`

*server/entity.gd*

Dropped item stacks.

### `brain = null  (property)`

*server/entity.gd*

Mobs: the AI brain (engine/server/ai/mob_brain.gd); null for other kinds.

### `set_look(values: Dictionary) -> void`

*server/entity.gd*

How clients draw this entity: {scale (1 = normal, babies are smaller), hide: [model part name
prefixes to hide, e.g. "wool" once sheared], tint: {part prefix: "#rrggbb"}, pose: "" | "sit"}. Merged into the current
look and saved in data.look.

**See also:** `apply`, `look_changed`, `merge`

### `is_alive() -> bool`

*server/entity.gd*

False once the entity died or was removed.

### `remove() -> void`

*server/entity.gd*

Removes the entity from the world (no death, no drops).

### `damage(amount: float, cause := "magic", attacker = null) -> bool`

*server/entity.gd*

Deals damage as if from `attacker` (a ServerPlayer, entity or null). Returns true if it applied.

`cause` comes before `attacker` to match ServerPlayer.damage and EntityManager.damage. It used to be
the other way round on this one object alone, which meant `target.damage(5, "poison")` filed the
cause as the attacker on a creature and as the cause on a player - no error either way, because an
attacker is untyped. Conditions had to tell the two apart rather than just calling it. (2026-09-20)

**See also:** `broadcast_entity_event`, `damage_player`, `is_alive`, `kill`, `on_hurt`, `play_sound`

### `kill(cause := "magic") -> void`

*server/entity.gd*

Kills it outright, with drops and a death, as opposed to `remove()` which takes it away as though it
had never been there. Player has had `kill` all along; this is the same verb for a creature.

**See also:** `broadcast_entity_event`, `damage`, `drop_item`, `is_alive`, `kill_player`, `play_sound`

### `teleport(pos: Vector3) -> void`

*server/entity.gd*

Puts it somewhere, stopping it dead. The same spelling as ServerPlayer.teleport, so code that moves
"a thing" does not have to know which kind of thing it has.

**See also:** `ensure_area_loaded`, `realm_of`

### `set_health(value: float) -> void`

*server/entity.gd*

Sets health, clamped, and dies properly if that takes it to zero.

The spelling Player has had all along, and the reason it is worth having on both: writing
`e.health = 0` notifies (the property is hooked) but does not clamp to the type's maximum and does
not *die* - no drops, no death event, just a creature standing there with nothing left. The raw
property stays for the engine's own writes; a mod wanting to set health should use this.
(2026-09-21)

**See also:** `is_alive`, `kill`, `kill_player`, `sync_health`

### `heal(amount: float) -> void`

*server/entity.gd*

Gives back health, up to the type's maximum.

**See also:** `heal_player`, `is_alive`

### `set_goal(pos: Vector3) -> void`

*server/entity.gd*

Makes a mob walk to `pos`, overriding its behaviour until it arrives; Vector3.INF clears it.

**See also:** `wake`

### `get_target()`

*server/entity.gd*

Mobs: the current enemy (a player or entity), or null.

**See also:** `now`

### `set_target(new_target) -> void`

*server/entity.gd*

Mobs: attack this player or entity now (null forgets the current target).

**See also:** `alert_allies`, `key_of`, `position_of`, `velocity_of`

### `add_threat(source, amount: float) -> void`

*server/entity.gd*

Mobs: makes `source` more (or less) hated; the highest threat becomes the target.

**See also:** `is_alive`, `key_of`, `position_of`, `velocity_of`

### `tune(values: Dictionary) -> void`

*server/entity.gd*

Mobs: overrides AI settings for this mob only (see engine/server/ai/mob_config.gd).

**See also:** `agent_for`, `sanitize`

### `alert(pos: Vector3) -> void`

*server/entity.gd*

Mobs: investigate a position as if it heard something there.

### `set_home(pos: Vector3, leash := -1.0) -> void`

*server/entity.gd*

Mobs: the home it returns to when it strays beyond its leash.

**See also:** `tune`

### `perform_attack(attack_name: String) -> bool`

*server/entity.gd*

Mobs: starts the named attack against the current target right away (ignores range and cooldown).

**See also:** `begin`

### `get_behavior() -> String`

*server/entity.gd*

Mobs: name of the running behaviour ("wander", "engage", "flee", ...).

### `push(impulse: Vector3) -> void`

*server/entity.gd*

Adds velocity (e.g. knockback, launch pads).

**See also:** `play_sound`, `wake`

### `wake() -> void`

*server/entity.gd*

Makes a resting entity simulate again right away (after moving it from a mod).

**See also:** `needed_sleepers`, `refresh_appearance`, `stand_spot`, `teleport`

### `aabb() -> AABB`

*server/entity.gd*

Box enclosing the entity, for hit tests.

### `static default_for(def: Dictionary) -> Dictionary`

*server/nameplates.gd*

The default for an entity type: `nameplate` in its definition, or {} for no plate at all. Creatures
are quiet by default - a field of forty sheep each wearing a label is worse than no labels.

### `set_plate(target, spec := {}) -> bool`

*server/nameplates.gd*

Sets or changes what is over something's head. `spec` merges with whatever is there, so a mod can
add a line without knowing whether health is being shown.

**See also:** `close`, `open`, `plate_of`, `set_look`

### `plate_of(target) -> Dictionary`

*server/nameplates.gd*

What is over its head now, defaults included.

**See also:** `default_for`

### `clear(target) -> bool`

*server/nameplates.gd*

Takes it away entirely.

### `health_changed(target) -> void`

*server/nameplates.gd*

Called when something's health moves. Only reaches the client for a plate that actually draws it.

**See also:** `close`, `open`, `plate_of`, `set_look`

### `category_of_type(type_id: int) -> String`

*server/spawning.gd*

A mob type's category: its `category` key, else from its AI (hostile, archer and boss presets or a
hostile temperament: monster; passive: animal).

### `count_near(center: Vector3, category: String) -> int`

*server/spawning.gd*

Mobs of a category within CAP_RADIUS of a position.

**See also:** `category_of`, `is_alive`

### `run(for_players: Array = []) -> void`

*server/spawning.gd*

One spawning round for `for_players` (default: everyone). The server calls it every tick for a slice of
the players, so each player gets a round about once a second without one tick doing them all.

**See also:** `category_of`, `daylight`, `find_spot`, `get_time_of_day`, `is_alive`, `spawn`

### `find_spot(center: Vector3, rule: Dictionary, daylight: float, min_distance := -1.0, max_distance := -1.0) -> Vector3`

*server/spawning.gd*

A spot for a rule's mob around `center` (surface or caves), or Vector3.INF.

**See also:** `biome_at`, `chunk_coord_at`, `collides`, `get_block`, `has_chunk`, `index`

### `despawn(slot := 0, slots := 1) -> void`

*server/spawning.gd*

Removes mobs nobody is near. `slot`/`slots` check only the mobs whose id falls in that slot (the server
spreads the check over a second of ticks); the defaults check every mob.

**See also:** `category_of`

### `summary(center: Vector3) -> Dictionary`

*server/spawning.gd*

{category: {near, cap}} around a player, for the /mobs command.

**See also:** `count_near`

### `interact(p, e) -> bool`

*server/taming.gd*

Right-click by a player. Returns true if it was handled (a taming try or sit toggle).

**See also:** `clear_slot`, `config_of`, `is_alive`, `is_food`, `is_tamed`, `owner_id`

### `defenders_of(p) -> Array`

*server/taming.gd*

Tamed mobs near a player that are ready to fight for them.

**See also:** `in_radius`, `is_alive`, `owner_id`

### `owner_hurt(p, attacker) -> void`

*server/taming.gd*

Someone hurt `p`: their tamed mobs turn on the attacker.

**See also:** `add_threat`, `defenders_of`

### `owner_attacked(p, target) -> void`

*server/taming.gd*

`p` attacked `target`: their tamed mobs join in.

**See also:** `add_threat`, `defenders_of`

### `protects(e, other) -> bool`

*server/taming.gd*

Whether `e` must never treat `other` as an enemy (its owner).

**See also:** `is_tamed`, `owner_id`

### `update() -> void`

*server/taming.gd*

Once a second: tamed mobs that fell far behind catch up with their owner.

### `problem := ""  (property)`

*server/vehicles.gd*

Why the last mount was refused, in words somebody can be shown. A vehicle that silently does not
take you is indistinguishable from one that is broken. (2026-09-21)

### `static config(def: Dictionary) -> Dictionary`

*server/vehicles.gd*

The vehicle block of an entity type, or {}.

### `static riders_of(entity) -> Array`

*server/vehicles.gd*

Who is aboard, as player ids. Kept on the entity so it is saved with it: a boat you left at a jetty
is empty when you come back, which is right, but the boat is still there.

**See also:** `order`, `register_order`

### `mount(player, entity) -> bool`

*server/vehicles.gd*

Puts a player aboard. Refused when it is full, too far away, or they are already riding something.

**See also:** `config_of`, `is_alive`, `riders_of`, `tell_riding`

### `dismount(player, to = null) -> bool`

*server/vehicles.gd*

Takes a player off. `to` is where to put them down; by default beside the vehicle rather than inside
it, because standing inside a boat's own box pushes you through the floor.

**See also:** `riders_of`, `tell_riding`

### `empty(entity) -> void`

*server/vehicles.gd*

Everybody off, for a vehicle that is being removed or has died.

**See also:** `dismount`, `player_by_id`, `riders_of`

### `simulate(player) -> void`

*server/vehicles.gd*

The rider's share of a server tick, called instead of walking them. Returns after draining the input
queue either way, so the client's prediction queue does not stall.

**See also:** `at_path_end`, `config_of`, `dismount`, `get_block`, `is_alive`, `node_center`

### `static step(b: Body, world, solid: PackedByteArray, liquid: PackedByteArray, dt: float, gravity: float, drag := 0.0, shapes := PackedByteArray()) -> void`

*shared/entity_physics.gd*

Integrates one step. `gravity` in blocks/s^2, `drag` per second applied to horizontal velocity
when airborne (ground friction comes from the caller steering velocity).

**See also:** `block`, `block_state`, `box`, `collides`, `family_of`, `get_block`

### `static segment_hits_box(from: Vector3, dir: Vector3, max_t: float, box_min: Vector3, box_max: Vector3) -> float`

*shared/entity_physics.gd*

Distance along the segment `from` + `dir` * t (t in [0, max_t]) where it enters the box, or -1.

### `register(def: Dictionary, replace := false) -> int`

*shared/entity_registry.gd*

Definition keys (all optional except name):
kind: "mob" | "projectile" | "object" | "item"
model: glTF asset (nodes named leg_a / leg_b / arm_a / arm_b swing while walking, head turns)
sprite: texture asset drawn as a billboard when there is no model (projectiles, particles)
width, height: collision box in blocks; scale: model scale; glow: unshaded (e.g. magic sparks)
health (0 = cannot be damaged), speed, gravity, drag, knockback_resistance (0-1)
ai: a preset name or a Dictionary of behaviour settings, attacks and phases; see
engine/server/ai/mob_config.gd (mobs only)
damage (projectiles: damage dealt on hit), lifetime (seconds, 0 = forever)
drops: [[item name or id, count], ...] on death; sounds: {hurt, death, ambient, attack}
persistent: saved with the chunk it is in (otherwise despawns when no player is near)
`replace`: an existing type of that name gets the new definition in place (same id; mod reloads).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of(type_name: String) -> int`

*shared/entity_registry.gd*

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid(id: int) -> bool`

*shared/entity_registry.gd*

Whether anything is registered under this id.

### `to_network() -> Array`

*shared/entity_registry.gd*

The creature table as the client receives it, trimmed to `NETWORK_FIELDS`.

### `load_network(data) -> bool`

*shared/entity_registry.gd*

Client side. Rebuilds the table from the server's copy (the engine:item entry is included).

### `static dir() -> String`

*shared/identity.gd*

Where identities live. QW_IDENTITY_DIR moves them, which is how the tests keep their bot keys out of
the player's own folder: a test run used to overwrite default.pem and take the player's account with
it. (2026-09-18)

### `static load_or_create(identity_name := "default", bits := DEFAULT_BITS) -> CryptoKey`

*shared/identity.gd*

Loads the named identity from user://identity, creating it on first use.

**See also:** `load`, `path_for`, `save`

### `static parse_public_key(pem: String) -> CryptoKey`

*shared/identity.gd*

Server side: parses a public key PEM; returns null if it is not a usable key.

**See also:** `key`

### `static player_id(key: CryptoKey) -> String`

*shared/identity.gd*

Stable id derived from the public key (32 hex characters).

**See also:** `finish`, `start`

### `static export_encrypted(key: CryptoKey, passphrase: String, iterations := EXPORT_ITERATIONS) -> String`

*shared/identity.gd*

Returns the JSON text of an encrypted identity file.

**See also:** `finish`, `pbkdf2_sha256`, `player_id`, `start`

### `static import_encrypted(text: String, passphrase: String) -> Dictionary`

*shared/identity.gd*

Decrypts an exported identity. Returns {key: CryptoKey, player_id} or {error: String}.

**See also:** `finish`, `pbkdf2_sha256`, `player_id`, `start`

### `static install(key: CryptoKey, identity_name := "default") -> Error`

*shared/identity.gd*

Saves `key` as the named identity. An existing different identity is kept as a .bak file.

**See also:** `close`, `download`, `install_package`, `installed`, `installed_path`, `installer`

### `static pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray`

*shared/identity.gd*

PBKDF2-HMAC-SHA256 with a single 32-byte output block.


## Players

### `textures := {}  (property)`

*client/effects/effect_player.gd*

Asset name -> Texture2D (mod emitter textures).

### `play_sound: Callable  (property)`

*client/effects/effect_player.gd*

Plays a sound by name at a position: Callable(name, position).

**See also:** `play_sound_at`, `qualified`

### `quality := 1.0  (property)`

*client/effects/effect_player.gd*

Scales particle counts (graphics presets).

### `shake_offset := Vector3.ZERO  (property)`

*client/effects/effect_player.gd*

Current camera shake as an offset to add to the camera, decaying over time.

### `shake_scale := 1.0  (property)`

*client/effects/effect_player.gd*

Accessibility: 0..1 multipliers for camera shake and light flashes.

### `play(id: int, position: Vector3, options := {}, parent: Node3D = null, listener := Vector3.INF) -> Node3D`

*client/effects/effect_player.gd*

Plays effect `id` at a world position. `parent` (optional) makes it follow a node; `listener`
(camera position) decides whether shake reaches this player. Returns the effect's root node.

**See also:** `exists`, `load`, `play`, `play_def`, `read`

### `play_def(def: Dictionary, position: Vector3, options := {}, parent: Node3D = null, listener := Vector3.INF) -> Node3D`

*client/effects/effect_player.gd*

Plays an effect from its definition rather than its id, for effects that were never registered.

Oldest effects are freed once `MAX_LIVE` are running: a mod that fires one per tick should slow the
room down, not fill memory.

**See also:** `builtin_texture`

### `block_break(position: Vector3, atlas_texture: Texture2D, uv: Rect2, brightness := 1.0) -> void`

*client/effects/effect_player.gd*

Chunks of a block flying apart: `atlas_texture` with the block face's `uv` rectangle.

**See also:** `begin`

### `builtin_texture(texture_name: String) -> Texture2D`

*client/effects/effect_player.gd*

Procedural particle sprites: soft (round glow), spark (bright core), star (four points), square.

**See also:** `create`

### `fetch := Callable()  (property)`

*client/music_player.gd*

Set by the client: fetch_lazy_asset(asset_name, then) from GameClient.

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `manifest := {}  (property)`

*client/music_player.gd*

asset name -> {hash, size}; set by the client once content has loaded, as for sounds.

### `wanted := -1  (property)`

*client/music_player.gd*

The track the server last asked for, whether or not it is audible yet (read by tests).

### `playing := -1  (property)`

*client/music_player.gd*

What is actually playing (read by tests).

### `play(track_id: int, fade: float, restart: bool) -> void`

*client/music_player.gd*

The server's instruction. -1 stops.

**See also:** `exists`, `load`, `play`, `play_def`, `read`

### `credits() -> Array`

*client/music_player.gd*

Everything the server is carrying, as lines to show a player. Music must say who made it.

### `manifest := {}  (property)`

*client/sound_player.gd*

asset name -> {hash, size}; set by the client once content has loaded.

### `volume: float  (property)`

*client/sound_player.gd*

The master volume (the "audio/volume" setting).

### `played := 0  (property)`

*client/sound_player.gd*

Sounds started so far (read by tests).

### `stream_named(sound_name: String) -> AudioStream`

*client/sound_player.gd*

A decoded stream by sound name, for anything that wants to own its own playback rather than borrow a
voice from the pool - weather, which loops for as long as it is raining. null if unknown.

**See also:** `exists`, `load`, `read`

### `clock_override := -1  (property)`

*server/anticheat.gd*

Tests drive time themselves (microseconds); -1 = the real clock.

### `record(p, check: String, amount := 1.0, detail := "") -> void`

*server/anticheat.gd*

Adds to a check's score for a player. `detail` explains this event (shown to moderators).

**See also:** `has_permission`, `kick`, `send_message`

### `count_input(p) -> void`

*server/anticheat.gd*

Counts a new input from a client and flags inputs beyond the allowance (real time, not server ticks, so
a slow server does not make honest players look fast).

**See also:** `now_usec`, `record`

### `allow_message(peer_id: int) -> bool`

*server/anticheat.gd*

Counts a message from a peer (every client RPC). Returns false when it should be dropped.

**See also:** `record`

### `recent() -> Array`

*server/anticheat.gd*

[{time, player, check, score, detail, action}] newest first (for /anticheat and the dashboard).

### `load_extra(world_dir: String) -> void`

*server/chat_filter.gd*

Adds the world's own words (one per line; # starts a comment).

### `clean(text: String) -> String`

*server/chat_filter.gd*

The text with filtered words replaced by asterisks (same length, first letter kept).

### `budget_usec := 2000  (property)`

*server/claims.gd*

The share of a tick, in microseconds, that all the claims on this server may have between them.
Two milliseconds of a sixteen millisecond tick by default: enough for a few real factories, little
enough that the people actually playing keep the rest.

### `add(realm_id: String, centre: Vector3i, radius: int, options := {}) -> int`

*server/claims.gd*

Keeps chunks awake around a position. `owner` is the mod; `player_id` is whoever should be told if
it has to be paused, and `display` is what to call the place when telling them.

### `awake_chunks(realm_id: String) -> Dictionary`

*server/claims.gd*

The chunks a realm is keeping awake on somebody's behalf. Paused claims contribute nothing, which is
the whole of what pausing means.

### `update(delta: float) -> void`

*server/claims.gd*

Charges each claim what its chunks actually spent, and pauses the dearest until the total fits.

### `resume(id: int) -> bool`

*server/claims.gd*

Lets a paused claim run again - a player tidied their machine, or an admin raised the budget.

**See also:** `add_modifier`, `mark_simulation_stale`

### `kinds := {}  (property)`

*server/conditions.gd*

Name -> {name, display_name, color, good, max_level, modifiers, tick, particle, stacks, owner}

### `give(target, condition_name: String, options := {}) -> bool`

*server/conditions.gd*

Gives one. `seconds` 0 means until it is taken away. Returns false when the target already has
something stronger and the condition does not stack.

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `wake`

### `clear_all(target, only_bad := false) -> int`

*server/conditions.gd*

Takes away everything, or with `only_bad` everything unpleasant - which is the whole of what a cure
is, and means a mod can write one without listing every affliction in the game.

### `of_target(target) -> Array`

*server/conditions.gd*

What they are under, for a panel or a command: [{name, display_name, color, level, good, seconds}],
where `seconds` is -1 for one that does not run out.

### `tick(_delta: float) -> void`

*server/conditions.gd*

Expiry and the repeating half. Walks only what is holding something, so a world of four thousand
creatures costs nothing until one of them is actually poisoned.

**See also:** `aabb`, `allied`, `apply_condition`, `at_path_end`, `at_station`, `broadcast_entity_event`

### `resume(target) -> void`

*server/conditions.gd*

Puts a target back on the ticking list after a load: conditions live in saved data, so somebody who
logs out poisoned logs back in poisoned.

**See also:** `add_modifier`, `mark_simulation_stale`

### `before_save(target) -> void`

*server/conditions.gd*

Writes how long is *left* rather than when it expires, because server time restarts with the server
and an absolute expiry means nothing on the other side of a save.

### `sync(p, force := false) -> void`

*server/hunger.gd*

Sends hunger when it changes (-1 while the `hunger` rule is off, which hides the bar).

**See also:** `refresh`, `state_of`, `view`

### `update(p, delta: float, moved: Vector3, move_time: float, was_on_ground: bool) -> void`

*server/hunger.gd*

Each tick: movement exhaustion, hunger drain, regeneration, starvation and eating.
`moved`: how far the player's inputs moved them this tick, over `move_time` seconds of simulation.

### `regen_interval(p, normal_interval: float) -> float`

*server/hunger.gd*

Whether natural regeneration may heal now, and how often: 0 = not at all.

**See also:** `enabled`

### `start_eating(p) -> bool`

*server/hunger.gd*

Starts eating the held food. Returns false (with a reason shown) if it cannot be eaten now.

**See also:** `enabled`, `get_def`, `members`, `selected_item`, `show_title`, `view`

### `finish_eating(p, slot: int) -> bool`

*server/hunger.gd*

Eats one item from a slot right away (also used by mods and tests).

**See also:** `add_modifier`, `clear_slot`, `drop`, `get_def`, `get_eye_position`, `heal_player`

### `static apply_armor(amount: float, armor: float, toughness: float) -> float`

*server/player_stats.gd*

Damage left after armor: armor points absorb up to 80% of a hit, less against big hits unless
toughness is high: a diminishing-returns curve, so each point of armour is worth less than the last.

### `descriptions := {  (property)`

*server/roles.gd*

Known permissions and what they mean (built-in and mod-registered), for /role info and the admin panel.

### `apply_config_admins(config_admins: Dictionary) -> void`

*server/roles.gd*

Applies the admins named in the server's configuration as owners, every start: the config is the
authority on who runs the server, so it is reapplied rather than migrated once.

**See also:** `give`

### `role(role_name: String) -> Dictionary`

*server/roles.gd*

A role's definition (saved changes over the built-in one), or {}.

**See also:** `merge`

### `set_permission(role_name: String, permission: String, remove := false) -> String`

*server/roles.gd*

Adds ("build") or denies ("-build") a permission on a role; `remove` takes an entry away instead.

**See also:** `exists`, `merge`, `role`

### `roles_of(player_id: String) -> Array`

*server/roles.gd*

A player's roles: assigned ones plus the default role.

**See also:** `exists`

### `entries_of(player_id: String) -> Array`

*server/roles.gd*

Every permission entry a player's roles give, following inheritance.

**See also:** `exists`, `role`, `roles_of`

### `static allows(entries: Array, permission: String) -> bool`

*server/roles.gd*

Whether a set of entries grants a permission: a matching denial wins; "*" and "group.*" match.

### `badge(player_id: String) -> Dictionary`

*server/roles.gd*

The highest role with a tag, for chat: {tag, color} or {}.

**See also:** `role`, `roles_of`

### `rank(player_id: String) -> int`

*server/roles.gd*

The highest priority among a player's roles (a manager can only hand out roles below their own).

**See also:** `roles_of`

### `player_id := ""  (property)`

*server/server_player.gd*

Permanent id derived from the player's identity key.

**See also:** `finish`, `start`

### `kept_items: Array = []  (property)`

*server/server_player.gd*

Stacks from mods this server does not have right now: kept as saved and written back untouched.

### `data := {}  (property)`

*server/server_player.gd*

Free-form per-player data owned by mods; persisted with the world. Namespace your keys.

### `hunger := 20.0  (property)`

*server/server_player.gd*

Hunger 0-20 and hidden saturation (see engine/server/hunger.gd).

### `realm_id := ""  (property)`

*server/server_player.gd*

Which of the server's worlds this player is standing in; "" is the overworld. Saved with them, so
somebody who logged out in another realm comes back to it rather than falling into the overworld at
the same coordinates - which would be a different place entirely.

### `spawn_point := Vector3.INF  (property)`

*server/server_player.gd*

Where the player respawns; Vector3.INF uses their bed, then the game's spawn handler.

### `spawn_bed = null  (property)`

*server/server_player.gd*

The bed they last used (Vector3i, foot) or null; checked when respawning.

### `sleeping := {}  (property)`

*server/server_player.gd*

{bed, since, head_dir, return} while asleep in a bed.

### `riding := 0  (property)`

*server/server_player.gd*

The entity this player is riding, or 0. While it is set they do not walk: their position comes from
the vehicle and their input is steering (see engine/server/vehicles.gd).

### `modifiers := {}  (property)`

*server/server_player.gd*

Timed stat modifiers: id -> {stat, amount, op, expires (server time, 0 = permanent)}.

### `input_credit := 0.0  (property)`

*server/server_player.gd*

Simulation steps this player may take (anti-cheat: inputs cannot run faster than the game).

### `charging := {}  (property)`

*server/server_player.gd*

{slot, item, started} while holding use on an item that charges (a drawn bow; see Charging).

### `physics_rules = null  (property)`

*server/server_player.gd*

Physics rules adjusted by this player's move_speed stat (null = the server's rules).

### `appearance := {}  (property)`

*server/server_player.gd*

Last appearance sent to clients (held item, visible armor, cosmetics).

### `avatar := {}  (property)`

*server/server_player.gd*

The look others see (Cosmetics avatar data), recomputed by the server from the fields below.

### `portable_avatar := {}  (property)`

*server/server_player.gd*

The player's own built-in look, sent by their client.

### `server_wear := {}  (property)`

*server/server_player.gd*

Server cosmetics the player picked on this server: {category: {id, color}}.

### `avatar_override := {}  (property)`

*server/server_player.gd*

Avatar data mods lay over the player's look (see set_avatar_override).

### `requested_avatar := {}  (property)`

*server/server_player.gd*

The avatar the client last asked for (creations in it may still be uploading or awaiting approval).

### `owned_cosmetics := {}  (property)`

*server/server_player.gd*

Server cosmetics granted to this player: name -> true.

### `open_container = null  (property)`

*server/server_player.gd*

Position of the container whose screen is open (null when none).

**See also:** `open`

### `crafting_station := {}  (property)`

*server/server_player.gd*

{name, position, title} of the crafting station in use ({} = crafting by hand).

### `known_recipes := {}  (property)`

*server/server_player.gd*

Recipes this player has discovered: recipe id -> true (see RecipeRegistry unlock rules).

### `seen_items := {}  (property)`

*server/server_player.gd*

Items this player has held at least once: item name -> true (drives "pickup" discoveries).

### `team := ""  (property)`

*server/server_player.gd*

Team name ("" = none). Teams share station trays and projects; mods decide who is on which team.

### `guide := {}  (property)`

*server/server_player.gd*

Guidebook progress (see engine/server/guide.gd).

### `tutorial := {}  (property)`

*server/server_player.gd*

Tutorial progress and tips seen (see engine/server/tutorials.gd).

### `selected_slot: int  (property)`

*server/server_player.gd*

Index of the selected hotbar slot.

### `get_eye_position() -> Vector3`

*server/server_player.gd*

Where the player's eyes are (for aiming and line of sight).

**See also:** `eye_position`

### `has_permission(permission: String) -> bool`

*server/server_player.gd*

Whether this player's roles grant a permission ("build", "creative", "ugc.review", a mod's own ...).

### `transfer_to(server_name: String, arrival := "", data := {}) -> String`

*server/server_player.gd*

Sends the player to another server in this server's network (network.json; see engine/server/transfers.gd).
`arrival`: a named arrival point there; `data`: a small Dictionary mods there receive in player_arrived.
Returns "" or why not.

**See also:** `transfer`

### `teleport(pos: Vector3) -> void`

*server/server_player.gd*

Moves the player to a position and stops their fall.

**See also:** `ensure_area_loaded`, `realm_of`

### `damage(amount: float, cause := "magic", attacker = null) -> bool`

*server/server_player.gd*

Deals damage from `attacker` (player, entity or null). Creative players are unaffected. Returns
true if damage applied. `cause`: "attack", "mob", "projectile", "fall", "void", "magic", ...

**See also:** `broadcast_entity_event`, `damage_player`, `is_alive`, `kill`, `on_hurt`, `play_sound`

### `heal(amount: float) -> void`

*server/server_player.gd*

Gives back health, up to max_health.

**See also:** `heal_player`, `is_alive`

### `is_alive() -> bool`

*server/server_player.gd*

The same question Entity.is_alive answers, spelled the same way, so code that asks "is this thing
still around" does not have to know which kind of thing it has. `dead` stays as it was.

### `set_hunger(value: float, new_saturation := -1.0) -> void`

*server/server_player.gd*

Sets hunger (0-20) and optionally saturation.

**See also:** `add_modifier`, `enabled`, `remove_modifier`, `sync`

### `add_exhaustion(amount: float) -> void`

*server/server_player.gd*

Adds hunger exhaustion (4 = one point of saturation or hunger).

**See also:** `enabled`, `get_stats`, `set_hunger`, `sync`

### `feed(hunger_points: float, saturation_points := 0.0) -> void`

*server/server_player.gd*

Restores hunger and saturation as if eating.

**See also:** `clear_slot`, `config_of`, `is_alive`, `is_baby`, `is_food`, `play_effect`

### `set_health(value: float) -> void`

*server/server_player.gd*

Sets health (0 kills).

**See also:** `is_alive`, `kill`, `kill_player`, `sync_health`

### `set_max_health(value: float) -> void`

*server/server_player.gd*

Sets the base max health for this player (items and effects still modify it).

**See also:** `add_modifier`

### `kill(cause := "magic") -> void`

*server/server_player.gd*

Kills the player with a cause (shown in the death message).

**See also:** `broadcast_entity_event`, `damage`, `drop_item`, `is_alive`, `kill_player`, `play_sound`

### `push(impulse: Vector3) -> void`

*server/server_player.gd*

Adds velocity (knockback, launch pads). The client is corrected by the next snapshot.

**See also:** `play_sound`, `wake`

### `hear(sound_name: String, volume := 1.0, pitch := 1.0) -> void`

*server/server_player.gd*

Plays a sound only this player hears, not positioned in the world.

**Called `hear`, not `play_sound`.** `api.play_sound(name, position, volume, pitch)` puts a sound
in the world; this one was `play_sound(name, volume, pitch)`, so the same name took a Vector3 as
its second argument in one place and a float in the other - a transposition the compiler would
catch but a reader would not. (2026-09-21)

**See also:** `play_sound_to`

### `send_message(text: String) -> void`

*server/server_player.gd*

A chat message only this player sees.

### `show_title(text: String, subtitle := "", seconds := 3.0) -> void`

*server/server_player.gd*

Big text in the middle of the player's screen for a few seconds.

### `show_ui(ui_id: String, spec: Dictionary) -> void`

*server/server_player.gd*

Shows or replaces a server-defined UI panel. See engine/client/server_ui.gd for the spec format.

### `hide_ui(ui_id: String) -> void`

*server/server_player.gd*

Closes a server UI panel shown with show_ui.

### `is_creative() -> bool`

*server/server_player.gd*

Whether the player is in creative mode.

### `set_creative(enabled: bool) -> void`

*server/server_player.gd*

Switches the player between creative (true) and survival (false).

**See also:** `has_permission`, `on_join`, `set_flying`, `sync_inventory`

### `has_room(item: int, count := 1, item_data := {}) -> bool`

*server/server_player.gd*

Whether this many would fit in the pack. A reward can be dropped at a player's feet when it does not
(see give), but anything they are *paying* for should be refused instead: goods on the floor can be
missed, or despawn, and the coin is gone either way.

**See also:** `give`, `max_stack`, `space_for`

### `give(item: int, count := 1, item_data := {}) -> bool`

*server/server_player.gd*

Adds blocks or items (optionally with item data). Anything that does not fit falls at the player's
feet rather than vanishing, so a reward, a purchase or a quest payout is never lost to a full pack -
a mod would otherwise have to remember to check the return value every single time.

**True when it all fit.** This returned the number *dropped*, which meant `if player.give(...)`
read as "if it worked" and meant "if it failed" - the kind of thing that is right in the one place
somebody thought about it and wrong everywhere it was copied to. The count is still available from
`give_overflow` for the two callers that want to say how much ended up on the floor. (2026-09-21)

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `wake`

### `give_overflow(item: int, count := 1, item_data := {}) -> int`

*server/server_player.gd*

The same, returning how many did not fit and were dropped at their feet. 0 means it all fit.

**See also:** `drop_item`, `max_stack`, `realm_of`, `send_message`, `sync_inventory`

### `take(block: int, count := 1) -> bool`

*server/server_player.gd*

Removes items if the player has enough; returns false otherwise.

**See also:** `coop`, `get_item`, `max_stack`, `may_take`, `set_item`, `sync_inventory`

### `count_of(block: int) -> int`

*server/server_player.gd*

How many of a block or item the player carries.

### `clear_inventory() -> void`

*server/server_player.gd*

Empties the player's inventory.

**See also:** `sync_inventory`

### `drop(item: int, count := 1, item_data := {}) -> void`

*server/server_player.gd*

Drops items as an entity in front of the player.

**See also:** `drop_item`, `get_eye_position`, `look_direction`, `realm_of`

### `set_hotbar(blocks: Array, count := 1) -> void`

*server/server_player.gd*

Fills hotbar slots in order with the given block ids.

**See also:** `set_slot`, `sync_inventory`

### `get_item(slot: int) -> Dictionary`

*server/server_player.gd*

{item, count, data} in a slot (0-35 backpack, then equipment; see equipment_slot).

**See also:** `total`

### `set_item_data(slot: int, item_data: Dictionary) -> void`

*server/server_player.gd*

Replaces the item data of a slot (a copy is stored). Use it for wear, experience, levels,
upgrades, custom names ("name"), tooltip lines ("lore") and per-item stat "modifiers".

**See also:** `sync_inventory`, `total`

### `equipment_slot(slot_name: String) -> int`

*server/server_player.gd*

Inventory index of a named equipment slot ("head", "chest", ...), or -1.

**See also:** `equipment_index`

### `damage_item(slot: int, amount := 1, reason := "use") -> void`

*server/server_player.gd*

Wears down the item in a slot (respects the durability gameplay rule and item_durability event).

**See also:** `clear_slot`, `get_eye_position`, `look_direction`, `max_durability`, `play_effect`, `play_sound_at`

### `get_stats() -> Dictionary`

*server/server_player.gd*

Current stats (see ItemRegistry.BASE_STATS and register_stat).

**See also:** `refresh_stats`

### `get_stat(stat_name: String) -> float`

*server/server_player.gd*

One stat's current value (see get_stats).

### `add_modifier(id: String, stat: String, amount: float, op := "add", seconds := 0.0) -> void`

*server/server_player.gd*

Adds or replaces a stat modifier. `op`: "add" or "multiply" (amount 0.2 = +20%); `seconds` 0 = until
removed. Use ids like "my_mod:haste".

**See also:** `refresh_stats`

### `remove_modifier(id: String) -> void`

*server/server_player.gd*

Removes a stat modifier added with add_modifier.

**See also:** `now`, `refresh_stats`

### `refresh_stats() -> void`

*server/server_player.gd*

Recomputes stats now (after changing item data or modifiers outside the API).

**See also:** `compute`, `refresh_appearance`, `sync_health`

### `sync_inventory() -> void`

*server/server_player.gd*

Sends the inventory to the player after changing it directly (give and take do this for you).

**See also:** `data_to_network`, `refresh_stats`, `to_packed`

### `grant_cosmetic(cosmetic_name: String) -> void`

*server/server_player.gd*

Lets the player wear a server cosmetic registered with `unlocked: false`. Saved with the world.

**See also:** `get_def`, `refresh_avatar`

### `revoke_cosmetic(cosmetic_name: String) -> void`

*server/server_player.gd*

Takes back a server cosmetic granted with grant_cosmetic.

**See also:** `grant_cosmetic`

### `has_cosmetic(cosmetic_name: String) -> bool`

*server/server_player.gd*

Whether the player may wear a server cosmetic.

### `set_avatar_override(values: Dictionary) -> void`

*server/server_player.gd*

Avatar data laid over this player's look, e.g. a team uniform: {wear: {shirt: {id, color}}}; an
empty id takes a category off. Pass {} to clear. Not saved.

**See also:** `refresh_avatar`, `sanitize_avatar`

### `knows_recipe(recipe_id: String) -> bool`

*server/server_player.gd*

Whether the player can craft a recipe (discovered, or discovery is off).

**See also:** `index_of`

### `learn_recipe(recipe_id: String, source := "mod") -> bool`

*server/server_player.gd*

Teaches a recipe (source is passed to recipe_learned). Returns true if it was new.

**See also:** `index_of`

### `is_admin() -> bool`

*server/server_player.gd*

Whether the player is a server admin.

**See also:** `has_permission`

### `kick(reason: String) -> void`

*server/server_player.gd*

Disconnects the player with a reason.

**See also:** `allowed`, `apply_condition`, `block_state`, `chunk_coord_at`, `damage`, `damage_player`

### `save_items() -> Dictionary`

*server/server_player.gd*

The inventory, equipment and item data as saved with the world.
The inventory by item name, the saved form since save format 2: ids depend on which blocks and items
are registered, so they change between versions and mod sets; names do not.
{slots: [[index, name, count, data]], equipment: {slot: [name, count, data]}}

**See also:** `have`, `off`

### `load_items(saved) -> Array`

*server/server_player.gd*

Loads save_items() output. Returns the names of items this server does not have (they are left out).

**See also:** `equipment_index`, `set_slot`

### `bed_cells(pos: Vector3i) -> Dictionary`

*server/sleep.gd*

Both cells of a bed (the clicked one first), and the direction from foot to head.

**See also:** `facing_direction`, `get_block_state`, `get_block_v`, `is_bed`, `pair_position`

### `use_bed(p, pos: Vector3i) -> void`

*server/sleep.gd*

Right-click on a bed: set the respawn point, then try to sleep.

**See also:** `bed_cells`, `is_alive`, `is_night`, `needed_sleepers`, `refresh_appearance`, `send_message`

### `needed_sleepers() -> int`

*server/sleep.gd*

How many players must be asleep to skip the night.

### `stand_spot(anchor: Vector3i) -> Vector3`

*server/sleep.gd*

Where to stand next to a bed (respawning or getting up), or Vector3.INF if it is gone or boxed in.

**See also:** `bed_cells`, `get_block_v`

### `respawn_position(p) -> Vector3`

*server/sleep.gd*

The respawn position from a player's bed, or Vector3.INF (and a message) when it can't be used.

**See also:** `ensure_area_loaded`, `realm_of`, `send_message`, `stand_spot`

### `key: CryptoKey  (property)`

*server/status_query.gd*

The server's identity key (signs proofs for the hub); set by the server when it starts listening.

### `static overlaps_block(p: Vector3, block: Vector3i) -> bool`

*shared/player_physics.gd*

True if a player standing at feet position `p` overlaps the unit block at `block`.

### `static sanitize(def) -> Dictionary`

*shared/player_rig.gd*

Validates a rig from a mod or the network. Returns the default rig when anything is wrong.

**See also:** `condition_of`, `default_rig`, `merge`

### `static parse_request(packet: PackedByteArray) -> Dictionary`

*shared/server_status.gd*

{nonce, proof} of a valid request, or {}.

### `static proof_message(nonce: PackedByteArray) -> PackedByteArray`

*shared/server_status.gd*

The bytes a server signs to prove it holds its key.

### `static parse_response(packet: PackedByteArray) -> Dictionary`

*shared/server_status.gd*

{nonce, info} from a response, or {} when it is not one. Every field is checked and clamped.


## Effects, sound and weather

### `effects  (property)`

*client/weather_view.gd*

Set by the client: the EffectPlayer (it knows how to build an emitter) and the camera to follow.

### `current := -1  (property)`

*client/weather_view.gd*

Read by tests: which weather is drawn and how strongly it has faded in.

### `apply(weather_id: int, intensity: float) -> void`

*client/weather_view.gd*

The server's instruction. -1 is a clear sky. Not called show(): Node3D already has one.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `light_scale() -> float`

*client/weather_view.gd*

How much this weather is dimming the world, for whoever owns the light: 1.0 is untouched.

### `sky_tint() -> Dictionary`

*client/weather_view.gd*

The colour the sky is being pulled towards, and how far. Returns {} when nothing is happening.

### `register(def: Dictionary) -> String`

*server/ambience.gd*

Returns "" or why it was refused.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `register_category(def: Dictionary) -> bool`

*shared/cosmetics.gd*

def: name, display_name, attach (attachment point for boxes/models), covers (armor slots its
cosmetics replace by default). Returns false when invalid or full.

**See also:** `category`, `has_category`

### `register(def: Dictionary) -> String`

*shared/cosmetics.gd*

Registers (or replaces) a cosmetic. Returns its name, or "" when invalid.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `in_category(cat_name: String) -> Array`

*shared/cosmetics.gd*

Cosmetics of a category in registration order.

### `sanitize_avatar(avatar, can_wear := Callable(), keep_removals := false) -> Dictionary`

*shared/cosmetics.gd*

Cleans avatar data from a client, a mod or a file. `can_wear(id) -> bool` filters cosmetics the
player may not wear. With `keep_removals`, wear entries with an empty id survive (uniforms use them
to take a category off).

**See also:** `category`, `clean_color`, `get_def`, `is_color`

### `static merge(base: Dictionary, top: Dictionary) -> Dictionary`

*shared/cosmetics.gd*

`top` laid over `base`: its colors replace base colors, its wear replaces base wear per category
(an empty id removes the category).

**See also:** `compare`, `sha256`

### `static default_avatar(seed_text: String) -> Dictionary`

*shared/cosmetics.gd*

The look a player without avatar data gets, varied by name so players are told apart.

### `visible_armor(armor: Dictionary, avatar: Dictionary) -> Dictionary`

*shared/cosmetics.gd*

Which armor slots stay visible given the avatar's cosmetics, the player's choices and the policy.
`armor`: {slot: item id} -> the visible subset.

**See also:** `get_def`

### `to_network() -> Dictionary`

*shared/cosmetics.gd*

Built-in cosmetics are part of every client; only categories, server cosmetics and policy travel.

### `register(def: Dictionary) -> int`

*shared/effect_registry.gd*

Registers an effect (see the header). Returns its id, or -1.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of(effect_name: String) -> int`

*shared/effect_registry.gd*

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid(id: int) -> bool`

*shared/effect_registry.gd*

Whether anything is registered under this id.

### `static clean_options(options) -> Dictionary`

*shared/effect_registry.gd*

Cleans play options for the network: {color, scale, direction, duration}.

**See also:** `clean_color`, `is_color`

### `to_network() -> Array`

*shared/effect_registry.gd*

The effect table as the client receives it.

### `load_network(data) -> bool`

*shared/effect_registry.gd*

Rebuilds the table on the client. False when the data is not the shape we expect.

### `static is_color(value) -> bool`

*shared/effect_registry.gd*

Whether a mod wrote something we can read as a colour: `#rgb`, `#rrggbb` or `#rrggbbaa`.

### `static clean_color(value, fallback: String) -> String`

*shared/effect_registry.gd*

A mod's colour normalised to `#rrggbbaa`, or `fallback` if it is not one. Use this rather than
`Color.html`, which returns black for anything it cannot parse - and a silent black is very hard
to tell from a colour somebody meant.

**See also:** `is_color`

### `static emitter(e: Dictionary) -> Dictionary`

*shared/effect_registry.gd*

One emitter, read and clamped. Public because weather uses the same vocabulary: a mod should write an
emitter once and have it mean the same thing wherever it is used, defaults and limits included.

**See also:** `clean_color`, `is_color`

### `register(def: Dictionary) -> int`

*shared/music_registry.gd*

def: name, file (asset name), volume (0-2), loop (default true), attribution (required: who made it
and under what licence). Returns the id, or -1 with an error explaining which part was wrong.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of(track_name: String) -> int`

*shared/music_registry.gd*

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid(id: int) -> bool`

*shared/music_registry.gd*

Whether anything is registered under this id.

### `to_network() -> Array`

*shared/music_registry.gd*

The music table as the client receives it.

### `load_network(list) -> bool`

*shared/music_registry.gd*

Rebuilds the table on the client. False when the data is malformed.

### `credits() -> Array`

*shared/music_registry.gd*

Everything playing on this server, as lines a player can read: what it is and who made it. The
point of making attribution required is that it can be shown, so it is shown - /music credits.

### `register(def: Dictionary) -> int`

*shared/sound_registry.gd*

def: name, files (asset names), volume (linear, 0-2), pitch (1 = original), pitch_variance
(random +/- added to pitch), range (blocks until inaudible). Returns the id or -1.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of(sound_name: String) -> int`

*shared/sound_registry.gd*

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid(id: int) -> bool`

*shared/sound_registry.gd*

Whether anything is registered under this id.

### `to_network() -> Array`

*shared/sound_registry.gd*

The sound table as the client receives it.

### `load_network(data) -> bool`

*shared/sound_registry.gd*

Rebuilds the table on the client. False when the data is malformed.

### `register(def: Dictionary) -> int`

*shared/weather_registry.gd*

def: name, emitter (as an effect emitter), sound (looped while it falls), sky_tint ("#rrggbb"),
light_scale (0-1, how far it darkens the world), fog (0-1). Returns the id, or -1.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of(weather_name: String) -> int`

*shared/weather_registry.gd*

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid(id: int) -> bool`

*shared/weather_registry.gd*

Whether anything is registered under this id.

### `to_network() -> Array`

*shared/weather_registry.gd*

The weather table as the client receives it.

### `load_network(list) -> bool`

*shared/weather_registry.gd*

Rebuilds the table on the client. False when the data is malformed.


## Progression and story

### `crafting  (property)`

*client/guide_screen.gd*

The crafting screen: icons, recipe knowledge and station requirement text.

### `make_entity_view: Callable  (property)`

*client/guide_screen.gd*

Builds a Node3D model of an entity type by name (null if it has no model).

### `texture_of: Callable  (property)`

*client/guide_screen.gd*

Texture of an asset by name (image blocks).

### `open(page_id := "") -> void`

*client/guide_screen.gd*

Opens the book at a page ("" = the current page, or the first unlocked one).

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `add_unlocked(pages: PackedStringArray) -> Array`

*client/guide_screen.gd*

Adds newly unlocked pages; returns them.

**See also:** `chapter_pages`, `page_text`, `show_page`, `sorted_chapters`

### `lock_hint(page: Dictionary) -> String`

*client/guide_screen.gd*

What reveals a locked page.

**See also:** `get_page`, `index_of`

### `static key_name(action: String) -> String`

*client/guide_screen.gd*

The first key bound to an input action ("G", "Space", "Left Mouse").

### `step_done(kind: String) -> void`

*client/tutorial_hud.gd*

A step was finished: a quick green flash (the next step arrives with the view).

### `preferred_page(read: Dictionary) -> String`

*client/tutorial_hud.gd*

The page the G key should open: the tip on show, else the current step's page (if not read yet).

### `offer_worn(avatar: Dictionary) -> void`

*client/ugc_client.gd*

Offers the player's own creations worn in `avatar` to the server.

**See also:** `get_manifest`, `worn_ids`

### `ensure_known(avatar) -> void`

*client/ugc_client.gd*

Makes sure the creations in someone's avatar can be drawn: registers known ones, fetches the rest.

**See also:** `add_to`, `asset_name`, `cache_dir`, `get_def`, `get_manifest`, `get_payload`

### `fetch(ids: Array) -> void`

*client/ugc_client.gd*

Asks the server for creations (e.g. from the library) even if nobody wears them yet.

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `creation_ready(id: String) -> void`

*client/ugc_review.gd*

A creation's files arrived: draw its preview if it is the one on show.

**See also:** `select`

### `kinds := {}  (property)`

*server/characters.gd*

Name -> {name, display_name, color, lines: {id: {text, options}}, owner}

### `talk(player, character_name: String, options := {}) -> bool`

*server/characters.gd*

Opens a conversation. `options.line` is where to start - the mod's choice, because which line a
person opens on is a fact about their story and not about conversations. `options.entity` is who is
speaking, so a choice can say which one it was.

**See also:** `key_of`, `position_of`, `show_ui`, `velocity_of`

### `has_met(player, character_name: String) -> bool`

*server/characters.gd*

Whether this player has ever spoken to them, which is most of what "we have met" needs.

**See also:** `qualified`, `register_shop`

### `on_action(player, action: String) -> bool`

*server/characters.gd*

A button was pressed. Returns true if it was one of ours, so the caller knows whether to look
further.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `give`, `heat`

### `companies := {}  (property)`

*server/companies.gd*

id -> {id, name, members: {player_id: rank}, data}

### `at_least(id: int, player_id: String, rank: String) -> bool`

*server/companies.gd*

Whether this person is at least this rank.

**See also:** `rank_of`

### `of_player(player_id: String) -> Array`

*server/companies.gd*

Every company someone is in: [{id, name, rank}].

**See also:** `is_member`, `rank_of`

### `units := {}  (property)`

*server/flows.gd*

Unit name -> {name, owner}. A unit is just a name the engine keeps apart from other names.

### `on_received(unit: String, handler: Callable) -> void`

*server/flows.gd*

Told when what a face receives changes: ctx = {realm, position, face, unit, wanted, got}.

**See also:** `qualified`, `register_link_kind`

### `set_supply(unit: String, node: Dictionary, amount: float) -> void`

*server/flows.gd*

This face offers this much of `unit` per second (0 to stop).

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `set_demand(unit: String, node: Dictionary, amount: float) -> void`

*server/flows.gd*

This face wants this much per second (0 to stop asking).

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `received(unit: String, node: Dictionary) -> float`

*server/flows.gd*

What this face is actually receiving.

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `link_changed(a: Dictionary, b: Dictionary) -> void`

*server/flows.gd*

A link was made or cut: whatever it touched needs working out again.

**See also:** `key_name`, `node_key`

### `settle() -> void`

*server/flows.gd*

Works out every network that has changed since last time. Called once a tick from the server, which
is cheap when nothing changed - the usual case - because the dirty list is empty.

**See also:** `describe`, `drive_changed`, `get_block_v`, `node_of`, `qualified`, `reachable`

### `static state_of(p) -> Dictionary`

*server/guide.gd*

Per-player guide state: {flags, entities, read, unlocked (page id -> true), last}.

### `condition_met(p, page: Dictionary) -> bool`

*server/guide.gd*

Whether a page's unlock condition holds right now (ignores pages unlocked before).

**See also:** `knows_recipe`, `state_of`

### `refresh(p, notify := true) -> void`

*server/guide.gd*

Unlocks pages whose conditions now hold; tells the client (with a popup when `notify`).

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `sync(p) -> void`

*server/guide.gd*

Sends the full guide state after joining.

**See also:** `refresh`, `state_of`, `view`

### `unlock(p, page_id: String, notify := true) -> bool`

*server/guide.gd*

Unlocks a page right away, whatever its condition.

**See also:** `get_page`, `state_of`

### `open(p, page_id := "") -> void`

*server/guide.gd*

Opens the book for a player, at a page ("" = where they left off).

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `on_read(p, page_id: String) -> void`

*server/guide.gd*

The client shows a page: it counts as read (if unlocked) and is remembered as the last page.

**See also:** `get_page`, `refresh`, `state_of`

### `kinds := {}  (property)`

*server/ledgers.gd*

Name -> {name, display_name, levels, min, max, owner}

### `register(ledger_name: String, def: Dictionary, owner := "engine") -> bool`

*server/ledgers.gd*

def: display_name, levels (thresholds, lowest first - the value at which each level begins),
min and max (what the number may not go past; a balance that may not go negative sets min 0).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `set_value(player, ledger_name: String, value: float) -> float`

*server/ledgers.gd*

Sets it outright. Returns what it ended up as, which is not always what was asked for - a ledger
may have a floor or a ceiling, and saying so is more use than refusing.

**See also:** `describe`, `drive_changed`, `get_value`, `level_for`, `qualified`, `report_error`

### `add(player, ledger_name: String, amount: float) -> float`

*server/ledgers.gd*

Adds to it (a negative amount spends). Returns what it ended up as.

### `spend(player, ledger_name: String, amount: float) -> bool`

*server/ledgers.gd*

Takes `amount` only if there is that much, so a shop can be written without a check and a race
between the check and the spend. Returns false and changes nothing when there is not enough.

**See also:** `value_of`

### `level_for(ledger_name: String, value: float) -> int`

*server/ledgers.gd*

What level a value is at: 0 below the first threshold, 1 at it, and so on.

### `progress_of(player, ledger_name: String) -> Dictionary`

*server/ledgers.gd*

How far through the current level, 0 to 1, and what is left to the next. {level, value, into, needed,
next}, with `next` -1 at the top. For a bar on the screen, which is the usual reason to ask.

**See also:** `level_for`, `value_of`

### `all_of(player) -> Array`

*server/ledgers.gd*

Everything a player has, for a scoreboard or a screen: [{name, display_name, value, level}].

**See also:** `level_for`, `value_of`

### `kinds := {}  (property)`

*server/links.gd*

Kind name -> definition. See `register_kind`.

### `links := {}  (property)`

*server/links.gd*

Link id -> {kind, a: {realm, position, face}, b: {...}, length}

### `register_kind(kind_name: String, def: Dictionary, owner := "engine") -> bool`

*server/links.gd*

A kind of link a mod can lay.

def: `span` (blocks, capped at MAX_SPAN), `wireless` (nothing is drawn and no clear line is needed),
`crosses_realms` (wireless only), `needs_air` (refuse if anything solid is in the way; default true
for anything not wireless), `item` (what a block of it costs to lay), `draw` ("cable" sags, "pipe"
does not, "" draws nothing), `color` (what it is drawn in).

### `why_not(kind_name: String, a: Dictionary, b: Dictionary) -> String`

*server/links.gd*

Why these two nodes may not be joined, or "" if they may. Every refusal is a sentence somebody can
act on, because "cannot place" tells a child nothing.

**See also:** `get_block_v`, `key_name`, `node_key`

### `problem := ""  (property)`

*server/links.gd*

Joins two nodes. Returns the link id, or 0 with the reason in `problem`.

### `cut(id: int, why := "removed") -> bool`

*server/links.gd*

Removes a link and says so. `why` reaches the mod, which is how a player finds out their cable was
cut by a wall somebody built rather than simply stopping working.

**See also:** `key_name`, `node_key`

### `at_block(realm_id: String, pos: Vector3i) -> Array`

*server/links.gd*

Every link touching a block, whichever face. Used when one is mined.

**See also:** `node_key`

### `reachable(from: Dictionary, limit := 4096) -> Dictionary`

*server/links.gd*

Everything reachable from a node, as node keys. The graph traversal every layer above this uses.

**See also:** `key_name`, `node_key`

### `block_changed(realm_id: String, pos: Vector3i, old: int, block: int) -> void`

*server/links.gd*

A block was placed or broken. Links ending at it go; links *passing through* it are cut too, which
is the rule that stops a cable quietly running through a wall somebody built after it.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `to_saved() -> Array`

*server/links.gd*

What to save with the world. Links belong to the world rather than to a chunk: one end may be in a
chunk that is loaded and the other in one that is not, and a link that vanished because half of it
was asleep would be a very confusing bug.

### `register(id: String, def: Dictionary, qualify: Callable) -> bool`

*server/milestones.gd*

Registers one. `qualify` turns a bare name into a mod-qualified one, as it does for tutorials.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `remove_owner(owner: String) -> void`

*server/milestones.gd*

Drops a mod's milestones before it registers them again on reload. What players have already reached
stays in their data, so a reload does not hand the rewards out twice.

### `reached(p, id: String) -> bool`

*server/milestones.gd*

Whether this player has reached one, for mods that want to gate something behind it.

**See also:** `state_of`

### `view(p) -> Array`

*server/milestones.gd*

The list a player sees: what they have done, what is left, and how far along they are. Secret ones
stay out of the list until they are reached, so the surprise survives being able to read the list.

**See also:** `coop`, `index_of`, `invites_at`, `members`, `merge`, `project_fraction`

### `kinds := {}  (property)`

*server/objectives.gd*

Name -> {name, display_name, description, steps: [{text, count}], repeatable, owner}

### `give(player, objective_name: String) -> bool`

*server/objectives.gd*

Gives it to a player. Returns false if they already have it, have finished one that cannot be
repeated, or are carrying as many as they may.

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `wake`

### `advance(player, objective_name: String, amount := 1) -> bool`

*server/objectives.gd*

Counts `amount` towards the step they are on. When the step is filled it moves on, and when the
last one is filled the whole thing is done - which is `objective_done`, where a mod hands out
whatever it thinks the reward is. The engine has no idea what a reward would be.

**See also:** `advance`, `biome_at`, `give`, `has_flag`, `is_night`, `play_sound_to`

### `abandon(player, objective_name: String) -> bool`

*server/objectives.gd*

Gives up on one. Kept separate from finishing it, because "I am not doing this" and "I did this"
are different things and a mod may want to say so.

### `active_for(player) -> Array`

*server/objectives.gd*

What they are doing now: [{name, display_name, step, of, text, progress, needed}].

### `finished(player, objective_name: String) -> int`

*server/objectives.gd*

How many times they have finished it (0 if never).

### `kinds := {}  (property)`

*server/shops.gd*

Name -> {name, display_name, offers: [...], owner}

### `problem := ""  (property)`

*server/shops.gd*

Why the last buy failed, in words a child can read.

### `left_of(shop_name: String, index: int) -> int`

*server/shops.gd*

How many of this offer are left, refilling first if it is time. Unlimited offers say -1.

### `offers_for(player, shop_name: String) -> Array`

*server/shops.gd*

What a player would see: [{index, item, name, count, price, ledger, cost, sells, left, can}].

**See also:** `count_of`, `has_room`, `left_of`, `value_of`

### `trade(player, shop_name: String, index: int) -> bool`

*server/shops.gd*

Does the trade. Everything is checked before anything moves, so a failure halfway leaves a player
with neither the coin nor the goods - which has happened in enough games to be worth the care.

**See also:** `count_of`, `give`, `has_room`, `left_of`, `spend`, `take`

### `show(player, shop_name: String) -> bool`

*server/shops.gd*

Opens the shop panel. Drawn by the engine so every shop in every mod looks the same, which is the
whole reason this is a capability and not thirty lines in a mod.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `heat`, `hold_fraction`

### `on_action(player, action: String) -> bool`

*server/shops.gd*

A button was pressed. Returns true if it was one of ours.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `give`, `heat`

### `to_saved() -> Dictionary`

*server/shops.gd*

Stock is saved: a village whose shelves refill every restart is a village worth restarting for.

### `levels := {}  # Vector3i -> int  (property)`

*server/signals.gd*

Where a level is, and how strong. Only cells above zero are kept, so an unpowered world costs nothing.

### `sources := {}  # Vector3i -> int  (property)`

*server/signals.gd*

Levels a mod has put on particular blocks (a lever that is on). Block types that always emit are
read from the registry instead, so a thousand torches cost no memory.

### `origins := {}  # Vector3i -> Vector3i  (property)`

*server/signals.gd*

Which source each powered cell's level came from. A gate must not hear its own voice come back to it
through the wire it is driving - which is not the same as not hearing its own cell, and cost an
afternoon to tell apart. (2026-09-19)

### `handlers := {}  (property)`

*server/signals.gd*

Block id -> {handler, owner}: told when the level arriving at one of these changes.

### `register(block: int, handler: Callable, owner := "engine") -> void`

*server/signals.gd*

Tells `handler(ctx)` when the level reaching a block of this type changes.
ctx = {position, block, level, previous, realm}.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `set_source(pos: Vector3i, level: int) -> void`

*server/signals.gd*

Makes the block at `pos` emit `level` (0 stops it). This is how a lever, a plate or a mod's own
gate speaks: the engine never learns what any of them are.

**See also:** `get_block_v`, `key_name`, `node_key`, `reaching`, `record`

### `level_at(pos: Vector3i) -> int`

*server/signals.gd*

The level in a cell: what a carrier there is carrying.

### `reaching(pos: Vector3i) -> int`

*server/signals.gd*

The strongest level arriving at a block **from elsewhere** - what a receiver acts on.

Deliberately not counting what the block itself emits. A gate that heard its own output would
oscillate for ever the moment a mod wrote the most obvious thing there is - "emit when nothing
reaches me" - and the first version of this did exactly that, with a stack overflow to show for it.
A thing does not hear itself speak.

**See also:** `get_block_v`

### `block_changed(pos: Vector3i, old: int, block: int) -> void`

*server/signals.gd*

A block was placed or broken: the network around it may be a different shape now.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `unload_chunk(coord: Vector2i) -> void`

*server/signals.gd*

Forgets a chunk's levels. Nothing is written: a level follows from the sources, and they are saved
with the blocks, so it is worked out again when somebody comes back.

**See also:** `chunk_coord_at`, `chunk_coord_of`, `serialize_chunk`

### `register_tutorial(id: String, def: Dictionary, qualify: Callable) -> bool`

*server/tutorials.gd*

`qualify(name) -> String` turns local names into full ones.

**See also:** `add_handler`, `announce`, `qualified`

### `remove_owner(owner: String) -> void`

*server/tutorials.gd*

Drops a mod's tutorials and tips (before it registers them again on reload). Players in one of its
tutorials keep their place if the tutorial comes back with enough steps.

### `revalidate() -> void`

*server/tutorials.gd*

Checks players' tutorial progress after a reload, and resends their trackers.

**See also:** `state_of`, `sync`

### `to_network() -> Array`

*server/tutorials.gd*

Tutorials in order: [{id, title, description, steps}] for clients.

### `static state_of(p) -> Dictionary`

*server/tutorials.gd*

{active, step, progress, done: {id: true}, stopped: {id: true}, tips: {id: true}, tips_off}

### `on_join(p) -> void`

*server/tutorials.gd*

After joining (or switching to survival): resumes the active tutorial or starts the first
auto-start one not yet done or stopped.

**See also:** `start`, `state_of`, `sync`

### `stop(p) -> void`

*server/tutorials.gd*

Stops the active tutorial (it will not start by itself again).

**See also:** `close`, `state_of`, `step`, `sync`, `unsubscribe`

### `advance(p, skipped := false) -> void`

*server/tutorials.gd*

Completes the current step (skip, or a "manual" goal done by a mod).

**See also:** `advance`, `biome_at`, `give`, `has_flag`, `is_night`, `play_sound_to`

### `view(p) -> Dictionary`

*server/tutorials.gd*

The tracker the client draws: {} when no tutorial is running.

**See also:** `coop`, `index_of`, `invites_at`, `members`, `merge`, `project_fraction`

### `show_tip(p, id: String) -> bool`

*server/tutorials.gd*

Shows a tip now (registered id), even if it was seen before.

**See also:** `icon_of`, `key_name`, `library`, `node_key`, `qualified`, `state_of`

### `store := {}  (property)`

*server/ugc.gd*

id -> {manifest, status, reason, uploaded_by (player id), uploaded_at, size}

**See also:** `is_valid_hash`, `open`, `sha256`

### `blocked := {}  (property)`

*server/ugc.gd*

Content ids refused for good (removed creations), id -> reason.

### `banned_creators := {}  (property)`

*server/ugc.gd*

Player ids that may not upload, player id -> reason.

### `trusted := {}  (property)`

*server/ugc.gd*

Player ids whose uploads are approved at once under "trusted".

### `revision := 0  (property)`

*server/ugc.gd*

Goes up whenever creations, reports, trust or bans change (the dashboard reloads its list).

### `can_wear(p, id: String) -> bool`

*server/ugc.gd*

Whether a player may wear a creation here.

**See also:** `get_def`, `is_approved`, `is_blocked`, `is_builtin`, `is_id`, `look`

### `ensure_registered(ids: Array) -> void`

*server/ugc.gd*

Registers approved creations as cosmetics so avatars can use them.

**See also:** `get_def`, `is_approved`, `is_id`, `payload`, `register`, `to_cosmetic`

### `static worn_ids(avatar) -> Array`

*server/ugc.gd*

Creation ids worn in an avatar dictionary.

**See also:** `is_id`

### `offer(p, manifests: Array) -> Dictionary`

*server/ugc.gd*

A client offers creations it wears. Returns {request: [ids], status: {id: [status, reason]}}.

**See also:** `is_id`

### `upload_piece(p, id: String, offset: int, total: int, bytes: PackedByteArray) -> void`

*server/ugc.gd*

A piece of an upload. Completes (validates and stores) when the last piece arrives.

**See also:** `close`, `ensure_registered`, `is_admin`, `open`, `payload_extension`, `reapply_requested_avatar`

### `set_status(id: String, status: String, reason := "", by := "") -> bool`

*server/ugc.gd*

Changes a creation's status (moderation). "removed" also blocks the content for good.

**See also:** `draw`, `ensure_registered`, `payload_extension`, `reapply_requested_avatar`, `save_index`, `worn_ids`

### `fetch(p, ids: PackedStringArray) -> void`

*server/ugc.gd*

A client asks for creations it needs to draw (or browse).

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `library(query := {}, offset := 0, count := 48) -> Dictionary`

*server/ugc.gd*

Approved creations others may wear, newest first: [{manifest..., uses}] filtered by kind/category/text.

### `report(p, id: String, reason: String, details := "") -> String`

*server/ugc.gd*

A player reports a creation. Returns "" or why it was not accepted.

**See also:** `save_index`, `set_status`, `tell_moderators`

### `review_list(filter := "pending", text := "") -> Array`

*server/ugc.gd*

Creations for review: filter pending | reported | approved | rejected | removed | all, newest first.

### `resolve_id(text: String) -> String`

*server/ugc.gd*

Finds a creation by id or a unique start of it ("3f2a", "ugc:3f2a"). "" when none or ambiguous.

### `set_banned(player_id: String, on: bool, reason := "", by := "") -> void`

*server/ugc.gd*

Bans (or unbans) a creator from uploading. Banning also hides their creations (rejected); unbanning
leaves them hidden until approved again.

**See also:** `save_index`, `set_status`

### `add_chapter(def: Dictionary) -> bool`

*shared/guide_registry.gd*

Adds a guidebook chapter. False if it has no id, or one is already registered under that id.

### `add_page(def: Dictionary) -> bool`

*shared/guide_registry.gd*

Adds a page to a chapter. False if it has no id, or one is already registered under that id.

### `remove_owner(owner: String) -> void`

*shared/guide_registry.gd*

Drops everything a mod registered (before it registers again on reload).

### `clear() -> void`

*shared/guide_registry.gd*

Empties the book. The client calls this before loading the server's copy, so a second world does
not inherit the first one's pages.

### `get_page(id: String) -> Dictionary`

*shared/guide_registry.gd*

One page, or `{}` if there is no such page.

### `get_chapter(id: String) -> Dictionary`

*shared/guide_registry.gd*

One chapter, or `{}` if there is no such chapter.

### `chapter_pages(chapter_id: String) -> Array`

*shared/guide_registry.gd*

Pages of a chapter in order.

### `sorted_chapters() -> Array`

*shared/guide_registry.gd*

Chapters in the order a player should see them: by `order`, then by title so the result is stable
when two chapters share one.

### `static page_text(page: Dictionary) -> String`

*shared/guide_registry.gd*

Plain searchable text of a page (title, keywords and text blocks).

### `to_network() -> Dictionary`

*shared/guide_registry.gd*

The whole book as the client receives it.

### `load_network(data) -> void`

*shared/guide_registry.gd*

Replaces the client's book with the server's.


## Mods, loading and validation

### `index: Array = []  (property)`

*client/menu/mod_browser.gd*

What the site offers, from the last fetch (or the cached copy from last time).

### `busy := false  (property)`

*client/menu/mod_browser.gd*

True while a fetch or an install is running, so the screen can disable its buttons.

### `refresh(force := false) -> void`

*client/menu/mod_browser.gd*

Fetches the mod index. `force` asks again even if it was already fetched this session.

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `install(entry: Dictionary) -> void`

*client/menu/mod_browser.gd*

Downloads and installs one mod, and anything it needs that is missing. `entry` is a row from the index.

**See also:** `close`, `download`, `install_package`, `installed`, `installed_path`, `installer`

### `remove(id: String, mod_name := "") -> void`

*client/menu/mod_browser.gd*

Takes a mod off this computer.

### `static installed() -> Array`

*client/mod_catalog.gd*

What the player has, as [{id, name, version, description, game, depends, dir, removable, kind}].

**See also:** `discover`, `is_removable`, `kind_of`, `search_dirs`

### `static kind_of(manifest: Dictionary) -> String`

*client/mod_catalog.gd*

What a mod is for, so the screen can group them: a game to play, an add-on for a game, a library other
mods build on, or an example to read.

### `static is_removable(dir: String) -> bool`

*client/mod_catalog.gd*

True for a mod the player installed themselves (the only ones Remove may touch).

**See also:** `user_mods`

### `static cached_index() -> Dictionary`

*client/mod_catalog.gd*

The index as it was last fetched ({version, mods: [...]}), or {} the first time.

### `static index_url() -> String`

*client/mod_catalog.gd*

Where the mod index lives: next to the update manifest, on the address built into the client.

**See also:** `manifest_url`

### `static read_index(text: String) -> Array`

*client/mod_catalog.gd*

Checks an index and returns its entries as [{id, name, version, description, url, sha256, size, kind}],
dropping anything malformed or from an address the client does not trust.

**See also:** `url_allowed`

### `static cache_index(text: String) -> void`

*client/mod_catalog.gd*

Keeps an index for next time (so the screen works offline). Silently does nothing if it cannot.

**See also:** `close`, `open`

### `static merge(installed_mods: Array, index: Array) -> Array`

*client/mod_catalog.gd*

The installed mods and the index as one list for the screen: [{..., state}], where state is
"installed" (nothing to do), "update" (a newer version is offered), or "available" (not installed).

**See also:** `compare`, `sha256`

### `static install_package(bytes: PackedByteArray, expect_id := "") -> String`

*client/mod_catalog.gd*

Unpacks a downloaded mod zip into user://mods/<id>/, replacing an older copy. Returns "" or the problem.
The bytes must already have been checked against the index's sha256 (see Updater.verify).

**See also:** `close`, `download`, `install_file`, `open`

### `static install_file(package_path: String, expect_id := "") -> String`

*client/mod_catalog.gd*

Unpacks a mod zip from a path into user://mods/<id>/. Returns "" or the problem.

**See also:** `open`, `read_manifest`, `unpack`, `user_mods`

### `static remove(id: String) -> String`

*client/mod_catalog.gd*

Takes an installed mod off this computer. Only mods in user://mods may be removed - the ones inside the
app come back with every update anyway. Returns "" or the problem.

### `static needed_by(id: String, installed_mods: Array) -> Array`

*client/mod_catalog.gd*

Which installed mods need `id`, so the screen can warn before it is removed.

### `static missing_dependencies(entry: Dictionary, installed_mods: Array, index: Array) -> Array`

*client/mod_catalog.gd*

The mods that have to be installed before `entry` can run, from what the index offers.

### `to_js(value)`

*server/js_mod.gd*

Engine values -> JSON-safe values for the prelude.

### `setup(_api) -> void`

*server/mod.gd*

Called once at server start, after all dependencies have run their setup.
Register blocks, event handlers, commands and world hooks through `api` (see mod_api.gd).

### `static cache_dir() -> String`

*server/mod_loader.gd*

Unpacked mods and the player's own mods folder. QW_USER_DIR moves both, so a test run does not
unpack its fixtures into the player's folder.

### `static search_dirs(configured: PackedStringArray) -> PackedStringArray`

*server/mod_loader.gd*

Where mods are searched, highest priority first: configured folders, a `mods` folder next to the
executable (exported builds ship mods there as plain files, since exports would otherwise repack
the raw textures and models the server streams to clients), mods created in game (user://mods), then
the project's own res://mods.

**See also:** `user_mods`

### `static creation_dir() -> String`

*server/mod_loader.gd*

Where the game's "Create a mod" puts new mods: the project's mods folder when running from the editor
or source, otherwise user://mods.

**See also:** `user_mods`

### `static discover(dirs: PackedStringArray) -> Dictionary`

*server/mod_loader.gd*

Returns id -> manifest for every valid mod folder or package in `dirs`. Manifests gain `dir` (and
`package` for zips).

**See also:** `open`, `read_manifest`, `unpack`

### `static read_manifest(mod_dir: String) -> Dictionary`

*server/mod_loader.gd*

Reads and normalizes <dir>/mod.json. Returns the manifest, or {error}.

**See also:** `parse`, `parse_dependencies`

### `static parse_dependencies(value) -> Array`

*server/mod_loader.gd*

Dependencies as [{id, version}] from ["id", "id@range", {id, version}] or {id: range}.

**See also:** `order`

### `static resolve(requested: PackedStringArray, available: Dictionary) -> Array`

*server/mod_loader.gd*

Returns manifests in load order (dependencies first), or an empty Array on error (see last_errors).

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `static unpack(package_path: String) -> Dictionary`

*server/mod_loader.gd*

Unpacks a mod package into the cache (once per package content). Returns {dir} or {error}.

**See also:** `cache_dir`, `close`, `finish`, `open`, `start`

### `static pack(mod_dir: String, zip_path: String) -> Error`

*server/mod_loader.gd*

Writes a mod folder into a .zip (mod.json at the root). Skips Godot's import metadata. Returns OK.

**See also:** `close`, `open`

### `reload(mod_id: String) -> Dictionary`

*server/mod_reload.gd*

Re-runs a mod's setup. Returns {ok, mod, ms, notes: [String], error}.

**See also:** `after_mod_reload`, `begin_reload`, `close`, `drain`, `end_reload`, `forget`

### `reload_all() -> Array`

*server/mod_reload.gd*

Reloads every mod in load order (dependencies first).

**See also:** `place`, `reload`

### `register(mod_id: String, schema: Dictionary) -> void`

*server/mod_settings.gd*

Declares a mod's settings. A malformed entry is dropped with a warning rather than taken as a value,
so a typo in a mod cannot stop the server from starting.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `get_value(mod_id: String, key: String)`

*server/mod_settings.gd*

The value in force for a mod's setting: its default until a file or an admin changed it. null when the
mod never declared it.

### `set_value(mod_id: String, key: String, value) -> String`

*server/mod_settings.gd*

Changes one setting and saves it with the world. Returns "" or why it was refused; tells the mod
through `settings_changed` so it can react without a restart.

**See also:** `describe`, `drive_changed`, `get_value`, `level_for`, `qualified`, `report_error`

### `reset(mod_id: String, key: String) -> String`

*server/mod_settings.gd*

Puts a setting back to its default (and to whatever the data folder's file says).

**See also:** `describe`, `drive_changed`, `get_value`, `qualified`, `to_saved`

### `list(mod_id := "") -> Array`

*server/mod_settings.gd*

Every setting of every mod (or one mod), for the admin screen and /modsettings:
[{mod, key, type, label, help, value, default, changed, ...}], in a stable order.

**See also:** `get_value`, `is_id`, `open`, `read_meta`

### `mods() -> Array`

*server/mod_settings.gd*

Ids of the mods that have settings, in load order.

### `static describe(entry: Dictionary) -> String`

*server/mod_settings.gd*

What a setting accepts, for an error message or a tooltip.

**See also:** `kind_of`

### `load_sources(meta: Dictionary, data_dir: String, override := "") -> void`

*server/mod_settings.gd*

Reads the values a host set outside the game, before the mods load, so a mod can read its own settings
while it is still starting up. `override` is a path to a JSON file or the JSON itself (--mod-settings).

**See also:** `describe`, `drive_changed`, `merge`, `qualified`

### `to_saved() -> Dictionary`

*server/mod_settings.gd*

What goes into world.json: the values an admin set, untouched for mods that are not loaded now.

### `static create(parent_dir: String, options: Dictionary) -> Dictionary`

*server/mod_templates.gd*

options: id, name, language ("gdscript" | "javascript"), kind ("addon" | "game"), author, description.
Returns {ok, dir, files: [relative paths], error}.

**See also:** `broadcast_entity_event`, `close`, `create`, `enabled`, `exists`, `heading`

### `static id_from_name(display_name: String) -> String`

*server/mod_templates.gd*

A valid id from a display name ("My Cool Mod" -> "my_cool_mod").

### `static validate(mod_dir: String, parent: Node, search_dirs := PackedStringArray()) -> Dictionary`

*server/mod_validator.gd*

Every check. Returns {mod, ok, issues: [...], counts: {error, warning, hint}}.

**See also:** `check_files`, `check_manifest`, `check_references`, `check_scripts`, `check_structures`, `check_unused_files`

### `static check_running(server, mod_id: String) -> Dictionary`

*server/mod_validator.gd*

The checks that need no fresh load, on a running server.

**See also:** `check_files`, `check_manifest`, `check_references`, `sorted_errors`

### `static report(result: Dictionary) -> PackedStringArray`

*server/mod_validator.gd*

Human-readable report lines.

**See also:** `save_index`, `set_status`, `tell_moderators`

### `static check_scripts(mod_dir: String) -> Array`

*server/mod_validator.gd*

Compiles every GDScript in the mod (JavaScript is checked by loading it).

**See also:** `open`, `reload`

### `static check_unused_files(server, mod_dir: String, manifest: Dictionary) -> Array`

*server/mod_validator.gd*

Files in the mod folder that nothing loads (not a script, data file or registered asset).

**See also:** `open`

### `declared := {}  (property)`

*server/sources.gd*

Sources a mod declared: item id -> [{kind, from, detail}].

### `declare(item_id: int, source: Dictionary) -> bool`

*server/sources.gd*

Adds a source nothing could infer. `detail` is shown to a player, so write it as a sentence.

### `of_item(item_id: int) -> Array`

*server/sources.gd*

Everywhere `item_id` comes from, most likely first. Always returns an Array.

**See also:** `sources_of`, `table_for_block`, `table_for_entity`

### `static parse(text: String) -> Array`

*shared/semver.gd*

[major, minor, patch, prerelease] or [] when not a version.

### `static compare(a: String, b: String) -> int`

*shared/semver.gd*

-1, 0 or 1.

**See also:** `parse`

### `static satisfies(version: String, range_text: String) -> bool`

*shared/semver.gd*

Whether `version` satisfies `range_text`.

**See also:** `parse`

### `static range_error(range_text: String) -> String`

*shared/semver.gd*

Whether a range string can be understood at all ("" when fine, else the problem).

**See also:** `parse`

### `members := {}  (property)`

*shared/tag_registry.gd*

Tag name -> {member name: true}. Members are kept by *name* rather than by id because ids move
whenever a mod is added, and a tag outlives the run that defined it.

### `add(tag_name: String, names: Array) -> int`

*shared/tag_registry.gd*

Adds names to a tag, creating it if need be. Returns the number actually added.

### `names_in(tag_name: String) -> Array`

*shared/tag_registry.gd*

The names in a tag, or an empty array. A tag nobody defined is empty rather than an error: a mod
that works with another one when it is installed should not have to guard every call.

### `has(tag_name: String, name: String) -> bool`

*shared/tag_registry.gd*

Whether a thing is in a tag. This is the cheap question - `tags_of` walks every tag, this does not.

### `exists(tag_name: String) -> bool`

*shared/tag_registry.gd*

Whether anything has ever been put in this tag. A tag nobody filled is absent, not empty.

### `tags_of(name: String) -> Array`

*shared/tag_registry.gd*

Every tag something is in. Walks all of them, so it is for tools and questions rather than for
anything on the hot path.

**See also:** `qualified`

### `namespaces() -> Array`

*shared/tag_registry.gd*

The namespaces tags have been written for ("base", "cherry"), for warning about ones that no
installed mod owns.


## Saving, network and protocol

### `static check_and_pin(endpoint: String, certificate_pem: String) -> String`

*net/known_servers.gd*

Pins `certificate_pem` for `endpoint` if nothing is pinned yet. Returns "" when the certificate
matches (or was just pinned), otherwise a message explaining the mismatch.
PEM text is compared directly (X509Certificate.save_to_string() adds a NUL character).

**See also:** `open`, `path_for`

### `server: Node = null  (property)`

*net/net.gd*

Set by GameServer when running as a server.

### `client: Node = null  (property)`

*net/net.gd*

Set by GameClient when running as a client.

### `pin_servers := true  (property)`

*net/net.gd*

Client: pin server certificates (load-test bots turn this off).

### `create_server(port: int, max_players: int, tls_key: CryptoKey, tls_cert: X509Certificate, cert_pem: String) -> Error`

*net/net.gd*

`tls_key`/`tls_cert`: the server's identity. Traffic is always encrypted with DTLS.

**See also:** `close`

### `create_client(address: String, port: int, protocol_override := -1) -> Error`

*net/net.gd*

Connects over DTLS. If this server's certificate was seen before, the DTLS handshake verifies it,
so an impostor cannot complete the connection; the first connection trusts and pins it.

**See also:** `close`, `load_certificate`

### `static load_or_create_server_identity(dir: String) -> Array`

*net/net.gd*

Loads the server's DTLS identity from `dir`, creating a self-signed one on first start.
Returns [CryptoKey, X509Certificate, certificate PEM text].

**See also:** `load`, `save`

### `peer_rtt_ms(peer_id: int) -> int`

*net/net.gd*

Server side: a client's round-trip time in milliseconds (0 if unknown).

### `code := ""  (property)`

*server/hub_announcer.gd*

The hub's invite code for this server ("QW-ABC-123"), once listed.

### `problem := ""  (property)`

*server/hub_announcer.gd*

"" while fine, else why the last announce failed (shown to admins and in the log once per change).

### `leave() -> void`

*server/hub_announcer.gd*

Asks the hub to drop the listing (best effort, on shutdown: a blocking request with a short timeout).

**See also:** `allowed`, `close`, `finish`, `get_block`, `send_to_realm`, `sign`

### `transfer(p, target: String, options := {}) -> String`

*server/transfers.gd*

Sends a player to another server. options: {arrival, data (a small Dictionary for mods), reason}.
Returns "" or why not.

**See also:** `kick`, `make`, `pack_inventory`, `save_items`, `save_player`, `schedule`

### `pack_inventory(p) -> Dictionary`

*server/transfers.gd*

Items by name (ids differ between servers): see ServerPlayer.save_items.

**See also:** `save_items`

### `unpack_inventory(p, packed) -> Array`

*server/transfers.gd*

Puts a carried inventory into the player's; returns the names of items this server does not have.

**See also:** `load_items`

### `settle_escrow(p, arrived_by_ticket: bool) -> void`

*server/transfers.gd*

A player who joined without a transfer ticket but has a travelling inventory held here: give it back.
Arriving with a ticket (from anywhere in the network) drops the held copy instead.

**See also:** `send_message`, `sync_inventory`, `unpack_inventory`

### `accept(ticket: String, signature: String, player_id: String) -> Dictionary`

*server/transfers.gd*

A joining player's ticket, checked once they have proven their identity. Returns {entry, data} for an
accepted ticket, or {error}.

**See also:** `check`, `verify`

### `arrival_position(accepted: Dictionary) -> Vector3`

*server/transfers.gd*

Where an arriving player appears: the ticket's named arrival point, or Vector3.INF (their usual place).

### `arrive(p, accepted: Dictionary) -> void`

*server/transfers.gd*

After an arriving player spawned: give what they carried and tell mods.

**See also:** `send_message`, `sync_health`, `sync_inventory`, `unpack_inventory`

### `portal_at(position: Vector3, into = null) -> Dictionary`

*server/transfers.gd*

The portal settings of a portal block at the player's feet or body, or {}.
The portal a player is standing in, or {}. Its block data says where it goes: `server` for another
machine, or `realm` for another world on this one. Both are portals to a player, so both are read
here rather than growing a second block with a second timer that feels slightly different.

**See also:** `get_block_data`, `get_block_v`

### `static encode(address: String, port: int) -> String`

*shared/invite_code.gd*

The code for an IPv4 address, or "" when the address is not IPv4.

### `static share_text(address: String, port: int) -> String`

*shared/invite_code.gd*

What someone shares: an invite code when possible, else "address:port".

**See also:** `encode`

### `static parse(text: String) -> Dictionary`

*shared/invite_code.gd*

{address, port} from a code or "host[:port]" text, or {error}.

### `static local_address() -> String`

*shared/invite_code.gd*

The first private IPv4 address of this computer (to invite people on the same network), or "".

### `static create(native_class: StringName) -> Object`

*shared/native.gd*

Returns a new instance of a native class, or null when the extension is unavailable.

**See also:** `broadcast_entity_event`, `close`, `create`, `enabled`, `exists`, `heading`

### `static key_id(key: CryptoKey) -> String`

*shared/transfer_ticket.gd*

The id servers use for each other: the first 32 hex characters of SHA-256 over the public key PEM.

**See also:** `pem_id`

### `static make(source_key: CryptoKey, fields: Dictionary) -> Dictionary`

*shared/transfer_ticket.gd*

{ticket: JSON text, signature: base64}

**See also:** `content_id`, `finish`, `key_id`, `sign`, `start`

### `static verify(ticket: String, signature: String, trusted: Dictionary) -> Dictionary`

*shared/transfer_ticket.gd*

Checks a ticket's signature and shape. `trusted`: source id -> anything truthy.
Returns {ok: true, data} or {ok: false, error}. Expiry, destination and replay are the caller's checks
too (see `check`), since they need the destination's own details.

**See also:** `finish`, `pem_id`, `start`

### `static check(data: Dictionary, player_id: String, own_id: String, now: int) -> String`

*shared/transfer_ticket.gd*

The destination's checks after `verify`: the logged-in player, this server, time.

**See also:** `compare`, `fetch`, `installed_path`, `manifest_url`, `parse`, `platform`

### `static path(relative: String) -> String`

*shared/user_paths.gd*

`relative` is what would have followed `user://`, e.g. "cache/assets" or "crafting_pins.cfg".

### `static redirected() -> bool`

*shared/user_paths.gd*

Whether this process has been moved out of the player's folder. Tests assert on it, because the whole
point is that it is true while they run and false while somebody is playing.


## Dev tools and logging

### `current_mod := ""  (property)`

*server/dev_log.gd*

The mod whose setup() is running, if any. Errors raised while it is set belong to it.

### `open_file(save_dir: String) -> void`

*server/dev_log.gd*

Opens <save_dir>/logs/latest.log, moving the previous one aside.

**See also:** `close`, `open`, `set_look`

### `mod_of_file(file: String) -> String`

*server/dev_log.gd*

Which mod a script file belongs to ("" when none).

### `add(level: String, source: String, message: String, extra := {}, echo := true) -> Dictionary`

*server/dev_log.gd*

Adds a message. Returns the entry, or {} when filtered out.
`echo` prints it to the console (off for lines that were captured from the console already).

### `report_error(source: String, message: String, file := "", line := 0, stack := [], level := "error") -> Dictionary`

*server/dev_log.gd*

Records an error (grouped with identical ones) and logs it once per group.

### `recent(count := 50, source := "", min_level := "debug", text := "") -> Array`

*server/dev_log.gd*

Recent entries, newest last: filtered by source ("" = all), minimum level and text.

### `drain() -> void`

*server/dev_log.gd*

Moves what Godot reported (from any thread) into the log. Call every frame on the main thread.

**See also:** `mod_of_file`, `report_error`, `unlock`

### `viewers := {}  (property)`

*server/dev_tools.gd*

peer id -> {channels: {name: true}, inspect: {...target}, trace_filter: String, log_after: int}

### `timed(owner: String, category: String, callable: Callable, args := [])`

*server/dev_tools.gd*

Calls `callable` with `args`, timing it for `owner`.

**See also:** `record`

### `perf() -> Array`

*server/dev_tools.gd*

[{owner, category, calls, ms_per_s, avg_ms, max_ms}] over the last WINDOWS seconds, slowest first,
plus owner totals ({owner, category: "total"}).

### `dispatch(event: String, handlers: Array, payload: Dictionary) -> Dictionary`

*server/dev_tools.gd*

Emits `payload` to `handlers` ([priority, callable, owner]), timing each handler and recording the
event when tracing. Returns the payload.

**See also:** `describe`, `record`

### `describe(value, key := "", depth := 0)`

*server/dev_tools.gd*

A JSON-friendly copy of a value: players, entities, vectors and block/item ids become readable.

**See also:** `kind_of`

### `inspect(target: Dictionary) -> Dictionary`

*server/dev_tools.gd*

target: {pos: Vector3i} | {entity: id} | {player: peer id}

**See also:** `biome_at`, `describe`, `evaluate`, `get_block_data`, `get_block_state`, `get_block_v`

### `draw(owner: String, shape: Dictionary) -> void`

*server/dev_tools.gd*

shape: {type: box | line | text | path | sphere, color, seconds, ...}; box {min, max} or {center, size},
line {from, to}, text {position, text}, path {points}, sphere {center, radius}.

### `start(listen_port: int, bind_host := "127.0.0.1", keep_token := "") -> Error`

*server/dev_web.gd*

`keep_token`: reuse a token (a full reload keeps open dashboards working).

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `streaming() -> bool`

*server/dev_web.gd*

True when the native server (with live push) is in use.


## The client

### `last_state := {}  (property)`

*client/admin/worlds_panel.gd*

What the server last sent (also read by tests).

### `voxels := {}  (property)`

*client/avatar/accessory_builder.gd*

Vector3i (skin pixels from the attachment point) -> "#rrggbb".

### `apply_at(cell: Vector2i, erase := false) -> void`

*client/avatar/accessory_builder.gd*

Applies the current tool at a grid cell (x, z) of the current layer.

**See also:** `begin_stroke`, `set_color`

### `build_boxes() -> Array`

*client/avatar/accessory_builder.gd*

Merges voxels into boxes (greedy: along x, then z, then y, same color only).

### `load_boxes(boxes: Array) -> void`

*client/avatar/accessory_builder.gd*

Turns boxes back into voxels (for editing a saved accessory).

### `parts := {}  (property)`

*client/avatar/avatar.gd*

Parts by name (Node3D pivots) and attachment points by name.

### `sleep_yaw = null  (property)`

*client/avatar/avatar.gd*

Yaw (radians) while lying in a bed with the head that way, or null when not sleeping.

### `set_armor(texture: Texture2D) -> void`

*client/avatar/avatar.gd*

Armor shell texture in the skin layout, or null to hide armor.

### `set_held(node: Node3D, look := {}) -> void`

*client/avatar/avatar.gd*

Replaces the item in the right hand (null = empty hand). `look`: {glow, trail, held} of the stack.

### `set_accessories(list: Array) -> void`

*client/avatar/avatar.gd*

Adds accessory nodes at attachment points: [{attach, node}]. Replaces previous accessories.

### `set_sleeping(head: Array) -> void`

*client/avatar/avatar.gd*

Lies down in a bed: `head` is the [x, z] direction from the feet to the pillow, or [] to get up.

### `set_armor_glow(glow: Dictionary) -> void`

*client/avatar/avatar.gd*

Glowing armor: {color, energy} lights up the armor texture in its own colors; {} turns it off.

### `animate(delta: float, velocity: Vector3, on_ground: bool, pitch: float) -> void`

*client/avatar/avatar.gd*

Poses the body. `velocity` in blocks/s, `pitch` in radians (look up positive). Positive x rotation
swings a hanging limb forward.

**See also:** `bites`, `gulp`, `lift`

### `avatar := {}  (property)`

*client/avatar/avatar_editor.gd*

The avatar being edited (Cosmetics data).

### `owned := PackedStringArray()  (property)`

*client/avatar/avatar_editor.gd*

Server cosmetics the player owns (in game).

### `creations := false  (property)`

*client/avatar/avatar_editor.gd*

Show the player's creations and the tools to make them.

### `ugc = null  (property)`

*client/avatar/avatar_editor.gd*

In game: the UgcClient, for the server library.

### `open_painter(id: String) -> void`

*client/avatar/avatar_editor.gd*

Opens the skin painter on a library skin (id) or, for "", on the current look.

**See also:** `add_to`, `apply`, `clear_cache`, `get_def`, `get_manifest`, `get_payload`

### `open_builder(id: String) -> void`

*client/avatar/avatar_editor.gd*

Opens the accessory builder, empty or on a library accessory.

**See also:** `add_to`, `apply`, `clear_cache`, `get_def`, `get_manifest`, `get_payload`

### `open_library() -> void`

*client/avatar/avatar_editor.gd*

Other players' creations on this server, for the category on show.

**See also:** `apply`, `fetch`, `get_def`, `in_category`, `is_blocked`, `is_builtin`

### `model_bytes: Callable  (property)`

*client/avatar/item_mesh.gd*

asset name -> {hash, size} and a reader for downloaded bytes.

### `node_for(id: int, first_person := false, item_data := {}) -> Node3D`

*client/avatar/item_mesh.gd*

A node showing the item, oriented for a hand attachment: +Y points out of the fist, -Z runs down
the forearm. With `first_person` it is instead oriented for the view model: origin at the hand in
camera space, the icon's face turned towards the camera. null for nothing.

**See also:** `get_def`, `mesh_for`

### `apply_glow(node: Node3D, glow: Dictionary) -> void`

*client/avatar/item_mesh.gd*

Makes a held item node glow: {color, energy, light}. Additive, so pixels glow in their own colors.

### `icons  (property)`

*client/avatar/item_mesh.gd*

Composed icons (ItemIcons) for stacks with icon_layers; set by the client.

### `icon_image(id: int, item_data := {}) -> Image`

*client/avatar/item_mesh.gd*

The item's 2D icon as an image (composed icons included), or null for blocks and models.

**See also:** `composed`, `get_def`, `icon_of`

### `bitten_mesh(id: int, item_data: Dictionary, bites: int) -> Mesh`

*client/avatar/item_mesh.gd*

The icon extruded with `bites` (0-3) bites taken out of its top-right edge, for eating. Falls back
to the normal mesh for blocks and models.

**See also:** `begin`, `icon_image`, `mesh_for`, `on`, `set_color`

### `plate_mesh() -> Mesh`

*client/avatar/item_mesh.gd*

A round plate to serve food on (lies in the XY plane like an icon; turn it flat where it is used).

**See also:** `begin`, `create`, `set_color`

### `images := {}  (property)`

*client/avatar/look_builder.gd*

Asset name -> Image (server cosmetic textures).

### `read_model: Callable  (property)`

*client/avatar/look_builder.gd*

Asset name -> glTF bytes (server cosmetic models).

**See also:** `get_payload`, `is_id`

### `clear_cache() -> void`

*client/avatar/look_builder.gd*

Forgets cached skins and meshes (after cosmetics or their images change).

### `static resolve(avatar: Dictionary, name_text: String) -> Dictionary`

*client/avatar/look_builder.gd*

The avatar to draw: the player's own data, or the default look for their name.

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `apply(target, avatar: Dictionary, name_text: String) -> void`

*client/avatar/look_builder.gd*

Dresses an Avatar node with `avatar` data (skin and accessories; armor and held items are separate).

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `skin_image(look: Dictionary) -> Image`

*client/avatar/look_builder.gd*

The composed 64x64 skin: body colors, face, then clothing layers in category order.

**See also:** `compose_skin`, `create`, `get_def`, `side_rects`

### `accessories(look: Dictionary, pixel: float) -> Array`

*client/avatar/look_builder.gd*

[{attach, node}] for cosmetics with boxes or models.

**See also:** `begin`, `get_def`, `load_mesh`, `set_color`

### `static side_rects(r: Array, row_from: int, row_to: int, sides: Array) -> Array[Rect2i]`

*client/avatar/look_builder.gd*

Rectangles of a region [u, v, w, h, d] for the chosen sides, limited to rows of the side height.

### `static compose_skin(colors: Dictionary, face: Image, layers: Array) -> Image`

*client/avatar/skin_compositor.gd*

`colors`: {head, torso, arms, legs} as Color; `face`: an 8x8 image (or null); `layers`: Images in
the skin layout drawn over the body in order.

**See also:** `create`, `unfold`

### `static compose_armor(pieces: Dictionary) -> Image`

*client/avatar/skin_compositor.gd*

`pieces`: {slot name: Image} for visible armor. Returns null when nothing is worn.

**See also:** `create`, `unfold`

### `static unfold(r: Array, row_from := 0, row_to := -1) -> Array[Rect2i]`

*client/avatar/skin_compositor.gd*

Box unfold rectangles of a region [u, v, w, h, d]; `rows` limits the side faces to part of the
height (the top face is included only from row 0, the bottom only to the last row).

### `begin_stroke() -> void`

*client/avatar/skin_painter.gd*

Starts an undoable change (once per stroke).

### `apply_tool(p: Vector2i, alt := false) -> void`

*client/avatar/skin_painter.gd*

Applies the current tool at a skin pixel. Only faces of the current layer take paint.

**See also:** `begin_stroke`, `face_at`, `set_color`

### `save() -> Dictionary`

*client/avatar/skin_painter.gd*

Validates and saves to the local library. Returns the result ({ok, error, manifest}).

**See also:** `build_boxes`, `close`, `make`, `open`, `payload_extension`, `validate`

### `set_held(id: int, node: Node3D, look := {}) -> void`

*client/avatar/view_model.gd*

`node` shows the held item; `id` lets the arm dip and come back up when the item changes.

### `animate(delta: float, speed: float, on_ground: bool, look_delta: Vector2) -> void`

*client/avatar/view_model.gd*

`speed`: horizontal speed in blocks/s; `look_delta`: mouse movement this frame (pixels).

**See also:** `bites`, `gulp`, `lift`

### `add(from: Vector3, to: Vector3, look: Dictionary) -> void`

*client/beam_view.gd*

look: {color, width, seconds, sag (0 for a straight beam, >0 for something hanging)}.

### `add_link(link: Dictionary) -> void`

*client/cable_view.gd*

link: {id, draw ("cable" | "pipe"), a (Vector3), b (Vector3), color}

**See also:** `add_tab`, `begin`, `builtin_texture`, `creation_dir`, `curve`, `heading`

### `static curve(from: Vector3, to: Vector3, pipe: bool) -> PackedVector3Array`

*client/cable_view.gd*

The curve from one end to the other. A pipe is the same call with no dip.

### `receive(state: Dictionary) -> void`

*client/compass.gd*

`state` is what the server sends for the map: {players: [...], markers: [...]}.

**See also:** `apply`, `asset_name`, `available`, `box`, `cancel_request`, `default_avatar`

### `static dir() -> String`

*client/content_cache.gd*

Where cached assets live. QW_USER_DIR moves it, so a test run does not fill the player's cache.

### `static save(manifest: Dictionary, payload: PackedByteArray) -> Dictionary`

*client/creation_library.gd*

Validates and saves a creation. Returns {ok, error, manifest}.

**See also:** `build_boxes`, `close`, `make`, `open`, `payload_extension`, `validate`

### `static list() -> Array`

*client/creation_library.gd*

Manifests of every creation, newest first.

**See also:** `get_value`, `is_id`, `open`, `read_meta`

### `static update(id: String, changes: Dictionary) -> bool`

*client/creation_library.gd*

Changes the name or color (the id stays: it depends only on the content).

### `static register_all(registry, images: Dictionary) -> int`

*client/creation_library.gd*

Registers every creation as a cosmetic, putting skin images in `images` (asset name -> Image) for the
look builder. Returns how many were added.

**See also:** `add_to`, `get_payload`, `list`

### `static read_model(asset: String) -> PackedByteArray`

*client/creation_library.gd*

Model bytes by asset name ("ugc:....glb"), for LookBuilder's model reader.

**See also:** `get_payload`, `is_id`

### `add(pos: Vector3, normal: Vector3i, look: Dictionary) -> void`

*client/decal_view.gd*

look: {color, size, seconds (0 stays until the limit pushes it out)}.

### `static bites(t: float, duration: float) -> int`

*client/eating_visuals.gd*

How many bites are gone (0-3; 3 = eaten) `t` seconds into a meal of `duration`.

### `static lift(t: float) -> float`

*client/eating_visuals.gd*

0..1..0 each chomp: how far the food is raised towards the mouth.

**See also:** `block_state`, `get_block_data`, `get_block_v`, `set_block_authoritative`, `tell_assembly`

### `static gulp(t: float) -> float`

*client/eating_visuals.gd*

0..1 over the meal, and a small wobble for each gulp.

### `static crumbs(parent: Node, at: Vector3, color: Color, amount := 8, size := 0.03) -> void`

*client/eating_visuals.gd*

A one-shot burst of pixel crumbs falling in world space.

**See also:** `set_color`

### `start(grip: Node3D, tip: Node3D, trail: Dictionary, swing_seconds: float, space: Node3D = null, subtle := false) -> void`

*client/effects/swing_trail.gd*

Records the ribbon for `swing_seconds`. `space` null means world space. `subtle` (first person, where
the blade sweeps right past the camera) draws a thinner, fainter, shorter ribbon.

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `follow(node: Node3D) -> void`

*client/float_text.gd*

Sticks it to something that moves. The offset is kept so a number that appeared at chest height
stays at chest height rather than snapping to the thing's feet.

### `reload_pending := false  (property)`

*client/game_client.gd*

Set when the server announced a full reload: whoever owns the client should reconnect (see main.gd).

### `admin_token := ""  (property)`

*client/game_client.gd*

Passed by the menu when this client launched a local server it should stop on exit.

### `identity_name := "default"  (property)`

*client/game_client.gd*

Which saved identity (user://identity/<name>.pem) to log in with.

### `test_signing_key: CryptoKey = null  (property)`

*client/game_client.gd*

Tests only: sign challenges with this key instead of the identity (must fail authentication).

### `test_protocol := -1  (property)`

*client/game_client.gd*

Tests: announce this protocol version instead of the real one.

### `ignore_mouse_capture := false  (property)`

*client/game_client.gd*

Accept gameplay input without a captured mouse (headless bots / tests).

### `avatar = null  (property)`

*client/game_client.gd*

Your portable avatar (Cosmetics data) sent to the server on join; null loads the saved one.

### `realm := ""  (property)`

*client/game_client.gd*

Which of the server's worlds this player is standing in ("" is the overworld), and what to call it.
Everything in `world` belongs to this realm and nothing outlives a move to another (see on_realm).

### `owned_cosmetics := PackedStringArray()  (property)`

*client/game_client.gd*

Server cosmetics you own on this server.

### `effects_seen := {}  (property)`

*client/game_client.gd*

Effect name -> times the server played it for us (debug overlay and tests).

### `stats := {}  (property)`

*client/game_client.gd*

Stats the server computed for this player (reach, attack_cooldown, mining_speed, armor, ...).

### `transfer_ticket := {}  (property)`

*client/game_client.gd*

A ticket to hand to the server right after hello, when arriving through a transfer: {ticket, signature}.

### `transfer := {}  (property)`

*client/game_client.gd*

Set when the server sent us elsewhere: {address, port, name, ticket}.

**See also:** `kick`, `make`, `pack_inventory`, `save_items`, `save_player`, `schedule`

### `exit_kind := ""  (property)`

*client/game_client.gd*

Why the game ended, for the menu: "" or "identity" (the server's identity no longer matches the pinned one).

### `lazy_bytes_skipped := 0  (property)`

*client/game_client.gd*

Bytes the join deliberately did not wait for. Counted whether or not they were already cached, so it
says what the join *decided* rather than what happened to be on disk - which is the thing to test.

### `ugc := UgcClient.new(self)  (property)`

*client/game_client.gd*

Player creations: uploads, downloads and the server library (see engine/client/ugc_client.gd).

### `ugc_models := {}  (property)`

*client/game_client.gd*

Model files of downloaded creations: asset name -> GLB bytes.

### `social  (property)`

*client/game_client.gd*

engine/client/social/social_client.gd when main.gd runs the game (null in tests).

### `on_content_update(content: Dictionary) -> void`

*client/game_client.gd*

A mod was reloaded: take the new definitions, recipe book, guide and tutorials (ids are unchanged).

**See also:** `craftable_times`, `have`, `have_all`, `open`, `refresh`, `register`

### `static resolve_transfer_address(address: String, current: String) -> String`

*client/game_client.gd*

Where to actually go when a server sends us somewhere. A server that names itself 127.0.0.1 means "this
machine" - but the client reads that as the *player's* machine, and the destination is wherever the
server we are talking to lives. Unless we really are playing on our own computer, use the host we are
already connected to. (A network.json written with loopback addresses is an easy mistake and used to
leave nobody able to travel at all.)

### `fetch_lazy_asset(asset_name: String, then: Callable) -> void`

*client/game_client.gd*

Fetches a lazy asset, calling `then(asset_name)` once it is on disk. Calling it again for something
already arriving just adds another listener rather than asking the server twice.

### `refresh_looks() -> void`

*client/game_client.gd*

Draws everyone again (a creation someone wears has arrived).

**See also:** `apply`, `apply_glow`, `clear_cache`, `compose_armor`, `get_def`, `node_for`

### `open_ugc_review() -> void`

*client/game_client.gd*

The admin review panel for player creations.

**See also:** `fetch`, `has_modal`

### `invite_text() -> String`

*client/game_client.gd*

Report a creation another player is wearing.
The invite code for this server. When playing on this computer (a hosted world), people on the same
network use this computer's local address; from elsewhere they need its public address and the port
forwarded (the hub service will make that easier).

**See also:** `local_address`, `share_text`

### `notify(text: String) -> void`

*client/game_client.gd*

A short message for the player (creation statuses and the like).

**See also:** `on_chat`

### `on_screen(look: Dictionary) -> void`

*client/game_client.gd*

look: {color, strength (0-1), seconds (0 holds until changed)}. An empty colour clears it.

Respects the accessibility setting for flashes, like the hurt overlay: a full-screen colour is
exactly the thing somebody may need turned down, and a mod should not be able to insist.

**See also:** `get_value`, `shared`

### `on_decal(pos: Vector3, normal: Vector3i, look: Dictionary) -> void`

*client/game_client.gd*

A mark left on the world.

### `on_beam(from: Vector3, to: Vector3, look: Dictionary) -> void`

*client/game_client.gd*

A line drawn from one place to another for a moment.

### `on_player_nameplate(peer_id: int, plate: Dictionary) -> void`

*client/game_client.gd*

The label over another player's head changed.

**See also:** `apply`

### `on_float_text(text: String, pos: Vector3, options: Dictionary) -> void`

*client/game_client.gd*

A word that floats in the world for a moment: damage off a hit, a name over a thing.

**See also:** `follow`

### `on_flying(enabled: bool) -> void`

*client/game_client.gd*

The server started or stopped this player's flight.

**See also:** `notify`

### `on_wind(angle: float, strength: float) -> void`

*client/game_client.gd*

The server's music instruction. Nothing here can fail loudly: the track may not have arrived yet, or
may never arrive, and either way the game carries on without it.
The wind the server is running. Stored, not applied: `_wind_angle` eases toward it over a few
seconds, because wind that snaps to a new heading looks like a bug rather than like weather.

### `on_weather(weather_id: int, intensity: float) -> void`

*client/game_client.gd*

What the sky is doing. Like music, nothing here can fail loudly: unknown weather simply is not drawn.

**See also:** `apply`

### `on_realm(realm_id: String, display_name: String) -> void`

*client/game_client.gd*

The server has put this player in another world. Everything on screen belongs to the one they have
left - its terrain, its creatures, the people standing in it - so all of it goes, and the server
streams the new world from scratch.

This arrives on the same channel as chunks, and that is not incidental: the three channels are
delivered independently, so a chunk sent a moment before the move would otherwise be free to arrive
*after* it and be built into the world the player just walked into. Ordering only exists within a
channel, so the message that ends a world travels in the same queue as the chunks it invalidates.

**See also:** `despawn`, `on_assembly_gone`, `on_effect_stop`, `on_player_left`, `on_unload_chunk`

### `on_assembly(id: int, origin: Vector3i, blocks: PackedInt32Array) -> void`

*client/game_client.gd*

Cables and pipes: the whole lot on joining, then one at a time as they are made.
A set of blocks that has left the grid. Built once from everything it is made of.

**See also:** `on_assembly_gone`

### `on_drives(positions: PackedVector3Array, values: PackedFloat32Array) -> void`

*client/game_client.gd*

What is turning, and how fast. A wheel turns constantly but changes speed rarely, so this arrives
on change and the angle is carried forward here rather than sent every tick.

### `mine_block(pos: Vector3i) -> void`

*client/game_client.gd*

Breaks a block the way a player holding the button would (used by tests and automation).

**See also:** `break_time`, `crack_node`, `get_block_v`, `request_break`, `selected_item`, `tool_of`

### `attack_target() -> bool`

*client/game_client.gd*

Attacks the entity or player under the crosshair. Returns false if nothing is targeted.

**See also:** `play_name`, `swing`

### `use_selected_item() -> bool`

*client/game_client.gd*

Uses the held item on the current target (or on nothing). Returns false if it is not usable.

**See also:** `bitten_mesh`, `crumbs`, `get_def`, `is_usable`, `mesh_for`, `plate_mesh`

### `on_selection(a: Vector3i, b: Vector3i, show: bool) -> void`

*client/game_client.gd*

Outline of a structure selection (/struct pos1, pos2).

### `on_area_preview(cells: PackedVector3Array, color: String, seconds: float, visible: bool) -> void`

*client/game_client.gd*

The outline of what an area tool is about to change.

One wireframe cube per cell rather than a bounding box, because the point of the preview is to
show a vein's actual shape - a box round a vein tells you nothing you wanted to know. The server
caps how many cells it sends (AreaEdits.PREVIEW_CELLS), so this draws whatever arrives.

### `request_break(pos: Vector3i) -> void`

*client/game_client.gd*

Predicts the edit locally and asks the server to apply it.

**See also:** `block_break`, `chunk_coord_at`, `get_block_v`, `has_chunk`, `play_name`, `set_block`

### `placement_spot(target: Dictionary) -> Vector3i`

*client/game_client.gd*

Places the selected hotbar block, predicting the result.
Where a block goes when placing against a target: into replaceable blocks (tall grass) themselves,
otherwise against the face that was hit.

**See also:** `get_block_v`

### `on_recipe_learned(index: int, source: String) -> void`

*client/game_client.gd*

A new recipe: remember it and celebrate (several at once are grouped into one toast).

**See also:** `open`

### `on_dev_error(e: Dictionary) -> void`

*client/game_client.gd*

Script errors on the server, for admins: a red card per error (repeats update its count).

### `on_station_label(pos: Vector3i, text: String) -> void`

*client/game_client.gd*

Floating progress text above a station for everyone nearby ("" removes it).

### `on_structure_guide(missing: Array) -> void`

*client/game_client.gd*

Ghost blocks where a structure's missing blocks go (red where a block is in the way). Clears after
a minute or when the guide is requested again.

**See also:** `mesh_for`

### `craft_recipe(index: int, times := 1) -> void`

*client/game_client.gd*

Asks the server to craft a recipe (see RecipeRegistry indices).

### `lookup_recipes(item: int, mode: String) -> void`

*client/game_client.gd*

Opens the recipe book filtered to what makes (`mode` "make") or uses ("use") an item.

**See also:** `show_lookup`

### `pin_recipe(index: int) -> void`

*client/game_client.gd*

Pins a recipe to the HUD (-1 unpins). Saved per server.

**See also:** `craftable_times`, `have`, `have_all`, `load`, `refresh`, `save`

### `open_avatar_editor() -> void`

*client/game_client.gd*

In game: your look with this server's cosmetics; saved built-in choices travel to other servers.

**See also:** `has_modal`, `is_builtin`, `player_id`, `resolve`

### `open_settings() -> void`

*client/game_client.gd*

The settings screen over the game (from the pause menu).

**See also:** `build`

### `open_players_panel() -> void`

*client/game_client.gd*

Players and roles (admins) over the game, in the settings overlay slot.

**See also:** `build`

### `open_server_panel() -> void`

*client/game_client.gd*

Server settings (admins) over the game, in the settings overlay slot.

**See also:** `build`

### `open_worlds_panel() -> void`

*client/game_client.gd*

The worlds this server is linked to, and travel between them.

**See also:** `build`

### `toggle_map() -> void`

*client/game_client.gd*

The map (M): the world from above with everyone on it.

**See also:** `close_map`

### `open_friends() -> void`

*client/game_client.gd*

Friends and party over the game (from the pause menu), reusing the settings overlay slot.

**See also:** `build`, `close_settings`, `notify`

### `on_riding(state_info: Dictionary) -> void`

*client/game_client.gd*

The server says this player got on or off something.

### `light_the_sun() -> void`

*client/game_client.gd*

Turns real shadows on the sun and moon on or off, from the `realistic` graphics setting.

Separate from `GraphicsSettings.apply_realism`, which owns the environment, because shadows live
on the lights and the lights belong to the client. Called at build and whenever the setting
changes, so somebody whose frame rate has collapsed can get it back without restarting.

**See also:** `off`

### `on_palette(groups: Dictionary) -> void`

*client/game_client.gd*

Everything a creative player may take, sent when they ask for it.

**See also:** `show_palette`

### `preset: String  (property)`

*client/graphics_settings.gd*

The current preset name ("custom" when the player changed single toggles). Values live in the shared
client settings (engine/client/settings/client_settings.gd).

### `cycle() -> void`

*client/graphics_settings.gd*

F4: the next preset (from "custom", back to the first).

**See also:** `set_value`, `shared`

### `apply_environment(env: Environment, viewport: Viewport) -> void`

*client/graphics_settings.gd*

Applies post-processing and resolution settings. Material and mesher toggles are applied by the
client since they need its materials and a remesh.

**See also:** `apply_realism`

### `static off(part: String) -> bool`

*client/graphics_settings.gd*

The realistic preset's half of the environment. Split out so it can be turned on and off while the
game is running rather than only at startup - somebody whose frame rate has collapsed should be
able to get it back from the settings screen without restarting.

Sun shadows themselves live on the light, not here; see `light_the_sun` in game_client.gd.
Which parts of the realistic preset to leave off, for finding out what a frame is being spent on:
QW_REAL_OFF=ssil,ssao,shadows,lit,sky
Empty in normal use. Bisecting beats guessing, and 22 fps on a 24-core M1 Max is not a preset being
expensive - it is something being wrong. (2026-09-21)

### `static sweep() -> int`

*client/housekeeping.gd*

Prunes every cache back inside its budget. Returns bytes freed, for the log.

**See also:** `boxes_of`, `get_block`, `move`, `prune`

### `static prune(dir: String, budget: int) -> int`

*client/housekeeping.gd*

Deletes oldest-first until what is left fits in `budget` bytes. Directly under `dir` only: entries are
whole units (a file, or an unpacked mod's folder), and half an unpacked mod is worse than none.

**See also:** `list`, `open`

### `static size_of(dir: String) -> int`

*client/housekeeping.gd*

What a folder currently costs, for the settings screen.

**See also:** `open`

### `static listing() -> Array`

*client/housekeeping.gd*

The folders, with their sizes filled in.

**See also:** `size_of`

### `static human(bytes: int) -> String`

*client/housekeeping.gd*

"412 MB", "9.1 GB" - sizes a person reads rather than a number they count the digits of.

### `images := {}  (property)`

*client/item_icons.gd*

Asset name -> Image (all downloaded PNGs).

### `composed(layers: Array) -> Image`

*client/item_icons.gd*

The composed image for layers, or null when none of the sprites are available.

**See also:** `create`

### `static tooltip_lines(items, id: int, item_data: Dictionary) -> PackedStringArray`

*client/item_visuals.gd*

Tooltip text: name (item data "name" overrides), stats from the definition, durability, then lore
from the definition and from item data ("lore": [...]).

**See also:** `get_def`, `max_durability`, `tool_of`, `weapon_of`

### `static update_wear_bar(slot: Control, items, id: int, item_data: Dictionary) -> void`

*client/item_visuals.gd*

Adds or updates a thin bar along the bottom of an item slot showing remaining durability.

**See also:** `max_durability`

### `static shield_icon(fill: float) -> ImageTexture`

*client/item_visuals.gd*

9x9 shield: `fill` 1 = full, 0.5 = left half, 0 = empty outline.

**See also:** `create`

### `zoom_by(steps: int) -> void`

*client/map_screen.gd*

Zooms in (+1) or out (-1). The buttons call this, and so does the mouse wheel: reaching for the wheel
over a map is what everybody does, and it used to change the hotbar behind the map instead.

**See also:** `chunk_coord_at`

### `fetch(url: String) -> String`

*client/menu/downloads.gd*

GETs a small text file (a manifest, an index). "" if anything went wrong.

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `download(url: String, into_dir: String) -> PackedByteArray`

*client/menu/downloads.gd*

GETs a file, through a file on disk so a large zip is not held in memory twice. Empty if it failed.

**See also:** `allowed`, `cancel_request`

### `social  (property)`

*client/menu/main_menu.gd*

engine/client/social/social_client.gd, from main.gd.

### `installed_games() -> Array`

*client/menu/main_menu.gd*

The installed games, as the menu found them. Exposed so the backdrop can generate itself from a
game that is actually present instead of naming one. (2026-09-21)

### `show_message(text: String, kind := "info", action_text := "", action := Callable()) -> void`

*client/menu/main_menu.gd*

kind: "info" (fades after a few seconds), "success" (green, fades) or "error" (red, stays until
dismissed). `action_text` + `action` add a button (e.g. retry).

**See also:** `box`

### `refresh_servers(query := false) -> void`

*client/menu/main_menu.gd*

Redraws the list; `query` asks again (the hub, the network, or each server for its status).

**See also:** `box`, `configured`, `discover_lan`, `find_favorite`, `get_value`, `join_selected_server`

### `refresh_mods() -> void`

*client/menu/main_menu.gd*

The rows of the current tab, from what is installed here and what the index offers.

**See also:** `box`, `install`, `installed`, `merge`, `muted`, `refresh_mods`

### `game := ""  (property)`

*client/menu/menu_backdrop.gd*

The game to generate the backdrop from. Empty means "the first one installed", which is what the
menu does: this named "vanilla" until that mod was deleted on 21 September 2026, and a backdrop
pinned to one mod's id is wrong anyway - it is meant to show whatever this player actually has.

### `motion := true  (property)`

*client/menu/menu_backdrop.gd*

Orbiting camera and passing time (off: a still view, for players who prefer less motion).

### `refresh_avatar(look: Dictionary, name_text: String) -> void`

*client/menu/menu_backdrop.gd*

Shows a (new) look on the menu avatar, e.g. after the avatar editor closes.

**See also:** `apply`, `clear_cache`, `default_avatar`, `merge`, `refresh_appearance`, `sanitize_avatar`

### `static primary(button: Button) -> Button`

*client/menu/menu_theme.gd*

A primary (accent) button.

**See also:** `box`

### `static nav(button: Button) -> Button`

*client/menu/menu_theme.gd*

A sidebar navigation button: flat until selected.

**See also:** `box`

### `static close_icon(color: Color) -> ImageTexture`

*client/menu/menu_theme.gd*

A checkbox mark: a light rounded outline, or an accent square with a tick. Drawn at twice the size
and scaled down, for smooth edges.
The ✕ on a dialog's title bar, drawn so it reads on any backdrop.

**See also:** `create`

### `add_favorite(server_name: String, address: String, port: int) -> bool`

*client/menu/server_book.gd*

Adds or updates a favorite. Returns false when the list is full.

**See also:** `find_favorite`, `save`

### `note_joined(server_name: String, address: String, port: int) -> void`

*client/menu/server_book.gd*

Remembers a join (most recent first). `server_name` may be updated later by a status answer.

**See also:** `key`, `save`

### `discover_lan(extra_ports := []) -> void`

*client/menu/server_pinger.gd*

Finds servers on the local network (a broadcast) and on this computer. `extra_ports`: more game
ports to try (e.g. the one this player hosts on).

**See also:** `make_request`, `query_port`

### `ping(key: String, address: String, game_port: int) -> void`

*client/menu/server_pinger.gd*

`key` identifies the answer (e.g. "host:port").

**See also:** `make_request`, `query_port`

### `check(manual := false) -> void`

*client/menu/update_check.gd*

Asks the release page what the newest version is. `manual` also reports "you are up to date".

**See also:** `compare`, `fetch`, `installed_path`, `manifest_url`, `parse`, `platform`

### `install() -> void`

*client/menu/update_check.gd*

Downloads the update, checks it and hands over to the installer script.

**See also:** `close`, `download`, `install_package`, `installed`, `installed_path`, `installer`

### `static list(root := "") -> Array`

*client/menu/world_list.gd*

[{id, title, game, mods, seed, created_at, last_played, size}] newest played first.

**See also:** `get_value`, `is_id`, `open`, `read_meta`

### `static id_for(title: String, root := "") -> String`

*client/menu/world_list.gd*

A folder name for a new world from its title: letters, digits and underscores, unique in `root`.

### `static create(title: String, mods: Array, world_seed: int, root := "") -> String`

*client/menu/world_list.gd*

Creates the folder and a world.json with the title, mods and seed, so the list shows it before the
first launch. The server fills in the rest when it starts.

**See also:** `broadcast_entity_event`, `close`, `create`, `enabled`, `exists`, `heading`

### `static delete(id: String, root := "") -> bool`

*client/menu/world_list.gd*

Deletes a world folder and its backups. Refuses ids that are not plain world folders.

**See also:** `open`, `read_meta`

### `static describe_time(unix: int) -> String`

*client/menu/world_list.gd*

"3 minutes ago", "yesterday", "12 Sep 2026".

### `static load_mesh(bytes: PackedByteArray) -> ArrayMesh`

*client/model_library.gd*

Returns null if the bytes are not a usable model.

### `static load_parts(bytes: PackedByteArray) -> Array`

*client/model_library.gd*

For animated entities: one entry per glTF node with a mesh, {name, mesh, transform}, where the
transform is the node's global transform (its pivot) and the mesh stays in node space so the part
can rotate around its pivot. Returns [] if the bytes are not a usable model.

### `apply(plate: Dictionary) -> void`

*client/nameplate.gd*

The plate as the server describes it: {name, lines, show_health, health, color, hidden, range}.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `update_for_camera(camera_position: Vector3) -> void`

*client/nameplate.gd*

Fades with distance and hides when there is nothing to say. Called by the client each frame with
where the camera is, because a plate has no way of knowing on its own.

### `show_palette(groups: Dictionary, items, atlas) -> void`

*client/palette_screen.gd*

Called when the server sends the catalogue.

**See also:** `icon_of`

### `static create(texture: Texture2D) -> ShaderMaterial`

*client/scrolling_material.gd*

A material that scrolls `texture`. One shader for every belt; one material per texture.

**See also:** `broadcast_entity_event`, `close`, `create`, `enabled`, `exists`, `heading`

### `static texture_of(mesh: Mesh) -> Texture2D`

*client/scrolling_material.gd*

The albedo texture a loaded model is drawn with, so the belt keeps its own look.

### `textures := {}  (property)`

*client/server_ui.gd*

asset name -> Texture2D, provided by the client after content loads.

### `path := DEFAULT_PATH  (property)`

*client/settings/client_settings.gd*

Resolved in _init, so an instance made directly (a test, a tool) writes where QW_SETTINGS says rather
than over the player's own file. One that did exactly that wiped a player's settings. (2026-09-18)

### `static shared()`

*client/settings/client_settings.gd*

The settings every part of the client shares (loaded on first use).

**See also:** `load`, `load_file`

### `set_value(key: String, value, save_now := true) -> void`

*client/settings/client_settings.gd*

Sets and saves a value (clamped to the schema) and emits `changed`. Changing a graphics toggle while a
preset is selected switches to "custom", starting from that preset's values.

**See also:** `describe`, `drive_changed`, `get_value`, `level_for`, `qualified`, `report_error`

### `events(action: String) -> Array`

*client/settings/client_settings.gd*

The events for an action (saved bindings, else defaults) as descriptors.

**See also:** `default_events`, `event_from`, `get_value`

### `action_using(descriptor: String, except := "") -> String`

*client/settings/client_settings.gd*

Which action (if any, other than `except`) already uses an event.

**See also:** `events`

### `apply_bindings() -> void`

*client/settings/client_settings.gd*

Registers every action in the InputMap with the player's bindings.

**See also:** `event_from`, `events`

### `static descriptor_of(event: InputEvent) -> String`

*client/settings/client_settings.gd*

The descriptor for a pressed key or mouse button, or "" for anything else.

### `apply_display(window: Window) -> void`

*client/settings/client_settings.gd*

Window mode, v-sync, frame rate limit and interface scale.

**See also:** `apply_ui_scale`, `get_value`

### `apply_ui_scale(window: Window) -> void`

*client/settings/client_settings.gd*

Interface size: the screen's own density (Retina = 2) times the player's choice.

### `apply_audio() -> void`

*client/settings/client_settings.gd*

Master volume on the Master bus; World and Interface buses (created when missing) below it.

### `closable := false  (property)`

*client/settings/settings_screen.gd*

Shows a close button (the in-game overlay).

### `closable := false  (property)`

*client/social/friends_panel.gd*

Shows a Done button (the in-game overlay).

### `current_server := {}  (property)`

*client/social/social_client.gd*

{name, address, port, code} while playing on a server, else {}.

### `key: CryptoKey  (property)`

*client/social/social_client.gd*

For tests: sign in with this key instead of the player's identity.

### `refresh() -> void`

*client/social/social_client.gd*

Checks in now (signing in first when needed).

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `leader_server() -> Dictionary`

*client/social/social_client.gd*

The party leader's server, when someone else leads and shares it ({} otherwise).

### `static build(images: Dictionary) -> Dictionary`

*client/texture_atlas.gd*

`images`: asset name -> Image. Returns {texture, surface, uv: name -> Rect2, pixels: name -> Rect2}.
Unknown names should fall back to the MISSING ("") entry, a magenta checker.

**See also:** `add_handler`, `agent_for`, `area_cells`, `at`, `attach`, `body_font`

### `static build_surface(built: Dictionary) -> Image`

*client/texture_atlas.gd*

The relief and roughness atlas for an already-built one. **Slow on purpose to call, not to run.**

Split out because it is the expensive half - a Sobel over every pixel of every texture - and doing it
inside `build()` put two and a half seconds on the main thread during world load. That is not merely
a hitch: the client stops draining its socket, Godot starts printing "Buffer full, dropping packets",
the chunks never arrive and the world comes up empty. Run this on a worker and hand the texture over
when it is ready; relief appearing a second after the world does is nothing anybody notices.
(2026-09-22)

**See also:** `create`, `texture`

### `static manifest_url() -> String`

*client/updater.gd*

Where to ask about new versions (the project setting wins, so a fork can point somewhere else).

### `static platform() -> String`

*client/updater.gd*

This platform's key in the manifest, or "" where updating is not supported (a server, or a build
installed by something else).

### `static signature_ok(manifest_text: String, signature: String, keys := RELEASE_KEYS) -> bool`

*client/updater.gd*

Whether this manifest was signed by one of the project's release keys. A build with no keys refuses
everything rather than accepting everything: this used to return true so that builds made before
signing existed could still update themselves, which meant that a build shipped with its keys somehow
empty would take an update from anyone who could answer for the address.

**See also:** `finish`, `start`, `verify`

### `static check(manifest_text: String, current := Protocol.GAME_VERSION, for_platform := "", signature := "", keys := RELEASE_KEYS) -> Dictionary`

*client/updater.gd*

Reads a manifest. Returns {available, version, notes, url, sha256, size, reason}: `available` is true
only when the manifest is signed by the project, sound, names this platform, and is newer than `current`.

**See also:** `compare`, `fetch`, `installed_path`, `manifest_url`, `parse`, `platform`

### `static url_allowed(url: String) -> bool`

*client/updater.gd*

Only the project's own release hosts (or whatever host the built-in manifest address uses), over https.
The mod list checks every download address the same way (engine/client/mod_catalog.gd).

### `static verify(bytes: PackedByteArray, sha256: String, size := 0) -> bool`

*client/updater.gd*

Whether a downloaded file is exactly what the manifest described.

**See also:** `finish`, `pem_id`, `start`

### `static installed_path() -> String`

*client/updater.gd*

Where this build is installed: the .app bundle on macOS, otherwise the folder holding the executable.
"" when the game runs from source (the editor), where there is nothing to replace.

### `static installer(zip_path: String, work_dir: String, installed: String, pid: int, force := "") -> Dictionary`

*client/updater.gd*

The installer for this platform: what file to write, what runs it, and what goes inside.
`force` ("macos", "linux", "windows") is for the tests, which have to be able to read the Windows
installer from a Mac - there is no Windows machine in this project and there may never be one.

**See also:** `install_script`, `windows_install_script`

### `static windows_install_script(zip_path: String, work_dir: String, installed: String, pid: int) -> String`

*client/updater.gd*

The Windows twin of install_script, as a batch file.

Windows will not let you delete a running .exe, so everything waits for the game to go first - the
same shape as the shell one, in a language that cannot do most of it. `tasklist` is the wait,
PowerShell is borrowed for the unzip because batch has no such thing, and the swap is a rename so
that a failure halfway leaves the old build where it was rather than nothing at all.

**Not tested on Windows by anyone yet.** It is deliberately not reachable: Windows is a download link
and is not in update.json, so no client will run this until somebody has tried it by hand and the
manifest is changed to offer it. An untested script that replaces a folder is not something to arm.

### `static install_script(zip_path: String, work_dir: String, installed: String, pid: int) -> String`

*client/updater.gd*

The script that installs a downloaded update once this process has gone: it unpacks the zip itself
(so the executable bits inside a .app survive), swaps it with the installed build, clears the download
flag macOS puts on it and starts the new one. Kept as a string so a test can read it without installing.


## The server itself

### `static export_identity(path: String, passphrase: String) -> String`

*main.gd*

Returns a status message; failures start with "Error".

**See also:** `close`, `export_encrypted`, `load_or_create`, `open`, `player_id`

### `realms := {}  (property)`

*server/game_server.gd*

The worlds this server is running. "" is the overworld - the one a server has always had, and the
one an old save belongs to. Realms are added by mods before the world loads.

### `realm: Realm  (property)`

*server/game_server.gd*

The realm everything without a realm of its own means. Every field below that used to hold the world
directly now reads through it, so the hundred and seventy places that say `world.get_block(...)` did
not all have to change on the same day. They will change as each becomes realm-aware; until then
this is the overworld and the behaviour is exactly what it was.

### `weather_now := {"id": -1, "intensity": 0.0, "until": 0.0}  (property)`

*server/game_server.gd*

What the sky is doing: {id, intensity, until}. World state, not per player - everyone standing in the
same world is standing in the same storm, and somebody joining halfway through arrives in it.

### `wind_now := {"angle": 135.0, "strength": 0.3, "until": 0.0, "drifting": true}  (property)`

*server/game_server.gd*

Which way the wind blows and how hard: degrees clockwise from north, and 0 (still) to 1 (a gale).

**The server sends a base vector and the client does the gusting.** Wind that a player can see is
mostly gusts - grass ripples, a cloud edge tears - and sending that at tick rate would be a lot of
bandwidth for something nobody can be wrong about. So this changes rarely, and the detail is worked
out on each client from time and position. `until` matches `weather_now`: 0 means until something
says otherwise, and while it is unset the engine drifts the wind gently so a world nobody has
written weather for still breathes. (2026-09-22)

### `player_rig := PlayerRig.default_rig()  (property)`

*server/game_server.gd*

The character body every client draws players with (see PlayerRig; mods may replace it).

### `cosmetics := Cosmetics.new()  (property)`

*server/game_server.gd*

Built-in and server cosmetics, categories and this server's cosmetics policy.

### `effects := EffectRegistry.new()  (property)`

*server/game_server.gd*

Named visual effects clients render on request (see EffectRegistry).

### `block_ticks  (property)`

*server/game_server.gd*

Random and scheduled block ticks, the world clock and server-side light (see BlockTicks). One per
realm; this is the overworld's, for everything that has not been told which world it means yet.

### `signals  (property)`

*server/game_server.gd*

Signal levels (see engine/server/signals.gd). One per realm; this is the overworld's.

### `liquids  (property)`

*server/game_server.gd*

Liquids (see engine/server/liquids.gd). One per realm; this is the overworld's.

### `multiblocks  (property)`

*server/game_server.gd*

Machines assembled out of blocks (see engine/server/multiblocks.gd).

### `containers := Containers.new(self)  (property)`

*server/game_server.gd*

Container types and open container screens (chests, furnaces, machines).

### `gameplay := {  (property)`

*server/game_server.gd*

Game-wide rules mods can change with set_gameplay.

### `map_markers := {}  (property)`

*server/game_server.gd*

Map markers mods set for a player: player id -> {marker id: {label, position, color}} (see ModApi.set_map_marker).

### `world_markers := {}  (property)`

*server/game_server.gd*

Markers everyone sees (ModApi.set_world_marker); saved in world.json.

### `generator  (property)`

*server/game_server.gd*

What this realm's terrain is generated by (the overworld's, for callers that have not been told
which world they mean). A chunk job is handed this.

### `generation_passes: Array  (property)`

*server/game_server.gd*

Objects with decorate(chunk, world_seed) run after the generator on worker threads (e.g. ores).

### `biome_generator  (property)`

*server/game_server.gd*

The engine biome generator once a mod registers biomes (may also be the world generator, but is a
separate field - see Realm).

**See also:** `block`, `qualified`, `register_instance`

### `rejoin_handler := Callable()  (property)`

*server/game_server.gd*

Where a *returning* player appears, if a mod wants a say - a lobby, a hub, wherever their story left
them. Separate from spawn_handler because "where does a new player start" and "where does somebody
who has played before come back to" are different questions, and a mod that answers one usually does
not want to answer the other. Vector3.INF means "leave them where they logged out".

### `start_error := ""  (property)`

*server/game_server.gd*

Why start() gave up, in words a player can act on. Written next to the worlds so the menu can say it
instead of "could not connect to 127.0.0.1" (see engine/server_main.gd).

### `recipes := RecipeRegistry.new()  (property)`

*server/game_server.gd*

Crafting recipes and categories (sent to clients for the recipe book).

### `tags := TagRegistry.new()  (property)`

*server/game_server.gd*

Named groups of blocks and items (see engine/shared/tag_registry.gd). Server-side: a tag is a
question a mod asks while the world runs, not something a client has to know.

### `block_tick_handlers := {}  (property)`

*server/game_server.gd*

What a block *type* does is true of every world, so these tables belong to the server and every
realm's machinery reads the same one. Registering per realm looked equivalent and was not: a realm
a mod adds later would have had no handlers at all, silently. (2026-09-20)

### `links := Links.new(self)  (property)`

*server/game_server.gd*

What is joined to what (see engine/server/links.gd). Server-wide, not per realm: a wireless link may
have one end in one world and the other somewhere else, so it belongs to neither.

### `flows := Flows.new(self)  (property)`

*server/game_server.gd*

Quantities moving along those links - power, fluid, gas (see engine/server/flows.gd).

### `parcels := Parcels.new(self)  (property)`

*server/game_server.gd*

Things travelling along those links (see engine/server/parcels.gd). Not the same mechanism as
flows, and the file says why.

### `drives := Drives.new(self)  (property)`

*server/game_server.gd*

Values driven through the graph with nothing stored - rotation (see engine/server/drives.gd).

### `assemblies := Assemblies.new(self)  (property)`

*server/game_server.gd*

Blocks that have left the grid and move as one thing (see engine/server/assemblies.gd).

### `modifiers := Modifiers.new(self)  (property)`

*server/game_server.gd*

Named marks on particular items - keen, sturdy (see engine/server/modifiers.gd).

### `ledgers := Ledgers.new(self)  (property)`

*server/game_server.gd*

Named numbers a player owns - coins, reputation, experience (see engine/server/ledgers.gd).

### `objectives := Objectives.new(self)  (property)`

*server/game_server.gd*

Things a player has been asked to do (see engine/server/objectives.gd).

### `characters := Characters.new(self)  (property)`

*server/game_server.gd*

People who stand somewhere and hold a conversation (see engine/server/characters.gd).

### `shops := Shops.new(self)  (property)`

*server/game_server.gd*

Buying and selling, drawn the same way everywhere (see engine/server/shops.gd).

### `conditions := Conditions.new(self)  (property)`

*server/game_server.gd*

What somebody is temporarily under - swiftness, poison (see engine/server/conditions.gd).

### `fields := Fields.new(self)  (property)`

*server/game_server.gd*

Ground that does something to whoever stands in it (see engine/server/fields.gd).

### `companions := Companions.new(self)  (property)`

*server/game_server.gd*

What a tamed creature is being told to do (see engine/server/companions.gd).

### `vehicles := Vehicles.new(self)  (property)`

*server/game_server.gd*

Things you can sit on and steer (see engine/server/vehicles.gd).

### `nameplates := Nameplates.new(self)  (property)`

*server/game_server.gd*

The label over a thing's head (see engine/server/nameplates.gd).

### `companies := Companies.new(self)  (property)`

*server/game_server.gd*

Groups of players that things can belong to (see engine/server/companies.gd).

### `plots := Plots.new(self)  (property)`

*server/game_server.gd*

Ground with an owner, consulted before an edit (see engine/server/plots.gd).

### `area_edits := AreaEdits.new(self)  (property)`

*server/game_server.gd*

Changing many blocks at once, with the same checks one block gets (see engine/server/area_edits.gd).

### `instances := Instances.new(self)  (property)`

*server/game_server.gd*

Private copies of a space, made on demand and thrown away (see engine/server/instances.gd).

### `sources := Sources.new(self)  (property)`

*server/game_server.gd*

Where a thing comes from when the answer is not a recipe (see engine/server/sources.gd).

### `claims := Claims.new(self)  (property)`

*server/game_server.gd*

Parts of the world kept awake when nobody is there, and the budget that stops one player doing it
to everybody else (see engine/server/claims.gd).

### `stations := Stations.new(self)  (property)`

*server/game_server.gd*

Station tiers, workshop upgrades and multiblock structures.

### `sessions := StationSessions.new(self)  (property)`

*server/game_server.gd*

Co-op crafting at stations: presence, shared trays, timed jobs and projects.

### `experiments := Experiments.new(self)  (property)`

*server/game_server.gd*

The experimentation grid (discovering recipes by arranging items).

### `guide := Guide.new(self)  (property)`

*server/game_server.gd*

The guidebook: registered pages and what each player has unlocked.

### `tutorials := Tutorials.new(self)  (property)`

*server/game_server.gd*

Tutorials and contextual tips.

### `milestones := Milestones.new(self)  (property)`

*server/game_server.gd*

What a player has done, for as long as the world lasts (see engine/server/milestones.gd).

### `charging := Charging.new(self)  (property)`

*server/game_server.gd*

Items held down rather than clicked: bows, slings (see engine/server/charging.gd).

### `dev_log := DevLog.new()  (property)`

*server/game_server.gd*

Logs and script errors for mod authors (see engine/server/dev_log.gd).

### `dev_tools := DevTools.new(self)  (property)`

*server/game_server.gd*

Profiler, event tracer, inspector and debug drawing (see engine/server/dev_tools.gd).

### `dev_mode := false  (property)`

*server/game_server.gd*

--dev: every player gets the developer tools (local development).

### `dev_web := DevWeb.new(self)  (property)`

*server/game_server.gd*

The dev dashboard web server (--dev-web=port).

### `hub: HubAnnouncer  (property)`

*server/game_server.gd*

Lists the server on a hub (a child node while online; null for offline servers).

### `port := 0  (property)`

*server/game_server.gd*

The game port (0 when offline).

### `view_distance := DEFAULT_VIEW_DISTANCE  (property)`

*server/game_server.gd*

Chunks of terrain a player is sent, and chunks around them that the world actually runs in.
Both from the host's configuration; see the constants above for why they are separate.

### `mod_reload := ModReload.new(self)  (property)`

*server/game_server.gd*

Quick reloads, the file watcher and full reloads (see engine/server/mod_reload.gd).

### `ugc := Ugc.new(self)  (property)`

*server/game_server.gd*

Player creations: uploads, the server library and serving them (see engine/server/ugc.gd).

### `mod_settings := ModSettings.new(self)  (property)`

*server/game_server.gd*

What mods let a host change without editing them (see engine/server/mod_settings.gd).

### `mod_manifests := {}  (property)`

*server/game_server.gd*

Loaded mods: id -> manifest, in load order, and id -> the running mod (GDScript instance or JsMod).

### `connect := Connect.new(self)  (property)`

*server/game_server.gd*

Blocks that notice their neighbours: fences joining into a run, panes into a window.

### `assembly := Assembly.new()  (property)`

*server/game_server.gd*

Materials, parts and tools built from parts (see Assembly).

### `add_realm(realm_id: String, realm_name := "") -> Realm`

*server/game_server.gd*

Adds a world beside the overworld. A mod calls this while it is setting up, before the world loads,
and then gives the realm a generator the same way it gives the overworld one.

Returns the realm, or null when the name is taken or empty. The id is the mod's own qualified name
("mymod:emberdeep"), so two mods can both have an underworld without colliding.

**See also:** `attach`, `reload`, `set_storage`, `start`

### `add_asset(asset_name: String, path: String, lazy := false) -> void`

*server/game_server.gd*

`lazy` assets are in the manifest but are not part of the download a player waits through to join.
The client fetches one the first time something actually needs it. Music lives here: a track is
megabytes where a texture is a few hundred bytes, and a child should not wait through the soundtrack
to get into the world.

### `add_handler(event: String, handler: Callable, priority: int, owner := "engine") -> void`

*server/game_server.gd*

`owner`: the mod id (or "engine") the profiler and tracer credit.

### `is_excluded(full_name: String) -> bool`

*server/game_server.gd*

Whether a fully qualified name was excluded by some mod's manifest. Checked at registration, so an
excluded thing is never given an id at all - and anything that later names it simply finds nothing,
which is a warning rather than a dangling reference to an id that moved. (2026-09-21)

### `add_command(command: String, description: String, handler: Callable, mod_id: String, permission := "") -> void`

*server/game_server.gd*

permission: "" (everyone), "admin" (needs the "command.<name>" permission, which admins have) or any
permission name (see engine/server/roles.gd).

**See also:** `players`, `register_command`

### `is_allowed(player_id: String, player_name: String) -> bool`

*server/game_server.gd*

Whether a player may join: always when the allowlist is off; else admins and listed players (by id, or
by name until that name first joins and binds the entry to the player's identity).

### `allowlist_add(name_or_id: String) -> void`

*server/game_server.gd*

Adds a player by name (or id) to the allowlist.

### `allowlist_bind(player_id: String, player_name: String) -> void`

*server/game_server.gd*

The first time a listed name joins, its entry is tied to that identity (so the name cannot be taken).

### `has_permission(p, permission: String) -> bool`

*server/game_server.gd*

Whether a player's roles grant a permission (config admins have everything).

### `after_mod_reload() -> void`

*server/game_server.gd*

After a quick reload: clients get the new definitions, recipe book, guide and tutorials.

**See also:** `open_crafting_refresh`, `revalidate`, `sources_index`, `sync`

### `open_crafting_refresh(p: ServerPlayer) -> void`

*server/game_server.gd*

Refreshes a player's open crafting screen (the recipe book may have changed).

### `tell_moderators(text: String) -> void`

*server/game_server.gd*

Messages for admins only (moderation).

**See also:** `has_permission`, `send_message`

### `request_full_reload() -> void`

*server/game_server.gd*

Saves and asks the owner to restart the server with the same settings; clients are told to reconnect.

**See also:** `chunk_coord_of`, `merge`, `tell_admins`, `ticking_chunks`, `to_saved`

### `tell_riding(p: ServerPlayer) -> void`

*server/game_server.gd*

Tells a client whether it is riding, and on what. The client stops predicting its own movement while
it is, which is the whole reason this crosses the wire at all.

**See also:** `config`, `riders_of`

### `player_by_id(player_id: String)`

*server/game_server.gd*

The online player with this id, or null. Two loops already did this by hand.

### `backup_now(requester := 0) -> bool`

*server/game_server.gd*

Flushes pending saves, then archives the world on a worker thread. `requester` (peer id) is told
when it finishes. Returns false if a backup is already running.

**See also:** `chunk_coord_of`, `merge`, `ticking_chunks`, `timestamp`, `to_saved`

### `set_flying(p: ServerPlayer, enabled: bool) -> bool`

*server/game_server.gd*

Starts or stops flight for a player, telling their client. Returns false when they may not fly.

**See also:** `may_fly`

### `may_fly(p: ServerPlayer) -> bool`

*server/game_server.gd*

Creative players fly; anyone else needs the "fly" permission.

**See also:** `has_permission`

### `damage_player(p: ServerPlayer, amount: float, cause: String, attacker = null, direction := Vector3.ZERO, bypass_cooldown := false, knockback := 6.0) -> bool`

*server/game_server.gd*

Returns true if damage applied. `direction` sets the knockback direction (defaults to away from
the attacker). `bypass_cooldown` lets continuous damage (void) ignore the invulnerability window.

**See also:** `add_exhaustion`, `apply_armor`, `broadcast_player_event`, `damage_item`, `get_def`, `get_eye_position`

### `play_sound_at(sound_name: String, pos: Vector3, volume := 1.0, pitch := 1.0, exclude := 0) -> void`

*server/game_server.gd*

Plays a registered sound at a world position for players in range. `exclude` is a peer id that
already played it locally (e.g. the player who broke the block).

### `play_decal(pos: Vector3, normal: Vector3i, look := {}, realm_id := "") -> void`

*server/game_server.gd*

Starts an effect that keeps going until stop_effect. Returns a handle, or 0.

For a machine that should smoke *while it runs*: play_effect is a burst and forgets itself, which
cannot express "this is working now".
Leaves a mark on the world for everyone near enough to see it.

**See also:** `qualified`, `realm_of`

### `play_beam(from: Vector3, to: Vector3, look := {}, realm_id := "") -> void`

*server/game_server.gd*

Draws a line between two places for a moment, for everyone near enough to see it.

**See also:** `qualified`, `realm_of`

### `float_text(text: String, pos: Vector3, options := {}, realm_id := "") -> void`

*server/game_server.gd*

Words that float in the world for a moment and then go: damage off a hit, "+3 copper" over a
chest, a name over a thing. Transient on purpose - nothing is stored, nobody has to clean it up, and
a client that was not listening has missed nothing that matters.

options: color, seconds, rise (how far it drifts up), size, follow (a player or entity it sticks to).

**See also:** `qualified`, `register_entity`

### `send_music(p, track_id: int, fade := 2.0, restart := false) -> void`

*server/game_server.gd*

Tells a player (or everyone, when `p` is null) what music to play. -1 means stop. The track each
player is on is remembered so a mod can call this on every biome change without restarting anything,
and so a player who reconnects hears the same thing rather than silence.

### `set_weather(weather_name: String, intensity := 1.0, seconds := 0.0) -> void`

*server/game_server.gd*

Starts weather, or stops it with an empty name. `seconds` of 0 means until something says otherwise.

### `set_wind(degrees: float, strength := 0.5, seconds := 0.0) -> void`

*server/game_server.gd*

Sets the wind: `degrees` clockwise from north, `strength` 0 (still) to 1 (a gale). `seconds` of 0
means until something says otherwise, matching `set_weather`.

While a mod holds the wind the engine stops drifting it, so a storm's gale does not wander off on
its own halfway through.

### `wind_state() -> Dictionary`

*server/game_server.gd*

The wind as a mod sees it: {angle, strength}.

### `weather_state() -> Dictionary`

*server/game_server.gd*

The weather as a mod sees it: {name, intensity}. "" when the sky is clear.

### `block_sound(block: int, action: String) -> String`

*server/game_server.gd*

Sound name for a block action ("break", "place", "step"); empty when the block has none.

### `set_world_time(time_of_day: float, day_length: float) -> void`

*server/game_server.gd*

`time_of_day`: 0 = midnight, 0.25 = sunrise, 0.5 = noon. `day_length` in seconds, 0 = frozen.

**See also:** `daylight`, `get_day_length`, `phase`

### `on_auth(peer_id: int, signature: PackedByteArray) -> void`

*server/game_server.gd*

The client proves it holds the private key for the identity it presented.

**See also:** `accept`, `allowlist_bind`, `give`, `is_allowed`, `kick`, `sources_index`

### `on_claim_admin(peer_id: int, token: String) -> void`

*server/game_server.gd*

The local host proves it launched this server and becomes a permanent admin.

**See also:** `give`, `send_message`

### `mark_simulation_stale() -> void`

*server/game_server.gd*

Says the simulated set needs working out again. Claims call it; so does anything else that changes
which part of the world should be running.

### `tell_assembly(id: int) -> void`

*server/game_server.gd*

A face is being driven at a new speed: tell whoever is standing in that world and holds the chunk.
Only for blocks that say they turn, because telling a client about a shaft it will not animate is
bytes spent on nothing.
Everything an assembly is made of, once, to whoever is in that world.

**See also:** `realm_of`

### `tell_assembly_moved(id: int) -> void`

*server/game_server.gd*

Where it has got to. Unreliable and ordered, like movement: a position that arrives late is worth
nothing, and the next one is along in a moment.

**See also:** `realm_of`

### `remove_realm(realm_id: String) -> bool`

*server/game_server.gd*

Takes a realm out of the server. Only for instances: a realm a mod declared is part of the world
and stays for the session.

Everything a realm owns hangs off the Realm object - its world, its entities, its tickers - so
dropping the reference is most of the job. What is not automatic is the simulated set, which is
rebuilt from players, and anything holding the realm id.

**See also:** `is_overworld`

### `send_to_realm(p: ServerPlayer, realm_id: String, position: Vector3) -> bool`

*server/game_server.gd*

Moves a player to another world, standing at `position`. Portals, the command and the mod API all
end here, so the order below is the only place it has to be right.

Returns false when there is no such realm, or they are already in it.

**See also:** `ensure_area_loaded`, `generate`, `index`, `links_for`, `qualified`, `realm_of`

### `ensure_area_loaded(pos: Vector3, into: Realm = null) -> void`

*server/game_server.gd*

Loads the chunks around a position so players placed there have ground to stand on.

**See also:** `add_chunk`, `block`, `chunk_coord_of`, `chunk_path`, `decorate`, `generate`

### `get_block_loaded(pos: Vector3i, into: Realm = null) -> int`

*server/game_server.gd*

Every function here takes the world to act in, and `null` means the overworld. A position alone
does not say which world any more - the same coordinates exist in all of them - so anything acting
for a player passes `realm_of(p)`, and anything acting for a creature passes its realm.

**See also:** `add_chunk`, `block`, `chunk_coord_at`, `chunk_path`, `decorate`, `generate`

### `surface_height(x: int, z: int, into: Realm = null) -> int`

*server/game_server.gd*

Y of the highest solid or liquid block in the column (loading it if needed), or -1. Plants and
other non-solid decorations are skipped, so things placed on the surface stand on the ground.

**See also:** `add_chunk`, `block`, `chunk_coord_at`, `chunk_path`, `decorate`, `generate`

### `get_block_data(pos: Vector3i, into: Realm = null) -> Dictionary`

*server/game_server.gd*

Live dictionary for the block at `pos`, or an empty one if it has none. Mutations to a returned
dictionary are saved; call set_block_data to attach data to a block that has none yet.

**See also:** `chunk_coord_at`, `qualified`, `register_instance`

### `find_block_data(block := -1, into: Realm = null) -> Array[Vector3i]`

*server/game_server.gd*

Positions of loaded blocks that have data, optionally only of one block type.

**See also:** `get_block_v`, `qualified`, `register_instance`

### `add_death_messages(key: String, lines: Array) -> void`

*server/game_server.gd*

Adds ways of saying somebody died (see ModApi.add_death_messages). `key` is a cause, or the name of an
entity so a mod's own mob gets its own send-off; "%s" is the player, and a second "%s" is what did it.

**See also:** `qualified`, `register_settings`

### `announce_rare_loot(player, item: int, count: int, position: Vector3) -> void`

*server/game_server.gd*

A find worth noticing: a sparkle where it landed, a sound for whoever found it, and a line in chat so
the rest of the server shares the moment. The sparkle repeats for a little while, so a rare drop in
long grass can still be found. Rarity comes from the table's own weights - nothing is marked by hand.

**See also:** `broadcast_chat`, `cancel_task`, `play_effect`, `play_sound_at`, `schedule`, `send_message`

### `break_block_for(p: ServerPlayer, pos: Vector3i, into: Realm, harvest := true) -> bool`

*server/game_server.gd*

Breaks one block *on a player's behalf*: the pre-event, the loot roll, the drops, the tool wear, the
hunger and the post-event, exactly as breaking it by hand does.

Split out of `on_break_block` so area tools get all of that without copying it. What stays with the
caller is what an area tool decides differently: reach and mining time are per-block questions when
you are swinging at one, and whole-selection questions when you are not. Everything below here is
the same either way. (2026-09-21)

**See also:** `add_exhaustion`, `awarded`, `block_changed`, `block_removed`, `block_state`, `break_block`

### `place_block_for(p: ServerPlayer, pos: Vector3i, block: int, into: Realm) -> bool`

*server/game_server.gd*

Places one block *on a player's behalf* at a chosen cell, for area tools.

Deliberately not `on_place_block`'s path. Almost everything in that function is about placing the
thing you are *holding* where you are *aiming* - the slab that merges with the slab below, the
stair that turns to face you, the bed that needs room for its other half - and none of it means
anything when a mod names a block and a cell. What does carry over is what protects the world:
the block must be placeable, the cell replaceable, the result supported, and nobody standing in it.

`_has_solid_neighbor` is the one hand-placement rule left out on purpose. It stops a player
hanging blocks in mid-air off nothing; an area fill building a floating platform is doing that
deliberately, and one cell at a time would refuse its own interior. (2026-09-21)

**See also:** `block_changed`, `block_removed`, `block_state`, `break_block`, `chunk_coord_at`, `clear_block_data`

### `open_palette(p: ServerPlayer) -> void`

*server/game_server.gd*

Everything that exists, for a creative player to take from.

**A creative game ships no recipes**, so the recipe book - which is how a player finds out what
exists - is empty in exactly the game where finding out what exists matters most. This is the
other half of that: a browser of every block and item, grouped the way they were registered.

Sent rather than derived on the client because the client does not know which items a mod meant
to be takeable; `hidden` on a definition keeps the plumbing out (block data holders, half-slabs
that are placed rather than carried). (2026-09-22)

**See also:** `get_def`

### `on_palette_take(peer_id: int, item: int, whole_stack: bool) -> void`

*server/game_server.gd*

A creative player asking for a stack of something from the palette.

**See also:** `get_def`, `max_stack`, `sync_inventory`

### `on_tutorial_action(peer_id: int, action: String, arg: String) -> void`

*server/game_server.gd*

Tutorial buttons: start <id> | skip (the current step) | stop | tips_on | tips_off.

**See also:** `advance`, `set_tips`, `start`, `stop`

### `on_dev(peer_id: int, action: String, args: Dictionary) -> void`

*server/game_server.gd*

Dev overlay requests: subscribe {channels}, inspect {pos | entity | player}, trace_filter {filter},
clear_errors {source}.

**See also:** `add_shapes`, `allowed`, `clear_errors`, `receive`, `set_inspect`, `set_open`

### `damage_item(p: ServerPlayer, slot: int, amount: int, reason := "use") -> void`

*server/game_server.gd*

Wears an item: adds `amount` to its item data `damage`; at the item's durability it breaks.

**See also:** `clear_slot`, `get_eye_position`, `look_direction`, `max_durability`, `play_effect`, `play_sound_at`

### `refresh_stats(p: ServerPlayer) -> void`

*server/game_server.gd*

Recomputes a player's stats, applies max health and movement speed, reports equipment changes and
sends the result to the client when it changed.

**See also:** `compute`, `refresh_appearance`, `sync_health`

### `refresh_appearance(p: ServerPlayer) -> void`

*server/game_server.gd*

What other players see: held item, visible armor and avatar. Sent to everyone when it changes.

**See also:** `equipment_index`, `selected_item`, `visible_armor`, `visuals`

### `on_set_avatar(peer_id: int, avatar: Dictionary) -> void`

*server/game_server.gd*

A client sent its avatar: while joining it is kept for spawn; in game it replaces the player's look.

**See also:** `ensure_registered`, `is_builtin`, `is_id`, `refresh_avatar`, `sanitize_avatar`, `worn_ids`

### `can_wear(cosmetic_name: String, p: ServerPlayer) -> bool`

*server/game_server.gd*

Whether a player may pick a cosmetic themselves (mods can still dress anyone in anything).

**See also:** `get_def`, `is_approved`, `is_blocked`, `is_builtin`, `is_id`, `look`

### `refresh_avatar(p: ServerPlayer) -> void`

*server/game_server.gd*

Recomputes the look others see: portable look (or the name's default), then this server's picks,
the policy uniform, the player's override and avatar_change handlers.

**See also:** `apply`, `clear_cache`, `default_avatar`, `merge`, `refresh_appearance`, `sanitize_avatar`

### `reapply_requested_avatar(p: ServerPlayer) -> void`

*server/game_server.gd*

Applies the avatar the player last asked for again (a creation in it was approved or removed).

**See also:** `ensure_registered`, `is_builtin`, `is_id`, `refresh_avatar`, `sanitize_avatar`, `worn_ids`

### `dimension_of(p) -> String`

*server/game_server.gd*

The players and roles panel. Answers with {players, roles, can_kick, denied?}.
Which world a player is in. One world today ("" is it); mods that add dimensions set this key on the
player, and the map, compass and markers follow them there.

### `on_map(peer_id: int) -> void`

*server/game_server.gd*

What the player's map shows: everyone in the same dimension (unless the server hides them) and the
markers mods set, also filtered to that dimension.

**See also:** `dimension_of`, `get_block`, `has_permission`, `receive`

### `on_worlds_panel(peer_id: int, action: String, args: Dictionary) -> void`

*server/game_server.gd*

The worlds panel: the servers this one is linked to (network.json), and travel.

**See also:** `has_permission`, `send_message`, `transfer`

### `on_server_panel(peer_id: int, action: String, args: Dictionary) -> void`

*server/game_server.gd*

The admin settings screen. Every action is the command an admin could type, run with their own
permissions, so nothing here grants more than chat already does.

**See also:** `has_permission`, `list`, `mods`, `receive`, `send_message`

### `on_ugc_admin(peer_id: int, action: String, args: Dictionary) -> void`

*server/game_server.gd*

The creations review panel (admins): list {filter, text} | set_status {id, status, reason} |
trust {player_id, on} | ban {player_id, on, reason} | clear_reports {id}. Answers with the list.

**See also:** `clear_reports`, `has_permission`, `review_list`, `set_banned`, `set_status`, `set_trusted`

### `add_recipe(inputs: Dictionary, output: int, count: int, station := "", options := {}) -> int`

*server/game_server.gd*

`station`: "" (crafted anywhere) or a station name blocks declare with `station` (e.g. a crafting table).
options: category, id. Returns the recipe index.

### `get_fuel(item: int) -> float`

*server/game_server.gd*

How long an item burns as fuel (seconds; 0 = not fuel).

**See also:** `register_process`

### `add_process(kind: String, input: int, output: int, count: int, seconds: float) -> void`

*server/game_server.gd*

Processing recipes machines look up: kind ("smelting", "grinding", ...) -> input -> result.

### `crafting_stock(p: ServerPlayer) -> Dictionary`

*server/game_server.gd*

Items a station can draw from containers around it: {item id: count}. Empty when crafting by hand.

**See also:** `find_block_data`, `get_block_v`, `get_container`, `get_eye_position`, `get_item`, `now`

### `craftable_times(p: ServerPlayer, recipe: Dictionary, limit := 999) -> int`

*server/game_server.gd*

How many times the player can craft a recipe right now (inventory plus the station's nearby chests).

**See also:** `at_station`, `count_of`, `crafting_stock`, `get_block_v`, `get_eye_position`, `have`

### `learn_recipe(p: ServerPlayer, recipe_id: String, source := "mod") -> bool`

*server/game_server.gd*

Teaches a recipe. Returns true if the player did not know it (creative players still learn it).

**See also:** `index_of`

### `check_discoveries(p: ServerPlayer) -> void`

*server/game_server.gd*

"pickup" recipes unlock the first time a player holds one of their ingredients.

**See also:** `learn_recipe`, `total`, `using`

### `open_crafting(p: ServerPlayer, station := {}) -> void`

*server/game_server.gd*

Opens the crafting screen for a player: by hand ({}) or at a station {name, position, title}.

**See also:** `crafting_stock`, `evaluate`, `leave`

### `on_station_action(peer_id: int, action: String) -> void`

*server/game_server.gd*

Station screen buttons: "upgrade" uses the next tier's kit, "guide" shows a structure's missing blocks.

**See also:** `get_block_v`, `get_eye_position`, `open_crafting`, `realm_of`, `structure_missing`, `upgrade`

### `show_crafting(p: ServerPlayer) -> void`

*server/game_server.gd*

Mods: opens the crafting screen for a player as if they pressed the crafting key.

**See also:** `open_crafting`

### `craft(p: ServerPlayer, index: int, times := 1) -> int`

*server/game_server.gd*

Crafts a recipe up to `times` times, taking ingredients from the inventory first and then from the
station's nearby chests. Returns how many times it crafted.

**See also:** `add_job`, `consume_tray`, `count_of`, `craftable_times`, `crafting_stock`, `drop`

### `take_recipe_inputs(p: ServerPlayer, index: int) -> Dictionary`

*server/game_server.gd*

Takes one craft's ingredients for crafting by hand: {item, count, data, recipe}, or {} if the
recipe cannot be crafted here.

**See also:** `consume_tray`, `count_of`, `craftable_times`, `crafting_stock`, `evaluate`, `find_block_data`

### `give_crafted(p: ServerPlayer, item: int, count: int, item_data: Dictionary, forged := false) -> void`

*server/game_server.gd*

Gives a finished item (from crafting by hand or assembling) with effects at the station.

**See also:** `crafting_stock`, `drop`, `get_block_v`, `get_eye_position`, `max_stack`, `play_effect`

### `assemble(p: ServerPlayer, assembly_name: String, slots: PackedInt32Array) -> bool`

*server/game_server.gd*

Builds a tool from parts in the player's inventory: `slots` lists a backpack slot per assembly slot.

**See also:** `give_crafted`, `take_assembly_parts`

### `take_assembly_parts(p: ServerPlayer, assembly_name: String, slots: PackedInt32Array) -> Dictionary`

*server/game_server.gd*

Takes the parts for an assembly: {item, count, data}, or {} if they are not valid.

**See also:** `build`, `clear_slot`, `sync_inventory`

### `on_station_coop(peer_id: int, action: String, arg: int) -> void`

*server/game_server.gd*

Co-op actions at the player's station: "view" (recipe index), "deposit" (backpack slot), "take" (tray
index), "start_project" (recipe index), "contribute", "cancel_project".

**See also:** `cancel_project`, `contribute`, `crafting_stock`, `deposit`, `get_block_v`, `get_eye_position`

### `refresh_crafting_stock(pos: Vector3i) -> void`

*server/game_server.gd*

Tells players crafting near a changed container what their station can draw from now.
Called from containers.gd when a container a station draws from changed. Public because it is
reached across files: a leading underscore that another script calls is a lie about what is private.

**See also:** `crafting_stock`

### `static pair_offset(pair: Dictionary, state: int) -> Vector3i`

*server/game_server.gd*

Offset from one half of a two-block piece to the other: `pair.direction` is "back" (away from the
player who placed it), "front", "up" or "down".

**See also:** `facing_direction`

### `pair_position(pos: Vector3i, into: Realm = null) -> Vector3i`

*server/game_server.gd*

The other half of a two-block piece at `pos`, or `pos` itself.

**See also:** `block_state`, `get_block_v`, `pair_offset`

### `is_supported(pos: Vector3i, block: int, into: Realm = null) -> bool`

*server/game_server.gd*

Whether `block` may stand at `pos`: its `support` rule ("solid" or [block names]) must accept the block
below. Blocks without a rule always can.

**See also:** `get_block_v`

### `break_block(pos: Vector3i, drop := true, into: Realm = null, sound := true) -> void`

*server/game_server.gd*

Breaks a block without a player (support lost, explosions, mods): drops items, plays its sound.

`sound` is off for a blast, which breaks fifty blocks in one instant: fifty break sounds on top of
the explosion is a noise, not fifty pieces of feedback.

**See also:** `block_changed`, `block_removed`, `block_state`, `break_block`, `chunk_coord_at`, `clear_block_data`


## Everything else

### `static list(backup_dir: String) -> Array`

*server/world_backups.gd*

Newest first. Each entry: {name, path, size, modified}.

**See also:** `get_value`, `is_id`, `open`, `read_meta`

### `static create(world_dir: String, zip_path: String) -> String`

*server/world_backups.gd*

Worker thread safe. Archives every file under `world_dir` into `zip_path`. Returns "" or an error.

**See also:** `broadcast_entity_event`, `close`, `create`, `enabled`, `exists`, `heading`

### `static prune(backup_dir: String, keep: int) -> int`

*server/world_backups.gd*

Deletes the oldest backups beyond `keep`. Returns how many were removed.

**See also:** `list`, `open`

### `static resolve(backup_dir: String, which: String) -> String`

*server/world_backups.gd*

Resolves "latest", a file name in `backup_dir`, or a path to an archive.

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `static restore(zip_path: String, world_dir: String) -> String`

*server/world_backups.gd*

Replaces `world_dir` with the archive's contents. The current world is moved aside (not deleted)
to <world_dir>.before-restore-<timestamp>. Returns "" or an error.

**See also:** `close`, `open`, `timestamp`

### `static allowed(url: String) -> bool`

*shared/net_access.gd*

Whether this process may fetch `url`. True for everything unless `QW_OFFLINE` is set, and then only
for loopback.

**See also:** `has_permission`, `host_allowed`, `leave`

### `static host_allowed(host: String) -> bool`

*shared/net_access.gd*

The same question when the host is already in hand, as `hub_announcer.leave()` has it.

### `static restricted() -> bool`

*shared/net_access.gd*

Whether this process has been kept off the network. Tests assert on it, because the whole point is
that it is true while they run and false while somebody is playing.

### `chunks := {}  (property)`

*shared/voxel_world.gd*

Vector2i -> Chunk. Read freely; mutate only through add_chunk / remove_chunk / set_block so the
native mirror stays in sync.

### `void_below := false  (property)`

*shared/voxel_world.gd*

When true, everything below y = 0 is open air (skyblock-style void) instead of a solid floor.

### `native: Object = Native.create(&"NativeVoxelWorld")  (property)`

*shared/voxel_world.gd*

NativeVoxelWorld mirror used by native physics, or null.

### `set_block(x: int, y: int, z: int, id: int) -> bool`

*shared/voxel_world.gd*

Returns false if the position is outside the world or in an unloaded chunk.

**See also:** `qualified`, `register_instance`, `set_block_authoritative`

### `static daylight(time_of_day: float) -> float`

*shared/world_time.gd*

Sky light multiplier in [NIGHT_LIGHT, 1].

### `static phase(time_of_day: float) -> String`

*shared/world_time.gd*

Which quarter of the day it is, as a word: "night", "dawn", "day", "dusk". Named here rather than in
whichever mod asked first, so two mods cannot disagree about when dusk begins.
