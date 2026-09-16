extends RefCounted
## What comes out of things: a mob that dies, a block that breaks, a chest in a dungeon, or anything a mod
## asks for. One table format for all of them (see docs/loot.md).
##
##   {"pools": [{"rolls": [0, 2], "when": {...}, "entries": [
##        {"item": "base:rotten_flesh", "count": [1, 2], "weight": 3, "data": {}},
##        {"table": "vanilla:junk", "weight": 1},   # roll another table instead
##        {"empty": true, "weight": 4},             # the miss: this is how a chance below 1 is written
##   ]}]}
##
## Pools roll independently, so "always some flesh, and separately a small chance of something good" needs
## no arithmetic. A table may also use the older {rolls, entries} shape; it is read as a single pool, and a
## mob's or block's `drops` list becomes a table with one pool per line (see from_drops), so mods written
## before this keep working and get conditions, tuning and extension for free.
##
## Rolls are seeded when it matters (a chest holds the same loot for a given world seed and position) and
## otherwise use the global RNG.

const Semver = preload("res://engine/shared/semver.gd")

## How unlikely a drop has to be before it counts as a find worth announcing.
const RARE_CHANCE := 0.06
## Rolls of bad luck before a table's rarest entry is given anyway (see `pity`).
const PITY_ROLLS := 40
const MAX_POOLS := 24
const MAX_ENTRIES := 256
## How deep a table may refer to other tables.
const MAX_DEPTH := 4

var tables := {}
## Set false to stop the engine announcing rare finds (a server that would rather stay quiet).
var announce_rare := true
## Multiplies how many times every pool rolls: a host's "how much loot" setting (see ModApi.set_loot_rate).
var rate := 1.0
## Temporary changes on top of `rate`, for events ("double coins this weekend", "pumpkins all October"):
## "table:<name>" -> how much more often that table's pools roll, "item:<name>" -> how much more often that
## item comes up in any table. Each is {factor, until} where `until` is a unix time, or 0 for no end.
var boosts := {}
## Tables already built from a mob's or block's `drops` list, so extending one first does not replace it.
var _generated := {}

var _server


func _init(game_server) -> void:
	_server = game_server


## Declares a table. Entries naming an item that does not exist are left out with a warning rather than
## dropping nothing at all later.
func register(table_name: String, def: Dictionary) -> void:
	tables[table_name] = _clean(table_name, def)


## Adds pools to a table another mod owns, without forking it. Unknown tables are created. `owner` is the
## mod adding them, so reloading that mod takes its pools away again instead of stacking another copy on
## every save.
func extend(table_name: String, def: Dictionary, owner := "") -> void:
	var extra := _clean(table_name, def)
	for pool: Dictionary in extra.pools:
		pool.owner = owner
	if not tables.has(table_name):
		tables[table_name] = extra
		return
	var existing: Dictionary = tables[table_name]
	existing.pools.append_array(extra.pools)
	existing.pools = existing.pools.slice(0, MAX_POOLS)


## Takes back everything a mod added to other mods' tables, for a reload.
func forget(owner: String) -> void:
	for table_name: String in tables:
		var pools: Array = tables[table_name].pools
		tables[table_name].pools = pools.filter(func(pool): return str(pool.get("owner", "")) != owner)


func has(table_name: String) -> bool:
	return tables.has(table_name)


## Rolls a table. `context` says what the loot came out of, so conditions can look at it:
##   seed        an int to make the roll repeatable (a chest); left out, the roll is random
##   player      who caused it (their luck, what they have already found)
##   cause       "player", "mob", "fire", "fall", … for a mob's death
##   tool        the item id in the hand that did it
##   position    where it happened (depth and biome come from this)
## Returns [[item id, count, data], …].
func roll(table_name: String, context := {}) -> Array:
	var ctx: Dictionary = (context if context is Dictionary else {}).duplicate()
	ctx.table = table_name  # so `first_time` can ask whether this player has met this source before
	var rng := RandomNumberGenerator.new()
	if ctx.has("seed"):
		rng.seed = int(ctx.seed)
	else:
		rng.randomize()
	var out := []
	_roll_into(out, table_name, ctx, rng, 0)
	awarded(table_name, out, ctx)
	return out


