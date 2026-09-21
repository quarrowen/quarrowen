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
