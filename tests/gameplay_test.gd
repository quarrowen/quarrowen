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
	_mining_rules()
	await _server_rules()
	await _equipment()
	await _progression()
	await _cosmetics()
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


func _mining_rules() -> void:
	const Mining = preload("res://engine/shared/mining.gd")
	var stone := {"hardness": 1.5, "tier": 1, "tool": "pickaxe"}
	var dirt := {"hardness": 0.5, "tool": "shovel"}
	var wood_pick := {"type": "pickaxe", "tier": 1, "speed": 2.0}
	_check(is_equal_approx(Mining.break_time(dirt, {}), 0.75), "dirt by hand takes 0.75 s")
	_check(is_equal_approx(Mining.break_time(stone, wood_pick), 1.125), "stone with a wooden pickaxe takes 1.125 s")
	_check(Mining.break_time(stone, {}) > 7.0 and not Mining.can_harvest(stone, {}), "stone by hand is slow and drops nothing")
	_check(Mining.can_harvest({"tier": 2, "tool": "pickaxe"}, {"type": "pickaxe", "tier": 3}) and not Mining.can_harvest({"tier": 3, "tool": "pickaxe"}, wood_pick),
		"tool tier gates harvesting")
	_check(is_equal_approx(Mining.break_time(dirt, {}, 2.0), 0.375), "mining_speed stat speeds breaking up")
	var inv := Inventory.new(PackedStringArray(["head", "chest"]))
	inv.add(70000, 1, 1, {"damage": 3})
	inv.add(70000, 1, 1)
	_check(inv.ids[0] == 70000 and inv.ids[1] == 70000 and inv.data[0].damage == 3 and inv.data[1].is_empty(), "items with different data do not stack")
	inv.add(5, 10)
	inv.add(5, 5, 64, {"name": "Lucky"})
	_check(inv.counts[2] == 10 and inv.data[3].get("name") == "Lucky", "renamed stacks stay separate")
	inv.remove(5, 10)
	_check(inv.ids[3] == 5 and inv.ids[2] == 0, "recipes consume plain stacks before ones with data")


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