## Rolls without any of the consequences of actually getting the loot. Use this when the drop might still
## be thrown away - a creative player breaking a block, or a handler that may cancel the break - and call
## `awarded` once it is really handed over.
func preview(table_name: String, context := {}) -> Array:
	var ctx: Dictionary = (context if context is Dictionary else {}).duplicate()
	ctx.table = table_name
	ctx.preview = true
	var rng := RandomNumberGenerator.new()
	if ctx.has("seed"):
		rng.seed = int(ctx.seed)
	else:
		rng.randomize()
	var out := []
	_roll_into(out, table_name, ctx, rng, 0)
	return out


## What getting the loot means for this player: they have now met this table, a long run of bad luck pays
## out, and a find worth announcing is announced. Called for you by `roll`; call it yourself after a
## `preview` that really happened.
func awarded(table_name: String, out: Array, context := {}) -> void:
	_after_roll(table_name, out, context if context is Dictionary else {})


## A mob's or block's `drops` list as a table: [[item, count, chance]] becomes one pool per line, each
## rolling once, so an old definition behaves exactly as it did.
func from_drops(drops: Array) -> Dictionary:
	var pools := []
	for drop in drops:
		if not (drop is Array) or drop.size() < 2:
			continue
		var chance := clampf(float(drop[2]) if drop.size() > 2 else 1.0, 0.0, 1.0)
		var entries := [{"item": drop[0], "count": drop[1], "weight": chance}]
		if chance < 1.0:
			entries.append({"empty": true, "weight": 1.0 - chance})
		pools.append({"rolls": 1, "entries": entries})
	return {"pools": pools}


## Registers every loot/*.json in a mod folder as "<mod>:<file name>", so a creator can tune what drops
## without touching code. A file may hold one table, or {"<name>": {table}, …} for several.
func load_files(mod_id: String, mod_dir: String) -> void:
	var dir := DirAccess.open(mod_dir.path_join("loot"))
	if dir == null:
		return
	for file in dir.get_files():
		if file.get_extension().to_lower() != "json":
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(mod_dir.path_join("loot").path_join(file)))
		if not (parsed is Dictionary):
			_server.dev_log.add("warn", mod_id, "loot/%s is not a JSON object" % file)
			continue
		if parsed.has("pools") or parsed.has("entries"):
			register("%s:%s" % [mod_id, file.get_basename()], parsed)
			continue
		for name in parsed:
			if parsed[name] is Dictionary:
				register("%s:%s" % [mod_id, name], parsed[name])


## The table a mob's or block's drops come from: the one its definition names in `loot`, or one made from
## its old `drops` list the first time it is needed (so mods written before tables keep working and still
## get conditions, tuning and rare finds). Generated tables are named "mob:<name>" and "block:<name>".
func table_for_entity(def: Dictionary) -> String:
	return _table_for(def, "mob:" + str(def.get("name", "")), def.get("drops", []))


func table_for_block(block: int, default_drops: Array) -> String:
	var def: Dictionary = _server.registry.defs[block]
	return _table_for(def, "block:" + str(def.get("name", block)), default_drops)


func _table_for(def: Dictionary, generated_name: String, drops) -> String:
	var named := str(def.get("loot", ""))
	if not named.is_empty():
		return named
	if not _generated.has(generated_name):
		# A mod may have extended this table before anything was killed or broken (a first-kill bonus, say),
		# so the drops go in front of whatever is already there rather than instead of it.
		_generated[generated_name] = true
		var built := _clean(generated_name, from_drops(drops if drops is Array else []))
		built.pools.append_array(tables.get(generated_name, {}).get("pools", []))
		tables[generated_name] = built
	return generated_name


