extends RefCounted
## The industrial half: signals, links, flows, parcels, drives, multiblocks, assemblies, liquids,
## claims and realms.

var api
var ids: Dictionary


func setup(mod_api, id_table: Dictionary) -> void:
	api = mod_api
	ids = id_table
	ids.wire = api.register_block("wire", {"display_name": "Wire",
		"hardness": 0.5, "signal_carry": true, "connect_group": "proving_signal"})
	ids.switch = api.register_block("switch", {"display_name": "Switch",
		"hardness": 0.5, "interactive": true})
	ids.core = api.register_block("core", {"display_name": "Core",
		"hardness": 2.0})
	# A block that listens. Emitting and carrying are block keys; this is the third of the three.
	api.register_signal("core", func(ctx):
		api.set_block_data(ctx.position, {"level": int(ctx.level)}))
	api.on("block_interact", func(ev):
		if ev.block != ids.switch:
			return
		ev.cancelled = true
		api.set_signal(ev.position, 15 if api.signal_at(ev.position) == 0 else 0))
	# Links, and the three things that travel along them.
	api.register_link_kind("cable", {"span": 10.0, "needs_air": true, "draw": "cable", "color": "#c2703c"})
	api.register_link_kind("aether", {"span": 0.0, "wireless": true, "crosses_realms": true})
	api.register_unit("power")
	api.register_drive("shaft")
	# A multiblock, and the assembly it can become.
	# A tag in the key as well as a block, so the "#" path is covered.
	api.register_multiblock("engine", {
		"layers": [["PPP", "PCP", "PPP"]],
		"key": {"P": "#proving:stone_like", "C": "proving:core"},
		"controller": "C"})
	# A realm, so dimensions are covered, and a liquid to put in it.
	api.add_realm("deep", {"display_name": "The Deep", "generator": "void"})
	# A liquid of our own, with a shallow form, plus what happens where two meet.
	ids.slime = api.register_block("slime", {"display_name": "Slime",
		"render": "translucent", "liquid": true})
	ids.slime_thin = api.register_block("slime_thin", {"display_name": "Slime",
		"render": "translucent", "liquid": true, "shape": "slab"})
	api.register_liquid("slime", {"range": 4, "falls": true, "speed": 0.4,
		"shallow": "proving:slime_thin", "shallow_from": 2})
	api.register_liquid_meeting("slime", "proving:slime", "proving:plain")
	_setup_bucket()


## Carrying a liquid about, which is what liquids are for and the one part of them a mod has to write
## itself - the engine supplies sources, flows and `item_use`, not the bucket.
##
## Here because `gameplay_test` had six assertions about scooping and pouring sitting behind
## `if bucket > 0`, where `bucket` was `id_of("vanilla:bucket")`. With that mod gone the id is -1, so
## the whole block stopped running rather than started failing - the same silent-skip the music checks
## had. Asserting the capability against a bucket the test mod owns is the fix for both. (2026-09-21)
##
## Only a **source** goes in: a flow is liquid already on its way somewhere, and scooping it would be
## scooping something about to vanish. Pouring always puts down a source, so slime carried uphill works.
func _setup_bucket() -> void:
	ids.pail = api.register_item("pail", {"display_name": "Pail", "max_stack": 1, "usable": true})
	ids.slime_pail = api.register_item("slime_pail", {"display_name": "Pail of Slime",
		"max_stack": 1, "usable": true})
	api.on("item_use", func(ev):
		if not ev.get("has_target", false):
			return
		var player = ev.player
		var realm_id: String = api.realm_of(player)
		if int(ev.item) == int(ids.pail):
			_scoop(player, ev.position, realm_id)
		elif int(ev.item) == int(ids.slime_pail):
			_pour(player, ev, realm_id))


func _scoop(player, at: Vector3i, realm_id: String) -> void:
	if api.get_block(at, realm_id) != int(ids.slime):
		return
	# State 0 is the source; anything else is a trickle running away from one.
	if api.get_block_state(at, realm_id) != 0:
		player.send_message("That is only a trickle - find where it comes from.")
		return
	if not player.is_creative() and not player.take(int(ids.pail), 1):
		return
	api.set_block(at, 0, realm_id)
	if not player.is_creative():
		player.give(int(ids.slime_pail), 1)


func _pour(player, ev: Dictionary, realm_id: String) -> void:
	# "normal", not "face" - the event calls the struck side the normal.
	var at: Vector3i = Vector3i(ev.position) + Vector3i(ev.get("normal", Vector3i.UP))
	if api.get_block(at, realm_id) != 0:
		return
	if not player.is_creative() and not player.take(int(ids.slime_pail), 1):
		return
	api.set_block(at, int(ids.slime), realm_id)
	if not player.is_creative():
		player.give(int(ids.pail), 1)
