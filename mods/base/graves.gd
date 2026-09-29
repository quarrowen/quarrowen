extends RefCounted
## Graves and homes: dying leaves a grave holding your things instead of scattering them on the floor,
## and /sethome, /home, /back get you around.
##
## The grave is a normal container block, so anything that works on chests works on it. Breaking it gives
## everything back. Only the player who died (or an admin) can open or break it until it is empty.

const MAX_GRAVES := 3  # older graves of the same player are marked so the newest is obvious

var api
var ids := {}


func setup(mod_api, sounds: Dictionary) -> void:
	api = mod_api
	api.register_container("grave", {"title": "Grave", "groups": [{"name": "items", "count": 41, "columns": 9}]})
	ids.grave = api.register_block("grave", {"group": "Special", "display_name": "Grave", "container": "grave", "sounds": sounds.get("stone", {}),
		"textures": {"top": "textures/grave_top.png", "side": "textures/grave_side.png", "bottom": "textures/grave_top.png"},
		"hardness": 0.6, "placeable": false, "drops": ""})
	api.on("player_death", _on_death)
	api.on("player_join", func(ev):
		# Markers live in memory, so put this player's home back on the map when they join.
		var home = ev.player.data.get("base:home")
		if home is Array and home.size() == 3:
			api.set_map_marker(ev.player, "home", {"label": "Home", "position": Vector3(float(home[0]), float(home[1]), float(home[2])), "color": "#8fd88f"}))
	api.on("container_open", _guard_open)
	api.on("block_break", _guard_break)
	api.register_command("sethome", "Remember this spot as your home", _cmd_sethome)
	api.register_command("home", "Go to the spot you set with /sethome", _cmd_home)
	api.register_command("back", "Go back to where you last died", _cmd_back)


# --- Graves ---------------------------------------------------------------------------------------

func _on_death(ev: Dictionary) -> void:
	var player = ev.player
	player.data["base:death_spot"] = _pack(player.position, api.realm_of(player))
	if ev.keep_inventory or player.is_creative():
		return
	# **The world they died in.** Every block call in here used to default to the overworld, so dying
	# anywhere else built the grave at those coordinates *in the overworld* - over whatever was already
	# standing there, possibly inside somebody's house - and then told the player their things were at a
	# spot they could walk to and find untouched ground. It was invisible until something put a player in
	# another realm and killed them. (2026-09-28)
	var realm: String = api.realm_of(player)
	var spot := _grave_spot(player.position, realm)
	if spot == Vector3i.MAX:
		return  # nowhere to put it: the engine drops the items as usual
	ev.keep_inventory = true  # the grave keeps them instead of the floor
	api.set_block(spot, ids.grave, realm)
	var grave = api.get_container(spot, realm)
	if grave == null:
		ev.keep_inventory = false
		return
	var moved := 0
	var inventory = player.inventory
	for i in inventory.total():
		if inventory.ids[i] > 0 and inventory.counts[i] > 0:
			if grave.add(inventory.ids[i], inventory.counts[i], inventory.data[i]) == 0:
				moved += 1
	if inventory.cursor_count > 0:
		grave.add(inventory.cursor_id, inventory.cursor_count, inventory.cursor_data)
	player.clear_inventory()
	api.set_block_data(spot, _mark(api.get_block_data(spot, realm), player), realm)
	# The marker carries the world too, or a grave in one realm is drawn on the map of another.
	api.set_map_marker(player, "grave", {"label": "Your grave", "position": Vector3(spot),
		"color": "#d8d8e0", "dimension": realm})
	player.send_message("Your things are in a grave at %d, %d, %d - break it to get them back (/back goes there)." % [spot.x, spot.y, spot.z])
	api.info("%s left a grave at %s with %d stacks" % [player.name, spot, moved])


## A free block at or just above where the player died, so the grave never replaces someone's build.
func _grave_spot(position: Vector3, realm := "") -> Vector3i:
	var at := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	for offset in [Vector3i.ZERO, Vector3i.UP, Vector3i.UP * 2, Vector3i.DOWN, Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
			Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var cell: Vector3i = at + offset
		if cell.y < 1 or cell.y > 250:
			continue
		var block: int = api.get_loaded_block(cell, realm)
		if block == 0 or not api.is_solid(block):
			return cell
	return Vector3i.MAX


func _mark(data: Dictionary, player) -> Dictionary:
	data["base:grave"] = {"owner": player.player_id, "name": player.name, "at": int(Time.get_unix_time_from_system())}
	return data


## Whose grave this is, or "" when the block is not a grave (or nobody claimed it).
func _owner_of(position: Vector3i, realm := "") -> String:
	var data: Dictionary = api.get_block_data(position, realm)
	var grave = data.get("base:grave")
	return str(grave.get("owner", "")) if grave is Dictionary else ""


func _guard_open(ev: Dictionary) -> void:
	# **Read from the world the grave is in.** Against the overworld this found no grave at all, so
	# `owner` came back empty and the check below passed for everybody - anyone could open anyone
	# else's grave in a dungeon. The grave itself was made realm-aware on 28 September; its two
	# guards were not. (2026-09-29)
	var owner := _owner_of(ev.position, api.realm_of(ev.player))
	if not owner.is_empty() and owner != ev.player.player_id and not ev.player.has_permission("admin"):
		ev.cancelled = true
		ev.player.show_title("", "This grave is not yours", 1.5)


func _guard_break(ev: Dictionary) -> void:
	if ev.block != ids.grave:
		return
	var owner := _owner_of(ev.position, api.realm_of(ev.player))
	if not owner.is_empty() and owner != ev.player.player_id and not ev.player.has_permission("admin"):
		ev.cancelled = true
		ev.player.show_title("", "This grave is not yours", 1.5)
		return
	if owner == ev.player.player_id:
		api.clear_map_marker(ev.player, "grave")  # emptied: off the map


# --- Homes ----------------------------------------------------------------------------------------

func _cmd_sethome(player, _args: PackedStringArray) -> void:
	player.data["base:home"] = _pack(player.position, api.realm_of(player))
	api.set_map_marker(player, "home", {"label": "Home", "position": player.position, "color": "#8fd88f"})
	player.send_message("Home set here. /home brings you back.")


func _cmd_home(player, _args: PackedStringArray) -> void:
	_go(player, player.data.get("base:home"), "You have no home yet: stand where you want it and type /sethome")


func _cmd_back(player, _args: PackedStringArray) -> void:
	_go(player, player.data.get("base:death_spot"), "You have not died yet - nothing to go back to")


func _go(player, packed, missing: String) -> void:
	if not (packed is Array) or packed.size() < 3:
		player.send_message(missing)
		return
	var to := Vector3(float(packed[0]), float(packed[1]), float(packed[2]))
	# A fourth entry is the realm; three on its own is a spot saved before 29 September 2026, and the
	# overworld is what those meant.
	var realm: String = String(packed[3]) if packed.size() > 3 else ""
	if realm == api.realm_of(player):
		player.teleport(to)
	elif not api.send_to_realm(player, realm, to):
		player.send_message("That place is in a world this server no longer has")


static func _pack(position: Vector3, realm := "") -> Array:
	return [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01), realm]