## Fills a container from its `loot` block data, once. `player` is whoever opened it, when known.
##
## A chest whose data says `personal: true` is rolled for each player separately: everyone who opens it
## gets their own loot, handed straight to them, so nobody has to race a sibling for the good item. The
## chest is then an ordinary chest to keep things in. Any other chest is filled once and shared.
func fill(container, player = null) -> void:
	var store: Dictionary = container._store if container.get("_store") != null else {}
	var table := str(store.get("loot", ""))
	if table.is_empty():
		return
	if bool(store.get("personal", false)):
		# Everyone gets their own, so the chest itself is never filled - not even when something other
		# than a player opening it looks inside (a hopper, a crafting table pulling stock, a click on a
		# slot). Falling through to the shared roll here would hand out a second, free copy of the loot.
		if player != null:
			_fill_personal(container, store, table, player)
		return
	var seed_value := int(store.get("structure_seed", randi()))
	store.erase("loot")
	var context := {"seed": seed_value, "position": container.position, "source": "container"}
	if player != null:
		context.player = player
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	for stack in roll(table, context):
		# Scatter the loot over the empty slots, so a chest does not look packed from the left.
		var free := []
		for slot in container.size():
			if int(container.get_item(slot).item) == 0:
				free.append(slot)
		if free.is_empty():
			break
		container.set_item(free[rng.randi_range(0, free.size() - 1)], stack[0], stack[1], stack[2])
	_server.emit("loot_generated", {"position": container.position, "table": table})


## Everyone who opens this chest gets their own loot, once each.
func _fill_personal(container, store: Dictionary, table: String, player) -> void:
	var looted: Dictionary = store.get("looted", {}) if store.get("looted") is Dictionary else {}
	if looted.has(player.player_id):
		return
	looted[player.player_id] = true
	store.looted = looted
	var stacks := roll(table, {"seed": hash([int(store.get("structure_seed", 0)), player.player_id]),
		"player": player, "position": container.position, "source": "container"})
	var names := []
	for stack in stacks:
		player.give(stack[0], stack[1], stack[2])  # a full pack drops the rest at their feet
		names.append("%s%s" % ["%d × " % int(stack[1]) if int(stack[1]) > 1 else "", _server.items.display_name(stack[0])])
	_server.play_sound_at("engine:discover", Vector3(container.position) + Vector3.ONE * 0.5)
	player.send_message("The chest had something for you: %s" % ", ".join(PackedStringArray(names)) if not names.is_empty()
		else "The chest was empty this time.")
	_server.emit("loot_generated", {"position": container.position, "table": table, "player": player})


## Makes something more (or less) common for a while: `target` is a table name, an item name, or either
## with its "table:"/"item:" prefix; `factor` is how much more often; `seconds` ends it on its own (0: it
## stays until changed). Setting the factor back to 1 clears it.
func set_boost(target: String, factor: float, seconds := 0.0) -> String:
	var key := target if target.begins_with("table:") or target.begins_with("item:") else \
		("table:" + target if tables.has(target) else "item:" + target)
	# A typo would otherwise be announced to the server as an event that then does nothing.
	if key.begins_with("item:") and _server.items.id_of(key.substr(5)) <= 0:
		return "Nothing here is called '%s' - name an item like base:coal, or a loot table" % target
	if is_equal_approx(factor, 1.0) or factor < 0.0:
		boosts.erase(key)
		return ""
	boosts[key] = {"factor": factor, "until": int(Time.get_unix_time_from_system() + seconds) if seconds > 0.0 else 0}
	return ""


## What `target` is multiplied by right now, 1.0 when nothing applies. Expired events clear themselves.
func factor_for(key: String) -> float:
	var boost = boosts.get(key)
	if not (boost is Dictionary):
		return 1.0
	if int(boost.until) > 0 and Time.get_unix_time_from_system() > int(boost.until):
		boosts.erase(key)
		return 1.0
	return float(boost.factor)


## Everything a host turned up or down, for the admin screen and /loot: [{target, factor, ends_in}].
func active_boosts() -> Array:
	var now := int(Time.get_unix_time_from_system())
	var out := []
	for key: String in boosts.keys():
		if factor_for(key) == 1.0:
			continue
		var boost: Dictionary = boosts[key]
		out.append({"target": key, "factor": float(boost.factor), "ends_in": maxi(0, int(boost.until) - now) if int(boost.until) > 0 else 0})
	out.sort_custom(func(a, b): return a.target < b.target)
	return out


func _entry_factor(entry: Dictionary) -> float:
	if entry.has("table"):
		return factor_for("table:" + str(entry.table))
	return factor_for("item:" + str(entry.get("item", ""))) if entry.has("item") else 1.0


