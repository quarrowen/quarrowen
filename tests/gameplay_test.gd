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
