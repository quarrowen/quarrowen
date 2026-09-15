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
const Chunk = preload("res://engine/shared/chunk.gd")
const StationSessions = preload("res://engine/server/station_sessions.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")

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
	await _effects()
	await _farming()
	await _containers()
	await _stations()
	await _coop()
	await _discovery()
	await _experiments()
	await _assembly()
	_minigames()
	await _skill_crafting()
	await _hunger()
	await _beds()
	await _guide()
	await _tutorials()
	await _guide_content()
	await _spawning()
	await _animals()
	await _taming()
	await _explosions()
	await _biomes()
	await _structures()
	await _js_blocks()
	await _dev_log()
	await _dev_tools()
	await _dev_web()
	await _mod_reload()
	_semver()
	await _mod_packages()
	await _mod_templates()
	_api_docs()
	_creations()
	await _skin_painter()
	await _accessory_tools()
	await _ugc_server()
	await _ugc_moderation()
	_menu_data()
	_client_settings()
	await _status_query()
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


func _effects() -> void:
	const EffectRegistry = preload("res://engine/shared/effect_registry.gd")
	const EffectPlayer = preload("res://engine/client/effects/effect_player.gd")
	var registry := EffectRegistry.new()
	_check(registry.id_of("engine:explosion") >= 0 and registry.id_of("engine:hit") >= 0, "built-in effects exist")
	var id := registry.register({"name": "test:wild", "duration": 99999, "emitters": [
		{"amount": 100000, "lifetime": -3, "speed": "fast", "colors": ["#ff000080", "nope"], "shape": "cube", "texture": 5}, "junk"],
		"light": {"energy": 500}, "shake": {"strength": 9}})
	var d: Dictionary = registry.defs[id]
	_check(d.emitters.size() == 1 and d.emitters[0].amount == 256 and d.emitters[0].lifetime == 0.05 and d.emitters[0].speed == [1.0, 2.0],
		"emitter values are clamped and defaulted")
	_check(d.emitters[0].colors == ["#ff000080"] and d.emitters[0].shape == "point" and d.duration == 600.0 and d.light.energy == 16.0 and d.shake.strength == 3.0,
		"colors, shapes, duration, light and shake are cleaned")
	_check(EffectRegistry.clean_options({"color": "#00ff00", "scale": 99, "direction": [0, 0, -1], "evil": true}) == {"color": "#00ff00ff", "scale": 20.0, "direction": Vector3(0, 0, -1)},
		"play options are cleaned")

	# Client: effects become particles, a light and shake, and clean themselves up.
	var player := EffectPlayer.new()
	add_child(player)
	var root := player.play(registry.id_of("engine:explosion"), Vector3(0, 60, 0), {"scale": 2.0}, null, Vector3(0, 60, 3))
	var particles := root.get_children().filter(func(n): return n is CPUParticles3D)
	_check(particles.size() == 2 and root.get_children().any(func(n): return n is OmniLight3D), "explosion builds two emitters and a light flash")
	_check(is_equal_approx((particles[0] as CPUParticles3D).initial_velocity_max, 18.0), "scale multiplies particle speed")
	await get_tree().process_frame
	_check(player.shake_offset.length() > 0.0, "a nearby explosion shakes the camera")
	var held := player.play_def(registry.defs[id], Vector3.ZERO, {"duration": -1}, player)
	await get_tree().create_timer(1.8).timeout
	_check(not is_instance_valid(root) and is_instance_valid(held), "one-shot effects free themselves; held effects stay until removed")
	player.queue_free()

	# Server: item looks come from definitions and item data, and reach the appearance.
	var server = _start("effects_%d" % Time.get_ticks_msec(), ["vanilla", "arcana"])
	var items = server.items
	var blade: int = items.id_of("arcana:soul_blade")
	_check(items.visuals(blade).trail.color == "#a060ff90" and items.visuals(blade).effects.hit == "arcana:soul_hit", "item defs carry trails and qualified effect names")
	var levelled: Dictionary = items.visuals(blade, {"glow": {"color": "#b070ff", "energy": 1.4}, "effects": {"held": "arcana:soul_aura"}})
	_check(levelled.glow.energy == 1.4 and levelled.effects.held == "arcana:soul_aura" and levelled.effects.hit == "arcana:soul_hit",
		"item data overrides glow and adds effects")
	var p := ServerPlayer.new(server, 79, "Glimmer")
	p.player_id = "glimmer"
	server.players[79] = p
	p.inventory.set_slot(0, blade, 1, {"glow": {"color": "#b070ff", "energy": 1.0}})
	p.inventory.set_slot(p.equipment_slot("head"), items.id_of("arcana:crystal_helmet"), 1)
	server.refresh_appearance(p)
	_check(p.appearance.get("held_look", {}).get("glow", {}).get("energy") == 1.0 and p.appearance.held_look.trail.width == 0.5,
		"the appearance carries the held stack's glow and trail")
	_check(p.appearance.get("armor_glow", {}).get("color") == "#60e0ffff", "glowing armor reaches the appearance")
	var stomp: Array = server.entities.ai.config_for(server.entities.registry.id_of("vanilla:colossus")).attacks.filter(func(a): return a.name == "stomp")
	_check(stomp.size() == 1 and stomp[0].effect == "engine:dust", "mob attacks carry effects")
	server.queue_free()
	await get_tree().process_frame


func _farming() -> void:
	const BlockTicks = preload("res://engine/server/block_ticks.gd")
	var blocks := PackedByteArray()
	blocks.resize(Chunk.VOLUME * 2)
	blocks.encode_u16(Chunk.index(3, 40, 5) << 1, 300)
	blocks.encode_u16(Chunk.index(9, 70, 1) << 1, 44)
	blocks.encode_u16(Chunk.index(9, 71, 1) << 1, 300 + 256)
	var found := BlockTicks.scan(blocks, PackedInt32Array([44, 300]))
	_check(found.size() == 2 and found[Chunk.index(3, 40, 5)] == 300 and found[Chunk.index(9, 70, 1)] == 44, "tick index finds exactly the listed block ids (%s)" % found)

	var server = _start("farming_%d" % Time.get_ticks_msec(), ["vanilla", "arcana"])
	var ticks = server.block_ticks
	var reg = server.registry
	var farmland: int = reg.id_of("base:farmland")
	var wheat: Array = [reg.id_of("base:wheat_0"), reg.id_of("base:wheat_1"), reg.id_of("base:wheat_2"), reg.id_of("base:wheat_3")]
	server.set_world_time(0.5, 0.0)  # noon, frozen
	var y: int = server.surface_height(8, 8)
	var soil := Vector3i(8, y, 8)
	for dy in range(1, 4):
		server.set_block_authoritative(soil + Vector3i(0, dy, 0), 0)
	server.set_block_authoritative(soil, farmland, false, 1)
	server.set_block_authoritative(soil + Vector3i.UP, wheat[0])
	_check(reg.defs[wheat[0]].render == reg.Render.PLANT and not reg.defs[wheat[0]].solid, "wheat renders as a plant and is not solid")
	_check(ticks.light_at(soil + Vector3i.UP, 1.0) == 15, "open sky at noon is full light")
	ticks._call(soil + Vector3i.UP, 1, "random", {})
	_check(server.world.get_block_v(soil + Vector3i.UP) == wheat[1], "a random tick grows watered wheat one stage")
	ticks._call(soil + Vector3i.UP, 12, "random", {})
	_check(server.world.get_block_v(soil + Vector3i.UP) == wheat[3], "caught-up ticks grow it to ripe wheat")

	# Catch-up after an unload: a saved clock in the past hands the missed ticks over.
	server.set_block_authoritative(soil + Vector3i.UP, wheat[0])
	var coord := Vector2i(0, 0)
	var saved: Dictionary = ticks.save_chunk(coord)
	_check(saved != null and saved.has("at"), "chunks with growing plants save a tick clock")
	var positions: Dictionary = ticks._positions[coord].duplicate()
	ticks.unload_chunk(coord)
	ticks.clock += 3600.0
	ticks.load_chunk(coord, positions, {}, saved)
	ticks.update(BlockTicks.STEP)
	_check(server.world.get_block_v(soil + Vector3i.UP) == wheat[3], "wheat kept growing while its chunk was unloaded")

	# Support: removing the farmland pops the wheat off as items.
	var items_before: int = server.entities.entities.size()
	server.break_block(soil)
	_check(server.world.get_block_v(soil + Vector3i.UP) == 0 and server.entities.entities.size() >= items_before + 2,
		"breaking the farmland broke the wheat and dropped it")
	_check(not server.is_supported(soil + Vector3i.UP, wheat[0]), "wheat cannot stand without farmland")

	# Light: a stone roof blocks the sky; a light block lights its surroundings.
	var stone: int = reg.id_of("base:stone")
	var probe := Vector3i(20, server.surface_height(20, 20) + 1, 20)
	for dx in range(-7, 8):
		for dz in range(-7, 8):
			server.set_block_authoritative(probe + Vector3i(dx, 3, dz), stone)
	_check(ticks.sky_light(probe) <= 8, "a wide roof shades the sky light (%d)" % ticks.sky_light(probe))
	var glow_id := -1
	for d in reg.defs:
		if d.light >= 12:
			glow_id = d.id
			break
	if glow_id > 0:
		server.set_block_authoritative(probe + Vector3i(2, 0, 0), glow_id)
		_check(ticks.block_light(probe) == reg.defs[glow_id].light - 2, "block light falls off with distance (%d)" % ticks.block_light(probe))

	# Scheduled ticks fire once when due, and saplings grow into trees.
	var sapling: int = reg.id_of("base:sapling")
	var tree_spot := Vector3i(40, server.surface_height(40, 40), 40)
	server.set_block_authoritative(tree_spot, reg.id_of("base:grass"))
	for dy in range(1, 9):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				server.set_block_authoritative(tree_spot + Vector3i(dx, dy, dz), 0)
	server.set_block_authoritative(tree_spot + Vector3i.UP, sapling)
	ticks.schedule(tree_spot + Vector3i.UP, 1.0)
	ticks.update(0.6)
	_check(server.world.get_block_v(tree_spot + Vector3i.UP) == sapling, "a scheduled tick waits until it is due")
	ticks.update(0.6)
	_check(server.world.get_block_v(tree_spot + Vector3i.UP) == reg.id_of("base:log"), "the scheduled tick grew the sapling into a tree")
	server.queue_free()
	await get_tree().process_frame


