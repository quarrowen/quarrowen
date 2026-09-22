extends RefCounted
## Where a thing comes from, when the answer is not a recipe.
##
## The recipe book answers "how is this made". Half of what is in a world is never made: ore is in the
## ground, leather is on a cow, the good sword is in a chest at the bottom of something. A player
## holding a block they cannot craft has no way to ask where another one would come from, and the
## bigger the block palette gets the more often that question is the only one they have. (2026-09-22)
##
## **Almost all of it is derived rather than declared.** The engine already knows: every loot table,
## every block's drops, every creature's drops, every ore pass. A mod that registers a creature with
## `drops` has said where that item comes from whether it meant to or not, and asking it to say so a
## second time in a separate registry is how the two fall out of step. `register_source` exists only
## for the things nothing can infer - "traded by the smith", "washes up after a storm".
##
##     api.sources_of(api.item("base:coal"))
##     -> [{kind: "block",  from: "Coal Ore", detail: "mined", chance: 1.0},
##         {kind: "ground", from: "Coal Ore", detail: "in the ground, y 5 to 64", chance: 1.0}]
##
## `chance` is a real probability, not a label: the loot registry weighs each entry against its pool,
## folds in how many times the pool rolls and the host's loot rate, so a creature that always drops
## meat and drops hide half the time reports 1.0 and 0.5.
##
## Rebuilt on demand rather than kept in step: mods can register at any point during load, reload
## replaces whole tables, and a cache that has to be invalidated from seven places is a cache that
## will be wrong. It is asked for by a player opening a screen, which is not a hot path.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")

## What a source can be. Kept as plain strings because they cross to the client and into JavaScript.
const KINDS := ["block", "creature", "container", "ground", "other"]

## Loot names its tables by what owns them; a player wants to hear it in our words.
const KIND_OF_TABLE := {"mob": "creature", "block": "block", "table": "container"}
const DETAIL_OF_TABLE := {"creature": "dropped", "block": "mined", "container": "found in"}

var server
## Sources a mod declared: item id -> [{kind, from, detail}].
var declared := {}


func _init(game_server) -> void:
	server = game_server


## Adds a source nothing could infer. `detail` is shown to a player, so write it as a sentence.
func declare(item_id: int, source: Dictionary) -> bool:
	if item_id <= 0:
		push_error("register_source: unknown item")
		return false
	var kind := String(source.get("kind", "other"))
	if not kind in KINDS:
		push_error("register_source: kind must be one of %s, not '%s'" % [", ".join(KINDS), kind])
		return false
	if not declared.has(item_id):
		declared[item_id] = []
	declared[item_id].append({
		"kind": kind,
		"from": String(source.get("from", "")),
		"detail": String(source.get("detail", "")).left(120),
		"chance": clampf(float(source.get("chance", 1.0)), 0.0, 1.0),
	})
	return true


## Everywhere `item_id` comes from, most likely first. Always returns an Array.
func of_item(item_id: int) -> Array:
	if item_id <= 0:
		return []
	_materialise()
	var found: Array = []
	_from_tables(item_id, found)
	_from_ground(item_id, found)
	for extra in declared.get(item_id, []):
		found.append((extra as Dictionary).duplicate())
	# Certain things before chancy ones: a player wants the reliable answer first.
	found.sort_custom(func(a, b): return float(a.get("chance", 1.0)) > float(b.get("chance", 1.0)))
	return _once_each(found)


## One line per thing it comes from, keeping the likeliest.
##
## An ore is both a block that drops it and a thing in the ground, and a mod may declare a source for
## something that also drops - telling a player the same stone twice reads as a bug in the game rather
## than in the screen. Sorted by chance already, so the first of a pair is the one worth keeping.
func _once_each(found: Array) -> Array:
	var seen := {}
	var out: Array = []
	for row: Dictionary in found:
		var key: String = "%s/%s" % [row.get("kind", ""), row.get("from", "")]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(row)
	return out


## Makes sure every block's and every creature's drop table exists before we ask what is in it.
##
## A creature's `drops` list is not a separate mechanism: `entities.gd` rolls
## `loot.table_for_entity(def)` on death, and that *builds* the table the first time something dies.
## So until a grazer has been killed, nothing has ever asked for `mob:proving:grazer` and the loot
## registry has never heard of it - which is why reading declarations by hand here looked necessary.
## Building them up front instead means one place works out where things come from, and it is the place
## that already knows that meat is guaranteed and hide is one kill in two. Doing it early is what
## happens on the first kill anyway, and `_table_for` already copes with a mod extending a table
## before or after. (2026-09-22)
func _materialise() -> void:
	for def: Dictionary in server.entities.registry.defs:
		if def.get("drops") is Array and not (def.drops as Array).is_empty():
			server.loot.table_for_entity(def)
	for id in server.registry.defs.size():
		if id == BlockRegistry.AIR or server.registry.breakable_lut[id] == 0:
			continue
		var drops: Array = server._default_drops(id)
		if not drops.is_empty():
			server.loot.table_for_block(id, drops)


## Loot tables that can produce it - chests, fishing, rewards, ore, creature drops, anything a mod rolls.
##
## `LootRegistry.sources_of` already does this, and does it properly: it weighs every entry against its
## pool, folds in how many times the pool rolls and the host's loot rate, and hands back the name a
## player would recognise the table by rather than "block:base:coal_ore". Walking `pools` by hand here
## gave a made-up flat chance and an internal name, which is the mistake CLAUDE.md warns about - the
## engine-internal readers are what get reimplemented, because no document describes them. (2026-09-22)
func _from_tables(item_id: int, found: Array) -> void:
	for row: Dictionary in server.loot.sources_of(item_id):
		var kind: String = KIND_OF_TABLE.get(String(row.get("kind", "table")), "container")
		found.append({
			"kind": kind,
			"from": String(row.get("source", "")),
			"detail": DETAIL_OF_TABLE.get(kind, "found in"),
			"chance": float(row.get("chance", 0.0)),
		})


## Ore passes: the block is generated in the ground, so whatever it drops comes from the ground.
func _from_ground(item_id: int, found: Array) -> void:
	for r in server.realms.values():
		for pass_object in r.generation_passes:
			var ore = pass_object.get("ore") if pass_object is Dictionary else null
			if ore == null and "ore" in pass_object:
				ore = pass_object.ore
			if ore == null:
				continue
			var ore_id := int(ore)
			if not server.registry.is_valid(ore_id):
				continue
			var gives := false
			for drop in server._default_drops(ore_id):
				if drop is Array and drop.size() >= 1 and int(drop[0]) == item_id:
					gives = true
			if not gives and server.items.id_of(String(server.registry.defs[ore_id].name)) != item_id:
				continue
			var detail := "in the ground"
			var low = pass_object.get("min_y") if pass_object is Dictionary else null
			var high = pass_object.get("max_y") if pass_object is Dictionary else null
			if low != null and high != null:
				detail = "in the ground, y %d to %d" % [int(low), int(high)]
			found.append({"kind": "ground", "from": server.registry.display_name(ore_id), "detail": detail, "chance": 1.0})