func _equipment() -> void:
	var server = _start("equip_%d" % Time.get_ticks_msec())
	var items = server.items
	var p := ServerPlayer.new(server, 77, "Knight")
	p.player_id = "knight"
	server.players[77] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	var chest := p.equipment_slot("chest")
	var chestplate: int = items.id_of("base:iron_chestplate")
	var helmet: int = items.id_of("base:iron_helmet")
	var sword: int = items.id_of("base:iron_sword")
	_check(chest == Inventory.SIZE + 1 and p.inventory.total() == Inventory.SIZE + 5, "equipment slots follow the backpack")

	p.give(helmet)
	var helmet_slot := p.inventory.ids.find(helmet)
	p.inventory.click(helmet_slot, 1, false, items.max_stack)
	server.on_inventory_click(77, chest, 1, false)
	_check(p.inventory.ids[chest] == 0 and p.inventory.cursor_id == helmet, "a helmet does not fit the chest slot")
	server.on_inventory_closed(77)
	p.give(chestplate)
	server.on_inventory_click(77, p.inventory.ids.find(chestplate), 1, true)
	_check(p.inventory.ids[chest] == chestplate, "shift-click wears armor")
	_check(p.get_stat("armor") == 6.0, "chestplate gives 6 armor (%s)" % p.get_stat("armor"))

	p.hurt_timer = 0.0
	server.damage_player(p, 10.0, "attack", null)
	_check(p.health > 10.0 and p.health < 20.0, "armor reduced a 10 damage hit (health %.2f)" % p.health)
	_check(p.inventory.data[chest].get("damage", 0) == 1, "the hit wore the armor")
	p.hurt_timer = 0.0
	var before: float = p.health
	server.damage_player(p, 3.0, "fall", null)
	_check(is_equal_approx(before - p.health, 3.0), "armor does not stop fall damage")

	p.inventory.clear_slot(0)
	p.inventory.set_slot(0, sword, 1)
	p.inventory.selected = 0
	p.refresh_stats()
	_check(p.get_stat("attack_damage") == 6.0 and p.get_stat("attack_cooldown") == 0.6, "holding an iron sword sets attack stats")
	p.set_item_data(0, {"modifiers": [{"stat": "attack_damage", "amount": 2}], "level": 3})
	_check(p.get_stat("attack_damage") == 8.0, "per-item modifiers in item data apply (%.1f)" % p.get_stat("attack_damage"))
	p.add_modifier("test:rage", "attack_damage", 0.5, "multiply", 1.0)
	_check(p.get_stat("attack_damage") == 12.0, "timed multiply modifier applies (%.1f)" % p.get_stat("attack_damage"))
	server._time += 1.5
	p.refresh_stats()
	_check(p.get_stat("attack_damage") == 8.0, "timed modifier expired")
	p.add_modifier("test:fast", "move_speed", 0.5, "multiply")
	_check(p.physics_rules != null and is_equal_approx(p.physics_rules.walk_speed, server.rules.walk_speed * 1.5), "move_speed changes this player's physics")
	p.remove_modifier("test:fast")
	var hook := func(ev): ev.stats.reach += 2.0
	server.add_handler("player_stats", hook, 0)
	p.refresh_stats()
	_check(p.get_stat("reach") > 6.0, "player_stats event can adjust stats")

	var broke := []
	server.add_handler("item_break", func(ev): broke.append(ev.item), 0)
	for i in 300:
		server.damage_item(p, 0, 1, "attack")
	_check(broke == [sword] and p.inventory.ids[0] == 0, "item breaks at its durability")

	var saved: Dictionary = p.save_inventory()
	var copy := ServerPlayer.new(server, 78, "Copy")
	copy.load_inventory(saved)
	_check(copy.inventory.ids[chest] == chestplate and copy.inventory.data[chest].get("damage", 0) == 1, "equipment and item data survive saving")

	# Timed mining: breaking needs a started mine that lasted long enough; tiers gate drops.
	var stone: int = server.registry.id_of("base:stone")
	var target := Vector3i(9, y + 1, 9)
	server.set_block_authoritative(target, stone)
	p.inventory.clear_slot(0)
	server.on_break_block(77, target)
	_check(server.world.get_block_v(target) == stone, "survival break without mining is rejected")
	server.on_mine_start(77, target)
	server._time += 3.0
	server.on_break_block(77, target)
	_check(server.world.get_block_v(target) == stone, "still too early by hand (stone takes 7.4 s)")
	server._time += 5.0
	server.on_break_block(77, target)
	var dropped: Array = server.entities.in_radius(Vector3(target) + Vector3(0.5, 0.5, 0.5), 2.0, EntityRegistry.ITEM)
	_check(server.world.get_block_v(target) == 0 and dropped.is_empty(), "stone broke by hand but dropped nothing")
	server.set_block_authoritative(target, stone)
	var pick: int = items.id_of("base:stone_pickaxe")
	p.inventory.set_slot(0, pick, 1)
	p.refresh_stats()
	server.on_mine_start(77, target)
	server._time += 0.6
	server.on_break_block(77, target)
	dropped = server.entities.in_radius(Vector3(target) + Vector3(0.5, 0.5, 0.5), 2.0, EntityRegistry.ITEM)
	_check(server.world.get_block_v(target) == 0 and dropped.size() == 1, "stone pickaxe mined stone in 0.56 s with a drop")
	_check(p.inventory.data[0].get("damage", 0) == 1, "mining wore the pickaxe")
	server.players.erase(77)
	server.queue_free()
	await get_tree().process_frame