## How likely this table is to give `item_id` at all, as 0-1. Used to tell a find worth announcing from
## an everyday one, so nothing has to be marked "rare" by hand.
## Boosts and the loot rate count here: during a "coal everywhere" event, coal is common, and announcing
## every lump of it as a rare find would drown the chat the event is supposed to liven up.
func chance_of(table_name: String, item_id: int) -> float:
	var table: Dictionary = tables.get(table_name, {})
	var miss := 1.0
	for pool: Dictionary in table.get("pools", []):
		var total := 0.0
		var wanted := 0.0
		for entry: Dictionary in pool.entries:
			var weight: float = entry.weight * _entry_factor(entry)
			total += weight
			if _server.items.id_of(str(entry.get("item", ""))) == item_id:
				wanted += weight
		if total <= 0.0 or wanted <= 0.0:
			continue
		var rolls: float = maxf(float(pool.rolls[0] + pool.rolls[1]) * 0.5, 0.0)
		if not bool(pool.get("guaranteed", false)):
			rolls *= rate * factor_for("table:" + table_name)
		miss *= pow(1.0 - wanted / total, rolls)
	return 1.0 - miss


## Everywhere an item can come from: [{table, kind ("mob" | "block" | "table"), source, chance, count}],
## likeliest first. This is what the guide's "what drops this?" is built from, so a player can find out
## where something comes from without being told by an adult.
func sources_of(item_id: int) -> Array:
	if item_id <= 0:
		return []
	var out := []
	for table_name: String in tables:
		var chance := chance_of(table_name, item_id)
		if chance <= 0.0:
			continue
		var count := [99, 0]
		for pool: Dictionary in tables[table_name].pools:
			for entry: Dictionary in pool.entries:
				if entry.has("item") and _server.items.id_of(str(entry.item)) == item_id:
					count = [mini(count[0], entry.count[0]), maxi(count[1], entry.count[1])]
		out.append({"table": table_name, "kind": kind_of(table_name), "source": describe(table_name),
			"chance": chance, "count": count})
	out.sort_custom(func(a, b): return a.chance > b.chance)
	return out


## Where things come from, small enough to send a client once: {item id: [[source, percent], …]}, at most
## a few sources each. The tooltip's "Dropped by" line is built from this.
func sources_index(limit := 3) -> Dictionary:
	var out := {}
	for table_name: String in tables:
		var described := describe(table_name)
		for pool: Dictionary in tables[table_name].pools:
			for entry: Dictionary in pool.entries:
				if not entry.has("item"):
					continue
				var id := int(_server.items.id_of(str(entry.item)))
				if id <= 0:
					continue
				var rows: Array = out.get(id, [])
				if rows.any(func(row): return row[0] == described):
					continue
				rows.append([described, int(round(chance_of(table_name, id) * 100.0))])
				out[id] = rows
	for id in out:
		var rows: Array = out[id]
		rows.sort_custom(func(a, b): return a[1] > b[1])
		out[id] = rows.slice(0, limit)
	return out


## Whether a table belongs to a mob, a block, or is a table in its own right (a chest, a reward).
func kind_of(table_name: String) -> String:
	if table_name.begins_with("mob:"):
		return "mob"
	if table_name.begins_with("block:"):
		return "block"
	return "table"


## The name a player would recognise a table by: the mob or block it belongs to, or the table's own name.
func describe(table_name: String) -> String:
	match kind_of(table_name):
		"mob":
			var type := int(_server.entities.registry.id_of(table_name.substr(4)))
			return str(_server.entities.registry.defs[type].display_name) if type > 0 else table_name.substr(4)
		"block":
			var block := int(_server.registry.id_of(table_name.substr(6)))
			return _server.registry.display_name(block) if block > 0 else table_name.substr(6)
	return table_name.get_slice(":", 1).capitalize()


## True when getting this item from this table is a find worth making a fuss about.
func is_rare(table_name: String, item_id: int) -> bool:
	var chance := chance_of(table_name, item_id)
	return chance > 0.0 and chance <= RARE_CHANCE


