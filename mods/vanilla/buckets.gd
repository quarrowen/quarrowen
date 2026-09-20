extends RefCounted
## Carrying water and lava about.
##
## This is the thing liquids were for. A bucket was worth making before only because a cow would fill
## it; now it picks a spring up out of the ground and puts it down somewhere else, which is how a moat
## gets dug, a farm gets watered and a cave gets flooded on purpose.
##
## Only a **source** goes in the bucket - a flow is water that is already on its way somewhere, and
## scooping it up would be scooping up something that is about to vanish anyway. Emptying one always
## puts down a source, so water carried uphill is water that works when it gets there.

var api
var ids := {}


func setup(mod_api, bucket_id: int) -> void:
	api = mod_api
	ids.empty = bucket_id
	ids.water = api.register_item("water_bucket", {"display_name": "Bucket of Water",
		"icon": "textures/water_bucket.png", "max_stack": 1, "usable": true,
		"lore": ["A spring, carried. Right-click to pour it out."]})
	ids.lava = api.register_item("lava_bucket", {"display_name": "Bucket of Lava",
		"icon": "textures/lava_bucket.png", "max_stack": 1, "usable": true,
		"lore": ["Heavy, and far too hot.", "Right-click to pour it out - carefully."]})
	# Fuel, because a bucket of lava is the obvious thing to burn once you can carry one.
	api.set_fuel("vanilla:lava_bucket", 1000.0)
	api.on("item_use", _on_use)


func _fills() -> Dictionary:
	return {api.block("base:water"): ids.water, api.block("base:lava"): ids.lava}


func _empties() -> Dictionary:
	return {ids.water: api.block("base:water"), ids.lava: api.block("base:lava")}


func _on_use(ev: Dictionary) -> void:
	if not ev.get("has_target", false):
		return
	var player = ev.player
	var realm_id: String = api.realm_of(player)
	if ev.item == ids.empty:
		_fill(player, ev.position, realm_id)
		return
	var pours: Dictionary = _empties()
	if pours.has(ev.item):
		_pour(player, ev, int(pours[ev.item]), realm_id)


## Scooping up: only a source, and the cell is left empty rather than left to fill itself back in.
func _fill(player, at: Vector3i, realm_id: String) -> void:
	var block: int = api.get_block(at, realm_id)
	var holds: Dictionary = _fills()
	if not holds.has(block):
		return
	if api.get_block_state(at, realm_id) != 0:
		player.send_message("That is only a trickle - find where it comes from.")
		return
	if not player.is_creative() and not player.take(ids.empty, 1):
		return
	api.set_block(at, 0, false, 0, realm_id)
	if not player.is_creative():
		player.give(int(holds[block]), 1)
	api.play_sound("engine:click", Vector3(at) + Vector3.ONE * 0.5, 0.8, 0.7)


## Pouring out: into the face the player is looking at, so a bucket behaves like every other block in
## the hand rather than replacing what is aimed at.
func _pour(player, ev: Dictionary, block: int, realm_id: String) -> void:
	var at: Vector3i = ev.position
	var target: int = api.get_block(at, realm_id)
	if api.is_solid(target) or api.is_liquid(target):
		at += ev.get("normal", Vector3i.UP)
		target = api.get_block(at, realm_id)
	if api.is_solid(target):
		return
	if not player.is_creative() and not player.take(ev.item, 1):
		return
	api.set_block(at, block, false, 0, realm_id)  # state 0: what comes out of a bucket is a source
	if not player.is_creative():
		player.give(ids.empty, 1)
	api.play_sound("engine:click", Vector3(at) + Vector3.ONE * 0.5, 0.9, 0.6)