func _progression() -> void:
	var mods := ["vanilla", "arcana", "guild"] if ClassDB.class_exists(&"NativeJsRuntime") else ["vanilla", "arcana"]
	var server = _start("progression_%d" % Time.get_ticks_msec(), mods)
	var p := ServerPlayer.new(server, 90, "Hero")
	p.player_id = "hero"
	server.players[90] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 1000.0
	# Soul Blade (GDScript mod): kills level it up through item data.
	var blade: int = server.items.id_of("arcana:soul_blade")
	p.inventory.set_slot(0, blade, 1)
	p.inventory.selected = 0
	var zombie: int = server.entities.registry.id_of("vanilla:zombie")
	for i in 3:
		var mob = server.entities.spawn(zombie, p.position + Vector3(2, 0, 0))
		mob.health = 1.0
		server.entities.damage(mob, 5.0, "attack", p)
	var data: Dictionary = p.inventory.data[0]
	_check(data.get("souls") == 3 and data.get("level") == 1 and data.get("name") == "Soul Blade +1", "Soul Blade levelled from kills (%s)" % str(data))
	p.refresh_stats()
	_check(p.get_stat("attack_damage") == 6.5, "its level adds damage through item modifiers (%.1f)" % p.get_stat("attack_damage"))
	# Prospector's Pick (JavaScript mod): harvested blocks level it and speed up mining.
	if "guild" in mods:
		var pick: int = server.items.id_of("guild:prospector_pick")
		p.inventory.set_slot(1, pick, 1)
		p.inventory.selected = 1
		p.refresh_stats()
		var dirt: int = server.registry.id_of("base:dirt")
		for i in 5:
			var target := Vector3i(10 + i, y + 1, 10)
			server.set_block_authoritative(target, dirt)
			server.on_mine_start(90, target)
			server._time += 1.0
			server.on_break_block(90, target)
		var pick_data: Dictionary = p.inventory.data[1]
		_check(int(pick_data.get("xp", 0)) == 5 and int(pick_data.get("level", 0)) == 1, "JavaScript pick levelled from mining (%s)" % str(pick_data))
		_check(is_equal_approx(p.get_stat("mining_speed"), 1.2), "its level speeds up mining (%.2f)" % p.get_stat("mining_speed"))
	server.players.erase(90)
	server.queue_free()
	await get_tree().process_frame


