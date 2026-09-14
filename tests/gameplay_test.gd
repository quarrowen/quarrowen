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
	await _spawning()
	await _animals()
	await _taming()
	await _js_blocks()
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
			for dy in range(-1, 4):
				var edge: bool = dy == -1 or dy == 3 or x == 0 or x == 39 or z == 0 or z == 11 or x == 20
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