func _roll_into(out: Array, table_name: String, ctx: Dictionary, rng: RandomNumberGenerator, depth: int) -> void:
	var table: Dictionary = tables.get(table_name, {})
	if table.is_empty() or depth > MAX_DEPTH:
		return
	for pool: Dictionary in table.pools:
		if not _passes(pool.get("when", {}), ctx, rng):
			continue
		var weights := []
		var total := 0.0
		for entry: Dictionary in pool.entries:
			var weight: float = entry.weight * _entry_factor(entry) if _passes(entry.get("when", {}), ctx, rng) else 0.0
			weights.append(weight)
			total += weight
		if total <= 0.0:
			continue
		var rolls := rng.randi_range(pool.rolls[0], pool.rolls[1])
		if not bool(pool.get("guaranteed", false)):
			rolls = int(round(rolls * rate * factor_for("table:" + table_name)))
		for i in rolls:
			var pick := rng.randf() * total
			for index in pool.entries.size():
				var entry: Dictionary = pool.entries[index]
				if weights[index] <= 0.0:
					continue
				pick -= weights[index]
				if pick > 0.0:
					continue
				if entry.has("table"):
					_roll_into(out, str(entry.table), ctx, rng, depth + 1)
				elif not bool(entry.get("empty", false)):
					var id := int(_server.items.id_of(str(entry.item)))
					if id > 0:
						out.append([id, rng.randi_range(entry.count[0], entry.count[1]), entry.data.duplicate(true)])
				break


## Whether a condition holds for this roll. An unknown condition never holds, so a typo is visible
## (nothing drops) rather than silently letting everything through.
func _passes(when, ctx: Dictionary, rng: RandomNumberGenerator) -> bool:
	if not (when is Dictionary) or when.is_empty():
		return true
	for key in when:
		var want = when[key]
		match str(key):
			"killed_by", "cause":
				if not _matches(str(ctx.get("cause", "")), want):
					return false
			"tool":
				if not _tool_matches(int(ctx.get("tool", 0)), want):
					return false
			"biome":
				if not _matches(_biome_at(ctx), want):
					return false
			"depth":
				var y := int(ctx.get("position", Vector3.ZERO).y) if ctx.has("position") else 0
				if want is Array and want.size() == 2 and (y < int(want[0]) or y > int(want[1])):
					return false
			"time":
				var clock: float = _server.get_time_of_day()
				var night := clock < 0.25 or clock > 0.75
				if str(want) == "night" and not night:
					return false
				if str(want) == "day" and night:
					return false
			"chance":
				if rng.randf() > float(want):
					return false
			"first_time":
				if bool(want) != _first_time(ctx):
					return false
			"player":
				if ctx.get("player") == null:
					return false
			_:
				return false
	return true


static func _matches(value: String, want) -> bool:
	if want is Array:
		return want.map(func(v): return str(v)).has(value)
	return str(want) == value


## `tool` takes an item name, or {"material": "iron"} / {"tier": 2} to accept a whole class of tools.
func _tool_matches(tool_id: int, want) -> bool:
	if tool_id <= 0:
		return false
	var def: Dictionary = _server.items.get_def(tool_id)
	if want is Dictionary:
		if want.has("tier") and int(def.get("tier", 0)) < int(want.tier):
			return false
		if want.has("material") and str(def.get("material", "")) != str(want.material):
			return false
		return true
	return _matches(_server.items.name_of(tool_id), want)


func _biome_at(ctx: Dictionary) -> String:
	if not ctx.has("position") or _server.biome_generator == null:
		return ""
	var pos: Vector3 = ctx.position
	return str(_server.biome_generator.biome_at(int(pos.x), int(pos.z)))


## True the first time this player gets loot from this table (the reward for meeting something new).
func _first_time(ctx: Dictionary) -> bool:
	var player = ctx.get("player")
	var table := str(ctx.get("table", ""))
	if player == null or table.is_empty():
		return false
	var seen: Dictionary = player.data.get("loot_seen", {})
	return not seen.has(table)

## Reads a table into the one shape the roller uses: pools of weighted entries. The older {rolls, entries}
## shape becomes a single pool, so tables written before pools existed still work.
func _clean(table_name: String, def: Dictionary) -> Dictionary:
	var raw: Array = def.get("pools", []) if def.get("pools") is Array else [def]
	var pools := []
	for pool in raw.slice(0, MAX_POOLS):
		if not (pool is Dictionary):
			continue
		var entries := []
		for entry in (pool.get("entries", []) if pool.get("entries") is Array else []):
			var clean := _clean_entry(table_name, entry)
			if not clean.is_empty():
				entries.append(clean)
			if entries.size() >= MAX_ENTRIES:
				break
		if entries.is_empty():
			continue
		pools.append({
			"rolls": _range(pool.get("rolls", [2, 4] if pools.is_empty() and not def.has("pools") else 1)),
			"when": pool.get("when", {}) if pool.get("when") is Dictionary else {},
			"guaranteed": bool(pool.get("guaranteed", false)),
			"entries": entries,
		})
	return {"pools": pools}