func _cosmetics() -> void:
	const Cosmetics = preload("res://engine/shared/cosmetics.gd")
	const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
	var registry := Cosmetics.new()
	_check(registry.in_category("hat").size() >= 5 and registry.in_category("face").size() >= 5, "built-in catalog has hats and faces")
	var messy := {"skin": "#abc", "body": {"arms": "red", "legs": "#102030"}, "show_armor": {"head": true, "tail": true},
		"wear": {"hat": {"id": "builtin:crown", "color": "#nothex"}, "shirt": {"id": "builtin:crown"}, "wings": {"id": "builtin:wings"},
			"face": {"id": "nobody:face"}}}
	var clean := registry.sanitize_avatar(messy)
	_check(clean.skin == "#aabbcc" and clean.body == {"legs": "#102030"} and clean.show_armor == {"head": true},
		"sanitize keeps valid colors and armor choices (%s)" % clean)
	_check(clean.wear.keys() == ["hat"] and clean.wear.hat.color == "#e8c040", "sanitize drops unknown and misfiled cosmetics, bad colors fall back")
	var merged := Cosmetics.merge(clean, {"wear": {"hat": {"id": ""}, "back": {"id": "builtin:cape", "color": "#ffffff"}}})
	_check(not merged.wear.has("hat") and merged.wear.back.id == "builtin:cape", "merge removes with empty ids and adds")

	# Client side: data-drawn looks.
	var looks := LookBuilder.new(registry)
	var look := {"skin": "#8c5a3a", "wear": {"shirt": {"id": "builtin:tshirt", "color": "#ff0000"}, "hat": {"id": "builtin:top_hat"},
		"face": {"id": "builtin:smile", "color": "#0000ff"}}}
	var skin := looks.skin_image(look)
	var torso: Color = skin.get_pixel(21, 24)
	var arm_low: Color = skin.get_pixel(45, 30)  # right arm front, below the sleeve
	var eye: Color = skin.get_pixel(8 + 2, 8 + 3)
	_check(torso.r > 0.9 and torso.g < 0.1, "t-shirt paints the torso (%s)" % torso)
	_check(absf(arm_low.r - 0.55) < 0.06, "arms below the sleeves keep the skin color (%s)" % arm_low)
	_check(eye.b > 0.9 and eye.r < 0.1, "face pixels use the eye tint (%s)" % eye)
	var parts := looks.accessories(look, 0.05)
	_check(parts.size() == 1 and parts[0].attach == "hat" and parts[0].node.get_child_count() == 1, "hats become accessory meshes")
	for entry in parts:
		entry.node.free()

	# Server side: armor visibility, ownership, policy, overrides.
	var server = _start("cosmetics_%d" % Time.get_ticks_msec(), ["vanilla", "arcana"])
	var p := ServerPlayer.new(server, 78, "Stylist")
	p.player_id = "stylist"
	server.players[78] = p
	var helmet: int = server.items.id_of("base:iron_helmet")
	p.inventory.set_slot(p.equipment_slot("head"), helmet, 1)
	server._set_client_avatar(p, {"wear": {"hat": {"id": "builtin:cap"}, "hair": {"id": "builtin:short_hair"}}}, true)
	server.refresh_appearance(p)
	_check(p.appearance.avatar.wear.hat.id == "builtin:cap" and not p.appearance.armor.has("head"), "a hat shows instead of the helmet by default")
	server._set_client_avatar(p, {"wear": {"hat": {"id": "builtin:cap"}}, "show_armor": {"head": true}}, false)
	_check(p.appearance.armor.get("head") == helmet, "show_armor puts the helmet back")
	server.set_cosmetics_policy({"armor": "cosmetics"})
	_check(not p.appearance.armor.has("head"), "policy can force cosmetics over armor")
	server.set_cosmetics_policy({"armor": "player"})

	var hat := "arcana:archmage_hat"
	server._set_client_avatar(p, {"wear": {"hat": {"id": hat}}}, false)
	_check(not p.avatar.get("wear", {}).has("hat"), "locked server cosmetics cannot be worn")
	p.grant_cosmetic(hat)
	server._set_client_avatar(p, {"wear": {"hat": {"id": hat}, "shirt": {"id": "builtin:tank_top"}}}, false)
	_check(p.avatar.wear.hat.id == hat and p.server_wear.has("hat") and not p.portable_avatar.wear.has("hat"),
		"granted cosmetics can be worn and are remembered by the server, not the portable look")
	server._set_client_avatar(p, {"wear": {"shirt": {"id": "builtin:tshirt"}}}, true)
	_check(p.avatar.wear.hat.id == hat and p.avatar.wear.shirt.id == "builtin:tshirt", "rejoining keeps server picks over the portable look")
	server._store_player(p)
	_check(server._meta.players.stylist.cosmetics == [hat] and server._meta.players.stylist.server_wear.has("hat"), "owned cosmetics are saved")
	p.revoke_cosmetic(hat)
	_check(not p.avatar.wear.has("hat"), "revoking takes the cosmetic off")

	server.set_cosmetics_policy({"uniform": {"wear": {"shirt": {"id": "builtin:long_sleeve", "color": "#3d9c9c"}}}, "blocked": ["builtin:tshirt"]})
	_check(p.avatar.wear.shirt.id == "builtin:long_sleeve" and p.avatar.wear.shirt.color == "#3d9c9c", "a uniform dresses everyone")
	server.set_cosmetics_policy({"uniform": {}})
	_check(not p.avatar.get("wear", {}).has("shirt"), "blocked cosmetics are removed")
	server.set_cosmetics_policy({"blocked": []})
	p.set_avatar_override({"wear": {"glasses": {"id": "builtin:shades"}}})
	_check(p.avatar.wear.glasses.id == "builtin:shades", "mods can override a player's look")
	server.add_handler("avatar_change", func(ev): ev.avatar.skin = "#00ff00", 0)
	p.set_avatar_override({})
	_check(p.avatar.skin == "#00ff00" and not p.avatar.get("wear", {}).has("glasses"), "avatar_change handlers can change the look")
	server.queue_free()
	await get_tree().process_frame


func _start(world: String, mods := ["vanilla"]):
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(mods), "world": world, "data_dir": DATA_DIR, "seed": 42, "offline": true})
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
