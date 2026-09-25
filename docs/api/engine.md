# Engine reference

Every documented function inside the engine, grouped by the question it answers rather
than by the folder it lives in. This is the half with no other index, and the half that
kept getting reimplemented: search here before writing anything that reads, normalises or
validates data a mod supplied. For the functions a mod calls, see [mod-api.md](mod-api.md).


## Drops, loot and rewards

### `position`

*server/container.gd*

GDScript: `position: Vector3i  (property)`

Where this container is, for a block. Vector3i.ZERO for a bag or a shared store, which are
nowhere - use `key` to say *which* container this is.

### `key`

*server/container.gd*

GDScript: `key: String  (property)`

The container's address (see Containers.block_key / item_key / store_key). Held so `changed()` can
tell viewers about a container that has no position: marking one by `position` sent every bag in
the world to whoever was looking at the chest at the origin. (2026-09-21)

### `state`

*server/container.gd*

GDScript: `state: Dictionary  (property)`

Mod-owned data saved with the container (e.g. how long the fuel still burns).

### `get_item`

*server/container.gd*

GDScript: `get_item(slot: int) -> Dictionary`

{item, count, data} for a slot (item 0 when empty).

**See also:** `total`

### `group`

*server/container.gd*

GDScript: `group(group_name := "") -> Array`

Slot indices of a named group, or every slot for "".

### `group_of`

*server/container.gd*

GDScript: `group_of(slot: int) -> Dictionary`

The group a slot belongs to ({} if none).

**See also:** `group`

### `add`

*server/container.gd*

GDScript: `add(item: int, count: int, item_data := {}, group_name := "") -> int`

Adds items to a group (or to every slot players may insert into), merging stacks first. Returns
how many did not fit.

### `take`

*server/container.gd*

GDScript: `take(slot: int, count: int) -> Dictionary`

Removes up to `count` items from a slot and returns what was removed as {item, count, data}.

**See also:** `coop`, `get_item`, `max_stack`, `may_take`, `set_item`, `sync_inventory`

### `set_progress`

*server/container.gd*

GDScript: `set_progress(bar: String, value: float) -> void`

Sets a progress bar of the container type (0-1) for viewers.

**See also:** `changed`

### `changed`

*server/container.gd*

GDScript: `changed() -> void`

Shows the current contents to everyone viewing (called automatically by the setters above).

**See also:** `at_key`, `block_key`, `is_block_key`, `position_of`

### `to_network`

*server/container.gd*

GDScript: `to_network() -> Dictionary`

Network form: ids and counts packed, item data by slot, progress values.

### `block_key`

*server/containers.gd*

GDScript: `static block_key(pos: Vector3i) -> String`

What a container screen is showing, as one string. Three kinds live behind it:

b:12,64,-3   a block - the store is that block's data
i:7          the bag in the viewer's own inventory slot 7 - the store is that item's data
s:mod:vault  a shared store - the store is `stores[name]`, saved with the world

**One type rather than a Vector3i that is sometimes something else.** The addressing used to be a
position everywhere, which is why "a container that is the same wherever you open it" had nowhere
to live. A tagged string keeps every viewer map, dirty set and open-screen field a single type,
and the tag says which kind you have rather than leaving it to be inferred. (2026-09-21)

### `stores`

*server/containers.gd*

GDScript: `stores := {}  (property)`

Shared stores: name -> the dictionary a container view is backed by. Saved with the world.

The engine does not decide whose a store is - the *name* does. A mod wanting one vault for the
server asks for "vault"; a mod wanting one each asks for "vault_" + player_id. That keeps the
sharing rule where the rule belongs and this table a plain dictionary. (2026-09-21)

### `register`

*server/containers.gd*

GDScript: `register(type_name: String, def: Dictionary) -> bool`

Registers a container type. Returns false when invalid.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `type_of_block`

*server/containers.gd*

GDScript: `type_of_block(block: int) -> Dictionary`

The container type of a block, or {}.

### `get_container`

*server/containers.gd*

GDScript: `get_container(pos: Vector3i, player = null)`

JavaScript: `api.getContainer(pos, player)`

The container at a position (loads its chunk), or null if the block there is not a container.

**See also:** `block_key`, `get_block_data`, `get_block_loaded`, `realm_of`, `set_block_data`, `type_of_block`

### `at_key`

*server/containers.gd*

GDScript: `at_key(key: String, player = null)`

The container a key names, whoever it belongs to, or null. The one place that knows where each
kind of store lives; everything else works in keys.

**See also:** `get_container`, `get_def`, `is_block_key`, `item_key`, `store_key`

### `declare_store`

*server/containers.gd*

GDScript: `declare_store(store_name: String, type_name: String) -> bool`

Declares a shared store, if it does not exist yet. Returns false if the type is unknown.

### `open_item`

*server/containers.gd*

GDScript: `open_item(p, slot: int) -> bool`

Opens the bag in one of a player's own inventory slots.

**See also:** `at_key`, `close`, `is_block_key`, `item_key`, `merge`, `position_of`

### `open_store`

*server/containers.gd*

GDScript: `open_store(p, store_name: String) -> bool`

Opens a shared store by name.

**See also:** `at_key`, `close`, `is_block_key`, `merge`, `position_of`, `store_key`

### `close`

*server/containers.gd*

GDScript: `close(p, tell_client := true) -> void`

Closes the player's container screen (`tell_client`: the server decided, e.g. it was broken).

**See also:** `input`, `is_block_key`, `leave`, `player_by_id`, `position_of`, `remove_realm`

### `mark_changed`

*server/containers.gd*

GDScript: `mark_changed(pos: Vector3i, p = null, slot := -1) -> void`

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

### `changed`

*server/containers.gd*

GDScript: `changed(key: String, p = null, slot := -1) -> void`

The same, for any container: a bag or a shared store has no position to be marked at.

**See also:** `at_key`, `block_key`, `is_block_key`, `position_of`

### `update`

*server/containers.gd*

GDScript: `update(delta: float) -> void`

Sends changed contents to viewers and closes screens players walked away from.

### `block_removed`

*server/containers.gd*

GDScript: `block_removed(pos: Vector3i, store: Dictionary, old_block: int, into = null) -> void`

A container block was removed: close screens and spill the contents.

**See also:** `block_key`, `close`, `drop_item`, `get_item`, `type_of_block`

### `holds_open_bag`

*server/containers.gd*

GDScript: `holds_open_bag(p, slot: int) -> bool`

Whether this inventory slot is the bag the player currently has open.

**See also:** `item_key`

### `click`

*server/containers.gd*

GDScript: `click(p, slot: int, button: int, shift: bool) -> void`

A click on container slot `slot` by a player whose screen shows it. Returns true if handled.

**See also:** `accepts`, `at_key`, `changed`, `clear_slot`, `get_def`, `get_item`

### `quick_move_in`

*server/containers.gd*

GDScript: `quick_move_in(p, slot: int) -> bool`

Shift-click on a backpack slot while a container is open: move the stack into the container.

**See also:** `accepts`, `at_key`, `changed`, `clear_slot`, `item`, `sync_inventory`

### `announce_rare`

*server/loot.gd*

GDScript: `announce_rare := true  (property)`

Set false to stop the engine announcing rare finds (a server that would rather stay quiet).

### `rate`

*server/loot.gd*

GDScript: `rate := 1.0  (property)`

Multiplies how many times every pool rolls: a host's "how much loot" setting (see ModApi.set_loot_rate).

### `boosts`

*server/loot.gd*

GDScript: `boosts := {}  (property)`

Temporary changes on top of `rate`, for events ("double coins this weekend", "pumpkins all October"):
"table:<name>" -> how much more often that table's pools roll, "item:<name>" -> how much more often that
item comes up in any table. Each is {factor, until} where `until` is a unix time, or 0 for no end.

### `register`

*server/loot.gd*

GDScript: `register(table_name: String, def: Dictionary) -> void`

Declares a table. Entries naming an item that does not exist are left out with a warning rather than
dropping nothing at all later.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `extend`

*server/loot.gd*

GDScript: `extend(table_name: String, def: Dictionary, owner := "") -> void`

Adds pools to a table another mod owns, without forking it. Unknown tables are created. `owner` is the
mod adding them, so reloading that mod takes its pools away again instead of stacking another copy on
every save.

### `forget`

*server/loot.gd*

GDScript: `forget(owner: String) -> void`

Takes back everything a mod added to other mods' tables, for a reload.

**See also:** `path_for`

### `has`

*server/loot.gd*

GDScript: `has(table_name: String) -> bool`

Whether a table is registered under this name. Generated tables (`mob:`, `block:`) only exist once
something has asked for them, so this answers false for a creature nothing has killed yet.

### `roll`

*server/loot.gd*

GDScript: `roll(table_name: String, context := {}) -> Array`

Rolls a table. `context` says what the loot came out of, so conditions can look at it:
seed        an int to make the roll repeatable (a chest); left out, the roll is random
player      who caused it (their luck, what they have already found)
cause       "player", "mob", "fire", "fall", … for a mob's death
tool        the item id in the hand that did it
position    where it happened (depth and biome come from this)
Returns [[item id, count, data], …].

**See also:** `awarded`, `factor_for`, `get_time_of_day`

### `preview`

*server/loot.gd*

GDScript: `preview(table_name: String, context := {}) -> Array`

Rolls without any of the consequences of actually getting the loot. Use this when the drop might still
be thrown away - a creative player breaking a block, or a handler that may cancel the break - and call
`awarded` once it is really handed over.

**See also:** `factor_for`, `get_time_of_day`

### `awarded`

*server/loot.gd*

GDScript: `awarded(table_name: String, out: Array, context := {}) -> void`

What getting the loot means for this player: they have now met this table, a long run of bad luck pays
out, and a find worth announcing is announced. Called for you by `roll`; call it yourself after a
`preview` that really happened.

**See also:** `announce_rare_loot`, `is_rare`, `rarest`

### `from_drops`

*server/loot.gd*

GDScript: `from_drops(drops: Array) -> Dictionary`

A mob's or block's `drops` list as a table: [[item, count, chance]] becomes one pool per line, each
rolling once, so an old definition behaves exactly as it did.

### `load_files`

*server/loot.gd*

GDScript: `load_files(mod_id: String, mod_dir: String) -> void`