func _clean_entry(table_name: String, entry) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var out := {
		"weight": maxf(float(entry.get("weight", 1.0)), 0.0),
		"count": _range(entry.get("count", 1)),
		"data": entry.get("data", {}).duplicate(true) if entry.get("data") is Dictionary else {},
		"when": entry.get("when", {}) if entry.get("when") is Dictionary else {},
	}
	if bool(entry.get("empty", false)):
		out.empty = true
		return out
	if entry.has("table"):
		out.table = str(entry.table)
		return out
	var item: String = str(entry.get("item", "")) if not (entry.get("item") is int) else _server.items.name_of(int(entry.item))
	if _server.items.id_of(item) <= 0:
		push_warning("[loot] %s: unknown item '%s' left out" % [table_name, entry.get("item", "")])
		return {}
	out.item = item
	return out


static func _range(value) -> Array:
	if value is Array and value.size() == 2:
		return [int(value[0]), int(value[1])]
	return [int(value), int(value)]


## After a roll: remembers that this player has met this table, gives the rare thing anyway after a long
## run of bad luck, and tells the rest of the engine about a find worth announcing.
func _after_roll(table_name: String, out: Array, ctx: Dictionary) -> void:
	var player = ctx.get("player")
	if player == null or not str(ctx.get("source", "")).is_empty() and str(ctx.get("source", "")) == "preview":
		return
	var seen: Dictionary = player.data.get("loot_seen", {})
	var first_time := not seen.has(table_name)
	seen[table_name] = true
	player.data.loot_seen = seen
	if first_time:
		# Something this player had not met before: a mod can make a moment of it.
		_server.emit("loot_first_time", {"player": player, "table": table_name, "source": str(ctx.get("source", ""))})
	var found_rare := false
	var rare_ids := {}
	for stack in out:
		if is_rare(table_name, int(stack[0])):
			found_rare = true
			rare_ids[int(stack[0])] = true
	# Bad luck does not last, but it is counted per table: forty stone blocks should not pay out the rare
	# drop of the next mob you happen to kill. Only tables that hold something rare count at all.
	var wanted := rarest(table_name)
	if not wanted.is_empty():
		var pity: Dictionary = player.data.get("loot_pity", {})
		var count := int(pity.get(table_name, 0))
		if found_rare:
			count = 0
		else:
			count += 1
			if count >= PITY_ROLLS:
				count = 0
				found_rare = true
				rare_ids[wanted.item] = true
				out.append([wanted.item, wanted.count, {}])
		pity[table_name] = count
		player.data.loot_pity = pity
	if not found_rare:
		return
	var where = ctx.get("position", player.state.position if player.get("state") != null else Vector3.ZERO)
	for stack in out:
		if not rare_ids.has(int(stack[0])):
			continue
		var ev: Dictionary = _server.emit("rare_loot", {"player": player, "item": int(stack[0]), "count": int(stack[1]),
			"table": table_name, "position": where, "announce": announce_rare})
		if bool(ev.get("announce", true)):
			_server.announce_rare_loot(player, int(stack[0]), int(stack[1]), where if where is Vector3 else Vector3(where))


## The least likely thing a table can give, as {item, count}: what a run of bad luck eventually pays out.
func rarest(table_name: String) -> Dictionary:
	var table: Dictionary = tables.get(table_name, {})
	var best := {}
	var best_chance := RARE_CHANCE + 0.0001
	for pool: Dictionary in table.get("pools", []):
		for entry: Dictionary in pool.entries:
			if not entry.has("item"):
				continue
			var id := int(_server.items.id_of(str(entry.item)))
			if id <= 0:
				continue
			var chance := chance_of(table_name, id)
			if chance > 0.0 and chance < best_chance:
				best_chance = chance
				best = {"item": id, "count": int(entry.count[0])}
	return best
