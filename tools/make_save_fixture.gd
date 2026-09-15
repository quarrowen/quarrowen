extends Node
## Writes a save-compatibility fixture: a small world made by *this* version of the game with builds, a
## chest, a pig and a player carrying items from several mods (worn armour and item data included), plus
## expected.json describing it. Run it from a checkout of a release, then copy the output to
## tests/fixtures/saves/<version>/ so tests/save_compat_test.tscn keeps checking newer versions load it.
##   godot --headless --path <release checkout> res://tools/make_save_fixture.tscn -- --out=/tmp/fixture

const GameServer = preload("res://engine/server/game_server.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

const MODS := ["vanilla", "industry", "arcana", "guild"]
const INVENTORY := [
	[0, "base:stone_sword", 1, {}], [1, "base:stone_pickaxe", 1, {"damage": 12}], [2, "base:planks", 48, {}], [3, "base:torch", 16, {}],
	[4, "base:iron_ingot", 9, {}], [5, "base:apple", 3, {}], [9, "vanilla:bone", 4, {}], [10, "vanilla:leather", 7, {}],
	[11, "arcana:mana_shard", 5, {}], [12, "industry:cable", 32, {}], [13, "industry:battery", 1, {}], [14, "guild:gold_coin", 11, {}],
	[20, "base:glass", 64, {}], [35, "base:coal", 2, {}],
]
const EQUIPMENT := {"chest": ["base:iron_chestplate", 1, {}]}
const BLOCKS := [[0, 1, 0, "base:planks"], [1, 1, 0, "base:glass"], [2, 1, 0, "base:torch"], [0, 2, 0, "base:planks"], [3, 1, 0, "industry:cable"]]
const CHEST := [[0, "base:iron_ingot", 5], [1, "arcana:mana_shard", 2], [26, "base:apple", 1]]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	if out.is_empty():
		printerr("pass --out=<folder>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var server = GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(MODS), "world": "fixture", "data_dir": out, "seed": 1234, "offline": true})
	if err != OK:
		printerr("server start failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	var origin := Vector3i(20, server.surface_height(20, 20) + 1, 20)
	for b in BLOCKS:
		server.set_block_authoritative(origin + Vector3i(b[0], b[1] - 1, b[2]), server.registry.id_of(b[3]))
	var chest_pos := origin + Vector3i(-2, 0, 0)
	server.set_block_authoritative(chest_pos, server.registry.id_of("base:chest"))
	var chest = server.containers.get_container(chest_pos)
	for c in CHEST:
		chest.set_item(c[0], server.items.id_of(c[1]), c[2])
	server.entities.spawn(server.entities.registry.id_of("vanilla:pig"), Vector3(origin) + Vector3(4.5, 0, 0.5))
	var p := ServerPlayer.new(server, 7, "Fixture")
	p.player_id = "f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1"
	server.players[7] = p
	for s in INVENTORY:
		p.inventory.set_slot(s[0], server.items.id_of(s[1]), s[2], s[3])
	for slot_name in EQUIPMENT:
		p.inventory.set_slot(p.inventory.equipment_index(slot_name), server.items.id_of(EQUIPMENT[slot_name][0]), EQUIPMENT[slot_name][1], EQUIPMENT[slot_name][2])
	p.state.position = Vector3(origin) + Vector3(0.5, 2, 3.5)
	server._meta.names["fixture"] = p.player_id
	server._store_player(p)
	server._save_all(true)
	var expected := {"version": Protocol.GAME_VERSION, "mods": MODS, "world": "fixture", "player_id": p.player_id, "inventory": INVENTORY,
		"equipment": EQUIPMENT, "origin": [origin.x, origin.y, origin.z], "blocks": BLOCKS, "chest": [chest_pos.x, chest_pos.y, chest_pos.z],
		"chest_items": CHEST, "pig_near": [origin.x + 4.5, origin.y, origin.z + 0.5]}
	var f := FileAccess.open(out.path_join("expected.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(expected, "\t"))
	f.close()
	print("[fixture] wrote %s (version %s)" % [out, Protocol.GAME_VERSION])
	server.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
