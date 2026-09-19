extends RefCounted
## The cable spool: how a player actually strings a cable between two places.
##
## The engine can hold a link between any two faces, but until something lets a player *make* one, all
## of that is unreachable. This is that something, and it is deliberately the smallest thing that
## works: right-click one pole to take hold of the cable, right-click another to fix it. Right-click
## the air to let go.
##
## Every refusal the engine gives back is a sentence ("Too far apart: 30 blocks, and this reaches 14"),
## so it is shown to the player as it is. A child who cannot run a cable should learn why from the
## game rather than from an adult.

const KIND := "cable"

var api
var ids: Dictionary
## Who is holding the loose end, and where it started. Cleared when they let go, finish, or log out.
var _holding := {}  # peer id -> Vector3i


func setup(mod_api, block_ids: Dictionary) -> void:
	api = mod_api
	ids = block_ids
	# A pole is something to string a cable *between*: cheap, tall, and no use for anything else.
	ids.pole = api.register_block("pole", {"display_name": "Cable Pole", "textures": "textures/pole.png",
		"shape": "fence", "connect_group": "power", "hardness": 1.0, "drops": "industry:pole"})
	ids.spool = api.register_item("cable_spool", {"display_name": "Cable Spool",
		"icon": "textures/cable_spool.png", "usable": true, "max_stack": 1,
		"lore": ["Right-click a pole to take the cable.", "Right-click another to fix it.", "Right-click the air to let go."]})

	api.register_link_kind(KIND, {"span": 14, "draw": "cable", "color": "#c8822e", "item": "industry:cable"})
	api.register_recipe({"industry:cable": 4, "base:stick": 1}, "industry:cable_spool")
	api.register_recipe({"base:planks": 2, "industry:cable": 1}, "industry:pole", 2)

	api.on("item_use", _on_use)
	api.on("player_leave", func(ev): _holding.erase(ev.player.peer_id))
	api.on("block_broken", func(ev):
		# The pole is gone, so whoever was stringing from it is holding nothing.
		for peer in _holding.keys():
			if _holding[peer] == ev.position:
				_holding.erase(peer))


## Whether a cable may be fixed to this block. Poles and machines, not the middle of a wall: a cable
## fixed to anything at all would let a player wire two bases together along the ground.
func _can_hold_cable(block: int) -> bool:
	return block in [ids.pole, ids.generator, ids.solar, ids.battery, ids.lamp, ids.lamp_on, ids.miner]


func _on_use(ev: Dictionary) -> void:
	if api.item_name(ev.item) != "industry:cable_spool":
		return
	var player = ev.player
	var peer: int = player.peer_id
	if not ev.get("has_target", false):
		if _holding.erase(peer):
			player.send_message("You let the cable go.")
		return
	var target: Vector3i = ev.position
	if not _can_hold_cable(api.get_block(target)):
		player.send_message("A cable needs a pole or a machine to hold on to.")
		return
	if not _holding.has(peer):
		_holding[peer] = target
		player.send_message("You take hold of the cable. Right-click where it should go.")
		return
	var from: Vector3i = _holding[peer]
	if from == target:
		_holding.erase(peer)
		player.send_message("You let the cable go.")
		return
	# Face 0 (the top) at both ends: a cable strung between poles hangs from the tops of them, which is
	# where anybody would expect it and saves asking a player to think about faces.
	var made: int = api.link(KIND, {"position": from, "face": 0}, {"position": target, "face": 0})
	if made == 0:
		player.send_message(api.link_problem())  # the engine's own words: they are already a sentence
		return
	_holding.erase(peer)
	player.send_message("The cable is up.")
	api.play_sound("engine:click", Vector3(target) + Vector3.ONE * 0.5, 1.0, 0.9)
