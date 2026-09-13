extends Node
## Offline tests of the gameplay foundation (no networking):
##   godot --headless --path . res://tests/gameplay_test.tscn
## Inventory rules, entity physics, item stacks, damage/death events and persistent entities.

const GameServer = preload("res://engine/server/game_server.gd")
const Inventory = preload("res://engine/shared/inventory.gd")
const EntityPhysics = preload("res://engine/shared/entity_physics.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")
const SoundRegistry = preload("res://engine/shared/sound_registry.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

const DATA_DIR := "user://gameplay_test"
var _failures := 0


func _ready() -> void:
	_inventory_rules()
	_registries()
	await _server_rules()
	_remove_tree(ProjectSettings.globalize_path(DATA_DIR))
	print("[gameplay] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _inventory_rules() -> void:
	var stack64 := func(_id): return 64
	var inv := Inventory.new()
	_check(inv.add(5, 100) == 0 and inv.counts[0] == 64 and inv.counts[1] == 36, "add fills stacks in order")
	inv.click(0, 1, false, stack64)
	_check(inv.cursor_id == 5 and inv.cursor_count == 64 and inv.ids[0] == 0, "left click picks up a stack")
	inv.click(1, 1, false, stack64)
	_check(inv.counts[1] == 64 and inv.cursor_count == 36, "left click merges up to the stack limit")
	inv.click(20, 2, false, stack64)
	_check(inv.ids[20] == 5 and inv.counts[20] == 1 and inv.cursor_count == 35, "right click places one")
	inv.click(30, 1, false, stack64)
	_check(inv.counts[30] == 35 and inv.cursor_count == 0, "left click puts the whole cursor down")
	inv.click(30, 2, false, stack64)
	_check(inv.cursor_count == 18 and inv.counts[30] == 17, "right click picks up half")
	inv.set_slot(2, 7, 3)
	inv.click(2, 1, false, stack64)
	_check(inv.ids[2] == 5 and inv.counts[2] == 18 and inv.cursor_id == 7 and inv.cursor_count == 3, "clicking a different item swaps")
	inv.clear()
	inv.set_slot(3, 9, 10)
	inv.click(3, 1, true, stack64)
	_check(inv.ids[3] == 0 and inv.ids[Inventory.HOTBAR] == 9 and inv.counts[Inventory.HOTBAR] == 10, "shift click moves hotbar -> main")
	var old := PackedInt32Array([1, 2, 0, 0, 0, 0, 0, 0, 0, 10, 20, 0, 0, 0, 0, 0, 0, 0])
	var migrated := Inventory.new()
	_check(migrated.load_packed(old) and migrated.ids[1] == 2 and migrated.counts[1] == 20 and migrated.ids.size() == Inventory.SIZE,
		"9-slot inventories from older saves load into the hotbar")
	var round_trip := Inventory.new()
	_check(round_trip.load_packed(inv.to_packed()) and round_trip.ids == inv.ids, "inventory round-trips through to_packed")


func _registries() -> void:
	var entities := EntityRegistry.new()
	entities.register({"name": "test:blob", "model": "test:models/blob.glb", "health": 8, "ai": "hostile", "attack_damage": 99})
	var client := EntityRegistry.new()
	_check(client.load_network(entities.to_network()) and client.id_of("test:blob") == 1, "entity types replicate")
	_check(not client.defs[1].has("attack_damage") or client.defs[1].attack_damage != 99, "server-only entity fields stay on the server")
	var sounds := SoundRegistry.new()
	sounds.register({"name": "test:boom", "files": ["test:sounds/boom.ogg"], "volume": 5.0})
	var client_sounds := SoundRegistry.new()
	_check(client_sounds.load_network(sounds.to_network()) and client_sounds.defs[client_sounds.id_of("test:boom")].volume == 2.0,
		"sounds replicate with clamped volume")
	_check(EntityPhysics.segment_hits_box(Vector3(0, 0.5, -5), Vector3(0, 0, 1), 10.0, Vector3(-0.5, 0, -0.5), Vector3(0.5, 1, 0.5)) == 4.5,
		"segment/box intersection distance")


func _server_rules() -> void:
	var world := "gameplay_%d" % Time.get_ticks_msec()
	var server = _start(world)
	var pig_type: int = server.entities.registry.id_of("vanilla:pig")
	var zombie_type: int = server.entities.registry.id_of("vanilla:zombie")
	_check(pig_type > 0 and zombie_type > 0, "vanilla registered pig and zombie")
	var y: int = server.surface_height(8, 8)
	var pos := Vector3(8.5, y + 1, 8.5)

	# Physics: a dropped item falls and comes to rest on the ground; stacks nearby merge.
	var coal: int = server.items.id_of("base:coal")
	var a = server.entities.drop_item(coal, 3, pos + Vector3(0, 3, 0), Vector3.ZERO)
	var b = server.entities.drop_item(coal, 4, pos + Vector3(0.3, 3, 0), Vector3.ZERO)
	for i in 120:
		server.entities.tick(1.0 / 60.0)
	_check(a.body.on_ground and absf(a.body.position.y - (y + 1)) < 0.01, "item fell and rests on the ground (y %.2f)" % a.body.position.y)
	server.entities._merge_items()
	_check((a.removed != b.removed) and (a.item_count + b.item_count == 7 or (a if not a.removed else b).item_count == 7), "nearby stacks merged into 7")

	# Damage and death events; drops become item entities.
	var events := []
	server.add_handler("entity_damage", func(ev): events.append("damage %s" % ev.cause), 0)
	server.add_handler("entity_death", func(ev):
		events.append("death")
		ev.drops = [[coal, 2]], 0)
	var zombie = server.entities.spawn(zombie_type, pos + Vector3(3, 0, 0))
	_check(zombie.damage(5.0, null, "magic") and zombie.health == 15.0, "damage applied (%.1f)" % zombie.health)
	_check(not zombie.damage(5.0, null, "magic"), "hurt cooldown blocks immediate repeat damage")
	zombie.hurt_timer = 0.0
	zombie.damage(100.0, null, "magic")
	_check(zombie.removed and events == ["damage magic", "damage magic", "death"], "death event fired (%s)" % str(events))
	var dropped: Array = server.entities.in_radius(pos + Vector3(3, 0, 0), 2.0, EntityRegistry.ITEM)
	_check(dropped.size() == 1 and dropped[0].item_count == 2, "entity_death handler replaced the drops")

	# Persistence: pigs are persistent, zombies are not.
	var pig = server.entities.spawn(pig_type, pos + Vector3(-2, 0, 0))
	pig.hurt_timer = 0.0
	pig.damage(3.0)
	pig.data["test"] = {"name": "Wilbur"}
	server.entities.spawn(zombie_type, pos + Vector3(-2, 0, 2))
	server._save_all(true)
	server.queue_free()
	await get_tree().process_frame
	var again = _start(world)
	var pigs: Array = again.entities.in_radius(pos, 16.0, pig_type)
	_check(pigs.size() == 1 and pigs[0].health == 7.0 and pigs[0].data.get("test", {}).get("name") == "Wilbur",
		"persistent pig saved with health and data (%d pigs)" % pigs.size())
	_check(again.entities.in_radius(pos, 16.0, zombie_type).is_empty(), "zombies are not saved")

	# Players: damage, death and respawn without networking.
	var p := ServerPlayer.new(again, 99, "Tester")
	p.player_id = "t"
	again.players[99] = p
	p.state.position = pos
	var deaths := []
	again.add_handler("player_death", func(ev): deaths.append(ev.message), 0)
	_check(again.damage_player(p, 5.0, "attack", pigs[0]) and p.health == 15.0, "player damage applied")
	p.hurt_timer = 0.0
	again.damage_player(p, 50.0, "mob", pigs[0])
	_check(p.dead and deaths.size() == 1 and deaths[0].contains("Pig"), "player death names the attacker (%s)" % str(deaths))
	again.on_respawn(99)
	_check(not p.dead and p.health == 20.0, "respawned at full health")
	p.inventory.creative = true
	p.hurt_timer = 0.0
	_check(not again.damage_player(p, 5.0, "mob"), "creative players take no damage")
	again.players.erase(99)
	again.queue_free()
	await get_tree().process_frame


func _start(world: String):
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["vanilla"]), "world": world, "data_dir": DATA_DIR, "seed": 42, "offline": true})
	if err != OK:
		_check(false, "server start: %s" % error_string(err))
	server.set_physics_process(false)  # the test drives ticks itself
	return server


func _check(ok: bool, what: String) -> void:
	print("[gameplay] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