Registers every loot/*.json in a mod folder as "<mod>:<file name>", so a creator can tune what drops
without touching code. A file may hold one table, or {"<name>": {table}, …} for several.

**See also:** `open`, `register`

### `table_for_entity`

*server/loot.gd*

GDScript: `table_for_entity(def: Dictionary) -> String`

The table a mob's or block's drops come from: the one its definition names in `loot`, or one made from
its old `drops` list the first time it is needed (so mods written before tables keep working and still
get conditions, tuning and rare finds). Generated tables are named "mob:<name>" and "block:<name>".

**See also:** `from_drops`

### `table_for_block`

*server/loot.gd*

GDScript: `table_for_block(block: int, default_drops: Array) -> String`

The name of the table a block drops from, building it from `default_drops` the first time.

As with `table_for_entity`, the table does not exist until this is called - so anything asking what
a block can drop has to call this first, or the registry will honestly report that it has never
heard of it. (2026-09-22)

**See also:** `from_drops`

### `fill`

*server/loot.gd*

GDScript: `fill(container, player = null) -> void`

JavaScript: `api.fill(container, player)`

Fills a container from its `loot` block data, once. `player` is whoever opened it, when known.

A chest whose data says `personal: true` is rolled for each player separately: everyone who opens it
gets their own loot, handed straight to them, so nobody has to race a sibling for the good item. The
chest is then an ordinary chest to keep things in. Any other chest is filled once and shared.

### `set_boost`

*server/loot.gd*

GDScript: `set_boost(target: String, factor: float, seconds := 0.0) -> String`

Makes something more (or less) common for a while: `target` is a table name, an item name, or either
with its "table:"/"item:" prefix; `factor` is how much more often; `seconds` ends it on its own (0: it
stays until changed). Setting the factor back to 1 clears it.

### `factor_for`

*server/loot.gd*

GDScript: `factor_for(key: String) -> float`

What `target` is multiplied by right now, 1.0 when nothing applies. Expired events clear themselves.

### `active_boosts`

*server/loot.gd*

GDScript: `active_boosts() -> Array`

Everything a host turned up or down, for the admin screen and /loot: [{target, factor, ends_in}].

**See also:** `factor_for`

### `chance_of`

*server/loot.gd*

GDScript: `chance_of(table_name: String, item_id: int) -> float`

How likely this table is to give `item_id` at all, as 0-1. Used to tell a find worth announcing from
an everyday one, so nothing has to be marked "rare" by hand.
Boosts and the loot rate count here: during a "coal everywhere" event, coal is common, and announcing
every lump of it as a rare find would drown the chat the event is supposed to liven up.

**See also:** `factor_for`

### `sources_of`

*server/loot.gd*

GDScript: `sources_of(item_id: int) -> Array`

JavaScript: `api.sourcesOf(itemId)`

Everywhere an item can come from: [{table, kind ("mob" | "block" | "table"), source, chance, count}],
likeliest first. This is what the guide's "what drops this?" is built from, so a player can find out
where something comes from without being told by an adult.

**See also:** `chance_of`, `describe`, `kind_of`, `of_item`

### `sources_index`

*server/loot.gd*

GDScript: `sources_index(limit := 3) -> Dictionary`

Where things come from, small enough to send a client once: {item id: [[source, percent], …]}, at most
a few sources each. The tooltip's "Dropped by" line is built from this.

**See also:** `chance_of`, `describe`

### `kind_of`

*server/loot.gd*

GDScript: `kind_of(table_name: String) -> String`

Whether a table belongs to a mob, a block, or is a table in its own right (a chest, a reward).

### `describe`

*server/loot.gd*

GDScript: `describe(table_name: String) -> String`

The name a player would recognise a table by: the mob or block it belongs to, or the table's own name.

**See also:** `kind_of`

### `is_rare`

*server/loot.gd*

GDScript: `is_rare(table_name: String, item_id: int) -> bool`

True when getting this item from this table is a find worth making a fuss about.

**See also:** `chance_of`

### `rarest`

*server/loot.gd*

GDScript: `rarest(table_name: String) -> Dictionary`

The least likely thing a table can give, as {item, count}: what a run of bad luck eventually pays out.

**See also:** `chance_of`

### `set_accepts`

*server/parcels.gd*

GDScript: `set_accepts(node: Dictionary, filter: Dictionary) -> void`

JavaScript: `api.setAccepts(node, filter)`

What a face will take. `items` and `tags` name what is allowed; an empty filter takes anything.
`deny` turns it inside out, which is how a mod writes "everything except cobblestone".

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `send`

*server/parcels.gd*

GDScript: `send(from: Dictionary, item_name: String, count: int, data := {}) -> bool`

Sends something from a face to whichever connected face will take it. Returns true if it is on its
way; false if nothing would take it, which is the answer a mod needs to decide whether to keep
holding the thing or to stop trying.

**See also:** `key_name`, `node_key`, `reachable`

### `would_accept`

*server/parcels.gd*

GDScript: `would_accept(from: Dictionary, item_name: String) -> bool`

JavaScript: `api.wouldAccept(from, itemName)`

Whether anything connected to this face would take this item, without sending it.

**See also:** `key_name`, `node_key`, `qualified`, `reachable`, `tag`

### `update`

*server/parcels.gd*

GDScript: `update(delta: float) -> void`

Moves everything in flight along, and delivers what has arrived.

### `in_transit`

*server/parcels.gd*

GDScript: `in_transit() -> int`

How many parcels are in flight, for the dev tools and for tests.


## World generation

### `setup`

*server/spawners.gd*

GDScript: `setup() -> void`

Hooks every spawner block up to block ticks (after all mods registered their blocks). One shared
handler table, so a realm added later gets them too.

### `load_saved`

*server/structure_tools.gd*

GDScript: `load_saved() -> void`

Loads templates saved in this world's structures/ folder as "world:<name>".

**See also:** `add_template`, `folder`, `key_name`, `node_key`, `open`, `place`

### `place`

*server/structure_tools.gd*

GDScript: `place(template_name: String, at: Vector3i, rotation := 0, into = null) -> bool`

Places a template now (world edits and block data), corner at `at`.

**See also:** `get_block`, `rotate`, `set_block`, `set_block_authoritative`, `set_block_data`, `start_effect`

### `carvers`

*server/worldgen/biome_generator.gd*

GDScript: `carvers: Array = []  (property)`

Carvers and other passes: objects with carve(chunk, generator) run after terrain, before features.

### `structures`

*server/worldgen/biome_generator.gd*

GDScript: `structures: Structures  (property)`

Templates and structure sets placed after features (see worldgen/structures.gd).

### `freeze`

*server/worldgen/biome_generator.gd*

GDScript: `freeze() -> void`

Called once every mod has registered its blocks: snapshots block tables for the worker threads.

### `climate`

*server/worldgen/biome_generator.gd*

GDScript: `climate(x: int, z: int) -> Dictionary`

{t, h, w, p, c} at a column.

### `weights`

*server/worldgen/biome_generator.gd*

GDScript: `weights(c: Dictionary) -> Dictionary`

Blend weights {biome index: weight} for a climate, normalized. Weights are relative to the closest
biome, so every column has a clear winner and borders blend over a short distance.

### `column`

*server/worldgen/biome_generator.gd*

GDScript: `column(x: int, z: int) -> Dictionary`

{biome (index), height} for a column.

**See also:** `climate`, `weights`

### `resolve`

*server/worldgen/features.gd*

GDScript: `static resolve(def: Dictionary, block_id: Callable) -> Dictionary`

Resolves block names in a data feature to ids. Returns {} if the feature is invalid.

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `add_template`

*server/worldgen/structures.gd*

GDScript: `add_template(template_name: String, doc: Dictionary) -> bool`

Parses a template dictionary (from JSON). Unknown blocks are skipped. Returns false if invalid.

### `rotate`

*server/worldgen/structures.gd*

GDScript: `static rotate(p: Vector3i, size: Vector3i, rotation: int) -> Vector3i`

Rotates a local template position (y unchanged) inside a template of `size`.

### `start_for`

*server/worldgen/structures.gd*

GDScript: `start_for(s: Dictionary, region: Vector2i, gen) -> Dictionary`

The structure a region holds, or {} (cached; safe to call from worker threads).

**See also:** `column`, `rotated_size`, `unlock`

### `place_in_chunk`

*server/worldgen/structures.gd*

GDScript: `place_in_chunk(chunk, gen, writer, data: Dictionary) -> void`

Writes every structure piece that overlaps this chunk. `data` collects block data {Vector3i: dict}.

**See also:** `get_block`, `rotate`, `set_block`, `set_state`, `start_for`

### `capture`

*server/worldgen/structures.gd*

GDScript: `static capture(server, lo: Vector3i, hi: Vector3i, keep_air := false) -> Dictionary`

A template dictionary (JSON-ready) from a region of a world. `keep_air`: leave air cells out (the
structure then keeps the terrain there). Block data in the region (chest contents, spawner settings)
goes into `data`.

**See also:** `get_block_data`, `get_block_loaded`, `get_block_state`

### `nearest`

*server/worldgen/structures.gd*

GDScript: `nearest(set_name: String, from: Vector3, gen, rings := 4) -> Vector3`

Where the nearest structure of a set is, or Vector3.INF. Searches outwards from the region the
point is in, up to `rings` regions away.

**A locator, because a structure nobody can find is the same as no structure.** Everything here is
computed from the world seed and the region, so this asks the same question chunk generation asks
and gets the same answer - without generating anything. A game that wants to point a player at the
dungeon it placed had otherwise to guess a position and hope, which is exactly what Firstlight did
for an afternoon: it marked a spot near the player and the ruin was two thousand blocks away.
(2026-09-24)

**See also:** `start_for`


## Blocks and the world

### `make_context`

*client/chunk_mesher.gd*

GDScript: `static make_context(registry, atlas_uv: Dictionary) -> Dictionary`

Builds the read-only context meshing threads need from the registry and atlas.

**See also:** `index`

### `build`

*client/chunk_mesher.gd*

GDScript: `static build(chunks: Array, ctx: Dictionary) -> Array`

`chunks`: 9 PackedByteArrays for the 3x3 neighbourhood, index (dx + 1) + (dz + 1) * 3, empty where
not loaded. Returns [solid_arrays, translucent_arrays, models]; models is a PackedInt32Array of
(block id, x, y, z, sky light, block light) per model block.

**See also:** `area_cells`, `body_font`, `box`, `box_mesh`, `check_icon`, `close_icon`

### `rules`

*server/area_edits.gd*

GDScript: `rules := {}  (property)`

Rules a mod registered, name -> Callable(ctx) -> Array[Vector3i].

### `problem`

*server/area_edits.gd*

GDScript: `problem := ""  (property)`

Why the last call refused, in words a player can be shown. A selection that silently does nothing
is indistinguishable from a broken tool. (2026-09-21)

### `register_rule`

*server/area_edits.gd*

GDScript: `register_rule(rule_name: String, chooser: Callable) -> void`

Registers a way of choosing cells. The callable is handed the context dictionary the mod passed to
`area_cells` and returns an Array of Vector3i.

### `cells`

*server/area_edits.gd*

GDScript: `cells(rule_name: String, ctx: Dictionary) -> Array`

The cells a rule chooses, capped and de-duplicated. Always returns something a caller can loop
over, so a mod never has to check for null.

### `apply`

*server/area_edits.gd*

GDScript: `apply(player, cell_list: Array, options := {}) -> Dictionary`

Applies one change to every cell a player is allowed to change.

options: {block (id to set; 0 or absent breaks instead), drops (default true), realm}.

Returns {changed, skipped, refused, reason}. **`skipped` is not a failure** - a selection that
crosses into somebody's garden does the part outside it and says how much it left alone, which is
friendlier than refusing the lot and lets a vein run up to a boundary and stop.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `preview`

*server/area_edits.gd*

GDScript: `preview(player, cell_list: Array, options := {}) -> void`

Outlines a selection for one player, before they commit to it. `seconds` 0 leaves it up until the
next call clears it, which is what a tool holding a selection wants.

**See also:** `factor_for`, `get_time_of_day`

### `clear_preview`

*server/area_edits.gd*

GDScript: `clear_preview(player) -> void`

Takes the outline away.

**See also:** `preview`

### `realm`

*server/block_ticks.gd*

GDScript: `realm  (property)`

The world these blocks are in. Everything here is indexed by chunk coordinate, and every realm has
a chunk (0, 0), so the table has to belong to one world rather than to the server.

### `clock`

*server/block_ticks.gd*

GDScript: `clock := 0.0  (property)`

Seconds of simulated world time (persists across restarts).

### `handlers`

*server/block_ticks.gd*

GDScript: `handlers := {}  (property)`

Block id -> {handler, interval, catch_up}.

### `cost_by_chunk`

*server/block_ticks.gd*

GDScript: `cost_by_chunk := {}  # Vector2i -> int  (property)`

Microseconds spent in handlers, by chunk, since it was last read. This is what makes a claim's cost
a measurement rather than a guess: machines are block ticks, and a block tick knows where it is.

### `register`

*server/block_ticks.gd*

GDScript: `register(block: int, handler: Callable, options := {}, owner := "engine") -> void`

options.random: false gives a block a handler for *scheduled* ticks only, and keeps it out of the
per-chunk index of randomly-ticked blocks. That index is also what marks a chunk as one that has to
be saved, so indexing a block as common as water means every chunk with a puddle in it is written
on every save. Liquids are driven entirely by scheduling, so they ask for this. (2026-09-19)

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `schedule`

*server/block_ticks.gd*

GDScript: `schedule(pos: Vector3i, seconds: float, payload := {}) -> void`

Calls the handler of the block at `pos` after `seconds` (reason "scheduled"). One per position; a
new schedule replaces the old one.

**See also:** `chunk_coord_at`, `index`

### `scan`

*server/block_ticks.gd*

GDScript: `static scan(blocks: PackedByteArray, ids: PackedInt32Array) -> Dictionary`

Worker thread: local indices of the given block ids in a chunk's block array.

### `scan_ids`

*server/block_ticks.gd*

GDScript: `scan_ids() -> Array`

Block ids the chunk jobs should index: [tickable ids, light-emitting ids].

### `save_chunk`

*server/block_ticks.gd*

GDScript: `save_chunk(coord: Vector2i)`

What to save with a chunk (null when nothing).

### `ticking_chunks`

*server/block_ticks.gd*

GDScript: `ticking_chunks() -> Array`

Chunks whose tick state must be saved.

### `update`

*server/block_ticks.gd*

GDScript: `update(delta: float, simulated: Dictionary) -> void`

`simulated` is the set of chunk coordinates close enough to somebody to be run; everything else
that is loaded is left alone. The clock advances either way, so a chunk that comes back is told how
long it was asleep rather than losing the time.

### `light_levels`

*server/block_ticks.gd*

GDScript: `light_levels(pos: Vector3i) -> Dictionary`

{sky, block} light levels (0-15) at a position; sky is not scaled by the time of day.

**See also:** `block_light`, `sky_light`

### `light_at`

*server/block_ticks.gd*

GDScript: `light_at(pos: Vector3i, daylight: float) -> int`

Light plants and mobs care about: block light or daylight-scaled sky light, whichever is brighter.

### `refresh_around`

*server/connect.gd*

GDScript: `refresh_around(pos: Vector3i, into = null) -> void`

Called when a block is placed or broken: fixes up that cell and the four around it.

**See also:** `refresh`

### `refresh`

*server/connect.gd*

GDScript: `refresh(pos: Vector3i, into = null) -> void`

Puts the right form of a connecting block at `pos`, if what is there is one.

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `explode`

*server/explosions.gd*

GDScript: `explode(center: Vector3, power: float, options := {}) -> Dictionary`

JavaScript: `api.explode(center, power, options)`

options.realm: the world it goes off in (a Realm, or null for the overworld). An explosion is a
thing that happens in a place, and a position alone no longer says where.

**See also:** `blast_resistance`, `break_block`, `cast`, `damage`, `damage_player`, `get_block_v`

### `kinds`

*server/fields.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, radius, seconds, tick, condition, effect, affects, except_owner, owner}

### `fields`

*server/fields.gd*

GDScript: `fields := {}  (property)`

id -> {id, kind, realm, position, radius, expires, next_tick, level, owner, handle}

### `place`

*server/fields.gd*

GDScript: `place(field_name: String, position: Vector3, options := {}) -> int`

Puts one down. `options`: seconds, radius, level (multiplies damage, heal and the condition's
level), owner (a player or a creature), realm.

**See also:** `get_block`, `rotate`, `set_block`, `set_block_authoritative`, `set_block_data`, `start_effect`

### `at`

*server/fields.gd*

GDScript: `at(position: Vector3, realm_id := "") -> Array`

Every field a point is inside, for a mod that wants to ask rather than be told.

**See also:** `get_block_v`, `uptime`

### `to_saved`

*server/fields.gd*

GDScript: `to_saved() -> Array`

Fields are saved: a village campfire that went out because somebody restarted the server would be a
puzzle rather than a feature. Written as how long is *left*, since server time restarts with it.

### `kinds`

*server/instances.gd*

GDScript: `kinds := {}  (property)`

Kinds a mod registered: name -> def.

### `live`

*server/instances.gd*

GDScript: `live := {}  (property)`

Instances that exist now: id -> {kind, realm_id, members, empty_since, data}.

### `problem`

*server/instances.gd*

GDScript: `problem := ""  (property)`

Why the last call refused, in words somebody can be shown.

### `register`

*server/instances.gd*

GDScript: `register(kind_name: String, def: Dictionary) -> bool`

Declares a kind of instance. `generator` is the terrain (the same object `set_world_generator`
takes); without one the instance is empty air, which is what a mod building its own room wants.

def: {generator, passes, empty_seconds, max_players, display_name}.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `open`

*server/instances.gd*

GDScript: `open(kind_name: String, options := {}) -> String`

Makes one, and returns its id ("" if it could not be made).

options: {seed, data (anything the mod wants to keep with it)}.

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `enter`

*server/instances.gd*

GDScript: `enter(player, instance_id: String, position: Vector3) -> bool`

Sends a player in, remembering where they were so `leave` can put them back.

**See also:** `send_to_realm`

### `leave`

*server/instances.gd*

GDScript: `leave(player) -> bool`

Puts a player back where they were before they entered. Returns false if they were not in one.

**See also:** `allowed`, `close`, `finish`, `get_block`, `gone`, `send_to_realm`

### `close`

*server/instances.gd*

GDScript: `close(instance_id: String) -> bool`

Closes one now: everybody inside goes back, and the realm is thrown away.

**See also:** `input`, `is_block_key`, `leave`, `player_by_id`, `position_of`, `remove_realm`

### `id_of`

*server/instances.gd*

GDScript: `id_of(player) -> String`

The instance a player is in, or "".

### `data_of`

*server/instances.gd*

GDScript: `data_of(instance_id: String) -> Dictionary`

What a mod kept with an instance when it opened it.

### `update`

*server/instances.gd*

GDScript: `update(_delta: float) -> void`

Closes instances that have been empty long enough. Called each tick.

### `kinds`

*server/liquids.gd*

GDScript: `kinds := {}  (property)`

Block id -> {range, falls, speed, name}

### `meetings`

*server/liquids.gd*

GDScript: `meetings := {}  (property)`

Two block ids meeting -> the block that forms. Keyed "lower:higher" so the pair is order-free.

### `register`

*server/liquids.gd*

GDScript: `register(block: int, def: Dictionary) -> void`

`shallow` is the block id to use once it has travelled `shallow_from` blocks (0 for none). Both ids
are the same liquid as far as flowing, drying and meeting are concerned.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `register_meeting`

*server/liquids.gd*

GDScript: `register_meeting(a: int, b: int, result: int) -> void`

What forms where these two meet. The mod decides; the engine has never heard of obsidian.

### `family_of`

*server/liquids.gd*

GDScript: `family_of(block: int) -> int`

The deep form of whatever liquid this is, so the two forms are one thing everywhere it matters.

### `block_changed`

*server/liquids.gd*

GDScript: `block_changed(pos: Vector3i, old: int, block: int) -> void`

A block was placed or broken: whatever was flowing near it may now have somewhere to go, or nothing
holding it up.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `step`

*server/liquids.gd*

GDScript: `step(pos: Vector3i) -> void`

One step for the liquid at `pos`. Called from a scheduled block tick.

**See also:** `block_state`, `family_of`, `get_block_v`, `set_block_authoritative`

### `patterns`

*server/multiblocks.gd*

GDScript: `patterns := {}  (property)`

Name -> {name, owner, cells: [{offset, spec}], controller: Vector3i, size}

### `register`

*server/multiblocks.gd*

GDScript: `register(pattern_name: String, def: Dictionary, owner := "engine") -> bool`

def: layers (bottom first, each a list of rows of characters), key (character -> block name or
"#tag"), controller (which character is the controller; default the first key that matches one cell).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `at`

*server/multiblocks.gd*

GDScript: `at(controller_pos: Vector3i, pattern_name := "") -> Dictionary`

Is a machine of this pattern standing with its controller here? Worked out now rather than looked up.

**See also:** `get_block_v`, `uptime`

### `block_changed`

*server/multiblocks.gd*

GDScript: `block_changed(pos: Vector3i, _old: int, _block: int) -> void`

A block was placed or broken: a machine near it may have just been finished, or just been spoiled.

Every pattern is tried with this block as each of its cells in turn, which is why a pattern is
capped: the work is cells squared, and a machine is a handful of blocks.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `plots`

*server/plots.gd*

GDScript: `plots := {}  (property)`

id -> {id, realm, from, to, owner_player, owner_company, name, members: {player_id: true}, open}

### `problem`

*server/plots.gd*

GDScript: `problem := ""  (property)`

Why the last claim was refused, in words somebody can be shown.

### `claim`

*server/plots.gd*

GDScript: `claim(realm_id: String, from: Vector3i, to: Vector3i, options := {}) -> int`

Marks out a plot. `owner` is a player id, or use `company` for one owned by a group.

**See also:** `coop`

### `at`

*server/plots.gd*

GDScript: `at(realm_id: String, pos: Vector3i) -> Dictionary`

The plot a block is in, or {}.

**See also:** `get_block_v`, `uptime`

### `add_member`

*server/plots.gd*

GDScript: `add_member(id: int, player_id: String) -> bool`

Lets somebody else build here. A plot owned by a company already admits its members.

### `may_build`

*server/plots.gd*

GDScript: `may_build(player, realm_id: String, pos: Vector3i) -> bool`

JavaScript: `api.mayBuild(player, realmId, pos)`

Whether this player may change a block here. Everything outside a plot is allowed: the engine does
not decide that the world is closed by default, because most of it is not anybody's.

**See also:** `at`, `may_build_in`, `qualified`

### `of_player`

*server/plots.gd*

GDScript: `of_player(player_id: String) -> Array`

Every plot somebody has a say in, for a screen or a command.

**See also:** `is_member`, `rank_of`

### `id`

*server/realm.gd*

GDScript: `id := ""  (property)`

What a mod called it ("overworld", "mymod:emberdeep"). The overworld's name is "" for the world a
server has always had, so a save written before realms existed is still where it was.

### `ephemeral`

*server/realm.gd*

GDScript: `ephemeral := false  (property)`

An instance's realm: made on demand, thrown away when it empties. Never written to disk, so a
dungeon run leaves no folder behind and a crash mid-run leaves nothing to clean up. (2026-09-21)

### `generator`

*server/realm.gd*

GDScript: `generator = null  (property)`

Set once the mods have run: the terrain this realm is made of. Realms differ mostly by this, and it
is what a chunk job is handed. A mod supplies it with set_world_generator, or asks for the engine's
biome generator, which is then usually - but not always - the same object.

### `biome_generator`

*server/realm.gd*

GDScript: `biome_generator = null  (property)`

JavaScript: `api.biomeGenerator(property)`

The engine biome generator, if this realm uses one. **Not** the same field as `generator`: a game can
use its own world generator and still want biomes for spawning and for "what biome am I in", which
is why conflating the two broke chunk generation for the games that do. (2026-09-19)

**See also:** `block`, `qualified`, `register_instance`

### `block_ticks`

*server/realm.gd*

GDScript: `block_ticks: BlockTicks  (property)`

Blocks that change over time in this realm, and the light it is lit by. One per realm rather than
one per server, because everything in it is indexed by chunk coordinate and every realm has a
chunk (0, 0) - a single table would have the Emberdeep's furnaces and the overworld's sharing a key.

### `signals`

*server/realm.gd*

GDScript: `signals: Signals  (property)`

Levels spreading from block to block in this realm (see engine/server/signals.gd). Per realm for
the same reason as everything else here: a position alone does not say which world.

### `liquids`

*server/realm.gd*

GDScript: `liquids: Liquids  (property)`

Liquids flowing in this realm (see engine/server/liquids.gd).

### `multiblocks`

*server/realm.gd*

GDScript: `multiblocks: Multiblocks  (property)`

Machines assembled out of blocks (see engine/server/multiblocks.gd).

### `block_data`

*server/realm.gd*

GDScript: `block_data := {}  # Vector2i chunk -> {Vector3i: Dictionary}  (property)`

Blocks that differ from freshly generated terrain, and which chunks still need writing.

### `deltas`

*server/realm.gd*

GDScript: `deltas := {}  # Vector2i chunk -> {local index: block id}  (property)`

Delta persistence: what each chunk's terrain was when generated, and how it differs now.

### `save_queue`

*server/realm.gd*

GDScript: `save_queue := {}  # Vector2i chunk -> true  (property)`

Chunks waiting to be serialized, and chunks being loaded or generated on a worker thread. Both are
per realm for the same reason as block_ticks: the coordinate alone does not say which world.

### `entity_chunks`

*server/realm.gd*

GDScript: `entity_chunks := {}  # Vector2i chunk -> true  (property)`

Chunks whose saved file lists persistent creatures; resaved so ones that walked away are dropped.

### `save_dir`

*server/realm.gd*

GDScript: `save_dir := ""  (property)`

Where this realm's chunks live. The overworld keeps the folder it always had; every other realm gets
one of its own beside it, so an old save is still a valid new save.

### `simulated`

*server/realm.gd*

GDScript: `simulated := {}  # Vector2i chunk -> true  (property)`

Chunks close enough to somebody to be run. Everything else that is loaded is still there - a player
can still see it, it is still saved - it simply does not tick. Empty means the realm is asleep: its
clock keeps running and nothing in it does, which is what makes it cheap for a mod to register five
realms nobody is standing in. (2026-09-19, and see docs/roadmap.md "How much of the world is running")

### `attach`

*server/realm.gd*

GDScript: `attach() -> void`

Built after the realm is in place rather than inside _init, because the creatures reach back through
the server for the world they are standing in - and during _init the server does not yet know this
realm exists, so it would hand them somebody else's.

**See also:** `config_for`

### `is_awake`

*server/realm.gd*

GDScript: `is_awake() -> bool`

Whether anything in this realm should be run this tick. A claim on a chunk (keeping a machine going
after its owner leaves) will wake a realm too, which is why this asks about the simulated set rather
than counting players.

### `is_overworld`

*server/realm.gd*

GDScript: `is_overworld() -> bool`

Whether this is the world a server has always had. Kept as a question rather than a comparison
scattered about, because "" meaning the overworld is a compatibility decision and not an obvious one.

### `block_state`

*server/realm.gd*

GDScript: `block_state(pos: Vector3i) -> int`

The block state (its rotation, its stage, whatever the block means by it) at a position in *this*
world. On the realm rather than the server because a position alone does not say which world.

**See also:** `chunk_coord_at`, `index`

### `set_storage`

*server/realm.gd*

GDScript: `set_storage(world_dir: String) -> void`

Decides where this realm keeps its chunks, under the world's folder, and makes the folder.

The overworld keeps `<world>/chunks`, which is the folder every save already has; every other realm
gets `<world>/realms/<id>/chunks` beside it. That is the whole of why the overworld's id is "": a
world written before realms existed is still a valid world afterwards, with no migration.

**See also:** `is_overworld`

### `chunk_path`

*server/realm.gd*

GDScript: `chunk_path(coord: Vector2i) -> String`

`<save dir>/chunks/x_z.json`.

### `shape_lut`

*shared/block_registry.gd*

GDScript: `shape_lut := PackedByteArray()  (property)`

Which shape each block fills its cell with (Shape); FULL for almost everything.

### `hazard_lut`

*shared/block_registry.gd*

GDScript: `hazard_lut := PackedByteArray()  (property)`

Blocks mobs never path into or onto (e.g. lava, spikes). Server-side only.

### `register`

*shared/block_registry.gd*

GDScript: `register(def: Dictionary, replace := false) -> int`

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

### `facing_from_yaw`

*shared/block_registry.gd*

GDScript: `static facing_from_yaw(yaw: float) -> int`

JavaScript: `api.facingFromYaw(yaw)`

Facing (0-3) for a horizontally oriented block placed by a player looking along `yaw`: the block's
front (+Z in model space) turns toward the player.

**See also:** `block`

### `facing_direction`

*shared/block_registry.gd*

GDScript: `static facing_direction(facing: int) -> Vector3i`

JavaScript: `api.facingDirection(facing)`

Direction the front of a block with this facing points to.

### `id_of`

*shared/block_registry.gd*

GDScript: `id_of(block_name: String) -> int`

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid`

*shared/block_registry.gd*

GDScript: `is_valid(id: int) -> bool`

Whether anything is registered under this id.

### `display_name`

*shared/block_registry.gd*

GDScript: `display_name(id: int) -> String`

The name to show a player, or "?" for an id nothing registered. Display names are safe to change;
ids are not, because saves are written by name and ids shift whenever anything is added.

### `expand_textures`

*shared/block_registry.gd*

GDScript: `static expand_textures(value) -> Array`

A mod's `textures` normalised to one asset name per face, always six, in face order.

A mod may write one name for every face, `{all, side, top, bottom}`, or all six. Use this rather
than reading the value a mod wrote - three of those four shapes are not an Array, and code that
assumes the sixth-element form gets a block with no texture rather than an error.

### `to_network`

*shared/block_registry.gd*

GDScript: `to_network() -> Array`

The block table as the client receives it, trimmed to `NETWORK_FIELDS`. Sent once on joining.

### `load_network`

*shared/block_registry.gd*

GDScript: `load_network(data) -> bool`

Rebuilds this (fresh) registry from server data. Returns false if the data is malformed.

### `boxes_of`

*shared/block_shapes.gd*

GDScript: `static boxes_of(block: int, shapes: PackedByteArray) -> Array`

The boxes a block fills, or the whole cell when it has no shape of its own.

### `overlaps`

*shared/block_shapes.gd*

GDScript: `static overlaps(position: Vector3, half_width: float, height: float, world, solid: PackedByteArray, shapes: PackedByteArray) -> bool`

True when the box at `position` overlaps any solid block.

**See also:** `boxes_of`, `get_block`

### `states`

*shared/chunk.gd*

GDScript: `states := {}  (property)`

Sparse block states: local index -> state (1..255). Missing means 0.

### `dirty`

*shared/chunk.gd*

GDScript: `dirty := false  (property)`

Server only: modified since last save.

### `generated_data`

*shared/chunk.gd*

GDScript: `generated_data := {}  (property)`

Server only: block data written by world generation (structure chests, spawners): Vector3i -> Dictionary.

### `contains`

*shared/chunk.gd*

GDScript: `static contains(blocks: PackedByteArray, id: int) -> bool`

True if any cell holds `id`. Uses a native byte search, then confirms the id at cell boundaries.

### `encode_states`

*shared/chunk.gd*

GDScript: `encode_states() -> PackedInt32Array`

[index, state, index, state, ...] for the network.

### `decode_blocks`

*shared/chunk.gd*

GDScript: `static decode_blocks(payload: PackedByteArray) -> PackedByteArray`

Returns an empty array if the payload is malformed.

### `content_id`

*shared/creations.gd*

GDScript: `static content_id(kind: String, category: String, payload: PackedByteArray) -> String`

The id for a creation's content.

**See also:** `finish`, `start`

### `make`

*shared/creations.gd*

GDScript: `static make(kind: String, category: String, payload: PackedByteArray, name: String, author := "", author_name := "", extra := {}) -> Dictionary`

Builds a manifest for new content (the id comes from the payload).

**See also:** `content_id`, `finish`, `key_id`, `sign`, `start`

### `validate`

*shared/creations.gd*

GDScript: `static validate(manifest, payload: PackedByteArray) -> Dictionary`

Checks a manifest and its payload. Returns {ok, error, manifest (cleaned), info} where info carries
what was measured (triangles, texture sizes, box count).

**See also:** `check_files`, `check_manifest`, `check_references`, `check_scripts`, `check_structures`, `check_unused_files`

### `measure_model`

*shared/creations.gd*

GDScript: `static measure_model(bytes: PackedByteArray) -> Dictionary`

Triangles and the largest texture in a GLB, or {error}.

### `to_cosmetic`

*shared/creations.gd*

GDScript: `static to_cosmetic(manifest: Dictionary, payload: PackedByteArray) -> Dictionary`

The cosmetic definition that draws a creation. `asset` is the texture or model asset name clients load
(by default the id itself).

**See also:** `asset_name`

### `cast`

*shared/voxel_raycast.gd*

GDScript: `static cast(world, targetable: PackedByteArray, origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary`

`targetable` is BlockRegistry.targetable_lut. Returns {hit, position, normal, block}.

**See also:** `get_block`


## Items, crafting and recipes

### `station`

*client/crafting_screen.gd*

GDScript: `station := {}  (property)`

{name ("" = by hand), title, position}

### `stock`

*client/crafting_screen.gd*

GDScript: `stock := {}  (property)`

Items the station can draw from nearby chests: {item id: count}.

### `processes`

*client/crafting_screen.gd*

GDScript: `processes := {}  (property)`

Smelting and other processes for lookups: {kind: {input id: {output, count, seconds}}}.

### `stations`

*client/crafting_screen.gd*

GDScript: `stations := {}  (property)`

Every station's titles, tiers and upgrades (from the server) to explain recipe requirements.

### `icons`

*client/crafting_screen.gd*

GDScript: `icons  (property)`

ItemIcons (composed icons for parts and built tools); set by the client.

### `session`

*client/crafting_screen.gd*

GDScript: `session := {}  (property)`

The shared state at this station: {players, tray, jobs, project, owner, speedup}.

### `known`

*client/crafting_screen.gd*

GDScript: `known := {}  (property)`

Recipe ids this player has discovered, and whether the server uses discovery at all.

### `minigames`

*client/crafting_screen.gd*

GDScript: `minigames := {}  (property)`

Crafting minigames by name (from the server) and the player's relaxed-timing choice.

### `assembly`

*client/crafting_screen.gd*

GDScript: `assembly := Assembly.new()  (property)`

Materials, parts and tools built from parts (shared definitions from the server).

### `set_experiment_result`

*client/crafting_screen.gd*

GDScript: `set_experiment_result(result: Dictionary) -> void`

Shows what an experiment did: the discovered or known result, or a hint.

**See also:** `area_cells`, `at_station`, `box_mesh`, `count`, `count_of`, `craftable_times`

### `open`

*client/crafting_screen.gd*

GDScript: `open(station_info: Dictionary, station_stock: Dictionary) -> void`

Opens (or refreshes) the book for a station and its stock.

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `show_lookup`

*client/crafting_screen.gd*

GDScript: `show_lookup(item: int, mode: String) -> void`

Filters the book to recipes making (`mode` "make") or using ("use") an item; item 0 clears.

**See also:** `at_station`, `count_of`, `craftable_times`, `in_category`, `is_blocked`, `is_builtin`

### `craftable_times`

*client/crafting_screen.gd*

GDScript: `craftable_times(index: int) -> int`

How many times a recipe could be crafted now (999 in creative).

**See also:** `at_station`, `count_of`, `crafting_stock`, `get_block_v`, `get_eye_position`, `have`

### `have_all`

*client/crafting_screen.gd*

GDScript: `have_all(index: int) -> bool`

Whether you hold every ingredient (ignoring where the recipe must be crafted).

**See also:** `have`

### `requirement_text`

*client/crafting_screen.gd*

GDScript: `requirement_text(r: Dictionary) -> String`

What a recipe needs, in words: "Needs a Sturdy Workbench with Metalwork (an Anvil nearby)".

**See also:** `station_title`

### `set_session`

*client/crafting_screen.gd*

GDScript: `set_session(view: Dictionary) -> void`

Applies a station session update; rebuilds the co-op panel only when more than progress changed.

**See also:** `at_station`, `count_of`, `craftable_times`, `have`, `heading`, `icon_of`

### `station_title`

*client/crafting_screen.gd*

GDScript: `static station_title(station_name: String) -> String`

Short text for a station name ("crafting_table" -> "Crafting Table").

**See also:** `count`

### `stat_preview`

*client/crafting_screen.gd*

GDScript: `stat_preview(item: int) -> PackedStringArray`

BBCode lines describing an item and how it compares to what you hold (tools, weapons) or wear (armor).

**See also:** `equipment_index`, `get_def`, `selected_item`

### `icons`

*client/inventory_screen.gd*

GDScript: `icons  (property)`

ItemIcons (composed icons for stacks built from parts); set by the client.

### `container`

*client/inventory_screen.gd*

GDScript: `container := {}  (property)`

The open container ({} when none): {title, size, groups, bars, slots, data, progress}.

### `set_container`

*client/inventory_screen.gd*

GDScript: `set_container(view: Dictionary) -> void`

Shows a container above the inventory (or hides it with {}).

**See also:** `refresh`

### `update_container`

*client/inventory_screen.gd*

GDScript: `update_container(view: Dictionary) -> void`

Applies {slots, data, progress} for the open container.

**See also:** `merge`, `refresh`

### `build_equipment`

*client/inventory_screen.gd*

GDScript: `build_equipment(slot_defs: Array) -> void`

Builds one slot per equipment slot the server defined (called once content is known).

### `partner_event`

*client/minigame_screen.gd*

GDScript: `partner_event(action: String, t: float, arg: int) -> void`

The partner's input (team games).

**See also:** `rate_strike`

### `assemblies`

*server/assemblies.gd*

GDScript: `assemblies := {}  (property)`

id -> {realm, origin (Vector3i the cells are relative to), offset (Vector3), cells, riders}

### `problem`

*server/assemblies.gd*

GDScript: `problem := ""  (property)`

Why the last lift or settle was refused, in words a player can be shown.

### `lift`

*server/assemblies.gd*

GDScript: `lift(realm_id: String, positions: Array, options := {}) -> int`

Takes a set of world positions out of the world and holds them as one moving thing. Returns the
assembly id, or 0 with the reason in `problem`.

**See also:** `block_state`, `get_block_data`, `get_block_v`, `set_block_authoritative`, `tell_assembly`

### `move`

*server/assemblies.gd*

GDScript: `move(id: int, by: Vector3) -> bool`

Moves it, and carries whoever is standing on it. `by` is in blocks and may be fractional - that is
the whole point of being off the grid.

**See also:** `realm_of`, `teleport`, `tell_assembly_moved`

### `settle`

*server/assemblies.gd*

GDScript: `settle(id: int) -> bool`

Puts it back into the world at wherever it has got to, and stops being an assembly.

Refused if anything solid is in the way. Forcing it would mean deleting whatever was there, and an
engine that destroys what somebody built because a machine arrived is not one to build with.

**See also:** `describe`, `drive_changed`, `get_block_v`, `node_of`, `qualified`, `reachable`

### `cancel`

*server/assemblies.gd*

GDScript: `cancel(id: int) -> bool`

JavaScript: `api.cancel(id)`

Puts an assembly back exactly where it was lifted from, for a mod that wants to give up cleanly.

**See also:** `broadcast_player_event`, `cancel_task`, `settle`

### `config_of`

*server/charging.gd*

GDScript: `config_of(item: int) -> Dictionary`

Whether this item is held rather than clicked.

**See also:** `config`, `get_def`

### `start`

*server/charging.gd*

GDScript: `start(p, item: int) -> bool`

Begins a draw. Returns false when the item is not a charging one or a mod refused it.

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `release`

*server/charging.gd*

GDScript: `release(p) -> void`

Let go. Fires item_released when it was held long enough, and tells everyone the draw is over either way.

**See also:** `broadcast_player_event`, `config_of`, `look_direction`

### `cancel`

*server/charging.gd*

GDScript: `cancel(p) -> void`

JavaScript: `api.cancel(p)`

Drops the draw without firing: the item left their hand, or they died holding it.

**See also:** `broadcast_player_event`, `cancel_task`, `settle`

### `update`

*server/charging.gd*

GDScript: `update(p) -> void`

Called every tick: a draw belongs to the item that started it, so swapping slots or losing the item
lets it go rather than leaving a player drawing something they are no longer holding.

### `experiment`

*server/experiments.gd*

GDScript: `experiment(p, grid: Array) -> Dictionary`

`grid`: 9 item ids (0 = empty), row by row. Returns {status: "discovered" | "known" | "blueprint" |
"close" | "nothing" | "invalid", recipe (index or -1), hint}.

**See also:** `count_of`, `get_block_v`, `get_eye_position`, `knows_recipe`, `learn_recipe`, `play_sound_to`

### `kinds`

*server/modifiers.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, max_level, per_level, applies_to, owner}

### `allows`

*server/modifiers.gd*

GDScript: `allows(modifier_name: String, item_name: String) -> bool`

Whether this mark may go on this item.

### `level_of`

*server/modifiers.gd*

GDScript: `level_of(item_data: Dictionary, modifier_name: String) -> int`

JavaScript: `api.levelOf(itemData, modifierName)`

The level of a mark on an item, or 0.

**See also:** `level_for`, `qualified`, `value_of`

### `marks_on`

*server/modifiers.gd*

GDScript: `marks_on(item_data: Dictionary) -> Array`

Every mark on an item, as [{name, level, display_name}].

### `apply`

*server/modifiers.gd*

GDScript: `apply(item_data: Dictionary, item_name: String, modifier_name: String, level: int) -> Dictionary`

Puts a mark on an item, returning the new item data. `level` 0 takes it off again.

Returns the data unchanged if the mark does not exist or does not belong on that item, so a mod
calling this with something silly gets an item back rather than a broken one.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `time_override`

*server/skill_crafting.gd*

GDScript: `time_override := -1.0  (property)`

Tests set this to control the clock (seconds); < 0 uses real time.

### `start`

*server/skill_crafting.gd*

GDScript: `start(p, product: Dictionary, assist := false, with_partner := false) -> int`

Starts crafting by hand. product: {recipe: index} or {assembly: name, slots: [backpack slot per
assembly slot]}. Returns the game id, or 0 if it could not start.

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `invites_at`

*server/skill_crafting.gd*

GDScript: `invites_at(pos: Vector3i) -> Array`

Invitations waiting at a station: [{id, by_name, title}].

### `join`

*server/skill_crafting.gd*

GDScript: `join(p, game_id: int) -> bool`

Joins a waiting team game as the bellows.

### `start_alone`

*server/skill_crafting.gd*

GDScript: `start_alone(p) -> void`

Starts a waiting team game without a partner.

**See also:** `game_of`, `mark`, `now`, `role_of`

### `input`

*server/skill_crafting.gd*

GDScript: `input(p, action: String, t: float, arg := 0) -> void`

An input from a player: "strike", "hold" (arg 1 pressed / 0 released), "key" (arg = direction
index) or "quit". `t` is the game time the client saw.

**See also:** `complete`, `finish`, `game_of`, `now`, `peer_rtt`, `role_of`

### `finish`

*server/skill_crafting.gd*

GDScript: `finish(g: Dictionary) -> void`

Ends the game: scores it, gives the item with its quality and tells the players.

**See also:** `apply_quality`, `give_crafted`, `mark`, `quality_for`, `score`, `time_limit`

### `apply_quality`

*server/skill_crafting.gd*

GDScript: `apply_quality(item: int, data: Dictionary, quality: Dictionary, names: Array) -> Dictionary`

Quality raises durability, tool speed, weapon damage and armor, renames the item and credits the
makers. Standard leaves the item unchanged.

**See also:** `get_def`, `max_durability`, `tool_of`, `weapon_of`

### `coop`

*server/station_sessions.gd*

GDScript: `coop(pos: Vector3i) -> Dictionary`

The co-op state of a station: {owner, owner_name, owner_team, tray: [...], jobs: [...], project: {}}.

**See also:** `get_block_data`, `set_block_data`

### `claim`

*server/station_sessions.gd*

GDScript: `claim(pos: Vector3i, p) -> void`

Records who placed a station (they own its tray).

**See also:** `coop`

### `speedup`

*server/station_sessions.gd*

GDScript: `static speedup(helpers: int, station_speed: float) -> float`

How much faster timed crafts go with `helpers` players present.

### `deposit`

*server/station_sessions.gd*

GDScript: `deposit(p, pos: Vector3i, slot: int) -> bool`

Moves the stack in a backpack slot into the tray. Returns true if anything moved.

**See also:** `clear_slot`, `coop`, `max_stack`, `sync_inventory`

### `usable_tray`

*server/station_sessions.gd*

GDScript: `usable_tray(p, pos: Vector3i) -> Dictionary`

Tray items this player may use: {item id: count}.

**See also:** `coop`, `may_take`

### `consume_tray`

*server/station_sessions.gd*

GDScript: `consume_tray(p, pos: Vector3i, item: int, count: int) -> int`

Removes up to `count` of an item from the tray stacks the player may use. Returns how many.

**See also:** `coop`, `may_take`

### `contribute`

*server/station_sessions.gd*

GDScript: `contribute(p, pos: Vector3i) -> int`

Delivers whatever the project still needs from the player's inventory. Returns items delivered.

**See also:** `broadcast_chat`, `coop`, `count_of`, `drop_item`, `index_of`, `play_effect`

### `view`

*server/station_sessions.gd*

GDScript: `view(pos: Vector3i) -> Dictionary`

What session members see: players and the recipes they look at, tray, jobs with speed, project.

**See also:** `coop`, `index_of`, `invites_at`, `members`, `merge`, `project_fraction`

### `station_of_block`

*server/stations.gd*

GDScript: `station_of_block(block: int) -> String`

Station name of a block: from a registered station's tiers or multiblock core, or the block's own
`station` key. "" when the block is not a station.

### `evaluate`

*server/stations.gd*

GDScript: `evaluate(pos: Vector3i) -> Dictionary`

Everything about the station at a position: {name, title, tier, tier_title, features, speed,
quality, pull_radius, hints, detected: [...], available: [...], next: {...}, structure: {...}}.

**See also:** `apply_condition`, `damage`, `damage_player`, `get_block_v`, `heal`, `station_of_block`

### `usable`

*server/stations.gd*

GDScript: `static usable(info: Dictionary) -> bool`

Whether the station is usable: multiblock stations must be complete.

### `structure_missing`

*server/stations.gd*

GDScript: `structure_missing(core_pos: Vector3i, m: Dictionary) -> Array`

The best rotation's missing blocks as [[position, block id], ...] (empty when the structure is
complete). The core is the block at "C".

**See also:** `close`, `get_block_loaded`, `open`

### `upgrade`

*server/stations.gd*

GDScript: `upgrade(p, pos: Vector3i) -> bool`

Uses the next tier's kit from the player's inventory on the station. Returns true if it upgraded.

**See also:** `evaluate`, `get_block_state`, `play_effect`, `play_sound_at`, `realm_of`, `set_block_authoritative`

### `to_network`

*server/stations.gd*

GDScript: `to_network() -> Dictionary`

For clients: every station's titles, tiers, upgrades and structure so recipe requirements can be
explained anywhere.

### `part_data`

*shared/assembly.gd*

GDScript: `part_data(part_name: String, material_name: String) -> Dictionary`

Item data for a part made of a material.

### `build`

*shared/assembly.gd*

GDScript: `build(assembly_name: String, chosen: Dictionary) -> Dictionary`

The finished tool's item data from {slot name: material name}, or {} if something is invalid.

**See also:** `area_cells`, `body_font`, `box`, `box_mesh`, `check_icon`, `close_icon`

### `creative`

*shared/inventory.gd*

GDScript: `creative := false  (property)`

Creative players place without consuming and do not collect drops.

### `equipment_slots`

*shared/inventory.gd*

GDScript: `equipment_slots: PackedStringArray = []  (property)`

Names of the equipment slots after the backpack (index SIZE + i).

### `total`

*shared/inventory.gd*

GDScript: `total() -> int`

Total slots including equipment.

### `selected_block`

*shared/inventory.gd*

GDScript: `selected_block() -> int`

The selected item if it is a block, else 0.

**See also:** `selected_item`

### `consume_selected`

*shared/inventory.gd*

GDScript: `consume_selected() -> void`

Consumes one item from the selected slot (no-op in creative).

**See also:** `clear_slot`

### `add`

*shared/inventory.gd*

GDScript: `add(id: int, count: int, max_stack := MAX_STACK, item_data := {}) -> int`

Adds to matching stacks first, then to empty slots (hotbar before the main inventory). Items with
data only merge with stacks carrying identical data. Returns how many items did not fit.

### `space_for`

*shared/inventory.gd*

GDScript: `space_for(id: int, max_stack := MAX_STACK, item_data := {}) -> int`

How many of an item would fit (without changing anything).

**See also:** `available`

### `remove`

*shared/inventory.gd*

GDScript: `remove(id: int, count: int) -> bool`

Removes `count` items of `id` if available (any data). Returns false (and removes nothing) otherwise.

### `click`

*shared/inventory.gd*

GDScript: `click(slot: int, button: int, shift: bool, max_stack_of: Callable, accepts := Callable()) -> bool`

Inventory screen click on `slot` with the mouse `button` (1 = left, 2 = right):
left picks up / puts down / merges / swaps whole stacks, right picks up half or puts down one.
`shift` moves the stack between the hotbar and the main inventory, or into and out of equipment.
`max_stack_of(id)` gives stack limits; `accepts(slot_index, id)` says whether an equipment slot
takes an item (backpack slots take anything). Returns true if anything changed.

**See also:** `accepts`, `at_key`, `changed`, `clear_slot`, `get_def`, `get_item`

### `to_packed`

*shared/inventory.gd*

GDScript: `to_packed() -> PackedInt32Array`

[ids..., counts..., cursor id, cursor count] for every slot including equipment.

### `data_to_network`

*shared/inventory.gd*

GDScript: `data_to_network() -> Dictionary`

Item data for the network: {slot index: Dictionary} for slots that have data, cursor as -1.

**See also:** `to_packed`, `total`

### `load_packed`

*shared/inventory.gd*

GDScript: `load_packed(packed: PackedInt32Array) -> bool`

Reads what to_packed() wrote: ids then counts, optionally followed by the held cursor stack. The
length has to match this inventory exactly, which is what makes a mismatch a refusal rather than a
silently half-filled backpack.

**See also:** `total`

### `load_network_data`

*shared/inventory.gd*

GDScript: `load_network_data(network: Dictionary) -> void`

Client side: applies data from data_to_network, rejecting anything malformed or oversized.

**See also:** `total`

### `slots`

*shared/item_registry.gd*

GDScript: `slots: Array[Dictionary] = []  (property)`

Equipment slots in inventory order: {name, display_name}.

### `is_block_item`

*shared/item_registry.gd*

GDScript: `static is_block_item(id: int) -> bool`

Whether an id is a block rather than a registered item. Every block is also an item, and block ids
run below `FIRST_ITEM` while item ids start there.

**See also:** `attack_damage`, `max_stack`, `place`, `sweep`, `worn`

### `register`

*shared/item_registry.gd*

GDScript: `register(def: Dictionary, replace := false) -> int`

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

### `register_slot`

*shared/item_registry.gd*

GDScript: `register_slot(def: Dictionary) -> int`

def: name, display_name. Items whose equip_slot matches go in it (the offhand takes anything).

**See also:** `slot_index`

### `slot_index`

*shared/item_registry.gd*

GDScript: `slot_index(slot_name: String) -> int`

Where a named equipment slot sits in `slots`, or -1 if there is no such slot.

### `slot_names`

*shared/item_registry.gd*

GDScript: `slot_names() -> PackedStringArray`

Every equipment slot's name, in the order they were registered.

### `register_stat`

*shared/item_registry.gd*

GDScript: `register_stat(stat_name: String, base: float) -> void`

JavaScript: `api.registerStat(statName, base)`

Declares a stat and the value it has before any modifier applies. First registration wins, so a mod
cannot change the base another mod set.

**See also:** `can_see_target`, `health_fraction`

### `fits_slot`

*shared/item_registry.gd*

GDScript: `fits_slot(id: int, slot_name: String) -> bool`

Whether an item may be placed in the named equipment slot. The offhand takes anything.

**See also:** `get_def`

### `id_of`

*shared/item_registry.gd*

GDScript: `id_of(item_name: String) -> int`

Resolves block or item names.

### `is_valid`

*shared/item_registry.gd*

GDScript: `is_valid(id: int) -> bool`

Whether anything is registered under this id, block or item.

### `get_def`

*shared/item_registry.gd*

GDScript: `get_def(id: int) -> Dictionary`

An item's definition, or `{}` for a block id or an id nothing registered. Blocks keep their
definitions in `BlockRegistry`, so this answers `{}` for them rather than failing.

### `name_of`

*shared/item_registry.gd*

GDScript: `name_of(id: int) -> String`

The internal name (`mod:thing`), for blocks and items alike. This is what saves are written with,
because ids shift whenever anything is added and names do not.

### `display_name`

*shared/item_registry.gd*

GDScript: `display_name(id: int) -> String`

The name to show a player. Safe to change at any time, unlike the internal name.

### `max_stack`

*shared/item_registry.gd*

GDScript: `max_stack(id: int) -> int`

How many fit in one slot. Blocks are always 64; an item says so in its definition, and anything with
durability normally says 1.

**See also:** `get_def`

### `max_durability`

*shared/item_registry.gd*

GDScript: `max_durability(id: int, item_data := {}) -> int`

Item data may override `durability`, `tool` and `weapon` per stack (tools built from parts).

**See also:** `get_def`

### `tool_of`

*shared/item_registry.gd*

GDScript: `tool_of(id: int, item_data := {}) -> Dictionary`

The tool stats in force for this particular stack: `{type, tier, speed}`, or `{}` if it is not a tool.

**Per-stack data wins over the definition**, which is what makes a tool built from parts possible -
two stacks of the same item can mine at different speeds. Read this rather than `get_def(id).tool`,
or a part-built tool silently reports the stats of the plain one.

**See also:** `get_def`

### `weapon_of`

*shared/item_registry.gd*

GDScript: `weapon_of(id: int, item_data := {}) -> Dictionary`

The weapon stats in force for this particular stack: `{damage, cooldown, reach, crit_chance,
knockback, sweep}`, or `{}` if it is not a weapon. Per-stack data wins, as with `tool_of`.

**See also:** `get_def`, `item`

### `attack_damage`

*shared/item_registry.gd*

GDScript: `attack_damage(id: int, item_data := {}) -> float`

Damage dealt when attacking while holding this item (bare hand and blocks: 1).

**See also:** `heal`, `weapon_of`

### `clean_food`

*shared/item_registry.gd*

GDScript: `static clean_food(value) -> Dictionary`

food: {hunger (points, 20 = full), saturation, eat_time (seconds holding use), always (edible when
full), heal (health), remainder (item left over, e.g. a bottle), color (crumbs), style ("plate":
served on a plate, "hand": eaten from the hand, "drink": swigged from the item), sound (played per
bite or gulp; default engine:munch or engine:gulp), effects: [{stat, amount, op, seconds, chance, message}]}.

### `is_usable`

*shared/item_registry.gd*

GDScript: `is_usable(id: int) -> bool`

Whether right-clicking with it fires `item_use`.

**See also:** `get_def`

### `icon_of`

*shared/item_registry.gd*

GDScript: `icon_of(id: int) -> String`

Texture asset for inventory icons.

**See also:** `get_def`

### `to_network`

*shared/item_registry.gd*

GDScript: `to_network() -> Array`

The item table as the client receives it. Sent once on joining, so the client can name and draw
everything without the server being asked again.

### `load_network`

*shared/item_registry.gd*

GDScript: `load_network(data, slot_data = null, stat_data = null) -> bool`

Rebuilds the table on the client from what the server sent. False when the data is not the shape we
expect, which is refused at the door rather than half-loaded.

### `visuals`

*shared/item_registry.gd*

GDScript: `visuals(id: int, item_data := {}) -> Dictionary`

The look of one stack: {glow, trail, effects} from the definition, overridden by item data.

**See also:** `clean_effects`, `clean_glow`, `clean_trail`, `get_def`, `merge`

### `clean_glow`

*shared/item_registry.gd*

GDScript: `static clean_glow(value) -> Dictionary`

A mod's `glow` normalised: `{color, energy 0-8, light 0-16}`, or `{}` if there is none.

Use this rather than reading the dictionary a mod wrote. The clamps are the point - an item asking
for a light level of 400 is a mod bug, not a reason for the world to light up.

### `clean_trail`

*shared/item_registry.gd*

GDScript: `static clean_trail(value) -> Dictionary`

A mod's `trail` normalised: `{color, width 0.1-1, seconds 0.05-1}`, or `{}` if there is none.

### `clean_effects`

*shared/item_registry.gd*

GDScript: `static clean_effects(value) -> Dictionary`

A mod's `effects` normalised to the hooks the engine actually plays (`EFFECT_HOOKS`), with anything
else dropped. An effect named under a hook nobody fires is a quiet nothing, so this is where it goes.

### `clean_modifiers`

*shared/item_registry.gd*

GDScript: `static clean_modifiers(list) -> Array`

A mod's stat modifiers normalised: `[{stat, amount, op}]`, `op` either "add" or "multiply", capped at
sixteen. Anything without a `stat` name is dropped rather than carried as a half-modifier.

### `time_limit`

*shared/minigame.gd*

GDScript: `static time_limit(g: Dictionary) -> float`

Seconds after which the game ends even without more input.

**See also:** `speed`, `window`

### `complete`

*shared/minigame.gd*

GDScript: `static complete(g: Dictionary, t: float) -> bool`

Whether the game has everything it needs (all strikes, prompts or the full duration).

**See also:** `sequence_progress`

### `marker`

*shared/minigame.gd*

GDScript: `static marker(g: Dictionary, t: float) -> float`

Marker position 0..1 at time t (sweeping back and forth, faster as the work cools).

**See also:** `speed`

### `zone_width`

*shared/minigame.gd*

GDScript: `static zone_width(g: Dictionary, i: int, t := -1.0) -> float`

Zone width for strike i (narrower each strike; the station's quality bonus widens it).

**See also:** `heat`

### `heat`

*shared/minigame.gd*

GDScript: `static heat(g: Dictionary, t: float) -> float`

Solo with `cool`: 1 falling to 0. Team: simulated from the bellows' presses and releases.

### `rate_strike`

*shared/minigame.gd*

GDScript: `static rate_strike(g: Dictionary, i: int, t: float) -> Dictionary`

{grade: "perfect" | "good" | "miss" | "burnt", score, synced} for strike i at time t.

**See also:** `heat`, `zone_center`, `zone_width`

### `band_center`

*shared/minigame.gd*

GDScript: `static band_center(g: Dictionary, t: float) -> float`

The band's center at time t (drifts slowly).

### `gauge`

*shared/minigame.gd*

GDScript: `static gauge(g: Dictionary, t: float) -> float`

Gauge value at time t: rises while held, falls otherwise.

**See also:** `heat`

### `sequence_progress`

*shared/minigame.gd*

GDScript: `static sequence_progress(g: Dictionary, t := INF) -> Dictionary`

{index (current prompt), hits, started (when the current prompt appeared)} replaying key presses.

**See also:** `prompt`, `window`

### `score`

*shared/minigame.gd*

GDScript: `static score(g: Dictionary, t: float) -> float`

0..1 (team timing can reach a little over 1 with sync).

**See also:** `hold_fraction`, `is_alive`, `order_of`, `post_of`, `rate_strike`

### `break_time`

*shared/mining.gd*

GDScript: `static break_time(block: Dictionary, tool: Dictionary, mining_speed := 1.0) -> float`

Seconds to break `block` (a BlockRegistry def) holding `tool` ({type, tier, speed} or {}),
with the player's `mining_speed` stat. 0 = instant.

**See also:** `can_harvest`

### `can_harvest`

*shared/mining.gd*

GDScript: `static can_harvest(block: Dictionary, tool: Dictionary) -> bool`

True if breaking the block with this tool yields its drops.

### `stage`

*shared/mining.gd*

GDScript: `static stage(progress: float) -> int`

Crack animation stage 0-9 for progress 0-1.

### `register_category`

*shared/recipe_registry.gd*

GDScript: `register_category(def: Dictionary) -> bool`

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

### `has_category`

*shared/recipe_registry.gd*

GDScript: `has_category(cat_name: String) -> bool`

Whether a tab of this name is already declared, by the engine or by a mod that loaded earlier.

### `add`

*shared/recipe_registry.gd*

GDScript: `add(def: Dictionary, items = null) -> int`

Adds a recipe. `items` (an ItemRegistry) picks a category when none is given. Returns its index.

### `begin_reload`

*shared/recipe_registry.gd*

GDScript: `begin_reload(owner: String) -> void`

Starts watching one mod's recipes so `end_reload` can tell which have gone.

Reloading cannot simply drop the owner's recipes and re-add them: a recipe is referred to by index
elsewhere, so they are marked removed instead and the indices stay put.

### `end_reload`

*shared/recipe_registry.gd*

GDScript: `end_reload() -> int`

Marks the owner's recipes that were not registered again as removed. Returns how many changed.

### `clear`

*shared/recipe_registry.gd*

GDScript: `clear() -> void`

Forgets every recipe (clients rebuild the book from a content update).

### `index_of`

*shared/recipe_registry.gd*

GDScript: `index_of(recipe_id: String) -> int`

Where a recipe sits in `recipes`, or -1. The index is what everything else refers to a recipe by,
because it survives a reload while the array position of a rebuilt list would not.

### `producing`

*shared/recipe_registry.gd*

GDScript: `producing(item: int) -> Array`

Recipes whose output is `item`.

### `using`

*shared/recipe_registry.gd*

GDScript: `using(item: int) -> Array`

Recipes that use `item` as an ingredient.

### `guess_category`

*shared/recipe_registry.gd*

GDScript: `static guess_category(output: int, items) -> String`

Which crafting tab a recipe belongs in when the mod did not say: worked out from what it makes -
blocks, armor, tools, weapons, food, else materials.

**See also:** `get_def`

### `to_network`

*shared/recipe_registry.gd*

GDScript: `to_network() -> Dictionary`

The recipe book as the client receives it.

### `load_network`

*shared/recipe_registry.gd*

GDScript: `load_network(data) -> bool`

Rebuilds the book on the client. False when the data is not the shape we expect.


## Creatures and AI

### `setup`

*client/entity_view.gd*

GDScript: `setup(id: int, def: Dictionary, parts: Array, sprite: Texture2D, pos: Vector3, yaw: float) -> void`

`parts`: [{name, mesh, transform}] from ModelLibrary.load_parts, or empty. `sprite`: texture for
items, projectiles and model-less entities.

### `update_plate`

*client/entity_view.gd*

GDScript: `update_plate(camera_position: Vector3) -> void`

Where the camera is, so the plate can fade with distance. Set by the client each frame.

**See also:** `update_for_camera`

### `windup`

*client/entity_view.gd*

GDScript: `windup() -> void`

The mob is about to attack: arms rise and it glows, so players can react.

### `despawn`

*client/entity_view.gd*

GDScript: `despawn() -> void`

Server despawn: plays out a running death or pickup animation first.

**See also:** `category_of`

### `aabb`

*client/entity_view.gd*

GDScript: `aabb() -> AABB`

Hit box for client-side targeting.

### `custom_behaviors`

*server/ai/mob_ai.gd*

GDScript: `custom_behaviors := {}  (property)`

name -> {score: Callable(brain) -> float, update: Callable(brain, delta), stop: Callable(brain)}

### `edge_distance`

*server/ai/mob_ai.gd*

GDScript: `edge_distance(e, t) -> float`

Horizontal gap between the mob's box and the target's box (0 when touching), plus any height gap.

**See also:** `aabb`, `aabb_of`

### `enemies_near`

*server/ai/mob_ai.gd*

GDScript: `enemies_near(brain: MobBrain, center: Vector3, radius: float) -> Array`

Enemies (survival players and mobs of enemy groups) within `radius`.

**See also:** `brains_near`, `is_alive`, `is_enemy`

### `surround_slot`

*server/ai/mob_ai.gd*

GDScript: `surround_slot(brain: MobBrain, t, ring: float) -> Vector3`

Melee mobs fighting the same target spread around it instead of piling up on one side.
Returns this brain's slot position, or Vector3.INF when it is the only attacker.

**See also:** `key_of`, `position_of`

### `can_reach`

*server/ai/mob_attacks.gd*

GDScript: `static can_reach(brain, target) -> bool`

A melee blow needs an opening: some line from the mob to the target not blocked by blocks (no hits
through walls, floors or closed doors).

**See also:** `chest_of`, `eye_of`, `line_of_sight`, `position_of`

### `apply_condition`

*server/ai/mob_attacks.gd*

GDScript: `static apply_condition(server, victim, condition: Dictionary) -> void`

What an attack leaves behind on whoever it hit. Applied after the damage, so a condition that kills
does not race the blow that would have.

**See also:** `give`

### `target`

*server/ai/mob_brain.gd*

GDScript: `target = null  (property)`

Current enemy (a ServerPlayer or an entity) or null.

### `behavior`

*server/ai/mob_brain.gd*

GDScript: `behavior := "idle"  (property)`

Name of the running behavior.

### `phase`

*server/ai/mob_brain.gd*

GDScript: `phase := -1  (property)`

Index of the boss phase reached (-1 = none).

### `home`

*server/ai/mob_brain.gd*

GDScript: `home := Vector3.INF  (property)`

Where the mob returns to when leashed (Vector3.INF = roams freely).

### `tune`

*server/ai/mob_brain.gd*

GDScript: `tune(values: Dictionary) -> void`

Changes this mob's AI settings (any MobConfig key, including attacks and phases).

**See also:** `agent_for`, `sanitize`

### `alert`

*server/ai/mob_brain.gd*

GDScript: `alert(position: Vector3) -> void`

Makes the mob notice a position (walks there to investigate).

### `move_to`

*server/ai/mob_brain.gd*

GDScript: `move_to(goal: Vector3, speed := 1.0, radius := 0.8) -> void`

Walks toward a position (pathfinding as needed). Custom behaviors call this each think.

**See also:** `node_of`, `request_path`, `walkable_line`

### `at_path_end`

*server/ai/mob_brain.gd*

GDScript: `at_path_end() -> bool`

True when the goal cannot be reached and the mob stands at the end of the best partial path (or found no
way at all from where it stands): as close as it can get. Behaviors treat that like arriving instead of pushing against the obstacle.

### `resolve`

*server/ai/mob_config.gd*

GDScript: `static resolve(ai, def: Dictionary, resolve_entity: Callable) -> Dictionary`

Returns the resolved config. `ai` is a preset name, a Dictionary, or anything else (-> "wander").
`resolve_entity` maps entity type names to ids (for projectiles and summons).

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `condition_of`

*server/ai/mob_config.gd*

GDScript: `static condition_of(value) -> Dictionary`

{condition, seconds, level, chance} or {} - read here rather than where it is applied, so a malformed
one is a dull default at load instead of a surprise mid-fight.

Public because `fields.gd` needs exactly this reader: a field and a bite leave the same kind of thing
behind, and a second copy would drift from this one.

### `set_tables`

*server/ai/pathfinder.gd*

GDScript: `set_tables(solid_lut: PackedByteArray, liquid_lut: PackedByteArray, sight_blockers: PackedByteArray, hazards: PackedByteArray) -> void`

`sight_blockers`: 1 for blocks that stop line of sight; `hazards`: 1 for blocks mobs avoid.

### `find_path`

*server/ai/pathfinder.gd*

GDScript: `find_path(start: Vector3i, goal: Vector3i, radius: float, agent: PackedInt32Array, max_nodes := -1) -> Dictionary`

{status: Status, nodes: Array[Vector3i]} from start to the end node.

### `settle`

*server/ai/pathfinder.gd*

GDScript: `settle(position: Vector3, agent: PackedInt32Array) -> Vector3i`

Standable node at or near `position` (scans a few cells up and down).

**See also:** `describe`, `drive_changed`, `get_block_v`, `node_of`, `qualified`, `reachable`

### `feed`

*server/breeding.gd*

GDScript: `feed(p, e) -> bool`

A player right-clicked `e` holding `item`. Returns true if it was eaten.

**See also:** `clear_slot`, `config_of`, `is_alive`, `is_baby`, `is_food`, `play_effect`

### `update`

*server/breeding.gd*

GDScript: `update(delta: float) -> void`

Once a second: babies grow, love and cooldowns run out.

### `mate`

*server/breeding.gd*

GDScript: `mate(a, b) -> Object`

Spawns a baby between two parents and starts their cooldowns.

**See also:** `config_of`, `play_effect`, `spawn`

### `kinds`

*server/companions.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, behavior, owner}

### `order_of`

*server/companions.gd*

GDScript: `order_of(entity) -> String`

JavaScript: `api.orderOf(entity)`

What it is being told to do now. Everything defaults to following, which is what a creature that has
just been tamed should do without anybody saying so.

### `post_of`

*server/companions.gd*

GDScript: `post_of(entity) -> Vector3`

Where it was told to hold, for guard. Vector3.INF when it has no post.

### `give`

*server/companions.gd*

GDScript: `give(entity, order_name: String, options := {}) -> bool`

Tells it something. `options.at` is where, for orders that need a place; it defaults to where the
creature is standing, which is what "guard this spot" means when somebody says it out loud.

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `sync`

### `orders_for`

*server/companions.gd*

GDScript: `orders_for(entity) -> Array`

The orders this creature can be given: the engine's three, plus any a mod registered for its type.
A mod restricts them by handling `companion_orders`, which is cheaper than a registry of which
creature may be told what.

### `show`

*server/companions.gd*

GDScript: `show(player, entity) -> bool`

The panel. Drawn by the engine so every companion in every mod is told what to do the same way.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `heat`, `hold_fraction`

### `score`

*server/companions.gd*

GDScript: `score(brain) -> float`

Registered into the AI the way sit and follow-owner are. Guarding is holding a spot: it fights what
comes to it, and walks back when whatever it was fighting drew it away.

**See also:** `hold_fraction`, `is_alive`, `order_of`, `post_of`, `rate_strike`

### `on_changed`

*server/drives.gd*

GDScript: `on_changed(unit: String, handler: Callable) -> void`

Told when what a face is driven at changes: {realm, position, face, unit, value, jammed}.

### `set_source`

*server/drives.gd*

GDScript: `set_source(unit: String, node: Dictionary, value: float) -> void`

This face drives at `value` - a speed, and a sign for which way round. 0 stops driving.

**See also:** `get_block_v`, `key_name`, `node_key`, `reaching`, `record`

### `value_at`

*server/drives.gd*

GDScript: `value_at(unit: String, node: Dictionary) -> float`

What this face is being driven at. Zero when nothing drives it, and zero when the line is jammed -
a jammed line does not turn.

**See also:** `key_name`, `node_key`

### `jammed_at`

*server/drives.gd*

GDScript: `jammed_at(unit: String, node: Dictionary) -> bool`

Whether this face is on a line that two sources are fighting over.

**See also:** `key_name`, `node_key`

### `projectiles`

*server/entities.gd*

GDScript: `projectiles: Array = []  (property)`

Live projectiles (mobs watch these to dodge).

### `spawning`

*server/entities.gd*

GDScript: `spawning  (property)`

Natural spawning rules, category caps and despawning.

### `breeding`

*server/entities.gd*

GDScript: `breeding  (property)`

Feeding, love, babies and growing up (see engine/server/breeding.gd).

### `taming`

*server/entities.gd*

GDScript: `taming  (property)`

Owners, following, sitting and defending (see engine/server/taming.gd).

### `realm`

*server/entities.gd*

GDScript: `realm  (property)`

The realm these creatures are in.

### `spawn`

*server/entities.gd*

GDScript: `spawn(type_id: int, pos: Vector3, options := {}) -> Entity`

options: yaw, velocity (Vector3), data (Dictionary), owner, item (id), count, pickup_delay

**See also:** `arrived`, `attach`, `ensure`

### `drop_item`

*server/entities.gd*

GDScript: `drop_item(item: int, count: int, pos: Vector3, velocity := Vector3.INF, pickup_delay := ITEM_PICKUP_DELAY, item_data := {}) -> Entity`

JavaScript: `api.dropItem(item, count, pos, velocity, pickupDelay, itemData)`

Drops an item stack at `pos` with a small random toss.

**See also:** `max_stack`, `qualified`, `register_instance`, `spawn`

### `last_sections`

*server/entities.gd*

GDScript: `last_sections := {}  (property)`

Microseconds spent in each part of the last tick (read by the server's --metrics).

### `damage`

*server/entities.gd*

GDScript: `damage(e: Entity, amount: float, cause: String, attacker = null, direction := Vector3.ZERO) -> bool`

Returns true if damage was applied. `direction` pushes the entity (defaults to away from attacker).

**See also:** `broadcast_entity_event`, `damage_player`, `is_alive`, `kill`, `on_hurt`, `play_sound`

### `add_spawn_rule`

*server/entities.gd*

GDScript: `add_spawn_rule(rule: Dictionary) -> void`

JavaScript: `api.addSpawnRule(rule)`

See engine/server/spawning.gd for rule keys.

**See also:** `add_rule`, `block`, `entity_type`, `is_excluded`, `qualified`

### `replicate`

*server/entities.gd*

GDScript: `replicate(players: Array) -> void`

Called every snapshot interval. Sends spawns/despawns for entities entering or leaving each
player's view, and compact position updates for visible entities that moved.

### `look_changed`

*server/entities.gd*

GDScript: `look_changed(e: Entity) -> void`

An entity's look changed (Entity.set_look): tell players who can see it.

### `serialize_chunk`

*server/entities.gd*

GDScript: `serialize_chunk(coord: Vector2i) -> Array`

Persistent entities standing in `coord` as JSON-safe dictionaries.

**See also:** `chunk_coord_of`, `is_alive`

### `unload_chunk`

*server/entities.gd*

GDScript: `unload_chunk(coord: Vector2i) -> Array`

Removes every entity in the chunk (called when it unloads). Returns the persistent ones' records.

**See also:** `chunk_coord_at`, `chunk_coord_of`, `serialize_chunk`

### `type`

*server/entity.gd*

GDScript: `type := 0  (property)`

Type id (EntityRegistry index) and its full server-side definition.

### `health`

*server/entity.gd*

GDScript: `health := 0.0  (property)`

Health is a property rather than a plain field so the label over its head cannot go stale. A mod
writing `e.health = 5` is not a rare case - it is how half the tests and several mods change it -
and hooking the two places the engine happens to change it left every other writer silent.
(2026-09-20, after the user asked why this was not event driven: there is no entity_healed event to
listen to, and entity_damage fires *before* the change.)

### `data`

*server/entity.gd*

GDScript: `data := {}  (property)`

Free-form data owned by mods; saved with persistent entities. Namespace your keys.

### `age`

*server/entity.gd*

GDScript: `age := 0.0  (property)`

Seconds since spawning.

### `owner`

*server/entity.gd*

GDScript: `owner = null  (property)`

Projectiles: the ServerPlayer or entity that fired it (never persisted).

### `item_id`

*server/entity.gd*

GDScript: `item_id := 0  (property)`

Dropped item stacks.

### `brain`

*server/entity.gd*

GDScript: `brain = null  (property)`

Mobs: the AI brain (engine/server/ai/mob_brain.gd); null for other kinds.

### `set_look`

*server/entity.gd*

GDScript: `set_look(values: Dictionary) -> void`

How clients draw this entity: {scale (1 = normal, babies are smaller), hide: [model part name
prefixes to hide, e.g. "wool" once sheared], tint: {part prefix: "#rrggbb"}, pose: "" | "sit"}. Merged into the current
look and saved in data.look.

**See also:** `apply`, `look_changed`, `merge`

### `is_alive`

*server/entity.gd*

GDScript: `is_alive() -> bool`

False once the entity died or was removed.

### `remove`

*server/entity.gd*

GDScript: `remove() -> void`

Removes the entity from the world (no death, no drops).

### `damage`

*server/entity.gd*

GDScript: `damage(amount: float, cause := "magic", attacker = null) -> bool`

Deals damage as if from `attacker` (a ServerPlayer, entity or null). Returns true if it applied.

`cause` comes before `attacker` to match ServerPlayer.damage and EntityManager.damage. It used to be
the other way round on this one object alone, which meant `target.damage(5, "poison")` filed the
cause as the attacker on a creature and as the cause on a player - no error either way, because an
attacker is untyped. Conditions had to tell the two apart rather than just calling it. (2026-09-20)

**See also:** `broadcast_entity_event`, `damage_player`, `is_alive`, `kill`, `on_hurt`, `play_sound`

### `kill`

*server/entity.gd*

GDScript: `kill(cause := "magic") -> void`

Kills it outright, with drops and a death, as opposed to `remove()` which takes it away as though it
had never been there. Player has had `kill` all along; this is the same verb for a creature.

**See also:** `broadcast_entity_event`, `damage`, `drop_item`, `is_alive`, `kill_player`, `play_sound`

### `teleport`

*server/entity.gd*

GDScript: `teleport(pos: Vector3) -> void`

Puts it somewhere, stopping it dead. The same spelling as ServerPlayer.teleport, so code that moves
"a thing" does not have to know which kind of thing it has.

**See also:** `ensure_area_loaded`, `realm_of`

### `set_health`

*server/entity.gd*

GDScript: `set_health(value: float) -> void`

Sets health, clamped, and dies properly if that takes it to zero.

The spelling Player has had all along, and the reason it is worth having on both: writing
`e.health = 0` notifies (the property is hooked) but does not clamp to the type's maximum and does
not *die* - no drops, no death event, just a creature standing there with nothing left. The raw
property stays for the engine's own writes; a mod wanting to set health should use this.
(2026-09-21)

**See also:** `is_alive`, `kill`, `kill_player`, `sync_health`

### `heal`

*server/entity.gd*

GDScript: `heal(amount: float) -> void`

Gives back health, up to the type's maximum.

**See also:** `heal_player`, `is_alive`

### `set_goal`

*server/entity.gd*

GDScript: `set_goal(pos: Vector3) -> void`

Makes a mob walk to `pos`, overriding its behaviour until it arrives; Vector3.INF clears it.

**See also:** `wake`

### `get_target`

*server/entity.gd*

GDScript: `get_target()`

Mobs: the current enemy (a player or entity), or null.

**See also:** `now`

### `set_target`

*server/entity.gd*

GDScript: `set_target(new_target) -> void`

Mobs: attack this player or entity now (null forgets the current target).

**See also:** `alert_allies`, `key_of`, `position_of`, `velocity_of`

### `add_threat`

*server/entity.gd*

GDScript: `add_threat(source, amount: float) -> void`

Mobs: makes `source` more (or less) hated; the highest threat becomes the target.

**See also:** `is_alive`, `key_of`, `position_of`, `velocity_of`

### `tune`

*server/entity.gd*

GDScript: `tune(values: Dictionary) -> void`

Mobs: overrides AI settings for this mob only (see engine/server/ai/mob_config.gd).

**See also:** `agent_for`, `sanitize`

### `alert`

*server/entity.gd*

GDScript: `alert(pos: Vector3) -> void`

Mobs: investigate a position as if it heard something there.

### `set_home`

*server/entity.gd*

GDScript: `set_home(pos: Vector3, leash := -1.0) -> void`

Mobs: the home it returns to when it strays beyond its leash.

**See also:** `tune`

### `perform_attack`

*server/entity.gd*

GDScript: `perform_attack(attack_name: String) -> bool`

Mobs: starts the named attack against the current target right away (ignores range and cooldown).

**See also:** `begin`

### `get_behavior`

*server/entity.gd*

GDScript: `get_behavior() -> String`

Mobs: name of the running behaviour ("wander", "engage", "flee", ...).

### `push`

*server/entity.gd*

GDScript: `push(impulse: Vector3) -> void`

Adds velocity (e.g. knockback, launch pads).

**See also:** `play_sound`, `wake`

### `wake`

*server/entity.gd*

GDScript: `wake() -> void`

Makes a resting entity simulate again right away (after moving it from a mod).

**See also:** `needed_sleepers`, `refresh_appearance`, `stand_spot`, `teleport`

### `aabb`

*server/entity.gd*

GDScript: `aabb() -> AABB`

Box enclosing the entity, for hit tests.

### `default_for`

*server/nameplates.gd*

GDScript: `static default_for(def: Dictionary) -> Dictionary`

The default for an entity type: `nameplate` in its definition, or {} for no plate at all. Creatures
are quiet by default - a field of forty sheep each wearing a label is worse than no labels.

### `set_plate`

*server/nameplates.gd*

GDScript: `set_plate(target, spec := {}) -> bool`

Sets or changes what is over something's head. `spec` merges with whatever is there, so a mod can
add a line without knowing whether health is being shown.

**See also:** `close`, `open`, `plate_of`, `set_look`

### `plate_of`

*server/nameplates.gd*

GDScript: `plate_of(target) -> Dictionary`

What is over its head now, defaults included.

**See also:** `default_for`

### `ensure`

*server/nameplates.gd*

GDScript: `ensure(target) -> void`

Writes a plate at spawn for the creatures that should wear one before anybody hits them.

**Only the rare ones**, which is a deliberate line rather than an oversight (the user, 2026-09-24):

- **A `notable` creature is announced to the whole server and marked on everybody's compass**, so
arriving at it and finding an unlabelled shape would be a worse moment than not announcing it.
It wears its name from the start.
- **Ordinary mobs and animals keep the old behaviour** - a plate the first time they take damage.
A meadow of sheep each wearing a label is worse than no labels, which is why `default_for`
refuses by default and why this does not override it.
- **Players already have one** and always did: `remote_player.gd` applies a plate on setup, so this
never had anything to do with them.
- **Tamed creatures** get theirs from `taming.tame`, because whose it is only becomes true then.

**See also:** `close`, `notable_of`, `open`, `plate_of`, `set_look`

### `clear`

*server/nameplates.gd*

GDScript: `clear(target) -> bool`

Takes it away entirely.

### `health_changed`

*server/nameplates.gd*

GDScript: `health_changed(target) -> void`

Called when something's health moves. Only reaches the client for a plate that actually draws it.

**See also:** `close`, `open`, `plate_of`, `set_look`

### `category_of_type`

*server/spawning.gd*

GDScript: `category_of_type(type_id: int) -> String`

A mob type's category: its `category` key, else from its AI (hostile, archer and boss presets or a
hostile temperament: monster; passive: animal).

### `count_near`

*server/spawning.gd*

GDScript: `count_near(center: Vector3, category: String) -> int`

Mobs of a category within CAP_RADIUS of a position.

**See also:** `category_of`, `is_alive`

### `run`

*server/spawning.gd*

GDScript: `run(for_players: Array = []) -> void`

One spawning round for `for_players` (default: everyone). The server calls it every tick for a slice of
the players, so each player gets a round about once a second without one tick doing them all.

**See also:** `category_of`, `daylight`, `find_spot`, `get_time_of_day`, `is_alive`, `spawn`

### `find_spot`

*server/spawning.gd*

GDScript: `find_spot(center: Vector3, rule: Dictionary, daylight: float, min_distance := -1.0, max_distance := -1.0) -> Vector3`

A spot for a rule's mob around `center` (surface or caves), or Vector3.INF.

**See also:** `biome_at`, `chunk_coord_at`, `collides`, `get_block`, `has_chunk`, `index`

### `despawn`

*server/spawning.gd*

GDScript: `despawn(slot := 0, slots := 1) -> void`

Removes mobs nobody is near. `slot`/`slots` check only the mobs whose id falls in that slot (the server
spreads the check over a second of ticks); the defaults check every mob.

**See also:** `category_of`

### `summary`

*server/spawning.gd*

GDScript: `summary(center: Vector3) -> Dictionary`

{category: {near, cap}} around a player, for the /mobs command.

**See also:** `count_near`

### `interact`

*server/taming.gd*

GDScript: `interact(p, e) -> bool`

Right-click by a player. Returns true if it was handled (a taming try or sit toggle).

**See also:** `clear_slot`, `config_of`, `is_alive`, `is_food`, `is_tamed`, `owner_id`

### `defenders_of`

*server/taming.gd*

GDScript: `defenders_of(p) -> Array`

Tamed mobs near a player that are ready to fight for them.

**See also:** `in_radius`, `is_alive`, `owner_id`

### `owner_hurt`

*server/taming.gd*

GDScript: `owner_hurt(p, attacker) -> void`

Someone hurt `p`: their tamed mobs turn on the attacker.

**See also:** `add_threat`, `defenders_of`

### `owner_attacked`

*server/taming.gd*

GDScript: `owner_attacked(p, target) -> void`

`p` attacked `target`: their tamed mobs join in.

**See also:** `add_threat`, `defenders_of`

### `protects`

*server/taming.gd*

GDScript: `protects(e, other) -> bool`

Whether `e` must never treat `other` as an enemy (its owner).

**See also:** `is_tamed`, `owner_id`

### `update`

*server/taming.gd*

GDScript: `update() -> void`

Once a second: tamed mobs that fell far behind catch up with their owner.

### `problem`

*server/vehicles.gd*

GDScript: `problem := ""  (property)`

Why the last mount was refused, in words somebody can be shown. A vehicle that silently does not
take you is indistinguishable from one that is broken. (2026-09-21)

### `config`

*server/vehicles.gd*

GDScript: `static config(def: Dictionary) -> Dictionary`

The vehicle block of an entity type, or {}.

### `riders_of`

*server/vehicles.gd*

GDScript: `static riders_of(entity) -> Array`

JavaScript: `api.ridersOf(entity)`

Who is aboard, as player ids. Kept on the entity so it is saved with it: a boat you left at a jetty
is empty when you come back, which is right, but the boat is still there.

**See also:** `order`, `register_order`

### `mount`

*server/vehicles.gd*

GDScript: `mount(player, entity) -> bool`

JavaScript: `api.mount(player, entity)`

Puts a player aboard. Refused when it is full, too far away, or they are already riding something.

**See also:** `config_of`, `is_alive`, `riders_of`, `tell_riding`

### `dismount`

*server/vehicles.gd*

GDScript: `dismount(player, to = null) -> bool`

JavaScript: `api.dismount(player, to)`

Takes a player off. `to` is where to put them down; by default beside the vehicle rather than inside
it, because standing inside a boat's own box pushes you through the floor.

**See also:** `riders_of`, `tell_riding`

### `empty`

*server/vehicles.gd*

GDScript: `empty(entity) -> void`

Everybody off, for a vehicle that is being removed or has died.

**See also:** `dismount`, `player_by_id`, `riders_of`

### `simulate`

*server/vehicles.gd*

GDScript: `simulate(player) -> void`

The rider's share of a server tick, called instead of walking them. Returns after draining the input
queue either way, so the client's prediction queue does not stall.

**See also:** `at_path_end`, `config_of`, `dismount`, `get_block`, `is_alive`, `node_center`

### `segment_hits_box`

*shared/entity_physics.gd*

GDScript: `static segment_hits_box(from: Vector3, dir: Vector3, max_t: float, box_min: Vector3, box_max: Vector3) -> float`

Distance along the segment `from` + `dir` * t (t in [0, max_t]) where it enters the box, or -1.

### `register`

*shared/entity_registry.gd*

GDScript: `register(def: Dictionary, replace := false) -> int`

Definition keys (all optional except name):
kind: "mob" | "projectile" | "object" | "item"
model: glTF asset (nodes named leg_a / leg_b / arm_a / arm_b swing while walking, head turns)
sprite: texture asset drawn as a billboard when there is no model (projectiles, particles)
width, height: collision box in blocks; scale: model scale; glow: unshaded (e.g. magic sparks)
light: a model part that lights the world around it - {part: "lantern", color, energy 0-8,
range 0-16 blocks}. `glow` only makes a part draw at full brightness; this one actually
casts. Items have had the same thing for weeks (item_registry.clean_glow) and creatures
had no way to say it, which is how a lamplighter ended up carrying a lamp that lit
nothing. Use it sparingly: it is a real light per creature on screen.
health (0 = cannot be damaged), speed, gravity, drag, knockback_resistance (0-1)
ai: a preset name or a Dictionary of behaviour settings, attacks and phases; see
engine/server/ai/mob_config.gd (mobs only)
damage (projectiles: damage dealt on hit), lifetime (seconds, 0 = forever)
drops: [[item name or id, count], ...] on death; sounds: {hurt, death, ambient, attack}
persistent: saved with the chunk it is in (otherwise despawns when no player is near)
notable: the whole server is told when one appears, and it is marked on everybody's map and
compass - the marker follows it and counts down - until it dies or its time runs out.
{announce, slain ("%s" is the killer), gone, label, color, minutes (0 = never leaves)},
or `true` for the defaults. For the rare ones worth hunting; see server/sightings.gd.
`replace`: an existing type of that name gets the new definition in place (same id; mod reloads).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `notable_of`

*shared/entity_registry.gd*

GDScript: `notable_of(type_id: int) -> Dictionary`

JavaScript: `api.notableOf(typeId)`

Whether this type is one the server announces, and how. `{}` when it is not.

A function rather than a reach into `defs[id].notable`, because `notable` is a shape a mod wrote
and this registry normalised, and those have one owner here - see engine/owned.txt.

**See also:** `entity_type`

### `id_of`

*shared/entity_registry.gd*

GDScript: `id_of(type_name: String) -> int`

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid`

*shared/entity_registry.gd*

GDScript: `is_valid(id: int) -> bool`

Whether anything is registered under this id.

### `to_network`

*shared/entity_registry.gd*

GDScript: `to_network() -> Array`

The creature table as the client receives it, trimmed to `NETWORK_FIELDS`.

### `load_network`

*shared/entity_registry.gd*

GDScript: `load_network(data) -> bool`

Client side. Rebuilds the table from the server's copy (the engine:item entry is included).

### `dir`

*shared/identity.gd*

GDScript: `static dir() -> String`

Where identities live. QW_IDENTITY_DIR moves them, which is how the tests keep their bot keys out of
the player's own folder: a test run used to overwrite default.pem and take the player's account with
it. (2026-09-18)

### `load_or_create`

*shared/identity.gd*

GDScript: `static load_or_create(identity_name := "default", bits := DEFAULT_BITS) -> CryptoKey`

Loads the named identity from user://identity, creating it on first use.

**See also:** `load`, `path_for`, `save`

### `sign`

*shared/identity.gd*

GDScript: `static sign(key: CryptoKey, nonce: PackedByteArray, audience := "") -> PackedByteArray`

Signs the challenge. **`audience` is who the signature is *for*, and leaving it out is the bug this
parameter exists to fix.**

Signing a bare nonce proves you hold the key and nothing else - so a hostile server could take the
nonce a real server handed it, pass it to you as its own challenge, and replay your answer to log
in as you. Binding the server's id into what is signed makes the answer worthless anywhere else:
the real server hashes its own id and the signature no longer matches. The hub has always done it
this way; the game handshake did not. (2026-09-24)

**See also:** `finish`, `start`

### `parse_public_key`

*shared/identity.gd*

GDScript: `static parse_public_key(pem: String) -> CryptoKey`

Server side: parses a public key PEM; returns null if it is not a usable key.

**See also:** `key`

### `player_id`

*shared/identity.gd*

GDScript: `static player_id(key: CryptoKey) -> String`

Stable id derived from the public key (32 hex characters).

**See also:** `finish`, `start`

### `export_encrypted`

*shared/identity.gd*

GDScript: `static export_encrypted(key: CryptoKey, passphrase: String, iterations := EXPORT_ITERATIONS) -> String`

Returns the JSON text of an encrypted identity file.

**See also:** `finish`, `pbkdf2_sha256`, `player_id`, `start`

### `import_encrypted`

*shared/identity.gd*

GDScript: `static import_encrypted(text: String, passphrase: String) -> Dictionary`

Decrypts an exported identity. Returns {key: CryptoKey, player_id} or {error: String}.

**See also:** `finish`, `pbkdf2_sha256`, `player_id`, `start`

### `install`

*shared/identity.gd*

GDScript: `static install(key: CryptoKey, identity_name := "default") -> Error`

Saves `key` as the named identity. An existing different identity is kept as a .bak file.

**See also:** `close`, `download`, `install_package`, `installed`, `installed_path`, `installer`

### `pbkdf2_sha256`

*shared/identity.gd*

GDScript: `static pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray`

PBKDF2-HMAC-SHA256 with a single 32-byte output block.


## Players

### `textures`

*client/effects/effect_player.gd*

GDScript: `textures := {}  (property)`

Asset name -> Texture2D (mod emitter textures).

### `play_sound`

*client/effects/effect_player.gd*

GDScript: `play_sound: Callable  (property)`

JavaScript: `api.playSound(property)`

Plays a sound by name at a position: Callable(name, position).

**See also:** `play_sound_at`, `qualified`

### `quality`

*client/effects/effect_player.gd*

GDScript: `quality := 1.0  (property)`

Scales particle counts (graphics presets).

### `shake_offset`

*client/effects/effect_player.gd*

GDScript: `shake_offset := Vector3.ZERO  (property)`

Current camera shake as an offset to add to the camera, decaying over time.

### `shake_scale`

*client/effects/effect_player.gd*

GDScript: `shake_scale := 1.0  (property)`

Accessibility: 0..1 multipliers for camera shake and light flashes.

### `play`

*client/effects/effect_player.gd*

GDScript: `play(id: int, position: Vector3, options := {}, parent: Node3D = null, listener := Vector3.INF) -> Node3D`

Plays effect `id` at a world position. `parent` (optional) makes it follow a node; `listener`
(camera position) decides whether shake reaches this player. Returns the effect's root node.

**See also:** `exists`, `load`, `play`, `play_def`, `read`

### `play_def`

*client/effects/effect_player.gd*

GDScript: `play_def(def: Dictionary, position: Vector3, options := {}, parent: Node3D = null, listener := Vector3.INF) -> Node3D`

Plays an effect from its definition rather than its id, for effects that were never registered.

Oldest effects are freed once `MAX_LIVE` are running: a mod that fires one per tick should slow the
room down, not fill memory.

**See also:** `builtin_texture`

### `block_break`

*client/effects/effect_player.gd*

GDScript: `block_break(position: Vector3, atlas_texture: Texture2D, uv: Rect2, brightness := 1.0) -> void`

Chunks of a block flying apart: `atlas_texture` with the block face's `uv` rectangle.

**See also:** `begin`

### `builtin_texture`

*client/effects/effect_player.gd*

GDScript: `builtin_texture(texture_name: String) -> Texture2D`

Procedural particle sprites: soft (round glow), spark (bright core), star (four points), square.

**See also:** `create`

### `fetch`

*client/music_player.gd*

GDScript: `fetch := Callable()  (property)`

Set by the client: fetch_lazy_asset(asset_name, then) from GameClient.

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `manifest`

*client/music_player.gd*

GDScript: `manifest := {}  (property)`

asset name -> {hash, size}; set by the client once content has loaded, as for sounds.

### `wanted`

*client/music_player.gd*

GDScript: `wanted := -1  (property)`

The track the server last asked for, whether or not it is audible yet (read by tests).

### `playing`

*client/music_player.gd*

GDScript: `playing := -1  (property)`

What is actually playing (read by tests).

### `play`

*client/music_player.gd*

GDScript: `play(track_id: int, fade: float, restart: bool) -> void`

The server's instruction. -1 stops.

**See also:** `exists`, `load`, `play`, `play_def`, `read`

### `credits`

*client/music_player.gd*

GDScript: `credits() -> Array`

Everything the server is carrying, as lines to show a player. Music must say who made it.

### `manifest`

*client/sound_player.gd*

GDScript: `manifest := {}  (property)`

asset name -> {hash, size}; set by the client once content has loaded.

### `volume`

*client/sound_player.gd*

GDScript: `volume: float  (property)`

The master volume (the "audio/volume" setting).

### `played`

*client/sound_player.gd*

GDScript: `played := 0  (property)`

Sounds started so far (read by tests).

### `stream_named`

*client/sound_player.gd*

GDScript: `stream_named(sound_name: String) -> AudioStream`

A decoded stream by sound name, for anything that wants to own its own playback rather than borrow a
voice from the pool - weather, which loops for as long as it is raining. null if unknown.

**See also:** `exists`, `load`, `read`

### `clock_override`

*server/anticheat.gd*

GDScript: `clock_override := -1  (property)`

Tests drive time themselves (microseconds); -1 = the real clock.

### `record`

*server/anticheat.gd*

GDScript: `record(p, check: String, amount := 1.0, detail := "") -> void`

Adds to a check's score for a player. `detail` explains this event (shown to moderators).

**See also:** `has_permission`, `kick`, `send_message`

### `count_input`

*server/anticheat.gd*

GDScript: `count_input(p) -> void`

Counts a new input from a client and flags inputs beyond the allowance (real time, not server ticks, so
a slow server does not make honest players look fast).

**See also:** `now_usec`, `record`

### `allow_message`

*server/anticheat.gd*

GDScript: `allow_message(peer_id: int) -> bool`

Counts a message from a peer (every client RPC). Returns false when it should be dropped.

**See also:** `record`

### `recent`

*server/anticheat.gd*

GDScript: `recent() -> Array`

[{time, player, check, score, detail, action}] newest first (for /anticheat and the dashboard).

### `load_extra`

*server/chat_filter.gd*

GDScript: `load_extra(world_dir: String) -> void`

Adds the world's own words (one per line; # starts a comment).

### `clean`

*server/chat_filter.gd*

GDScript: `clean(text: String) -> String`

The text with filtered words replaced by asterisks (same length, first letter kept).

### `budget_usec`

*server/claims.gd*

GDScript: `budget_usec := 2000  (property)`

The share of a tick, in microseconds, that all the claims on this server may have between them.
Two milliseconds of a sixteen millisecond tick by default: enough for a few real factories, little
enough that the people actually playing keep the rest.

### `add`

*server/claims.gd*

GDScript: `add(realm_id: String, centre: Vector3i, radius: int, options := {}) -> int`

Keeps chunks awake around a position. `owner` is the mod; `player_id` is whoever should be told if
it has to be paused, and `display` is what to call the place when telling them.

### `awake_chunks`

*server/claims.gd*

GDScript: `awake_chunks(realm_id: String) -> Dictionary`

The chunks a realm is keeping awake on somebody's behalf. Paused claims contribute nothing, which is
the whole of what pausing means.

### `update`

*server/claims.gd*

GDScript: `update(delta: float) -> void`

Charges each claim what its chunks actually spent, and pauses the dearest until the total fits.

### `resume`

*server/claims.gd*

GDScript: `resume(id: int) -> bool`

Lets a paused claim run again - a player tidied their machine, or an admin raised the budget.

**See also:** `add_modifier`, `mark_simulation_stale`

### `kinds`

*server/conditions.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, color, good, max_level, modifiers, tick, particle, stacks, owner}

### `give`

*server/conditions.gd*

GDScript: `give(target, condition_name: String, options := {}) -> bool`

Gives one. `seconds` 0 means until it is taken away. Returns false when the target already has
something stronger and the condition does not stack.

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `sync`

### `clear_all`

*server/conditions.gd*

GDScript: `clear_all(target, only_bad := false) -> int`

Takes away everything, or with `only_bad` everything unpleasant - which is the whole of what a cure
is, and means a mod can write one without listing every affliction in the game.

### `of_target`

*server/conditions.gd*

GDScript: `of_target(target) -> Array`

What they are under, for a panel or a command: [{name, display_name, color, level, good, seconds}],
where `seconds` is -1 for one that does not run out.

### `tick`

*server/conditions.gd*

GDScript: `tick(_delta: float) -> void`

Expiry and the repeating half. Walks only what is holding something, so a world of four thousand
creatures costs nothing until one of them is actually poisoned.

**See also:** `aabb`, `allied`, `apply_condition`, `at_path_end`, `at_station`, `broadcast_entity_event`

### `resume`

*server/conditions.gd*

GDScript: `resume(target) -> void`

Puts a target back on the ticking list after a load: conditions live in saved data, so somebody who
logs out poisoned logs back in poisoned.

**See also:** `add_modifier`, `mark_simulation_stale`

### `before_save`

*server/conditions.gd*

GDScript: `before_save(target) -> void`

Writes how long is *left* rather than when it expires, because server time restarts with the server
and an absolute expiry means nothing on the other side of a save.

### `sync`

*server/hunger.gd*

GDScript: `sync(p, force := false) -> void`

Sends hunger when it changes (-1 while the `hunger` rule is off, which hides the bar).

**See also:** `active_for`, `refresh`, `state_of`, `view`

### `update`

*server/hunger.gd*

GDScript: `update(p, delta: float, moved: Vector3, move_time: float, was_on_ground: bool) -> void`

Each tick: movement exhaustion, hunger drain, regeneration, starvation and eating.
`moved`: how far the player's inputs moved them this tick, over `move_time` seconds of simulation.

### `regen_interval`

*server/hunger.gd*

GDScript: `regen_interval(p, normal_interval: float) -> float`

Whether natural regeneration may heal now, and how often: 0 = not at all.

**See also:** `enabled`

### `start_eating`

*server/hunger.gd*

GDScript: `start_eating(p) -> bool`

Starts eating the held food. Returns false (with a reason shown) if it cannot be eaten now.

**See also:** `enabled`, `get_def`, `members`, `selected_item`, `show_title`, `view`

### `finish_eating`

*server/hunger.gd*

GDScript: `finish_eating(p, slot: int) -> bool`

Eats one item from a slot right away (also used by mods and tests).

**See also:** `add_modifier`, `clear_slot`, `drop`, `get_def`, `get_eye_position`, `heal_player`

### `apply_armor`

*server/player_stats.gd*

GDScript: `static apply_armor(amount: float, armor: float, toughness: float) -> float`

Damage left after armor: armor points absorb up to 80% of a hit, less against big hits unless
toughness is high: a diminishing-returns curve, so each point of armour is worth less than the last.

### `descriptions`

*server/roles.gd*

GDScript: `descriptions := {  (property)`

Known permissions and what they mean (built-in and mod-registered), for /role info and the admin panel.

### `apply_config_admins`

*server/roles.gd*

GDScript: `apply_config_admins(config_admins: Dictionary) -> void`

Applies the admins named in the server's configuration as owners, every start: the config is the
authority on who runs the server, so it is reapplied rather than migrated once.

**See also:** `give`

### `role`

*server/roles.gd*

GDScript: `role(role_name: String) -> Dictionary`

A role's definition (saved changes over the built-in one), or {}.

**See also:** `merge`

### `set_permission`

*server/roles.gd*

GDScript: `set_permission(role_name: String, permission: String, remove := false) -> String`

Adds ("build") or denies ("-build") a permission on a role; `remove` takes an entry away instead.

**See also:** `exists`, `merge`, `role`

### `roles_of`

*server/roles.gd*

GDScript: `roles_of(player_id: String) -> Array`

A player's roles: assigned ones plus the default role.

**See also:** `exists`

### `entries_of`

*server/roles.gd*

GDScript: `entries_of(player_id: String) -> Array`

Every permission entry a player's roles give, following inheritance.

**See also:** `exists`, `role`, `roles_of`

### `allows`

*server/roles.gd*

GDScript: `static allows(entries: Array, permission: String) -> bool`

Whether a set of entries grants a permission: a matching denial wins; "*" and "group.*" match.

### `badge`

*server/roles.gd*

GDScript: `badge(player_id: String) -> Dictionary`

The highest role with a tag, for chat: {tag, color} or {}.

**See also:** `role`, `roles_of`

### `rank`

*server/roles.gd*

GDScript: `rank(player_id: String) -> int`

The highest priority among a player's roles (a manager can only hand out roles below their own).

**See also:** `roles_of`

### `player_id`

*server/server_player.gd*

GDScript: `player_id := ""  (property)`

Permanent id derived from the player's identity key.

**See also:** `finish`, `start`

### `kept_items`

*server/server_player.gd*

GDScript: `kept_items: Array = []  (property)`

Stacks from mods this server does not have right now: kept as saved and written back untouched.

### `data`

*server/server_player.gd*

GDScript: `data := {}  (property)`

Free-form per-player data owned by mods; persisted with the world. Namespace your keys.

### `hunger`

*server/server_player.gd*

GDScript: `hunger := 20.0  (property)`

Hunger 0-20 and hidden saturation (see engine/server/hunger.gd).

### `realm_id`

*server/server_player.gd*

GDScript: `realm_id := ""  (property)`

Which of the server's worlds this player is standing in; "" is the overworld. Saved with them, so
somebody who logged out in another realm comes back to it rather than falling into the overworld at
the same coordinates - which would be a different place entirely.

### `spawn_point`

*server/server_player.gd*

GDScript: `spawn_point := Vector3.INF  (property)`

Where the player respawns; Vector3.INF uses their bed, then the game's spawn handler.

### `spawn_bed`

*server/server_player.gd*

GDScript: `spawn_bed = null  (property)`

The bed they last used (Vector3i, foot) or null; checked when respawning.

### `sleeping`

*server/server_player.gd*

GDScript: `sleeping := {}  (property)`

{bed, since, head_dir, return} while asleep in a bed.

### `riding`

*server/server_player.gd*

GDScript: `riding := 0  (property)`

JavaScript: `api.riding(property)`

The entity this player is riding, or 0. While it is set they do not walk: their position comes from
the vehicle and their input is steering (see engine/server/vehicles.gd).

### `modifiers`

*server/server_player.gd*

GDScript: `modifiers := {}  (property)`

Timed stat modifiers: id -> {stat, amount, op, expires (server time, 0 = permanent)}.

### `input_credit`

*server/server_player.gd*

GDScript: `input_credit := 0.0  (property)`

Simulation steps this player may take (anti-cheat: inputs cannot run faster than the game).

### `charging`

*server/server_player.gd*

GDScript: `charging := {}  (property)`

{slot, item, started} while holding use on an item that charges (a drawn bow; see Charging).

### `physics_rules`

*server/server_player.gd*

GDScript: `physics_rules = null  (property)`

Physics rules adjusted by this player's move_speed stat (null = the server's rules).

### `appearance`

*server/server_player.gd*

GDScript: `appearance := {}  (property)`

Last appearance sent to clients (held item, visible armor, cosmetics).

### `avatar`

*server/server_player.gd*

GDScript: `avatar := {}  (property)`

The look others see (Cosmetics avatar data), recomputed by the server from the fields below.

### `portable_avatar`

*server/server_player.gd*

GDScript: `portable_avatar := {}  (property)`

The player's own built-in look, sent by their client.

### `server_wear`

*server/server_player.gd*

GDScript: `server_wear := {}  (property)`

Server cosmetics the player picked on this server: {category: {id, color}}.

### `avatar_override`

*server/server_player.gd*

GDScript: `avatar_override := {}  (property)`

Avatar data mods lay over the player's look (see set_avatar_override).

### `requested_avatar`

*server/server_player.gd*

GDScript: `requested_avatar := {}  (property)`

The avatar the client last asked for (creations in it may still be uploading or awaiting approval).

### `owned_cosmetics`

*server/server_player.gd*

GDScript: `owned_cosmetics := {}  (property)`

Server cosmetics granted to this player: name -> true.

### `open_container`

*server/server_player.gd*

GDScript: `open_container = null  (property)`

JavaScript: `api.openContainer(property)`

Position of the container whose screen is open (null when none).

**See also:** `open`

### `crafting_station`

*server/server_player.gd*

GDScript: `crafting_station := {}  (property)`

{name, position, title} of the crafting station in use ({} = crafting by hand).

### `known_recipes`

*server/server_player.gd*

GDScript: `known_recipes := {}  (property)`

Recipes this player has discovered: recipe id -> true (see RecipeRegistry unlock rules).

### `seen_items`

*server/server_player.gd*

GDScript: `seen_items := {}  (property)`

Items this player has held at least once: item name -> true (drives "pickup" discoveries).

### `team`

*server/server_player.gd*

GDScript: `team := ""  (property)`

Team name ("" = none). Teams share station trays and projects; mods decide who is on which team.

### `guide`

*server/server_player.gd*

GDScript: `guide := {}  (property)`

Guidebook progress (see engine/server/guide.gd).

### `tutorial`

*server/server_player.gd*

GDScript: `tutorial := {}  (property)`

Tutorial progress and tips seen (see engine/server/tutorials.gd).

### `selected_slot`

*server/server_player.gd*

GDScript: `selected_slot: int  (property)`

Index of the selected hotbar slot.

### `get_eye_position`

*server/server_player.gd*

GDScript: `get_eye_position() -> Vector3`

Where the player's eyes are (for aiming and line of sight).

**See also:** `eye_position`

### `has_permission`

*server/server_player.gd*

GDScript: `has_permission(permission: String) -> bool`

Whether this player's roles grant a permission ("build", "creative", "ugc.review", a mod's own ...).

### `transfer_to`

*server/server_player.gd*

GDScript: `transfer_to(server_name: String, arrival := "", data := {}) -> String`

Sends the player to another server in this server's network (network.json; see engine/server/transfers.gd).
`arrival`: a named arrival point there; `data`: a small Dictionary mods there receive in player_arrived.
Returns "" or why not.

**See also:** `transfer`

### `teleport`

*server/server_player.gd*

GDScript: `teleport(pos: Vector3) -> void`

Moves the player to a position and stops their fall.

**See also:** `ensure_area_loaded`, `realm_of`

### `damage`

*server/server_player.gd*

GDScript: `damage(amount: float, cause := "magic", attacker = null) -> bool`

Deals damage from `attacker` (player, entity or null). Creative players are unaffected. Returns
true if damage applied. `cause`: "attack", "mob", "projectile", "fall", "void", "magic", ...

**See also:** `broadcast_entity_event`, `damage_player`, `is_alive`, `kill`, `on_hurt`, `play_sound`

### `heal`

*server/server_player.gd*

GDScript: `heal(amount: float) -> void`

Gives back health, up to max_health.

**See also:** `heal_player`, `is_alive`

### `is_alive`

*server/server_player.gd*

GDScript: `is_alive() -> bool`

The same question Entity.is_alive answers, spelled the same way, so code that asks "is this thing
still around" does not have to know which kind of thing it has. `dead` stays as it was.

### `set_hunger`

*server/server_player.gd*

GDScript: `set_hunger(value: float, new_saturation := -1.0) -> void`

Sets hunger (0-20) and optionally saturation.

**See also:** `add_modifier`, `enabled`, `remove_modifier`, `sync`

### `add_exhaustion`

*server/server_player.gd*

GDScript: `add_exhaustion(amount: float) -> void`

Adds hunger exhaustion (4 = one point of saturation or hunger).

**See also:** `enabled`, `get_stats`, `set_hunger`, `sync`

### `feed`

*server/server_player.gd*

GDScript: `feed(hunger_points: float, saturation_points := 0.0) -> void`

Restores hunger and saturation as if eating.

**See also:** `clear_slot`, `config_of`, `is_alive`, `is_baby`, `is_food`, `play_effect`

### `set_health`

*server/server_player.gd*

GDScript: `set_health(value: float) -> void`

Sets health (0 kills).

**See also:** `is_alive`, `kill`, `kill_player`, `sync_health`

### `set_max_health`

*server/server_player.gd*

GDScript: `set_max_health(value: float) -> void`

Sets the base max health for this player (items and effects still modify it).

**See also:** `add_modifier`

### `kill`

*server/server_player.gd*

GDScript: `kill(cause := "magic") -> void`

Kills the player with a cause (shown in the death message).

**See also:** `broadcast_entity_event`, `damage`, `drop_item`, `is_alive`, `kill_player`, `play_sound`

### `push`

*server/server_player.gd*

GDScript: `push(impulse: Vector3) -> void`

Adds velocity (knockback, launch pads). The client is corrected by the next snapshot.

**See also:** `play_sound`, `wake`

### `hear`

*server/server_player.gd*

GDScript: `hear(sound_name: String, volume := 1.0, pitch := 1.0) -> void`

Plays a sound only this player hears, not positioned in the world.

**Called `hear`, not `play_sound`.** `api.play_sound(name, position, volume, pitch)` puts a sound
in the world; this one was `play_sound(name, volume, pitch)`, so the same name took a Vector3 as
its second argument in one place and a float in the other - a transposition the compiler would
catch but a reader would not. (2026-09-21)

**See also:** `play_sound_to`

### `send_message`

*server/server_player.gd*

GDScript: `send_message(text: String) -> void`

A chat message only this player sees.

### `show_title`

*server/server_player.gd*

GDScript: `show_title(text: String, subtitle := "", seconds := 3.0) -> void`

Big text in the middle of the player's screen for a few seconds.

### `show_ui`

*server/server_player.gd*

GDScript: `show_ui(ui_id: String, spec: Dictionary) -> void`

Shows or replaces a server-defined UI panel. See engine/client/server_ui.gd for the spec format.

### `hide_ui`

*server/server_player.gd*

GDScript: `hide_ui(ui_id: String) -> void`

Closes a server UI panel shown with show_ui.

### `is_creative`

*server/server_player.gd*

GDScript: `is_creative() -> bool`

Whether the player is in creative mode.

### `set_creative`

*server/server_player.gd*

GDScript: `set_creative(enabled: bool) -> void`

Switches the player between creative (true) and survival (false).

**See also:** `has_permission`, `on_join`, `set_flying`, `sync_inventory`

### `has_room`

*server/server_player.gd*

GDScript: `has_room(item: int, count := 1, item_data := {}) -> bool`

Whether this many would fit in the pack. A reward can be dropped at a player's feet when it does not
(see give), but anything they are *paying* for should be refused instead: goods on the floor can be
missed, or despawn, and the coin is gone either way.

**See also:** `give`, `max_stack`, `space_for`

### `give`

*server/server_player.gd*

GDScript: `give(item: int, count := 1, item_data := {}) -> bool`

Adds blocks or items (optionally with item data). Anything that does not fit falls at the player's
feet rather than vanishing, so a reward, a purchase or a quest payout is never lost to a full pack -
a mod would otherwise have to remember to check the return value every single time.

**True when it all fit.** This returned the number *dropped*, which meant `if player.give(...)`
read as "if it worked" and meant "if it failed" - the kind of thing that is right in the one place
somebody thought about it and wrong everywhere it was copied to. The count is still available from
`give_overflow` for the two callers that want to say how much ended up on the floor. (2026-09-21)

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `sync`

### `give_overflow`

*server/server_player.gd*

GDScript: `give_overflow(item: int, count := 1, item_data := {}) -> int`

The same, returning how many did not fit and were dropped at their feet. 0 means it all fit.

**See also:** `drop_item`, `max_stack`, `realm_of`, `send_message`, `sync_inventory`

### `take`

*server/server_player.gd*

GDScript: `take(block: int, count := 1) -> bool`

Removes items if the player has enough; returns false otherwise.

**See also:** `coop`, `get_item`, `max_stack`, `may_take`, `set_item`, `sync_inventory`

### `count_of`

*server/server_player.gd*

GDScript: `count_of(block: int) -> int`

How many of a block or item the player carries.

### `clear_inventory`

*server/server_player.gd*

GDScript: `clear_inventory() -> void`

Empties the player's inventory.

**See also:** `sync_inventory`

### `drop`

*server/server_player.gd*

GDScript: `drop(item: int, count := 1, item_data := {}) -> void`

Drops items as an entity in front of the player.

**See also:** `drop_item`, `get_eye_position`, `look_direction`, `realm_of`

### `set_hotbar`

*server/server_player.gd*

GDScript: `set_hotbar(blocks: Array, count := 1) -> void`

Fills hotbar slots in order with the given block ids.

**See also:** `set_slot`, `sync_inventory`

### `get_item`

*server/server_player.gd*

GDScript: `get_item(slot: int) -> Dictionary`

{item, count, data} in a slot (0-35 backpack, then equipment; see equipment_slot).

**See also:** `total`

### `set_item_data`

*server/server_player.gd*

GDScript: `set_item_data(slot: int, item_data: Dictionary) -> void`

Replaces the item data of a slot (a copy is stored). Use it for wear, experience, levels,
upgrades, custom names ("name"), tooltip lines ("lore") and per-item stat "modifiers".

**See also:** `sync_inventory`, `total`

### `equipment_slot`

*server/server_player.gd*

GDScript: `equipment_slot(slot_name: String) -> int`

Inventory index of a named equipment slot ("head", "chest", ...), or -1.

**See also:** `equipment_index`

### `damage_item`

*server/server_player.gd*

GDScript: `damage_item(slot: int, amount := 1, reason := "use") -> void`

Wears down the item in a slot (respects the durability gameplay rule and item_durability event).

**See also:** `clear_slot`, `get_eye_position`, `look_direction`, `max_durability`, `play_effect`, `play_sound_at`

### `get_stats`

*server/server_player.gd*

GDScript: `get_stats() -> Dictionary`

Current stats (see ItemRegistry.BASE_STATS and register_stat).

**See also:** `refresh_stats`

### `get_stat`

*server/server_player.gd*

GDScript: `get_stat(stat_name: String) -> float`

One stat's current value (see get_stats).

### `add_modifier`

*server/server_player.gd*

GDScript: `add_modifier(id: String, stat: String, amount: float, op := "add", seconds := 0.0) -> void`

Adds or replaces a stat modifier. `op`: "add" or "multiply" (amount 0.2 = +20%); `seconds` 0 = until
removed. Use ids like "my_mod:haste".

**See also:** `refresh_stats`

### `remove_modifier`

*server/server_player.gd*

GDScript: `remove_modifier(id: String) -> void`

Removes a stat modifier added with add_modifier.

**See also:** `now`, `refresh_stats`

### `refresh_stats`

*server/server_player.gd*

GDScript: `refresh_stats() -> void`

Recomputes stats now (after changing item data or modifiers outside the API).

**See also:** `compute`, `refresh_appearance`, `sync_health`

### `sync_inventory`

*server/server_player.gd*

GDScript: `sync_inventory() -> void`

Sends the inventory to the player after changing it directly (give and take do this for you).

**See also:** `data_to_network`, `refresh_stats`, `to_packed`

### `grant_cosmetic`

*server/server_player.gd*

GDScript: `grant_cosmetic(cosmetic_name: String) -> void`

Lets the player wear a server cosmetic registered with `unlocked: false`. Saved with the world.

**See also:** `get_def`, `refresh_avatar`

### `revoke_cosmetic`

*server/server_player.gd*

GDScript: `revoke_cosmetic(cosmetic_name: String) -> void`

Takes back a server cosmetic granted with grant_cosmetic.

**See also:** `grant_cosmetic`

### `has_cosmetic`

*server/server_player.gd*

GDScript: `has_cosmetic(cosmetic_name: String) -> bool`

Whether the player may wear a server cosmetic.

### `set_avatar_override`

*server/server_player.gd*

GDScript: `set_avatar_override(values: Dictionary) -> void`

Avatar data laid over this player's look, e.g. a team uniform: {wear: {shirt: {id, color}}}; an
empty id takes a category off. Pass {} to clear. Not saved.

**See also:** `refresh_avatar`, `sanitize_avatar`

### `knows_recipe`

*server/server_player.gd*

GDScript: `knows_recipe(recipe_id: String) -> bool`

Whether the player can craft a recipe (discovered, or discovery is off).

**See also:** `index_of`

### `learn_recipe`

*server/server_player.gd*

GDScript: `learn_recipe(recipe_id: String, source := "mod") -> bool`

Teaches a recipe (source is passed to recipe_learned). Returns true if it was new.

**See also:** `index_of`

### `is_admin`

*server/server_player.gd*

GDScript: `is_admin() -> bool`

Whether the player is a server admin.

**See also:** `has_permission`

### `kick`

*server/server_player.gd*

GDScript: `kick(reason: String) -> void`

Disconnects the player with a reason.

**See also:** `allowed`, `apply_condition`, `block_state`, `chunk_coord_at`, `damage`, `damage_player`

### `save_items`

*server/server_player.gd*

GDScript: `save_items() -> Dictionary`

The inventory, equipment and item data as saved with the world.
The inventory by item name, the saved form since save format 2: ids depend on which blocks and items
are registered, so they change between versions and mod sets; names do not.
{slots: [[index, name, count, data]], equipment: {slot: [name, count, data]}}

**See also:** `have`, `off`

### `load_items`

*server/server_player.gd*

GDScript: `load_items(saved) -> Array`

Loads save_items() output. Returns the names of items this server does not have (they are left out).

**See also:** `equipment_index`, `set_slot`

### `bed_cells`

*server/sleep.gd*

GDScript: `bed_cells(pos: Vector3i) -> Dictionary`

Both cells of a bed (the clicked one first), and the direction from foot to head.

**See also:** `facing_direction`, `get_block_state`, `get_block_v`, `is_bed`, `pair_position`

### `use_bed`

*server/sleep.gd*

GDScript: `use_bed(p, pos: Vector3i) -> void`

Right-click on a bed: set the respawn point, then try to sleep.

**See also:** `bed_cells`, `is_alive`, `is_night`, `needed_sleepers`, `refresh_appearance`, `send_message`

### `needed_sleepers`

*server/sleep.gd*

GDScript: `needed_sleepers() -> int`

How many players must be asleep to skip the night.

### `stand_spot`

*server/sleep.gd*

GDScript: `stand_spot(anchor: Vector3i) -> Vector3`

Where to stand next to a bed (respawning or getting up), or Vector3.INF if it is gone or boxed in.

**See also:** `bed_cells`, `get_block_v`

### `respawn_position`

*server/sleep.gd*

GDScript: `respawn_position(p) -> Vector3`

The respawn position from a player's bed, or Vector3.INF (and a message) when it can't be used.

**See also:** `ensure_area_loaded`, `realm_of`, `send_message`, `stand_spot`

### `key`

*server/status_query.gd*

GDScript: `key: CryptoKey  (property)`

The server's identity key (signs proofs for the hub); set by the server when it starts listening.

### `step`

*shared/player_physics.gd*

GDScript: `static step(s: State, input: PlayerInput, world, rules: Rules) -> void`

One movement step, run identically by the client (prediction) and the server (authority).

The GDScript twin of this was deleted on 2026-09-23 along with the rest; it was 94 lines that had
to agree exactly with `native/src/physics.rs` or the symptom was rubber-banding rather than an
error. The extension is required now, so there is one implementation and nothing to disagree with.

**See also:** `block_state`, `family_of`, `get_block_v`, `set_block_authoritative`

### `overlaps_block`

*shared/player_physics.gd*

GDScript: `static overlaps_block(p: Vector3, block: Vector3i) -> bool`

True if a player standing at feet position `p` overlaps the unit block at `block`.

### `sanitize`

*shared/player_rig.gd*

GDScript: `static sanitize(def) -> Dictionary`

Validates a rig from a mod or the network. Returns the default rig when anything is wrong.

**See also:** `condition_of`, `default_rig`, `merge`

### `parse_request`

*shared/server_status.gd*

GDScript: `static parse_request(packet: PackedByteArray) -> Dictionary`

{nonce, proof} of a valid request, or {}.

### `proof_message`

*shared/server_status.gd*

GDScript: `static proof_message(nonce: PackedByteArray) -> PackedByteArray`

The bytes a server signs to prove it holds its key.

### `parse_response`

*shared/server_status.gd*

GDScript: `static parse_response(packet: PackedByteArray) -> Dictionary`

{nonce, info} from a response, or {} when it is not one. Every field is checked and clamped.


## Effects, sound and weather

### `effects`

*client/weather_view.gd*

GDScript: `effects  (property)`

Set by the client: the EffectPlayer (it knows how to build an emitter) and the camera to follow.

### `current`

*client/weather_view.gd*

GDScript: `current := -1  (property)`

Read by tests: which weather is drawn and how strongly it has faded in.

### `apply`

*client/weather_view.gd*

GDScript: `apply(weather_id: int, intensity: float) -> void`

The server's instruction. -1 is a clear sky. Not called show(): Node3D already has one.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `light_scale`

*client/weather_view.gd*

GDScript: `light_scale() -> float`

How much this weather is dimming the world, for whoever owns the light: 1.0 is untouched.

### `sky_tint`

*client/weather_view.gd*

GDScript: `sky_tint() -> Dictionary`

The colour the sky is being pulled towards, and how far. Returns {} when nothing is happening.

### `register`

*server/ambience.gd*

GDScript: `register(def: Dictionary) -> String`

Returns "" or why it was refused.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `register_category`

*shared/cosmetics.gd*

GDScript: `register_category(def: Dictionary) -> bool`

def: name, display_name, attach (attachment point for boxes/models), covers (armor slots its
cosmetics replace by default). Returns false when invalid or full.

**See also:** `category`, `has_category`

### `register`

*shared/cosmetics.gd*

GDScript: `register(def: Dictionary) -> String`

Registers (or replaces) a cosmetic. Returns its name, or "" when invalid.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `in_category`

*shared/cosmetics.gd*

GDScript: `in_category(cat_name: String) -> Array`

Cosmetics of a category in registration order.

### `sanitize_avatar`

*shared/cosmetics.gd*

GDScript: `sanitize_avatar(avatar, can_wear := Callable(), keep_removals := false) -> Dictionary`

Cleans avatar data from a client, a mod or a file. `can_wear(id) -> bool` filters cosmetics the
player may not wear. With `keep_removals`, wear entries with an empty id survive (uniforms use them
to take a category off).

**See also:** `category`, `clean_color`, `get_def`, `is_color`

### `merge`

*shared/cosmetics.gd*

GDScript: `static merge(base: Dictionary, top: Dictionary) -> Dictionary`

`top` laid over `base`: its colors replace base colors, its wear replaces base wear per category
(an empty id removes the category).

**See also:** `compare`, `sha256`

### `default_avatar`

*shared/cosmetics.gd*

GDScript: `static default_avatar(seed_text: String) -> Dictionary`

The look a player without avatar data gets, varied by name so players are told apart.

### `visible_armor`

*shared/cosmetics.gd*

GDScript: `visible_armor(armor: Dictionary, avatar: Dictionary) -> Dictionary`

Which armor slots stay visible given the avatar's cosmetics, the player's choices and the policy.
`armor`: {slot: item id} -> the visible subset.

**See also:** `get_def`

### `to_network`

*shared/cosmetics.gd*

GDScript: `to_network() -> Dictionary`

Built-in cosmetics are part of every client; only categories, server cosmetics and policy travel.

### `register`

*shared/effect_registry.gd*

GDScript: `register(def: Dictionary) -> int`

Registers an effect (see the header). Returns its id, or -1.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of`

*shared/effect_registry.gd*

GDScript: `id_of(effect_name: String) -> int`

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid`

*shared/effect_registry.gd*

GDScript: `is_valid(id: int) -> bool`

Whether anything is registered under this id.

### `clean_options`

*shared/effect_registry.gd*

GDScript: `static clean_options(options) -> Dictionary`

Cleans play options for the network: {color, scale, direction, duration}.

**See also:** `clean_color`, `is_color`

### `to_network`

*shared/effect_registry.gd*

GDScript: `to_network() -> Array`

The effect table as the client receives it.

### `load_network`

*shared/effect_registry.gd*

GDScript: `load_network(data) -> bool`

Rebuilds the table on the client. False when the data is not the shape we expect.

### `is_color`

*shared/effect_registry.gd*

GDScript: `static is_color(value) -> bool`

Whether a mod wrote something we can read as a colour: `#rgb`, `#rrggbb` or `#rrggbbaa`.

### `clean_color`

*shared/effect_registry.gd*

GDScript: `static clean_color(value, fallback: String) -> String`

A mod's colour normalised to `#rrggbbaa`, or `fallback` if it is not one. Use this rather than
`Color.html`, which returns black for anything it cannot parse - and a silent black is very hard
to tell from a colour somebody meant.

**See also:** `is_color`

### `emitter`

*shared/effect_registry.gd*

GDScript: `static emitter(e: Dictionary) -> Dictionary`

One emitter, read and clamped. Public because weather uses the same vocabulary: a mod should write an
emitter once and have it mean the same thing wherever it is used, defaults and limits included.

**See also:** `clean_color`, `is_color`

### `register`

*shared/music_registry.gd*

GDScript: `register(def: Dictionary) -> int`

def: name, file (asset name), volume (0-2), loop (default true), attribution (required: who made it
and under what licence). Returns the id, or -1 with an error explaining which part was wrong.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of`

*shared/music_registry.gd*

GDScript: `id_of(track_name: String) -> int`

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid`

*shared/music_registry.gd*

GDScript: `is_valid(id: int) -> bool`

Whether anything is registered under this id.

### `to_network`

*shared/music_registry.gd*

GDScript: `to_network() -> Array`

The music table as the client receives it.

### `load_network`

*shared/music_registry.gd*

GDScript: `load_network(list) -> bool`

Rebuilds the table on the client. False when the data is malformed.

### `credits`

*shared/music_registry.gd*

GDScript: `credits() -> Array`

Everything playing on this server, as lines a player can read: what it is and who made it. The
point of making attribution required is that it can be shown, so it is shown - /music credits.

### `register`

*shared/sound_registry.gd*

GDScript: `register(def: Dictionary) -> int`

def: name, files (asset names), volume (linear, 0-2), pitch (1 = original), pitch_variance
(random +/- added to pitch), range (blocks until inaudible). Returns the id or -1.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of`

*shared/sound_registry.gd*

GDScript: `id_of(sound_name: String) -> int`

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid`

*shared/sound_registry.gd*

GDScript: `is_valid(id: int) -> bool`

Whether anything is registered under this id.

### `to_network`

*shared/sound_registry.gd*

GDScript: `to_network() -> Array`

The sound table as the client receives it.

### `load_network`

*shared/sound_registry.gd*

GDScript: `load_network(data) -> bool`

Rebuilds the table on the client. False when the data is malformed.

### `register`

*shared/weather_registry.gd*

GDScript: `register(def: Dictionary) -> int`

def: name, emitter (as an effect emitter), sound (looped while it falls), sky_tint ("#rrggbb"),
light_scale (0-1, how far it darkens the world), fog (0-1). Returns the id, or -1.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `id_of`

*shared/weather_registry.gd*

GDScript: `id_of(weather_name: String) -> int`

The id registered under this name, or **-1 if nothing is**.

-1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
only after checking it, or use the `require_*` form at the API boundary.

### `is_valid`

*shared/weather_registry.gd*

GDScript: `is_valid(id: int) -> bool`

Whether anything is registered under this id.

### `to_network`

*shared/weather_registry.gd*

GDScript: `to_network() -> Array`

The weather table as the client receives it.

### `load_network`

*shared/weather_registry.gd*

GDScript: `load_network(list) -> bool`

Rebuilds the table on the client. False when the data is malformed.


## Progression and story

### `crafting`

*client/guide_screen.gd*

GDScript: `crafting  (property)`

The crafting screen: icons, recipe knowledge and station requirement text.

### `make_entity_view`

*client/guide_screen.gd*

GDScript: `make_entity_view: Callable  (property)`

Builds a Node3D model of an entity type by name (null if it has no model).

### `texture_of`

*client/guide_screen.gd*

GDScript: `texture_of: Callable  (property)`

Texture of an asset by name (image blocks).

### `open`

*client/guide_screen.gd*

GDScript: `open(page_id := "") -> void`

Opens the book at a page ("" = the current page, or the first unlocked one).

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `add_unlocked`

*client/guide_screen.gd*

GDScript: `add_unlocked(pages: PackedStringArray) -> Array`

Adds newly unlocked pages; returns them.

**See also:** `chapter_pages`, `page_text`, `show_page`, `sorted_chapters`

### `lock_hint`

*client/guide_screen.gd*

GDScript: `lock_hint(page: Dictionary) -> String`

What reveals a locked page.

**See also:** `get_page`, `index_of`

### `key_name`

*client/guide_screen.gd*

GDScript: `static key_name(action: String) -> String`

The first key bound to an input action ("G", "Space", "Left Mouse").

### `set_view`

*client/objective_hud.gd*

GDScript: `set_view(view: Dictionary) -> void`

{active: [{name, display_name, step, of, text, progress, needed}]} from the server.

**See also:** `icon_of`, `key_name`, `new_game`, `node_key`, `texture`, `uptime`

### `step_done`

*client/tutorial_hud.gd*

GDScript: `step_done(kind: String) -> void`

A step was finished: a quick green flash (the next step arrives with the view).

### `preferred_page`

*client/tutorial_hud.gd*

GDScript: `preferred_page(read: Dictionary) -> String`

The page the G key should open: the tip on show, else the current step's page (if not read yet).

### `offer_worn`

*client/ugc_client.gd*

GDScript: `offer_worn(avatar: Dictionary) -> void`

Offers the player's own creations worn in `avatar` to the server.

**See also:** `get_manifest`, `worn_ids`

### `ensure_known`

*client/ugc_client.gd*

GDScript: `ensure_known(avatar) -> void`

Makes sure the creations in someone's avatar can be drawn: registers known ones, fetches the rest.

**See also:** `add_to`, `asset_name`, `cache_dir`, `get_def`, `get_manifest`, `get_payload`

### `fetch`

*client/ugc_client.gd*

GDScript: `fetch(ids: Array) -> void`

Asks the server for creations (e.g. from the library) even if nobody wears them yet.

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `creation_ready`

*client/ugc_review.gd*

GDScript: `creation_ready(id: String) -> void`

A creation's files arrived: draw its preview if it is the one on show.

**See also:** `select`

### `kinds`

*server/characters.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, color, lines: {id: {text, options}}, owner}

### `talk`

*server/characters.gd*

GDScript: `talk(player, character_name: String, options := {}) -> bool`

Opens a conversation. `options.line` is where to start - the mod's choice, because which line a
person opens on is a fact about their story and not about conversations. `options.entity` is who is
speaking, so a choice can say which one it was.

**See also:** `key_of`, `position_of`, `show_ui`, `velocity_of`

### `has_met`

*server/characters.gd*

GDScript: `has_met(player, character_name: String) -> bool`

JavaScript: `api.hasMet(player, characterName)`

Whether this player has ever spoken to them, which is most of what "we have met" needs.

**See also:** `qualified`, `register_shop`

### `on_action`

*server/characters.gd*

GDScript: `on_action(player, action: String) -> bool`

A button was pressed. Returns true if it was one of ours, so the caller knows whether to look
further.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `give`, `heat`

### `companies`

*server/companies.gd*

GDScript: `companies := {}  (property)`

id -> {id, name, members: {player_id: rank}, data}

### `at_least`

*server/companies.gd*

GDScript: `at_least(id: int, player_id: String, rank: String) -> bool`

Whether this person is at least this rank.

**See also:** `rank_of`

### `of_player`

*server/companies.gd*

GDScript: `of_player(player_id: String) -> Array`

Every company someone is in: [{id, name, rank}].

**See also:** `is_member`, `rank_of`

### `units`

*server/flows.gd*

GDScript: `units := {}  (property)`

Unit name -> {name, owner}. A unit is just a name the engine keeps apart from other names.

### `on_received`

*server/flows.gd*

GDScript: `on_received(unit: String, handler: Callable) -> void`

JavaScript: `api.onReceived(unit, handler)`

Told when what a face receives changes: ctx = {realm, position, face, unit, wanted, got}.

**See also:** `qualified`, `register_link_kind`

### `set_supply`

*server/flows.gd*

GDScript: `set_supply(unit: String, node: Dictionary, amount: float) -> void`

JavaScript: `api.setSupply(unit, node, amount)`

This face offers this much of `unit` per second (0 to stop).

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `set_demand`

*server/flows.gd*

GDScript: `set_demand(unit: String, node: Dictionary, amount: float) -> void`

JavaScript: `api.setDemand(unit, node, amount)`

This face wants this much per second (0 to stop asking).

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `received`

*server/flows.gd*

GDScript: `received(unit: String, node: Dictionary) -> float`

JavaScript: `api.received(unit, node)`

What this face is actually receiving.

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `link_changed`

*server/flows.gd*

GDScript: `link_changed(a: Dictionary, b: Dictionary) -> void`

A link was made or cut: whatever it touched needs working out again.

**See also:** `key_name`, `node_key`

### `settle`

*server/flows.gd*

GDScript: `settle() -> void`

Works out every network that has changed since last time. Called once a tick from the server, which
is cheap when nothing changed - the usual case - because the dirty list is empty.

**See also:** `describe`, `drive_changed`, `get_block_v`, `node_of`, `qualified`, `reachable`

### `state_of`

*server/guide.gd*

GDScript: `static state_of(p) -> Dictionary`

Per-player guide state: {flags, entities, read, unlocked (page id -> true), last}.

### `condition_met`

*server/guide.gd*

GDScript: `condition_met(p, page: Dictionary) -> bool`

Whether a page's unlock condition holds right now (ignores pages unlocked before).

**See also:** `knows_recipe`, `state_of`

### `refresh`

*server/guide.gd*

GDScript: `refresh(p, notify := true) -> void`

Unlocks pages whose conditions now hold; tells the client (with a popup when `notify`).

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `sync`

*server/guide.gd*

GDScript: `sync(p) -> void`

Sends the full guide state after joining.

**See also:** `active_for`, `refresh`, `state_of`, `view`

### `unlock`

*server/guide.gd*

GDScript: `unlock(p, page_id: String, notify := true) -> bool`

Unlocks a page right away, whatever its condition.

**See also:** `get_page`, `state_of`

### `open`

*server/guide.gd*

GDScript: `open(p, page_id := "") -> void`

Opens the book for a player, at a page ("" = where they left off).

**See also:** `add_realm`, `at_key`, `at_station`, `block_key`, `chapter_pages`, `close`

### `on_read`

*server/guide.gd*

GDScript: `on_read(p, page_id: String) -> void`

The client shows a page: it counts as read (if unlocked) and is remembered as the last page.

**See also:** `get_page`, `refresh`, `state_of`

### `kinds`

*server/ledgers.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, levels, min, max, owner}

### `register`

*server/ledgers.gd*

GDScript: `register(ledger_name: String, def: Dictionary, owner := "engine") -> bool`

def: display_name, levels (thresholds, lowest first - the value at which each level begins),
min and max (what the number may not go past; a balance that may not go negative sets min 0).

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `set_value`

*server/ledgers.gd*

GDScript: `set_value(player, ledger_name: String, value: float) -> float`

Sets it outright. Returns what it ended up as, which is not always what was asked for - a ledger
may have a floor or a ceiling, and saying so is more use than refusing.

**See also:** `describe`, `drive_changed`, `get_value`, `level_for`, `qualified`, `report_error`

### `add`

*server/ledgers.gd*

GDScript: `add(player, ledger_name: String, amount: float) -> float`

Adds to it (a negative amount spends). Returns what it ended up as.

### `spend`

*server/ledgers.gd*

GDScript: `spend(player, ledger_name: String, amount: float) -> bool`

Takes `amount` only if there is that much, so a shop can be written without a check and a race
between the check and the spend. Returns false and changes nothing when there is not enough.

**See also:** `value_of`

### `level_for`

*server/ledgers.gd*

GDScript: `level_for(ledger_name: String, value: float) -> int`

What level a value is at: 0 below the first threshold, 1 at it, and so on.

### `progress_of`

*server/ledgers.gd*

GDScript: `progress_of(player, ledger_name: String) -> Dictionary`

How far through the current level, 0 to 1, and what is left to the next. {level, value, into, needed,
next}, with `next` -1 at the top. For a bar on the screen, which is the usual reason to ask.

**See also:** `level_for`, `value_of`

### `all_of`

*server/ledgers.gd*

GDScript: `all_of(player) -> Array`

Everything a player has, for a scoreboard or a screen: [{name, display_name, value, level}].

**See also:** `level_for`, `value_of`

### `kinds`

*server/links.gd*

GDScript: `kinds := {}  (property)`

Kind name -> definition. See `register_kind`.

### `links`

*server/links.gd*

GDScript: `links := {}  (property)`

Link id -> {kind, a: {realm, position, face}, b: {...}, length}

### `register_kind`

*server/links.gd*

GDScript: `register_kind(kind_name: String, def: Dictionary, owner := "engine") -> bool`

A kind of link a mod can lay.

def: `span` (blocks, capped at MAX_SPAN), `wireless` (nothing is drawn and no clear line is needed),
`crosses_realms` (wireless only), `needs_air` (refuse if anything solid is in the way; default true
for anything not wireless), `item` (what a block of it costs to lay), `draw` ("cable" sags, "pipe"
does not, "" draws nothing), `color` (what it is drawn in).

### `why_not`

*server/links.gd*

GDScript: `why_not(kind_name: String, a: Dictionary, b: Dictionary) -> String`

Why these two nodes may not be joined, or "" if they may. Every refusal is a sentence somebody can
act on, because "cannot place" tells a child nothing.

**See also:** `get_block_v`, `key_name`, `node_key`

### `problem`

*server/links.gd*

GDScript: `problem := ""  (property)`

Joins two nodes. Returns the link id, or 0 with the reason in `problem`.

### `cut`

*server/links.gd*

GDScript: `cut(id: int, why := "removed") -> bool`

Removes a link and says so. `why` reaches the mod, which is how a player finds out their cable was
cut by a wall somebody built rather than simply stopping working.

**See also:** `key_name`, `node_key`

### `at_block`

*server/links.gd*

GDScript: `at_block(realm_id: String, pos: Vector3i) -> Array`

Every link touching a block, whichever face. Used when one is mined.

**See also:** `node_key`

### `reachable`

*server/links.gd*

GDScript: `reachable(from: Dictionary, limit := 4096) -> Dictionary`

Everything reachable from a node, as node keys. The graph traversal every layer above this uses.

**See also:** `key_name`, `node_key`

### `block_changed`

*server/links.gd*

GDScript: `block_changed(realm_id: String, pos: Vector3i, old: int, block: int) -> void`

A block was placed or broken. Links ending at it go; links *passing through* it are cut too, which
is the rule that stops a cable quietly running through a wall somebody built after it.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `to_saved`

*server/links.gd*

GDScript: `to_saved() -> Array`

What to save with the world. Links belong to the world rather than to a chunk: one end may be in a
chunk that is loaded and the other in one that is not, and a link that vanished because half of it
was asleep would be a very confusing bug.

### `register`

*server/milestones.gd*

GDScript: `register(id: String, def: Dictionary, qualify: Callable) -> bool`

Registers one. `qualify` turns a bare name into a mod-qualified one, as it does for tutorials.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `remove_owner`

*server/milestones.gd*

GDScript: `remove_owner(owner: String) -> void`

Drops a mod's milestones before it registers them again on reload. What players have already reached
stays in their data, so a reload does not hand the rewards out twice.

### `reached`

*server/milestones.gd*

GDScript: `reached(p, id: String) -> bool`

Whether this player has reached one, for mods that want to gate something behind it.

**See also:** `state_of`

### `view`

*server/milestones.gd*

GDScript: `view(p) -> Array`

The list a player sees: what they have done, what is left, and how far along they are. Secret ones
stay out of the list until they are reached, so the surprise survives being able to read the list.

**See also:** `coop`, `index_of`, `invites_at`, `members`, `merge`, `project_fraction`

### `kinds`

*server/objectives.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, description, steps: [{text, count}], repeatable, owner}

### `give`

*server/objectives.gd*

GDScript: `give(player, objective_name: String) -> bool`

Gives it to a player. Returns false if they already have it, have finished one that cannot be
repeated, or are carrying as many as they may.

**See also:** `add_modifier`, `exists`, `give_overflow`, `is_alive`, `set_sitting`, `sync`

### `advance`

*server/objectives.gd*

GDScript: `advance(player, objective_name: String, amount := 1) -> bool`

Counts `amount` towards the step they are on. When the step is filled it moves on, and when the
last one is filled the whole thing is done - which is `objective_done`, where a mod hands out
whatever it thinks the reward is. The engine has no idea what a reward would be.

**See also:** `advance`, `biome_at`, `give`, `has_flag`, `is_night`, `play_sound_to`

### `abandon`

*server/objectives.gd*

GDScript: `abandon(player, objective_name: String) -> bool`

Gives up on one. Kept separate from finishing it, because "I am not doing this" and "I did this"
are different things and a mod may want to say so.

**See also:** `sync`

### `sync`

*server/objectives.gd*

GDScript: `sync(player) -> void`

Sends the task list to whoever it belongs to. **Pushed on every change rather than asked for**, the
way the tutorial tracker is: a list you have to request is a list that is wrong for as long as
nobody asked, and the one moment it matters is the moment it changed.

**See also:** `active_for`, `refresh`, `state_of`, `view`

### `active_for`

*server/objectives.gd*

GDScript: `active_for(player) -> Array`

What they are doing now: [{name, display_name, step, of, text, progress, needed}].

### `finished`

*server/objectives.gd*

GDScript: `finished(player, objective_name: String) -> int`

How many times they have finished it (0 if never).

### `kinds`

*server/shops.gd*

GDScript: `kinds := {}  (property)`

Name -> {name, display_name, offers: [...], owner}

### `problem`

*server/shops.gd*

GDScript: `problem := ""  (property)`

Why the last buy failed, in words a child can read.

### `left_of`

*server/shops.gd*

GDScript: `left_of(shop_name: String, index: int) -> int`

How many of this offer are left, refilling first if it is time. Unlimited offers say -1.

### `offers_for`

*server/shops.gd*

GDScript: `offers_for(player, shop_name: String) -> Array`

What a player would see: [{index, item, name, count, price, ledger, cost, sells, left, can}].

**See also:** `count_of`, `has_room`, `left_of`, `value_of`

### `trade`

*server/shops.gd*

GDScript: `trade(player, shop_name: String, index: int) -> bool`

Does the trade. Everything is checked before anything moves, so a failure halfway leaves a player
with neither the coin nor the goods - which has happened in enough games to be worth the care.

**See also:** `count_of`, `give`, `has_room`, `left_of`, `spend`, `take`

### `show`

*server/shops.gd*

GDScript: `show(player, shop_name: String) -> bool`

Opens the shop panel. Drawn by the engine so every shop in every mod looks the same, which is the
whole reason this is a capability and not thirty lines in a mod.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `heat`, `hold_fraction`

### `on_action`

*server/shops.gd*

GDScript: `on_action(player, action: String) -> bool`

A button was pressed. Returns true if it was one of ours.

**See also:** `band_center`, `band_half`, `game_time`, `gauge`, `give`, `heat`

### `to_saved`

*server/shops.gd*

GDScript: `to_saved() -> Dictionary`

Stock is saved: a village whose shelves refill every restart is a village worth restarting for.

### `levels`

*server/signals.gd*

GDScript: `levels := {}  # Vector3i -> int  (property)`

Where a level is, and how strong. Only cells above zero are kept, so an unpowered world costs nothing.

### `sources`

*server/signals.gd*

GDScript: `sources := {}  # Vector3i -> int  (property)`

Levels a mod has put on particular blocks (a lever that is on). Block types that always emit are
read from the registry instead, so a thousand torches cost no memory.

### `origins`

*server/signals.gd*

GDScript: `origins := {}  # Vector3i -> Vector3i  (property)`

Which source each powered cell's level came from. A gate must not hear its own voice come back to it
through the wire it is driving - which is not the same as not hearing its own cell, and cost an
afternoon to tell apart. (2026-09-19)

### `handlers`

*server/signals.gd*

GDScript: `handlers := {}  (property)`

Block id -> {handler, owner}: told when the level arriving at one of these changes.

### `register`

*server/signals.gd*

GDScript: `register(block: int, handler: Callable, owner := "engine") -> void`

Tells `handler(ctx)` when the level reaching a block of this type changes.
ctx = {position, block, level, previous, realm}.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `set_source`

*server/signals.gd*

GDScript: `set_source(pos: Vector3i, level: int) -> void`

Makes the block at `pos` emit `level` (0 stops it). This is how a lever, a plate or a mod's own
gate speaks: the engine never learns what any of them are.

**See also:** `get_block_v`, `key_name`, `node_key`, `reaching`, `record`

### `level_at`

*server/signals.gd*

GDScript: `level_at(pos: Vector3i) -> int`

The level in a cell: what a carrier there is carrying.

### `reaching`

*server/signals.gd*

GDScript: `reaching(pos: Vector3i) -> int`

The strongest level arriving at a block **from elsewhere** - what a receiver acts on.

Deliberately not counting what the block itself emits. A gate that heard its own output would
oscillate for ever the moment a mod wrote the most obvious thing there is - "emit when nothing
reaches me" - and the first version of this did exactly that, with a stack overflow to show for it.
A thing does not hear itself speak.

**See also:** `get_block_v`

### `block_changed`

*server/signals.gd*

GDScript: `block_changed(pos: Vector3i, old: int, block: int) -> void`

A block was placed or broken: the network around it may be a different shape now.

**See also:** `at_block`, `chunk_coord_at`, `cut`, `get_block_v`, `index`, `reaching`

### `unload_chunk`

*server/signals.gd*

GDScript: `unload_chunk(coord: Vector2i) -> void`

Forgets a chunk's levels. Nothing is written: a level follows from the sources, and they are saved
with the blocks, so it is worked out again when somebody comes back.

**See also:** `chunk_coord_at`, `chunk_coord_of`, `serialize_chunk`

### `register_tutorial`

*server/tutorials.gd*

GDScript: `register_tutorial(id: String, def: Dictionary, qualify: Callable) -> bool`

JavaScript: `api.registerTutorial(id, def, qualify)`

`qualify(name) -> String` turns local names into full ones.

**See also:** `add_handler`, `announce`, `qualified`

### `remove_owner`

*server/tutorials.gd*

GDScript: `remove_owner(owner: String) -> void`

Drops a mod's tutorials and tips (before it registers them again on reload). Players in one of its
tutorials keep their place if the tutorial comes back with enough steps.

### `revalidate`

*server/tutorials.gd*

GDScript: `revalidate() -> void`

Checks players' tutorial progress after a reload, and resends their trackers.

**See also:** `state_of`, `sync`

### `to_network`

*server/tutorials.gd*

GDScript: `to_network() -> Array`

Tutorials in order: [{id, title, description, steps}] for clients.

### `state_of`

*server/tutorials.gd*

GDScript: `static state_of(p) -> Dictionary`

{active, step, progress, done: {id: true}, stopped: {id: true}, tips: {id: true}, tips_off}

### `on_join`

*server/tutorials.gd*

GDScript: `on_join(p) -> void`

After joining (or switching to survival): resumes the active tutorial or starts the first
auto-start one not yet done or stopped.

**See also:** `start`, `state_of`, `sync`

### `stop`

*server/tutorials.gd*

GDScript: `stop(p) -> void`

Stops the active tutorial (it will not start by itself again).

**See also:** `close`, `state_of`, `step`, `sync`

### `advance`

*server/tutorials.gd*

GDScript: `advance(p, skipped := false) -> void`

Completes the current step (skip, or a "manual" goal done by a mod).

**See also:** `advance`, `biome_at`, `give`, `has_flag`, `is_night`, `play_sound_to`

### `view`

*server/tutorials.gd*

GDScript: `view(p) -> Dictionary`

The tracker the client draws: {} when no tutorial is running.

**See also:** `coop`, `index_of`, `invites_at`, `members`, `merge`, `project_fraction`

### `show_tip`

*server/tutorials.gd*

GDScript: `show_tip(p, id: String) -> bool`

JavaScript: `api.showTip(p, id)`

Shows a tip now (registered id), even if it was seen before.

**See also:** `icon_of`, `key_name`, `library`, `node_key`, `qualified`, `state_of`

### `store`

*server/ugc.gd*

GDScript: `store := {}  (property)`

id -> {manifest, status, reason, uploaded_by (player id), uploaded_at, size}

**See also:** `is_valid_hash`, `open`, `sha256`

### `blocked`

*server/ugc.gd*

GDScript: `blocked := {}  (property)`

Content ids refused for good (removed creations), id -> reason.

### `banned_creators`

*server/ugc.gd*

GDScript: `banned_creators := {}  (property)`

Player ids that may not upload, player id -> reason.

### `trusted`

*server/ugc.gd*

GDScript: `trusted := {}  (property)`

Player ids whose uploads are approved at once under "trusted".

### `revision`

*server/ugc.gd*

GDScript: `revision := 0  (property)`

Goes up whenever creations, reports, trust or bans change (the dashboard reloads its list).

### `can_wear`

*server/ugc.gd*

GDScript: `can_wear(p, id: String) -> bool`

Whether a player may wear a creation here.

**See also:** `get_def`, `is_approved`, `is_blocked`, `is_builtin`, `is_id`, `look`

### `ensure_registered`

*server/ugc.gd*

GDScript: `ensure_registered(ids: Array) -> void`

Registers approved creations as cosmetics so avatars can use them.

**See also:** `get_def`, `is_approved`, `is_id`, `payload`, `register`, `to_cosmetic`

### `worn_ids`

*server/ugc.gd*

GDScript: `static worn_ids(avatar) -> Array`

Creation ids worn in an avatar dictionary.

**See also:** `is_id`

### `offer`

*server/ugc.gd*

GDScript: `offer(p, manifests: Array) -> Dictionary`

A client offers creations it wears. Returns {request: [ids], status: {id: [status, reason]}}.

**See also:** `is_clean`, `is_id`

### `upload_piece`

*server/ugc.gd*

GDScript: `upload_piece(p, id: String, offset: int, total: int, bytes: PackedByteArray) -> void`

A piece of an upload. Completes (validates and stores) when the last piece arrives.

**See also:** `close`, `ensure_registered`, `is_admin`, `is_clean`, `open`, `payload_extension`

### `set_status`

*server/ugc.gd*

GDScript: `set_status(id: String, status: String, reason := "", by := "") -> bool`

Changes a creation's status (moderation). "removed" also blocks the content for good.

**See also:** `draw`, `ensure_registered`, `payload_extension`, `reapply_requested_avatar`, `save_index`, `status`

### `fetch`

*server/ugc.gd*

GDScript: `fetch(p, ids: PackedStringArray) -> void`

A client asks for creations it needs to draw (or browse).

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `library`

*server/ugc.gd*

GDScript: `library(query := {}, offset := 0, count := 48) -> Dictionary`

Approved creations others may wear, newest first: [{manifest..., uses}] filtered by kind/category/text.

### `report`

*server/ugc.gd*

GDScript: `report(p, id: String, reason: String, details := "") -> String`

A player reports a creation. Returns "" or why it was not accepted.

**See also:** `save_index`, `set_status`, `tell_moderators`

### `review_list`

*server/ugc.gd*

GDScript: `review_list(filter := "pending", text := "") -> Array`

Creations for review: filter pending | reported | approved | rejected | removed | all, newest first.

### `resolve_id`

*server/ugc.gd*

GDScript: `resolve_id(text: String) -> String`

Finds a creation by id or a unique start of it ("3f2a", "ugc:3f2a"). "" when none or ambiguous.

### `set_banned`

*server/ugc.gd*

GDScript: `set_banned(player_id: String, on: bool, reason := "", by := "") -> void`

Bans (or unbans) a creator from uploading. Banning also hides their creations (rejected); unbanning
leaves them hidden until approved again.

**See also:** `save_index`, `set_status`

### `add_chapter`

*shared/guide_registry.gd*

GDScript: `add_chapter(def: Dictionary) -> bool`

Adds a guidebook chapter. False if it has no id, or one is already registered under that id.

### `add_page`

*shared/guide_registry.gd*

GDScript: `add_page(def: Dictionary) -> bool`

Adds a page to a chapter. False if it has no id, or one is already registered under that id.

### `remove_owner`

*shared/guide_registry.gd*

GDScript: `remove_owner(owner: String) -> void`

Drops everything a mod registered (before it registers again on reload).

### `clear`

*shared/guide_registry.gd*

GDScript: `clear() -> void`

Empties the book. The client calls this before loading the server's copy, so a second world does
not inherit the first one's pages.

### `get_page`

*shared/guide_registry.gd*

GDScript: `get_page(id: String) -> Dictionary`

One page, or `{}` if there is no such page.

### `get_chapter`

*shared/guide_registry.gd*

GDScript: `get_chapter(id: String) -> Dictionary`

One chapter, or `{}` if there is no such chapter.

### `chapter_pages`

*shared/guide_registry.gd*

GDScript: `chapter_pages(chapter_id: String) -> Array`

Pages of a chapter in order.

### `sorted_chapters`

*shared/guide_registry.gd*

GDScript: `sorted_chapters() -> Array`

Chapters in the order a player should see them: by `order`, then by title so the result is stable
when two chapters share one.

### `page_text`

*shared/guide_registry.gd*

GDScript: `static page_text(page: Dictionary) -> String`

Plain searchable text of a page (title, keywords and text blocks).

### `to_network`

*shared/guide_registry.gd*

GDScript: `to_network() -> Dictionary`

The whole book as the client receives it.

### `load_network`

*shared/guide_registry.gd*

GDScript: `load_network(data) -> void`

Replaces the client's book with the server's.


## Mods, loading and validation

### `index`

*client/menu/mod_browser.gd*

GDScript: `index: Array = []  (property)`

What the site offers, from the last fetch (or the cached copy from last time).

### `busy`

*client/menu/mod_browser.gd*

GDScript: `busy := false  (property)`

True while a fetch or an install is running, so the screen can disable its buttons.

### `refresh`

*client/menu/mod_browser.gd*

GDScript: `refresh(force := false) -> void`

Fetches the mod index. `force` asks again even if it was already fetched this session.

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `install`

*client/menu/mod_browser.gd*

GDScript: `install(entry: Dictionary) -> void`

Downloads and installs one mod, and anything it needs that is missing. `entry` is a row from the index.

**See also:** `close`, `download`, `install_package`, `installed`, `installed_path`, `installer`

### `remove`

*client/menu/mod_browser.gd*

GDScript: `remove(id: String, mod_name := "") -> void`

Takes a mod off this computer.

### `installed`

*client/mod_catalog.gd*

GDScript: `static installed() -> Array`

What the player has, as [{id, name, version, description, game, depends, dir, removable, kind}].

**See also:** `discover`, `is_removable`, `kind_of`, `search_dirs`

### `kind_of`

*client/mod_catalog.gd*

GDScript: `static kind_of(manifest: Dictionary) -> String`

What a mod is for, so the screen can group them: a game to play, an add-on for a game, a library other
mods build on, or an example to read.

### `is_removable`

*client/mod_catalog.gd*

GDScript: `static is_removable(dir: String) -> bool`

True for a mod the player installed themselves (the only ones Remove may touch).

**See also:** `user_mods`

### `cached_index`

*client/mod_catalog.gd*

GDScript: `static cached_index() -> Dictionary`

The index as it was last fetched ({version, mods: [...]}), or {} the first time.

### `index_url`

*client/mod_catalog.gd*

GDScript: `static index_url() -> String`

Where the mod index lives: next to the update manifest, on the address built into the client.

**See also:** `manifest_url`

### `read_index`

*client/mod_catalog.gd*

GDScript: `static read_index(text: String) -> Array`

Checks an index and returns its entries as [{id, name, version, description, url, sha256, size, kind}],
dropping anything malformed or from an address the client does not trust.

**See also:** `url_allowed`

### `cache_index`

*client/mod_catalog.gd*

GDScript: `static cache_index(text: String) -> void`

Keeps an index for next time (so the screen works offline). Silently does nothing if it cannot.

**See also:** `close`, `open`

### `merge`

*client/mod_catalog.gd*

GDScript: `static merge(installed_mods: Array, index: Array) -> Array`

The installed mods and the index as one list for the screen: [{..., state}], where state is
"installed" (nothing to do), "update" (a newer version is offered), or "available" (not installed).

**See also:** `compare`, `sha256`

### `install_package`

*client/mod_catalog.gd*

GDScript: `static install_package(bytes: PackedByteArray, expect_id := "") -> String`

Unpacks a downloaded mod zip into user://mods/<id>/, replacing an older copy. Returns "" or the problem.
The bytes must already have been checked against the index's sha256 (see Updater.verify).

**See also:** `close`, `download`, `install_file`, `open`

### `install_file`

*client/mod_catalog.gd*

GDScript: `static install_file(package_path: String, expect_id := "") -> String`

Unpacks a mod zip from a path into user://mods/<id>/. Returns "" or the problem.

**See also:** `open`, `read_manifest`, `unpack`, `user_mods`

### `remove`

*client/mod_catalog.gd*

GDScript: `static remove(id: String) -> String`

Takes an installed mod off this computer. Only mods in user://mods may be removed - the ones inside the
app come back with every update anyway. Returns "" or the problem.

### `needed_by`

*client/mod_catalog.gd*

GDScript: `static needed_by(id: String, installed_mods: Array) -> Array`

Which installed mods need `id`, so the screen can warn before it is removed.

### `missing_dependencies`

*client/mod_catalog.gd*

GDScript: `static missing_dependencies(entry: Dictionary, installed_mods: Array, index: Array) -> Array`

The mods that have to be installed before `entry` can run, from what the index offers.

### `to_js`

*server/js_mod.gd*

GDScript: `to_js(value)`

Engine values -> JSON-safe values for the prelude.

### `setup`

*server/mod.gd*

GDScript: `setup(_api) -> void`

Called once at server start, after all dependencies have run their setup.
Register blocks, event handlers, commands and world hooks through `api` (see mod_api.gd).

### `cache_dir`

*server/mod_loader.gd*

GDScript: `static cache_dir() -> String`

Unpacked mods and the player's own mods folder. QW_USER_DIR moves both, so a test run does not
unpack its fixtures into the player's folder.

### `search_dirs`

*server/mod_loader.gd*

GDScript: `static search_dirs(configured: PackedStringArray) -> PackedStringArray`

Where mods are searched, highest priority first: configured folders, a `mods` folder next to the
executable (exported builds ship mods there as plain files, since exports would otherwise repack
the raw textures and models the server streams to clients), mods created in game (user://mods), then
the project's own res://mods.

**See also:** `user_mods`

### `creation_dir`

*server/mod_loader.gd*

GDScript: `static creation_dir() -> String`

Where the game's "Create a mod" puts new mods: the project's mods folder when running from the editor
or source, otherwise user://mods.

**See also:** `user_mods`

### `discover`

*server/mod_loader.gd*

GDScript: `static discover(dirs: PackedStringArray) -> Dictionary`

Returns id -> manifest for every valid mod folder or package in `dirs`. Manifests gain `dir` (and
`package` for zips).

**See also:** `open`, `read_manifest`, `unpack`

### `read_manifest`

*server/mod_loader.gd*

GDScript: `static read_manifest(mod_dir: String) -> Dictionary`

Reads and normalizes <dir>/mod.json. Returns the manifest, or {error}.

**See also:** `parse`, `parse_dependencies`

### `parse_dependencies`

*server/mod_loader.gd*

GDScript: `static parse_dependencies(value) -> Array`

Dependencies as [{id, version}] from ["id", "id@range", {id, version}] or {id: range}.

**See also:** `order`

### `resolve`

*server/mod_loader.gd*

GDScript: `static resolve(requested: PackedStringArray, available: Dictionary) -> Array`

Returns manifests in load order (dependencies first), or an empty Array on error (see last_errors).

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `unpack`

*server/mod_loader.gd*

GDScript: `static unpack(package_path: String) -> Dictionary`

Unpacks a mod package into the cache (once per package content). Returns {dir} or {error}.

**See also:** `cache_dir`, `close`, `finish`, `open`, `start`

### `pack`

*server/mod_loader.gd*

GDScript: `static pack(mod_dir: String, zip_path: String) -> Error`

Writes a mod folder into a .zip (mod.json at the root). Skips Godot's import metadata. Returns OK.

**See also:** `close`, `open`

### `reload`

*server/mod_reload.gd*

GDScript: `reload(mod_id: String) -> Dictionary`

Re-runs a mod's setup. Returns {ok, mod, ms, notes: [String], error}.

**See also:** `after_mod_reload`, `begin_reload`, `close`, `drain`, `end_reload`, `forget`

### `reload_all`

*server/mod_reload.gd*

GDScript: `reload_all() -> Array`

Reloads every mod in load order (dependencies first).

**See also:** `place`, `reload`

### `register`

*server/mod_settings.gd*

GDScript: `register(mod_id: String, schema: Dictionary) -> void`

Declares a mod's settings. A malformed entry is dropped with a warning rather than taken as a value,
so a typo in a mod cannot stop the server from starting.

**See also:** `add_handler`, `category`, `clean_color`, `clean_def`, `clean_effects`, `clean_food`

### `get_value`

*server/mod_settings.gd*

GDScript: `get_value(mod_id: String, key: String)`

The value in force for a mod's setting: its default until a file or an admin changed it. null when the
mod never declared it.

### `set_value`

*server/mod_settings.gd*

GDScript: `set_value(mod_id: String, key: String, value) -> String`

Changes one setting and saves it with the world. Returns "" or why it was refused; tells the mod
through `settings_changed` so it can react without a restart.

**See also:** `describe`, `drive_changed`, `get_value`, `level_for`, `qualified`, `report_error`

### `reset`

*server/mod_settings.gd*

GDScript: `reset(mod_id: String, key: String) -> String`

Puts a setting back to its default (and to whatever the data folder's file says).

**See also:** `describe`, `drive_changed`, `get_value`, `qualified`, `to_saved`

### `list`

*server/mod_settings.gd*

GDScript: `list(mod_id := "") -> Array`

Every setting of every mod (or one mod), for the admin screen and /modsettings:
[{mod, key, type, label, help, value, default, changed, ...}], in a stable order.

**See also:** `count`, `get_value`, `is_id`, `open`, `read_meta`

### `mods`

*server/mod_settings.gd*

GDScript: `mods() -> Array`

Ids of the mods that have settings, in load order.

### `describe`

*server/mod_settings.gd*

GDScript: `static describe(entry: Dictionary) -> String`

What a setting accepts, for an error message or a tooltip.

**See also:** `kind_of`

### `load_sources`

*server/mod_settings.gd*

GDScript: `load_sources(meta: Dictionary, data_dir: String, override := "") -> void`

Reads the values a host set outside the game, before the mods load, so a mod can read its own settings
while it is still starting up. `override` is a path to a JSON file or the JSON itself (--mod-settings).

**See also:** `describe`, `drive_changed`, `merge`, `qualified`

### `to_saved`

*server/mod_settings.gd*

GDScript: `to_saved() -> Dictionary`

What goes into world.json: the values an admin set, untouched for mods that are not loaded now.

### `create`

*server/mod_templates.gd*

GDScript: `static create(parent_dir: String, options: Dictionary) -> Dictionary`

options: id, name, language ("gdscript" | "javascript"), kind ("addon" | "game"), author, description.
Returns {ok, dir, files: [relative paths], error}.

**See also:** `broadcast_entity_event`, `close`, `create`, `exists`, `heading`, `id_for`

### `id_from_name`

*server/mod_templates.gd*

GDScript: `static id_from_name(display_name: String) -> String`

A valid id from a display name ("My Cool Mod" -> "my_cool_mod").

### `validate`

*server/mod_validator.gd*

GDScript: `static validate(mod_dir: String, parent: Node, search_dirs := PackedStringArray()) -> Dictionary`

Every check. Returns {mod, ok, issues: [...], counts: {error, warning, hint}}.

**See also:** `check_files`, `check_manifest`, `check_references`, `check_scripts`, `check_structures`, `check_unused_files`

### `check_running`

*server/mod_validator.gd*

GDScript: `static check_running(server, mod_id: String) -> Dictionary`

The checks that need no fresh load, on a running server.

**See also:** `check_files`, `check_manifest`, `check_references`, `sorted_errors`

### `report`

*server/mod_validator.gd*

GDScript: `static report(result: Dictionary) -> PackedStringArray`

Human-readable report lines.

**See also:** `save_index`, `set_status`, `tell_moderators`

### `check_scripts`

*server/mod_validator.gd*

GDScript: `static check_scripts(mod_dir: String) -> Array`

Compiles every GDScript in the mod (JavaScript is checked by loading it).

**See also:** `open`, `reload`

### `check_unused_files`

*server/mod_validator.gd*

GDScript: `static check_unused_files(server, mod_dir: String, manifest: Dictionary) -> Array`

Files in the mod folder that nothing loads (not a script, data file or registered asset).

**See also:** `open`

### `declared`

*server/sources.gd*

GDScript: `declared := {}  (property)`

Sources a mod declared: item id -> [{kind, from, detail}].

### `declare`

*server/sources.gd*

GDScript: `declare(item_id: int, source: Dictionary) -> bool`

Adds a source nothing could infer. `detail` is shown to a player, so write it as a sentence.

### `of_item`

*server/sources.gd*

GDScript: `of_item(item_id: int) -> Array`

Everywhere `item_id` comes from, most likely first. Always returns an Array.

**See also:** `sources_of`, `table_for_block`, `table_for_entity`

### `parse`

*shared/semver.gd*

GDScript: `static parse(text: String) -> Array`

[major, minor, patch, prerelease] or [] when not a version.

**See also:** `count`

### `compare`

*shared/semver.gd*

GDScript: `static compare(a: String, b: String) -> int`

-1, 0 or 1.

**See also:** `parse`

### `satisfies`

*shared/semver.gd*

GDScript: `static satisfies(version: String, range_text: String) -> bool`

Whether `version` satisfies `range_text`.

**See also:** `parse`

### `range_error`

*shared/semver.gd*

GDScript: `static range_error(range_text: String) -> String`

Whether a range string can be understood at all ("" when fine, else the problem).

**See also:** `parse`

### `members`

*shared/tag_registry.gd*

GDScript: `members := {}  (property)`

Tag name -> {member name: true}. Members are kept by *name* rather than by id because ids move
whenever a mod is added, and a tag outlives the run that defined it.

### `add`

*shared/tag_registry.gd*

GDScript: `add(tag_name: String, names: Array) -> int`

Adds names to a tag, creating it if need be. Returns the number actually added.

### `names_in`

*shared/tag_registry.gd*

GDScript: `names_in(tag_name: String) -> Array`

The names in a tag, or an empty array. A tag nobody defined is empty rather than an error: a mod
that works with another one when it is installed should not have to guard every call.

### `has`

*shared/tag_registry.gd*

GDScript: `has(tag_name: String, name: String) -> bool`

Whether a thing is in a tag. This is the cheap question - `tags_of` walks every tag, this does not.

### `exists`

*shared/tag_registry.gd*

GDScript: `exists(tag_name: String) -> bool`

Whether anything has ever been put in this tag. A tag nobody filled is absent, not empty.

### `tags_of`

*shared/tag_registry.gd*

GDScript: `tags_of(name: String) -> Array`

JavaScript: `api.tagsOf(name)`

Every tag something is in. Walks all of them, so it is for tools and questions rather than for
anything on the hot path.

**See also:** `qualified`

### `namespaces`

*shared/tag_registry.gd*

GDScript: `namespaces() -> Array`

The namespaces tags have been written for ("base", "cherry"), for warning about ones that no
installed mod owns.


## Saving, network and protocol

### `check_and_pin`

*net/known_servers.gd*

GDScript: `static check_and_pin(endpoint: String, certificate_pem: String) -> String`

Pins `certificate_pem` for `endpoint` if nothing is pinned yet. Returns "" when the certificate
matches (or was just pinned), otherwise a message explaining the mismatch.
PEM text is compared directly (X509Certificate.save_to_string() adds a NUL character).

**See also:** `open`, `path_for`

### `server`

*net/net.gd*

GDScript: `server: Node = null  (property)`

Set by GameServer when running as a server.

### `client`

*net/net.gd*

GDScript: `client: Node = null  (property)`

Set by GameClient when running as a client.

### `pin_servers`

*net/net.gd*

GDScript: `pin_servers := true  (property)`

Client: pin server certificates (load-test bots turn this off).

### `create_server`

*net/net.gd*

GDScript: `create_server(port: int, max_players: int, tls_key: CryptoKey, tls_cert: X509Certificate, cert_pem: String) -> Error`

`tls_key`/`tls_cert`: the server's identity. Traffic is always encrypted with DTLS.

**See also:** `close`

### `create_client`

*net/net.gd*

GDScript: `create_client(address: String, port: int, protocol_override := -1) -> Error`

Connects over DTLS. If this server's certificate was seen before, the DTLS handshake verifies it,
so an impostor cannot complete the connection; the first connection trusts and pins it.

**See also:** `close`, `load_certificate`

### `load_or_create_server_identity`

*net/net.gd*

GDScript: `static load_or_create_server_identity(dir: String) -> Array`

Loads the server's DTLS identity from `dir`, creating a self-signed one on first start.
Returns [CryptoKey, X509Certificate, certificate PEM text].

**See also:** `load`, `save`

### `peer_rtt_ms`

*net/net.gd*

GDScript: `peer_rtt_ms(peer_id: int) -> int`

Server side: a client's round-trip time in milliseconds (0 if unknown).

### `code`

*server/hub_announcer.gd*

GDScript: `code := ""  (property)`

The hub's invite code for this server ("QW-ABC-123"), once listed.

### `problem`

*server/hub_announcer.gd*

GDScript: `problem := ""  (property)`

"" while fine, else why the last announce failed (shown to admins and in the log once per change).

### `leave`

*server/hub_announcer.gd*

GDScript: `leave() -> void`

Asks the hub to drop the listing (best effort, on shutdown: a blocking request with a short timeout).

**See also:** `allowed`, `close`, `finish`, `get_block`, `gone`, `send_to_realm`

### `transfer`

*server/transfers.gd*

GDScript: `transfer(p, target: String, options := {}) -> String`

Sends a player to another server. options: {arrival, data (a small Dictionary for mods), reason}.
Returns "" or why not.

**See also:** `kick`, `make`, `pack_inventory`, `save_items`, `save_player`, `schedule`

### `pack_inventory`

*server/transfers.gd*

GDScript: `pack_inventory(p) -> Dictionary`

Items by name (ids differ between servers): see ServerPlayer.save_items.

**See also:** `save_items`

### `unpack_inventory`

*server/transfers.gd*

GDScript: `unpack_inventory(p, packed) -> Array`

Puts a carried inventory into the player's; returns the names of items this server does not have.

**See also:** `load_items`

### `settle_escrow`

*server/transfers.gd*

GDScript: `settle_escrow(p, arrived_by_ticket: bool) -> void`

A player who joined without a transfer ticket but has a travelling inventory held here: give it back.
Arriving with a ticket (from anywhere in the network) drops the held copy instead.

**See also:** `send_message`, `sync_inventory`, `unpack_inventory`

### `accept`

*server/transfers.gd*

GDScript: `accept(ticket: String, signature: String, player_id: String) -> Dictionary`

A joining player's ticket, checked once they have proven their identity. Returns {entry, data} for an
accepted ticket, or {error}.

**See also:** `check`, `verify`

### `arrival_position`

*server/transfers.gd*

GDScript: `arrival_position(accepted: Dictionary) -> Vector3`

Where an arriving player appears: the ticket's named arrival point, or Vector3.INF (their usual place).

### `arrive`

*server/transfers.gd*

GDScript: `arrive(p, accepted: Dictionary) -> void`

After an arriving player spawned: give what they carried and tell mods.

**See also:** `send_message`, `sync_health`, `sync_inventory`, `unpack_inventory`

### `portal_at`

*server/transfers.gd*

GDScript: `portal_at(position: Vector3, into = null) -> Dictionary`

The portal settings of a portal block at the player's feet or body, or {}.
The portal a player is standing in, or {}. Its block data says where it goes: `server` for another
machine, or `realm` for another world on this one. Both are portals to a player, so both are read
here rather than growing a second block with a second timer that feels slightly different.

**See also:** `get_block_data`, `get_block_v`

### `encode`

*shared/invite_code.gd*

GDScript: `static encode(address: String, port: int) -> String`

The code for an IPv4 address, or "" when the address is not IPv4.

### `share_text`

*shared/invite_code.gd*

GDScript: `static share_text(address: String, port: int) -> String`

What someone shares: an invite code when possible, else "address:port".

**See also:** `encode`

### `parse`

*shared/invite_code.gd*

GDScript: `static parse(text: String) -> Dictionary`

{address, port} from a code or "host[:port]" text, or {error}.

**See also:** `count`

### `local_address`

*shared/invite_code.gd*

GDScript: `static local_address() -> String`

The first private IPv4 address of this computer (to invite people on the same network), or "".

### `enabled`

*shared/native.gd*

GDScript: `static enabled() -> bool`

Whether the extension is loaded. Kept as a function because a handful of callers want to *report*
it (the server's startup line, the benchmark's labels) rather than depend on it.

**See also:** `level_of`

### `create`

*shared/native.gd*

GDScript: `static create(native_class: StringName) -> Object`

A new instance of a native class. Never null in a working build; says what is wrong when it is.

**See also:** `broadcast_entity_event`, `close`, `create`, `exists`, `heading`, `id_for`

### `key_id`

*shared/transfer_ticket.gd*

GDScript: `static key_id(key: CryptoKey) -> String`

The id servers use for each other: the first 32 hex characters of SHA-256 over the public key PEM.

**See also:** `pem_id`

### `make`

*shared/transfer_ticket.gd*

GDScript: `static make(source_key: CryptoKey, fields: Dictionary) -> Dictionary`

{ticket: JSON text, signature: base64}

**See also:** `content_id`, `finish`, `key_id`, `sign`, `start`

### `verify`

*shared/transfer_ticket.gd*

GDScript: `static verify(ticket: String, signature: String, trusted: Dictionary) -> Dictionary`

Checks a ticket's signature and shape. `trusted`: source id -> anything truthy.
Returns {ok: true, data} or {ok: false, error}. Expiry, destination and replay are the caller's checks
too (see `check`), since they need the destination's own details.

**See also:** `finish`, `pem_id`, `start`

### `check`

*shared/transfer_ticket.gd*

GDScript: `static check(data: Dictionary, player_id: String, own_id: String, now: int) -> String`

The destination's checks after `verify`: the logged-in player, this server, time.

**See also:** `compare`, `fetch`, `installed_path`, `manifest_url`, `parse`, `platform`

### `path`

*shared/user_paths.gd*

GDScript: `static path(relative: String) -> String`

`relative` is what would have followed `user://`, e.g. "cache/assets" or "crafting_pins.cfg".

### `redirected`

*shared/user_paths.gd*

GDScript: `static redirected() -> bool`

Whether this process has been moved out of the player's folder. Tests assert on it, because the whole
point is that it is true while they run and false while somebody is playing.


## Dev tools and logging

### `current_mod`

*server/dev_log.gd*

GDScript: `current_mod := ""  (property)`

The mod whose setup() is running, if any. Errors raised while it is set belong to it.

### `open_file`

*server/dev_log.gd*

GDScript: `open_file(save_dir: String) -> void`

Opens <save_dir>/logs/latest.log, moving the previous one aside.

**See also:** `close`, `open`, `set_look`

### `mod_of_file`

*server/dev_log.gd*

GDScript: `mod_of_file(file: String) -> String`

Which mod a script file belongs to ("" when none).

### `add`

*server/dev_log.gd*

GDScript: `add(level: String, source: String, message: String, extra := {}, echo := true) -> Dictionary`

Adds a message. Returns the entry, or {} when filtered out.
`echo` prints it to the console (off for lines that were captured from the console already).

### `report_error`

*server/dev_log.gd*

GDScript: `report_error(source: String, message: String, file := "", line := 0, stack := [], level := "error") -> Dictionary`

Records an error (grouped with identical ones) and logs it once per group.

### `recent`

*server/dev_log.gd*

GDScript: `recent(count := 50, source := "", min_level := "debug", text := "") -> Array`

Recent entries, newest last: filtered by source ("" = all), minimum level and text.

### `drain`

*server/dev_log.gd*

GDScript: `drain() -> void`

Moves what Godot reported (from any thread) into the log. Call every frame on the main thread.

**See also:** `mod_of_file`, `report_error`, `unlock`

### `viewers`

*server/dev_tools.gd*

GDScript: `viewers := {}  (property)`

peer id -> {channels: {name: true}, inspect: {...target}, trace_filter: String, log_after: int}

### `timed`

*server/dev_tools.gd*

GDScript: `timed(owner: String, category: String, callable: Callable, args := [])`

Calls `callable` with `args`, timing it for `owner`.

**See also:** `record`

### `perf`

*server/dev_tools.gd*

GDScript: `perf() -> Array`

[{owner, category, calls, ms_per_s, avg_ms, max_ms}] over the last WINDOWS seconds, slowest first,
plus owner totals ({owner, category: "total"}).

### `dispatch`

*server/dev_tools.gd*

GDScript: `dispatch(event: String, handlers: Array, payload: Dictionary) -> Dictionary`

Emits `payload` to `handlers` ([priority, callable, owner]), timing each handler and recording the
event when tracing. Returns the payload.

**See also:** `describe`, `record`

### `describe`

*server/dev_tools.gd*

GDScript: `describe(value, key := "", depth := 0)`

A JSON-friendly copy of a value: players, entities, vectors and block/item ids become readable.

**See also:** `kind_of`

### `inspect`

*server/dev_tools.gd*

GDScript: `inspect(target: Dictionary) -> Dictionary`

target: {pos: Vector3i} | {entity: id} | {player: peer id}

**See also:** `biome_at`, `describe`, `evaluate`, `get_block_data`, `get_block_state`, `get_block_v`

### `draw`

*server/dev_tools.gd*

GDScript: `draw(owner: String, shape: Dictionary) -> void`

shape: {type: box | line | text | path | sphere, color, seconds, ...}; box {min, max} or {center, size},
line {from, to}, text {position, text}, path {points}, sphere {center, radius}.


## The client

### `last_state`

*client/admin/worlds_panel.gd*

GDScript: `last_state := {}  (property)`

What the server last sent (also read by tests).

### `voxels`

*client/avatar/accessory_builder.gd*

GDScript: `voxels := {}  (property)`

Vector3i (skin pixels from the attachment point) -> "#rrggbb".

### `apply_at`

*client/avatar/accessory_builder.gd*

GDScript: `apply_at(cell: Vector2i, erase := false) -> void`

Applies the current tool at a grid cell (x, z) of the current layer.

**See also:** `begin_stroke`, `set_color`

### `build_boxes`

*client/avatar/accessory_builder.gd*

GDScript: `build_boxes() -> Array`

Merges voxels into boxes (greedy: along x, then z, then y, same color only).

### `load_boxes`

*client/avatar/accessory_builder.gd*

GDScript: `load_boxes(boxes: Array) -> void`

Turns boxes back into voxels (for editing a saved accessory).

### `parts`

*client/avatar/avatar.gd*

GDScript: `parts := {}  (property)`

Parts by name (Node3D pivots) and attachment points by name.

### `sleep_yaw`

*client/avatar/avatar.gd*

GDScript: `sleep_yaw = null  (property)`

Yaw (radians) while lying in a bed with the head that way, or null when not sleeping.

### `set_armor`

*client/avatar/avatar.gd*

GDScript: `set_armor(texture: Texture2D) -> void`

Armor shell texture in the skin layout, or null to hide armor.

### `set_held`

*client/avatar/avatar.gd*

GDScript: `set_held(node: Node3D, look := {}) -> void`

Replaces the item in the right hand (null = empty hand). `look`: {glow, trail, held} of the stack.

### `set_accessories`

*client/avatar/avatar.gd*

GDScript: `set_accessories(list: Array) -> void`

Adds accessory nodes at attachment points: [{attach, node}]. Replaces previous accessories.

### `set_sleeping`

*client/avatar/avatar.gd*

GDScript: `set_sleeping(head: Array) -> void`

Lies down in a bed: `head` is the [x, z] direction from the feet to the pillow, or [] to get up.

### `set_armor_glow`

*client/avatar/avatar.gd*

GDScript: `set_armor_glow(glow: Dictionary) -> void`

Glowing armor: {color, energy} lights up the armor texture in its own colors, and `light` (a radius
in blocks) makes it light the world around the wearer too. {} turns both off.

**`light` arrived here for weeks and was thrown away.** The server already computed it from the
worn stack's data and shipped it in `appearance.armor_glow`; this function read `color` and
`energy` and dropped the rest on the floor, so armour could look lit and never lit anything. Held
items have made a real light out of the same field all along (avatar/item_mesh.gd). (2026-09-24)

### `animate`

*client/avatar/avatar.gd*

GDScript: `animate(delta: float, velocity: Vector3, on_ground: bool, pitch: float) -> void`

Poses the body. `velocity` in blocks/s, `pitch` in radians (look up positive). Positive x rotation
swings a hanging limb forward.

**See also:** `bites`, `gulp`, `lift`

### `avatar`

*client/avatar/avatar_editor.gd*

GDScript: `avatar := {}  (property)`

The avatar being edited (Cosmetics data).

### `owned`

*client/avatar/avatar_editor.gd*

GDScript: `owned := PackedStringArray()  (property)`

Server cosmetics the player owns (in game).

### `creations`

*client/avatar/avatar_editor.gd*

GDScript: `creations := false  (property)`

Show the player's creations and the tools to make them.

### `ugc`

*client/avatar/avatar_editor.gd*

GDScript: `ugc = null  (property)`

In game: the UgcClient, for the server library.

### `open_painter`

*client/avatar/avatar_editor.gd*

GDScript: `open_painter(id: String) -> void`

Opens the skin painter on a library skin (id) or, for "", on the current look.

**See also:** `add_to`, `apply`, `clear_cache`, `get_def`, `get_manifest`, `get_payload`

### `open_builder`

*client/avatar/avatar_editor.gd*

GDScript: `open_builder(id: String) -> void`

Opens the accessory builder, empty or on a library accessory.

**See also:** `add_to`, `apply`, `clear_cache`, `get_def`, `get_manifest`, `get_payload`

### `open_library`

*client/avatar/avatar_editor.gd*

GDScript: `open_library() -> void`

Other players' creations on this server, for the category on show.

**See also:** `apply`, `fetch`, `get_def`, `in_category`, `is_blocked`, `is_builtin`

### `model_bytes`

*client/avatar/item_mesh.gd*

GDScript: `model_bytes: Callable  (property)`

asset name -> {hash, size} and a reader for downloaded bytes.

### `node_for`

*client/avatar/item_mesh.gd*

GDScript: `node_for(id: int, first_person := false, item_data := {}) -> Node3D`

A node showing the item, oriented for a hand attachment: +Y points out of the fist, -Z runs down
the forearm. With `first_person` it is instead oriented for the view model: origin at the hand in
camera space, the icon's face turned towards the camera. null for nothing.

**See also:** `get_def`, `mesh_for`

### `apply_glow`

*client/avatar/item_mesh.gd*

GDScript: `apply_glow(node: Node3D, glow: Dictionary) -> void`

Makes a held item node glow: {color, energy, light}. Additive, so pixels glow in their own colors.

### `icons`

*client/avatar/item_mesh.gd*

GDScript: `icons  (property)`

Composed icons (ItemIcons) for stacks with icon_layers; set by the client.

### `icon_image`

*client/avatar/item_mesh.gd*

GDScript: `icon_image(id: int, item_data := {}) -> Image`

The item's 2D icon as an image (composed icons included), or null for blocks and models.

**See also:** `composed`, `get_def`, `icon_of`

### `bitten_mesh`

*client/avatar/item_mesh.gd*

GDScript: `bitten_mesh(id: int, item_data: Dictionary, bites: int) -> Mesh`

The icon extruded with `bites` (0-3) bites taken out of its top-right edge, for eating. Falls back
to the normal mesh for blocks and models.

**See also:** `begin`, `icon_image`, `mesh_for`, `on`, `set_color`

### `plate_mesh`

*client/avatar/item_mesh.gd*

GDScript: `plate_mesh() -> Mesh`

A round plate to serve food on (lies in the XY plane like an icon; turn it flat where it is used).

**See also:** `begin`, `create`, `set_color`

### `images`

*client/avatar/look_builder.gd*

GDScript: `images := {}  (property)`

Asset name -> Image (server cosmetic textures).

### `read_model`

*client/avatar/look_builder.gd*

GDScript: `read_model: Callable  (property)`

Asset name -> glTF bytes (server cosmetic models).

**See also:** `get_payload`, `is_id`

### `clear_cache`

*client/avatar/look_builder.gd*

GDScript: `clear_cache() -> void`

Forgets cached skins and meshes (after cosmetics or their images change).

### `resolve`

*client/avatar/look_builder.gd*

GDScript: `static resolve(avatar: Dictionary, name_text: String) -> Dictionary`

The avatar to draw: the player's own data, or the default look for their name.

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `apply`

*client/avatar/look_builder.gd*

GDScript: `apply(target, avatar: Dictionary, name_text: String) -> void`

Dresses an Avatar node with `avatar` data (skin and accessories; armor and held items are separate).

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `skin_image`

*client/avatar/look_builder.gd*

GDScript: `skin_image(look: Dictionary) -> Image`

The composed 64x64 skin: body colors, face, then clothing layers in category order.

**See also:** `compose_skin`, `create`, `get_def`, `side_rects`

### `accessories`

*client/avatar/look_builder.gd*

GDScript: `accessories(look: Dictionary, pixel: float) -> Array`

[{attach, node}] for cosmetics with boxes or models.

**See also:** `begin`, `get_def`, `load_mesh`, `set_color`

### `side_rects`

*client/avatar/look_builder.gd*

GDScript: `static side_rects(r: Array, row_from: int, row_to: int, sides: Array) -> Array[Rect2i]`

Rectangles of a region [u, v, w, h, d] for the chosen sides, limited to rows of the side height.

### `compose_skin`

*client/avatar/skin_compositor.gd*

GDScript: `static compose_skin(colors: Dictionary, face: Image, layers: Array) -> Image`

`colors`: {head, torso, arms, legs} as Color; `face`: an 8x8 image (or null); `layers`: Images in
the skin layout drawn over the body in order.

**See also:** `create`, `unfold`

### `compose_armor`

*client/avatar/skin_compositor.gd*

GDScript: `static compose_armor(pieces: Dictionary) -> Image`

`pieces`: {slot name: Image} for visible armor. Returns null when nothing is worn.

**See also:** `create`, `unfold`

### `unfold`

*client/avatar/skin_compositor.gd*

GDScript: `static unfold(r: Array, row_from := 0, row_to := -1) -> Array[Rect2i]`

Box unfold rectangles of a region [u, v, w, h, d]; `rows` limits the side faces to part of the
height (the top face is included only from row 0, the bottom only to the last row).

### `begin_stroke`

*client/avatar/skin_painter.gd*

GDScript: `begin_stroke() -> void`

Starts an undoable change (once per stroke).

### `apply_tool`

*client/avatar/skin_painter.gd*

GDScript: `apply_tool(p: Vector2i, alt := false) -> void`

Applies the current tool at a skin pixel. Only faces of the current layer take paint.

**See also:** `begin_stroke`, `face_at`, `set_color`

### `save`

*client/avatar/skin_painter.gd*

GDScript: `save() -> Dictionary`

Validates and saves to the local library. Returns the result ({ok, error, manifest}).

**See also:** `build_boxes`, `close`, `make`, `open`, `payload_extension`, `validate`

### `set_held`

*client/avatar/view_model.gd*

GDScript: `set_held(id: int, node: Node3D, look := {}) -> void`

`node` shows the held item; `id` lets the arm dip and come back up when the item changes.

### `animate`

*client/avatar/view_model.gd*

GDScript: `animate(delta: float, speed: float, on_ground: bool, look_delta: Vector2) -> void`

`speed`: horizontal speed in blocks/s; `look_delta`: mouse movement this frame (pixels).

**See also:** `bites`, `gulp`, `lift`

### `add`

*client/beam_view.gd*

GDScript: `add(from: Vector3, to: Vector3, look: Dictionary) -> void`

look: {color, width, seconds, sag (0 for a straight beam, >0 for something hanging)}.

### `add_link`

*client/cable_view.gd*

GDScript: `add_link(link: Dictionary) -> void`

link: {id, draw ("cable" | "pipe"), a (Vector3), b (Vector3), color}

**See also:** `add_tab`, `begin`, `builtin_texture`, `creation_dir`, `curve`, `heading`

### `curve`

*client/cable_view.gd*

GDScript: `static curve(from: Vector3, to: Vector3, pipe: bool) -> PackedVector3Array`

The curve from one end to the other. A pipe is the same call with no dip.

### `receive`

*client/compass.gd*

GDScript: `receive(state: Dictionary) -> void`

`state` is what the server sends for the map: {players: [...], markers: [...]}.

**See also:** `apply`, `asset_name`, `available`, `box`, `cancel_request`, `default_avatar`

### `dir`

*client/content_cache.gd*

GDScript: `static dir() -> String`

Where cached assets live. QW_USER_DIR moves it, so a test run does not fill the player's cache.

### `save`

*client/creation_library.gd*

GDScript: `static save(manifest: Dictionary, payload: PackedByteArray) -> Dictionary`

Validates and saves a creation. Returns {ok, error, manifest}.

**See also:** `build_boxes`, `close`, `make`, `open`, `payload_extension`, `validate`

### `list`

*client/creation_library.gd*

GDScript: `static list() -> Array`

Manifests of every creation, newest first.

**See also:** `count`, `get_value`, `is_id`, `open`, `read_meta`

### `update`

*client/creation_library.gd*

GDScript: `static update(id: String, changes: Dictionary) -> bool`

Changes the name or color (the id stays: it depends only on the content).

### `register_all`

*client/creation_library.gd*

GDScript: `static register_all(registry, images: Dictionary) -> int`

Registers every creation as a cosmetic, putting skin images in `images` (asset name -> Image) for the
look builder. Returns how many were added.

**See also:** `add_to`, `get_payload`, `list`

### `read_model`

*client/creation_library.gd*

GDScript: `static read_model(asset: String) -> PackedByteArray`

Model bytes by asset name ("ugc:....glb"), for LookBuilder's model reader.

**See also:** `get_payload`, `is_id`

### `add`

*client/decal_view.gd*

GDScript: `add(pos: Vector3, normal: Vector3i, look: Dictionary) -> void`

look: {color, size, seconds (0 stays until the limit pushes it out)}.

### `bites`

*client/eating_visuals.gd*

GDScript: `static bites(t: float, duration: float) -> int`

How many bites are gone (0-3; 3 = eaten) `t` seconds into a meal of `duration`.

### `lift`

*client/eating_visuals.gd*

GDScript: `static lift(t: float) -> float`

0..1..0 each chomp: how far the food is raised towards the mouth.

**See also:** `block_state`, `get_block_data`, `get_block_v`, `set_block_authoritative`, `tell_assembly`

### `gulp`

*client/eating_visuals.gd*

GDScript: `static gulp(t: float) -> float`

0..1 over the meal, and a small wobble for each gulp.

### `crumbs`

*client/eating_visuals.gd*

GDScript: `static crumbs(parent: Node, at: Vector3, color: Color, amount := 8, size := 0.03) -> void`

A one-shot burst of pixel crumbs falling in world space.

**See also:** `set_color`

### `start`

*client/effects/swing_trail.gd*

GDScript: `start(grip: Node3D, tip: Node3D, trail: Dictionary, swing_seconds: float, space: Node3D = null, subtle := false) -> void`

Records the ribbon for `swing_seconds`. `space` null means world space. `subtle` (first person, where
the blade sweeps right past the camera) draws a thinner, fainter, shorter ribbon.

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `follow`

*client/float_text.gd*

GDScript: `follow(node: Node3D) -> void`

Sticks it to something that moves. The offset is kept so a number that appeared at chest height
stays at chest height rather than snapping to the thing's feet.

### `reload_pending`

*client/game_client.gd*

GDScript: `reload_pending := false  (property)`

Set when the server announced a full reload: whoever owns the client should reconnect (see main.gd).

### `admin_token`

*client/game_client.gd*

GDScript: `admin_token := ""  (property)`

Passed by the menu when this client launched a local server it should stop on exit.

### `identity_name`

*client/game_client.gd*

GDScript: `identity_name := "default"  (property)`

Which saved identity (user://identity/<name>.pem) to log in with.

### `test_signing_key`

*client/game_client.gd*

GDScript: `test_signing_key: CryptoKey = null  (property)`

Tests only: sign challenges with this key instead of the identity (must fail authentication).

### `test_protocol`

*client/game_client.gd*

GDScript: `test_protocol := -1  (property)`

Tests: announce this protocol version instead of the real one.

### `auto_capture_mouse`

*client/game_client.gd*

GDScript: `auto_capture_mouse := true  (property)`

Accept gameplay input without a captured mouse (headless bots / tests).
Whether arriving in a world grabs the mouse. True for a person playing; the screenshot harness
turns it off, because a test run that steals the cursor for a minute is its own small cruelty.

### `avatar`

*client/game_client.gd*

GDScript: `avatar = null  (property)`

Your portable avatar (Cosmetics data) sent to the server on join; null loads the saved one.

### `realm`

*client/game_client.gd*

GDScript: `realm := ""  (property)`

Which of the server's worlds this player is standing in ("" is the overworld), and what to call it.
Everything in `world` belongs to this realm and nothing outlives a move to another (see on_realm).

### `owned_cosmetics`

*client/game_client.gd*

GDScript: `owned_cosmetics := PackedStringArray()  (property)`

Server cosmetics you own on this server.

### `effects_seen`

*client/game_client.gd*

GDScript: `effects_seen := {}  (property)`

Effect name -> times the server played it for us (debug overlay and tests).

### `stats`

*client/game_client.gd*

GDScript: `stats := {}  (property)`

Stats the server computed for this player (reach, attack_cooldown, mining_speed, armor, ...).

### `transfer_ticket`

*client/game_client.gd*

GDScript: `transfer_ticket := {}  (property)`

A ticket to hand to the server right after hello, when arriving through a transfer: {ticket, signature}.

### `transfer`

*client/game_client.gd*

GDScript: `transfer := {}  (property)`

Set when the server sent us elsewhere: {address, port, name, ticket}.

**See also:** `kick`, `make`, `pack_inventory`, `save_items`, `save_player`, `schedule`

### `exit_kind`

*client/game_client.gd*

GDScript: `exit_kind := ""  (property)`

Why the game ended, for the menu: "" or "identity" (the server's identity no longer matches the pinned one).

### `lazy_bytes_skipped`

*client/game_client.gd*

GDScript: `lazy_bytes_skipped := 0  (property)`

Bytes the join deliberately did not wait for. Counted whether or not they were already cached, so it
says what the join *decided* rather than what happened to be on disk - which is the thing to test.

### `ugc`

*client/game_client.gd*

GDScript: `ugc := UgcClient.new(self)  (property)`

Player creations: uploads, downloads and the server library (see engine/client/ugc_client.gd).

### `ugc_models`

*client/game_client.gd*

GDScript: `ugc_models := {}  (property)`

Model files of downloaded creations: asset name -> GLB bytes.

### `social`

*client/game_client.gd*

GDScript: `social  (property)`

engine/client/social/social_client.gd when main.gd runs the game (null in tests).

### `on_content_update`

*client/game_client.gd*

GDScript: `on_content_update(content: Dictionary) -> void`

A mod was reloaded: take the new definitions, recipe book, guide and tutorials (ids are unchanged).

**See also:** `craftable_times`, `have`, `have_all`, `open`, `refresh`, `register`

### `resolve_transfer_address`

*client/game_client.gd*

GDScript: `static resolve_transfer_address(address: String, current: String) -> String`

Where to actually go when a server sends us somewhere. A server that names itself 127.0.0.1 means "this
machine" - but the client reads that as the *player's* machine, and the destination is wherever the
server we are talking to lives. Unless we really are playing on our own computer, use the host we are
already connected to. (A network.json written with loopback addresses is an easy mistake and used to
leave nobody able to travel at all.)

### `fetch_lazy_asset`

*client/game_client.gd*

GDScript: `fetch_lazy_asset(asset_name: String, then: Callable) -> void`

Fetches a lazy asset, calling `then(asset_name)` once it is on disk. Calling it again for something
already arriving just adds another listener rather than asking the server twice.

### `refresh_looks`

*client/game_client.gd*

GDScript: `refresh_looks() -> void`

Draws everyone again (a creation someone wears has arrived).

**See also:** `apply`, `apply_glow`, `clear_cache`, `compose_armor`, `get_def`, `node_for`

### `open_ugc_review`

*client/game_client.gd*

GDScript: `open_ugc_review() -> void`

The admin review panel for player creations.

**See also:** `fetch`, `has_modal`

### `invite_text`

*client/game_client.gd*

GDScript: `invite_text() -> String`

Report a creation another player is wearing.
The invite code for this server. When playing on this computer (a hosted world), people on the same
network use this computer's local address; from elsewhere they need its public address and the port
forwarded (the hub service will make that easier).

**See also:** `local_address`, `share_text`

### `notify`

*client/game_client.gd*

GDScript: `notify(text: String) -> void`

A short message for the player (creation statuses and the like).

**See also:** `on_chat`

### `on_screen`

*client/game_client.gd*

GDScript: `on_screen(look: Dictionary) -> void`

look: {color, strength (0-1), seconds (0 holds until changed)}. An empty colour clears it.

Respects the accessibility setting for flashes, like the hurt overlay: a full-screen colour is
exactly the thing somebody may need turned down, and a mod should not be able to insist.

**See also:** `get_value`, `shared`

### `on_decal`

*client/game_client.gd*

GDScript: `on_decal(pos: Vector3, normal: Vector3i, look: Dictionary) -> void`

A mark left on the world.

### `on_beam`

*client/game_client.gd*

GDScript: `on_beam(from: Vector3, to: Vector3, look: Dictionary) -> void`

A line drawn from one place to another for a moment.

### `on_player_nameplate`

*client/game_client.gd*

GDScript: `on_player_nameplate(peer_id: int, plate: Dictionary) -> void`

The label over another player's head changed.

**See also:** `apply`

### `on_float_text`

*client/game_client.gd*

GDScript: `on_float_text(text: String, pos: Vector3, options: Dictionary) -> void`

A word that floats in the world for a moment: damage off a hit, a name over a thing.

**See also:** `follow`

### `on_flying`

*client/game_client.gd*

GDScript: `on_flying(enabled: bool) -> void`

The server started or stopped this player's flight.

**See also:** `notify`

### `on_wind`

*client/game_client.gd*

GDScript: `on_wind(angle: float, strength: float) -> void`

The server's music instruction. Nothing here can fail loudly: the track may not have arrived yet, or
may never arrive, and either way the game carries on without it.
The wind the server is running. Stored, not applied: `_wind_angle` eases toward it over a few
seconds, because wind that snaps to a new heading looks like a bug rather than like weather.

### `on_weather`

*client/game_client.gd*

GDScript: `on_weather(weather_id: int, intensity: float) -> void`

What the sky is doing. Like music, nothing here can fail loudly: unknown weather simply is not drawn.

**See also:** `apply`

### `on_realm`

*client/game_client.gd*

GDScript: `on_realm(realm_id: String, display_name: String) -> void`

The server has put this player in another world. Everything on screen belongs to the one they have
left - its terrain, its creatures, the people standing in it - so all of it goes, and the server
streams the new world from scratch.

This arrives on the same channel as chunks, and that is not incidental: the three channels are
delivered independently, so a chunk sent a moment before the move would otherwise be free to arrive
*after* it and be built into the world the player just walked into. Ordering only exists within a
channel, so the message that ends a world travels in the same queue as the chunks it invalidates.

**See also:** `despawn`, `on_assembly_gone`, `on_effect_stop`, `on_player_left`, `on_unload_chunk`

### `on_assembly`

*client/game_client.gd*

GDScript: `on_assembly(id: int, origin: Vector3i, blocks: PackedInt32Array) -> void`

Cables and pipes: the whole lot on joining, then one at a time as they are made.
A set of blocks that has left the grid. Built once from everything it is made of.

**See also:** `on_assembly_gone`

### `on_drives`

*client/game_client.gd*

GDScript: `on_drives(positions: PackedVector3Array, values: PackedFloat32Array) -> void`

What is turning, and how fast. A wheel turns constantly but changes speed rarely, so this arrives
on change and the angle is carried forward here rather than sent every tick.

### `mine_block`

*client/game_client.gd*

GDScript: `mine_block(pos: Vector3i) -> void`

Breaks a block the way a player holding the button would (used by tests and automation).

**See also:** `break_time`, `crack_node`, `get_block_v`, `request_break`, `selected_item`, `tool_of`

### `attack_target`

*client/game_client.gd*

GDScript: `attack_target() -> bool`

Attacks the entity or player under the crosshair. Returns false if nothing is targeted.

**See also:** `play_name`, `swing`

### `use_selected_item`

*client/game_client.gd*

GDScript: `use_selected_item() -> bool`

Uses the held item on the current target (or on nothing). Returns false if it is not usable.

**See also:** `bitten_mesh`, `crumbs`, `get_def`, `is_usable`, `mesh_for`, `plate_mesh`

### `on_selection`

*client/game_client.gd*

GDScript: `on_selection(a: Vector3i, b: Vector3i, show: bool) -> void`

Outline of a structure selection (/struct pos1, pos2).

### `on_area_preview`

*client/game_client.gd*

GDScript: `on_area_preview(cells: PackedVector3Array, color: String, seconds: float, visible: bool) -> void`

The outline of what an area tool is about to change.

One wireframe cube per cell rather than a bounding box, because the point of the preview is to
show a vein's actual shape - a box round a vein tells you nothing you wanted to know. The server
caps how many cells it sends (AreaEdits.PREVIEW_CELLS), so this draws whatever arrives.

### `request_break`

*client/game_client.gd*

GDScript: `request_break(pos: Vector3i) -> void`

Predicts the edit locally and asks the server to apply it.

**See also:** `block_break`, `chunk_coord_at`, `get_block_v`, `has_chunk`, `play_name`, `set_block`

### `placement_spot`

*client/game_client.gd*

GDScript: `placement_spot(target: Dictionary) -> Vector3i`

Places the selected hotbar block, predicting the result.
Where a block goes when placing against a target: into replaceable blocks (tall grass) themselves,
otherwise against the face that was hit.

**See also:** `get_block_v`

### `on_recipe_learned`

*client/game_client.gd*

GDScript: `on_recipe_learned(index: int, source: String) -> void`

A new recipe: remember it and celebrate (several at once are grouped into one toast).

**See also:** `open`

### `on_objectives`

*client/game_client.gd*

GDScript: `on_objectives(view: Dictionary) -> void`

The task list, pushed whenever it changes. See engine/client/objective_hud.gd for why this took
until there was a game with a story in it to notice was missing.

**See also:** `set_view`

### `on_dev_error`

*client/game_client.gd*

GDScript: `on_dev_error(e: Dictionary) -> void`

Script errors on the server, for admins: a red card per error (repeats update its count).

### `on_station_label`

*client/game_client.gd*

GDScript: `on_station_label(pos: Vector3i, text: String) -> void`

Floating progress text above a station for everyone nearby ("" removes it).

### `on_structure_guide`

*client/game_client.gd*

GDScript: `on_structure_guide(missing: Array) -> void`

Ghost blocks where a structure's missing blocks go (red where a block is in the way). Clears after
a minute or when the guide is requested again.

**See also:** `mesh_for`

### `craft_recipe`

*client/game_client.gd*

GDScript: `craft_recipe(index: int, times := 1) -> void`

Asks the server to craft a recipe (see RecipeRegistry indices).

### `lookup_recipes`

*client/game_client.gd*

GDScript: `lookup_recipes(item: int, mode: String) -> void`

Opens the recipe book filtered to what makes (`mode` "make") or uses ("use") an item.

**See also:** `show_lookup`

### `pin_recipe`

*client/game_client.gd*

GDScript: `pin_recipe(index: int) -> void`

Pins a recipe to the HUD (-1 unpins). Saved per server.

**See also:** `craftable_times`, `have`, `have_all`, `load`, `refresh`, `save`

### `open_avatar_editor`

*client/game_client.gd*

GDScript: `open_avatar_editor() -> void`

In game: your look with this server's cosmetics; saved built-in choices travel to other servers.

**See also:** `has_modal`, `is_builtin`, `player_id`, `resolve`

### `open_settings`

*client/game_client.gd*

GDScript: `open_settings() -> void`

The settings screen over the game (from the pause menu).

**See also:** `build`

### `open_players_panel`

*client/game_client.gd*

GDScript: `open_players_panel() -> void`

Players and roles (admins) over the game, in the settings overlay slot.

**See also:** `build`

### `open_server_panel`

*client/game_client.gd*

GDScript: `open_server_panel() -> void`

Server settings (admins) over the game, in the settings overlay slot.

**See also:** `build`

### `open_worlds_panel`

*client/game_client.gd*

GDScript: `open_worlds_panel() -> void`

The worlds this server is linked to, and travel between them.

**See also:** `build`

### `toggle_map`

*client/game_client.gd*

GDScript: `toggle_map() -> void`

The map (M): the world from above with everyone on it.

**See also:** `close_map`

### `open_friends`

*client/game_client.gd*

GDScript: `open_friends() -> void`

Friends and party over the game (from the pause menu), reusing the settings overlay slot.

**See also:** `build`, `close_settings`, `notify`

### `on_riding`

*client/game_client.gd*

GDScript: `on_riding(state_info: Dictionary) -> void`

The server says this player got on or off something.

### `light_the_sun`

*client/game_client.gd*

GDScript: `light_the_sun() -> void`

Turns real shadows on the sun and moon on or off, from the `realistic` graphics setting.

Separate from `GraphicsSettings.apply_realism`, which owns the environment, because shadows live
on the lights and the lights belong to the client. Called at build and whenever the setting
changes, so somebody whose frame rate has collapsed can get it back without restarting.

**See also:** `off`

### `on_palette`

*client/game_client.gd*

GDScript: `on_palette(groups: Dictionary) -> void`

Everything a creative player may take, sent when they ask for it.

**See also:** `show_palette`

### `preset`

*client/graphics_settings.gd*

GDScript: `preset: String  (property)`

The current preset name ("custom" when the player changed single toggles). Values live in the shared
client settings (engine/client/settings/client_settings.gd).

### `cycle`

*client/graphics_settings.gd*

GDScript: `cycle() -> void`

F4: the next preset (from "custom", back to the first).

**See also:** `set_value`, `shared`

### `apply_environment`

*client/graphics_settings.gd*

GDScript: `apply_environment(env: Environment, viewport: Viewport) -> void`

Applies post-processing and resolution settings. Material and mesher toggles are applied by the
client since they need its materials and a remesh.

**See also:** `apply_realism`

### `off`

*client/graphics_settings.gd*

GDScript: `static off(part: String) -> bool`

The realistic preset's half of the environment. Split out so it can be turned on and off while the
game is running rather than only at startup - somebody whose frame rate has collapsed should be
able to get it back from the settings screen without restarting.

Sun shadows themselves live on the light, not here; see `light_the_sun` in game_client.gd.
Which parts of the realistic preset to leave off, for finding out what a frame is being spent on:
QW_REAL_OFF=ssil,ssao,shadows,lit,sky
Empty in normal use. Bisecting beats guessing, and 22 fps on a 24-core M1 Max is not a preset being
expensive - it is something being wrong. (2026-09-21)

### `sweep`

*client/housekeeping.gd*

GDScript: `static sweep() -> int`

Prunes every cache back inside its budget. Returns bytes freed, for the log.

**See also:** `prune`

### `prune`

*client/housekeeping.gd*

GDScript: `static prune(dir: String, budget: int) -> int`

Deletes oldest-first until what is left fits in `budget` bytes. Directly under `dir` only: entries are
whole units (a file, or an unpacked mod's folder), and half an unpacked mod is worse than none.

**See also:** `list`, `open`

### `size_of`

*client/housekeeping.gd*

GDScript: `static size_of(dir: String) -> int`

What a folder currently costs, for the settings screen.

**See also:** `open`

### `listing`

*client/housekeeping.gd*

GDScript: `static listing() -> Array`

The folders, with their sizes filled in.

**See also:** `size_of`

### `human`

*client/housekeeping.gd*

GDScript: `static human(bytes: int) -> String`

"412 MB", "9.1 GB" - sizes a person reads rather than a number they count the digits of.

### `images`

*client/item_icons.gd*

GDScript: `images := {}  (property)`

Asset name -> Image (all downloaded PNGs).

### `composed`

*client/item_icons.gd*

GDScript: `composed(layers: Array) -> Image`

The composed image for layers, or null when none of the sprites are available.

**See also:** `create`

### `tooltip_lines`

*client/item_visuals.gd*

GDScript: `static tooltip_lines(items, id: int, item_data: Dictionary) -> PackedStringArray`

Tooltip text: name (item data "name" overrides), stats from the definition, durability, then lore
from the definition and from item data ("lore": [...]).

**See also:** `get_def`, `max_durability`, `tool_of`, `weapon_of`

### `update_wear_bar`

*client/item_visuals.gd*

GDScript: `static update_wear_bar(slot: Control, items, id: int, item_data: Dictionary) -> void`

Adds or updates a thin bar along the bottom of an item slot showing remaining durability.

**See also:** `max_durability`

### `shield_icon`

*client/item_visuals.gd*

GDScript: `static shield_icon(fill: float) -> ImageTexture`

9x9 shield: `fill` 1 = full, 0.5 = left half, 0 = empty outline.

**See also:** `create`

### `status`

*client/loading_curtain.gd*

GDScript: `status(text: String) -> void`

The line under the title: "Connecting…", "Downloading…", "Loading terrain…".

### `progress`

*client/loading_curtain.gd*

GDScript: `progress(fraction: float) -> void`

The bar, or anything negative to hide it. Most of the steps have nothing to measure, which is why
the blocks above keep moving regardless.

### `leave`

*client/loading_curtain.gd*

GDScript: `leave() -> void`

The world is ready. Fades out and frees itself; safe to call twice.

**See also:** `allowed`, `close`, `finish`, `get_block`, `gone`, `send_to_realm`

### `zoom_by`

*client/map_screen.gd*

GDScript: `zoom_by(steps: int) -> void`

Zooms in (+1) or out (-1). The buttons call this, and so does the mouse wheel: reaching for the wheel
over a map is what everybody does, and it used to change the hotbar behind the map instead.

**See also:** `chunk_coord_at`

### `fetch`

*client/menu/downloads.gd*

GDScript: `fetch(url: String) -> String`

GETs a small text file (a manifest, an index). "" if anything went wrong.

**See also:** `add_to`, `allowed`, `asset_name`, `cache_dir`, `cancel_request`, `get_def`

### `download`

*client/menu/downloads.gd*

GDScript: `download(url: String, into_dir: String) -> PackedByteArray`

GETs a file, through a file on disk so a large zip is not held in memory twice. Empty if it failed.

**See also:** `allowed`, `cancel_request`

### `social`

*client/menu/main_menu.gd*

GDScript: `social  (property)`

engine/client/social/social_client.gd, from main.gd.

### `installed_games`

*client/menu/main_menu.gd*

GDScript: `installed_games() -> Array`

The installed games, as the menu found them. Exposed so the backdrop can generate itself from a
game that is actually present instead of naming one. (2026-09-21)

### `show_message`

*client/menu/main_menu.gd*

GDScript: `show_message(text: String, kind := "info", action_text := "", action := Callable()) -> void`

kind: "info" (fades after a few seconds), "success" (green, fades) or "error" (red, stays until
dismissed). `action_text` + `action` add a button (e.g. retry).

**See also:** `box`

### `refresh_servers`

*client/menu/main_menu.gd*

GDScript: `refresh_servers(query := false) -> void`

Redraws the list; `query` asks again (the hub, the network, or each server for its status).

**See also:** `box`, `configured`, `discover_lan`, `find_favorite`, `get_value`, `join_selected_server`

### `refresh_mods`

*client/menu/main_menu.gd*

GDScript: `refresh_mods() -> void`

The rows of the current tab, from what is installed here and what the index offers.

**See also:** `box`, `install`, `installed`, `merge`, `muted`, `refresh_mods`

### `game`

*client/menu/menu_backdrop.gd*

GDScript: `game := ""  (property)`

The game to generate the backdrop from. Empty means "the first one installed", which is what the
menu does: this named "vanilla" until that mod was deleted on 21 September 2026, and a backdrop
pinned to one mod's id is wrong anyway - it is meant to show whatever this player actually has.

### `motion`

*client/menu/menu_backdrop.gd*

GDScript: `motion := true  (property)`

Orbiting camera and passing time (off: a still view, for players who prefer less motion).

### `refresh_avatar`

*client/menu/menu_backdrop.gd*

GDScript: `refresh_avatar(look: Dictionary, name_text: String) -> void`

Shows a (new) look on the menu avatar, e.g. after the avatar editor closes.

**See also:** `apply`, `clear_cache`, `default_avatar`, `merge`, `refresh_appearance`, `sanitize_avatar`

### `primary`

*client/menu/menu_theme.gd*

GDScript: `static primary(button: Button) -> Button`

A primary (accent) button.

**See also:** `box`

### `nav`

*client/menu/menu_theme.gd*

GDScript: `static nav(button: Button) -> Button`

A sidebar navigation button: flat until selected.

**See also:** `box`

### `close_icon`

*client/menu/menu_theme.gd*

GDScript: `static close_icon(color: Color) -> ImageTexture`

A checkbox mark: a light rounded outline, or an accent square with a tick. Drawn at twice the size
and scaled down, for smooth edges.
The ✕ on a dialog's title bar, drawn so it reads on any backdrop.

**See also:** `create`

### `add_favorite`

*client/menu/server_book.gd*

GDScript: `add_favorite(server_name: String, address: String, port: int) -> bool`

Adds or updates a favorite. Returns false when the list is full.

**See also:** `find_favorite`, `save`

### `note_joined`

*client/menu/server_book.gd*

GDScript: `note_joined(server_name: String, address: String, port: int) -> void`

Remembers a join (most recent first). `server_name` may be updated later by a status answer.

**See also:** `key`, `save`

### `discover_lan`

*client/menu/server_pinger.gd*

GDScript: `discover_lan(extra_ports := []) -> void`

Finds servers on the local network (a broadcast) and on this computer. `extra_ports`: more game
ports to try (e.g. the one this player hosts on).

**See also:** `make_request`, `query_port`

### `ping`

*client/menu/server_pinger.gd*

GDScript: `ping(key: String, address: String, game_port: int) -> void`

`key` identifies the answer (e.g. "host:port").

**See also:** `make_request`, `query_port`

### `check`

*client/menu/update_check.gd*

GDScript: `check(manual := false) -> void`

Asks the release page what the newest version is. `manual` also reports "you are up to date".

**See also:** `compare`, `fetch`, `installed_path`, `manifest_url`, `parse`, `platform`

### `install`

*client/menu/update_check.gd*

GDScript: `install() -> void`

Downloads the update, checks it and hands over to the installer script.

**See also:** `close`, `download`, `install_package`, `installed`, `installed_path`, `installer`

### `list`

*client/menu/world_list.gd*

GDScript: `static list(root := "") -> Array`

[{id, title, game, mods, seed, created_at, last_played, size}] newest played first.

**See also:** `count`, `get_value`, `is_id`, `open`, `read_meta`

### `id_for`

*client/menu/world_list.gd*

GDScript: `static id_for(title: String, root := "") -> String`

A folder name for a new world from its title: letters, digits and underscores, unique in `root`.

### `create`

*client/menu/world_list.gd*

GDScript: `static create(title: String, mods: Array, world_seed: int, root := "") -> String`

Creates the folder and a world.json with the title, mods and seed, so the list shows it before the
first launch. The server fills in the rest when it starts.

**See also:** `broadcast_entity_event`, `close`, `create`, `exists`, `heading`, `id_for`

### `delete`

*client/menu/world_list.gd*

GDScript: `static delete(id: String, root := "") -> bool`

Deletes a world folder and its backups. Refuses ids that are not plain world folders.

**See also:** `open`, `read_meta`

### `describe_time`

*client/menu/world_list.gd*

GDScript: `static describe_time(unix: int) -> String`

"3 minutes ago", "yesterday", "12 Sep 2026".

### `load_mesh`

*client/model_library.gd*

GDScript: `static load_mesh(bytes: PackedByteArray) -> ArrayMesh`

Returns null if the bytes are not a usable model.

### `load_parts`

*client/model_library.gd*

GDScript: `static load_parts(bytes: PackedByteArray) -> Array`

For animated entities: one entry per glTF node with a mesh, {name, mesh, transform}, where the
transform is the node's global transform (its pivot) and the mesh stays in node space so the part
can rotate around its pivot. Returns [] if the bytes are not a usable model.

### `apply`

*client/nameplate.gd*

GDScript: `apply(plate: Dictionary) -> void`

The plate as the server describes it: {name, lines, show_health, health, color, hidden, range}.

**See also:** `accessories`, `add_tab`, `allows`, `begin`, `break_block_for`, `chunk_coord_at`

### `update_for_camera`

*client/nameplate.gd*

GDScript: `update_for_camera(camera_position: Vector3) -> void`

Fades with distance and hides when there is nothing to say. Called by the client each frame with
where the camera is, because a plate has no way of knowing on its own.

### `show_palette`

*client/palette_screen.gd*

GDScript: `show_palette(groups: Dictionary, items, atlas) -> void`

Called when the server sends the catalogue.

**See also:** `icon_of`, `uptime`

### `create`

*client/scrolling_material.gd*

GDScript: `static create(texture: Texture2D) -> ShaderMaterial`

A material that scrolls `texture`. One shader for every belt; one material per texture.

**See also:** `broadcast_entity_event`, `close`, `create`, `exists`, `heading`, `id_for`

### `texture_of`

*client/scrolling_material.gd*

GDScript: `static texture_of(mesh: Mesh) -> Texture2D`

The albedo texture a loaded model is drawn with, so the belt keeps its own look.

### `textures`

*client/server_ui.gd*

GDScript: `textures := {}  (property)`

asset name -> Texture2D, provided by the client after content loads.

### `path`

*client/settings/client_settings.gd*

GDScript: `path := DEFAULT_PATH  (property)`

Resolved in _init, so an instance made directly (a test, a tool) writes where QW_SETTINGS says rather
than over the player's own file. One that did exactly that wiped a player's settings. (2026-09-18)

### `shared`

*client/settings/client_settings.gd*

GDScript: `static shared()`

The settings every part of the client shares (loaded on first use).

**See also:** `load`, `load_file`

### `set_value`

*client/settings/client_settings.gd*

GDScript: `set_value(key: String, value, save_now := true) -> void`

Sets and saves a value (clamped to the schema) and emits `changed`. Changing a graphics toggle while a
preset is selected switches to "custom", starting from that preset's values.

**See also:** `describe`, `drive_changed`, `get_value`, `level_for`, `qualified`, `report_error`

### `events`

*client/settings/client_settings.gd*

GDScript: `events(action: String) -> Array`

The events for an action (saved bindings, else defaults) as descriptors.

**See also:** `default_events`, `event_from`, `get_value`

### `action_using`

*client/settings/client_settings.gd*

GDScript: `action_using(descriptor: String, except := "") -> String`

Which action (if any, other than `except`) already uses an event.

**See also:** `events`

### `apply_bindings`

*client/settings/client_settings.gd*

GDScript: `apply_bindings() -> void`

Registers every action in the InputMap with the player's bindings.

**See also:** `event_from`, `events`

### `descriptor_of`

*client/settings/client_settings.gd*

GDScript: `static descriptor_of(event: InputEvent) -> String`

The descriptor for a pressed key or mouse button, or "" for anything else.

### `apply_display`

*client/settings/client_settings.gd*

GDScript: `apply_display(window: Window) -> void`

Window mode, v-sync, frame rate limit and interface scale.

**See also:** `apply_ui_scale`, `get_value`

### `apply_ui_scale`

*client/settings/client_settings.gd*

GDScript: `apply_ui_scale(window: Window) -> void`

Interface size: the screen's own density (Retina = 2) times the player's choice.

### `apply_audio`

*client/settings/client_settings.gd*

GDScript: `apply_audio() -> void`

Master volume on the Master bus; World and Interface buses (created when missing) below it.

### `closable`

*client/settings/settings_screen.gd*

GDScript: `closable := false  (property)`

Shows a close button (the in-game overlay).

### `closable`

*client/social/friends_panel.gd*

GDScript: `closable := false  (property)`

Shows a Done button (the in-game overlay).

### `current_server`

*client/social/social_client.gd*

GDScript: `current_server := {}  (property)`

{name, address, port, code} while playing on a server, else {}.

### `key`

*client/social/social_client.gd*

GDScript: `key: CryptoKey  (property)`

For tests: sign in with this key instead of the player's identity.

### `refresh`

*client/social/social_client.gd*

GDScript: `refresh() -> void`

Checks in now (signing in first when needed).

**See also:** `allowed`, `apply_condition`, `area_cells`, `at_station`, `available`, `block_state`

### `leader_server`

*client/social/social_client.gd*

GDScript: `leader_server() -> Dictionary`

The party leader's server, when someone else leads and shares it ({} otherwise).

### `build`

*client/texture_atlas.gd*

GDScript: `static build(images: Dictionary) -> Dictionary`

`images`: asset name -> Image. Returns {texture, surface, uv: name -> Rect2, pixels: name -> Rect2}.
Unknown names should fall back to the MISSING ("") entry, a magenta checker.

**See also:** `area_cells`, `body_font`, `box`, `box_mesh`, `check_icon`, `close_icon`

### `build_surface`

*client/texture_atlas.gd*

GDScript: `static build_surface(built: Dictionary) -> Image`

The relief and roughness atlas for an already-built one. **Slow on purpose to call, not to run.**

Split out because it is the expensive half - a Sobel over every pixel of every texture - and doing it
inside `build()` put two and a half seconds on the main thread during world load. That is not merely
a hitch: the client stops draining its socket, Godot starts printing "Buffer full, dropping packets",
the chunks never arrive and the world comes up empty. Run this on a worker and hand the texture over
when it is ready; relief appearing a second after the world does is nothing anybody notices.
(2026-09-22)

**See also:** `create`, `texture`

### `manifest_url`

*client/updater.gd*

GDScript: `static manifest_url() -> String`

Where to ask about new versions (the project setting wins, so a fork can point somewhere else).

### `platform`

*client/updater.gd*

GDScript: `static platform() -> String`

This platform's key in the manifest, or "" where updating is not supported (a server, or a build
installed by something else).

### `signature_ok`

*client/updater.gd*

GDScript: `static signature_ok(manifest_text: String, signature: String, keys := RELEASE_KEYS) -> bool`

Whether this manifest was signed by one of the project's release keys. A build with no keys refuses
everything rather than accepting everything: this used to return true so that builds made before
signing existed could still update themselves, which meant that a build shipped with its keys somehow
empty would take an update from anyone who could answer for the address.

**See also:** `finish`, `start`, `verify`

### `check`

*client/updater.gd*

GDScript: `static check(manifest_text: String, current := Protocol.GAME_VERSION, for_platform := "", signature := "", keys := RELEASE_KEYS) -> Dictionary`

Reads a manifest. Returns {available, version, notes, url, sha256, size, reason}: `available` is true
only when the manifest is signed by the project, sound, names this platform, and is newer than `current`.

**See also:** `compare`, `fetch`, `installed_path`, `manifest_url`, `parse`, `platform`

### `url_allowed`

*client/updater.gd*

GDScript: `static url_allowed(url: String) -> bool`

Only the project's own release hosts (or whatever host the built-in manifest address uses), over https.
The mod list checks every download address the same way (engine/client/mod_catalog.gd).

### `verify`

*client/updater.gd*

GDScript: `static verify(bytes: PackedByteArray, sha256: String, size := 0) -> bool`

Whether a downloaded file is exactly what the manifest described.

**See also:** `finish`, `pem_id`, `start`

### `installed_path`

*client/updater.gd*

GDScript: `static installed_path() -> String`

Where this build is installed: the .app bundle on macOS, otherwise the folder holding the executable.
"" when the game runs from source (the editor), where there is nothing to replace.

### `installer`

*client/updater.gd*

GDScript: `static installer(zip_path: String, work_dir: String, installed: String, pid: int, force := "") -> Dictionary`

The installer for this platform: what file to write, what runs it, and what goes inside.
`force` ("macos", "linux", "windows") is for the tests, which have to be able to read the Windows
installer from a Mac - there is no Windows machine in this project and there may never be one.

**See also:** `install_script`, `windows_install_script`

### `windows_install_script`

*client/updater.gd*

GDScript: `static windows_install_script(zip_path: String, work_dir: String, installed: String, pid: int) -> String`

The Windows twin of install_script, as a batch file.

Windows will not let you delete a running .exe, so everything waits for the game to go first - the
same shape as the shell one, in a language that cannot do most of it. `tasklist` is the wait,
PowerShell is borrowed for the unzip because batch has no such thing, and the swap is a rename so
that a failure halfway leaves the old build where it was rather than nothing at all.

**Not tested on Windows by anyone yet.** It is deliberately not reachable: Windows is a download link
and is not in update.json, so no client will run this until somebody has tried it by hand and the
manifest is changed to offer it. An untested script that replaces a folder is not something to arm.

### `install_script`

*client/updater.gd*

GDScript: `static install_script(zip_path: String, work_dir: String, installed: String, pid: int) -> String`

The script that installs a downloaded update once this process has gone: it unpacks the zip itself
(so the executable bits inside a .app survive), swaps it with the installed build, clears the download
flag macOS puts on it and starts the new one. Kept as a string so a test can read it without installing.


## The server itself

### `export_identity`

*main.gd*

GDScript: `static export_identity(path: String, passphrase: String) -> String`

Returns a status message; failures start with "Error".

**See also:** `close`, `export_encrypted`, `load_or_create`, `open`, `player_id`

### `realms`

*server/game_server.gd*

GDScript: `realms := {}  (property)`

The worlds this server is running. "" is the overworld - the one a server has always had, and the
one an old save belongs to. Realms are added by mods before the world loads.

### `realm`

*server/game_server.gd*

GDScript: `realm: Realm  (property)`

The realm everything without a realm of its own means. Every field below that used to hold the world
directly now reads through it, so the hundred and seventy places that say `world.get_block(...)` did
not all have to change on the same day. They will change as each becomes realm-aware; until then
this is the overworld and the behaviour is exactly what it was.

### `weather_now`

*server/game_server.gd*

GDScript: `weather_now := {"id": -1, "intensity": 0.0, "until": 0.0}  (property)`

What the sky is doing: {id, intensity, until}. World state, not per player - everyone standing in the
same world is standing in the same storm, and somebody joining halfway through arrives in it.

### `wind_now`

*server/game_server.gd*

GDScript: `wind_now := {"angle": 135.0, "strength": 0.3, "until": 0.0, "drifting": true}  (property)`

Which way the wind blows and how hard: degrees clockwise from north, and 0 (still) to 1 (a gale).

**The server sends a base vector and the client does the gusting.** Wind that a player can see is
mostly gusts - grass ripples, a cloud edge tears - and sending that at tick rate would be a lot of
bandwidth for something nobody can be wrong about. So this changes rarely, and the detail is worked
out on each client from time and position. `until` matches `weather_now`: 0 means until something
says otherwise, and while it is unset the engine drifts the wind gently so a world nobody has
written weather for still breathes. (2026-09-22)

### `player_rig`

*server/game_server.gd*

GDScript: `player_rig := PlayerRig.default_rig()  (property)`

The character body every client draws players with (see PlayerRig; mods may replace it).

### `cosmetics`

*server/game_server.gd*

GDScript: `cosmetics := Cosmetics.new()  (property)`

Built-in and server cosmetics, categories and this server's cosmetics policy.

### `effects`

*server/game_server.gd*

GDScript: `effects := EffectRegistry.new()  (property)`

Named visual effects clients render on request (see EffectRegistry).

### `block_ticks`

*server/game_server.gd*

GDScript: `block_ticks  (property)`

Random and scheduled block ticks, the world clock and server-side light (see BlockTicks). One per
realm; this is the overworld's, for everything that has not been told which world it means yet.

### `signals`

*server/game_server.gd*

GDScript: `signals  (property)`

Signal levels (see engine/server/signals.gd). One per realm; this is the overworld's.

### `liquids`

*server/game_server.gd*

GDScript: `liquids  (property)`

Liquids (see engine/server/liquids.gd). One per realm; this is the overworld's.

### `multiblocks`

*server/game_server.gd*

GDScript: `multiblocks  (property)`

Machines assembled out of blocks (see engine/server/multiblocks.gd).

### `containers`

*server/game_server.gd*

GDScript: `containers := Containers.new(self)  (property)`

Container types and open container screens (chests, furnaces, machines).

### `gameplay`

*server/game_server.gd*

GDScript: `gameplay := {  (property)`

Game-wide rules mods can change with set_gameplay.

### `map_markers`

*server/game_server.gd*

GDScript: `map_markers := {}  (property)`

Map markers mods set for a player: player id -> {marker id: {label, position, color}} (see ModApi.set_map_marker).

### `world_markers`

*server/game_server.gd*

GDScript: `world_markers := {}  (property)`

Markers everyone sees (ModApi.set_world_marker); saved in world.json.

### `generator`

*server/game_server.gd*

GDScript: `generator  (property)`

What this realm's terrain is generated by (the overworld's, for callers that have not been told
which world they mean). A chunk job is handed this.

### `generation_passes`

*server/game_server.gd*

GDScript: `generation_passes: Array  (property)`

Objects with decorate(chunk, world_seed) run after the generator on worker threads (e.g. ores).

### `biome_generator`

*server/game_server.gd*

GDScript: `biome_generator  (property)`

JavaScript: `api.biomeGenerator(property)`

The engine biome generator once a mod registers biomes (may also be the world generator, but is a
separate field - see Realm).

**See also:** `block`, `qualified`, `register_instance`

### `rejoin_handler`

*server/game_server.gd*

GDScript: `rejoin_handler := Callable()  (property)`

Where a *returning* player appears, if a mod wants a say - a lobby, a hub, wherever their story left
them. Separate from spawn_handler because "where does a new player start" and "where does somebody
who has played before come back to" are different questions, and a mod that answers one usually does
not want to answer the other. Vector3.INF means "leave them where they logged out".

### `start_error`

*server/game_server.gd*

GDScript: `start_error := ""  (property)`

Why start() gave up, in words a player can act on. Written next to the worlds so the menu can say it
instead of "could not connect to 127.0.0.1" (see engine/server_main.gd).

### `recipes`

*server/game_server.gd*

GDScript: `recipes := RecipeRegistry.new()  (property)`

Crafting recipes and categories (sent to clients for the recipe book).

### `tags`

*server/game_server.gd*

GDScript: `tags := TagRegistry.new()  (property)`

Named groups of blocks and items (see engine/shared/tag_registry.gd). Server-side: a tag is a
question a mod asks while the world runs, not something a client has to know.

### `block_tick_handlers`

*server/game_server.gd*

GDScript: `block_tick_handlers := {}  (property)`

What a block *type* does is true of every world, so these tables belong to the server and every
realm's machinery reads the same one. Registering per realm looked equivalent and was not: a realm
a mod adds later would have had no handlers at all, silently. (2026-09-20)

### `links`

*server/game_server.gd*

GDScript: `links := Links.new(self)  (property)`

What is joined to what (see engine/server/links.gd). Server-wide, not per realm: a wireless link may
have one end in one world and the other somewhere else, so it belongs to neither.

### `flows`

*server/game_server.gd*

GDScript: `flows := Flows.new(self)  (property)`

Quantities moving along those links - power, fluid, gas (see engine/server/flows.gd).

### `parcels`

*server/game_server.gd*

GDScript: `parcels := Parcels.new(self)  (property)`

Things travelling along those links (see engine/server/parcels.gd). Not the same mechanism as
flows, and the file says why.

### `drives`

*server/game_server.gd*

GDScript: `drives := Drives.new(self)  (property)`

Values driven through the graph with nothing stored - rotation (see engine/server/drives.gd).

### `assemblies`

*server/game_server.gd*

GDScript: `assemblies := Assemblies.new(self)  (property)`

Blocks that have left the grid and move as one thing (see engine/server/assemblies.gd).

### `modifiers`

*server/game_server.gd*

GDScript: `modifiers := Modifiers.new(self)  (property)`

Named marks on particular items - keen, sturdy (see engine/server/modifiers.gd).

### `ledgers`

*server/game_server.gd*

GDScript: `ledgers := Ledgers.new(self)  (property)`

Named numbers a player owns - coins, reputation, experience (see engine/server/ledgers.gd).

### `objectives`

*server/game_server.gd*

GDScript: `objectives := Objectives.new(self)  (property)`

Things a player has been asked to do (see engine/server/objectives.gd).

### `characters`

*server/game_server.gd*

GDScript: `characters := Characters.new(self)  (property)`

People who stand somewhere and hold a conversation (see engine/server/characters.gd).

### `shops`

*server/game_server.gd*

GDScript: `shops := Shops.new(self)  (property)`

Buying and selling, drawn the same way everywhere (see engine/server/shops.gd).

### `conditions`

*server/game_server.gd*

GDScript: `conditions := Conditions.new(self)  (property)`

What somebody is temporarily under - swiftness, poison (see engine/server/conditions.gd).

### `fields`

*server/game_server.gd*

GDScript: `fields := Fields.new(self)  (property)`

Ground that does something to whoever stands in it (see engine/server/fields.gd).

### `companions`

*server/game_server.gd*

GDScript: `companions := Companions.new(self)  (property)`

What a tamed creature is being told to do (see engine/server/companions.gd).

### `vehicles`

*server/game_server.gd*

GDScript: `vehicles := Vehicles.new(self)  (property)`

Things you can sit on and steer (see engine/server/vehicles.gd).

### `nameplates`

*server/game_server.gd*

GDScript: `nameplates := Nameplates.new(self)  (property)`

The label over a thing's head (see engine/server/nameplates.gd).

### `companies`

*server/game_server.gd*

GDScript: `companies := Companies.new(self)  (property)`

Groups of players that things can belong to (see engine/server/companies.gd).

### `plots`

*server/game_server.gd*

GDScript: `plots := Plots.new(self)  (property)`

Ground with an owner, consulted before an edit (see engine/server/plots.gd).

### `area_edits`

*server/game_server.gd*

GDScript: `area_edits := AreaEdits.new(self)  (property)`

Changing many blocks at once, with the same checks one block gets (see engine/server/area_edits.gd).

### `instances`

*server/game_server.gd*

GDScript: `instances := Instances.new(self)  (property)`

Private copies of a space, made on demand and thrown away (see engine/server/instances.gd).

### `sources`

*server/game_server.gd*

GDScript: `sources := Sources.new(self)  (property)`

Where a thing comes from when the answer is not a recipe (see engine/server/sources.gd).

### `conflicts`

*server/game_server.gd*

GDScript: `conflicts := Conflicts.new(self)  (property)`

Two mods quietly standing on each other. Reported, never resolved - see conflicts.gd.

### `claims`

*server/game_server.gd*

GDScript: `claims := Claims.new(self)  (property)`

Parts of the world kept awake when nobody is there, and the budget that stops one player doing it
to everybody else (see engine/server/claims.gd).

### `stations`

*server/game_server.gd*

GDScript: `stations := Stations.new(self)  (property)`

Station tiers, workshop upgrades and multiblock structures.

### `sessions`

*server/game_server.gd*

GDScript: `sessions := StationSessions.new(self)  (property)`

Co-op crafting at stations: presence, shared trays, timed jobs and projects.

### `experiments`

*server/game_server.gd*

GDScript: `experiments := Experiments.new(self)  (property)`

The experimentation grid (discovering recipes by arranging items).

### `guide`

*server/game_server.gd*

GDScript: `guide := Guide.new(self)  (property)`

The guidebook: registered pages and what each player has unlocked.

### `tutorials`

*server/game_server.gd*

GDScript: `tutorials := Tutorials.new(self)  (property)`

Tutorials and contextual tips.

### `milestones`

*server/game_server.gd*

GDScript: `milestones := Milestones.new(self)  (property)`

What a player has done, for as long as the world lasts (see engine/server/milestones.gd).

### `charging`

*server/game_server.gd*

GDScript: `charging := Charging.new(self)  (property)`

Items held down rather than clicked: bows, slings (see engine/server/charging.gd).

### `dev_log`

*server/game_server.gd*

GDScript: `dev_log := DevLog.new()  (property)`

Logs and script errors for mod authors (see engine/server/dev_log.gd).

### `dev_tools`

*server/game_server.gd*

GDScript: `dev_tools := DevTools.new(self)  (property)`

Profiler, event tracer, inspector and debug drawing (see engine/server/dev_tools.gd).

### `dev_mode`

*server/game_server.gd*

GDScript: `dev_mode := false  (property)`

--dev: every player gets the developer tools (local development).

### `status_query`

*server/game_server.gd*

GDScript: `status_query := StatusQuery.new(self)  (property)`

The dev dashboard web server (--dev-web=port).

### `hub`

*server/game_server.gd*

GDScript: `hub: HubAnnouncer  (property)`

Lists the server on a hub (a child node while online; null for offline servers).

### `port`

*server/game_server.gd*

GDScript: `port := 0  (property)`

The game port (0 when offline).

### `view_distance`

*server/game_server.gd*

GDScript: `view_distance := DEFAULT_VIEW_DISTANCE  (property)`

Chunks of terrain a player is sent, and chunks around them that the world actually runs in.
Both from the host's configuration; see the constants above for why they are separate.

### `mod_reload`

*server/game_server.gd*

GDScript: `mod_reload := ModReload.new(self)  (property)`

Quick reloads, the file watcher and full reloads (see engine/server/mod_reload.gd).

### `ugc`

*server/game_server.gd*

GDScript: `ugc := Ugc.new(self)  (property)`

Player creations: uploads, the server library and serving them (see engine/server/ugc.gd).

### `mod_settings`

*server/game_server.gd*

GDScript: `mod_settings := ModSettings.new(self)  (property)`

What mods let a host change without editing them (see engine/server/mod_settings.gd).

### `mod_manifests`

*server/game_server.gd*

GDScript: `mod_manifests := {}  (property)`

Loaded mods: id -> manifest, in load order, and id -> the running mod (GDScript instance or JsMod).

### `sightings`

*server/game_server.gd*

GDScript: `sightings := Sightings.new(self)  (property)`

The rare creatures the whole server is told about, and the markers that follow them.

### `connect`

*server/game_server.gd*

GDScript: `connect := Connect.new(self)  (property)`

Blocks that notice their neighbours: fences joining into a run, panes into a window.

### `assembly`

*server/game_server.gd*

GDScript: `assembly := Assembly.new()  (property)`

Materials, parts and tools built from parts (see Assembly).

### `add_realm`

*server/game_server.gd*

GDScript: `add_realm(realm_id: String, realm_name := "") -> Realm`

JavaScript: `api.addRealm(realmId, realmName)`

Adds a world beside the overworld. A mod calls this while it is setting up, before the world loads,
and then gives the realm a generator the same way it gives the overworld one.

Returns the realm, or null when the name is taken or empty. The id is the mod's own qualified name
("mymod:emberdeep"), so two mods can both have an underworld without colliding.

**See also:** `attach`, `reload`, `set_storage`, `start`

### `add_asset`

*server/game_server.gd*

GDScript: `add_asset(asset_name: String, path: String, lazy := false) -> void`

`lazy` assets are in the manifest but are not part of the download a player waits through to join.
The client fetches one the first time something actually needs it. Music lives here: a track is
megabytes where a texture is a few hundred bytes, and a child should not wait through the soundtrack
to get into the world.

### `add_handler`

*server/game_server.gd*

GDScript: `add_handler(event: String, handler: Callable, priority: int, owner := "engine") -> void`

`owner`: the mod id (or "engine") the profiler and tracer credit.

### `is_excluded`

*server/game_server.gd*

GDScript: `is_excluded(full_name: String) -> bool`

Whether a fully qualified name was excluded by some mod's manifest. Checked at registration, so an
excluded thing is never given an id at all - and anything that later names it simply finds nothing,
which is a warning rather than a dangling reference to an id that moved. (2026-09-21)

### `add_command`

*server/game_server.gd*

GDScript: `add_command(command: String, description: String, handler: Callable, mod_id: String, permission := "") -> void`

permission: "" (everyone), "admin" (needs the "command.<name>" permission, which admins have) or any
permission name (see engine/server/roles.gd).

**See also:** `players`, `register_command`

### `is_allowed`

*server/game_server.gd*

GDScript: `is_allowed(player_id: String, player_name: String) -> bool`

Whether a player may join: always when the allowlist is off; else admins and listed players (by id, or
by name until that name first joins and binds the entry to the player's identity).

### `ban_of`

*server/game_server.gd*

GDScript: `ban_of(player_id: String) -> Dictionary`

Whether this player is banned, and what they were told. `{}` when they are not.

**Separate from the allowlist on purpose.** The allowlist answers "is this a private server and are
you on the list"; a ban answers "you in particular are not welcome here", and it has to work on a
public server where the allowlist is off. Running them together would mean banning somebody turned
the whole server private.

### `is_muted`

*server/game_server.gd*

GDScript: `is_muted(player_id: String) -> bool`

Whether this player may not speak.

### `set_ban`

*server/game_server.gd*

GDScript: `set_ban(player_id: String, banned: bool, player_name := "", reason := "", by := "") -> void`

Bans or unbans by player id. The id is the durable half - a name is kept only so the list reads as
something a person can review.

### `player_id_of`

*server/game_server.gd*

GDScript: `player_id_of(name_or_id: String) -> String`

The id behind a name, whether or not they are online - so somebody can be banned while they are
not there, which is when most bans are actually written.

### `allowlist_add`

*server/game_server.gd*

GDScript: `allowlist_add(name_or_id: String) -> void`

Adds a player by name (or id) to the allowlist.

### `allowlist_bind`

*server/game_server.gd*

GDScript: `allowlist_bind(player_id: String, player_name: String) -> void`

The first time a listed name joins, its entry is tied to that identity (so the name cannot be taken).

### `has_permission`

*server/game_server.gd*

GDScript: `has_permission(p, permission: String) -> bool`

Whether a player's roles grant a permission (config admins have everything).

### `uptime`

*server/game_server.gd*

GDScript: `uptime() -> float`

Seconds since the server started ticking. What `schedule` measures against, so anything timing an
event of its own should ask here rather than reach for a wall clock - a paused or slow server then
counts the same time everything else does.

### `after_mod_reload`

*server/game_server.gd*

GDScript: `after_mod_reload() -> void`

After a quick reload: clients get the new definitions, recipe book, guide and tutorials.

**See also:** `open_crafting_refresh`, `revalidate`, `sources_index`, `sync`

### `open_crafting_refresh`

*server/game_server.gd*

GDScript: `open_crafting_refresh(p: ServerPlayer) -> void`

Refreshes a player's open crafting screen (the recipe book may have changed).

### `tell_moderators`

*server/game_server.gd*

GDScript: `tell_moderators(text: String) -> void`

Messages for admins only (moderation).

**See also:** `has_permission`, `send_message`

### `request_full_reload`

*server/game_server.gd*

GDScript: `request_full_reload() -> void`

Saves and asks the owner to restart the server with the same settings; clients are told to reconnect.

**See also:** `chunk_coord_of`, `merge`, `tell_admins`, `ticking_chunks`, `to_saved`

### `tell_riding`

*server/game_server.gd*

GDScript: `tell_riding(p: ServerPlayer) -> void`

Tells a client whether it is riding, and on what. The client stops predicting its own movement while
it is, which is the whole reason this crosses the wire at all.

**See also:** `config`, `riders_of`

### `player_by_id`

*server/game_server.gd*

GDScript: `player_by_id(player_id: String)`

The online player with this id, or null. Two loops already did this by hand.

### `backup_now`

*server/game_server.gd*

GDScript: `backup_now(requester := 0) -> bool`

Flushes pending saves, then archives the world on a worker thread. `requester` (peer id) is told
when it finishes. Returns false if a backup is already running.

**See also:** `chunk_coord_of`, `merge`, `ticking_chunks`, `timestamp`, `to_saved`

### `set_flying`

*server/game_server.gd*

GDScript: `set_flying(p: ServerPlayer, enabled: bool, deliberate := false) -> bool`

Starts or stops flight for a player, telling their client. Returns false when they may not fly.

**See also:** `may_fly`

### `may_fly`

*server/game_server.gd*

GDScript: `may_fly(p: ServerPlayer, deliberate := false) -> bool`

Creative players fly; anyone else needs the "fly" permission.
Whether `p` may fly. `deliberate` is a command rather than a double-tap on the jump key: a game that
turns flight off is saying "this is not a game you fly in", not "the admin may never fly", so an
explicit `/fly` still goes through and an accidental double-tap does not.

**See also:** `has_permission`

### `damage_player`

*server/game_server.gd*

GDScript: `damage_player(p: ServerPlayer, amount: float, cause: String, attacker = null, direction := Vector3.ZERO, bypass_cooldown := false, knockback := 6.0) -> bool`

Returns true if damage applied. `direction` sets the knockback direction (defaults to away from
the attacker). `bypass_cooldown` lets continuous damage (void) ignore the invulnerability window.

**See also:** `add_exhaustion`, `apply_armor`, `broadcast_player_event`, `damage_item`, `get_def`, `get_eye_position`

### `play_sound_at`

*server/game_server.gd*

GDScript: `play_sound_at(sound_name: String, pos: Vector3, volume := 1.0, pitch := 1.0, exclude := 0) -> void`

Plays a registered sound at a world position for players in range. `exclude` is a peer id that
already played it locally (e.g. the player who broke the block).

### `play_decal`

*server/game_server.gd*

GDScript: `play_decal(pos: Vector3, normal: Vector3i, look := {}, realm_id := "") -> void`

JavaScript: `api.playDecal(pos, normal, look, realmId)`

Starts an effect that keeps going until stop_effect. Returns a handle, or 0.

For a machine that should smoke *while it runs*: play_effect is a burst and forgets itself, which
cannot express "this is working now".
Leaves a mark on the world for everyone near enough to see it.

**See also:** `qualified`, `realm_of`

### `play_beam`

*server/game_server.gd*

GDScript: `play_beam(from: Vector3, to: Vector3, look := {}, realm_id := "") -> void`

JavaScript: `api.playBeam(from, to, look, realmId)`

Draws a line between two places for a moment, for everyone near enough to see it.

**See also:** `qualified`, `realm_of`

### `float_text`

*server/game_server.gd*

GDScript: `float_text(text: String, pos: Vector3, options := {}, realm_id := "") -> void`

JavaScript: `api.floatText(text, pos, options, realmId)`

Words that float in the world for a moment and then go: damage off a hit, "+3 copper" over a
chest, a name over a thing. Transient on purpose - nothing is stored, nobody has to clean it up, and
a client that was not listening has missed nothing that matters.

options: color, seconds, rise (how far it drifts up), size, follow (a player or entity it sticks to).

**See also:** `qualified`, `register_entity`

### `send_music`

*server/game_server.gd*

GDScript: `send_music(p, track_id: int, fade := 2.0, restart := false) -> void`

Tells a player (or everyone, when `p` is null) what music to play. -1 means stop. The track each
player is on is remembered so a mod can call this on every biome change without restarting anything,
and so a player who reconnects hears the same thing rather than silence.

### `set_weather`

*server/game_server.gd*

GDScript: `set_weather(weather_name: String, intensity := 1.0, seconds := 0.0) -> void`

JavaScript: `api.setWeather(weatherName, intensity, seconds)`

Starts weather, or stops it with an empty name. `seconds` of 0 means until something says otherwise.

### `set_wind`

*server/game_server.gd*

GDScript: `set_wind(degrees: float, strength := 0.5, seconds := 0.0) -> void`

JavaScript: `api.setWind(degrees, strength, seconds)`

Sets the wind: `degrees` clockwise from north, `strength` 0 (still) to 1 (a gale). `seconds` of 0
means until something says otherwise, matching `set_weather`.

While a mod holds the wind the engine stops drifting it, so a storm's gale does not wander off on
its own halfway through.

### `wind_state`

*server/game_server.gd*

GDScript: `wind_state() -> Dictionary`

The wind as a mod sees it: {angle, strength}.

### `weather_state`

*server/game_server.gd*

GDScript: `weather_state() -> Dictionary`

The weather as a mod sees it: {name, intensity}. "" when the sky is clear.

### `block_sound`

*server/game_server.gd*

GDScript: `block_sound(block: int, action: String) -> String`

Sound name for a block action ("break", "place", "step"); empty when the block has none.

### `set_world_time`

*server/game_server.gd*

GDScript: `set_world_time(time_of_day: float, day_length: float) -> void`

JavaScript: `api.setWorldTime(timeOfDay, dayLength)`

`time_of_day`: 0 = midnight, 0.25 = sunrise, 0.5 = noon. `day_length` in seconds, 0 = frozen.

**See also:** `daylight`, `get_day_length`, `phase`

### `on_auth`

*server/game_server.gd*

GDScript: `on_auth(peer_id: int, signature: PackedByteArray) -> void`

The client proves it holds the private key for the identity it presented.

**See also:** `accept`, `allowlist_bind`, `ban_of`, `give`, `is_allowed`, `kick`

### `on_claim_admin`

*server/game_server.gd*

GDScript: `on_claim_admin(peer_id: int, token: String) -> void`

The local host proves it launched this server and becomes a permanent admin.

**See also:** `give`, `send_message`

### `peer_address`

*server/game_server.gd*

GDScript: `peer_address(peer_id: int) -> String`

Where a peer is connecting from, or "" when that cannot be told (offline play, a peer already gone).

### `mark_simulation_stale`

*server/game_server.gd*

GDScript: `mark_simulation_stale() -> void`

Says the simulated set needs working out again. Claims call it; so does anything else that changes
which part of the world should be running.

### `tell_assembly`

*server/game_server.gd*

GDScript: `tell_assembly(id: int) -> void`

A face is being driven at a new speed: tell whoever is standing in that world and holds the chunk.
Only for blocks that say they turn, because telling a client about a shaft it will not animate is
bytes spent on nothing.
Everything an assembly is made of, once, to whoever is in that world.

**See also:** `realm_of`

### `tell_assembly_moved`

*server/game_server.gd*

GDScript: `tell_assembly_moved(id: int) -> void`

Where it has got to. Unreliable and ordered, like movement: a position that arrives late is worth
nothing, and the next one is along in a moment.

**See also:** `realm_of`

### `remove_realm`

*server/game_server.gd*

GDScript: `remove_realm(realm_id: String) -> bool`

Takes a realm out of the server. Only for instances: a realm a mod declared is part of the world
and stays for the session.

Everything a realm owns hangs off the Realm object - its world, its entities, its tickers - so
dropping the reference is most of the job. What is not automatic is the simulated set, which is
rebuilt from players, and anything holding the realm id.

**See also:** `is_overworld`

### `send_to_realm`

*server/game_server.gd*

GDScript: `send_to_realm(p: ServerPlayer, realm_id: String, position: Vector3) -> bool`

JavaScript: `api.sendToRealm(p, realmId, position)`

Moves a player to another world, standing at `position`. Portals, the command and the mod API all
end here, so the order below is the only place it has to be right.

Returns false when there is no such realm, or they are already in it.

**See also:** `ensure_area_loaded`, `generate`, `index`, `links_for`, `qualified`, `realm_of`

### `ensure_area_loaded`

*server/game_server.gd*

GDScript: `ensure_area_loaded(pos: Vector3, into: Realm = null) -> void`

Loads the chunks around a position so players placed there have ground to stand on.

**See also:** `add_chunk`, `block`, `chunk_coord_of`, `chunk_path`, `decorate`, `generate`

### `get_block_loaded`

*server/game_server.gd*

GDScript: `get_block_loaded(pos: Vector3i, into: Realm = null) -> int`

Every function here takes the world to act in, and `null` means the overworld. A position alone
does not say which world any more - the same coordinates exist in all of them - so anything acting
for a player passes `realm_of(p)`, and anything acting for a creature passes its realm.

**See also:** `add_chunk`, `block`, `chunk_coord_at`, `chunk_path`, `decorate`, `generate`

### `surface_height`

*server/game_server.gd*

GDScript: `surface_height(x: int, z: int, into: Realm = null) -> int`

Y of the highest solid or liquid block in the column (loading it if needed), or -1. Plants and
other non-solid decorations are skipped, so things placed on the surface stand on the ground.

**See also:** `add_chunk`, `block`, `chunk_coord_at`, `chunk_path`, `decorate`, `generate`

### `get_block_data`

*server/game_server.gd*

GDScript: `get_block_data(pos: Vector3i, into: Realm = null) -> Dictionary`

JavaScript: `api.getBlockData(pos, into)`

Live dictionary for the block at `pos`, or an empty one if it has none. Mutations to a returned
dictionary are saved; call set_block_data to attach data to a block that has none yet.

**See also:** `chunk_coord_at`, `qualified`, `register_instance`

### `find_block_data`

*server/game_server.gd*

GDScript: `find_block_data(block := -1, into: Realm = null) -> Array[Vector3i]`

JavaScript: `api.findBlockData(block, into)`

Positions of loaded blocks that have data, optionally only of one block type.

**See also:** `get_block_v`, `qualified`, `register_instance`

### `add_death_messages`

*server/game_server.gd*

GDScript: `add_death_messages(key: String, lines: Array) -> void`

JavaScript: `api.addDeathMessages(key, lines)`

Adds ways of saying somebody died (see ModApi.add_death_messages). `key` is a cause, or the name of an
entity so a mod's own mob gets its own send-off; "%s" is the player, and a second "%s" is what did it.

**See also:** `count`, `qualified`, `register_settings`

### `announce_rare_loot`

*server/game_server.gd*

GDScript: `announce_rare_loot(player, item: int, count: int, position: Vector3) -> void`

A find worth noticing: a sparkle where it landed, a sound for whoever found it, and a line in chat so
the rest of the server shares the moment. The sparkle repeats for a little while, so a rare drop in
long grass can still be found. Rarity comes from the table's own weights - nothing is marked by hand.

**See also:** `broadcast_chat`, `cancel_task`, `play_effect`, `play_sound_at`, `schedule`, `send_message`

### `break_block_for`

*server/game_server.gd*

GDScript: `break_block_for(p: ServerPlayer, pos: Vector3i, into: Realm, harvest := true) -> bool`

Breaks one block *on a player's behalf*: the pre-event, the loot roll, the drops, the tool wear, the
hunger and the post-event, exactly as breaking it by hand does.

Split out of `on_break_block` so area tools get all of that without copying it. What stays with the
caller is what an area tool decides differently: reach and mining time are per-block questions when
you are swinging at one, and whole-selection questions when you are not. Everything below here is
the same either way. (2026-09-21)

**See also:** `add_exhaustion`, `awarded`, `block_changed`, `block_removed`, `block_state`, `break_block`

### `place_block_for`

*server/game_server.gd*

GDScript: `place_block_for(p: ServerPlayer, pos: Vector3i, block: int, into: Realm) -> bool`

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

### `open_palette`

*server/game_server.gd*

GDScript: `open_palette(p: ServerPlayer) -> void`

Everything that exists, for a creative player to take from.

**A creative game ships no recipes**, so the recipe book - which is how a player finds out what
exists - is empty in exactly the game where finding out what exists matters most. This is the
other half of that: a browser of every block and item, grouped the way they were registered.

Sent rather than derived on the client because the client does not know which items a mod meant
to be takeable; `hidden` on a definition keeps the plumbing out (block data holders, half-slabs
that are placed rather than carried). (2026-09-22)

**See also:** `palette_groups`

### `palette_groups`

*server/game_server.gd*

GDScript: `palette_groups() -> Dictionary`

What the palette lists, split out from the sending so a test can read it.

**The first version of this listed nothing at all, for two reasons, and shipped that way**
(written 2026-09-22, found 2026-09-23). Both are worth keeping, because both look right:

- `range(ItemRegistry.FIRST_ITEM, items.defs.size())` reads like "every item", and is
`range(65536, 30)` - **empty**. Item ids start at `FIRST_ITEM` and run to
`FIRST_ITEM + defs.size()`; `defs.size()` on its own is a count, not an end.
- It looked for blocks by asking which *items* are also blocks. None are, and none can be:
a block **is** its own item id (below `FIRST_ITEM`), and `items.register` refuses a name a
block already holds. So that branch could never have been true.

What made it survive is the sharper lesson: the Proving Ground asserted that a creative player
could *take* from the palette, which worked, and never that the palette *listed* anything. Half a
feature tested is a feature that reports itself working.

`group` on a definition names the drawer. Without one, blocks and items fall into two default
drawers - which is all a small mod wants, and is what every mod had before this existed.

**See also:** `palette_lists`

### `palette_lists`

*server/game_server.gd*

GDScript: `palette_lists(id: int) -> bool`

Whether the palette offers this id at all - asked by the listing *and* by the handing out, so the
two can never disagree about what is takeable. They disagreeing is the bug class that produced an
empty palette in the first place.

**See also:** `get_def`

### `on_palette_take`

*server/game_server.gd*

GDScript: `on_palette_take(peer_id: int, item: int, whole_stack: bool) -> void`

A creative player asking for a stack of something from the palette.

**See also:** `max_stack`, `palette_lists`, `sync_inventory`

### `on_tutorial_action`

*server/game_server.gd*

GDScript: `on_tutorial_action(peer_id: int, action: String, arg: String) -> void`

Tutorial buttons: start <id> | skip (the current step) | stop | tips_on | tips_off.

**See also:** `advance`, `set_tips`, `start`, `stop`

### `on_dev`

*server/game_server.gd*

GDScript: `on_dev(peer_id: int, action: String, args: Dictionary) -> void`

Dev overlay requests: subscribe {channels}, inspect {pos | entity | player}, trace_filter {filter},
clear_errors {source}.

**See also:** `add_shapes`, `allowed`, `clear_errors`, `receive`, `set_inspect`, `set_open`

### `damage_item`

*server/game_server.gd*

GDScript: `damage_item(p: ServerPlayer, slot: int, amount: int, reason := "use") -> void`

Wears an item: adds `amount` to its item data `damage`; at the item's durability it breaks.

**See also:** `clear_slot`, `get_eye_position`, `look_direction`, `max_durability`, `play_effect`, `play_sound_at`

### `refresh_stats`

*server/game_server.gd*

GDScript: `refresh_stats(p: ServerPlayer) -> void`

Recomputes a player's stats, applies max health and movement speed, reports equipment changes and
sends the result to the client when it changed.

**See also:** `compute`, `refresh_appearance`, `sync_health`

### `refresh_appearance`

*server/game_server.gd*

GDScript: `refresh_appearance(p: ServerPlayer) -> void`

What other players see: held item, visible armor and avatar. Sent to everyone when it changes.

**See also:** `equipment_index`, `selected_item`, `visible_armor`, `visuals`

### `on_set_avatar`

*server/game_server.gd*

GDScript: `on_set_avatar(peer_id: int, avatar: Dictionary) -> void`

A client sent its avatar: while joining it is kept for spawn; in game it replaces the player's look.

**See also:** `ensure_registered`, `is_builtin`, `is_id`, `refresh_avatar`, `sanitize_avatar`, `worn_ids`

### `can_wear`

*server/game_server.gd*

GDScript: `can_wear(cosmetic_name: String, p: ServerPlayer) -> bool`

Whether a player may pick a cosmetic themselves (mods can still dress anyone in anything).

**See also:** `get_def`, `is_approved`, `is_blocked`, `is_builtin`, `is_id`, `look`

### `refresh_avatar`

*server/game_server.gd*

GDScript: `refresh_avatar(p: ServerPlayer) -> void`

Recomputes the look others see: portable look (or the name's default), then this server's picks,
the policy uniform, the player's override and avatar_change handlers.

**See also:** `apply`, `clear_cache`, `default_avatar`, `merge`, `refresh_appearance`, `sanitize_avatar`

### `reapply_requested_avatar`

*server/game_server.gd*

GDScript: `reapply_requested_avatar(p: ServerPlayer) -> void`

Applies the avatar the player last asked for again (a creation in it was approved or removed).

**See also:** `ensure_registered`, `is_builtin`, `is_id`, `refresh_avatar`, `sanitize_avatar`, `worn_ids`

### `dimension_of`

*server/game_server.gd*

GDScript: `dimension_of(p) -> String`

The players and roles panel. Answers with {players, roles, can_kick, denied?}.
Which world a player is in. One world today ("" is it); mods that add dimensions set this key on the
player, and the map, compass and markers follow them there.

### `too_often`

*server/game_server.gd*

GDScript: `too_often(p: ServerPlayer, what: String, seconds: float) -> bool`

What the player's map shows: everyone in the same dimension (unless the server hides them) and the
markers mods set, also filtered to that dimension.
**Handlers that do real work per call need a floor on how often.**

Three of them had none: `c_map` walks every player and generates a chunk, and the two UGC listings
walk the whole library. None of that is expensive once; all of it is expensive at a thousand calls
a second, and nothing stopped a client sending them that fast. A client asking politely is
unaffected - the map screen polls every two seconds and these floors are well under that.

Returns true when the call came too soon and should be dropped. Silent on purpose: an answer
explaining the limit is itself a reply to send, and a client that is misbehaving is not reading it.

### `on_worlds_panel`

*server/game_server.gd*

GDScript: `on_worlds_panel(peer_id: int, action: String, args: Dictionary) -> void`

The worlds panel: the servers this one is linked to (network.json), and travel.

**See also:** `has_permission`, `send_message`, `transfer`

### `on_server_panel`

*server/game_server.gd*

GDScript: `on_server_panel(peer_id: int, action: String, args: Dictionary) -> void`

The admin settings screen. Every action is the command an admin could type, run with their own
permissions, so nothing here grants more than chat already does.

**See also:** `has_permission`, `list`, `mods`, `receive`, `send_message`

### `on_ugc_admin`

*server/game_server.gd*

GDScript: `on_ugc_admin(peer_id: int, action: String, args: Dictionary) -> void`

The creations review panel (admins): list {filter, text} | set_status {id, status, reason} |
trust {player_id, on} | ban {player_id, on, reason} | clear_reports {id}. Answers with the list.

**See also:** `clear_reports`, `has_permission`, `review_list`, `set_banned`, `set_status`, `set_trusted`

### `add_recipe`

*server/game_server.gd*

GDScript: `add_recipe(inputs: Dictionary, output: int, count: int, station := "", options := {}) -> int`

`station`: "" (crafted anywhere) or a station name blocks declare with `station` (e.g. a crafting table).
options: category, id. Returns the recipe index.

### `get_fuel`

*server/game_server.gd*

GDScript: `get_fuel(item: int) -> float`

JavaScript: `api.getFuel(item)`

How long an item burns as fuel (seconds; 0 = not fuel).

**See also:** `register_process`

### `add_process`

*server/game_server.gd*

GDScript: `add_process(kind: String, input: int, output: int, count: int, seconds: float) -> void`

Processing recipes machines look up: kind ("smelting", "grinding", ...) -> input -> result.

### `crafting_stock`

*server/game_server.gd*

GDScript: `crafting_stock(p: ServerPlayer) -> Dictionary`

Items a station can draw from containers around it: {item id: count}. Empty when crafting by hand.

**See also:** `find_block_data`, `get_block_v`, `get_container`, `get_eye_position`, `get_item`, `now`

### `craftable_times`

*server/game_server.gd*

GDScript: `craftable_times(p: ServerPlayer, recipe: Dictionary, limit := 999) -> int`

How many times the player can craft a recipe right now (inventory plus the station's nearby chests).

**See also:** `at_station`, `count_of`, `crafting_stock`, `get_block_v`, `get_eye_position`, `have`

### `learn_recipe`

*server/game_server.gd*

GDScript: `learn_recipe(p: ServerPlayer, recipe_id: String, source := "mod") -> bool`

Teaches a recipe. Returns true if the player did not know it (creative players still learn it).

**See also:** `index_of`

### `check_discoveries`

*server/game_server.gd*

GDScript: `check_discoveries(p: ServerPlayer) -> void`

"pickup" recipes unlock the first time a player holds one of their ingredients.

**See also:** `learn_recipe`, `total`, `using`

### `open_crafting`

*server/game_server.gd*

GDScript: `open_crafting(p: ServerPlayer, station := {}) -> void`

Opens the crafting screen for a player: by hand ({}) or at a station {name, position, title}.

**See also:** `crafting_stock`, `evaluate`, `leave`

### `on_station_action`

*server/game_server.gd*

GDScript: `on_station_action(peer_id: int, action: String) -> void`

Station screen buttons: "upgrade" uses the next tier's kit, "guide" shows a structure's missing blocks.

**See also:** `get_block_v`, `get_eye_position`, `open_crafting`, `realm_of`, `structure_missing`, `upgrade`

### `show_crafting`

*server/game_server.gd*

GDScript: `show_crafting(p: ServerPlayer) -> void`

JavaScript: `api.showCrafting(p)`

Mods: opens the crafting screen for a player as if they pressed the crafting key.

**See also:** `open_crafting`

### `craft`

*server/game_server.gd*

GDScript: `craft(p: ServerPlayer, index: int, times := 1) -> int`

Crafts a recipe up to `times` times, taking ingredients from the inventory first and then from the
station's nearby chests. Returns how many times it crafted.

**See also:** `add_job`, `consume_tray`, `count_of`, `craftable_times`, `crafting_stock`, `drop`

### `take_recipe_inputs`

*server/game_server.gd*

GDScript: `take_recipe_inputs(p: ServerPlayer, index: int) -> Dictionary`

Takes one craft's ingredients for crafting by hand: {item, count, data, recipe}, or {} if the
recipe cannot be crafted here.

**See also:** `consume_tray`, `count_of`, `craftable_times`, `crafting_stock`, `evaluate`, `find_block_data`

### `give_crafted`

*server/game_server.gd*

GDScript: `give_crafted(p: ServerPlayer, item: int, count: int, item_data: Dictionary, forged := false) -> void`

Gives a finished item (from crafting by hand or assembling) with effects at the station.

**See also:** `crafting_stock`, `drop`, `get_block_v`, `get_eye_position`, `max_stack`, `play_effect`

### `assemble`

*server/game_server.gd*

GDScript: `assemble(p: ServerPlayer, assembly_name: String, slots: PackedInt32Array) -> bool`

Builds a tool from parts in the player's inventory: `slots` lists a backpack slot per assembly slot.

**See also:** `give_crafted`, `take_assembly_parts`

### `take_assembly_parts`

*server/game_server.gd*

GDScript: `take_assembly_parts(p: ServerPlayer, assembly_name: String, slots: PackedInt32Array) -> Dictionary`

Takes the parts for an assembly: {item, count, data}, or {} if they are not valid.

**See also:** `build`, `clear_slot`, `sync_inventory`

### `on_station_coop`

*server/game_server.gd*

GDScript: `on_station_coop(peer_id: int, action: String, arg: int) -> void`

Co-op actions at the player's station: "view" (recipe index), "deposit" (backpack slot), "take" (tray
index), "start_project" (recipe index), "contribute", "cancel_project".

**See also:** `cancel_project`, `contribute`, `crafting_stock`, `deposit`, `get_block_v`, `get_eye_position`

### `refresh_crafting_stock`

*server/game_server.gd*

GDScript: `refresh_crafting_stock(pos: Vector3i) -> void`

Tells players crafting near a changed container what their station can draw from now.
Called from containers.gd when a container a station draws from changed. Public because it is
reached across files: a leading underscore that another script calls is a lie about what is private.

**See also:** `crafting_stock`

### `pair_offset`

*server/game_server.gd*

GDScript: `static pair_offset(pair: Dictionary, state: int) -> Vector3i`

Offset from one half of a two-block piece to the other: `pair.direction` is "back" (away from the
player who placed it), "front", "up" or "down".

**See also:** `facing_direction`

### `pair_position`

*server/game_server.gd*

GDScript: `pair_position(pos: Vector3i, into: Realm = null) -> Vector3i`

The other half of a two-block piece at `pos`, or `pos` itself.

**See also:** `block_state`, `get_block_v`, `pair_offset`

### `is_supported`

*server/game_server.gd*

GDScript: `is_supported(pos: Vector3i, block: int, into: Realm = null) -> bool`

Whether `block` may stand at `pos`: its `support` rule ("solid" or [block names]) must accept the block
below. Blocks without a rule always can.

**See also:** `get_block_v`

### `break_block`

*server/game_server.gd*

GDScript: `break_block(pos: Vector3i, drop := true, into: Realm = null, sound := true) -> void`

JavaScript: `api.breakBlock(pos, drop, into, sound)`

Breaks a block without a player (support lost, explosions, mods): drops items, plays its sound.

`sound` is off for a blast, which breaks fifty blocks in one instant: fifty break sounds on top of
the explosion is a noise, not fifty pieces of feedback.

**See also:** `block_changed`, `block_removed`, `block_state`, `break_block`, `chunk_coord_at`, `clear_block_data`


## Everything else

### `find`

*server/conflicts.gd*

GDScript: `find() -> Array`

Everything worth telling somebody about: [{kind, detail, mods}], sorted for a stable report.

### `start`

*server/sightings.gd*

GDScript: `start() -> void`

Starts the sweep. Called once the server is running, because `schedule` needs its clock.

**See also:** `add_chunk`, `add_command`, `add_handler`, `add_mod_dir`, `add_recipe`, `advance`

### `arrived`

*server/sightings.gd*

GDScript: `arrived(e) -> void`

A creature has appeared. Announces it and marks it, if it is one of the notable ones.

Every spawn comes through here, including the ordinary ones, so the first line is the one that
matters: `notable_of` answers `{}` for almost everything and this returns having done nothing.

**See also:** `at_path_end`, `broadcast_chat`, `key_name`, `node_key`, `notable_of`, `play_sound_to`

### `slain`

*server/sightings.gd*

GDScript: `slain(e, attacker) -> void`

It died. Says who, then clears up.

**See also:** `broadcast_chat`, `count`, `gone`, `key_name`, `node_key`

### `gone`

*server/sightings.gd*

GDScript: `gone(e) -> void`

It is no longer in the world, for whatever reason. Takes its marker off the map.

**See also:** `key_name`, `node_key`

### `update`

*server/sightings.gd*

GDScript: `update() -> void`

Moves each marker to where its creature is now, and sees off the ones whose time has run out.

### `rebuild`

*server/sightings.gd*

GDScript: `rebuild() -> void`

Rebuilds the list from the creatures actually in the world, and sweeps any marker left behind.

Called after a world loads. Notable creatures are saved with their chunk, so one can outlive the
session it appeared in - and its marker is saved with the world too, which would otherwise leave a
compass pointing at a monster that had long since been dealt with. Nothing is re-announced: a line
in chat is for the moment it happened.

**See also:** `is_alive`, `key_name`, `node_key`, `notable_of`, `uptime`

### `count`

*server/sightings.gd*

GDScript: `count() -> int`

How many are being tracked, for the tests and for an admin wondering what is loose.

### `list`

*server/world_backups.gd*

GDScript: `static list(backup_dir: String) -> Array`

Newest first. Each entry: {name, path, size, modified}.

**See also:** `count`, `get_value`, `is_id`, `open`, `read_meta`

### `create`

*server/world_backups.gd*

GDScript: `static create(world_dir: String, zip_path: String) -> String`

Worker thread safe. Archives every file under `world_dir` into `zip_path`. Returns "" or an error.

**See also:** `broadcast_entity_event`, `close`, `create`, `exists`, `heading`, `id_for`

### `prune`

*server/world_backups.gd*

GDScript: `static prune(backup_dir: String, keep: int) -> int`

Deletes the oldest backups beyond `keep`. Returns how many were removed.

**See also:** `list`, `open`

### `resolve`

*server/world_backups.gd*

GDScript: `static resolve(backup_dir: String, which: String) -> String`

Resolves "latest", a file name in `backup_dir`, or a path to an archive.

**See also:** `default_avatar`, `list`, `merge`, `sanitize`, `satisfies`

### `restore`

*server/world_backups.gd*

GDScript: `static restore(zip_path: String, world_dir: String) -> String`

Replaces `world_dir` with the archive's contents. The current world is moved aside (not deleted)
to <world_dir>.before-restore-<timestamp>. Returns "" or an error.

**See also:** `close`, `open`, `timestamp`

### `allowed`

*shared/net_access.gd*

GDScript: `static allowed(url: String) -> bool`

Whether this process may fetch `url`. True for everything unless `QW_OFFLINE` is set, and then only
for loopback.

**See also:** `has_permission`, `host_allowed`, `leave`

### `host_allowed`

*shared/net_access.gd*

GDScript: `static host_allowed(host: String) -> bool`

The same question when the host is already in hand, as `hub_announcer.leave()` has it.

### `restricted`

*shared/net_access.gd*

GDScript: `static restricted() -> bool`

Whether this process has been kept off the network. Tests assert on it, because the whole point is
that it is true while they run and false while somebody is playing.

### `chunks`

*shared/voxel_world.gd*

GDScript: `chunks := {}  (property)`

Vector2i -> Chunk. Read freely; mutate only through add_chunk / remove_chunk / set_block so the
native mirror stays in sync.

### `void_below`

*shared/voxel_world.gd*

GDScript: `void_below := false  (property)`

When true, everything below y = 0 is open air (skyblock-style void) instead of a solid floor.

### `native`

*shared/voxel_world.gd*

GDScript: `native: Object = Native.create(&"NativeVoxelWorld")  (property)`

NativeVoxelWorld mirror used by native physics, or null.

### `set_block`

*shared/voxel_world.gd*

GDScript: `set_block(x: int, y: int, z: int, id: int) -> bool`

JavaScript: `api.setBlock(x, y, z, id)`

Returns false if the position is outside the world or in an unloaded chunk.

**See also:** `qualified`, `register_instance`, `set_block_authoritative`

### `daylight`

*shared/world_time.gd*

GDScript: `static daylight(time_of_day: float) -> float`

Sky light multiplier in [NIGHT_LIGHT, 1].

### `phase`

*shared/world_time.gd*

GDScript: `static phase(time_of_day: float) -> String`

Which quarter of the day it is, as a word: "night", "dawn", "day", "dusk". Named here rather than in
whichever mod asked first, so two mods cannot disagree about when dusk begins.