func _containers() -> void:
	var server = _start("containers_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var items = server.items
	var p := ServerPlayer.new(server, 81, "Keeper")
	p.player_id = "keeper"
	server.players[81] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	var chest_pos := Vector3i(10, y + 1, 8)
	server.set_block_authoritative(chest_pos, reg.id_of("base:chest"))
	var cobble: int = items.id_of("base:cobblestone")
	var coal: int = items.id_of("base:coal")
	p.inventory.set_slot(0, cobble, 40)
	_check(server.containers.open(p, chest_pos) and p.open_container == chest_pos, "a chest opens for a nearby player")
	server.on_inventory_click(81, 0, 1, true)
	var chest = server.containers.get_container(chest_pos)
	_check(chest.get_item(0).item == cobble and chest.get_item(0).count == 40 and p.inventory.ids[0] == 0, "shift-click moves a stack into the chest")
	server.on_inventory_click(81, 1000, 2, false)
	_check(p.inventory.cursor_count == 20 and chest.get_item(0).count == 20, "right-clicking a chest slot picks up half")
	server.on_inventory_click(81, 1005, 1, false)
	_check(chest.get_item(5).count == 20 and p.inventory.cursor_count == 0, "clicking an empty chest slot puts the stack down")
	var stored: Dictionary = server.get_block_data(chest_pos)
	_check(stored.slots[5][0] == "base:cobblestone", "contents are stored by item name in block data")
	server.on_inventory_click(81, 1005, 1, true)
	_check(p.inventory.count_of(cobble) == 20, "shift-click takes a stack back into the backpack")
	var entities_before: int = server.entities.entities.size()
	server.break_block(chest_pos, false)
	_check(server.entities.entities.size() == entities_before + 1 and p.open_container == null, "breaking a chest spills its contents and closes the screen")

	# Furnace: fuel filter, take-only output, smelting over world time, lights while burning.
	var furnace_pos := Vector3i(10, y + 1, 10)
	var furnace: int = reg.id_of("base:furnace")
	var furnace_lit: int = reg.id_of("base:furnace_lit")
	var ore: int = items.id_of("base:iron_ore")
	var ingot: int = items.id_of("base:iron_ingot")
	server.set_block_authoritative(furnace_pos, furnace)
	server.containers.open(p, furnace_pos)
	p.inventory.set_slot(1, ore, 3)
	p.inventory.set_slot(2, coal, 1)
	server.on_inventory_click(81, 0, 1, false)  # pick up the cobblestone
	server.on_inventory_click(81, 1001, 1, false)
	var box = server.containers.get_container(furnace_pos)
	_check(box.get_item(1).item == 0 and p.inventory.cursor_id == cobble, "the fuel slot refuses cobblestone")
	server.on_inventory_click(81, 1002, 1, false)
	_check(box.get_item(2).item == 0, "players cannot put items into the output slot")
	server.on_inventory_closed(81)
	server.containers.open(p, furnace_pos)
	server.on_inventory_click(81, 2, 1, true)  # coal -> fuel slot
	server.on_inventory_click(81, 1, 1, true)  # ore -> input slot
	_check(box.get_item(0).count == 3 and box.get_item(1).item == 0 and server.world.get_block_v(furnace_pos) == furnace_lit,
		"loading ore and coal lights the furnace and burns the coal")
	server.block_ticks.clock += 25.0
	server.block_ticks.update(0.6)
	_check(box.get_item(2).item == ingot and box.get_item(2).count == 2 and box.get_item(0).count == 1, "25 seconds smelted two ingots (%s)" % box.get_item(2))
	_check(box.get_progress("burn") > 0.0 and box.get_progress("cook") > 0.0, "progress bars follow fuel and smelting")
	server.block_ticks.clock += 500.0
	server.block_ticks.update(0.6)
	_check(box.get_item(2).count == 3 and server.world.get_block_v(furnace_pos) == furnace, "it finished the ore, burned out and went dark")
	server.on_inventory_click(81, 1002, 1, false)
	_check(p.inventory.cursor_id == ingot and p.inventory.cursor_count == 3, "the output slot can be emptied")
	server.on_inventory_closed(81)

	# Stations: recipes that need a crafting table.
	var pick: int = items.id_of("base:wooden_pickaxe")
	var recipe: Dictionary = server.recipes.recipes.filter(func(r): return r.output == pick)[0]
	p.inventory.clear()
	p.inventory.set_slot(0, items.id_of("base:planks"), 8)
	p.inventory.set_slot(1, items.id_of("base:stick"), 4)
	_check(recipe.station == "crafting_table" and not server._can_craft(p, recipe), "a pickaxe needs a crafting table")
	var table_pos := Vector3i(8, y + 1, 10)
	server.set_block_authoritative(table_pos, reg.id_of("base:crafting_table"))
	p.hurt_timer = 0.0
	server.on_interact(81, table_pos)
	_check(p.crafting_station.get("name") == "crafting_table" and server._can_craft(p, recipe),
		"right-clicking the table opens station crafting")
	server.craft(p, server.recipes.recipes.find(recipe))
	_check(p.inventory.count_of(pick) == 1, "crafted a pickaxe at the table")
	# The table draws ingredients from a chest beside it; craft-all makes as many as it can.
	p.inventory.clear()
	var chest_near := table_pos + Vector3i(1, 0, 0)
	server.set_block_authoritative(chest_near, reg.id_of("base:chest"))
	var near_chest = server.containers.get_container(chest_near)
	near_chest.set_item(0, items.id_of("base:planks"), 9)
	near_chest.set_item(1, items.id_of("base:stick"), 10)
	_check(server.crafting_stock(p).get(items.id_of("base:planks")) == 9, "station stock counts the nearby chest")
	_check(server.craftable_times(p, recipe) == 3, "three pickaxes' worth of planks nearby")
	_check(server.craft(p, server.recipes.recipes.find(recipe), 64) == 3 and p.inventory.count_of(pick) == 3
		and near_chest.get_item(0).item == 0 and near_chest.get_item(1).count == 4, "craft-all took ingredients from the chest")
	_check(server.recipes.recipes.find(recipe) == server.recipes.index_of("base:wooden_pickaxe") and recipe.category == "tools",
		"recipes get ids and categories")
	server.queue_free()
	await get_tree().process_frame


func _stations() -> void:
	var server = _start("stations_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var items = server.items
	var p := ServerPlayer.new(server, 83, "Smith")
	p.player_id = "smith"
	server.players[83] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	for x in range(4, 20):
		for z in range(4, 20):
			for dy in range(1, 5):
				server.set_block_authoritative(Vector3i(x, y + dy, z), 0)
			server.set_block_authoritative(Vector3i(x, y, z), reg.id_of("base:stone"))
	var table := Vector3i(10, y + 1, 8)
	server.set_block_authoritative(table, reg.id_of("base:crafting_table"))
	var ingot: int = items.id_of("base:iron_ingot")
	p.inventory.set_slot(0, ingot, 20)
	p.inventory.set_slot(1, items.id_of("base:stick"), 8)
	var iron_pick: Dictionary = server.recipes.recipes[server.recipes.index_of("base:iron_pickaxe")]
	var chestplate: Dictionary = server.recipes.recipes[server.recipes.index_of("base:iron_chestplate")]
	server.on_interact(83, table)
	var info: Dictionary = p.crafting_station
	_check(info.tier == 1 and info.features.is_empty() and info.available.size() == 3 and info.next.title == "Sturdy Workbench",
		"a plain crafting table is tier 1 with three possible upgrades")
	_check(not server._can_craft(p, iron_pick), "iron tools need metalwork")
	server.set_block_authoritative(table + Vector3i(2, 0, 0), reg.id_of("base:anvil"))
	server.on_interact(83, table)
	info = p.crafting_station
	_check(info.features.has("metalwork") and is_equal_approx(info.quality, 0.1) and info.detected.size() == 1, "an anvil nearby adds metalwork and quality")
	_check(server._can_craft(p, iron_pick) and not server._can_craft(p, chestplate), "metalwork unlocks iron tools but armor needs tier 2")
	var far_chest := table + Vector3i(0, 0, 5)
	server.set_block_authoritative(far_chest, reg.id_of("base:chest"))
	server.containers.get_container(far_chest).set_item(0, items.id_of("base:planks"), 3)
	_check(not server.crafting_stock(p).has(items.id_of("base:planks")), "a chest 5 blocks away is out of reach")
	server.set_block_authoritative(table + Vector3i(-1, 0, 0), reg.id_of("base:tool_rack"))
	server.on_interact(83, table)
	_check(server.crafting_stock(p).get(items.id_of("base:planks")) == 3 and p.crafting_station.speed > 0.1, "a tool rack reaches further chests and speeds crafting")

	p.inventory.set_slot(2, items.id_of("base:reinforced_frame"), 1)
	server.on_station_action(83, "upgrade")
	_check(server.world.get_block_v(table) == reg.id_of("base:sturdy_workbench") and p.inventory.count_of(items.id_of("base:reinforced_frame")) == 0
		and p.crafting_station.tier == 2 and p.crafting_station.next.is_empty(), "a reinforced frame upgrades the table to a Sturdy Workbench")
	_check(server._can_craft(p, chestplate), "the Sturdy Workbench with an anvil makes iron armor")

	# Multiblock: the forge only works once its bricks are in place (any rotation).
	var anvil_recipe: Dictionary = server.recipes.recipes[server.recipes.index_of("base:anvil")]
	var brick: int = reg.id_of("base:brick")
	var core := Vector3i(15, y + 1, 12)
	server.set_block_authoritative(core, reg.id_of("base:forge"))
	p.state.position = Vector3(13.5, y + 1, 12.5)
	server.on_interact(83, core)
	_check(p.crafting_station.structure.missing == 6 and not server._can_craft(p, anvil_recipe), "an unfinished forge lists 6 missing bricks and cannot forge")
	var guide: Array = server.stations.structure_missing(core, server.stations.defs.forge.multiblock)
	_check(guide.size() == 6 and guide.all(func(e): return e[1] == brick), "the build guide says where each brick goes")
	for offset in [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(0, 1, -1), Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 2, 0)]:
		server.set_block_authoritative(core + offset, brick)  # the pattern rotated to run along z
	server.on_interact(83, core)
	_check(p.crafting_station.structure.formed and p.crafting_station.features.has("forging") and server._can_craft(p, anvil_recipe),
		"a rotated forge structure forms and forges anvils")
	server.queue_free()
	await get_tree().process_frame


func _coop() -> void:
	var server = _start("coop_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var items = server.items
	var y: int = server.surface_height(8, 8)
	for x in range(4, 16):
		for z in range(4, 16):
			for dy in range(1, 4):
				server.set_block_authoritative(Vector3i(x, y + dy, z), 0)
			server.set_block_authoritative(Vector3i(x, y, z), reg.id_of("base:stone"))
	var crew := []
	for i in 3:
		var p := ServerPlayer.new(server, 90 + i, ["Ada", "Bo", "Cy"][i])
		p.player_id = "crew%d" % i
		p.state.position = Vector3(8.5 + i, y + 1, 8.5)
		p.edit_tokens = 1000.0
		server.players[90 + i] = p
		crew.append(p)
	var ada: ServerPlayer = crew[0]
	var bo: ServerPlayer = crew[1]
	var cy: ServerPlayer = crew[2]
	ada.team = "red"
	var table := Vector3i(10, y + 1, 10)
	server.set_block_authoritative(table, reg.id_of("base:sturdy_workbench"))
	server.set_block_authoritative(table + Vector3i(2, 0, 0), reg.id_of("base:anvil"))
	server.sessions.claim(table, ada)
	for p in crew:
		server.on_interact(p.peer_id, table)
	_check(server.sessions.view(table).players.size() == 3, "three players share the station session")
	server.on_station_coop(bo.peer_id, "view", server.recipes.index_of("base:chest"))
	_check(server.sessions.view(table).players.any(func(e): return e.name == "Bo" and e.recipe == server.recipes.index_of("base:chest")),
		"the session shows which recipe each player is looking at")

	var planks: int = items.id_of("base:planks")
	bo.inventory.set_slot(0, planks, 8)
	server.on_station_coop(bo.peer_id, "deposit", 0)
	_check(server.sessions.coop(table).tray.size() == 1 and bo.inventory.count_of(planks) == 0, "Bo put planks in the shared tray")
	_check(not server.sessions.may_take(cy, server.sessions.coop(table), server.sessions.coop(table).tray[0]), "Cy (no team) cannot take Bo's planks")
	cy.team = "red"
	_check(server.sessions.may_take(cy, server.sessions.coop(table), server.sessions.coop(table).tray[0]), "the owner's team can use the tray")
	cy.team = ""
	server.craft(bo, server.recipes.index_of("base:chest"))
	_check(bo.inventory.count_of(items.id_of("base:chest")) == 1 and server.sessions.coop(table).tray.is_empty(), "Bo crafted a chest from his tray planks")

	# Timed crafts: helpers speed up the queue.
	var plate: int = server.recipes.index_of("base:iron_chestplate")
	ada.inventory.set_slot(0, items.id_of("base:iron_ingot"), 8)
	server.craft(ada, plate)
	_check(server.sessions.coop(table).jobs.size() == 1 and ada.inventory.count_of(items.id_of("base:iron_ingot")) == 0
		and ada.inventory.count_of(items.id_of("base:iron_chestplate")) == 0, "a timed recipe joins the queue and takes its ingredients")
	_check(is_equal_approx(StationSessions.speedup(3, 0.0), 2.0), "three players craft twice as fast")
	server.sessions.update(2.5)
	_check(server.sessions.coop(table).jobs.size() == 1, "not done after 2.5 s with helpers (5 of 6 s)")
	server.sessions.update(1.0)
	_check(server.sessions.coop(table).jobs.is_empty() and ada.inventory.count_of(items.id_of("base:iron_chestplate")) == 1,
		"the chestplate finished early thanks to helpers")

	# Projects: several players contribute; completion lists who helped.
	var index: int = server.add_recipe({planks: 10, items.id_of("base:cobblestone"): 4}, items.id_of("base:furnace"), 1, "crafting_table", {"project": true, "id": "test:furnace_project"})
	var completed := []
	server.add_handler("project_completed", func(ev): completed.append(ev), 0)
	_check(server.craft(ada, index) == 0, "projects cannot be crafted directly")
	server.on_station_coop(ada.peer_id, "start_project", index)
	ada.inventory.set_slot(0, planks, 6)
	server.on_station_coop(ada.peer_id, "contribute", 0)
	_check(server.sessions.view(table).project.fraction > 0.4 and completed.is_empty(), "Ada delivered 6 of 14")
	bo.inventory.set_slot(0, planks, 10)
	bo.inventory.set_slot(1, items.id_of("base:cobblestone"), 4)
	var drops_before: int = server.entities.entities.size()
	server.on_station_coop(bo.peer_id, "contribute", 0)
	_check(completed.size() == 1 and completed[0].contributors.crew0.items == 6 and completed[0].contributors.crew1.items == 8
		and bo.inventory.count_of(planks) == 6, "Bo finished it; the project credits both and only took what was needed")
	_check(server.entities.entities.size() == drops_before + 1 and server.sessions.coop(table).project.is_empty(), "the finished project dropped its result")
	server.queue_free()
	await get_tree().process_frame


func _discovery() -> void:
	var server = _start("discovery_%d" % Time.get_ticks_msec())
	server.gameplay.recipe_discovery = true
	var items = server.items
	var p := ServerPlayer.new(server, 95, "Scholar")
	p.player_id = "scholar"
	server.players[95] = p
	p.state.position = Vector3(8.5, server.surface_height(8, 8) + 1, 8.5)
	p.edit_tokens = 100.0
	var learned := []
	server.add_handler("recipe_learned", func(ev): learned.append([ev.recipe, ev.source]), 0)
	_check(p.knows_recipe("base:planks") and p.knows_recipe("base:crafting_table") and not p.knows_recipe("base:chest"),
		"basics are known from the start, the rest is not")
	var gravel_recipe: Dictionary = server.recipes.recipes[server.recipes.index_of("base:gravel")]
	p.inventory.set_slot(0, items.id_of("base:cobblestone"), 4)
	_check(server.craftable_times(p, gravel_recipe) == 0, "an undiscovered recipe cannot be crafted even with the ingredients")
	p.sync_inventory()
	_check(p.knows_recipe("base:gravel") and learned.has(["base:gravel", "pickup"]) and server.craftable_times(p, gravel_recipe) == 4,
		"holding cobblestone discovered what it makes")
	p.inventory.set_slot(1, items.id_of("base:brick"), 6)
	p.inventory.set_slot(2, items.id_of("base:furnace"), 1)
	p.sync_inventory()
	_check(not p.knows_recipe("base:forge"), "blueprint recipes are not discovered by picking up ingredients")
	p.inventory.set_slot(3, items.id_of("base:forge_plans"), 1)
	p.inventory.selected = 3
	server.on_use_item(95, false, Vector3i.ZERO, Vector3i.ZERO)
	_check(p.knows_recipe("base:forge") and p.knows_recipe("base:anvil") and p.inventory.count_of(items.id_of("base:forge_plans")) == 0,
		"reading forge plans taught the forge and the anvil and used them up")
	# A generic blueprint: any item with `teaches` in its item data.
	p.inventory.set_slot(3, items.id_of("base:workbench_plans"), 1, {"teaches": ["base:iron_chestplate"], "name": "Armorer's Notes"})
	server.on_use_item(95, false, Vector3i.ZERO, Vector3i.ZERO)
	_check(p.knows_recipe("base:iron_chestplate") and not p.knows_recipe("base:reinforced_frame"), "item data can carry which recipes a blueprint teaches")
	server._store_player(p)
	_check(server._meta.players.scholar.recipes.has("base:forge") and server._meta.players.scholar.seen_items.has("base:brick"), "discoveries are saved")
	p.inventory.creative = true
	_check(p.knows_recipe("base:reinforced_frame"), "creative players know every recipe")
	server.queue_free()
	await get_tree().process_frame


func _experiments() -> void:
	var server = _start("experiments_%d" % Time.get_ticks_msec())
	server.gameplay.recipe_discovery = true
	var items = server.items
	var reg = server.registry
	var p := ServerPlayer.new(server, 96, "Tinkerer")
	p.player_id = "tinkerer"
	server.players[96] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	var coal: int = items.id_of("base:coal")
	var stick: int = items.id_of("base:stick")
	var wheat: int = items.id_of("base:wheat")
	p.inventory.set_slot(0, coal, 2)
	p.inventory.set_slot(1, stick, 2)
	p.inventory.set_slot(2, wheat, 9)
	var lab = server.experiments
	var attempt := func(grid: Array) -> Dictionary:
		lab._last.clear()
		return lab.experiment(p, grid)
	var result: Dictionary = attempt.call([stick, 0, 0, coal, 0, 0, 0, 0, 0])
	_check(result.status == "close" and result.hint.contains("arranged"), "the right items in the wrong arrangement get a hint (%s)" % result.hint)
	result = attempt.call([0, coal, 0, 0, stick, 0, 0, 0, 0])
	_check(result.status == "discovered" and p.knows_recipe("base:torch") and server.recipes.recipes[result.recipe].output == reg.id_of("base:torch"),
		"coal above a stick (anywhere in the grid) discovers torches")
	result = attempt.call([0, 0, 0, 0, 0, coal, 0, 0, stick])
	_check(result.status == "known", "trying a known recipe says so and allows crafting it")
	result = attempt.call([wheat, wheat, wheat, wheat, wheat, wheat, wheat, wheat, 0])
	_check(result.status == "close" and result.hint.contains("amounts"), "eight wheat hints that the amounts are off (%s)" % result.hint)
	result = attempt.call([wheat, wheat, wheat, wheat, wheat, wheat, wheat, wheat, wheat])
	_check(result.status == "discovered" and p.knows_recipe("base:hay_bale"), "nine wheat discovers the hay bale")
	result = attempt.call([items.id_of("base:iron_ingot"), 0, 0, 0, 0, 0, 0, 0, 0])
	_check(result.status == "invalid", "you cannot experiment with items you do not hold")
	lab._last.clear()
	lab.experiment(p, [coal, 0, 0, stick, 0, 0, 0, 0, 0])
	_check(lab.experiment(p, [coal, 0, 0, stick, 0, 0, 0, 0, 0]).status == "invalid", "experiments have a short cooldown")
	# Blueprint recipes cannot be experimented into existence.
	var table := Vector3i(10, y + 1, 8)
	server.set_block_authoritative(table, reg.id_of("base:crafting_table"))
	server.on_interact(96, table)
	p.inventory.set_slot(3, items.id_of("base:brick"), 6)
	p.inventory.set_slot(4, items.id_of("base:furnace"), 1)
	var brick: int = items.id_of("base:brick")
	result = attempt.call([brick, brick, brick, brick, items.id_of("base:furnace"), brick, brick, 0, 0])
	_check(result.status == "blueprint" and not p.knows_recipe("base:forge"), "matching a blueprint recipe says plans are needed")
	server.queue_free()
	await get_tree().process_frame


func _assembly() -> void:
	var server = _start("assembly_%d" % Time.get_ticks_msec())
	var items = server.items
	var reg = server.registry
	var asm = server.assembly
	var p := ServerPlayer.new(server, 97, "Smith")
	p.player_id = "smith"
	server.players[97] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	_check(asm.materials.has("base:iron") and asm.materials.has("vanilla:bone") and asm.assemblies.has("base:forged_pickaxe"),
		"materials and assemblies are registered")
	var head_recipe: int = server.recipes.index_of("base:pickaxe_head/base:iron")
	_check(head_recipe >= 0 and server.recipes.index_of("base:tool_handle/vanilla:bone") >= 0, "part recipes exist for every material")
	# Parts need the Tool Forge.
	p.inventory.set_slot(0, items.id_of("base:iron_ingot"), 5)
	p.inventory.set_slot(1, items.id_of("vanilla:bone"), 2)
	server.open_crafting(p, {})
	_check(server.craft(p, head_recipe) == 0, "parts cannot be made without a Tool Forge")
	var forge := Vector3i(10, y + 1, 8)
	server.set_block_authoritative(forge, reg.id_of("base:tool_forge"))
	server.on_interact(97, forge)
	_check(p.crafting_station.get("name", "") == "tool_forge", "the Tool Forge opens as a station")
	_check(server.craft(p, head_recipe) == 1, "an iron pickaxe head is forged")
	server.craft(p, server.recipes.index_of("base:tool_handle/vanilla:bone"))
	server.craft(p, server.recipes.index_of("base:binding/base:iron"))
	var find := func(item_name: String) -> int:
		for i in 36:
			if p.inventory.ids[i] == items.id_of(item_name) and p.inventory.counts[i] > 0:
				return i
		return -1
	var head_slot: int = find.call("base:pickaxe_head")
	var handle_slot: int = find.call("base:tool_handle")
	var binding_slot: int = find.call("base:binding")
	_check(head_slot >= 0 and p.inventory.data[head_slot].get("material") == "base:iron" and p.inventory.data[head_slot].has("icon_layers"),
		"parts carry their material and icon")
	_check(not server.assemble(p, "base:forged_pickaxe", PackedInt32Array([handle_slot, head_slot, binding_slot])), "parts in the wrong slots are refused")
	_check(not server.assemble(p, "base:forged_sword", PackedInt32Array([head_slot, handle_slot, binding_slot])), "parts for another assembly are refused")
	_check(server.assemble(p, "base:forged_pickaxe", PackedInt32Array([head_slot, handle_slot, binding_slot])), "a pickaxe is assembled from parts")
	var tool_slot: int = find.call("base:forged_pickaxe")
	_check(tool_slot >= 0 and find.call("base:pickaxe_head") < 0 and find.call("base:tool_handle") < 0, "assembling consumes the parts")
	if tool_slot >= 0:
		var id: int = p.inventory.ids[tool_slot]
		var data: Dictionary = p.inventory.data[tool_slot]
		var tool: Dictionary = items.tool_of(id, data)
		_check(tool.type == "pickaxe" and tool.tier == 3 and is_equal_approx(tool.speed, 6.6), "the head decides tier and speed, traits add to it (%s)" % tool)
		_check(items.max_durability(id, data) == 350, "a bone handle makes it last longer (%d)" % items.max_durability(id, data))
		_check(is_equal_approx(items.weapon_of(id, data).damage, 4.0), "the head adds damage")
		_check(data.icon_layers.size() == 3 and data.lore.size() >= 3 and data.name == "Iron Pickaxe", "the tool has layered icon, lore and name")
		_check(items.tool_of(id).get("tier", 0) == 0 and items.max_durability(id) == 1, "plain stacks keep the item's defaults")
	server.queue_free()
	await get_tree().process_frame


const Minigame = preload("res://engine/shared/minigame.gd")


## The first time after `after` when the marker sits on strike i's zone center.
func _perfect_time(g: Dictionary, i: int, after: float) -> float:
	var t := after + 0.05
	while t < after + 20.0:
		if absf(Minigame.marker(g, t) - Minigame.zone_center(g, i)) < 0.004:
			return t
		t += 0.001
	return after


func _minigames() -> void:
	var forging := Minigame.clean_def("test:forging", {"type": "timing", "rounds": 5, "speed": 0.75, "zone": 0.2, "cool": 9.0, "team": true})
	var g := Minigame.new_game(forging, 1234, false, 0.0, false)
	var t := 0.0
	for i in 5:
		t = _perfect_time(g, i, t)
		g.strikes.append(t)
	_check(Minigame.rate_strike(g, 0, g.strikes[0]).grade == "perfect", "a strike on the zone center is perfect")
	_check(Minigame.quality_for(Minigame.score(g, t)).name == "Masterwork", "five perfect strikes forge a Masterwork")
	_check(Minigame.marker(g, 3.3) == Minigame.marker(Minigame.new_game(forging, 1234, false, 0.0, false), 3.3), "the marker is the same for the same seed")
	var slow := Minigame.new_game(forging, 1234, false, 0.0, false)
	_check(Minigame.quality_for(Minigame.score(slow, 20.0)).name == "Standard", "no strikes is still Standard (never worse)")
	var off := Minigame.new_game(forging, 1234, false, 0.0, false)
	for i in 5:
		var c := Minigame.zone_center(off, i)
		var miss_t := 0.05
		while absf(Minigame.marker(off, miss_t) - c) < 0.3:
			miss_t += 0.01
		off.strikes.append(miss_t)
	_check(Minigame.score(off, 20.0) == 0.0, "strikes far from the zone miss")
	var assisted := Minigame.new_game(forging, 1234, true, 0.1, false)
	_check(Minigame.zone_width(assisted, 0) > Minigame.zone_width(g, 0) and Minigame.speed(assisted) < Minigame.speed(g),
		"relaxed timing and station quality widen the zone and slow the marker")
	_check(Minigame.heat(g, 0.0) == 1.0 and Minigame.heat(g, 9.0) == 0.0 and Minigame.marker(g, 8.5) != Minigame.marker(g, 8.51), "solo work cools over time")
	# Team: bellows keep the heat in the band and pump before each strike.
	var team := Minigame.new_game(forging, 99, false, 0.0, true)
	_check(team.team, "a team game with a partner")
	t = 0.0
	for i in 5:
		t = _perfect_time(team, i, t + 0.6)
		team.holds.append([t - 0.3, true])
		team.holds.append([t - 0.1, false])
		team.strikes.append(t)
	_check(Minigame.rate_strike(team, 0, team.strikes[0]).synced and Minigame.score(team, t) > 1.0, "pumping just before strikes gives a sync bonus")
	var burnt := Minigame.new_game(forging, 99, false, 0.0, true)
	burnt.holds.append([0.0, true])
	_check(Minigame.rate_strike(burnt, 0, 3.0).grade == "burnt", "holding the bellows too long burns the strike")
	var cold := Minigame.new_game(forging, 99, false, 0.0, true)
	_check(Minigame.zone_width(cold, 0, 5.0) < Minigame.zone_width(cold, 0), "cold metal narrows the zone")
	# Hold: follow the band.
	var channel := Minigame.clean_def("test:channel", {"type": "hold", "duration": 7.0, "zone": 0.24})
	var good := Minigame.new_game(channel, 7, false, 0.0, false)
	var down := false
	var st := 0.0
	while st < 7.0:
		var want: bool = Minigame.gauge(good, st) < Minigame.band_center(good, st)
		if want != down:
			good.holds.append([st, want])
			down = want
		st += 0.05
	var idle := Minigame.new_game(channel, 7, false, 0.0, false)
	_check(Minigame.score(good, 7.0) > 0.85 and Minigame.score(idle, 7.0) < 0.5, "following the band scores well, idling does not (%.2f / %.2f)" % [Minigame.score(good, 7.0), Minigame.score(idle, 7.0)])
	# Sequence: press the prompts in time.
	var stitch := Minigame.clean_def("test:stitch", {"type": "sequence", "rounds": 6, "window": 1.4})
	var right := Minigame.new_game(stitch, 5, false, 0.0, false)
	var wrong := Minigame.new_game(stitch, 5, false, 0.0, false)
	var late := Minigame.new_game(stitch, 5, false, 0.0, false)
	for i in 6:
		right.keys.append([0.5 * (i + 1), Minigame.prompt(right, i)])
		wrong.keys.append([0.5 * (i + 1), "up" if Minigame.prompt(wrong, i) != "up" else "down"])
	late.keys.append([2.0, Minigame.prompt(late, 0)])  # the first prompt timed out; this answers the second
	_check(Minigame.score(right, 3.0) == 1.0 and Minigame.complete(right, 3.0), "the right keys in time complete the stitching")
	_check(Minigame.score(wrong, 3.0) == 0.0, "wrong keys score nothing")
	_check(Minigame.sequence_progress(late).index == 2, "a prompt left too long fails and moves on")


func _skill_crafting() -> void:
	var server = _start("skill_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var items = server.items
	var skill = server.skill
	var p := ServerPlayer.new(server, 98, "Smith")
	p.player_id = "smith"
	server.players[98] = p
	var helper := ServerPlayer.new(server, 99, "Helper")
	helper.player_id = "helper"
	server.players[99] = helper
	var y: int = server.surface_height(8, 8)
	for x in range(4, 16):
		for z in range(4, 16):
			for dy in range(1, 4):
				server.set_block_authoritative(Vector3i(x, y + dy, z), 0)
			server.set_block_authoritative(Vector3i(x, y, z), reg.id_of("base:stone"))
	p.state.position = Vector3(8.5, y + 1, 8.5)
	helper.state.position = Vector3(9.5, y + 1, 9.5)
	p.edit_tokens = 100.0
	var table := Vector3i(10, y + 1, 8)
	server.set_block_authoritative(table, reg.id_of("base:crafting_table"))
	server.set_block_authoritative(table + Vector3i(2, 0, 0), reg.id_of("base:anvil"))
	p.inventory.set_slot(0, items.id_of("base:iron_ingot"), 20)
	p.inventory.set_slot(1, items.id_of("base:stick"), 32)
	helper.edit_tokens = 100.0
	server.on_interact(98, table)
	var pick_index: int = server.recipes.index_of("base:iron_pickaxe")
	var pick: int = items.id_of("base:iron_pickaxe")
	_check(server.recipes.recipes[pick_index].skill == "base:forging" and skill.defs.has("base:forging"), "iron tools can be forged by hand")
	_check(skill.start(p, {"recipe": server.recipes.index_of("base:stone_pickaxe")}) == 0, "recipes without a minigame cannot be crafted by hand")
	skill.time_override = 100.0
	var id: int = skill.start(p, {"recipe": pick_index})
	_check(id > 0 and p.inventory.count_of(items.id_of("base:iron_ingot")) == 17, "starting takes the ingredients")
	_check(skill.start(p, {"recipe": pick_index}) == 0, "one minigame at a time")
	var g: Dictionary = skill.game_of(p)
	_check(is_equal_approx(g.bonus, 0.1), "the anvil's quality bonus applies")
	var t := 0.0
	for i in 5:
		t = _perfect_time(g, i, t)
		skill.time_override = g.started + t
		skill.input(p, "strike", t)
	_check(skill.game_of(p).is_empty(), "the game ends after the last strike")
	var slot: int = p.inventory.ids.find(pick)
	var data: Dictionary = p.inventory.data[slot] if slot >= 0 else {}
	_check(data.get("quality", 0) == 3 and str(data.get("name", "")) == "Masterwork Iron Pickaxe", "perfect strikes forge a Masterwork pickaxe (%s)" % data.get("name", ""))
	var base_durability: int = items.max_durability(pick)
	_check(items.max_durability(pick, data) == roundi(base_durability * 1.3) and items.tool_of(pick, data).speed > items.tool_of(pick).speed,
		"Masterwork lasts 30% longer and mines faster")
	_check(str(data.get("lore", [""])[0]).contains("Masterwork") and str(data.lore.back()) == "Crafted by Smith" and data.has("glow"), "Masterwork credits the maker and glows")
	p.inventory.clear_slot(slot)
	# Quitting right away still gives a Standard item.
	skill.time_override = 200.0
	skill.start(p, {"recipe": pick_index})
	skill.input(p, "quit", 0.0)
	slot = p.inventory.ids.find(pick)
	_check(slot >= 0 and p.inventory.data[slot].is_empty(), "leaving early gives a plain Standard item")
	p.inventory.clear_slot(slot)
	# Inputs are clamped to what latency allows.
	skill.time_override = 300.0
	skill.start(p, {"recipe": pick_index})
	g = skill.game_of(p)
	skill.time_override = g.started + 5.0
	skill.input(p, "strike", 0.2)
	_check(float(g.strikes[0]) >= 5.0 - skill.MAX_LAG, "a strike claimed long ago is clamped to the latency window")
	skill.input(p, "hold", 5.1, 1)
	_check(g.holds.is_empty(), "the hammer cannot work the bellows")
	skill.time_override = g.started + 60.0
	skill.update()
	_check(skill.game_of(p).is_empty() and p.inventory.count_of(pick) == 1, "an abandoned game finishes on its own")
	p.inventory.clear_slot(p.inventory.ids.find(pick))
	# Team: the partner joins from the same station as the bellows.
	skill.time_override = 400.0
	id = skill.start(p, {"recipe": pick_index}, false, true)
	_check(skill.invites_at(table).size() == 1 and server.sessions.view(table).invites.size() == 1, "a team game invites others at the station")
	_check(not skill.join(helper, id), "a partner must be at the station")
	server.on_interact(99, table)
	_check(skill.join(helper, id) and skill.invites_at(table).is_empty(), "the partner joins")
	g = skill.game_of(p)
	_check(skill.role_of(g, p) == "hammer" and skill.role_of(g, helper) == "bellows", "starter hammers, partner pumps")
	skill.time_override = g.started + 0.5
	skill.input(helper, "strike", 0.5)
	_check(g.strikes.is_empty(), "the bellows cannot strike")
	skill.input(helper, "quit", 0.5)
	_check(skill.game_of(helper).is_empty() and not skill.game_of(p).is_empty(), "the partner can leave; the game goes on")
	skill.input(p, "quit", 0.6)
	# Waiting too long starts alone.
	skill.time_override = 500.0
	skill.start(p, {"recipe": pick_index}, false, true)
	skill.time_override = 500.0 + skill.INVITE_SECONDS + 0.1
	skill.update()
	g = skill.game_of(p)
	_check(not g.is_empty() and not g.team and g.started > 0.0, "without a partner the game starts solo")
	skill.input(p, "quit", 0.0)
	# Assemblies: forged tools from parts can be forged by hand too.
	var quality: Dictionary = skill.apply_quality(items.id_of("base:iron_chestplate"), {}, Minigame.QUALITIES[2], ["A"])
	_check(quality.modifiers[0].stat == "armor" and quality.modifiers[0].amount > 0.0 and quality.name.begins_with("Superior"), "quality adds armor to armor")
	_check(server.assembly.assemblies["base:forged_pickaxe"].skill == "base:forging", "assemblies name their minigame")
	server.queue_free()
	await get_tree().process_frame


func _hunger() -> void:
	var server = _start("hunger_%d" % Time.get_ticks_msec())
	var items = server.items
	var h = server.hunger
	var p := ServerPlayer.new(server, 101, "Hungry")
	p.player_id = "hungry"
	server.players[101] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	server.refresh_stats(p)
	_check(p.hunger == 20.0 and p.saturation == 5.0, "players start full")
	# Exhaustion uses saturation first, then hunger.
	h.add_exhaustion(p, 4.0 * 5.0)
	_check(p.hunger == 20.0 and p.saturation == 0.0, "exhaustion uses up saturation first")
	h.add_exhaustion(p, 8.0)
	_check(p.hunger == 18.0, "then hunger (4 exhaustion per point)")
	# Sprinting and jumping cost exhaustion; walking does not.
	var before: float = p.exhaustion
	h.update(p, 1.0 / 60.0, Vector3(server.rules.walk_speed / 60.0, 0, 0), 1.0 / 60.0, true)
	_check(is_equal_approx(p.exhaustion, before), "walking is free")
	h.update(p, 1.0 / 60.0, Vector3(server.rules.sprint_speed / 60.0, 0, 0), 1.0 / 60.0, true)
	_check(p.exhaustion > before, "sprinting costs exhaustion")
	# Regeneration needs 18+ hunger and costs exhaustion.
	_check(h.regen_interval(p, 2.5) == 2.5, "regenerates at 18 hunger")
	h.set_hunger(p, 17.0)
	_check(h.regen_interval(p, 2.5) == 0.0, "no regeneration below 18 hunger")
	h.set_hunger(p, 20.0, 5.0)
	_check(h.regen_interval(p, 2.5) < 2.5, "faster regeneration when full and saturated")
	var sat: float = p.saturation
	h.healed(p, 1.0)
	_check(p.saturation < sat, "healing costs saturation")
	# Low hunger stops sprinting (in the player's physics rules).
	h.set_hunger(p, 6.0, 0.0)
	_check(p.get_stats().sprint == 0.0 and p.physics_rules != null and is_equal_approx(p.physics_rules.sprint_speed, server.rules.walk_speed),
		"at 6 hunger you cannot sprint")
	h.set_hunger(p, 7.0)
	_check(p.get_stats().sprint == 1.0 and p.physics_rules == null, "eating above 6 lets you sprint again")
	# Starvation hurts down to 1 health by default.
	h.set_hunger(p, 0.0)
	p.health = 3.0
	for i in 20:
		p.hurt_timer = 0.0
		h.update(p, 1.0, Vector3.ZERO, 0.0, true)
	_check(p.health == 1.0 and not p.dead, "starvation stops at 1 health")
	server.gameplay.starvation_min_health = 0.0
	for i in 8:
		h.update(p, 1.0, Vector3.ZERO, 0.0, true)
	_check(p.dead, "with starvation_min_health 0 players can starve to death")
	server.on_respawn(101)
	_check(p.hunger == 20.0 and not p.dead, "respawning restores hunger")
	# Eating: hold use for eat_time.
	var bread: int = items.id_of("base:bread")
	_check(items.get_def(bread).food.hunger == 5.0 and items.is_usable(bread), "bread is food")
	p.inventory.set_slot(0, bread, 3)
	p.inventory.selected = 0
	_check(not h.start_eating(p), "you cannot eat when full")
	h.set_hunger(p, 10.0, 0.0)
	server.on_use_item(101, false, Vector3i.ZERO, Vector3i.ZERO)
	_check(not p.eating.is_empty(), "using food starts eating")
	server._time += 0.5
	h.update(p, 0.5, Vector3.ZERO, 0.0, true)
	_check(p.hunger == 10.0 and p.inventory.counts[0] == 3, "not eaten before eat_time")
	server._time += 1.0
	h.update(p, 1.0, Vector3.ZERO, 0.0, true)
	_check(p.hunger == 15.0 and p.saturation == 6.0 and p.inventory.counts[0] == 2, "bread restores 5 hunger and 6 saturation")
	server.on_use_item(101, false, Vector3i.ZERO, Vector3i.ZERO)
	server.on_stop_using(101)
	server._time += 2.0
	h.update(p, 2.0, Vector3.ZERO, 0.0, true)
	_check(p.inventory.counts[0] == 2, "releasing use stops eating")
	server.on_use_item(101, false, Vector3i.ZERO, Vector3i.ZERO)
	p.inventory.selected = 1
	server._time += 2.0
	h.update(p, 2.0, Vector3.ZERO, 0.0, true)
	_check(p.inventory.counts[0] == 2 and p.eating.is_empty(), "switching items stops eating")
	p.inventory.selected = 0
	# Quality food fills more; rotten flesh can poison.
	p.inventory.set_slot(2, bread, 1, {"quality": 3})
	h.set_hunger(p, 0.0, 0.0)
	h.finish_eating(p, 2)
	_check(is_equal_approx(p.hunger, 6.5), "Masterwork bread restores 30% more")
	var flesh: int = items.id_of("vanilla:rotten_flesh")
	p.inventory.set_slot(3, flesh, 20)
	var poisoned := false
	for i in 10:
		h.set_hunger(p, 0.0, 0.0)
		h.finish_eating(p, 3)
		if p.get_stats().hunger_drain > 0.0:
			poisoned = true
			break
	_check(poisoned, "rotten flesh can give food poisoning")
	var hunger_before: float = p.hunger
	for i in 20:
		h.update(p, 1.0, Vector3.ZERO, 0.0, true)
	_check(p.hunger < hunger_before, "food poisoning drains hunger over time")
	# Leftovers: a food with a remainder gives it back.
	var stew: int = items.register({"name": "test:stew", "food": {"hunger": 6, "saturation": 7, "remainder": "base:stick"}})
	p.inventory.set_slot(4, stew, 1)
	h.set_hunger(p, 0.0, 0.0)
	h.finish_eating(p, 4)
	_check(p.inventory.count_of(items.id_of("base:stick")) == 1, "eating a stew leaves the bowl (remainder)")
	# Drinks are swigged and give the bottle back.
	var juice: int = items.id_of("base:apple_juice")
	_check(items.get_def(juice).food.style == "drink" and items.get_def(bread).food.style == "plate", "drinks and plated food have their serving styles")
	p.inventory.set_slot(5, juice, 1)
	var bottles: int = p.inventory.count_of(items.id_of("base:glass_bottle"))
	h.set_hunger(p, 0.0, 0.0)
	h.finish_eating(p, 5)
	_check(p.hunger == 4.0 and p.inventory.count_of(items.id_of("base:glass_bottle")) == bottles + 1, "apple juice restores hunger and returns the bottle")
	# Rule off and creative: no hunger.
	h.set_hunger(p, 10.0)
	p.inventory.creative = true
	h.add_exhaustion(p, 40.0)
	_check(p.hunger == 10.0, "creative players do not get hungry")
	p.inventory.creative = false
	server.gameplay.hunger = false
	h.add_exhaustion(p, 40.0)
	_check(p.hunger == 10.0 and h.regen_interval(p, 2.5) == 2.5, "the hunger rule turns hunger off")
	server.gameplay.hunger = true
	# Saved with the player.
	server._store_player(p)
	_check(server._meta.players["hungry"].hunger == 10.0, "hunger is saved with the player")
	server.queue_free()
	await get_tree().process_frame


func _beds() -> void:
	var server = _start("beds_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var p := ServerPlayer.new(server, 102, "Sleepy")
	p.player_id = "sleepy"
	server.players[102] = p
	var other := ServerPlayer.new(server, 103, "Owl")
	other.player_id = "owl"
	server.players[103] = other
	var y: int = server.surface_height(8, 8)
	for x in range(2, 16):
		for z in range(2, 16):
			for dy in range(1, 5):
				server.set_block_authoritative(Vector3i(x, y + dy, z), 0)
			server.set_block_authoritative(Vector3i(x, y, z), reg.id_of("base:stone"))
	p.state.position = Vector3(8.5, y + 1, 12.5)
	other.state.position = Vector3(4.5, y + 1, 4.5)
	p.edit_tokens = 100.0
	var bed: int = reg.id_of("base:bed")
	var head: int = reg.id_of("base:bed_head")
	p.inventory.set_slot(0, bed, 2)
	p.inventory.selected = 0
	# Facing the player (yaw 0 looks along -Z, so the bed's front points +Z back at them).
	var foot := Vector3i(8, y + 1, 10)
	server.on_place_block(102, foot, 0.0)
	var head_pos: Vector3i = foot + Vector3i(0, 0, -1)
	_check(server.world.get_block_v(foot) == bed and server.world.get_block_v(head_pos) == head, "a bed places its head behind the foot")
	_check(server.pair_position(foot) == head_pos and server.pair_position(head_pos) == foot, "the two halves know each other")
	server.on_place_block(102, Vector3i(8, y + 1, 6), PI)
	_check(server.world.get_block_v(Vector3i(8, y + 1, 6)) == 0 or server.world.get_block_v(Vector3i(8, y + 1, 7)) == head,
		"placing needs room for both halves")
	server.set_block_authoritative(Vector3i(8, y + 1, 6), 0)
	server.set_block_authoritative(Vector3i(8, y + 1, 7), 0)
	# Using a bed by day sets the spawn but does not sleep.
	server.set_world_time(0.5, 1200.0)
	server.on_interact(102, head_pos)
	_check(p.spawn_bed == foot and p.sleeping.is_empty(), "a bed by day sets your respawn point")
	# At night you lie down; the night passes once everyone is asleep.
	server.set_world_time(0.0, 1200.0)
	server.on_interact(102, foot)
	_check(not p.sleeping.is_empty() and p.state.position.distance_to(Vector3(8.5, y + 2, 10.0)) < 0.01, "at night you lie down in the bed")
	_check(p.appearance.get("sleeping", {}).get("head", []) == [0, -1], "others see you lying with your head on the pillow")
	server.on_interact(103, foot)
	_check(other.sleeping.is_empty(), "an occupied bed cannot be shared")
	server._time += 5.0
	server.sleep.update(0.1)
	_check(not p.sleeping.is_empty() and server.get_time_of_day() == 0.0, "the night is not skipped while others are awake")
	server.gameplay.sleep_percentage = 50
	server.sleep.update(0.1)
	_check(p.sleeping.is_empty() and is_equal_approx(server.get_time_of_day(), server.sleep.MORNING), "with half the players asleep the night is skipped")
	_check(PlayerPhysics.overlaps_block(p.state.position, foot) == false and p.state.position.y >= y + 1, "waking up stands you next to the bed")
	server.gameplay.sleep_percentage = 100
	# Getting up early: moving, damage.
	server.set_world_time(0.0, 1200.0)
	server.on_interact(102, foot)
	var input := PlayerPhysics.PlayerInput.new()
	input.seq = 1
	input.move = Vector2(0, 1)
	p.input_queue.append(input)
	server._simulate_player(p)
	_check(p.sleeping.is_empty(), "moving gets you out of bed")
	server.on_interact(102, foot)
	p.hurt_timer = 0.0
	p.inventory.creative = false
	server.damage_player(p, 1.0, "magic")
	_check(p.sleeping.is_empty(), "damage wakes you")
	# Monsters nearby keep you awake.
	var zombie = server.entities.spawn(server.entities.registry.id_of("vanilla:zombie"), Vector3(10.5, y + 1, 10.5))
	server.on_interact(102, foot)
	_check(p.sleeping.is_empty(), "you cannot sleep with monsters nearby")
	if zombie != null:
		server.entities.remove(zombie)
	# Respawning at the bed, and falling back when it is gone.
	p.dead = true
	server.on_respawn(102)
	var spot: Vector3 = p.state.position
	_check(Vector2(spot.x, spot.z).distance_to(Vector2(8.5, 9.5)) < 2.5 and absf(spot.y - (y + 1)) < 1.1, "you respawn next to your bed (%s)" % spot)
	server._store_player(p)
	_check(server._meta.players["sleepy"].spawn_bed == [foot.x, foot.y, foot.z], "the bed spawn is saved")
	p.inventory.creative = true  # instant breaking
	server.on_break_block(102, head_pos)
	_check(server.world.get_block_v(foot) == 0 and server.world.get_block_v(head_pos) == 0, "breaking one half removes the whole bed")
	p.dead = true
	server.on_respawn(102)
	_check(p.spawn_bed == null, "a missing bed clears the respawn point")
	server.queue_free()
	await get_tree().process_frame


func _guide() -> void:
	var server = _start("guide_%d" % Time.get_ticks_msec())
	var guide = server.guide
	var reg = guide.registry
	_check(not reg.get_chapter("base:basics").is_empty() and not reg.get_page("base:welcome").is_empty(), "mods register guide chapters and pages")
	_check(reg.chapter_pages("base:basics")[0].id == "base:welcome", "pages are sorted by order")
	_check(reg.get_page("base:crafting_table").unlock == {"item": "base:planks"}, "unlock references are qualified")
	var api = preload("res://engine/server/mod_api.gd").new(server, {"id": "tester", "dir": "res://tests"})
	api.register_guide_page("secret", {"chapter": "base:basics", "unlock": {"flag": "found_it"},
		"blocks": [{"type": "items", "items": ["planks", "base:stick"]}, {"type": "bogus"}, {"type": "link", "page": "welcome"}]})
	var secret: Dictionary = reg.get_page("tester:secret")
	_check(secret.blocks.size() == 2 and secret.blocks[0].items == ["tester:planks", "base:stick"] and secret.blocks[1].page == "tester:welcome",
		"page blocks are cleaned and their names qualified")
	var p := ServerPlayer.new(server, 110, "Reader")
	p.player_id = "reader"
	server.players[110] = p
	server.gameplay.recipe_discovery = true
	guide.sync(p)
	_check(guide.is_unlocked(p, "base:welcome") and guide.is_unlocked(p, "base:wood"), "pages without conditions start unlocked")
	_check(not guide.is_unlocked(p, "base:crafting_table") and not guide.is_unlocked(p, "base:food"), "locked pages wait for their condition")
	_check(not guide.is_unlocked(p, "base:forge"), "recipe pages stay locked while the recipe is unknown")
	var unlocked := []
	api.on("guide_page_unlocked", func(ev): unlocked.append(ev.page))
	p.inventory.set_slot(0, server.items.id_of("base:planks"), 4)
	p.sync_inventory()
	guide.update(2.0)
	_check(guide.is_unlocked(p, "base:crafting_table") and unlocked.has("base:crafting_table"), "holding an item unlocks its page")
	guide.on_read(p, "base:crafting_table")
	guide.on_read(p, "tester:secret")
	_check(guide.state_of(p).last == "base:crafting_table" and not guide.state_of(p).read.has("tester:secret"), "reading remembers the page; locked pages cannot be read")
	guide.on_read(p, "base:wood")
	_check(guide.is_unlocked(p, "base:food"), "reading a page unlocks pages that follow it")
	server.learn_recipe(p, "base:forge")
	guide.update(2.0)
	_check(guide.is_unlocked(p, "base:forge"), "learning a recipe unlocks its page")
	api.set_guide_flag(p, "found_it")
	_check(guide.is_unlocked(p, "tester:secret") and api.has_guide_flag(p, "found_it"), "mod flags unlock pages")
	var cow = server.entities.spawn(server.entities.registry.id_of("vanilla:cow"), p.state.position + Vector3(3, 0, 0))
	api.register_guide_page("cows", {"chapter": "base:basics", "unlock": {"entity": "vanilla:cow"}, "blocks": []})
	guide.update(2.0)
	_check(cow != null and guide.is_unlocked(p, "tester:cows"), "seeing a mob unlocks its page")
	_check(api.unlock_guide_page(p, "base:stone_tools", false) and guide.is_unlocked(p, "base:stone_tools"), "mods can unlock pages directly")
	server._store_player(p)
	var saved: Dictionary = server._meta.players.reader.guide
	var q := ServerPlayer.new(server, 111, "Reader2")
	guide.load_player(q, JSON.parse_string(JSON.stringify(saved)))
	_check(guide.is_unlocked(q, "tester:secret") and guide.state_of(q).last == "base:wood" and guide.has_flag(q, "tester:found_it"),
		"guide progress is saved")
	var net: Dictionary = JSON.parse_string(JSON.stringify(reg.to_network()))
	var copy = preload("res://engine/shared/guide_registry.gd").new()
	copy.load_network(net)
	_check(copy.pages.size() == reg.pages.size() and copy.get_page("base:wood").blocks.size() == reg.get_page("base:wood").blocks.size(),
		"the guide reaches clients intact")
	_check(preload("res://engine/shared/guide_registry.gd").page_text(reg.get_page("base:wood")).contains("sticks"), "page text is searchable")
	server.queue_free()
	await get_tree().process_frame


## Every name the bundled guide pages, tutorials and tips refer to exists.
func _guide_content() -> void:
	var server = _start("guide_content_%d" % Time.get_ticks_msec(), ["vanilla", "industry", "arcana", "guild"])
	var reg = server.guide.registry
	var bad := PackedStringArray()
	var item_ok := func(n: String) -> bool: return server.items.id_of(n) > 0
	for c in reg.chapters:
		if not c.icon.is_empty() and not item_ok.call(c.icon):
			bad.append("%s icon %s" % [c.id, c.icon])
	for page in reg.pages:
		if reg.get_chapter(page.chapter).is_empty():
			bad.append("%s chapter %s" % [page.id, page.chapter])
		if not page.icon.is_empty() and not item_ok.call(page.icon):
			bad.append("%s icon %s" % [page.id, page.icon])
		var u: Dictionary = page.unlock
		if u.has("item") and not item_ok.call(u.item) or u.has("recipe") and server.recipes.index_of(u.recipe) < 0 \
				or u.has("entity") and server.entities.registry.id_of(u.entity) < 0 or u.has("page") and reg.get_page(u.page).is_empty():
			bad.append("%s unlock %s" % [page.id, u])
		for b in page.blocks:
			for n in (b.get("items") if b.get("items") is Array else []):
				if not item_ok.call(n):
					bad.append("%s item %s" % [page.id, n])
			if b.has("output") and not item_ok.call(b.output):
				bad.append("%s recipe %s" % [page.id, b.output])
			if b.has("entity") and server.entities.registry.id_of(b.entity) < 0:
				bad.append("%s entity %s" % [page.id, b.entity])
			if b.type == "link" and reg.get_page(b.page).is_empty():
				bad.append("%s link %s" % [page.id, b.page])
			if b.type == "keys" and not b.action in ["guide", "inventory", "crafting", "break", "place", "drop", "sprint", "jump", "chat"]:
				bad.append("%s key %s" % [page.id, b.action])
	for t in server.tutorials.tutorials.values():
		for step in t.steps:
			if not step.page.is_empty() and reg.get_page(step.page).is_empty():
				bad.append("%s page %s" % [t.id, step.page])
			if not step.icon.is_empty() and not item_ok.call(step.icon):
				bad.append("%s icon %s" % [t.id, step.icon])
	for tip in server.tutorials.tips.values():
		if not tip.page.is_empty() and reg.get_page(tip.page).is_empty():
			bad.append("%s page %s" % [tip.id, tip.page])
		if not tip.icon.is_empty() and not item_ok.call(tip.icon):
			bad.append("%s icon %s" % [tip.id, tip.icon])
	_check(bad.is_empty(), "guide, tutorial and tip references exist %s" % ", ".join(bad))
	_check(reg.chapters.size() >= 10 and reg.pages.size() >= 45 and not reg.get_page("guild:quests").is_empty(), "the bundled games write the guide (%d chapters, %d pages)" % [reg.chapters.size(), reg.pages.size()])
	server.queue_free()
	await get_tree().process_frame


func _tutorials() -> void:
	var server = _start("tutorials_%d" % Time.get_ticks_msec())
	var tut = server.tutorials
	var reg = server.registry
	var items = server.items
	_check(tut.tutorials.has("vanilla:survival") and tut.tutorials["vanilla:survival"].steps[0].goal.target == ["base:*log"], "mods register tutorials")
	_check(tut.tutorials["vanilla:survival"].steps[0].hint == {"block": ["base:*log"]}, "break goals point at the block by default")
	var api = preload("res://engine/server/mod_api.gd").new(server, {"id": "tester", "dir": "res://tests"})
	_check(not api.register_tutorial("broken", {"steps": [{"title": "?", "goal": {"type": "juggle"}}]}), "unknown goals are refused")
	api.register_tutorial("drill", {"title": "Drill", "reward": [["base:apple", 2]], "steps": [
		{"title": "Hold planks", "goal": {"type": "have", "target": "base:planks", "count": 4}},
		{"title": "Break logs", "goal": {"type": "break", "target": ["base:*log"], "count": 2}, "reward": [["base:stick", 1]]},
		{"title": "Craft sticks", "goal": {"type": "craft", "target": "base:stick", "count": 4}},
		{"title": "Custom", "goal": {"type": "manual"}},
		{"title": "Signal", "goal": {"type": "event", "event": "tester_signal", "field": "kind", "target": "go"}},
	]})
	api.register_tip("dusk", {"text": "It is dark", "trigger": {"type": "night"}})
	api.register_tip("logs", {"text": "Logs!", "trigger": {"type": "break", "target": "base:*log"}})
	var p := ServerPlayer.new(server, 120, "Learner")
	p.player_id = "learner"
	server.players[120] = p
	var shown := []
	api.on("tip_shown", func(ev): if ev.player.name == "Tipped": shown.append(ev.tip))
	var finished := []
	api.on("tutorial_completed", func(ev): finished.append(ev.tutorial))
	tut.on_join(p)
	_check(tut.state_of(p).active == "vanilla:survival", "new survival players start the auto-start tutorial")
	_check(api.start_tutorial(p, "drill") and tut.state_of(p).active == "tester:drill", "a mod can start another tutorial")
	p.inventory.set_slot(0, items.id_of("base:planks"), 3)
	tut.update(1.0)
	_check(tut.state_of(p).step == 0 and tut.state_of(p).progress == 3, "have goals track how many you hold")
	p.inventory.set_slot(0, items.id_of("base:planks"), 4)
	tut.update(1.0)
	_check(tut.state_of(p).step == 1, "holding enough completes a have goal")
	var birch: int = reg.id_of("base:birch_log")
	server.emit("block_broken", {"player": p, "position": Vector3i.ZERO, "block": reg.id_of("base:stone")})
	server.emit("block_broken", {"player": p, "position": Vector3i.ZERO, "block": birch})
	var other := ServerPlayer.new(server, 121, "Bystander")
	server.players[121] = other
	server.emit("block_broken", {"player": other, "position": Vector3i.ZERO, "block": birch})
	_check(tut.state_of(p).step == 1 and tut.state_of(p).progress == 1, "only matching events by the player count (wildcards match)")
	var sticks: int = p.inventory.count_of(items.id_of("base:stick"))
	server.emit("block_break", {"player": p, "position": Vector3i.ZERO, "block": birch, "drops": [], "cancelled": true})
	server.emit("block_broken", {"player": p, "position": Vector3i.ZERO, "block": reg.id_of("base:log")})
	_check(tut.state_of(p).step == 2 and p.inventory.count_of(items.id_of("base:stick")) == sticks + 1, "finishing a step gives its reward")
	server.emit("item_crafted", {"player": p, "item": items.id_of("base:stick"), "count": 4, "recipe": "base:stick"})
	_check(tut.state_of(p).step == 3, "craft goals count the items made")
	tut.update(1.0)
	_check(tut.state_of(p).step == 3, "manual goals wait for the mod")
	api.advance_tutorial(p)
	server.emit("tester_signal", {"player": p, "kind": "stop"})
	_check(tut.state_of(p).step == 4, "generic event goals match their field")
	var apples: int = p.inventory.count_of(items.id_of("base:apple"))
	server.emit("tester_signal", {"player": p, "kind": "go"})
	_check(tut.state_of(p).active == "" and tut.state_of(p).done.has("tester:drill") and finished == ["tester:drill"], "the last step completes the tutorial")
	_check(p.inventory.count_of(items.id_of("base:apple")) == apples + 2, "completing a tutorial gives its reward")
	_check(tut.view(p).done.has("tester:drill") and not tut.view(p).has("step"), "the tracker hides when nothing runs")
	# Skip and stop.
	tut.start(p, "vanilla:survival")
	server.on_tutorial_action(120, "skip", "")
	_check(tut.state_of(p).step == 1, "players can skip a step")
	server.on_tutorial_action(120, "stop", "")
	_check(tut.state_of(p).active == "" and tut.state_of(p).stopped.has("vanilla:survival"), "players can stop a tutorial")
	tut.on_join(p)
	_check(tut.state_of(p).active == "", "a stopped tutorial does not start again by itself")
	# Tips: once each, spaced out, off when the player says so.
	var r := ServerPlayer.new(server, 123, "Tipped")
	server.players.erase(121)
	server.players[123] = r
	r.health = r.max_health
	r.state.position = Vector3(0, 100, 0)
	server.set_world_time(0.5, 1200.0)
	server._time = 1000.0
	shown.clear()
	server.emit("block_broken", {"player": r, "position": Vector3i.ZERO, "block": birch})
	tut.update(1.0)
	_check(shown == ["tester:logs"], "event tips show")
	server.set_world_time(0.0, 1200.0)
	tut.update(1.0)
	_check(not shown.has("tester:dusk"), "tips wait for the gap after the last one")
	server._time = 1100.0
	tut.update(1.0)
	_check(shown.has("tester:dusk") or shown.has("vanilla:first_night"), "polled tips show when their condition holds")
	server.emit("block_broken", {"player": r, "position": Vector3i.ZERO, "block": birch})
	for i in 4:
		server._time += 100.0
		tut.update(1.0)
	_check(shown.count("tester:logs") == 1 and shown.has("tester:dusk") and shown.has("vanilla:first_night"), "a tip shows only once")
	server.on_tutorial_action(120, "tips_off", "")
	_check(tut.state_of(p).tips_off, "players can turn tips off")
	# Saved with the player.
	tut.start(p, "tester:drill")
	server._store_player(p)
	var q := ServerPlayer.new(server, 122, "Learner2")
	tut.load_player(q, JSON.parse_string(JSON.stringify(server._meta.players.learner.tutorial)))
	_check(tut.state_of(q).active == "tester:drill" and tut.state_of(q).done.has("tester:drill") and tut.state_of(q).tips.has("tester:dusk")
		and tut.state_of(q).tips_off, "tutorial progress and tips are saved")
	_check(tut.to_network().size() == 2 and tut.to_network()[0].id == "vanilla:survival", "clients get the tutorial list in order")
	server.queue_free()
	await get_tree().process_frame


func _spawning() -> void:
	var server = _start("spawning_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var entities = server.entities
	var spawning = entities.spawning
	var p := ServerPlayer.new(server, 104, "Watcher")
	p.player_id = "watcher"
	server.players[104] = p
	var zombie: int = entities.registry.id_of("vanilla:zombie")
	var pig: int = entities.registry.id_of("vanilla:pig")
	_check(spawning.category_of_type(zombie) == "monster" and spawning.category_of_type(pig) == "animal", "mobs get spawn categories from their AI")
	var zombie_rule: Dictionary = spawning.rules.filter(func(r): return int(r.entity) == zombie)[0]
	_check(zombie_rule.light == [0, 7] and zombie_rule.category == "monster", "vanilla zombies spawn in darkness")
	# A sealed dark room and a lit one, far below the surface.
	var stone: int = reg.id_of("base:stone")
	var y := 20
	for x in range(0, 40):
		for z in range(0, 12):
			for dy in range(-30, 31):
				var edge: bool = dy <= -1 or dy >= 3 or x == 0 or x == 39 or z == 0 or z == 11 or x == 20  # solid around, so caves nearby don't count
				server.set_block_authoritative(Vector3i(x, y + dy, z), stone if edge else 0)
	var dark := Vector3(10.5, y, 5.5)
	var lit := Vector3(30.5, y, 3.5)
	server.set_block_authoritative(Vector3i(30, y, 2), reg.id_of("base:torch"))
	var night := 0.12
	var rule := zombie_rule.duplicate()
	rule.on = []
	var found_dark: Vector3 = spawning.find_spot(dark, rule, night, 1.0, 6.0)
	_check(found_dark != Vector3.INF and found_dark.y == y, "monsters find spots in a dark cave room (%s)" % found_dark)
	_check(server.block_ticks.block_light(Vector3i(30, y, 4)) >= 10, "the torch lights the room (%d)" % server.block_ticks.block_light(Vector3i(30, y, 4)))
	var lit_spots := 0
	for i in 20:
		if spawning.find_spot(lit, rule, night, 1.0, 2.5) != Vector3.INF:
			lit_spots += 1
	_check(lit_spots == 0, "no monster spawns next to a torch (%d)" % lit_spots)
	var pig_rule: Dictionary = spawning.rules.filter(func(r): return int(r.entity) == pig)[0].duplicate()
	pig_rule.on = []
	_check(spawning.find_spot(dark, pig_rule, 1.0, 1.0, 6.0) == Vector3.INF, "animals need light and open sky")
	# Caps per category.
	p.state.position = dark
	spawning.caps.monster = 2
	for i in 3:
		entities.spawn(zombie, dark + Vector3(i, 0, 0))
	_check(spawning.count_near(dark, "monster") == 3, "counts mobs by category near a player")
	server.set_world_time(0.0, 1200.0)
	for i in 10:
		spawning.run()
	_check(entities.in_radius(dark, 64.0, zombie).size() == 3, "no more monsters spawn past the cap")
	# Despawning: monsters far from everyone go, animals stay.
	var far_zombie = entities.spawn(zombie, dark + Vector3(200, 0, 0))
	var far_pig = entities.spawn(pig, dark + Vector3(200, 0, 3))
	spawning.despawn()
	_check(far_zombie.removed and not far_pig.removed, "far monsters despawn, animals stay")
	var named = entities.spawn(zombie, dark + Vector3(150, 0, 0), {"data": {"no_despawn": true}})
	spawning.despawn()
	_check(not named.removed, "mobs marked no_despawn stay")
	server.queue_free()
	await get_tree().process_frame


func _animals() -> void:
	var server = _start("animals_%d" % Time.get_ticks_msec())
	var items = server.items
	var entities = server.entities
	var breeding = entities.breeding
	var p := ServerPlayer.new(server, 105, "Farmer")
	p.player_id = "farmer"
	server.players[105] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 1000.0
	var types = entities.registry
	var at := Vector3(9.5, y + 1, 8.5)
	# Breeding cows with wheat.
	var cow_a = entities.spawn(types.id_of("vanilla:cow"), at)
	var cow_b = entities.spawn(types.id_of("vanilla:cow"), at + Vector3(0.8, 0, 0))
	p.inventory.set_slot(0, items.id_of("base:wheat"), 10)
	p.inventory.selected = 0
	_check(breeding._tempt_score(cow_a.brain) > 0.0, "cows follow a player holding wheat")
	server.on_interact_entity(105, cow_a.id)
	_check(breeding.in_love(cow_a) and p.inventory.counts[0] == 9, "feeding a cow wheat makes it fall in love")
	server.on_interact_entity(105, cow_a.id)
	_check(p.inventory.counts[0] == 9, "a cow in love will not eat more")
	server.on_interact_entity(105, cow_b.id)
	_check(breeding.partner_for(cow_a) == cow_b and breeding._breed_score(cow_a.brain) > 0.0, "two cows in love find each other")
	var calf = breeding.mate(cow_a, cow_b)
	_check(calf != null and calf.data.get("baby", false) and calf.data.look.scale == 0.5, "they have a small calf")
	_check(not breeding.in_love(cow_a) and float(cow_a.data.breed_cooldown) > 0.0, "parents rest before breeding again")
	var grow: float = float(calf.data.grow_left)
	server.on_interact_entity(105, calf.id)
	_check(float(calf.data.grow_left) < grow, "feeding a calf helps it grow")
	breeding.update(10000.0)
	_check(not calf.data.get("baby", false) and calf.data.look.scale == 1.0, "the calf grows up")
	# Milk from a bucket.
	p.inventory.set_slot(1, items.id_of("vanilla:bucket"), 1)
	p.inventory.selected = 1
	server.on_interact_entity(105, cow_a.id)
	_check(p.inventory.count_of(items.id_of("vanilla:milk_bucket")) == 1 and p.inventory.count_of(items.id_of("vanilla:bucket")) == 0, "a bucket milks a cow")
	p.add_modifier("food:vanilla:rotten_flesh:1", "hunger_drain", 0.5, "add", 30.0)
	server.hunger.set_hunger(p, 10.0)
	server.hunger.finish_eating(p, p.inventory.ids.find(items.id_of("vanilla:milk_bucket")))
	_check(not p.modifiers.has("food:vanilla:rotten_flesh:1") and p.inventory.count_of(items.id_of("vanilla:bucket")) == 1, "milk cures food poisoning and gives the bucket back")
	# Sheep: colors, shearing, regrowth, dyeing, lambs.
	var sheep = entities.spawn(types.id_of("vanilla:sheep"), at + Vector3(0, 0, 0.8))
	_check(sheep.data.get("color") is String and sheep.data.look.tint.has("wool"), "sheep get a natural wool color")
	var white: int = items.id_of("vanilla:wool_white")
	sheep.data.color = "white"
	p.inventory.set_slot(2, items.id_of("vanilla:shears"), 1)
	p.inventory.selected = 2
	var drops_before: int = entities.in_radius(at, 5.0, 0).size()
	server.on_interact_entity(105, sheep.id)
	_check(sheep.data.get("sheared", false) and sheep.data.look.hide == ["wool"] and entities.in_radius(at, 5.0, 0).size() > drops_before, "shears take the wool")
	_check(int(p.inventory.data[2].get("damage", 0)) == 1, "shearing wears the shears")
	var mod_animals = null
	for m in server._mods:
		if m.get("animals") != null:
			mod_animals = m.animals
	if mod_animals != null:
		sheep.data.regrow_left = 1.0
		mod_animals._tick()
		_check(not sheep.data.get("sheared", false) and sheep.data.look.hide == [], "the wool grows back")
	p.inventory.set_slot(3, items.id_of("vanilla:dye_red"), 2)
	p.inventory.selected = 3
	server.on_interact_entity(105, sheep.id)
	_check(sheep.data.color == "red" and sheep.data.look.tint.wool == "#b83030", "dye turns a sheep red")
	var other_sheep = entities.spawn(types.id_of("vanilla:sheep"), at + Vector3(0.8, 0, 0.8))
	if mod_animals != null:
		mod_animals._set_color(other_sheep, "white")
	var lamb = breeding.mate(sheep, other_sheep)
	_check(lamb.data.get("color") == "pink", "a red and a white sheep have a pink lamb (%s)" % lamb.data.get("color"))
	entities.kill(lamb)
	_check(not entities.in_radius(lamb.body.position, 3.0, 0).any(func(d): return d.item_id == items.id_of("vanilla:wool_pink")), "lambs drop nothing")
	_check(server.recipes.index_of("vanilla:bed_pink") >= 0 or server.recipes.recipes.any(func(r): return r.output == items.id_of("vanilla:bed_pink")), "pink wool makes a pink bed")
	# Chickens lay eggs.
	var chicken = entities.spawn(types.id_of("vanilla:chicken"), at + Vector3(-1, 0, 0))
	_check(float(chicken.data.get("next_egg", 0.0)) > 0.0, "hens count down to their next egg")
	if mod_animals != null:
		chicken.data.next_egg = 1.0
		mod_animals._tick()
		_check(entities.in_radius(chicken.body.position, 2.0, 0).any(func(d): return d.item_id == items.id_of("vanilla:egg")), "a hen lays an egg")
	_check(mod_animals != null, "found the vanilla animals module")
	server.queue_free()
	await get_tree().process_frame


func _taming() -> void:
	var server = _start("taming_%d" % Time.get_ticks_msec())
	var items = server.items
	var entities = server.entities
	var taming = entities.taming
	var p := ServerPlayer.new(server, 106, "Ranger")
	p.player_id = "ranger"
	server.players[106] = p
	var stranger := ServerPlayer.new(server, 107, "Stranger")
	stranger.player_id = "stranger"
	server.players[107] = stranger
	var y: int = server.surface_height(8, 8)
	for x in range(-4, 40):
		for z in range(0, 16):
			for dy in range(1, 4):
				server.set_block_authoritative(Vector3i(x, y + dy, z), 0)
			server.set_block_authoritative(Vector3i(x, y, z), server.registry.id_of("base:stone"))
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.state.on_ground = true
	stranger.state.position = Vector3(12.5, y + 1, 12.5)
	p.edit_tokens = 1000.0
	var wolf = entities.spawn(entities.registry.id_of("vanilla:wolf"), Vector3(9.5, y + 1, 8.5))
	_check(wolf.data.look.hide == ["collar"], "wild wolves have no collar")
	p.inventory.set_slot(0, items.id_of("vanilla:bone"), 20)
	p.inventory.selected = 0
	taming.config_of(wolf).chance = 1.0
	server.on_interact_entity(106, wolf.id)
	_check(taming.is_tamed(wolf) and wolf.data.owner == "ranger" and p.inventory.counts[0] == 19, "a bone tames the wolf")
	_check(wolf.data.look.hide == [] and wolf.data.get("no_despawn", false), "tamed wolves wear a collar and never despawn")
	_check(not entities.ai.is_enemy(wolf.brain, p), "a tamed wolf never attacks its owner")
	# Sit and follow.
	p.inventory.selected = 1
	server.on_interact_entity(106, wolf.id)
	_check(wolf.data.get("sitting", false) and taming._sit_score(wolf.brain) > 1.0, "right-click makes it sit")
	server.on_interact_entity(107, wolf.id)
	_check(wolf.data.get("sitting", false), "only the owner can make it stand")
	server.on_interact_entity(106, wolf.id)
	_check(not wolf.data.get("sitting", false), "right-click again makes it stand")
	p.state.position = Vector3(16.5, y + 1, 8.5)
	_check(taming._follow_score(wolf.brain) > 0.0, "it follows its owner")
	p.state.position = Vector3(35.5, y + 1, 8.5)
	taming.update()
	_check(wolf.body.position.distance_to(p.state.position) < 4.0, "a wolf left far behind catches up (%.1f)" % wolf.body.position.distance_to(p.state.position))
	# Defending.
	var zombie = entities.spawn(entities.registry.id_of("vanilla:zombie"), p.state.position + Vector3(3, 0, 0))
	p.hurt_timer = 0.0
	p.inventory.creative = false
	server.damage_player(p, 1.0, "mob", zombie)
	_check(float(wolf.brain.threat.get(entities.ai.key_of(zombie), 0.0)) > 0.0 and entities.ai.is_enemy(wolf.brain, zombie), "it turns on whatever hurts its owner")
	var pig = entities.spawn(entities.registry.id_of("vanilla:pig"), p.state.position + Vector3(0, 0, 2))
	taming.owner_attacked(p, pig)
	_check(float(wolf.brain.threat.get(entities.ai.key_of(pig), 0.0)) > 0.0, "it joins its owner's attacks")
	entities.damage(wolf, 1.0, "attack", p)
	_check(float(wolf.brain.threat.get(entities.ai.key_of(p), 0.0)) == 0.0, "the owner hitting it does not make it hostile")
	taming.set_sitting(wolf, true, p)
	var threat_before: float = float(wolf.brain.threat.get(entities.ai.key_of(zombie), 0.0))
	taming.owner_hurt(p, zombie)
	_check(float(wolf.brain.threat.get(entities.ai.key_of(zombie), 0.0)) == threat_before, "sitting wolves stay put")
	entities.spawning.despawn()
	_check(not wolf.removed, "tamed wolves stay loaded")
	server.queue_free()
	await get_tree().process_frame


func _explosions() -> void:
	var server = _start("explosions_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var stone: int = reg.id_of("base:stone")
	var bedrock: int = reg.id_of("base:bedrock")
	var y: int = server.surface_height(8, 8) + 1
	for x in range(0, 16):
		for z in range(0, 16):
			for dy in range(0, 16):
				server.set_block_authoritative(Vector3i(x, y + dy, z), stone if dy < 8 else 0)
	server.set_block_authoritative(Vector3i(8, y + 3, 9), bedrock)
	var p := ServerPlayer.new(server, 108, "Miner")
	p.player_id = "miner"
	server.players[108] = p
	p.inventory.creative = false
	var center := Vector3(8.5, y + 4.5, 8.5)
	server.set_block_authoritative(Vector3i(8, y + 4, 8), 0)
	var drops_before: int = server.entities.in_radius(center, 8.0, 0).size()
	var ev: Dictionary = server.explosions.explode(center, 3.0)
	var broken := 0
	for x in range(4, 13):
		for z in range(4, 13):
			for dy in range(0, 8):
				if server.world.get_block_v(Vector3i(x, y + dy, z)) == 0:
					broken += 1
	_check(broken > 15 and ev.blocks.size() > 15, "a power-3 blast carves out stone (%d blocks)" % broken)
	_check(server.world.get_block_v(Vector3i(8, y + 3, 9)) == bedrock, "bedrock survives")
	_check(server.entities.in_radius(center, 8.0, 0).size() > drops_before, "some broken blocks drop items")
	# Damage falls off with distance and cover.
	p.state.position = Vector3(8.5, y + 8, 10.5)
	p.health = 20.0
	p.hurt_timer = 0.0
	server.explosions.explode(Vector3(8.5, y + 8.5, 8.5), 3.0, {"break_blocks": false})
	var near_damage: float = 20.0 - p.health
	_check(near_damage > 3.0, "a player next to a blast is badly hurt (%.1f)" % near_damage)
	p.health = 20.0
	p.hurt_timer = 0.0
	p.state.position = Vector3(8.5, y + 8, 14.5)
	server.explosions.explode(Vector3(8.5, y + 8.5, 8.5), 3.0, {"break_blocks": false})
	var far_damage: float = 20.0 - p.health
	_check(far_damage < near_damage, "further away hurts less (%.1f)" % far_damage)
	# Mob griefing off: a mob's blast leaves blocks alone.
	server.gameplay.mob_griefing = false
	var zombie = server.entities.spawn(server.entities.registry.id_of("vanilla:zombie"), Vector3(3.5, y + 8, 3.5))
	var solid_before: int = server.world.get_block_v(Vector3i(3, y + 7, 3))
	var mob_ev: Dictionary = server.explosions.explode(Vector3(3.5, y + 8.2, 3.5), 3.0, {"source": zombie})
	_check(mob_ev.blocks.is_empty() and server.world.get_block_v(Vector3i(3, y + 7, 3)) == solid_before, "mob_griefing off keeps mob blasts from breaking blocks")
	server.gameplay.mob_griefing = true
	server.queue_free()
	await get_tree().process_frame


func _biomes() -> void:
	var server = _start("biomes_%d" % Time.get_ticks_msec())
	var gen = server.biome_generator
	var reg = server.registry
	_check(gen != null and server.generator == gen and gen.biomes.size() >= 10, "vanilla uses the biome generator with the classic biomes")
	_check(gen.biome_ids.has("vanilla:mushroom_fields") and gen.biome_ids.has("vanilla:shadowwood"), "vanilla has its fantasy biomes")
	var weird := 0
	for i in 400:
		var name: String = gen.biome_at(i * 97 - 20000, i * 53 - 11000)
		if name in ["vanilla:mushroom_fields", "vanilla:shadowwood"]:
			weird += 1
	_check(weird > 0 and weird < 60, "fantasy biomes are rare but present (%d of 400 samples)" % weird)
	# Find a forest and a desert near the origin.
	var spots := {}
	for r in range(0, 3000, 32):
		for a in 12:
			var x := int(cos(a * TAU / 12.0) * r)
			var z := int(sin(a * TAU / 12.0) * r)
			var name: String = gen.biome_at(x, z)
			if not spots.has(name) and gen.biome_at(x + 40, z) == name and gen.biome_at(x - 40, z) == name and gen.biome_at(x, z + 40) == name and gen.biome_at(x, z - 40) == name:
				spots[name] = Vector2i(x, z)
	_check(spots.has("vanilla:forest") and spots.has("vanilla:desert") and spots.has("vanilla:ocean"), "forests, deserts and oceans exist (%s)" % str(spots.keys()))
	var Chunk = load("res://engine/shared/chunk.gd")
	var count := func(coord: Vector2i, ids: Array) -> int:
		var c = Chunk.new(coord)
		gen.generate(c)
		var n := 0
		for i in range(0, c.blocks.size(), 2):
			if ids.has(c.blocks.decode_u16(i)):
				n += 1
		return n
	if spots.has("vanilla:forest"):
		var fc := Vector2i(floori(spots["vanilla:forest"].x / 16.0), floori(spots["vanilla:forest"].y / 16.0))
		_check(count.call(fc, [reg.id_of("base:log"), reg.id_of("base:birch_log")]) > 8, "forests grow trees")
		var a = Chunk.new(fc)
		var b = Chunk.new(fc)
		gen.generate(a)
		gen.generate(b)
		_check(a.blocks == b.blocks, "generation is deterministic")
		# Trees near a chunk border spill their leaves into the neighbour.
		var leaves: int = reg.id_of("base:leaves")
		var border_leaves := 0
		for dz in range(0, 6):
			var c = Chunk.new(fc + Vector2i(1, dz))
			gen.generate(c)
			for y in range(40, 90):
				for z in 16:
					if c.blocks.decode_u16(Chunk.index(0, y, z) << 1) == leaves:
						border_leaves += 1
		_check(border_leaves > 0, "leaves reach across chunk borders")
	if spots.has("vanilla:desert"):
		var d: Vector2i = spots["vanilla:desert"]
		var h: int = gen.surface_height(d.x, d.y)
		var dc := Vector2i(floori(d.x / 16.0), floori(d.y / 16.0))
		var c = Chunk.new(dc)
		gen.generate(c)
		var top: int = c.blocks.decode_u16(Chunk.index(d.x - dc.x * 16, h, d.y - dc.y * 16) << 1)
		_check(top == reg.id_of("base:sand") and count.call(dc, [reg.id_of("base:grass")]) == 0, "deserts are sand without grass")
	# Caves, lava and deep ore.
	var lava: int = reg.id_of("base:lava")
	var cobalt: int = reg.id_of("base:cobalt_ore")
	var under_air := 0
	var lava_seen := 0
	var cobalt_high := 0
	var cobalt_seen := 0
	for i in 12:
		var c = Chunk.new(Vector2i(i * 7 - 40, i * 5 - 30))
		gen.generate(c)
		for pass_object in server.generation_passes:
			pass_object.decorate(c, server.world_seed)
		for y in range(4, 40):
			for z in 16:
				for x in 16:
					var id: int = c.blocks.decode_u16(Chunk.index(x, y, z) << 1)
					if id == 0:
						under_air += 1
					elif id == lava:
						lava_seen += 1
						_check(y <= 10, "lava only fills the deepest caves (y %d)" % y) if lava_seen == 1 else null
					elif id == cobalt:
						cobalt_seen += 1
						if y > 25:
							cobalt_high += 1
	_check(under_air > 1000, "caves and caverns are carved underground (%d air blocks)" % under_air)
	_check(lava_seen > 0 and cobalt_seen > 0 and cobalt_high == 0, "lava pools and cobalt ore appear deep down")
	# Lava hurts.
	var swimmer := ServerPlayer.new(server, 109, "Swimmer")
	swimmer.player_id = "swimmer"
	server.players[109] = swimmer
	swimmer.inventory.creative = false
	var pool := Vector3i(spots.values()[0].x if not spots.is_empty() else 0, 5, spots.values()[0].y if not spots.is_empty() else 0)
	server._ensure_chunk(Vector2i(floori(pool.x / 16.0), floori(pool.z / 16.0)))
	server.set_block_authoritative(pool, lava)
	server.set_block_authoritative(pool + Vector3i.UP, lava)
	swimmer.state.position = Vector3(pool) + Vector3(0.5, 0.0, 0.5)
	server._update_health(swimmer, 0.6)
	_check(swimmer.health < 20.0, "standing in lava burns (%.1f)" % swimmer.health)
	server.players.erase(109)
	# Biome water.
	_check(gen.biomes[gen.biome_ids["vanilla:mushroom_fields"]].water == reg.id_of("vanilla:glowing_water"), "mushroom fields have glowing water")
	# Spawn rules can be limited to biomes.
	var rule := {"entity": server.entities.registry.id_of("vanilla:cow"), "biomes": ["vanilla:desert"], "light": [0, 15], "on": []}
	server.entities.spawning.add_rule(rule)
	var added: Dictionary = server.entities.spawning.rules.back()
	if spots.has("vanilla:forest"):
		var f: Vector2i = spots["vanilla:forest"]
		server._ensure_chunk(Vector2i(floori(f.x / 16.0), floori(f.y / 16.0)))
		var spot: Vector3 = server.entities.spawning.find_spot(Vector3(f.x, gen.surface_height(f.x, f.y) + 1, f.y), added, 1.0, 1.0, 6.0)
		_check(spot == Vector3.INF, "a desert-only mob does not spawn in a forest")
	server.queue_free()
	await get_tree().process_frame


func _structures() -> void:
	var server = _start("structures_%d" % Time.get_ticks_msec())
	var gen = server.biome_generator
	var reg = server.registry
	var st = gen.structures
	var stone: int = reg.id_of("base:cobblestone")
	var chest: int = reg.id_of("base:chest")
	# A 5x4x3 hut: walls, a chest with loot in one corner, air inside.
	var doc := {"size": [5, 4, 3], "palette": ["base:cobblestone", "engine:air", "base:chest"], "blocks": [], "data": {"1,1,1": {"loot": "test:hut"}}}
	for y in 4:
		for z in 3:
			for x in 5:
				var wall: bool = y == 0 or y == 3 or x == 0 or x == 4 or z == 0 or z == 2
				doc.blocks.append([x, y, z, 0 if wall else 1])
	doc.blocks.append([1, 1, 1, 2])
	_check(st.add_template("test:hut", doc), "a template loads from JSON data")
	server.loot.register("test:hut", {"rolls": [2, 2], "entries": [{"item": "base:iron_ingot", "count": [3, 3]}]})
	st.add_set("test:huts", {"templates": [{"template": "test:hut"}], "spacing": 3, "separation": 0, "place": "surface"})
	st.freeze(reg)
	# Generate a block of chunks and count hut walls: every hut must be whole, even across chunk borders.
	var Chunk = load("res://engine/shared/chunk.gd")
	var starts := []
	for rz in range(0, 3):
		for rx in range(0, 3):
			var start: Dictionary = st.start_for(st.sets.back(), Vector2i(rx, rz), gen)
			if not start.is_empty():
				starts.append(start)
	_check(not starts.is_empty(), "structure regions pick starts (%d)" % starts.size())
	var chunks := {}
	for cz in range(-1, 10):
		for cx in range(-1, 10):
			var c = Chunk.new(Vector2i(cx, cz))
			gen.generate(c)
			chunks[Vector2i(cx, cz)] = c
	var whole := 0
	var loot_chests := 0
	for start in starts:
		var piece: Dictionary = start.pieces[0]
		var walls := 0
		for b in st.templates["test:hut"].blocks:
			if b[3] != stone:
				continue
			var p: Vector3i = piece.position + st.rotate(Vector3i(b[0], b[1], b[2]), Vector3i(5, 4, 3), piece.rotation)
			var c = chunks.get(Vector2i(floori(p.x / 16.0), floori(p.z / 16.0)))
			if c != null and c.blocks.decode_u16(Chunk.index(p.x & 15, p.y, p.z & 15) << 1) == stone:
				walls += 1
		if walls == st.templates["test:hut"].blocks.filter(func(b): return b[3] == stone).size():
			whole += 1
		var chest_pos: Vector3i = piece.position + st.rotate(Vector3i(1, 1, 1), Vector3i(5, 4, 3), piece.rotation)
		var cc = chunks.get(Vector2i(floori(chest_pos.x / 16.0), floori(chest_pos.z / 16.0)))
		if cc != null and cc.generated_data.has(chest_pos) and cc.generated_data[chest_pos].loot == "test:hut":
			loot_chests += 1
	_check(whole == starts.size(), "every generated hut is whole across chunk borders (%d of %d)" % [whole, starts.size()])
	_check(loot_chests == starts.size(), "hut chests carry their loot table")
	# Loot fills on first open.
	var p := ServerPlayer.new(server, 110, "Builder")
	p.player_id = "builder"
	server.players[110] = p
	var y: int = server.surface_height(8, 8) + 3
	var at := Vector3i(4, y, 4)
	server.structure_tools.place("test:hut", at, 1)
	var placed_chest: Vector3i = at + st.rotate(Vector3i(1, 1, 1), Vector3i(5, 4, 3), 1)
	_check(server.world.get_block_v(placed_chest) == chest, "a template places with rotation")
	var container = server.containers.get_container(placed_chest)
	var iron := 0
	for i in container.size():
		if container.get_item(i).item == server.items.id_of("base:iron_ingot"):
			iron += int(container.get_item(i).count)
	_check(iron == 6 and not server.get_block_data(placed_chest).has("loot"), "the chest fills from its loot table once (%d iron)" % iron)
	# Capture and place back.
	var captured: Dictionary = st.capture(server, at, at + Vector3i(2, 3, 4))
	_check(captured.size == [3, 4, 5] and captured.blocks.size() == 60, "a selection captures into a template")
	# Vanilla structures: every kind appears somewhere, dungeons get spawners and chests, mineshafts branch.
	var found := {}
	var mineshaft_pieces := 0
	for s in st.sets:
		if not String(s.name).begins_with("vanilla:"):
			continue
		for rz in range(-6, 7):
			for rx in range(-6, 7):
				var start: Dictionary = st.start_for(s, Vector2i(rx, rz), gen)
				if not start.is_empty():
					if not found.has(s.name):
						found[s.name] = start
					if s.name == "vanilla:mineshaft":
						mineshaft_pieces = maxi(mineshaft_pieces, start.pieces.size())
	_check(found.has("vanilla:dungeon") and found.has("vanilla:ruins") and found.has("vanilla:watchtower") and found.has("vanilla:mineshaft"),
		"dungeons, ruins, watchtowers and mineshafts generate (%s)" % str(found.keys()))
	_check(mineshaft_pieces > 8, "mineshafts branch into many corridors (%d pieces)" % mineshaft_pieces)
	if found.has("vanilla:dungeon"):
		var dungeon: Dictionary = found["vanilla:dungeon"]
		var spawner_at: Vector3i = dungeon.pieces[0].position + st.rotate(Vector3i(4, 1, 4), Vector3i(9, 6, 9), dungeon.pieces[0].rotation)
		var dc = Chunk.new(Vector2i(floori(spawner_at.x / 16.0), floori(spawner_at.z / 16.0)))
		gen.generate(dc)
		_check(dc.blocks.decode_u16(Chunk.index(spawner_at.x & 15, spawner_at.y, spawner_at.z & 15) << 1) == reg.id_of("base:spawner")
			and dc.generated_data.get(spawner_at, {}).has("spawner"), "a dungeon has its spawner")
	var arena_at := Vector3i(40, server.surface_height(40, 40) + 1, 40)
	server.structure_tools.place("vanilla:colossus_arena", arena_at, 0)
	var altar := arena_at + Vector3i(12, 2, 12)
	_check(server.world.get_block_v(altar) == reg.id_of("vanilla:ancient_altar"), "the arena has its altar")
	p.inventory.creative = false
	p.state.position = Vector3(altar) + Vector3(3, 0, 3)
	var mods: Array = server._mods.filter(func(m): return m.get("structures") != null)
	if not mods.is_empty():
		mods[0].structures._altar_tick({"position": altar})
		_check(server.entities.in_radius(Vector3(altar), 12.0, server.entities.registry.id_of("vanilla:colossus")).size() == 1,
			"stepping into the arena wakes the Colossus")
		mods[0].structures._altar_tick({"position": altar})
		_check(server.entities.in_radius(Vector3(altar), 12.0, server.entities.registry.id_of("vanilla:colossus")).size() == 1, "only once")
	# Spawners.
	var spawner: int = reg.id_of("base:spawner")
	var sp := Vector3i(20, y, 20)
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			server.set_block_authoritative(sp + Vector3i(dx, -1, dz), stone)
			for dy in range(0, 3):
				server.set_block_authoritative(sp + Vector3i(dx, dy, dz), 0)
	server.set_block_authoritative(sp, spawner)
	# Range 2 keeps every try on the cleared floor; spawn spots are random, so allow a few ticks.
	server.set_block_data(sp, {"spawner": {"entity": ["vanilla:zombie"], "count": [2, 2], "range": 2}})
	p.state.position = Vector3(sp) + Vector3(4, 0, 4)
	server.set_world_time(0.0, 1200.0)
	for i in 3:
		if server.entities.in_radius(Vector3(sp), 8.0, server.entities.registry.id_of("vanilla:zombie")).is_empty():
			server.spawners._tick({"position": sp})
	_check(server.entities.in_radius(Vector3(sp), 8.0, server.entities.registry.id_of("vanilla:zombie")).size() >= 1, "a spawner makes its mobs when a player is near")
	server.queue_free()
	await get_tree().process_frame


func _dev_log() -> void:
	var mods := ["buggy"]
	if ClassDB.class_exists(&"NativeJsRuntime"):
		mods.append("buggy_js")
	var server := GameServer.new()
	add_child(server)
	var world := "dev_log_%d" % Time.get_ticks_msec()
	var err: Error = server.start({"mods": PackedStringArray(mods), "mod_dirs": PackedStringArray(["res://tests/mods"]),
		"world": world, "data_dir": DATA_DIR, "seed": 42, "offline": true, "log_level": "warn,buggy:info"})
	_check(err == OK, "buggy test mods load")
	if err != OK:
		server.queue_free()
		return
	server.set_physics_process(false)
	var log = server.dev_log
	var p := ServerPlayer.new(server, 90, "Author")
	server.players[90] = p
	server._commands["complain"].handler.call(p, PackedStringArray())
	log.drain()
	var buggy: Array = log.recent(20, "buggy")
	_check(buggy.any(func(e): return e.message == "hello from buggy" and e.level == "info"), "mods log info lines")
	_check(not buggy.any(func(e): return e.message == "quiet detail"), "debug lines are dropped below the mod's level")
	_check(buggy.any(func(e): return e.level == "warn" and e.message == "running low"), "warnings are kept")
	var reported: Array = log.sorted_errors().filter(func(e): return e.source == "buggy" and e.message == "something broke")
	_check(reported.size() == 1 and reported[0].file.ends_with("tests/mods/buggy/main.gd") and reported[0].line == 14,
		"api.error records the mod's file and line")
	log.set_level("buggy", "debug")
	server._commands["complain"].handler.call(p, PackedStringArray())
	_check(log.recent(30, "buggy").any(func(e): return e.message == "quiet detail"), "/log level turns debug lines on")
	_check(log.errors.values().filter(func(e): return e.message == "something broke")[0].count == 2, "repeated errors are grouped with a count")
	# A real script error inside a mod.
	var alerts := []
	log.error_added.connect(func(e, first): alerts.append([e.source, first]))
	server._commands["crash"].handler.call(p, PackedStringArray())
	log.drain()
	var crash: Array = log.sorted_errors().filter(func(e): return e.source == "buggy" and e.message.contains("volume"))
	_check(crash.size() == 1 and crash[0].line == 19 and crash[0].file.ends_with("buggy/main.gd") and not crash[0].stack.is_empty(),
		"GDScript runtime errors are caught with the mod, file, line and stack")
	_check(alerts.has(["buggy", true]), "new errors notify listeners (admin alerts)")
	if mods.has("buggy_js"):
		server._commands["jslog"].handler.call(p, PackedStringArray())
		server._commands["jscrash"].handler.call(p, PackedStringArray())
		log.drain()
		_check(log.recent(20, "buggy_js", "warn").any(func(e): return e.message == "js running low"), "console.warn logs a warning from JavaScript")
		_check(not log.recent(20, "buggy_js").any(func(e): return e.message.begins_with("hello from js")), "JavaScript info lines follow the default level (warn)")
		var js: Array = log.sorted_errors().filter(func(e): return e.source == "buggy_js")
		_check(js.size() == 1 and js[0].file.ends_with("main.js") and js[0].line == 5, "JavaScript errors are caught with file and line")
		var commands: int = server._commands.size()
		var reloaded: Dictionary = server.mod_reload.reload("buggy_js")
		_check(reloaded.ok and server._commands.size() == commands and server._commands.has("jslog") and server.mod_instances.buggy_js.runtime != null,
			"JavaScript mods reload in a fresh runtime")
	server._exit_tree()
	var text := FileAccess.get_file_as_string(DATA_DIR.path_join(world).path_join("logs/latest.log"))
	_check(text.contains("[buggy] hello from buggy") and text.contains("ERROR [buggy]"), "the log is written to the world's logs/latest.log")
	server.queue_free()
	await get_tree().process_frame


func _dev_tools() -> void:
	var server = _start("dev_tools_%d" % Time.get_ticks_msec())
	var tools = server.dev_tools
	var api = preload("res://engine/server/mod_api.gd").new(server, {"id": "tester", "dir": "res://tests"})
	var p := ServerPlayer.new(server, 95, "Dev")
	p.player_id = "dev"
	server.players[95] = p
	# Access: admins or --dev.
	_check(not tools.allowed(p), "dev tools are closed to ordinary players")
	server.dev_mode = true
	_check(tools.allowed(p), "--dev opens the dev tools to everyone")
	# Profiler: handlers, tasks and block ticks are credited to their mod.
	api.on("tester_ping", func(ev):
		var x := 0
		for i in 2000:
			x += i
		ev.cancelled = true)
	api.on("tester_ping", func(_ev): pass, 10)
	for i in 5:
		server.emit("tester_ping", {"player": p, "block": server.registry.id_of("base:stone"), "cancelled": false})
	var ran := [false]
	api.after(0.0, func(): ran[0] = true)
	server._time += 1.0
	server._run_tasks()
	tools._roll_window()
	var rows: Array = tools.perf()
	var ping: Array = rows.filter(func(r): return r.owner == "tester" and r.category == "event:tester_ping")
	_check(ping.size() == 1 and ping[0].calls == 10 and ping[0].ms_per_s > 0.0, "the profiler times each mod's event handlers")
	_check(ran[0] and rows.any(func(r): return r.owner == "tester" and r.category == "task"), "scheduled tasks are timed per mod")
	_check(rows.any(func(r): return r.owner == "tester" and r.category == "total"), "the profiler totals each mod")
	# Tracer: subscribe to events, emit, read the record.
	tools.subscribe(p, ["events"])
	_check(tools.tracing, "subscribing to events turns tracing on")
	server.emit("tester_ping", {"player": p, "block": server.registry.id_of("base:stone"), "cancelled": false})
	server.emit("tick", {"delta": 0.016, "tick": 1})
	var rec: Dictionary = tools.trace.back()
	_check(rec.event == "tester_ping" and rec.payload.player == "player Dev" and rec.payload.block.begins_with("base:stone"),
		"traced payloads name players and blocks")
	_check(rec.handlers.size() == 2 and rec.handlers[0].owner == "tester" and rec.handlers[1].get("cancelled") == true and rec.cancelled,
		"the trace shows handler order and who cancelled")
	_check(not tools.trace.any(func(t): return t.event == "tick"), "tick events are left out unless asked for")
	tools.set_trace_filter(p, "tick")
	server.emit("tick", {"delta": 0.016, "tick": 2})
	server.emit("tester_ping", {"player": p, "cancelled": false})
	_check(tools.trace.back().event == "tick", "a trace filter picks events by name")
	tools.unsubscribe(95)
	_check(not tools.tracing, "tracing stops when nobody watches")
	# Inspector.
	var y: int = server.surface_height(8, 8)
	var info: Dictionary = tools.inspect({"pos": Vector3i(8, y, 8)})
	_check(info.kind == "block" and info.fields.has("definition") and info.fields.has("light"), "blocks can be inspected")
	var zombie = server.entities.spawn(server.entities.registry.id_of("vanilla:zombie"), Vector3(8.5, y + 1, 8.5))
	info = tools.inspect({"entity": zombie.id})
	_check(info.kind == "entity" and info.fields.ai.has("behavior") and info.fields.type == "vanilla:zombie", "mobs can be inspected with their AI state")
	info = tools.inspect({"player": 95})
	_check(info.kind == "player" and info.fields.name == "Dev" and info.fields.has("stats"), "players can be inspected")
	# Debug drawing only queues while someone watches.
	api.debug_box(Vector3.ZERO, Vector3.ONE, "#ff0000", 1.0, "here")
	_check(tools._shapes.is_empty(), "debug drawing costs nothing when nobody watches")
	tools.subscribe(p, ["draw"])
	api.debug_box(Vector3.ZERO, Vector3.ONE, "#ff0000", 1.0, "here")
	api.debug_path([Vector3.ZERO, Vector3(1, 0, 0), [2, 0, 0]])
	_check(tools._shapes.size() == 3 and tools._shapes[0].owner == "tester" and tools._shapes[2].points.size() == 3, "mods draw boxes, labels and paths for watchers")
	tools.subscribe(p, ["ai"])
	p.state.position = Vector3(10.5, y + 1, 8.5)
	tools._draw_ai(p)
	_check(tools._shapes.any(func(sh): return sh.owner == "engine:ai" and sh.type == "text"), "the AI view labels mobs near the watcher")
	server.queue_free()
	await get_tree().process_frame


func _dev_web() -> void:
	var server = _start("dev_web_%d" % Time.get_ticks_msec())
	var web = server.dev_web
	var port := 25990 + randi() % 40
	_check(web.start(port) == OK and web.url().contains("token="), "the dev dashboard starts with a token")
	var p := ServerPlayer.new(server, 97, "Watcher")
	p.player_id = "watcher"
	server.players[97] = p
	server.dev_log.add("info", "tester", "hello dashboard")
	var page: Array = await _http_get(server, port, "/?token=" + web.token)
	_check(page[0] == 200 and page[1].contains("VoxelCraft Dev Dashboard"), "the dashboard page is served with the token")
	var denied: Array = await _http_get(server, port, "/api/state?token=wrong")
	_check(denied[0] == 403, "the API refuses a wrong token")
	var state: Array = await _http_get(server, port, "/api/state?token=%s&events=1&filter=tester_*" % web.token)
	var json = JSON.parse_string(state[1])
	_check(state[0] == 200 and json is Dictionary and json.logs.any(func(e): return e.message == "hello dashboard") and json.players.size() == 1,
		"the state endpoint returns logs and players")
	_check(server.dev_tools.tracing, "a polling dashboard turns event tracing on")
	server.emit("tester_signal", {"player": p})
	state = await _http_get(server, port, "/api/state?token=%s&events=1&filter=tester_*&events_after=0" % web.token)
	json = JSON.parse_string(state[1])
	_check(json.events.any(func(ev): return ev.event == "tester_signal" and ev.payload.player == "player Watcher"), "traced events reach the dashboard")
	var info: Array = await _http_get(server, port, "/api/inspect?token=%s&player=97" % web.token)
	_check(info[0] == 200 and JSON.parse_string(info[1]).fields.name == "Watcher", "the dashboard inspects players")
	# Creations review.
	server.ugc.set_policy({"accept": "approval"})
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.9))
	var png := img.save_png_to_buffer()
	var m: Dictionary = preload("res://engine/shared/creations.gd").make("skin", "skin", png, "Sky", "watcher", "Watcher")
	server.ugc.offer(p, [m])
	server.ugc.upload_piece(p, m.id, 0, png.size(), png)
	var listed: Array = await _http_get(server, port, "/api/ugc?token=%s&filter=pending" % web.token)
	_check(listed[0] == 200 and JSON.parse_string(listed[1]).items[0].id == m.id, "the dashboard lists creations waiting for review")
	var file: Array = await _http_get(server, port, "/api/ugc_file?token=%s&id=%s" % [web.token, m.id])
	_check(file[0] == 200 and file[1].contains("PNG"), "the dashboard serves a skin's image")
	await _http_get(server, port, "/api/ugc_action?token=%s&action=set_status&id=%s&status=approved" % [web.token, m.id])
	_check(server.ugc.is_approved(m.id), "the dashboard approves creations")
	if web.streaming():
		# Live push: a Server-Sent Events stream gets state updates with new log lines.
		var stream := StreamPeerTCP.new()
		stream.connect_to_host("127.0.0.1", port)
		var received := ""
		var sent := false
		var deadline := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and not received.contains("pushed line"):
			stream.poll()
			if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
				stream.put_data(("GET /api/stream?token=%s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % web.token).to_utf8_buffer())
				sent = true
			if stream.get_available_bytes() > 0:
				received += stream.get_utf8_string(stream.get_available_bytes())
			if received.contains("text/event-stream") and server.dev_log.entries[-1].message != "pushed line":
				server.dev_log.add("info", "tester", "pushed line")
			web.update(0.1)
			await get_tree().process_frame
		_check(received.contains("text/event-stream") and received.contains("event: state") and received.contains("pushed line"),
			"the native dashboard pushes new state over an event stream")
		stream.disconnect_from_host()
		var refused: Array = await _http_get(server, port, "/api/stream?token=wrong")
		_check(refused[0] == 403, "the event stream needs the token")
	web.stop()
	_check(not server.dev_tools.viewers.has(web.VIEWER_ID), "stopping the dashboard removes its viewer")
	server.queue_free()
	await get_tree().process_frame


## [status, body] of a GET to the dev dashboard, pumping the server while waiting.
func _http_get(server, port: int, path: String) -> Array:
	var http := HTTPClient.new()
	http.connect_to_host("127.0.0.1", port)
	var deadline := Time.get_ticks_msec() + 5000
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		http.poll()
		server.dev_web.update()
		await get_tree().process_frame
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return [0, ""]
	http.request(HTTPClient.METHOD_GET, path, [])
	var body := PackedByteArray()
	while Time.get_ticks_msec() < deadline:
		http.poll()
		server.dev_web.update()
		var status := http.get_status()
		if status == HTTPClient.STATUS_BODY:
			body.append_array(http.read_response_body_chunk())
		elif status != HTTPClient.STATUS_REQUESTING and http.has_response() and status != HTTPClient.STATUS_BODY:
			break
		elif status in [HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR]:
			break
		await get_tree().process_frame
	return [http.get_response_code(), body.get_string_from_utf8()]


const RELOAD_MOD_A := """extends "res://engine/server/mod.gd"
const Helper = preload("helper.gd")
var api
var calls := 0

func setup(mod_api) -> void:
	api = mod_api
	api.register_block("thing", {"textures": "", "hardness": 1.0, "drops": "base:dirt"})
	api.register_recipe({"base:planks": 1}, "reloadme:thing", 1, {"unlock": "known"})
	api.register_recipe({"base:planks": 2}, "base:stick", 1, {"id": "extra", "unlock": "known"})
	api.register_command("hello", "Say hello", func(player, _args): player.data["hello"] = Helper.greeting())
	api.on("tester_signal", func(ev): ev.count = int(ev.get("count", 0)) + 1)
	api.every(1.0, func(): calls += 1)
	api.register_guide_chapter("notes", {"title": "Notes"})
	api.register_guide_page("page", {"chapter": "notes", "title": "Version A", "blocks": [{"type": "text", "text": "a"}]})
	api.register_tutorial("tour", {"title": "Tour", "steps": [{"title": "One", "goal": {"type": "manual"}}, {"title": "Two", "goal": {"type": "manual"}}]})
"""
const RELOAD_MOD_B := """extends "res://engine/server/mod.gd"
const Helper = preload("helper.gd")
var api

func setup(mod_api) -> void:
	api = mod_api
	api.register_block("thing", {"textures": "", "hardness": 5.0, "drops": "base:dirt"})
	api.register_block("newthing", {"textures": ""})
	api.register_recipe({"base:planks": 3}, "reloadme:thing", 1, {"unlock": "known"})
	api.register_command("hello", "Say hello", func(player, _args): player.data["hello"] = Helper.greeting())
	api.on("tester_signal", func(ev): ev.count = int(ev.get("count", 0)) + 10)
	api.register_guide_chapter("notes", {"title": "Notes"})
	api.register_guide_page("page", {"chapter": "notes", "title": "Version B", "blocks": [{"type": "text", "text": "b"}]})
	api.register_tutorial("tour", {"title": "Tour", "steps": [{"title": "Only", "goal": {"type": "manual"}}]})
"""


func _write_reload_mod(dir: String, main: String, greeting: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var files := {"mod.json": JSON.stringify({"id": "reloadme", "name": "Reload me", "version": "1.0.0", "depends": ["base"]}),
		"main.gd": main, "helper.gd": "extends RefCounted\n\nstatic func greeting() -> String:\n\treturn \"%s\"\n" % greeting}
	for name in files:
		var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		f.store_string(files[name])
		f.close()


func _mod_reload() -> void:
	var mods_dir := DATA_DIR.path_join("reload_mods_%d" % Time.get_ticks_msec())
	var mod_dir := mods_dir.path_join("reloadme")
	_write_reload_mod(mod_dir, RELOAD_MOD_A, "hello A")
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["vanilla", "reloadme"]), "mod_dirs": PackedStringArray([mods_dir]),
		"world": "reload_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 42, "offline": true})
	_check(err == OK, "the reload test mod loads")
	if err != OK:
		server.queue_free()
		return
	server.set_physics_process(false)
	var p := ServerPlayer.new(server, 99, "Author")
	p.player_id = "author"
	server.players[99] = p
	var thing: int = server.registry.id_of("reloadme:thing")
	var extra: int = server.recipes.index_of("reloadme:extra")
	var thing_recipe: int = server.recipes.index_of("reloadme:thing")
	var handlers_before: int = server._handlers.get("tester_signal", []).size()
	server._commands["hello"].handler.call(p, PackedStringArray())
	_check(p.data.hello == "hello A" and server.emit("tester_signal", {"count": 0}).count == 1, "version A runs")
	server.tutorials.start(p, "reloadme:tour")
	server.tutorials.advance(p)
	# Version B on disk, then a quick reload.
	_write_reload_mod(mod_dir, RELOAD_MOD_B, "hello B")
	var result: Dictionary = server.mod_reload.reload("reloadme")
	_check(result.ok, "the mod reloads: %s" % result.get("error", ""))
	server._commands["hello"].handler.call(p, PackedStringArray())
	_check(p.data.hello == "hello B", "reloaded commands run the new code, including preloaded helper scripts")
	_check(server.emit("tester_signal", {"count": 0}).count == 10 and server._handlers["tester_signal"].size() == handlers_before,
		"old event handlers are replaced, not added to")
	_check(not server._tasks.values().any(func(t): return t.owner == "reloadme"), "timers the new version no longer starts are gone")
	_check(server.registry.id_of("reloadme:thing") == thing and server.registry.defs[thing].hardness == 5.0, "blocks keep their id and take the new definition")
	_check(server.registry.id_of("reloadme:newthing") < 0 and result.notes.any(func(n): return n.contains("newthing")), "new blocks are refused with a full reload note")
	_check(server.recipes.index_of("reloadme:thing") == thing_recipe and server.recipes.recipes[thing_recipe].inputs.values() == [3],
		"recipes keep their index and take new ingredients")
	_check(server.recipes.recipes[extra].get("removed", false) and server.craft(p, extra) == 0, "recipes no longer registered are removed")
	_check(server.guide.registry.get_page("reloadme:page").title == "Version B", "guide pages are replaced")
	_check(server.tutorials.state_of(p).active == "", "a tutorial that no longer has the player's step stops")
	_check(server.mod_instances["reloadme"].get("calls") == null, "the mod runs as a fresh instance")
	# A syntax error keeps the old version running.
	_write_reload_mod(mod_dir, RELOAD_MOD_B.replace("func setup(mod_api) -> void:", "func setup(mod_api) -> void:\n\tthis is not gdscript"), "hello C")
	result = server.mod_reload.reload("reloadme")
	_check(not result.ok and server._commands.has("hello"), "a mod that does not compile keeps its old version")
	# Watching files: a change schedules a reload.
	_write_reload_mod(mod_dir, RELOAD_MOD_B, "hello B")
	server.mod_reload.set_watching(true)
	var main_path := mod_dir.path_join("main.gd")
	server.mod_reload._mtimes["reloadme"][main_path] = 0
	server.mod_reload.update(1.5)
	_check(server.mod_reload._pending.has("reloadme") and server.mod_reload._pending.reloadme.scripts, "the file watcher notices changed scripts")
	server.mod_reload._pending.reloadme.due = 0.0
	server.mod_reload.update(0.0)
	_check(not server.mod_reload._pending.has("reloadme"), "the watcher reloads the mod after the debounce")
	# Vanilla reloads cleanly too (a big mod with worldgen, mobs, guide and tutorials).
	var before_blocks: int = server.registry.defs.size()
	result = server.mod_reload.reload("vanilla")
	_check(result.ok and server.registry.defs.size() == before_blocks and server._commands.has("spawn") and server.tutorials.tutorials.has("vanilla:survival"),
		"vanilla reloads without new ids, keeping its commands and tutorial: %s" % str(result.notes.slice(0, 3)))
	server.queue_free()
	await get_tree().process_frame


func _semver() -> void:
	var S = preload("res://engine/shared/semver.gd")
	_check(S.compare("1.2.10", "1.2.9") == 1 and S.compare("1.0.0-beta", "1.0.0") == -1 and S.compare("2.0.0", "2.0.0") == 0, "versions compare numerically, pre-releases first")
	var cases := [["1.4.2", "^1.2", true], ["2.0.0", "^1.2", false], ["0.3.1", "^0.3.0", true], ["0.4.0", "^0.3.0", false],
		["1.2.9", "~1.2.3", true], ["1.3.0", "~1.2.3", false], ["1.5.0", ">=1.2 <2", true], ["2.1.0", ">=1.2 <2", false],
		["2.5.0", "^1.0 || ^2.0", true], ["1.7.3", "1.x", true], ["1.7.3", "1.6.x", false], ["3.0.0", "*", true], ["1.2.3", "1.2.3", true], ["1.2.4", "=1.2.3", false]]
	var wrong := cases.filter(func(c): return S.satisfies(c[0], c[1]) != c[2])
	_check(wrong.is_empty(), "version ranges (^, ~, comparisons, ||, x): %s" % str(wrong))
	_check(S.range_error(">=1.0 <two") != "" and S.range_error("^1.2 || ~2.0") == "" and not S.is_valid("1.2") and S.is_valid("1.2.3-rc.1"),
		"bad ranges and versions are recognized")


func _write_mod(dir: String, manifest: Dictionary, main := "extends \"res://engine/server/mod.gd\"\n\nfunc setup(_api) -> void:\n\tpass\n") -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	f = FileAccess.open(dir.path_join("main.gd"), FileAccess.WRITE)
	f.store_string(main)
	f.close()


func _mod_packages() -> void:
	var Loader = preload("res://engine/server/mod_loader.gd")
	var root := DATA_DIR.path_join("packages_%d" % Time.get_ticks_msec())
	var mods := root.path_join("mods")
	_write_mod(mods.path_join("lib"), {"id": "lib", "version": "1.4.0", "engine": "^1.0"})
	_write_mod(mods.path_join("needs_new"), {"id": "needs_new", "version": "1.0.0", "depends": ["lib@^2.0"]})
	_write_mod(mods.path_join("needs_ok"), {"id": "needs_ok", "version": "1.0.0", "depends": {"lib": ">=1.2 <2"}, "optional_depends": ["extra", "absent"]})
	_write_mod(mods.path_join("extra"), {"id": "extra", "version": "0.1.0"})
	_write_mod(mods.path_join("rival"), {"id": "rival", "version": "1.0.0", "conflicts": ["lib@<2"]})
	_write_mod(mods.path_join("future"), {"id": "future", "version": "1.0.0", "engine": "^9.0"})
	var available: Dictionary = Loader.discover(PackedStringArray([mods]))
	_check(Loader.resolve(PackedStringArray(["needs_new"]), available).is_empty() and Loader.last_errors[0].message.contains("needs lib ^2.0, but lib 1.4.0 is installed"),
		"a dependency outside the version range is refused with a clear message")
	var order: Array = Loader.resolve(PackedStringArray(["needs_ok"]), available)
	_check(order.map(func(m): return m.id) == ["lib", "extra", "needs_ok"], "version ranges pass and installed optional dependencies load first")
	_check(Loader.resolve(PackedStringArray(["lib", "rival"]), available).is_empty() and Loader.last_errors[0].message.contains("conflicts"), "conflicting mods are refused")
	_check(Loader.resolve(PackedStringArray(["future"]), available).is_empty() and Loader.last_errors[0].message.contains("mod API"), "mods for another engine API version are refused")
	# Packages: pack a mod folder, load it from a .zip.
	var src := root.path_join("src/zipped")
	_write_mod(src, {"id": "zipped", "version": "2.1.0", "depends": ["base@^1.0"]},
		"extends \"res://engine/server/mod.gd\"\nconst Helper = preload(\"helper.gd\")\n\nfunc setup(api) -> void:\n\tapi.register_item(\"gem\", {\"display_name\": Helper.NAME, \"icon\": \"gem.png\"})\n")
	var helper := FileAccess.open(src.path_join("helper.gd"), FileAccess.WRITE)
	helper.store_string("extends RefCounted\nconst NAME := \"Zip Gem\"\n")
	helper.close()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.save_png(src.path_join("gem.png"))
	var zip_path := root.path_join("packaged/zipped-2.1.0.zip")
	_check(Loader.pack(src, zip_path) == OK and FileAccess.file_exists(zip_path), "a mod folder packs into a zip")
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["zipped"]), "mod_dirs": PackedStringArray([root.path_join("packaged")]),
		"world": "zip_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 42, "offline": true})
	var gem: int = server.items.id_of("zipped:gem") if err == OK else -1
	_check(err == OK and gem > 0 and server.items.display_name(gem) == "Zip Gem" and server._assets.has("zipped:gem.png") and server._assets["zipped:gem.png"].has("hash"),
		"servers load mods from zip packages, with their scripts and assets")
	server.queue_free()
	await get_tree().process_frame
	# The validator finds typical mistakes.
	var bad := root.path_join("check/sloppy")
	_write_mod(bad, {"id": "sloppy", "version": "1.0", "dependencies": ["base"], "depends": ["base"]},
		"extends \"res://engine/server/mod.gd\"\n\nfunc setup(api) -> void:\n\tapi.register_block(\"crate\", {\"textures\": \"textures/missing.png\", \"drops\": \"sloppy:nothing\"})\n" +
		"\tapi.register_guide_chapter(\"notes\", {\"title\": \"Notes\"})\n" +
		"\tapi.register_guide_page(\"page\", {\"chapter\": \"notes\", \"unlock\": {\"item\": \"sloppy:ghost\"}, \"blocks\": [{\"type\": \"items\", \"items\": [\"base:nope\"]}]})\n")
	var result: Dictionary = preload("res://engine/server/mod_validator.gd").validate(bad, self)
	var text := "\n".join(result.issues.map(func(i): return "%s %s" % [i.level, i.message]))
	var expected := ["unknown key \"dependencies\"", "not a semantic version", "no \"engine\" range", "Asset not found", "drops 'sloppy:nothing'",
		"unlocks with", "shows item 'base:nope'"]
	var missing := expected.filter(func(e): return not text.contains(e))
	_check(not result.ok and missing.is_empty(), "the validator reports manifest, asset and reference mistakes (missing: %s)" % str(missing))
	var clean: Dictionary = preload("res://engine/server/mod_validator.gd").validate(ProjectSettings.globalize_path("res://mods/vanilla"), self)
	_check(clean.ok and clean.counts.warning == 0, "the bundled vanilla mod validates cleanly")


func _mod_templates() -> void:
	var Templates = preload("res://engine/server/mod_templates.gd")
	var root := DATA_DIR.path_join("templates_%d" % Time.get_ticks_msec())
	_check(Templates.id_from_name("My Cool Mod!") == "my_cool_mod" and Templates.id_from_name("3D Stuff") == "mod_3d_stuff", "ids are made from display names")
	_check(not Templates.create(root, {"id": "vanilla"}).ok and not Templates.create(root, {"id": "Bad Id"}).ok, "taken or invalid ids are refused")
	var languages := ["gdscript"]
	if ClassDB.class_exists(&"NativeJsRuntime"):
		languages.append("javascript")
	for language in languages:
		for kind in ["addon", "game"]:
			var id := "t_%s_%s" % [language.left(2), kind]
			var created: Dictionary = Templates.create(root, {"id": id, "name": "Test %s %s" % [language, kind], "language": language, "kind": kind, "author": "Tester"})
			if not created.ok:
				_check(false, "template %s %s: %s" % [language, kind, created.error])
				continue
			var mods := [id] if kind == "game" else ["vanilla", id]
			var server := GameServer.new()
			add_child(server)
			var err: Error = server.start({"mods": PackedStringArray(mods), "mod_dirs": PackedStringArray([root]), "world": "%s_%d" % [id, Time.get_ticks_msec()],
				"data_dir": DATA_DIR, "seed": 42, "offline": true})
			server.dev_log.drain()
			var errors: Array = server.dev_log.sorted_errors().filter(func(e): return e.source == id)
			_check(err == OK and errors.is_empty(), "the %s %s template loads without errors %s" % [language, kind, str(errors.map(func(e): return e.message))])
			if err != OK:
				server.queue_free()
				continue
			server.set_physics_process(false)
			var p := ServerPlayer.new(server, 130, "Maker")
			p.player_id = "maker"
			server.players[130] = p
			var gem: int = server.items.id_of(id + ":gem")
			server._commands[id].handler.call(p, PackedStringArray())
			var crate: int = server.registry.id_of(id + ":crate")
			_check(gem > 0 and crate > 0 and p.inventory.count_of(gem) == 1 and server.recipes.index_of(id + ":crate") >= 0,
				"the %s %s template registers its block, item, recipe and command" % [language, kind])
			_check(not server.guide.registry.get_page(id + ":crates").is_empty() and server.tutorials.tutorials.has(id + ":first_gem"),
				"the %s %s template adds a guide page and a tutorial" % [language, kind])
			if kind == "game":
				_check(server.biome_generator != null and server.generator == server.biome_generator and server.surface_height(8, 8) > 40,
					"the %s game template generates its own world" % language)
			var drops := 0
			for i in 20:
				var before: int = server.entities.entities.size()
				server.emit("block_broken", {"player": p, "position": Vector3i(8, 60, 8), "block": crate, "item": 0, "slot": 0, "harvested": true})
				drops += server.entities.entities.size() - before
			_check(drops > 0, "breaking the %s template's crate drops gems" % language)
			var validation: Dictionary = preload("res://engine/server/mod_validator.gd").check_running(server, id)
			_check(validation.ok and validation.counts.warning == 0, "the %s %s template passes the validator %s" % [language, kind, str(validation.issues.slice(0, 3))])
			server.queue_free()
			await get_tree().process_frame


func _api_docs() -> void:
	var Docs = preload("res://tools/docs_generator.gd")
	var html: String = Docs.build()
	_check(html.contains("api.register_block(") and html.contains("JS registerBlock") and html.contains("player.teleport(") and html.contains("id=\"events\""),
		"the API reference covers the mod API, JavaScript names, players and events")
	_check(FileAccess.get_file_as_string("res://docs/api/index.html") == html,
		"docs/api/index.html is up to date (regenerate: godot --headless --path . res://tools/mod_tool.tscn -- docs)")


func _creations() -> void:
	var C = preload("res://engine/shared/creations.gd")
	var Library = preload("res://engine/client/creation_library.gd")
	var skin := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	skin.fill(Color(0.2, 0.4, 0.8))
	var png := skin.save_png_to_buffer()
	var m: Dictionary = C.make("skin", "skin", png, "Blue Suit", "author1", "Ada")
	var checked: Dictionary = C.validate(m, png)
	_check(checked.ok and C.is_id(m.id) and m.id == C.content_id("skin", "skin", png), "a skin creation validates with a content id")
	var renamed := m.duplicate()
	renamed.name = "Navy Suit"
	_check(C.validate(renamed, png).manifest.id == m.id, "renaming keeps the id (it depends only on the content)")
	var small := Image.create(32, 32, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	_check(C.validate(C.make("skin", "skin", small, "Tiny"), small).error.contains("64x64"), "skins must be 64x64")
	_check(C.validate(m, Image.create(64, 64, false, Image.FORMAT_RGB8).save_png_to_buffer()).error.contains("id does not match"), "a changed payload no longer matches its id")
	var boxes := {"boxes": [{"from": [-4, 0, -4], "size": [8, 3, 8], "color": "#aa3333"}, {"from": [-2, 3, -2], "size": [4, 4, 4], "color": "#222222"}]}
	var box_data := JSON.stringify(boxes).to_utf8_buffer()
	var hat: Dictionary = C.make("accessory", "hat", box_data, "Top Hat", "author1", "Ada")
	_check(C.validate(hat, box_data).ok, "a voxel accessory validates")
	var too_many := {"boxes": []}
	for i in 70:
		too_many.boxes.append({"from": [0, 0, 0], "size": [1, 1, 1], "color": "#ffffff"})
	var many_data := JSON.stringify(too_many).to_utf8_buffer()
	_check(C.validate(C.make("accessory", "hat", many_data, "Heap"), many_data).error.contains("at most"), "accessories have a box limit")
	var far := JSON.stringify({"boxes": [{"from": [0, 90, 0], "size": [1, 1, 1], "color": "#ffffff"}]}).to_utf8_buffer()
	_check(not C.validate(C.make("accessory", "hat", far, "Tower"), far).ok, "accessory boxes stay near the attachment point")
	_check(not C.validate(C.make("accessory", "shirt", box_data, "Wrong"), box_data).ok, "accessories go in accessory categories")
	var glb := FileAccess.get_file_as_bytes("res://mods/base/models/bed_foot.glb")
	var model: Dictionary = C.make("model", "back", glb, "Bed Backpack", "author1", "Ada")
	var model_check: Dictionary = C.validate(model, glb)
	_check(model_check.ok and model_check.info.triangles > 0, "a GLB model validates and is measured (%s)" % model_check.error)
	_check(C.validate(C.make("model", "back", png, "Fake"), png).error.contains("GLB"), "non-GLB models are refused")
	var reg = preload("res://engine/shared/cosmetics.gd").new()
	var hat_def: Dictionary = C.to_cosmetic(hat, box_data)
	_check(reg.register(hat_def) == hat.id and reg.get_def(hat.id).boxes.size() == 2 and reg.get_def(hat.id).category == "hat", "creations become cosmetic definitions")
	_check(reg.register(C.to_cosmetic(m, png)) == m.id and reg.get_def(m.id).texture == m.id + ".png" and reg.category("skin").name == "skin",
		"a skin becomes a texture layer in the skin category")
	# The local library.
	var dir := ProjectSettings.globalize_path(DATA_DIR.path_join("creations_%d" % Time.get_ticks_msec()))
	OS.set_environment("VOXEL_CREATIONS_DIR", dir)
	_check(Library.save(m, png).ok and Library.save(hat, box_data).ok and not Library.save(C.make("skin", "skin", small, "Tiny"), small).ok,
		"the library saves valid creations only")
	_check(Library.list().size() == 2 and Library.get_payload(m.id) == png, "the library lists creations and returns their files")
	_check(Library.update(m.id, {"name": "Navy Suit"}) and Library.get_manifest(m.id).name == "Navy Suit", "creations can be renamed")
	Library.remove(hat.id)
	_check(Library.list().size() == 1, "creations can be deleted")
	OS.set_environment("VOXEL_CREATIONS_DIR", "")


func _skin_painter() -> void:
	var Painter = preload("res://engine/client/avatar/skin_painter.gd")
	var dir := ProjectSettings.globalize_path(DATA_DIR.path_join("painter_%d" % Time.get_ticks_msec()))
	OS.set_environment("VOXEL_CREATIONS_DIR", dir)
	var start := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	start.fill(Color(0.5, 0.5, 0.5))
	var painter = Painter.new()
	painter.setup(preload("res://engine/shared/player_rig.gd").default_rig(), start, "Test Skin", "author1", "Ada")
	add_child(painter)
	await get_tree().process_frame
	var front: Dictionary = painter._faces.filter(func(f): return f.region == "head" and f.side == "front")[0]
	var r: Rect2i = front.rect
	painter.set_color(Color.RED)
	painter.mirror = true
	painter.apply_tool(r.position)
	painter.end_stroke()
	var mirrored := Vector2i(r.end.x - 1, r.position.y)
	_check(painter.image.get_pixelv(r.position) == Color.RED and painter.image.get_pixelv(mirrored) == Color.RED, "mirrored painting paints both halves of a face")
	painter.mirror = false
	painter.set_tool("fill")
	painter.set_color(Color.BLUE)
	painter.apply_tool(r.position + Vector2i(2, 2))
	painter.end_stroke()
	var outside: Vector2i = painter._faces.filter(func(f): return f.region == "head" and f.side == "back")[0].rect.position
	_check(painter.image.get_pixelv(r.position + Vector2i(3, 3)) == Color.BLUE and painter.image.get_pixelv(r.position) == Color.RED
		and painter.image.get_pixelv(outside) != Color.BLUE, "fill stays on one face and stops at other colors")
	var overlay: Vector2i = painter._faces.filter(func(f): return f.overlay)[0].rect.position
	painter.set_tool("pencil")
	painter.apply_tool(overlay)
	painter.end_stroke()
	_check(painter.image.get_pixelv(overlay) != Color.BLUE, "the body layer does not paint the outer layer")
	painter.set_layer("overlay")
	painter.set_tool("eraser")
	painter.apply_tool(overlay)
	painter.end_stroke()
	_check(painter.image.get_pixelv(overlay).a == 0.0, "the eraser clears outer-layer pixels")
	painter.undo()
	_check(painter.image.get_pixelv(overlay).a > 0.0, "undo restores the last stroke")
	painter.redo()
	_check(painter.image.get_pixelv(overlay).a == 0.0, "redo repeats it")
	painter.set_tool("picker")
	painter.apply_tool(r.position)
	_check(painter.color == Color.RED, "the picker takes a color from the skin")
	_check(painter.load_png(Image.create(16, 16, false, Image.FORMAT_RGBA8).save_png_to_buffer()).contains("64x64"), "importing checks the size")
	var result: Dictionary = painter.save()
	_check(result.ok and preload("res://engine/client/creation_library.gd").get_manifest(result.manifest.id).name == "Test Skin", "saving puts the skin in the library")
	painter.queue_free()
	OS.set_environment("VOXEL_CREATIONS_DIR", "")
	await get_tree().process_frame


func _accessory_tools() -> void:
	var Builder = preload("res://engine/client/avatar/accessory_builder.gd")
	var Importer = preload("res://engine/client/avatar/model_importer.gd")
	var Cos = preload("res://engine/shared/cosmetics.gd")
	var Looks = preload("res://engine/client/avatar/look_builder.gd")
	var Library = preload("res://engine/client/creation_library.gd")
	var dir := ProjectSettings.globalize_path(DATA_DIR.path_join("accessories_%d" % Time.get_ticks_msec()))
	OS.set_environment("VOXEL_CREATIONS_DIR", dir)
	var registry = Cos.new()
	var looks = Looks.new(registry, {}, Library.read_model)
	var rig: Dictionary = preload("res://engine/shared/player_rig.gd").default_rig()
	var builder = Builder.new()
	builder.setup(registry, looks, rig, Cos.default_avatar("Maker"), "Maker", {"category": "hat", "author": "author1"})
	add_child(builder)
	await get_tree().process_frame
	builder.set_color("#222222")
	for x in range(-6, 6):
		for z in range(-6, 6):
			builder.apply_at(Vector2i(x, z))
	builder.end_stroke()
	builder.set_layer(1)
	builder.copy_layer_below()
	_check(builder.voxels.size() == 288 and builder.build_boxes().size() == 1, "voxels of one color merge into a single box")
	builder.set_color("#cc2222")
	builder.mirror = true
	builder.apply_at(Vector2i(2, -6))
	builder.end_stroke()
	_check(builder.voxels[Vector3i(2, 1, -6)] == "#cc2222" and builder.voxels[Vector3i(-3, 1, -6)] == "#cc2222", "mirroring places the other side too")
	var boxes: Array = builder.build_boxes()
	var count := 0
	for b in boxes:
		count += int(b.size[0]) * int(b.size[1]) * int(b.size[2])
	_check(count == builder.voxels.size(), "merged boxes cover exactly the voxels")
	builder.undo()
	_check(builder.voxels[Vector3i(2, 1, -6)] == "#222222", "undo works in the builder")
	var copy = Builder.new()
	copy.load_boxes(boxes)
	_check(copy.voxels.size() == count, "saved boxes load back into voxels for editing")
	builder._name_edit.text = "Flat Cap"
	var saved: Dictionary = builder.save()
	_check(saved.ok and Library.get_manifest(saved.manifest.id).category == "hat" and not registry.defs.has("preview:accessory"), "the builder saves an accessory to the library")
	builder.queue_free()
	var importer = Importer.new()
	importer.setup(registry, looks, rig, Cos.default_avatar("Maker"), "Maker", FileAccess.get_file_as_bytes("res://mods/industry/models/battery.glb"), {"category": "back"})
	_check(importer.error.contains("512"), "the model importer refuses oversized textures before saving")
	importer.free()
	importer = Importer.new()
	importer.setup(registry, looks, rig, Cos.default_avatar("Maker"), "Maker", FileAccess.get_file_as_bytes("res://mods/base/models/bed_foot.glb"), {"category": "back"})
	add_child(importer)
	await get_tree().process_frame
	importer.transform.scale = 0.4
	importer._name_edit.text = "Bedroll"
	var model: Dictionary = importer.save()
	_check(model.ok and Library.get_manifest(model.manifest.id).model_transform.scale == 0.4, "the model importer saves a model with its placement")
	importer.queue_free()
	await get_tree().process_frame
	_check(looks.read_model == Library.read_model or looks.read_model.is_valid(), "the look builder gets its model reader back")
	OS.set_environment("VOXEL_CREATIONS_DIR", "")


func _ugc_server() -> void:
	var C = preload("res://engine/shared/creations.gd")
	var server = _start("ugc_%d" % Time.get_ticks_msec())
	var ugc = server.ugc
	var author := ServerPlayer.new(server, 140, "Artist")
	author.player_id = "artist_id"
	server.players[140] = author
	var other := ServerPlayer.new(server, 141, "Fan")
	other.player_id = "fan_id"
	server.players[141] = other
	var skin := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	skin.fill(Color(0.1, 0.7, 0.2))
	var png := skin.save_png_to_buffer()
	var m: Dictionary = C.make("skin", "skin", png, "Green", "artist_id", "Artist")
	# Only authors bring creations.
	_check(ugc.offer(other, [m]).status[m.id][0] == "refused", "only the author can upload a creation")
	var answer: Dictionary = ugc.offer(author, [m])
	_check(answer.request == [m.id], "the server asks the author for a creation it does not have")
	var half := png.size() / 2
	ugc.upload_piece(author, m.id, 0, png.size(), png.slice(0, half))
	_check(not ugc.store.has(m.id), "a creation is stored only when complete")
	ugc.upload_piece(author, m.id, half, png.size(), png.slice(half))
	_check(ugc.is_approved(m.id) and FileAccess.file_exists(ugc._payload_path(m.id)), "with accept auto an upload is approved and stored")
	# Wearing it: the author, and others through the library.
	var worn := {"wear": {"skin": {"id": m.id, "color": "#ffffff"}}}
	server._set_client_avatar(author, worn, false)
	_check(author.avatar.get("wear", {}).get("skin", {}).get("id", "") == m.id, "the author wears an approved creation")
	server._set_client_avatar(other, worn, false)
	_check(other.avatar.get("wear", {}).get("skin", {}).get("id", "") == m.id, "others may wear it when the library is on")
	ugc.set_policy({"library": false})
	server._set_client_avatar(other, worn, false)
	_check(other.avatar.get("wear", {}).get("skin", {}).get("id", "") != m.id, "with the library off only the author wears it")
	ugc.set_policy({"library": true})
	_check(ugc.library({"category": "skin"}).items.map(func(x): return x.id) == [m.id], "the server library lists approved creations")
	# Approval mode: pending until approved, then the waiting avatar updates.
	ugc.set_policy({"accept": "approval"})
	var box_data := JSON.stringify({"boxes": [{"from": [-4, 0, -4], "size": [8, 2, 8], "color": "#3355aa"}]}).to_utf8_buffer()
	var cap: Dictionary = C.make("accessory", "hat", box_data, "Blue Cap", "artist_id", "Artist")
	ugc.offer(author, [cap])
	ugc.upload_piece(author, cap.id, 0, box_data.size(), box_data)
	_check(ugc.store[cap.id].status == "pending", "with accept approval uploads wait")
	server._set_client_avatar(author, {"wear": {"hat": {"id": cap.id, "color": "#ffffff"}}}, false)
	_check(author.avatar.get("wear", {}).get("hat", {}).get("id", "") != cap.id, "pending creations are not shown")
	ugc.set_status(cap.id, "approved")
	_check(author.avatar.get("wear", {}).get("hat", {}).get("id", "") == cap.id, "approving puts it on the player who was waiting")
	# Bad content and limits.
	var bad := Image.create(16, 16, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	var fake: Dictionary = C.make("skin", "skin", bad, "Tiny", "artist_id", "Artist")
	var statuses := []
	server.add_handler("ugc_status", func(ev): statuses.append([ev.id, ev.status, ev.reason]), 0)
	ugc.set_policy({"accept": "auto"})
	ugc.offer(author, [fake])
	ugc.upload_piece(author, fake.id, 0, bad.size(), bad)
	_check(not ugc.store.has(fake.id) and statuses.any(func(x): return x[0] == fake.id and x[1] == "refused" and x[2].contains("64x64")), "invalid uploads are refused with the reason")
	ugc.set_policy({"max_per_player": 2})
	var third_data := JSON.stringify({"boxes": [{"from": [0, 0, 0], "size": [1, 1, 1], "color": "#ffffff"}]}).to_utf8_buffer()
	var third: Dictionary = C.make("accessory", "back", third_data, "Dot", "artist_id", "Artist")
	_check(ugc.offer(author, [third]).status.get(third.id, [""])[0] == "refused", "the per-player creation limit applies")
	# Removing blocks the content for good.
	ugc.set_status(m.id, "removed", "not allowed")
	_check(ugc.blocked.has(m.id) and ugc.offer(author, [m]).status[m.id][1].contains("removed") and not other.avatar.get("wear", {}).has("skin"),
		"removed creations are blocked and taken off players")
	# Saved with the world.
	ugc.save_index()
	var again = preload("res://engine/server/ugc.gd").new(server)
	again.load_store(server._save_dir)
	_check(again.store.has(cap.id) and again.blocked.has(m.id) and again.policy.max_per_player == 2, "the creation store and blocklist are saved")
	server.queue_free()
	await get_tree().process_frame


func _ugc_moderation() -> void:
	var C = preload("res://engine/shared/creations.gd")
	var server = _start("ugc_mod_%d" % Time.get_ticks_msec())
	var ugc = server.ugc
	var people := []
	for i in 4:
		var p := ServerPlayer.new(server, 150 + i, ["Artist", "Fan", "Critic", "Admin"][i])
		p.player_id = ["artist_id", "fan_id", "critic_id", "admin_id"][i]
		server.players[150 + i] = p
		server._meta.names[p.name.to_lower()] = p.player_id
		people.append(p)
	var author: ServerPlayer = people[0]
	var admin: ServerPlayer = people[3]
	server._meta.admins.append(admin.player_id)
	admin.edit_tokens = 100.0
	author.edit_tokens = 100.0
	var upload := func(name: String, color: Color) -> String:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(color)
		var png := img.save_png_to_buffer()
		var m: Dictionary = C.make("skin", "skin", png, name, "artist_id", "Artist")
		ugc.offer(author, [m])
		ugc.upload_piece(author, m.id, 0, png.size(), png)
		return m.id
	var id: String = upload.call("Red", Color(0.8, 0.1, 0.1))
	var reported := []
	server.add_handler("ugc_reported", func(ev): reported.append([ev.player.name, ev.reason, ev.reports]), 0)
	# Reports: once per player, never your own, unknown reasons become "other".
	ugc.set_policy({"report_hide": 2})
	_check(ugc.report(author, id, "spam").contains("your own"), "players cannot report their own creations")
	_check(ugc.report(people[1], id, "whatever", "rude words") == "" and ugc.store[id].reports[0].reason == "other", "a report is stored, unknown reasons become other")
	_check(ugc.report(people[1], id, "spam") != "" and ugc.store[id].reports.size() == 1, "a player reports a creation only once")
	_check(ugc.report(people[1], "ugc:" + "0".repeat(24), "spam") != "", "unknown creations cannot be reported")
	_check(ugc.review_list("reported").map(func(x): return x.id) == [id] and ugc.is_approved(id), "reported creations are listed and stay up under the threshold")
	ugc.report(people[2], id, "offensive")
	_check(ugc.store[id].status == "pending" and reported.size() == 2 and reported[1] == ["Critic", "offensive", 2], "enough reports hide a creation until reviewed")
	_check(ugc.review_list("pending").size() == 1 and ugc.review_list("approved").is_empty() and ugc.review_list("all", "red").size() == 1
		and ugc.review_list("all", "blue").is_empty(), "review filters and search")
	# Mods can veto a report.
	var id2: String = upload.call("Blue", Color(0.1, 0.1, 0.8))
	server.add_handler("ugc_reported", func(ev): ev.cancelled = ev.reason == "copied", 1)
	ugc.report(people[1], id2, "copied")
	_check(not ugc.store[id2].has("reports") or ugc.store[id2].reports.is_empty(), "a mod handler can cancel a report")
	# Commands, admins only.
	_check(ugc.resolve_id(id.substr(4, 6)) == id and ugc.resolve_id("ugc:") == "" and ugc.resolve_id("zzzz") == "", "ids resolve from a unique prefix")
	server.on_chat(author.peer_id, "/ugc approve %s" % id.substr(4, 8))
	_check(ugc.store[id].status == "pending", "only admins may moderate creations")
	server.on_chat(admin.peer_id, "/ugc approve %s" % id.substr(4, 8))
	_check(ugc.store[id].status == "approved" and ugc.store[id].reports.is_empty(), "approving clears reports")
	server.on_chat(admin.peer_id, "/ugc reject %s looks like someone else's" % id.substr(4, 8))
	_check(ugc.store[id].status == "rejected" and ugc.store[id].reason == "looks like someone else's", "rejecting keeps the reason")
	# Trust skips the queue; banning hides everything and stops uploads.
	ugc.set_policy({"accept": "trusted"})
	var id3: String = upload.call("Green", Color(0.1, 0.8, 0.1))
	_check(ugc.store[id3].status == "pending", "with accept trusted, unknown creators wait")
	server.on_chat(admin.peer_id, "/ugc trust Artist")
	var id4: String = upload.call("Yellow", Color(0.8, 0.8, 0.1))
	_check(ugc.store[id4].status == "approved", "trusted creators skip the queue")
	server.on_chat(admin.peer_id, "/ugc ban Artist stolen art")
	_check([id2, id3, id4].all(func(x): return ugc.store[x].status == "rejected") and ugc.review_list("all")[0].author_banned, "banning a creator hides their creations")
	var id5: String = upload.call("Black", Color(0.05, 0.05, 0.05))
	_check(not ugc.store.has(id5), "banned creators cannot upload")
	server.on_chat(admin.peer_id, "/ugc unban Artist")
	_check(not ugc.banned_creators.has("artist_id") and ugc.store[id4].status == "rejected", "unbanning does not bring creations back by itself")
	server.on_chat(admin.peer_id, "/ugc policy report_hide 5")
	_check(ugc.policy.report_hide == 5, "/ugc policy sets values")
	# The mod API.
	var api = preload("res://engine/server/mod_api.gd").new(server, {"id": "tester", "dir": "res://tests"})
	api.ugc_set_status(id4, "approve")
	_check(ugc.is_approved(id4) and api.ugc_list("approved").size() == 1 and api.ugc_get(id4).manifest.name == "Yellow", "mods moderate through the API")
	ugc.save_index()
	var again = preload("res://engine/server/ugc.gd").new(server)
	again.load_store(server._save_dir)
	_check(again.trusted.has("artist_id") and again.store[id].reason == "looks like someone else's", "moderation state is saved")
	server.queue_free()
	await get_tree().process_frame


func _menu_data() -> void:
	var WorldList = preload("res://engine/client/menu/world_list.gd")
	var ServerBook = preload("res://engine/client/menu/server_book.gd")
	var InviteCode = preload("res://engine/shared/invite_code.gd")
	var root := DATA_DIR.path_join("menu_worlds_%d" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(root.path_join("backups"))
	var a: String = WorldList.create("Sunny Meadows!", ["vanilla", "arcana"], 42, root)
	var b: String = WorldList.create("Sunny Meadows!", ["skyblock"], -1, root)
	_check(a == "sunny_meadows" and b == "sunny_meadows_2", "world ids come from titles and stay unique (%s, %s)" % [a, b])
	var listed: Array = WorldList.list(root)
	_check(listed.size() == 2 and listed.any(func(w): return w.id == a and w.title == "Sunny Meadows!" and w.game == "vanilla" and w.mods == ["vanilla", "arcana"] and w.seed == 42),
		"the world list reads titles, games and mods (backups are not worlds)")
	_check(WorldList.rename(a, "Meadows", root) and WorldList.read_meta(root.path_join(a)).title == "Meadows", "worlds can be renamed")
	_check(not WorldList.delete("../" + a, root) and not WorldList.delete("backups", root) and WorldList.delete(b, root) and WorldList.list(root).size() == 1,
		"deleting refuses odd names and removes the world")
	_check(WorldList.describe_time(int(Time.get_unix_time_from_system()) - 7200) == "2 hours ago" and WorldList.describe_time(0) == "never", "play times read naturally")
	# Saved servers.
	OS.set_environment("VOXEL_SERVER_BOOK", root.path_join("servers.json"))
	var book = ServerBook.load_book()
	book.add_favorite("Home", "example.org", 24565)
	book.add_favorite("Home renamed", "Example.org", 24565)
	book.add_favorite("", "10.0.0.2", 25000)
	for i in 15:
		book.note_joined("S%d" % i, "10.1.0.%d" % i, 24565)
	book.note_joined("S3 again", "10.1.0.3", 24565)
	var again = ServerBook.load_book()
	_check(again.favorites.size() == 2 and again.favorites[0].name == "Home renamed" and again.favorites[1].name == "10.0.0.2", "favorites update in place and are saved")
	_check(again.recent.size() == ServerBook.MAX_RECENT and again.recent[0].name == "S3 again" and again.recent.filter(func(e): return e.address == "10.1.0.3").size() == 1,
		"recent servers keep the latest joins without repeats")
	again.move_favorite("10.0.0.2", 25000, -1)
	_check(ServerBook.load_book().favorites[0].address == "10.0.0.2", "favorites can be reordered")
	OS.set_environment("VOXEL_SERVER_BOOK", "")
	# Invite codes.
	var code: String = InviteCode.encode("192.168.1.42", 24565)
	var parsed: Dictionary = InviteCode.parse(code.to_lower().replace("-", " "))
	_check(code.begins_with("VC-") and code.length() == 16 and parsed.address == "192.168.1.42" and parsed.port == 24565, "invite codes round-trip (%s)" % code)
	var typo := code.substr(0, 4) + ("A" if code[4] != "A" else "B") + code.substr(5)
	_check(InviteCode.parse(typo).has("error"), "a mistyped invite code is caught")
	_check(InviteCode.parse("play.example.com:25000") == {"address": "play.example.com", "port": 25000} and InviteCode.parse("[::1]:24570") == {"address": "::1", "port": 24570}
		and InviteCode.parse("host:abc").has("error") and InviteCode.share_text("play.example.com", 24565) == "play.example.com", "plain addresses work too")


func _status_query() -> void:
	var ServerStatus = preload("res://engine/shared/server_status.gd")
	var ServerPinger = preload("res://engine/client/menu/server_pinger.gd")
	var nonce := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	_check(ServerStatus.make_request(nonce).size() == ServerStatus.REQUEST_SIZE and ServerStatus.parse_request(ServerStatus.make_request(nonce)) == nonce
		and ServerStatus.parse_request(PackedByteArray([86, 88, 81, 49])).is_empty(), "status requests are fixed-size and checked")
	var big := ServerStatus.make_response(nonce, {"name": "x".repeat(2000), "motd": "y".repeat(2000)})
	_check(big.size() <= ServerStatus.RESPONSE_MAX, "status answers stay small")
	var server = _start("status_%d" % Time.get_ticks_msec())
	server.server_info.name = "Status Test"
	server.server_info.motd = "hello"
	var port := 26100 + randi() % 200
	_check(server.status_query.start(port + 1) == OK, "the status responder listens")
	var pinger = ServerPinger.new()
	var answers := {}
	pinger.result.connect(func(k, e): answers[k] = e)
	pinger.ping("live", "127.0.0.1", port)
	pinger.ping("dead", "127.0.0.1", port + 50)
	var deadline := Time.get_ticks_msec() + 4000
	while answers.size() < 2 and Time.get_ticks_msec() < deadline:
		server.status_query.update()
		pinger.update()
		await get_tree().process_frame
	var live: Dictionary = answers.get("live", {})
	_check(live.get("online", false) and live.info.name == "Status Test" and live.info.motd == "hello" and live.info.game == "vanilla"
		and live.info.compatible and live.info.max_players == server.max_players, "a server answers status queries with its name, game and players")
	_check(answers.has("dead") and not answers.dead.online, "a server that does not answer shows as offline")
	# Rate limit: many queries from one address within a second get only a few answers.
	var flood := PacketPeerUDP.new()
	flood.bind(0)
	flood.set_dest_address("127.0.0.1", port + 1)
	for i in 30:
		flood.put_packet(ServerStatus.make_request(nonce))
	await get_tree().process_frame
	server.status_query.update()
	await get_tree().process_frame
	_check(flood.get_available_packet_count() <= server.status_query.PER_ADDRESS_PER_SECOND, "status answers are rate limited per address")
	flood.close()
	pinger.close()
	server.status_query.stop()
	server.queue_free()
	await get_tree().process_frame


func _client_settings() -> void:
	var ClientSettings = preload("res://engine/client/settings/client_settings.gd")
	var path := DATA_DIR.path_join("settings_%d.cfg" % Time.get_ticks_msec())
	OS.set_environment("VOXEL_SETTINGS", path)
	var graphics_env := OS.get_environment("VOXEL_GRAPHICS")
	OS.set_environment("VOXEL_GRAPHICS", "")
	var settings = ClientSettings.new()
	settings.load_file()
	var changes := []
	settings.changed.connect(func(k): changes.append(k))
	_check(settings.get_value("graphics/preset") == "balanced" and settings.get_value("graphics/bloom") == true and settings.get_value("graphics/fov") == 75.0,
		"settings start at their defaults")
	settings.set_value("graphics/preset", "fast")
	_check(settings.get_value("graphics/bloom") == false and settings.get_value("graphics/render_scale") == 0.7, "graphics toggles follow the preset")
	settings.set_value("graphics/bloom", true)
	_check(settings.get_value("graphics/preset") == "custom" and settings.get_value("graphics/bloom") == true and settings.get_value("graphics/sway") == false
		and changes.has("graphics/preset"), "changing one toggle switches to custom, starting from the preset")
	settings.set_value("graphics/fov", 500)
	settings.set_value("graphics/max_fps", 60.0)
	settings.set_value("graphics/window_mode", "tiny")
	settings.set_value("controls/invert_y", true)
	_check(settings.get_value("graphics/fov") == 110.0 and settings.get_value("graphics/max_fps") == 60 and settings.get_value("graphics/window_mode") == "windowed",
		"values are clamped to the schema")
	# Bindings.
	settings.set_events("jump", ["key:J", "mouse:4"])
	_check(InputMap.action_get_events("jump").size() == 2 and (InputMap.action_get_events("jump")[0] as InputEventKey).physical_keycode == KEY_J
		and settings.action_using("key:J") == "jump" and settings.action_using("key:J", "jump") == "", "rebinding updates the input map")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F6
	_check(ClientSettings.descriptor_of(key) == "key:F6" and ClientSettings.event_from("key:F6").physical_keycode == KEY_F6
		and ClientSettings.describe("mouse:2") == "Right mouse" and ClientSettings.event_from("key:NotAKey") == null, "key descriptors round-trip")
	var again = ClientSettings.new()
	again.load_file()
	_check(again.get_value("graphics/preset") == "custom" and again.get_value("controls/invert_y") == true and again.events("jump") == ["key:J", "mouse:4"],
		"settings and bindings are saved")
	again.reset_tab("Controls")
	_check(again.get_value("controls/invert_y") == false and again.events("jump") == ["key:Space"]
		and (InputMap.action_get_events("jump")[0] as InputEventKey).physical_keycode == KEY_SPACE, "resetting a tab restores its defaults and keys")
	_check(again.get_value("graphics/preset") == "custom", "resetting one tab leaves the others")
	OS.set_environment("VOXEL_SETTINGS", "")
	OS.set_environment("VOXEL_GRAPHICS", graphics_env)


func _js_blocks() -> void:
	if not ClassDB.class_exists(&"NativeJsRuntime"):
		return  # JavaScript mods need the native extension
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["js_blocks"]), "mod_dirs": PackedStringArray(["res://tests/mods"]),
		"world": "js_blocks_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 42, "offline": true})
	_check(err == OK, "JavaScript block test mod loaded")
	if err != OK:
		server.queue_free()
		return
	server.set_physics_process(false)
	server.gameplay.recipe_discovery = false
	var p := ServerPlayer.new(server, 82, "Scripter")
	p.player_id = "scripter"
	server.players[82] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	var crate_pos := Vector3i(9, y + 1, 8)
	server.set_block_authoritative(crate_pos, server.registry.id_of("js_blocks:crate"))
	var gravel: int = server.items.id_of("base:gravel")
	_check(server.get_fuel(gravel) == 7.0 and server.get_process("pressing", gravel).count == 2, "JavaScript set fuel and processing recipes")
	_check(server.containers.open(p, crate_pos), "a JavaScript container opens")
	p.inventory.set_slot(0, gravel, 3)
	server.on_inventory_click(82, 0, 1, true)
	var crate = server.containers.get_container(crate_pos)
	_check(crate.get_item(4).item == gravel, "shift-click sends fuel to the JavaScript fuel slot")
	_check(crate.state.get("filled") == 1 and is_equal_approx(crate.get_progress("fill"), 0.2) and crate.state.press.count == 2,
		"container_changed ran in JavaScript (%s)" % crate.state)
	server.block_ticks._call(crate_pos, 3, "random", {})
	crate = server.containers.get_container(crate_pos)
	_check(crate.get_item(0).item == server.items.id_of("base:coal") and crate.get_item(0).count == 3 and crate.state.reason == "random"
		and crate.state.fuel == 7.0, "a JavaScript block tick filled the crate (%s)" % crate.state)
	var stick_recipe: Dictionary = server.recipes.recipes.filter(func(r): return r.station == "workbench")[0]
	p.inventory.set_slot(1, server.items.id_of("base:planks"), 2)
	_check(not server._can_craft(p, stick_recipe), "a JavaScript station recipe needs its station")
	var bench := Vector3i(8, y + 1, 10)
	server.set_block_authoritative(bench, server.registry.id_of("js_blocks:workbench"))
	server.set_block_authoritative(bench + Vector3i(1, 0, 0), server.registry.id_of("base:glass"))
	server.on_interact(82, bench)
	_check(p.crafting_station.get("features", []).has("polish") and server._can_craft(p, stick_recipe), "a JavaScript workshop upgrade unlocks its recipe")
	server.queue_free()
	await get_tree().process_frame


func _start(world: String, mods := ["vanilla"]):
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(mods), "world": world, "data_dir": DATA_DIR, "seed": 42, "offline": true})
	if err != OK:
		_check(false, "server start: %s" % error_string(err))
	server.set_physics_process(false)  # the test drives ticks itself
	server.gameplay.recipe_discovery = false  # tests of crafting rules do not need to discover recipes first
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
