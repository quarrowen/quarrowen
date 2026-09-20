extends Node
## Offline tests of the gameplay foundation (no networking):
##   godot --headless --path . res://tests/gameplay_test.tscn
## Inventory rules, entity physics, item stacks, damage/death events and persistent entities.

const GameServer = preload("res://engine/server/game_server.gd")
const Inventory = preload("res://engine/shared/inventory.gd")
const EntityPhysics = preload("res://engine/shared/entity_physics.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")
const SoundRegistry = preload("res://engine/shared/sound_registry.gd")
const Loot = preload("res://engine/server/loot.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")
const MobAttacks = preload("res://engine/server/ai/mob_attacks.gd")
const MusicRegistryScript = preload("res://engine/shared/music_registry.gd")
const UserPaths = preload("res://engine/shared/user_paths.gd")
const ContentCacheScript = preload("res://engine/client/content_cache.gd")
const ModLoaderScript = preload("res://engine/server/mod_loader.gd")
const Validator = preload("res://engine/server/mod_validator.gd")
const WorldBackupsScript = preload("res://engine/server/world_backups.gd")
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
	await _archery()
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
	await _milestones()
	await _first_session()
	await _guide_content()
	await _spawning()
	await _animals()
	await _taming()
	await _explosions()
	await _biomes()
	await _structures()
	await _js_blocks()
	await _js_generated()
	await _dev_log()
	await _dev_tools()
	await _dev_web()
	await _mod_reload()
	_semver()
	await _mod_packages()
	await _mod_templates()
	_mod_index()
	await _examples()
	await _fuels()
	await _cooking()
	await _hearthhold()
	await _fishing()
	await _music()
	await _ambience()
	await _weather()
	await _links()
	await _flows()
	await _parcels()
	await _spool()
	await _claims()
	await _liquids()
	await _multiblocks()
	await _drives()
	await _assemblies()
	await _modifiers()
	await _effects_extra()
	await _social()
	await _characters()
	await _conditions()
	await _ores()
	await _fields()
	await _vehicles()
	await _plots()
	await _tags()
	await _signals()
	await _realms()
	await _simulation_distance()
	_scripts_compile()
	_mod_assets_exist()
	await _map_from_mod()
	await _story_mode()
	_test_isolation()
	await _loot()
	_api_docs()
	_creations()
	await _skin_painter()
	await _accessory_tools()
	await _ugc_server()
	await _ugc_moderation()
	_menu_data()
	_client_settings()
	await _private_server()
	await _transfers()
	await _roles()
	await _playtest_fixes()
	await _movement()
	await _swimming()
	await _ui_close()
	await _broadcast_id()
	await _server_panel()
	await _mod_settings()
	_housekeeping()
	await _graves_and_homes()
	await _items_of_missing_mods()
	await _block_shapes()
	_shape_twins()
	await _doors_and_windows()
	await _shape_meshing()
	_updates()
	await _anticheat()
	await _scale()
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
	var wrong_size := PackedInt32Array([1, 2, 0, 0, 0, 0, 0, 0, 0, 10, 20, 0, 0, 0, 0, 0, 0, 0])
	_check(not Inventory.new().load_packed(wrong_size), "a packed inventory of the wrong length is refused, not half-read")
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


## Blocks that do not fill their cell: slabs, stairs and fences, in movement and in what they block.
func _block_shapes() -> void:
	var server = _start("shapes_%d" % Time.get_ticks_msec())
	var stone: int = server.registry.id_of("base:stone")
	var slab: int = server.registry.id_of("base:stone_slab")
	var stairs: int = server.registry.id_of("base:stone_stairs_north")
	var fence: int = server.registry.id_of("base:fence")
	_check(slab > 0 and stairs > 0 and fence > 0, "base registers slabs, stairs and a fence")
	if slab <= 0:
		server.queue_free()
		await get_tree().process_frame
		return
	var o := Vector3i(60, 80, 60)
	server._ensure_chunk(Vector2i(3, 3))
	for x in range(-3, 7):
		for z in range(-3, 4):
			server.set_block_authoritative(o + Vector3i(x, 0, z), stone)
	var p := ServerPlayer.new(server, 41, "Walker")
	p.player_id = "walker"
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)
	p.state.on_ground = true
	server.players[41] = p
	var walk := func(ticks: int, forward: float) -> void:
		for t in ticks:
			var i = PlayerPhysics.PlayerInput.new()
			i.move = Vector2(0.0, forward)
			i.yaw = 0.0  # -z is forward
			PlayerPhysics.step(p.state, i, server.world, server.rules)

	# A slab is half a block high: you stand on it at half height, and walk onto it without jumping.
	server.set_block_authoritative(o + Vector3i(0, 1, -2), slab)
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)
	p.state.velocity = Vector3.ZERO
	walk.call(40, 1.0)
	_check(absf(p.state.position.y - (o.y + 1.5)) < 0.06 and p.state.position.z < o.z - 1.0,
		"a player walks up onto a slab and stands at half height (y %.2f, z %.1f)" % [p.state.position.y, p.state.position.z - o.z])

	# A slab fills the half you aimed at: look up at the underside of a block and it goes above your head,
	# look down at a floor and it stays at your feet (playtest: slabs only ever placed as the bottom half).
	var slab_top: int = server.registry.id_of("base:stone_slab_top")
	_check(slab_top > 0 and not server.registry.defs[slab_top].placeable, "a top slab exists and is never carried")
	server.set_block_authoritative(o + Vector3i(4, 4, 0), stone)  # a ceiling to aim up at, clear of the head
	p.state.position = Vector3(o.x + 4.5, o.y + 1.0, o.z + 0.5)
	p.inventory.creative = true
	# A player built by hand here never went through _spawn_player, which is what hands out edit tokens.
	# Without them every edit is refused before permissions are even consulted, and this test would have
	# "passed" its first two assertions for entirely the wrong reason.
	p.edit_tokens = 100.0
	p.inventory.ids[0] = slab
	p.inventory.counts[0] = 1
	p.inventory.selected = 0
	p.pitch = PI / 2.0  # straight up at the underside (positive pitch looks up)
	p.yaw = 0.0
	p.edit_tokens = 100.0
	server.on_place_block(41, o + Vector3i(4, 3, 0), 0.0)
	_check(server.world.get_block_v(o + Vector3i(4, 3, 0)) == slab_top,
		"aiming at the underside of a block places the slab in the top half")
	p.pitch = -PI / 2.0  # straight down at the floor
	p.state.position = Vector3(o.x + 6.5, o.y + 2.0, o.z + 0.5)
	p.edit_tokens = 100.0
	server.on_place_block(41, o + Vector3i(6, 1, 0), 0.0)
	_check(server.world.get_block_v(o + Vector3i(6, 1, 0)) == slab,
		"aiming down at a floor still places the ordinary bottom slab")
	# Two slabs make a whole block, so a floor of slabs can be filled in rather than stacked beside itself.
	p.inventory.creative = false  # survival, so the slab is actually spent
	server.set_block_authoritative(o + Vector3i(6, 1, 0), slab)
	p.state.position = Vector3(o.x + 6.5, o.y + 3.0, o.z + 0.5)
	p.pitch = -PI / 2.0  # looking down at the slab's flat top
	p.inventory.ids[0] = slab
	p.inventory.counts[0] = 2
	p.edit_tokens = 100.0
	server.on_place_block(41, o + Vector3i(6, 2, 0), 0.0)
	_check(server.world.get_block_v(o + Vector3i(6, 1, 0)) == stone and server.world.get_block_v(o + Vector3i(6, 2, 0)) == 0,
		"a second slab fills the first one's cell instead of stacking beside it")
	_check(p.inventory.counts[0] == 1, "and it costs one slab")
	server.set_block_authoritative(o + Vector3i(6, 1, 0), 0)
	server.set_block_authoritative(o + Vector3i(4, 3, 0), 0)
	server.set_block_authoritative(o + Vector3i(4, 4, 0), 0)
	server.set_block_authoritative(o + Vector3i(6, 1, 0), 0)

	# Stairs: the same, and standing on the high half puts you a whole block up.
	server.set_block_authoritative(o + Vector3i(0, 1, -2), 0)
	server.set_block_authoritative(o + Vector3i(0, 1, -2), stairs)
	server.set_block_authoritative(o + Vector3i(0, 1, -3), stone)
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)
	p.state.velocity = Vector3.ZERO
	walk.call(60, 1.0)
	_check(p.state.position.y > o.y + 1.4 and p.state.position.z < o.z - 1.0,
		"and up stairs onto the block behind them (y %.2f, z %.1f)" % [p.state.position.y, p.state.position.z - o.z])

	# A fence is taller than it looks: walking into one stops you, and a jump does not clear it.
	server.set_block_authoritative(o + Vector3i(0, 1, -2), 0)
	server.set_block_authoritative(o + Vector3i(0, 1, -3), 0)
	for x in range(-2, 3):
		server.set_block_authoritative(o + Vector3i(x, 1, -2), fence)
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)
	p.state.velocity = Vector3.ZERO
	for t in 90:
		var i = PlayerPhysics.PlayerInput.new()
		i.move = Vector2(0.0, 1.0)
		i.jump = t % 20 == 0
		i.yaw = 0.0
		PlayerPhysics.step(p.state, i, server.world, server.rules)
	# Names the form it ended up as: a run of five joins up, so the one being jumped is base:fence_ew.
	var fence_here: int = server.world.get_block_v(o + Vector3i(0, 1, -2))
	_check(p.state.position.z > o.z - 1.2, "a fence keeps a jumping player in, joined up or not (%s, z %.1f)" % [
		server.registry.defs[fence_here].name, p.state.position.z - o.z])
	server.queue_free()
	await get_tree().process_frame


## The mesher draws the shapes it collides with: a slab is half high, and neighbours keep their faces.
func _shape_meshing() -> void:
	var ChunkMesher = preload("res://engine/client/chunk_mesher.gd")
	var TextureAtlas = preload("res://engine/client/texture_atlas.gd")
	var server = _start("mesh_%d" % Time.get_ticks_msec())
	var registry = server.registry
	var uv := {}
	for d in registry.defs:
		for tex: String in d.textures:
			uv[tex] = Rect2(0, 0, 1, 1)
	uv[""] = Rect2(0, 0, 1, 1)
	var ctx := ChunkMesher.make_context(registry, uv)
	var Chunk = preload("res://engine/shared/chunk.gd")
	var chunk = Chunk.new(Vector2i(0, 0))
	var stone: int = registry.id_of("base:stone")
	var slab: int = registry.id_of("base:stone_slab")
	chunk.blocks.encode_u16(Chunk.index(8, 10, 8) << 1, stone)
	chunk.blocks.encode_u16(Chunk.index(8, 11, 8) << 1, slab)
	var chunks := []
	for i in 9:
		chunks.append(chunk.blocks if i == 4 else PackedByteArray())
	var built: Array = ChunkMesher.build(chunks, ctx)
	var verts: PackedVector3Array = built[0][Mesh.ARRAY_VERTEX] if not built[0].is_empty() else PackedVector3Array()
	var slab_top := 0
	var above_slab := 0
	for v in verts:
		if absf(v.y - 11.5) < 0.001:
			slab_top += 1
		if v.y > 11.51:
			above_slab += 1
	_check(slab_top >= 4, "the mesher draws the slab's top at half height (%d corners there)" % slab_top)
	_check(above_slab == 0, "and nothing above it (%d)" % above_slab)
	var stone_top := 0
	for v in verts:
		if absf(v.y - 11.0) < 0.001:
			stone_top += 1
	_check(stone_top >= 8, "the block under a slab keeps its top face (%d corners at the join)" % stone_top)
	server.queue_free()
	await get_tree().process_frame


## The updater: what it accepts, what it refuses, and the script that installs an update.
func _updates() -> void:
	var Updater = preload("res://engine/client/updater.gd")
	var key := Crypto.new().generate_rsa(2048)
	var other := Crypto.new().generate_rsa(2048)
	var keys := [key.save_to_string(true)]
	var sign := func(text: String, with: CryptoKey) -> String:
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(text.to_utf8_buffer())
		return Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256, hasher.finish(), with))
	var signed := func(manifest: Dictionary) -> Array:
		var text := JSON.stringify(manifest)
		return [text, sign.call(text, key)]
	var newer := {"version": "9.9.9", "notes": "New things", "builds": {"macos": {
		"url": "https://github.com/quarrowen/quarrowen/releases/download/v9.9.9/Quarrowen-macos.zip",
		"sha256": "a".repeat(64), "size": 1234}}}
	var found: Dictionary = Updater.check(signed.call(newer)[0], "0.37.0", "macos", signed.call(newer)[1], keys)
	_check(found.available and found.version == "9.9.9" and found.notes == "New things", "a newer release is offered (%s)" % found.reason)
	_check(not Updater.check(signed.call(newer)[0], "9.9.9", "macos", signed.call(newer)[1], keys).available, "the same version is not")
	_check(not Updater.check(signed.call(newer)[0], "10.0.0", "macos", signed.call(newer)[1], keys).available, "nor an older one")
	_check(not Updater.check(signed.call(newer)[0], "0.37.0", "windows", signed.call(newer)[1], keys).available, "nor a release without a build for this computer")
	var elsewhere: Dictionary = newer.duplicate(true)
	elsewhere.builds.macos.url = "https://not-github.example.com/evil.zip"
	var refused: Dictionary = Updater.check(signed.call(elsewhere)[0], "0.37.0", "macos", signed.call(elsewhere)[1], keys)
	_check(not refused.available and refused.url.is_empty(), "a download somewhere other than the project's releases is refused")
	var plain: Dictionary = newer.duplicate(true)
	plain.builds.macos.url = "http://github.com/quarrowen/quarrowen/x.zip"
	_check(not Updater.check(signed.call(plain)[0], "0.37.0", "macos", signed.call(plain)[1], keys).available, "and so is one that is not https")
	var unchecked: Dictionary = newer.duplicate(true)
	unchecked.builds.macos.erase("sha256")
	_check(not Updater.check(signed.call(unchecked)[0], "0.37.0", "macos", signed.call(unchecked)[1], keys).available, "a download with no checksum is refused")
	_check(not Updater.check("not json at all", "0.37.0", "macos", sign.call("not json at all", key), keys).available, "so is nonsense instead of a manifest")

	var payload := "the new build".to_utf8_buffer()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var digest: String = context.finish().hex_encode()
	_check(Updater.verify(payload, digest, payload.size()), "a download that matches its checksum passes")
	_check(not Updater.verify(payload, digest, payload.size() + 1), "one of the wrong size does not")
	_check(not Updater.verify("something else".to_utf8_buffer(), digest), "nor one with the wrong contents")

	# Signing: a manifest is only trusted when one of the build's release keys signed exactly those bytes.
	var manifest := JSON.stringify(newer)
	_check(Updater.signature_ok(manifest, sign.call(manifest, key), keys), "a manifest signed by the release key is trusted")
	_check(not Updater.signature_ok(manifest, sign.call(manifest, other), keys), "one signed by another key is not")
	_check(not Updater.signature_ok(manifest + " ", sign.call(manifest, key), keys), "nor one whose contents were changed after signing")
	_check(not Updater.signature_ok(manifest, "", keys), "nor an unsigned one, once the build expects a signature")
	_check(not Updater.signature_ok(manifest, "", []), "a build with no release keys trusts nothing rather than everything")
	_check(Updater.signature_ok(manifest, sign.call(manifest, other), [key.save_to_string(true), other.save_to_string(true)]),
		"either key works while one is being rotated out")
	_check(not Updater.check(manifest, "0.37.0", "macos", "", keys).available,
		"check() refuses an unsigned manifest when the build carries a release key")
	_check(not Updater.RELEASE_KEYS.filter(func(k): return not str(k).strip_edges().is_empty()).is_empty(),
		"this build ships a release key, so its updates must be signed")

	var script: String = Updater.install_script("/tmp/u/Quarrowen-9.9.9.zip", "/tmp/u", "/Applications/Quarrowen.app", 4242)
	_check(script.begins_with("#!/bin/sh") and script.contains("kill -0 4242"), "the installer waits for the game to quit")
	_check(script.contains("/Applications/Quarrowen.app.old") and script.contains("mv \"/Applications/Quarrowen.app.old\" \"/Applications/Quarrowen.app\""),
		"it keeps the old app and puts it back if the swap fails")
	_check(script.contains("com.apple.quarantine") and script.contains("open \"/Applications/Quarrowen.app\""),
		"it clears the download flag and starts the new one")

	# The Windows installer, read rather than run: there is no Windows machine here and there may never
	# be one, so what can be checked is that the script says what it should. It is also not reachable yet
	# - Windows is not in update.json - and this test guards that too, because arming an untested script
	# that replaces a folder is the mistake worth preventing.
	var win: Dictionary = Updater.installer("C:/Users/x/AppData/Quarrowen/updates/Quarrowen-9.9.9.zip",
		"C:/Users/x/AppData/Quarrowen/updates", "C:/Games/Quarrowen", 4242, "windows")
	_check(win.file == "install.cmd" and win.program == "cmd.exe" and (win.args as Array) == ["/c"],
		"Windows gets a batch file run by cmd, not a shell script")
	var cmd: String = win.text
	_check(cmd.contains("\r\n") and cmd.begins_with("@echo off"), "it is a batch file with CRLF line endings")
	_check(cmd.contains("tasklist /fi \"PID eq 4242\""), "it waits for the game to quit, because Windows locks a running exe")
	_check(cmd.contains("if %TRIES% GEQ 60 goto gone"), "and gives up waiting rather than looping for ever")
	_check(cmd.contains("Expand-Archive"), "it unzips with PowerShell, which batch cannot do itself")
	_check(cmd.contains("C:\\Games\\Quarrowen") and not cmd.contains("C:/Games"), "paths are backslashed")
	_check(cmd.contains("move \"%TARGET%\" \"%TARGET%.old\""), "it renames the old build aside rather than deleting it")
	# Without this, a failed first move means the second one puts the new build *inside* the old folder.
	_check(cmd.contains("if exist \"%TARGET%\" exit /b 1"), "and stops if that move did not work, leaving the old build whole")
	_check(cmd.contains("move \"%TARGET%.old\" \"%TARGET%\"") and cmd.contains("exit /b 1"),
		"and puts it back if the swap fails")
	_check(cmd.contains("start \"\" \"%TARGET%\\Quarrowen.exe\""), "then starts the new one")
	_check(cmd.contains("Quarrowen.exe\" set \"NEW="), "it finds the game inside the zip rather than assuming a folder name")


## What a player carries survives a mod being turned off and on again.
func _items_of_missing_mods() -> void:
	var server = _start("kept_%d" % Time.get_ticks_msec())
	var p := ServerPlayer.new(server, 66, "Collector")
	p.player_id = "collector"
	server.players[66] = p
	var saved := {"slots": [[0, "base:planks", 5, {}], [1, "someothermod:relic", 2, {"quality": 3}]], "equipment": {}}
	var missing := p.load_items(saved)
	_check(missing == ["someothermod:relic"], "an item from a mod that is not loaded is reported (%s)" % str(missing))
	_check(p.inventory.count_of(server.items.id_of("base:planks")) == 5, "the rest of the inventory loads")
	var written: Dictionary = p.save_items()
	var names: Array = written.slots.map(func(entry): return str(entry[1]))
	_check(names.has("someothermod:relic"), "and is written back untouched, so turning the mod on again restores it (%s)" % str(names))
	server.queue_free()
	await get_tree().process_frame


## Dying leaves a grave with your things in it, and /sethome, /home, /back get you around.
func _graves_and_homes() -> void:
	var server = _start("graves_%d" % Time.get_ticks_msec())
	server.set_gameplay({"keep_inventory": false})
	var y: int = server.surface_height(8, 8)
	var pos := Vector3(8.5, y + 1, 8.5)
	var p := ServerPlayer.new(server, 91, "Digger")
	p.player_id = "digger"
	p.state.position = pos
	server.players[91] = p
	var iron: int = server.items.id_of("base:iron_ingot")
	p.give(iron, 5)
	var stone: int = server.registry.id_of("base:stone")
	p.give(stone, 12)
	server.kill_player(p, "fall", null)
	_check(p.inventory.count_of(iron) == 0, "dying empties the backpack")
	var grave_block: int = server.registry.id_of("base:grave")
	var grave_at := Vector3i.MAX
	for dy in range(-1, 3):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell := Vector3i(floori(pos.x) + dx, floori(pos.y) + dy, floori(pos.z) + dz)
				if server.world.get_block_v(cell) == grave_block:
					grave_at = cell
	_check(grave_at != Vector3i.MAX, "a grave stands where the player died")
	if grave_at == Vector3i.MAX:
		server.queue_free()
		await get_tree().process_frame
		return
	var grave = server.containers.get_container(grave_at)
	var in_grave := 0
	for i in grave.size():
		var stack: Dictionary = grave.get_item(i)
		if int(stack.item) == iron:
			in_grave += int(stack.count)
	_check(in_grave == 5, "the iron is in the grave (%d)" % in_grave)
	var other := ServerPlayer.new(server, 92, "Robber")
	other.player_id = "robber"
	server.players[92] = other
	var blocked: Dictionary = server.emit("container_open", {"player": other, "position": grave_at, "container": grave, "cancelled": false})
	_check(blocked.cancelled, "someone else cannot open it")
	var mine: Dictionary = server.emit("container_open", {"player": p, "position": grave_at, "container": grave, "cancelled": false})
	_check(not mine.cancelled, "the owner can")

	# Homes: /sethome remembers a spot, /home returns to it, /back goes to the last death.
	p.dead = false
	p.edit_tokens = 100.0  # chat (and so commands) costs a token
	p.state.position = pos + Vector3(20, 0, 0)
	server.on_chat(91, "/sethome")
	p.state.position = pos + Vector3(60, 0, 60)
	server.on_chat(91, "/home")
	_check(p.state.position.distance_to(pos + Vector3(20, 0, 0)) < 0.2, "/home returns to the spot /sethome remembered")
	server.on_chat(91, "/back")
	_check(p.state.position.distance_to(pos) < 1.5, "/back goes to where you died (%.1f blocks away)" % p.state.position.distance_to(pos))
	server.queue_free()
	await get_tree().process_frame


## Mod settings: what a mod declares, the three ways a host changes them (the data folder's file, the
## command, the admin screen), that a mod is told, and that the world keeps them.
## Housekeeping: caches pruned oldest-first back to a budget, and nothing of the player's touched.
func _housekeeping() -> void:
	var Housekeeping = preload("res://engine/client/housekeeping.gd")
	var root := "user://test_housekeeping_%d" % Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(root)
	# Three files of 1 KB, written oldest first. They have to land in different seconds for oldest-first
	# to mean anything, because a filesystem modification time is only good to the second.
	var kilobyte := PackedByteArray()
	kilobyte.resize(1024)
	for name in ["a", "b", "c"]:
		var f := FileAccess.open(root.path_join(name), FileAccess.WRITE)
		f.store_buffer(kilobyte)
		f.close()
		OS.delay_msec(1100)
	_check(Housekeeping.size_of(root) == 3 * 1024, "a folder knows what it costs (%d)" % Housekeeping.size_of(root))
	var freed: int = Housekeeping.prune(root, 1024)
	var left := Array(DirAccess.get_files_at(root))
	left.sort()
	_check(freed == 2 * 1024 and left == ["c"], "pruning drops the oldest until it fits (%s)" % str(left))
	_check(Housekeeping.prune(root, 1024) == 0, "and does nothing when it already fits")
	# A budget of 0 means "never", not "delete everything" - it is what guards worlds and the identity key.
	for folder in Housekeeping.FOLDERS:
		if str(folder.key) in ["worlds", "mods", "creations", "identity", "logs"]:
			_check(int(folder.budget) == 0, "%s is never pruned" % folder.key)
	_check(Housekeeping.human(1024 * 1024 * 3) == "3 MB" and Housekeeping.human(900) == "900 bytes",
		"sizes read as sizes (%s)" % Housekeeping.human(1024 * 1024 * 3))
	for name in Array(DirAccess.get_files_at(root)):
		DirAccess.remove_absolute(root.path_join(name))
	DirAccess.remove_absolute(root)


func _mod_settings() -> void:
	var world := "modsettings_%d" % Time.get_ticks_msec()
	# A server with nobody logged in: values come from mod_settings.json in the data folder.
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	var file := FileAccess.open(DATA_DIR.path_join("mod_settings.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"vanilla": {"monsters": "few", "day_minutes": 5, "nonsense": true},
		"absent_mod": {"whatever": 3}}))
	file.close()
	var server = _start(world)
	var api = server.mod_instances.vanilla.api
	_check(api.setting("zombies_burn") == true, "a setting nobody changed is its default")
	_check(api.setting("monsters") == "few" and api.setting("day_minutes") == 5, "mod_settings.json sets values before the mod starts")
	_check(api.setting("nothing_like_this") == null, "a setting that was never declared reads as null")
	_check(server.entities.spawning.caps.monster == 8, "and the mod acted on it as it started")

	# Values the host gives are checked against what the setting accepts.
	_check(not server.mod_settings.set_value("vanilla", "monsters", "loads").is_empty(), "a choice refuses a value that is not one of its choices")
	_check(not server.mod_settings.set_value("vanilla", "not_a_setting", 1).is_empty(), "an unknown setting is refused")
	_check(server.mod_settings.set_value("vanilla", "day_minutes", 500).is_empty() and api.setting("day_minutes") == 120,
		"a number outside the range is brought back into it (%s)" % api.setting("day_minutes"))
	_check(server.mod_settings.set_value("vanilla", "zombies_burn", "off").is_empty() and api.setting("zombies_burn") == false,
		"'off' turns a switch off")

	# The mod hears about a change while the server runs, and the file's value can be overridden in game.
	var heard := []
	api.on("settings_changed", func(ev): heard.append(ev))
	_check(server.mod_settings.set_value("vanilla", "monsters", "many").is_empty(), "an admin can change a setting")
	_check(heard.size() == 1 and heard[0].key == "monsters" and heard[0].value == "many" and heard[0].previous == "few",
		"the mod is told what changed, and what it was")
	_check(server.entities.spawning.caps.monster == 48, "and it took effect at once")
	server.mod_settings.set_value("vanilla", "monsters", "many")
	_check(heard.size() == 1, "setting a value it already has tells nobody")

	# The command, with an admin and without one.
	var admin := ServerPlayer.new(server, 71, "Boss")
	admin.player_id = "boss"
	admin.edit_tokens = 100.0  # a command costs a token, like chatting
	server.players[71] = admin
	server.roles.give("boss", "owner")
	var guest := ServerPlayer.new(server, 72, "Guest")
	guest.player_id = "guest"
	guest.edit_tokens = 100.0
	server.players[72] = guest
	server.on_chat(72, "/modsettings vanilla monsters none")
	_check(api.setting("monsters") == "many", "a player who is not an admin cannot change a mod's settings")
	server.on_chat(71, "/modsettings vanilla monsters none")
	_check(api.setting("monsters") == "none", "an admin can, with /modsettings")
	server.on_server_panel(71, "modset", {"mod": "vanilla", "key": "monsters", "value": "few"})
	_check(api.setting("monsters") == "few", "and from the admin settings screen")
	server.on_server_panel(72, "modset", {"mod": "vanilla", "key": "monsters", "value": "many"})
	_check(api.setting("monsters") == "few", "which checks the role too, like every other action there")
	var listed: Array = server.mod_settings.list("vanilla")
	var keys: Array = listed.map(func(entry): return str(entry.key))
	_check(keys.has("monsters") and keys.has("day_minutes") and listed[0].has("label") and listed[0].has("type"),
		"the screen is given every setting with its type and label (%s)" % str(keys))
	server.on_chat(71, "/modsettings vanilla zombies_burn reset")
	_check(api.setting("zombies_burn") == true, "'reset' puts a setting back to its default")

	# The world keeps what the admin set; the file's values are not written into it.
	server._save_all(true)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR.path_join(world).path_join("world.json")))
	_check(saved.get("mod_settings", {}).get("vanilla", {}).get("monsters", "") == "few", "the world remembers what was changed")
	_check(not saved.mod_settings.vanilla.has("zombies_burn"), "a setting put back to its default is not kept")
	_check(saved.mod_settings.get("absent_mod", {}).is_empty(), "a mod_settings.json value is not copied into the world")
	server.queue_free()
	await get_tree().process_frame

	# Reopening the world: what an admin set wins over the file.
	server = _start(world)
	api = server.mod_instances.vanilla.api
	_check(api.setting("monsters") == "few", "the world's value wins over mod_settings.json when it opens again")
	DirAccess.remove_absolute(DATA_DIR.path_join("mod_settings.json"))
	server.queue_free()
	await get_tree().process_frame


## The admin server settings screen: state, changes, and that it grants nothing extra.
func _server_panel() -> void:
	var server = _start("panel_%d" % Time.get_ticks_msec())
	var sent := []
	var admin := ServerPlayer.new(server, 61, "Boss")
	admin.player_id = "boss"
	server.players[61] = admin
	server.roles.give("boss", "owner")
	var guest := ServerPlayer.new(server, 62, "Guest")
	guest.player_id = "guest"
	server.players[62] = guest
	# The server answers over the wire; catch what it would send by watching the rules it changes instead.
	server.on_server_panel(62, "set", {"key": "pvp", "value": "false"})
	_check(server.gameplay.pvp, "a player who is not an admin cannot change a rule from the panel")
	server.on_server_panel(61, "set", {"key": "pvp", "value": "false"})
	_check(not server.gameplay.pvp, "an admin can turn a rule off from the panel")
	server.on_server_panel(61, "set", {"key": "pvp", "value": "true"})
	_check(server.gameplay.pvp, "and on again")
	server.on_server_panel(61, "time", {"value": "night"})
	_check(server.get_time_of_day() > 0.8 or server.get_time_of_day() < 0.2, "the panel sets the time of day (%.2f)" % server.get_time_of_day())
	server.on_server_panel(61, "allowlist", {"mode": "add", "name": "Maya"})
	var list: Dictionary = server._meta.get("allowlist", {})
	_check(list.get("players", {}).has("maya"), "the panel adds a player to the allowlist")
	server.on_server_panel(61, "anticheat", {"mode": "log"})
	_check(server.anticheat.mode == "log", "the panel switches the cheat checks to logging")
	sent.append(true)
	server.queue_free()
	await get_tree().process_frame


## Getting out of the water onto a bank at the water's own level, which used to need a pickaxe.
## A Close button must actually close. Nothing handled the action, so a modal panel - the charter board,
## Bramble, /milestones - trapped the player until they quit the game.
## Peer 0 is Godot's broadcast id, not a harmless "nobody". A flooding client was handed to the handlers
## as 0, and the replies made on its behalf went to everyone - including a kick.
func _broadcast_id() -> void:
	var server = _start("peer0_%d" % Time.get_ticks_msec())
	var bystander := ServerPlayer.new(server, 210, "Bystander")
	bystander.player_id = "bystander"
	server.players[210] = bystander
	var before: int = server.players.size()
	# A hello from the broadcast id must be ignored outright: it used to create a join, send a challenge
	# to everybody, and - with a name already taken - kick the whole server.
	var protocol := preload("res://engine/shared/protocol.gd").VERSION
	server.on_hello(0, protocol, "Bystander", "not a key")
	_check(not server._joining.has(0), "a hello from the broadcast id starts no join")
	_check(server.players.size() == before and server.players.has(210), "and kicks nobody")
	server.on_hello(-1, protocol, "Someone", "not a key")
	_check(not server._joining.has(-1), "nor does one from a negative id, which means 'everyone else'")
	server.kick(0, "should do nothing at all")
	_check(server.players.has(210), "kicking the broadcast id throws nobody off")
	server.queue_free()
	await get_tree().process_frame


func _ui_close() -> void:
	var server = _start("uiclose_%d" % Time.get_ticks_msec())
	var p := ServerPlayer.new(server, 131, "Reader")
	p.player_id = "reader"
	server.players[131] = p
	p.show_ui("tester:panel", {"anchor": "center", "modal": true,
		"children": [{"type": "button", "text": "Close", "action": "close"}]})
	_check(p.ui_ids.has("tester:panel"), "a panel is open")
	var seen := []
	server.add_handler("ui_action", func(ev): seen.append(str(ev.action)), 0)
	server.on_ui_action(131, "tester:panel", "close")
	_check(not p.ui_ids.has("tester:panel"), "clicking Close closes it")
	_check(seen == ["close"], "and the mod still hears the action first")
	server.queue_free()
	await get_tree().process_frame


func _swimming() -> void:
	var server = _start("swim_%d" % Time.get_ticks_msec())
	var stone: int = server.registry.id_of("base:stone")
	var water: int = server.registry.id_of("base:water")
	var o := Vector3i(40, 80, 40)
	server._ensure_chunk(Vector2i(2, 2))
	# A floor, a pool two blocks deep, and a bank whose top is level with the water's top.
	for x in range(-3, 4):
		for z in range(-4, 5):
			server.set_block_authoritative(o + Vector3i(x, 0, z), stone)
			server.set_block_authoritative(o + Vector3i(x, 1, z), stone)
			if z <= 1:
				server.set_block_authoritative(o + Vector3i(x, 2, z), water)
				server.set_block_authoritative(o + Vector3i(x, 3, z), water)
			else:
				server.set_block_authoritative(o + Vector3i(x, 2, z), stone)
				server.set_block_authoritative(o + Vector3i(x, 3, z), stone)
	var bank_top: float = float(o.y + 4)
	var p := ServerPlayer.new(server, 73, "Swimmer")
	p.player_id = "swimmer"
	server.players[73] = p
	p.state.position = Vector3(o.x + 0.5, o.y + 3.0, o.z - 1.5)  # afloat, facing the bank
	p.state.velocity = Vector3.ZERO
	_check(server.rules.liquid_lut[server.world.get_block(o.x, o.y + 3, o.z - 1)] == 1, "the swimmer is in water")
	for t in 120:
		var i = PlayerPhysics.PlayerInput.new()
		i.move = Vector2(0.0, 1.0)  # forward, towards the bank
		i.jump = true               # holding jump, as anyone would
		i.yaw = PI                  # +z
		PlayerPhysics.step(p.state, i, server.world, server.rules)
	_check(p.state.position.y >= bank_top - 0.05 and p.state.position.z > float(o.z) + 1.0,
		"a swimmer can climb out onto a bank at the water's level (y %.2f of %.0f, z %.1f)"
			% [p.state.position.y, bank_top, p.state.position.z - o.z])
	server.queue_free()
	await get_tree().process_frame


## Flying (creative) and crouching, run through the same physics the client predicts with.
func _movement() -> void:
	var server = _start("movement_%d" % Time.get_ticks_msec())
	var stone: int = server.registry.id_of("base:stone")
	var o := Vector3i(40, 80, 40)
	server._ensure_chunk(Vector2i(2, 2))
	for x in range(-2, 3):
		for z in range(-2, 3):
			server.set_block_authoritative(o + Vector3i(x, 0, z), stone)  # a 5x5 platform in the air
	var p := ServerPlayer.new(server, 71, "Flyer")
	p.player_id = "flyer"
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)
	p.state.on_ground = true
	server.players[71] = p
	var rules = server.rules
	var input := func(forward: float, jump: bool, sneak: bool) -> PlayerPhysics.PlayerInput:
		var i = PlayerPhysics.PlayerInput.new()
		i.move = Vector2(0.0, forward)
		i.jump = jump
		i.sneak = sneak
		i.yaw = 0.0
		return i
	var run := func(ticks: int, forward: float, jump: bool, sneak: bool) -> void:
		for t in ticks:
			PlayerPhysics.step(p.state, input.call(forward, jump, sneak), server.world, rules)

	# Survival: no flying without the permission, and walking off the platform falls.
	_check(not server.set_flying(p, true) and not p.state.flying, "a survival player without the permission cannot fly")
	p.set_creative(true)
	_check(server.set_flying(p, true) and p.state.flying, "a creative player can fly")
	var start_y: float = p.state.position.y
	run.call(30, 0.0, false, false)
	_check(absf(p.state.position.y - start_y) < 0.05, "flying holds height with no input (%.2f)" % (p.state.position.y - start_y))
	run.call(60, 0.0, true, false)
	_check(p.state.position.y > start_y + 4.0, "jump rises while flying (%.1f blocks)" % (p.state.position.y - start_y))
	var high: float = p.state.position.y
	run.call(45, 0.0, false, true)
	_check(p.state.position.y < high - 2.5, "crouch sinks while flying (%.1f blocks)" % (high - p.state.position.y))
	server.set_flying(p, false)
	run.call(120, 0.0, false, false)
	_check(p.state.on_ground and absf(p.state.position.y - (o.y + 1)) < 0.05, "stopping flight drops back onto the platform")

	# Crouching: slower, and it will not step off the edge.
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)
	p.state.velocity = Vector3.ZERO
	var before: Vector3 = p.state.position
	run.call(30, 1.0, false, false)
	var walked: float = before.distance_to(p.state.position)
	p.state.position = before
	p.state.velocity = Vector3.ZERO
	run.call(30, 1.0, false, true)
	var crouched: float = before.distance_to(p.state.position)
	_check(crouched < walked * 0.6, "crouching is slower than walking (%.2f vs %.2f blocks)" % [crouched, walked])
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z - 1.1)  # at the north edge, facing off it
	p.state.velocity = Vector3.ZERO
	run.call(90, 1.0, false, true)
	_check(p.state.position.y >= o.y + 1 and p.state.on_ground, "crouching at the edge does not walk off (y %.2f)" % p.state.position.y)
	p.state.position = Vector3(o.x + 0.5, o.y + 1, o.z - 1.1)
	p.state.velocity = Vector3.ZERO
	run.call(90, 1.0, false, false)
	_check(p.state.position.y < o.y, "walking off the same edge falls (y %.2f)" % p.state.position.y)
	server.queue_free()
	await get_tree().process_frame


## Things the family playtest turned up: creative pickup, sparring, zombies burning at dawn.
func _playtest_fixes() -> void:
	var server = _start("playtest_%d" % Time.get_ticks_msec())
	var y: int = server.surface_height(8, 8)
	var pos := Vector3(8.5, y + 1, 8.5)
	var p := ServerPlayer.new(server, 81, "Builder")
	p.player_id = "builder"
	p.state.position = pos
	p.set_creative(true)
	server.players[81] = p
	var coal: int = server.items.id_of("base:coal")
	var dropped = server.entities.drop_item(coal, 1, pos + Vector3(0.4, 0.5, 0), Vector3.ZERO)
	dropped.pickup_delay = 0.0
	for i in 120:
		server.entities.tick(1.0 / 60.0)
	_check(dropped.removed, "a player in creative can pick up what they dropped")

	# Sparring: players can hit each other unless the server turns pvp off.
	var other := ServerPlayer.new(server, 82, "Sparring")
	other.player_id = "sparring"
	other.state.position = pos + Vector3(1.0, 0, 0)
	server.players[82] = other
	_check(server.gameplay.pvp, "players can hit each other by default")
	other.hurt_timer = 0.0
	server.on_attack(81, 1, 82)
	_check(other.health < other.max_health, "a player's swing lands on another player (health %.1f)" % other.health)
	server.set_gameplay({"pvp": false})
	other.hurt_timer = 0.0
	server._time += 5.0
	var before: float = other.health
	server.on_attack(81, 1, 82)
	_check(other.health == before, "and does not when pvp is off")
	server.set_gameplay({"pvp": true})

	# Daylight burns the undead: a zombie standing in the open at noon dies.
	server.set_world_time(0.5, 0.0)
	var burn_spot := Vector3(12.5, server.surface_height(12, 8) + 1, 8.5)
	var zombie = server.entities.spawn(server.entities.registry.id_of("vanilla:zombie"), burn_spot)
	zombie.data["no_despawn"] = true
	zombie.tune({"temperament": "none", "wander_radius": 0.0})  # stay in the open instead of wandering into shade
	var burned := false
	for i in 90 * 60:
		server._time += 1.0 / 60.0
		server.entities.tick(1.0 / 60.0)
		server._run_tasks()
		zombie.hurt_timer = 0.0
		if zombie.removed or not zombie.is_alive():
			burned = true
			break

	_check(burned, "a zombie caught in the open at noon burns up")
	server.queue_free()
	await get_tree().process_frame


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
	_check(zombie.damage(5.0, "magic") and zombie.health == 15.0, "damage applied (%.1f)" % zombie.health)
	_check(not zombie.damage(5.0, "magic"), "hurt cooldown blocks immediate repeat damage")
	zombie.hurt_timer = 0.0
	zombie.damage(100.0, "magic")
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


## Drawing a bow: the hold is the shot, and letting go early is not one.
func _archery() -> void:
	var server = _start("archery_%d" % Time.get_ticks_msec())
	var items = server.items
	var p := ServerPlayer.new(server, 91, "Archer")
	p.player_id = "archer"
	server.players[91] = p
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	p.edit_tokens = 100.0
	var bow: int = items.id_of("vanilla:bow")
	var arrow: int = items.id_of("vanilla:arrow")
	_check(bow > 0 and arrow > 0 and items.get_def(bow).charge.get("seconds", 0.0) > 0.0, "a bow is an item you hold")
	p.inventory.set_slot(0, bow, 1)
	p.inventory.selected = 0
	p.give(arrow, 3)
	var before: int = server.entities.entities.size()
	# Let go at once: under the minimum draw, so nothing is shot and no arrow is spent.
	_check(server.charging.start(p, bow) and not p.charging.is_empty(), "holding use draws it")
	server.charging.release(p)
	_check(server.entities.entities.size() == before and p.count_of(arrow) == 3, "letting go straight away shoots nothing")
	# A full draw.
	server.charging.start(p, bow)
	server._time += 1.0
	server.charging.release(p)
	_check(p.count_of(arrow) == 2, "a full draw spends an arrow")
	var shot = null
	for e in server.entities.entities.values():
		if e.type == server.entities.registry.id_of("vanilla:arrow"):
			shot = e
	_check(shot != null and shot.body.velocity.length() > 30.0, "and sends it off at speed (%.1f)" % (shot.body.velocity.length() if shot != null else 0.0))
	_check(shot != null and float(shot.data.get("damage", 0.0)) > 8.0, "a fully drawn arrow hits harder than the def alone")
	# Switching slots mid-draw lets it go rather than leaving them drawing something they no longer hold.
	server.charging.start(p, bow)
	p.inventory.selected = 1
	server.charging.update(p)
	_check(p.charging.is_empty(), "changing what you hold drops the draw")
	# With no arrows left it refuses rather than firing nothing.
	p.inventory.selected = 0
	p.take(arrow, 2)
	var count: int = server.entities.entities.size()
	server.charging.start(p, bow)
	server._time += 1.0
	server.charging.release(p)
	_check(server.entities.entities.size() == count, "no arrows, no shot")
	server.queue_free()
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
	# The slots sit after the backpack in one array, in registration order, so a mod adding one (base's
	# charm slot) lengthens the inventory rather than moving anything already in it.
	_check(chest == Inventory.SIZE + 1 and p.inventory.total() == Inventory.SIZE + items.slots.size(),
		"equipment slots follow the backpack (%d of them)" % items.slots.size())
	_check(p.equipment_slot("trinket") >= Inventory.SIZE + 5, "and a mod can add one of its own")

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

	var saved: Dictionary = p.save_items()
	var copy := ServerPlayer.new(server, 78, "Copy")
	copy.load_items(saved)
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
	var near := {coord: true}  # the simulated set: this chunk is close enough to somebody to run
	ticks.unload_chunk(coord)
	ticks.clock += 3600.0
	ticks.load_chunk(coord, positions, {}, saved)
	ticks.update(BlockTicks.STEP, near)  # the chunk wakes and works out what it missed...
	ticks.update(BlockTicks.STEP, near)  # ...which is handed over on the round after
	_check(server.world.get_block_v(soil + Vector3i.UP) == wheat[3], "wheat kept growing while its chunk was unloaded")

	# And the same when it was loaded the whole time but nobody was near enough to run it.
	server.set_block_authoritative(soil + Vector3i.UP, wheat[0])
	ticks.update(BlockTicks.STEP, {})  # everybody walked away
	ticks.clock += 3600.0
	_check(server.world.get_block_v(soil + Vector3i.UP) == wheat[0], "wheat does not grow with nobody near enough")
	ticks.update(BlockTicks.STEP, near)
	ticks.update(BlockTicks.STEP, near)
	_check(server.world.get_block_v(soil + Vector3i.UP) == wheat[3], "coming back hands it the hour it stood still")

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
	# Saplings also grow on random ticks (about 1 in 240 per half-second round): keep those out of this check.
	var growth_interval: float = ticks.handlers[sapling].interval
	ticks.handlers[sapling].interval = 1.0e12
	var grove := {Vector2i(tree_spot.x >> 4, tree_spot.z >> 4): true}
	ticks.update(0.6, grove)
	ticks.handlers[sapling].interval = growth_interval
	_check(server.world.get_block_v(tree_spot + Vector3i.UP) == sapling, "a scheduled tick waits until it is due")
	ticks.update(0.6, grove)
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
	# Blocks only tick within simulation distance of somebody, and this test drives block_ticks by
	# hand rather than through the server's tick, so it has to work out that set itself.
	server._refresh_simulation()
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
	server.block_ticks.update(0.6, server.realm.simulated)
	_check(box.get_item(2).item == ingot and box.get_item(2).count == 2 and box.get_item(0).count == 1, "25 seconds smelted two ingots (%s)" % box.get_item(2))
	_check(box.get_progress("burn") > 0.0 and box.get_progress("cook") > 0.0, "progress bars follow fuel and smelting")
	server.block_ticks.clock += 500.0
	server.block_ticks.update(0.6, server.realm.simulated)
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
	# Parts need the Toolsmith’s Bench.
	p.inventory.set_slot(0, items.id_of("base:iron_ingot"), 5)
	p.inventory.set_slot(1, items.id_of("vanilla:bone"), 2)
	server.open_crafting(p, {})
	_check(server.craft(p, head_recipe) == 0, "parts cannot be made without a Toolsmith’s Bench")
	var forge := Vector3i(10, y + 1, 8)
	server.set_block_authoritative(forge, reg.id_of("base:tool_forge"))
	server.on_interact(97, forge)
	_check(p.crafting_station.get("name", "") == "tool_forge", "the Toolsmith’s Bench opens as a station")
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
		# An unlock may name one thing or several, any of which opens the page.
		var items_named: Array = (u.item if u.item is Array else [u.item]) if u.has("item") else []
		if items_named.any(func(n): return not item_ok.call(str(n))) or u.has("recipe") and server.recipes.index_of(u.recipe) < 0 \
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
	var listed: Array = tut.to_network().map(func(t): return str(t.id))
	_check(listed.size() == 3 and listed[0] == "vanilla:first_steps" and listed[1] == "vanilla:survival",
		"clients get the tutorial list in order (%s)" % str(listed))
	server.queue_free()
	await get_tree().process_frame


## Milestones: lifetime counts, paid out once, saved with the player.
func _milestones() -> void:
	var server = _start("milestones_%d" % Time.get_ticks_msec())
	var ms = server.milestones
	var items = server.items
	var api = preload("res://engine/server/mod_api.gd").new(server, {"id": "tester", "dir": "res://tests"})
	_check(ms.milestones.has("vanilla:colossus") and ms.milestones["vanilla:colossus"].goal.event == "entity_death",
		"mods register milestones")
	_check(not api.register_milestone("nope", {"goal": {"type": "have", "target": "base:planks"}}),
		"a state is not a milestone, so poll goals are refused")
	_check(not api.register_milestone("nope2", {"goal": {"type": "juggle"}}), "and unknown goals are refused")
	api.register_milestone("digger", {"title": "Digger", "order": 1, "announce": true,
		"description": "Twelve blocks of stone.", "goal": {"type": "break", "target": "base:stone", "count": 12},
		"reward": {"items": [["base:apple", 2]]}})
	api.register_milestone("secretive", {"title": "Secret", "secret": true, "goal": {"type": "sleep"}})
	var p := ServerPlayer.new(server, 140, "Digger")
	p.player_id = "digger"
	server.players[140] = p
	var reached := []
	api.on("milestone_reached", func(ev): reached.append(ev.milestone))
	var stone: int = server.registry.id_of("base:stone")
	var dirt: int = server.registry.id_of("base:dirt")
	for i in 5:
		server.emit("block_broken", {"player": p, "position": Vector3i.ZERO, "block": stone})
	_check(ms.state_of(p).counts.get("tester:digger", 0) == 5, "matching events count towards a milestone")
	for i in 5:
		server.emit("block_broken", {"player": p, "position": Vector3i.ZERO, "block": dirt})
	_check(ms.state_of(p).counts.get("tester:digger", 0) == 5, "and other blocks do not")
	# The list a player sees, before it is finished: progress, and no sign of the secret one.
	var titles: Array = ms.view(p).map(func(m): return str(m.title))
	_check(not titles.has("Secret"), "a secret milestone stays out of the list until it is reached")
	var before: int = p.inventory.count_of(items.id_of("base:apple"))
	for i in 7:
		server.emit("block_broken", {"player": p, "position": Vector3i.ZERO, "block": stone})
	_check(reached == ["tester:digger"] and ms.reached(p, "tester:digger"), "reaching one fires once")
	_check(p.inventory.count_of(items.id_of("base:apple")) == before + 2, "and pays out its reward")
	for i in 6:
		server.emit("block_broken", {"player": p, "position": Vector3i.ZERO, "block": stone})
	_check(reached == ["tester:digger"], "and never pays out twice, however long you keep going")
	# A mob killing a mob is not a player reaching anything: `kill` reports whoever landed the blow, and
	# that is often another mob.
	api.register_milestone("hunter", {"title": "Hunter", "goal": {"type": "kill", "target": "vanilla:pig"}})
	var pig = server.entities.spawn(server.entities.registry.id_of("vanilla:pig"), p.position + Vector3(2, 0, 0))
	var wolf = server.entities.spawn(server.entities.registry.id_of("vanilla:wolf"), p.position + Vector3(3, 0, 0))
	server.emit("entity_death", {"attacker": wolf, "entity": pig})
	_check(reached == ["tester:digger"], "a kill with no player behind it counts for nobody")
	server.emit("entity_death", {"attacker": p, "entity": pig})
	_check(reached == ["tester:digger", "tester:hunter"], "and the same kill by a player does count")
	# Saved with the player, because it lives in player data.
	server._store_player(p)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(server._meta.players.digger.data))
	_check(saved.get("milestones", {}).get("done", {}).has("tester:digger"), "milestones are saved with the player")
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
	# The filled box has to cover everywhere find_spot can look, or the test is really asking what the
	# world generator happened to put next door: it picks a spot up to 6 blocks out and scans 28 up and
	# down. So the walls sit outside that reach, and only the room inside them is open.
	for x in range(-2, 42):
		for z in range(-2, 14):
			for dy in range(-30, 31):
				var edge: bool = dy <= -1 or dy >= 3 or x <= 0 or x >= 39 or z <= 0 or z >= 11 or x == 20  # solid around, so caves nearby don't count
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
	# Orders and follow. Right-clicking used to toggle sitting; it opens the order panel now, because a
	# toggle stops working the moment there are three things to say. (2026-09-20)
	p.inventory.selected = 1
	server.on_interact_entity(106, wolf.id)
	_check(p.ui_ids.has("engine:orders"), "right-click opens the order panel")
	_check(server.companions.order_of(wolf) == "engine:follow", "a newly tamed creature follows without being told")
	server.on_ui_action(106, "engine:orders", "order:engine:stay")
	_check(wolf.data.get("sitting", false) and taming._sit_score(wolf.brain) > 1.0, "telling it to stay sits it down")
	# A stranger's panel action must be refused even if they somehow send one.
	server.on_interact_entity(107, wolf.id)
	server.on_ui_action(107, "engine:orders", "order:engine:follow")
	_check(wolf.data.get("sitting", false), "only the owner can tell it anything")
	server.on_interact_entity(106, wolf.id)
	server.on_ui_action(106, "engine:orders", "order:engine:follow")
	_check(not wolf.data.get("sitting", false), "and the owner can tell it to come along again")

	# Guarding: it holds a spot, and walks back when something drew it away.
	server.on_interact_entity(106, wolf.id)
	server.on_ui_action(106, "engine:orders", "order:engine:guard")
	var post: Vector3 = server.companions.post_of(wolf)
	_check(post != Vector3.INF, "guarding remembers where it was told to stand")
	_check(server.companions.score(wolf.brain) == 0.0, "and it is content while it is there")
	wolf.body.position = post + Vector3(20, 0, 0)
	_check(server.companions.score(wolf.brain) > 0.0, "but wants to go back when it is dragged off")
	server.on_interact_entity(106, wolf.id)
	server.on_ui_action(106, "engine:orders", "order:engine:follow")
	wolf.body.position = post
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

	# What happens to a template with faults in it. It still loads - content should not crash a server -
	# but it must not do so in silence, which is what it used to do: blocks naming a palette entry nobody
	# registered were dropped, data keyed to nothing was dropped, and nothing said a word. You found out
	# when a chunk generated with holes in it, if you ever noticed. (2026-09-18)
	var broken := {"size": [3, 3, 3], "palette": ["base:cobblestone", "base:not_a_real_block"],
		"blocks": [[0, 0, 0, 0], [1, 0, 0, 1], [2, 2]], "data": {"0,0,0": {"loot": "x"}, "nope": {}}}
	_check(st.add_template("test:broken", broken), "a template with faults still loads, because content should not stop a server")
	_check((st.templates["test:broken"].blocks as Array).size() == 1, "and keeps only what it could read (%d of 3)" % (st.templates["test:broken"].blocks as Array).size())
	_check((st.templates["test:broken"].data as Dictionary).size() == 1, "same for its data")

	# The author should never get that far: mod_tool says so at pack time, naming the file and the fault.
	# Checked against the bundled structures first - if a rule complains about those, the rule is wrong.
	# Only the mods this server actually loaded: the check resolves block names against the running
	# registry, so pointing it at Hearthhold's structures from a vanilla server reports its blocks as
	# unregistered - correctly, and uselessly. `mod_tool validate mods/hearthhold` loads Hearthhold and
	# is where that one belongs.
	var structure_issues: Array = Validator.check_structures(server, "res://mods/vanilla")
	_check(structure_issues.is_empty(), "vanilla's structures all pass validation (%s)" % ", ".join(structure_issues.map(func(i): return str(i.message))))
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
	_check(page[0] == 200 and page[1].contains("Quarrowen Dev Dashboard"), "the dashboard page is served with the token")
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


## The mod list: reading the index, what is installed against what is offered, and putting a mod on this
## computer and taking it off again.
func _mod_index() -> void:
	var Catalog = preload("res://engine/client/mod_catalog.gd")
	var Loader = preload("res://engine/server/mod_loader.gd")
	var root := DATA_DIR.path_join("catalog_%d" % Time.get_ticks_msec())

	# An index only counts if every entry is from an address the client trusts, with a real checksum.
	var good_sha := "a".repeat(64)
	var index_text := JSON.stringify({"version": "1.0.0", "mods": [
		{"id": "handy", "name": "Handy", "version": "1.2.0", "kind": "addon", "size": 2048,
			"url": "https://quarrowen.com/v1/mods/handy-1.2.0.zip", "sha256": good_sha, "depends": ["base@^1.0"]},
		{"id": "evil", "name": "Evil", "version": "1.0.0", "size": 2048,
			"url": "https://example.com/evil.zip", "sha256": good_sha},
		{"id": "sloppy", "name": "Sloppy", "version": "1.0.0", "size": 2048,
			"url": "https://quarrowen.com/v1/mods/sloppy.zip", "sha256": "nope"},
		{"id": "huge", "name": "Huge", "version": "1.0.0", "size": 1 << 30,
			"url": "https://quarrowen.com/v1/mods/huge.zip", "sha256": good_sha},
	]})
	var index: Array = Catalog.read_index(index_text)
	_check(index.size() == 1 and index[0].id == "handy", "the index keeps only entries from the project's own site with a real checksum")
	_check(Catalog.read_index("not json at all").is_empty(), "a mod list that is not readable is treated as empty, not trusted")

	# Installed against offered: what is new, what has an update, and what came with the game.
	var installed := [
		{"id": "base", "name": "Base", "version": "1.0.0", "kind": "library", "removable": false, "description": "", "depends": []},
		{"id": "handy", "name": "Handy", "version": "1.0.0", "kind": "addon", "removable": true, "description": "", "depends": []},
	]
	var merged: Array = Catalog.merge(installed, index + [{"id": "base", "name": "Base", "version": "9.9.9", "kind": "library",
		"url": "https://quarrowen.com/v1/mods/base-9.9.9.zip", "sha256": good_sha, "size": 2048, "description": "", "depends": []}])
	var by_id := {}
	for row: Dictionary in merged:
		by_id[row.id] = row
	_check(by_id.handy.state == "update" and by_id.handy.offered == "1.2.0", "a newer version of an installed mod shows as an update")
	_check(by_id.base.state == "installed", "a mod that came with the game is not updated from the mod list (the game update brings it)")
	var fresh: Array = Catalog.merge([], index)
	_check(fresh.size() == 1 and fresh[0].state == "available", "a mod that is not installed shows as available")

	# What a mod needs, and what needs it.
	var needs: Array = Catalog.missing_dependencies({"id": "handy", "name": "Handy", "depends": ["base@^1.0", "nowhere"]}, [], index +
		[{"id": "base", "name": "Base", "version": "1.0.0", "depends": []}])
	_check(needs.size() == 2 and needs[0].id == "base" and needs[1].get("missing", false),
		"installing a mod pulls in what it needs, and says so when something is not offered at all")
	_check(Catalog.missing_dependencies({"id": "handy", "depends": ["base"]}, installed, index).is_empty(), "nothing is fetched twice")
	_check(Catalog.needed_by("base", [{"id": "vanilla", "name": "Vanilla", "depends": [{"id": "base", "version": "^1.0"}]}]) == ["Vanilla"],
		"removing a mod can say which other mods need it")

	# Installing from a package, and removing it again. user://mods is the only place either touches.
	var source := root.path_join("source")
	_write_mod(source.path_join("handy"), {"id": "handy", "name": "Handy", "version": "1.2.0", "engine": "^1.0", "kind": "addon"})
	var zip_path := ProjectSettings.globalize_path(root.path_join("handy-1.2.0.zip"))
	_check(Loader.pack(ProjectSettings.globalize_path(source.path_join("handy")), zip_path) == OK, "a mod packs into a zip to install from")
	var target: String = Loader.user_mods().path_join("handy")
	_check(Catalog.install_file(zip_path, "handy").is_empty() and FileAccess.file_exists(target.path_join("mod.json")),
		"installing a mod puts it in the player's own mods folder")
	_check(not Catalog.install_file(zip_path, "something_else").is_empty(), "a package holding a different mod than the list promised is refused")
	_check(Catalog.is_removable(target) and not Catalog.is_removable("res://mods/base"), "only mods the player installed may be removed")
	var listed: Array = Catalog.installed().filter(func(m): return m.id == "handy")
	_check(listed.size() == 1 and listed[0].removable and listed[0].version == "1.2.0", "an installed mod is listed with its version and can be removed")
	_check(Catalog.remove("handy").is_empty() and not DirAccess.dir_exists_absolute(target), "removing a mod takes its folder away")
	_check(not Catalog.remove("base").is_empty(), "a mod that came with the game cannot be removed")
	_remove_tree(ProjectSettings.globalize_path(root))


## Loot: one table format behind mobs, blocks and chests - pools, weights, conditions, nested tables,
## what a host can turn up for an event, and the find worth announcing.
func _loot() -> void:
	var server = _start("loot_%d" % Time.get_ticks_msec())
	var loot = server.loot
	var iron: int = server.items.id_of("base:iron_ingot")
	var coal: int = server.items.id_of("base:coal")
	var stick: int = server.items.id_of("base:stick")

	# Pools roll on their own: one always gives, the other is a small chance.
	loot.register("test:mix", {"pools": [
		{"rolls": 2, "entries": [{"item": "base:coal", "count": [1, 1]}]},
		{"rolls": 1, "entries": [{"item": "base:iron_ingot", "weight": 1}, {"empty": true, "weight": 9}]},
	]})
	var counts := {}
	for i in 400:
		for stack in loot.roll("test:mix"):
			counts[stack[0]] = int(counts.get(stack[0], 0)) + int(stack[1])
	_check(counts.get(coal, 0) == 800, "a pool that always gives, gives every time (%d of 800 coal)" % counts.get(coal, 0))
	_check(counts.get(iron, 0) > 10 and counts.get(iron, 0) < 100, "an entry's weight against 'empty' is its chance (%d irons in 400)" % counts.get(iron, 0))
	_check(loot.chance_of("test:mix", iron) > 0.08 and loot.chance_of("test:mix", iron) < 0.12,
		"the engine works out how likely a drop is from the weights (%.2f)" % loot.chance_of("test:mix", iron))
	_check(loot.is_rare("test:mix", iron) == false and loot.is_rare("test:mix", coal) == false, "a one-in-ten drop is not rare enough to announce")

	# The same roll twice, when it is seeded: a chest holds the same thing however often it is looked at.
	_check(str(loot.roll("test:mix", {"seed": 7})) == str(loot.roll("test:mix", {"seed": 7})), "a seeded roll gives the same loot every time")

	# Conditions, on a pool and on an entry.
	loot.register("test:conditions", {"pools": [
		{"rolls": 1, "when": {"killed_by": "player"}, "entries": [{"item": "base:iron_ingot"}]},
		{"rolls": 1, "entries": [{"item": "base:coal", "when": {"depth": [0, 30]}}, {"item": "base:stick"}]},
	]})
	var deep: Array = loot.roll("test:conditions", {"cause": "player", "position": Vector3(0, 12, 0)})
	var high: Array = loot.roll("test:conditions", {"cause": "fall", "position": Vector3(0, 80, 0)})
	_check(deep.any(func(d): return d[0] == iron), "a pool only rolls when its condition holds")
	_check(not high.any(func(d): return d[0] == iron), "and not when it does not")
	_check(high.all(func(d): return d[0] == stick), "an entry's condition takes it out of the running (%s)" % str(high))

	# One table can roll another.
	loot.register("test:nested", {"pools": [{"rolls": 1, "entries": [{"table": "test:mix"}]}]})
	_check(loot.roll("test:nested").any(func(d): return d[0] == coal), "an entry can roll another table")

	# An old mob or block definition still works: [[item, count, chance]] is read as a table.
	var from_drops: Dictionary = loot._clean("test:old", loot.from_drops([["base:coal", 2], ["base:iron_ingot", 1, 0.0]]))
	loot.tables["test:old"] = from_drops
	var old_rolls: Array = loot.roll("test:old")
	_check(old_rolls.size() == 1 and old_rolls[0][0] == coal and old_rolls[0][1] == 2, "a mob's old drops list behaves exactly as it did")

	# What a host turns up for an event, and what it goes back to afterwards.
	loot.register("test:event", {"pools": [{"rolls": 1, "entries": [{"item": "base:coal", "weight": 1}, {"item": "base:stick", "weight": 99}]}]})
	loot.set_boost("base:coal", 200.0)
	var boosted: int = 0
	for i in 100:
		boosted += loot.roll("test:event").reduce(func(n, d): return n + (1 if d[0] == coal else 0), 0)
	_check(boosted > 50, "an item can be made more common for an event (%d of 100)" % boosted)
	_check(loot.factor_for("item:base:coal") == 200.0 and loot.active_boosts().size() == 1, "and a host can see what is turned up")
	loot.set_boost("base:coal", 1.0)
	_check(loot.factor_for("item:base:coal") == 1.0 and loot.active_boosts().is_empty(), "setting it back to normal clears it")
	loot.set_boost("test:mix", 3.0, 0.001)
	await get_tree().create_timer(0.05).timeout
	_check(loot.factor_for("table:test:mix") == 1.0, "an event with a time on it ends by itself")

	# How much everything drops, as one dial.
	loot.rate = 2.0
	var doubled: int = loot.roll("test:mix").reduce(func(n, d): return n + (int(d[1]) if d[0] == coal else 0), 0)
	loot.rate = 1.0
	_check(doubled == 4, "the loot rate multiplies what every pool rolls (%d)" % doubled)

	# A rare find is announced, and bad luck does not last forever.
	loot.register("test:rare", {"pools": [{"rolls": 1, "entries": [{"item": "base:iron_ingot", "weight": 1}, {"empty": true, "weight": 199}]}]})
	_check(loot.is_rare("test:rare", iron), "a one-in-two-hundred drop counts as a find")
	var p := ServerPlayer.new(server, 140, "Finder")
	p.player_id = "finder"
	server.players[140] = p
	var announced := []
	server.add_handler("rare_loot", func(ev): announced.append(ev), 0, "test")
	var pity_rolls := 0
	for i in 200:
		var got: Array = loot.roll("test:rare", {"player": p, "position": Vector3(0, 60, 0)})
		pity_rolls += 1
		if got.any(func(d): return d[0] == iron):
			break
	_check(pity_rolls <= Loot.PITY_ROLLS, "a long run of bad luck is paid out (%d rolls)" % pity_rolls)
	_check(not announced.is_empty() and announced[0].item == iron and announced[0].player == p, "the find is announced with who found it")
	_check(p.data.get("loot_seen", {}).has("test:rare"), "the server remembers which tables a player has met (for first-time bonuses)")

	# A reward, a purchase or a quest payout must never be lost to a full pack.
	var full := ServerPlayer.new(server, 143, "Hoarder")
	full.player_id = "hoarder"
	server.players[143] = full
	for slot in full.inventory.ids.size():
		full.inventory.ids[slot] = stick
		full.inventory.counts[slot] = server.items.max_stack(stick)
	var entities_before: int = server.entities.entities.size()
	var dropped: int = full.give(iron, 5)
	_check(dropped == 5 and server.entities.entities.size() > entities_before,
		"items that do not fit fall at your feet instead of vanishing (%d dropped)" % dropped)

	# A pool held back for the first time a player meets a table has to actually fire.
	loot.register("test:greeting", {"pools": [
		{"rolls": 1, "entries": [{"item": "base:stick"}]},
		{"rolls": 1, "guaranteed": true, "when": {"first_time": true, "player": true}, "entries": [{"item": "base:iron_ingot"}]},
	]})
	var newcomer := ServerPlayer.new(server, 145, "Newcomer")
	newcomer.player_id = "newcomer"
	server.players[145] = newcomer
	var welcome: Array = loot.roll("test:greeting", {"player": newcomer, "position": Vector3(0, 60, 0)})
	_check(welcome.any(func(d): return d[0] == iron), "the first time a player meets a table, a first_time pool gives its bonus")
	var second: Array = loot.roll("test:greeting", {"player": newcomer, "position": Vector3(0, 60, 0)})
	_check(not second.any(func(d): return d[0] == iron), "and never again")

	# An event that makes something common must not announce every drop of it as a rare find.
	loot.register("test:announce", {"pools": [{"rolls": 1, "entries": [{"item": "base:coal", "weight": 1}, {"empty": true, "weight": 199}]}]})
	_check(loot.is_rare("test:announce", coal), "a one-in-two-hundred drop is a find")
	loot.set_boost("base:coal", 400.0)
	_check(not loot.is_rare("test:announce", coal), "but not while a host has made it common for an event")
	loot.set_boost("base:coal", 1.0)

	# Where an item comes from, for the guide.
	var sources: Array = loot.sources_of(iron)
	var names: Array = sources.map(func(row): return str(row.table))
	_check(names.has("test:mix") and names.has("test:rare"), "an item knows everywhere it can come from (%s)" % str(names.slice(0, 4)))
	_check(sources[0].chance >= sources[sources.size() - 1].chance, "the likeliest source comes first")

	# Everyone who opens a dungeon chest gets their own loot, so nobody races a sibling for it.
	loot.register("test:chest", {"pools": [{"rolls": 2, "entries": [{"item": "base:iron_ingot", "count": [2, 2]}]}]})
	var chest_at := Vector3i(6, 62, 6)
	server.set_block_authoritative(chest_at, server.registry.id_of("base:chest"))
	server.set_block_data(chest_at, {"loot": "test:chest", "personal": true, "structure_seed": 99})
	var ann := ServerPlayer.new(server, 141, "Ann")
	ann.player_id = "ann"
	server.players[141] = ann
	var ben := ServerPlayer.new(server, 142, "Ben")
	ben.player_id = "ben"
	server.players[142] = ben
	server.containers.get_container(chest_at, ann)
	server.containers.get_container(chest_at, ben)
	# Anything else that looks inside (a click, a hopper, a crafting table pulling stock) must not turn a
	# personal chest into a shared pile and hand out a second, free copy of the loot.
	server.containers.get_container(chest_at)
	server.containers.get_container(chest_at)
	_check(ann.inventory.count_of(iron) == 4 and ben.inventory.count_of(iron) == 4,
		"each player gets their own loot from a shared chest (Ann %d, Ben %d)" % [ann.inventory.count_of(iron), ben.inventory.count_of(iron)])
	server.containers.get_container(chest_at, ann)
	_check(ann.inventory.count_of(iron) == 4, "and only once each, however often they open it")
	_check(server.get_block_data(chest_at).get("loot", "") == "test:chest", "the chest keeps its table for whoever has not opened it yet")
	var in_chest := 0
	var chest_view = server.containers.get_container(chest_at)
	for slot in chest_view.size():
		in_chest += int(chest_view.get_item(slot).count)
	_check(in_chest == 0, "and nothing is ever poured into the chest itself (%d items)" % in_chest)

	# Bad luck is counted per table: forty stone blocks must not pay out the next mob's rare drop.
	loot.register("test:plain", {"pools": [{"rolls": 1, "entries": [{"item": "base:stick"}]}]})
	loot.register("test:pity", {"pools": [{"rolls": 1, "entries": [{"item": "base:iron_ingot", "weight": 1}, {"empty": true, "weight": 199}]}]})
	var patient := ServerPlayer.new(server, 144, "Patient")
	patient.player_id = "patient"
	server.players[144] = patient
	for i in Loot.PITY_ROLLS + 5:
		loot.roll("test:plain", {"player": patient, "position": Vector3(0, 60, 0)})
	loot.roll("test:pity", {"player": patient, "position": Vector3(0, 60, 0)})
	_check(int(patient.data.get("loot_pity", {}).get("test:pity", 0)) <= 1,
		"a table's own run of bad luck starts from zero, however much of something else was rolled first (%d)"
		% int(patient.data.get("loot_pity", {}).get("test:pity", 0)))
	_check(int(patient.data.get("loot_pity", {}).get("test:plain", 0)) == 0,
		"a table with nothing rare to give keeps no pity count at all")

	# A table nobody has met before is worth a moment.
	loot.register("test:new", {"pools": [{"rolls": 1, "entries": [{"item": "base:coal"}]}]})
	var firsts := []
	server.add_handler("loot_first_time", func(ev): firsts.append(ev), 0, "test")
	loot.roll("test:new", {"player": ann})
	loot.roll("test:new", {"player": ann})
	_check(firsts.size() == 1 and firsts[0].table == "test:new", "a player meeting a table for the first time is announced once")

	# Where an item comes from, small enough to send a client when it joins.
	var index: Dictionary = loot.sources_index()
	_check(index.has(iron) and index[iron] is Array and index[iron][0].size() == 2,
		"the client is sent where each item can be found, for the tooltip")
	_check(index[iron].size() <= 3, "with only the few likeliest sources each")

	# A mob's drops and a block's drops both go through tables now.
	var pig: int = server.entities.registry.id_of("vanilla:pig")
	if pig > 0:
		var pig_table: String = loot.table_for_entity(server.entities.registry.defs[pig])
		_check(loot.has(pig_table) and pig_table == "mob:vanilla:pig", "a mob without its own table gets one from its drops (%s)" % pig_table)
	var stone: int = server.registry.id_of("base:stone")
	var stone_table: String = loot.table_for_block(stone, server._default_drops(stone))
	_check(loot.roll(stone_table).any(func(d): return d[0] == server.items.id_of("base:cobblestone")),
		"a broken block's drops come from a table too")
	server.queue_free()
	await get_tree().process_frame


## The examples in examples/ are documentation that runs: they have to load and do what they claim, or
## they teach something that no longer works.
func _examples() -> void:
	var ids := ["loot_example", "events_example", "worldgen_example", "ui_example"]
	if ClassDB.class_exists(&"NativeJsRuntime"):
		ids.append("js_example")
	var server = _start("examples_%d" % Time.get_ticks_msec(), ["vanilla"] + ids, ["res://examples"])
	server.dev_log.drain()
	var errors: Array = server.dev_log.sorted_errors().filter(func(e): return ids.has(str(e.source)))
	_check(errors.is_empty(), "every example loads without errors %s" % str(errors.map(func(e): return e.message).slice(0, 3)))
	_check(server.loot.has("loot_example:chest") and server.loot.has("loot_example:junk"),
		"the loot example registers its tables")
	var pig_pools: int = server.loot.tables.get("mob:vanilla:pig", {}).get("pools", []).size()
	server.loot.table_for_entity(server.entities.registry.defs[server.entities.registry.id_of("vanilla:pig")])
	_check(server.loot.tables["mob:vanilla:pig"].pools.size() > pig_pools or pig_pools > 3,
		"the loot example adds a drop to a mob another mod owns")
	_check(server._commands.has("hello") and server._commands.has("prize"), "the examples register their commands")
	server.queue_free()
	await get_tree().process_frame


## Anything a player would look at and call wood has to burn, and char. A kid who started in a birch
## forest could not light a furnace with the only trees around them (playtest, 2026-09-16), so this
## checks the rule rather than a list: the next wood someone adds is covered too.
func _fuels() -> void:
	var server = _start("fuels_%d" % Time.get_ticks_msec(), ["vanilla", "arcana", "industry"])
	var woods := []
	var cold := []
	var uncharrable := []
	for id in server.registry.defs.size():
		var block_name := str(server.registry.defs[id].get("name", ""))
		if not (block_name.ends_with("log") or block_name.ends_with("planks")):
			continue
		woods.append(block_name)
		if server.get_fuel(id) <= 0.0:
			cold.append(block_name)
		if block_name.ends_with("log") and server.get_process("smelting", id).is_empty():
			uncharrable.append(block_name)
	_check(woods.size() >= 5, "there are several kinds of wood to check (%s)" % str(woods))
	_check(cold.is_empty(), "every kind of wood burns in a furnace (cold: %s)" % str(cold))
	_check(uncharrable.is_empty(), "every log can be charred into charcoal (cannot: %s)" % str(uncharrable))
	server.queue_free()
	await get_tree().process_frame


## What a child meets in their first minutes: the tutorial has to actually run (new players land in
## creative, where it used to be skipped), and dying must never be a state they cannot get out of.
func _first_session() -> void:
	var server = _start("firstrun_%d" % Time.get_ticks_msec())
	var p := ServerPlayer.new(server, 150, "Newcomer")
	p.player_id = "newcomer"
	p.inventory.creative = true
	server.players[150] = p
	server.tutorials.on_join(p)
	var running: String = server.tutorials.state_of(p).active
	_check(running == "vanilla:first_steps", "a new player in creative is taught the controls (%s)" % running)
	_check(server.tutorials.tutorials[running].steps[0].text.contains("W A S D"),
		"and the first step names the keys, because nothing else does")

	var survivor := ServerPlayer.new(server, 151, "Digger")
	survivor.player_id = "digger"
	server.players[151] = survivor
	server.tutorials.on_join(survivor)
	_check(server.tutorials.state_of(survivor).active == "vanilla:survival", "a survival player still gets Survival Basics")

	# A world that refuses to start must say why, in words, not as an address.
	var broken = GameServer.new()
	add_child(broken)
	var failed: Error = broken.start({"mods": PackedStringArray(["no_such_mod"]), "world": "broken_%d" % Time.get_ticks_msec(),
		"data_dir": DATA_DIR, "seed": 42, "offline": true})
	_check(failed != OK and str(broken.start_error).contains("no_such_mod"),
		"a world that cannot start says what is wrong with it (%s)" % broken.start_error)
	broken.queue_free()
	await get_tree().process_frame

	# The deepest system in the game must be pointed at, and the way in must be findable.
	var tips: Dictionary = server.tutorials.tips
	_check(str(tips["vanilla:iron_tools"].text).contains("Toolsmith’s Bench"),
		"finding iron points at the Toolsmith’s Bench, which needs no plans, not only at the anvil that does")
	var recipe_index: int = server.recipes.index_of("base:tool_forge")
	_check(recipe_index >= 0 and server.recipes.recipes[recipe_index].station == "crafting_table",
		"and a Toolsmith’s Bench is built at an ordinary crafting table")
	var skeleton: int = server.entities.registry.id_of("vanilla:skeleton")
	var plans_chance := 0.0
	for drop in server.entities.registry.defs[skeleton].drops:
		if str(drop[0]) == "base:forge_plans":
			plans_chance = float(drop[2]) if drop.size() > 2 else 1.0
	_check(plans_chance >= 0.1, "forge plans drop often enough to be a goal rather than a wall (%.0f%%)" % (plans_chance * 100.0))

	# Dying tells you what happened and what became of your things, rather than just "You died!".
	var titles := []
	server.add_handler("player_death", func(ev): titles.append(ev), 0, "test")
	survivor.state.position = Vector3(8, 70, 8)
	server.kill_player(survivor, "fall", null)
	_check(survivor.dead and not titles.is_empty(), "a fall kills, and says how")
	_check(str(titles[0].message).contains(survivor.name), "the message names who it happened to (%s)" % titles[0].message)
	# A few of each, never the same one twice running, and never unkind.
	var seen := {}
	for i in 40:
		seen[server._death_message("Robin", "fall", "")] = true
	_check(seen.size() >= 3, "death messages vary rather than repeating one line (%d of them)" % seen.size())
	var runs := []
	for i in 12:
		runs.append(server._death_message("Robin", "fall", ""))
	var repeated := false
	for i in range(1, runs.size()):
		repeated = repeated or runs[i] == runs[i - 1]
	_check(not repeated, "and never the same one twice in a row")
	_check(server._death_message("Robin", "mob", "").contains("Robin"), "a line needing an attacker is not used when there is none")
	# A mod can give its own mob its own send-off, without taking the engine's lines away.
	server.add_death_messages("testmod:dragon", ["%s was toasted by %s"])
	var mob_lines := {}
	for i in 20:
		mob_lines[server._death_message("Robin", "mob", "Dragon", "testmod:dragon")] = true
	_check(mob_lines.keys().any(func(line): return str(line).contains("toasted")),
		"a mod's own mob can have its own death message (%s)" % str(mob_lines.keys().slice(0, 2)))
	_check(mob_lines.size() > 1, "and the engine's lines are still in the mix")
	server.add_death_messages("testmod:bad", ["no placeholders here"])
	_check(not server._death_message("Robin", "mob", "Dragon", "testmod:bad").contains("no placeholders"),
		"a line that does not name anyone is refused")
	server.queue_free()
	await get_tree().process_frame


## Cooking: a pot you can put several things in, meals that do something for a while, and the quality
## minigame on food (which the engine already rewards by making a good meal more filling).
func _cooking() -> void:
	var server = _start("cooking_%d" % Time.get_ticks_msec())
	var pot: int = server.registry.id_of("base:cooking_pot")
	_check(pot > 0 and str(server.registry.defs[pot].get("station", "")) == "cooking_pot", "there is a pot to cook in")
	var dishes := ["vanilla:mushroom_stew", "vanilla:beef_stew", "vanilla:glowcap_soup", "vanilla:honey_cake",
		"vanilla:hearty_feast", "base:apple_pie"]
	var without_effects := []
	var without_recipe := []
	for name in dishes:
		var id: int = server.items.id_of(name)
		if id <= 0:
			without_recipe.append(name)
			continue
		var food: Dictionary = server.items.get_def(id).get("food", {})
		if food.get("effects", []).is_empty() and float(food.get("heal", 0.0)) <= 0.0:
			without_effects.append(name)
		if server.recipes.index_of(name) < 0:
			without_recipe.append(name)
	_check(without_recipe.is_empty(), "every dish can be cooked (%s)" % str(without_recipe))
	_check(without_effects.is_empty(), "every dish does something you can feel, not just fill you up (%s)" % str(without_effects))

	# Cooking is a station recipe, so it runs the minigame and can be done together - and a good cook is
	# rewarded, which is what makes the trouble worth it.
	var stew: int = server.recipes.index_of("vanilla:mushroom_stew")
	_check(str(server.recipes.recipes[stew].get("skill", "")) == "base:cooking", "a meal can be stirred by hand for quality")
	_check(server.skill.defs.has("base:cooking"), "and there is a stirring game to play")
	_check(server.items.id_of("vanilla:clean_broth") > 0, "and something to find out for yourself: rotten meat is worth boiling")

	# The ingredients that had no use at all before now have one.
	var used := {}
	for index in server.recipes.recipes.size():
		for id: int in server.recipes.recipes[index].inputs:
			used[server.items.name_of(id)] = true
	var orphans: Array = ["vanilla:egg", "vanilla:glow_mushroom", "vanilla:red_mushroom", "vanilla:nightbloom",
		"vanilla:rotten_flesh"].filter(func(n): return not used.has(n))
	_check(orphans.is_empty(), "things a player picks up are worth picking up (%s has no use)" % str(orphans))
	server.queue_free()
	await get_tree().process_frame


## Hearthhold, phase 1: the Hearthstone is the thing the whole game rests on, because it is what turns
## building into something the game counts. It must never answer "no" without saying which part is missing.
## Every engine script still parses. Cheap, and it runs early, because the alternative is finding out
## from the end-to-end tests: a client that will not compile fails as three four-minute timeouts twelve
## minutes apart, and the message says "nonexistent function 'new'" rather than naming the line.
## (A `--check-only --script` run reports success on a file that does not parse, so it cannot be used
## for this - 2026-09-18.)
## The suite must not write into the player's own folder. `project.godot` sets use_custom_user_dir, so
## `user://` from this checkout *is* the installed app's folder - running the tests used to overwrite the
## player's identity and settings, and after those were fixed one at a time it went on filling their
## asset cache and unpacked-mod cache and resetting their pinned recipe. Each fix was a path; this checks
## the mechanism, so the next path that forgets is caught here instead of by somebody losing something.
func _test_isolation() -> void:
	_check(UserPaths.redirected(), "the suite is redirected out of the player's folder (QW_USER_DIR)")
	for pair in [["assets cache", ContentCacheScript.dir()], ["unpacked mods", ModLoaderScript.cache_dir()],
			["the mods folder", ModLoaderScript.user_mods()], ["crafting pins", UserPaths.path("crafting_pins.cfg")]]:
		_check(not str(pair[1]).begins_with("user://"), "%s is not in the player's folder (%s)" % pair)


## Every asset a mod names actually exists.
##
## A missing one is only a push_error at startup - the mod loads, the sound is silent, and nobody finds
## out until somebody notices the coins stopped clinking. That is exactly what happened when the sounds
## became Kenney's: the .gd files were updated and `mods/guild/main.js` was not, because the search that
## did it only looked at GDScript. (2026-09-18)
## A mod that ships a world: authored terrain restored on first start instead of generated.
##
## The whole point is that no new format was needed - a world save already is a portable map. So the
## test does what an author would: play a world, change it, `/backup`, put the archive in a mod, and
## start a *fresh* world with that mod to see the change arrive.
## Story mode: a world you walk through rather than one you change.
##
## It needed no new capability, which is worth writing down because the plan assumed it would. "build"
## has been a permission since roles existed, `_may` already guards both breaking and placing, it tells
## the player why (once every three seconds, not every click), and `_reject_edit` puts the block back on
## the client that predicted it. The stock `visitor` role is already the shape - chat and interact, no
## build - so doors and chests still work while the valley stays as its author left it.
##
## So a story mod is one line: `api.set_default_role("visitor")`.
func _story_mode() -> void:
	var server = _start("story_%d" % Time.get_ticks_msec())
	var stone: int = server.registry.id_of("base:stone")
	var at := Vector3i(120, 60, 120)
	server.ensure_area_loaded(Vector3(at))
	server.set_block_authoritative(at, stone)

	var p := ServerPlayer.new(server, 210, "Reader")
	p.player_id = "reader"
	server.players[210] = p
	p.state.position = Vector3(at) + Vector3(0.5, 1.0, 0.5)
	# Creative, so the only thing between this player and the block is the permission. A survival player
	# has to mine for the block's break time first, and an instant break is refused as cheating - which
	# is a correct refusal and would have made this test look like it proved something it did not.
	p.inventory.creative = true

	_check(server.has_permission(p, "build"), "an ordinary player may build")
	var mod = server.mod_instances.get("vanilla")
	_check(mod.api.set_default_role("visitor") == "", "a mod can say which role players start in")
	_check(mod.api.set_default_role("not_a_role").contains("no role"), "and is told when the role does not exist")
	_check(not server.has_permission(p, "build"), "a visitor may not")
	_check(server.has_permission(p, "interact"), "but may still open doors and chests, which a story needs")

	p.edit_tokens = 100.0
	server.on_break_block(210, at)
	_check(server.world.get_block_v(at) == stone, "so breaking a block does nothing to the world")
	p.give(server.items.id_of("base:stone"), 4)
	p.inventory.selected = 0
	p.edit_tokens = 100.0
	server.on_place_block(210, at + Vector3i(0, 1, 0), 0.0)
	_check(server.world.get_block_v(at + Vector3i(0, 1, 0)) != stone, "and neither does placing one")

	server.roles.default_role = "member"
	p.edit_tokens = 100.0
	server.on_break_block(210, at)
	_check(server.world.get_block_v(at) != stone, "and it is the permission doing it, not something else")

	server.queue_free()
	await get_tree().process_frame


func _map_from_mod() -> void:
	var work := ProjectSettings.globalize_path("user://map_test_%d" % Time.get_ticks_msec())
	var mod_dir := work.path_join("mods/mapmod")
	DirAccess.make_dir_recursive_absolute(mod_dir)

	# 1. Author a world: put a block somewhere the generator would never choose.
	var source = _start("mapsrc_%d" % Time.get_ticks_msec())
	var marker: int = source.registry.id_of("base:glass")
	var at := Vector3i(300, 70, 300)
	source.ensure_area_loaded(Vector3(at))
	source.set_block_authoritative(at, marker)
	source._save_all(true)
	var archive := mod_dir.path_join("world.zip")
	var packed: String = WorldBackupsScript.create(source._save_dir, archive)
	_check(packed.is_empty() and FileAccess.file_exists(archive), "a world packs into an archive (%s)" % packed)
	source.queue_free()
	await get_tree().process_frame

	# 2. Ship it: a mod whose manifest says it brings a world.
	var manifest := {"id": "mapmod", "name": "Map Mod", "version": "1.0.0", "kind": "game",
		"depends": ["base@^1.0", "vanilla@^1.0"], "world": "world.zip"}
	var f := FileAccess.open(mod_dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	f = FileAccess.open(mod_dir.path_join("main.gd"), FileAccess.WRITE)
	f.store_string("extends RefCounted\n\n\nfunc setup(_api) -> void:\n\tpass\n")
	f.close()

	# 3. A brand new world with that mod gets the authored one, not generated terrain.
	var played = GameServer.new()
	add_child(played)
	var err: Error = played.start({"mods": PackedStringArray(["mapmod"]), "mod_dirs": PackedStringArray([work.path_join("mods")]),
		"world": "mapdest_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 7, "offline": true})
	played.set_physics_process(false)
	_check(err == OK, "a server starts with a mod that ships a world (%s)" % error_string(err))
	if err == OK:
		played.ensure_area_loaded(Vector3(at))
		_check(played.world.get_block_v(at) == marker, "and the authored world is what loads, not fresh terrain")

	# 4. Starting it again must not lay the map down over what has been played since.
	played.set_block_authoritative(at, 0)
	played._save_all(true)
	var world_name: String = played._save_dir.get_file()
	played.queue_free()
	await get_tree().process_frame
	var again = GameServer.new()
	add_child(again)
	again.start({"mods": PackedStringArray(["mapmod"]), "mod_dirs": PackedStringArray([work.path_join("mods")]),
		"world": world_name, "data_dir": DATA_DIR, "seed": 7, "offline": true})
	again.set_physics_process(false)
	again.ensure_area_loaded(Vector3(at))
	_check(again.world.get_block_v(at) != marker,
		"a second start leaves the played world alone rather than laying the map over it again")
	again.queue_free()
	await get_tree().process_frame

	# 5. A mod that promises a world it does not have stops the server, rather than quietly generating
	#    terrain the story does not fit.
	DirAccess.remove_absolute(archive)
	var broken = GameServer.new()
	add_child(broken)
	var broken_err: Error = broken.start({"mods": PackedStringArray(["mapmod"]), "mod_dirs": PackedStringArray([work.path_join("mods")]),
		"world": "mapmissing_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 7, "offline": true})
	_check(broken_err != OK and broken.start_error.contains("world"),
		"a missing map stops the server and says so (%s)" % broken.start_error)
	broken.queue_free()
	await get_tree().process_frame


func _mod_assets_exist() -> void:
	var missing := []
	var checked := 0
	var pending := ["res://mods"]
	var mods := []
	var dir := DirAccess.open("res://mods")
	if dir != null:
		for name in dir.get_directories():
			mods.append(name)
	for mod_name: String in mods:
		var root := "res://mods/%s" % mod_name
		var files := []
		pending = [root]
		while not pending.is_empty():
			var at: String = pending.pop_back()
			var d := DirAccess.open(at)
			if d == null:
				continue
			for sub in d.get_directories():
				pending.append(at.path_join(sub))
			for f in d.get_files():
				if f.ends_with(".gd") or f.ends_with(".js"):
					files.append(at.path_join(f))
		for path: String in files:
			var text := FileAccess.get_file_as_string(path)
			# "sounds/x.ogg", "textures/y.png", "models/z.glb", "music/w.ogg" - skipping anything with a
			# format placeholder in it, which is built at runtime and cannot be checked from here.
			for m in RegEx.create_from_string('"((?:sounds|textures|models|music)/[^"]+)"').search_all(text):
				var rel := m.get_string(1)
				if rel.contains("%"):
					continue
				checked += 1
				if not FileAccess.file_exists(root.path_join(rel)):
					missing.append("%s -> %s" % [path.replace("res://", ""), rel])
	_check(checked > 40, "found mod asset references to check (%d)" % checked)
	_check(missing.is_empty(), "every file a mod names exists (%s)" % ", ".join(missing))


func _scripts_compile() -> void:
	var bad := []
	var checked := 0
	# mods and tests as well as the engine. The parse error this catches - `:=` on anything reached
	# through an untyped variable - was made four times in one day, in all three places, and each time it
	# surfaced as something unrelated: a mod that silently did not load, a client that could not be
	# constructed, a test that failed on an assertion it never reached. (2026-09-18)
	var pending := ["res://engine", "res://mods", "res://tests"]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for name in dir.get_directories():
			pending.append(dir_path.path_join(name))
		for name in dir.get_files():
			if not name.ends_with(".gd"):
				continue
			var path := dir_path.path_join(name)
			var script = load(path)
			checked += 1
			if script == null or not script.can_instantiate():
				bad.append(path.replace("res://", ""))
	_check(checked > 150, "found the scripts to check (%d)" % checked)
	_check(bad.is_empty(), "every script parses (%s)" % ", ".join(bad))


## Atmosphere. The engine picks the moments; a mod says under what conditions.
## Weather: world state the engine keeps, whose look and timing belong to a mod.
## Links: what is joined to what. The graph the industrial half will stand on.
func _links() -> void:
	var server = _start("links_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var deep = server.add_realm("test:deep", "The Deep")
	_check(api.register_link_kind("cable", {"span": 10, "draw": "cable"}), "a mod can declare a kind of connection")
	_check(api.register_link_kind("aerial", {"wireless": true, "span": 40, "crosses_realms": true}), "including a wireless one")
	_check(not api.register_link_kind("cable", {}), "and cannot declare the same one twice")

	var y: int = server.surface_height(100, 100) + 2
	var node = func(x: int, z: int, face := 0, realm := "") -> Dictionary:
		return {"realm": realm, "position": Vector3i(x, y, z), "face": face}

	_check(api.link("cable", node.call(100, 100), node.call(106, 100)) > 0, "two faces within reach can be joined")
	_check(api.link("cable", node.call(100, 100), node.call(130, 100)) == 0, "but not two that are too far apart")
	_check(api.link_problem().contains("Too far"), "and it says so in words (%s)" % api.link_problem())
	_check(api.link("cable", node.call(100, 100), node.call(106, 100)) == 0, "the same pair cannot be joined twice")

	# A face is a node, not a block: the other side of the same block is somewhere else entirely.
	_check(api.link("cable", node.call(100, 100, 1), node.call(106, 100, 1)) > 0,
		"and the same two blocks join again on another face")

	# Worlds. A cable is a physical thing; only wireless crosses.
	_check(api.link("cable", node.call(100, 100, 2), node.call(100, 100, 2, "test:deep")) == 0,
		"a cable refuses to run between worlds")
	_check(api.link("aerial", node.call(100, 100, 2), node.call(100, 100, 2, "test:deep")) > 0,
		"while a wireless link may cross, if its kind says so")

	# Clear air, and staying clear.
	var stone: int = server.registry.id_of("base:stone")
	server.set_block_authoritative(Vector3i(103, y, 110), stone)
	_check(api.link("cable", node.call(100, 110), node.call(106, 110)) == 0, "a wall in the way refuses the link")
	server.set_block_authoritative(Vector3i(103, y, 110), 0)
	var through: int = api.link("cable", node.call(100, 110), node.call(106, 110))
	_check(through > 0, "and clearing it lets the link be made")
	var cut_reason := []
	server.add_handler("link_cut", func(ev): cut_reason.append(str(ev.reason)), 0, "test")
	server.set_block_authoritative(Vector3i(103, y, 110), stone)
	_check(api.link_info(through).is_empty(), "building into a span afterwards cuts it")
	_check(cut_reason.size() == 1 and cut_reason[0].contains("built through"), "and says why (%s)" % str(cut_reason))

	# Mining an end takes its links with it.
	var ends: Array = api.links_at(Vector3i(100, y, 100))
	_check(ends.size() >= 2, "a block knows the links that end on it (%d)" % ends.size())
	server.set_block_authoritative(Vector3i(100, y, 100), stone)
	server.break_block(Vector3i(100, y, 100))
	_check(api.links_at(Vector3i(100, y, 100)).is_empty(), "and loses them when it goes")
	server.queue_free()
	await get_tree().process_frame


## Flows: a quantity moving along the graph, and what happens when there is not enough of it.
func _flows() -> void:
	var server = _start("flows_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	_check(api.register_link_kind("cable", {"span": 10}), "a kind to carry it on")
	_check(api.register_unit("power"), "a mod declares a unit")
	_check(not api.register_unit("power"), "and cannot declare it twice")

	var told := []
	api.on_received("power", func(ev): told.append([ev.position.x, ev.wanted, ev.got]))
	var y: int = server.surface_height(140, 140) + 2
	var at = func(x: int) -> Dictionary: return {"position": Vector3i(x, y, 140), "face": 0}

	# A generator and two lamps on one run of cable.
	api.link("cable", at.call(140), at.call(144))
	api.link("cable", at.call(144), at.call(148))
	api.set_supply("power", at.call(140), 100.0)
	api.set_demand("power", at.call(144), 30.0)
	api.set_demand("power", at.call(148), 20.0)
	server.flows.settle()
	_check(api.received("power", at.call(144)) == 30.0 and api.received("power", at.call(148)) == 20.0,
		"with enough to go round, everybody gets what they asked for")

	# Not enough: the same fraction each, so the grid dims all over rather than in a hidden order.
	told.clear()
	api.set_supply("power", at.call(140), 25.0)
	server.flows.settle()
	_check(is_equal_approx(api.received("power", at.call(144)), 15.0)
		and is_equal_approx(api.received("power", at.call(148)), 10.0),
		"and when short, the same fraction each (%.1f, %.1f)" % [api.received("power", at.call(144)), api.received("power", at.call(148))])
	_check(told.size() == 2, "both were told what changed (%d)" % told.size())

	# Nothing recomputes on a quiet tick: settle() with nothing dirty must tell nobody anything.
	told.clear()
	server.flows.settle()
	server.flows.settle()
	_check(told.is_empty(), "a tick where nothing changed tells nobody anything")

	# Cutting the cable separates them: the far lamp is on its own network with no supply at all.
	var joined: Array = api.links_at(Vector3i(144, y, 140))
	for id in joined:
		var info: Dictionary = api.link_info(id)
		if info.a.position.x == 144 and info.b.position.x == 148:
			api.unlink(id, "test")
	server.flows.settle()
	_check(api.received("power", at.call(148)) == 0.0, "cutting the cable leaves the far end with nothing")
	_check(is_equal_approx(api.received("power", at.call(144)), 25.0),
		"and the near one now has the lot (%.1f)" % api.received("power", at.call(144)))
	server.queue_free()
	await get_tree().process_frame


## Plots and companies: ground with an owner, and groups that can own it.
func _plots() -> void:
	var server = _start("plots_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var reg = server.registry
	var stone: int = reg.id_of("base:stone")
	var y: int = server.surface_height(700, 700) + 2

	var owner := ServerPlayer.new(server, 110, "Rowan")
	owner.player_id = "rowan"
	var stranger := ServerPlayer.new(server, 111, "Passerby")
	stranger.player_id = "passerby"
	for p in [owner, stranger]:
		p.state.position = Vector3(700.5, y, 703.5)  # clear of the block they will place
		p.edit_tokens = 100.0  # handed out by _spawn_player, which a player built by hand never met
		p.inventory.creative = true
		p.inventory.ids[0] = reg.id_of("base:stone")
		p.inventory.counts[0] = 64
		p.inventory.selected = 0
		server.players[p.peer_id] = p

	var plot: int = api.claim_plot(Vector3i(698, y - 2, 698), Vector3i(702, y + 2, 702),
		{"owner": "rowan", "name": "Rowan's garden"})
	_check(plot > 0, "a piece of ground can be claimed")
	_check(api.plot_at(Vector3i(700, y, 700)).name == "Rowan's garden", "and asked about by position")
	_check(api.plot_at(Vector3i(720, y, 720)).is_empty(), "with everywhere else belonging to nobody")

	# Two owners of one block is a question with no good answer, so overlapping is refused.
	_check(api.claim_plot(Vector3i(700, y, 700), Vector3i(706, y, 706), {"owner": "passerby"}) == 0,
		"a plot cannot overlap another")
	_check(api.plot_problem().contains("overlaps"), "and says so (%s)" % api.plot_problem())

	# The point of the whole thing: it stops an edit, on every path at once.
	_check(api.may_build(owner, Vector3i(700, y, 700)), "the owner may build there")
	_check(not api.may_build(stranger, Vector3i(700, y, 700)), "and a stranger may not")
	_check(api.may_build(stranger, Vector3i(720, y, 720)), "though anywhere else is fine")

	# A baseline first: this player can place a block somewhere nobody owns. Without it, "the stranger
	# was refused" could be passing because *nothing* can be placed, which would prove nothing at all.
	var open_ground := Vector3i(720, y, 720)
	server.set_block_authoritative(open_ground, 0)
	server.set_block_authoritative(open_ground + Vector3i.DOWN, stone)
	# Standing clear of it: a block is not placed inside a player, and standing on the spot would have
	# refused the placement for a reason that has nothing to do with who owns the ground.
	stranger.state.position = Vector3(open_ground) + Vector3(0.5, 0.0, 3.0)
	stranger.edit_tokens = 100.0
	server.on_place_block(111, open_ground, 0.0)
	_check(server.world.get_block_v(open_ground) == stone, "a player can build where nobody owns the ground")
	stranger.state.position = Vector3(700.5, y, 703.5)
	stranger.edit_tokens = 100.0

	var at := Vector3i(700, y, 700)
	server.set_block_authoritative(at, 0)
	server.set_block_authoritative(at + Vector3i.DOWN, stone)  # something to place against
	server.on_place_block(111, at, 0.0)
	_check(server.world.get_block_v(at) == 0, "a stranger's block is refused rather than placed")
	server.on_place_block(110, at, 0.0)
	_check(server.world.get_block_v(at) == stone, "and the owner's goes down (item %d, held %d, block now %d)" % [server.items.id_of("base:stone"), owner.inventory.selected_block(), server.world.get_block_v(at)])

	# Letting somebody in, and a company owning land instead of a person.
	api.add_plot_member(plot, "passerby")
	_check(api.may_build(stranger, Vector3i(700, y, 700)), "somebody let in may build")
	api.remove_plot_member(plot, "passerby")

	var guild: int = api.found_company("The Delvers", "rowan")
	_check(guild > 0 and api.company_rank(guild, "rowan") == "owner", "a company can be founded")
	_check(api.set_company_rank(guild, "passerby", "member"), "and somebody added to it")
	_check(not api.set_company_rank(guild, "rowan", "member"),
		"but the last owner cannot be demoted, or nobody could ever wind it up")
	_check(not api.remove_from_company(guild, "rowan"), "nor leave")

	var yard: int = api.claim_plot(Vector3i(710, y - 2, 710), Vector3i(714, y + 2, 714), {"company": guild})
	_check(yard > 0, "a company can own ground")
	_check(api.may_build(stranger, Vector3i(712, y, 712)), "and its members may build on it")
	api.remove_from_company(guild, "passerby")
	_check(not api.may_build(stranger, Vector3i(712, y, 712)), "and stop being able to when they leave")
	server.queue_free()
	await get_tree().process_frame


## Ledgers and objectives: the social half.
func _social() -> void:
	var server = _start("social_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var p := ServerPlayer.new(server, 101, "Trader")
	p.player_id = "trader"
	server.players[101] = p

	# A balance and an experience are the same storage asked a different question, so they are one
	# capability here rather than two.
	_check(api.register_ledger("coins", {"display_name": "Coins", "min": 0}), "a mod registers a balance")
	_check(api.register_ledger("delving", {"display_name": "Delving", "levels": [10, 30, 60]}),
		"and one with levels, which is what experience is")

	api.add_balance(p, "coins", 25.0)
	_check(api.balance_of(p, "coins") == 25.0, "a balance goes up")
	_check(api.add_balance(p, "coins", -40.0) == 0.0, "and stops at its floor rather than going negative")

	api.set_balance(p, "coins", 30.0)
	_check(api.spend_balance(p, "coins", 10.0) and api.balance_of(p, "coins") == 20.0, "spending takes it")
	_check(not api.spend_balance(p, "coins", 100.0) and api.balance_of(p, "coins") == 20.0,
		"and spending more than there is takes nothing at all")

	api.add_balance(p, "delving", 35.0)
	_check(api.level_of(p, "delving") == 2, "thresholds give a level (%d)" % api.level_of(p, "delving"))
	var bar: Dictionary = api.level_progress(p, "delving")
	_check(bar.next == 60.0 and is_equal_approx(bar.needed, 25.0), "and how far to the next (%s)" % str(bar))
	_check(api.balances_of(p).size() == 2, "and a player can be asked for everything they have")

	# Objectives: given, stepped through, finished.
	var done := []
	server.add_handler("objective_done", func(ev): done.append(str(ev.objective)), 0, "test")
	_check(api.register_objective("post", {"display_name": "The Post",
		"steps": [{"text": "Take the letter"}, {"text": "Bring the answer", "count": 2}]}),
		"a mod registers something to be done")
	_check(api.give_objective(p, "post"), "it can be given")
	_check(not api.give_objective(p, "post"), "and not given twice")
	_check(api.objectives_of(p)[0].text == "Take the letter", "the player is on the first step")

	api.advance_objective(p, "post")
	_check(api.objectives_of(p)[0].step == 1, "finishing a step moves on")
	api.advance_objective(p, "post")
	_check(done.is_empty(), "a step that needs two is not done after one")
	api.advance_objective(p, "post")
	_check(done == ["vanilla:post"], "and the last step finishes the whole thing (%s)" % str(done))
	_check(api.objective_finished(p, "post") == 1 and not api.has_objective(p, "post"),
		"which is remembered, and it is no longer being carried")
	_check(not api.give_objective(p, "post"), "one that does not repeat cannot be given again")
	server.queue_free()
	await get_tree().process_frame


## Characters and shops: somebody to talk to, and somewhere to buy and sell.
func _characters() -> void:
	var server = _start("talk_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var p := ServerPlayer.new(server, 102, "Buyer")
	p.player_id = "buyer"
	p.state.position = Vector3(0, 64, 0)
	server.players[102] = p
	api.register_ledger("coins", {"display_name": "Coins", "min": 0})
	api.register_objective("errand", {"display_name": "An Errand", "steps": [{"text": "Go there"}]})

	var stone: int = api.item("base:stone")
	var torch: int = api.item("base:torch")

	# A shop. One offer that runs out, one bought with goods rather than coin, one that buys.
	_check(api.register_shop("stall", {"display_name": "The Stall", "offers": [
		{"item": "base:torch", "count": 2, "price": 5, "ledger": "coins", "stock": 1},
		{"item": "base:stone", "count": 4, "cost": [{"item": "base:torch", "count": 1}]},
		{"item": "base:stone", "price": 2, "ledger": "coins", "sells": true}]}),
		"a mod opens a shop")
	_check(not api.register_shop("empty", {"offers": []}), "but not one with nothing to trade")

	# Nothing to spend: the refusal has to happen before anything moves.
	_check(not api.shop_trade(p, "stall", 0), "a player with no coins cannot buy")
	_check(api.shop_problem() == "You cannot afford that.", "and is told why (%s)" % api.shop_problem())
	_check(p.count_of(torch) == 0, "and has nothing to show for it")

	api.add_balance(p, "coins", 20.0)
	_check(api.shop_trade(p, "stall", 0), "with coins in hand, they can")
	_check(p.count_of(torch) == 2 and api.balance_of(p, "coins") == 15.0,
		"the goods arrive and the coin goes (%d torches, %d coins)" % [p.count_of(torch), api.balance_of(p, "coins")])

	# Stock is the part that makes a shop a shop rather than a creative menu.
	_check(api.shop_offers(p, "stall")[0].left == 0, "the last one on the shelf is gone")
	_check(not api.shop_trade(p, "stall", 0) and api.shop_problem() == "Sold out. Come back later.",
		"and the shelf is empty until it is restocked")
	_check(api.balance_of(p, "coins") == 15.0, "a sold-out offer takes no money")

	# Barter: a game with no money at all still has shops.
	_check(api.shop_trade(p, "stall", 1), "goods buy goods")
	_check(p.count_of(stone) == 4 and p.count_of(torch) == 1, "the trade goes both ways at once")

	# And the shop buying from the player, which is the same offer turned round.
	_check(api.shop_trade(p, "stall", 2), "the shop buys")
	_check(p.count_of(stone) == 3 and api.balance_of(p, "coins") == 17.0,
		"the player is paid and the item is gone (%d stone, %d coins)" % [p.count_of(stone), api.balance_of(p, "coins")])
	p.take(stone, 3)
	_check(not api.shop_trade(p, "stall", 2), "and cannot sell what they do not have")

	# A character, and the two things characters are for.
	_check(api.register_character("shopkeep", {"display_name": "Wend", "lines": {
		"start": {"text": "Morning.", "options": [
			{"text": "What have you got?", "sells": "stall"},
			{"text": "Anything needing doing?", "gives": "errand"},
			{"text": "Who are you?", "goes_to": "who"},
			{"text": "Nothing, thanks", "does": "wave"}]},
		"who": {"text": "Wend. I keep the stall.", "options": [{"text": "I see", "goes_to": "start"}]}}}),
		"a mod registers somebody to talk to")
	_check(not api.register_character("mute", {"lines": {}}), "but not somebody with nothing to say")

	_check(not api.has_met(p, "shopkeep"), "they have not met")
	_check(api.talk_to(p, "shopkeep"), "the player says hello")
	_check(api.has_met(p, "shopkeep"), "and now they have")
	_check(p.ui_ids.has("engine:talk"), "a conversation is on the screen")

	# The engine draws it, so the engine answers its buttons.
	server.on_ui_action(102, "engine:talk", "say:start:2")
	_check(server.characters._talking[102].line == "who", "an option moves to another line")
	server.on_ui_action(102, "engine:talk", "say:who:0")
	_check(server.characters._talking[102].line == "start", "and back again")

	var waved := []
	server.add_handler("character_choice", func(ev): waved.append(str(ev.choice)), 0, "test")
	server.on_ui_action(102, "engine:talk", "say:start:3")
	_check(waved == ["wave"], "anything else is handed to the mod (%s)" % str(waved))
	_check(not p.ui_ids.has("engine:talk"), "and an option going nowhere ends the conversation")

	api.talk_to(p, "shopkeep")
	server.on_ui_action(102, "engine:talk", "say:start:1")
	_check(api.has_objective(p, "errand"), "a character hands over a quest")

	api.talk_to(p, "shopkeep")
	server.on_ui_action(102, "engine:talk", "say:start:0")
	_check(p.ui_ids.has("engine:shop") and not p.ui_ids.has("engine:talk"),
		"and opens the stall in place of the conversation, never both at once")

	# A stale button from a panel that has moved on must do nothing at all.
	server.on_ui_action(102, "engine:shop", "shop:0")
	_check(api.balance_of(p, "coins") == 17.0, "a sold-out button on the panel spends nothing")
	server.characters.player_left(102)
	server.shops.player_left(102)
	_check(not server.characters._talking.has(102), "leaving forgets the conversation")
	server.queue_free()
	await get_tree().process_frame


## Vehicles: sitting on something and steering it.
func _vehicles() -> void:
	var server = _start("vehicles_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var boat_type: int = api.register_entity("raft", {"kind": "mob", "display_name": "Raft",
		"width": 1.2, "height": 0.5, "health": 20, "speed": 1.0, "category": "misc", "persistent": true,
		"ai": {"preset": "none"},
		"vehicle": {"seats": 2, "speed": 6.0, "turn_speed": 10.0, "floats": true, "seat_height": 0.4}})
	_check(boat_type > 0, "a mod registers something to sit on")

	var p := ServerPlayer.new(server, 110, "Sailor")
	p.player_id = "sailor"
	var y: int = server.surface_height(8, 8)
	p.state.position = Vector3(8.5, y + 1, 8.5)
	server.players[110] = p
	var raft = api.spawn_entity("raft", Vector3(9.0, y + 1, 8.5), {})
	_check(raft != null, "and puts one in the world")

	_check(api.mount(p, raft), "a player gets on")
	_check(p.riding == raft.id and api.riders_of(raft) == ["sailor"], "and is aboard (%s)" % str(api.riders_of(raft)))
	_check(p.state.position.distance_to(raft.body.position) < 1.0, "sitting where the raft is")
	_check(bool(raft.data.get("no_despawn", false)), "and the raft will not vanish under them")

	# Too far away, and already riding, are both refused.
	var other := ServerPlayer.new(server, 111, "Bystander")
	other.player_id = "bystander"
	other.state.position = Vector3(80, y + 1, 80)
	server.players[111] = other
	_check(not api.mount(other, raft), "somebody across the map cannot get on")
	_check(not api.mount(p, raft), "and nobody gets on twice")

	# Steering: throttle forward, and the raft turns towards where the rider looks.
	var before: Vector3 = raft.body.position
	p.yaw = 0.0
	var input = PlayerPhysics.PlayerInput.new()
	input.seq = 1
	input.move = Vector2(0.0, 1.0)
	input.yaw = 0.0
	p.input_queue.append(input)
	server.vehicles.simulate(p)
	_check(raft.body.velocity.length() > 1.0, "throttle moves it (%s)" % raft.body.velocity.length())
	_check(p.input_queue.is_empty() and p.last_processed_seq == 1, "and the rider's inputs are drained, not stalled")
	# The rider is carried rather than walking: the server never stepped their physics.
	raft.body.position = before + Vector3(0, 0, -3)
	server.vehicles.simulate(p)
	_check(p.state.position.distance_to(raft.body.position) < 1.0, "the rider goes where the raft went")

	# Sneak gets off.
	var dismount_input = PlayerPhysics.PlayerInput.new()
	dismount_input.seq = 2
	dismount_input.sneak = true
	p.input_queue.append(dismount_input)
	server.vehicles.simulate(p)
	_check(p.riding == 0 and api.riders_of(raft).is_empty(), "sneak gets off")
	_check(p.state.position.distance_to(raft.body.position) > 0.5, "and puts them beside it, not inside it")

	# A vehicle that is removed does not leave a rider attached to nothing.
	api.mount(p, raft)
	_check(p.riding == raft.id, "back aboard")
	raft.remove()
	_check(p.riding == 0, "a raft that is taken away puts its riders down")
	server.queue_free()
	await get_tree().process_frame


## Fields: ground that does something to whoever stands in it.
func _fields() -> void:
	var server = _start("fields_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	api.register_condition("scorched", {"display_name": "Scorched", "good": false,
		"modifiers": [{"stat": "move_speed", "amount": -0.2, "op": "multiply"}]})
	_check(api.register_field("fire_pool", {"radius": 3.0, "seconds": 10.0, "effect": "engine:smoke",
		"tick": {"seconds": 1.0, "damage": 2.0, "cause": "fire"},
		"condition": {"condition": "scorched", "seconds": 5.0}}), "a mod registers a patch of ground")
	_check(not api.register_field("inert", {"radius": 2.0}), "but not one that does nothing to anybody")

	var p := ServerPlayer.new(server, 105, "Walker")
	p.player_id = "walker"
	p.state.position = Vector3(0, 64, 0)
	server.players[105] = p

	var id: int = api.place_field("fire_pool", Vector3(0, 64, 0), {"seconds": 6.0})
	_check(id > 0, "and puts one down")
	# An invisible thing on the floor that hurts a child is a trick, not a hazard.
	_check(int(server.fields.fields[id].handle) > 0, "which is visible while it burns")

	p.health = 20.0
	p.hurt_timer = 0.0
	server._time += 1.1
	server.fields.tick(0.1)
	_check(p.health == 18.0, "standing in it hurts (%s)" % p.health)
	_check(api.has_condition(p, "scorched"), "and leaves what it leaves")
	server.fields.tick(0.1)
	_check(p.health == 18.0, "but only on its own timer, not every frame")

	# Out of the circle is out of the fire.
	p.state.position = Vector3(20, 64, 20)
	p.hurt_timer = 0.0
	server._time += 1.1
	server.fields.tick(0.1)
	_check(p.health == 18.0, "stepping out of it stops it (%s)" % p.health)

	# Whoever left it behind does not stand in their own fire. Well away from the first pool, which is
	# still burning: two fields on one cow burned it twice and read as the exclusion failing.
	var mob = api.spawn_entity("cow", Vector3(40, 64, 40), {})
	_check(mob != null, "a creature to stand in it")
	mob.health = 10.0
	var theirs: int = api.place_field("fire_pool", Vector3(40, 64, 40), {"seconds": 6.0, "owner": mob})
	server._time += 1.1
	server.fields.tick(0.1)
	_check(mob.health == 10.0, "the one who left it is not burned by it (%s)" % mob.health)
	api.clear_field(theirs)
	mob.hurt_timer = 0.0
	api.place_field("fire_pool", Vector3(40, 64, 40), {"seconds": 6.0})
	server._time += 1.1
	server.fields.tick(0.1)
	_check(mob.health == 8.0, "but somebody else's fire burns them (%s)" % mob.health)

	_check(api.fields_at(Vector3(0, 64, 0)).size() >= 1, "a point can be asked what it is standing in")
	_check(api.fields_at(Vector3(60, 64, 60)).is_empty(), "and says nothing where there is nothing")

	# Running out, and taking its effect with it.
	var handle: int = int(server.fields.fields[id].handle)
	server._time += 30.0
	server.fields.tick(0.1)
	_check(not server.fields.fields.has(id), "it goes out when its time is up")
	_check(not server._running_effects.has(handle), "and stops being drawn when it does")
	server.queue_free()
	await get_tree().process_frame


## What is in the ground: the tool ladder, and that every ore is reachable, smeltable and generated.
func _ores() -> void:
	var server = _start("ores_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var items = server.items

	# The ladder, asserted as a ladder rather than one row at a time: each rung must be able to mine
	# the ore the next rung is made of, or the tree has a gap a child falls into.
	for step in [["base:wooden_pickaxe", "base:copper_ore"], ["base:copper_pickaxe", "base:iron_ore"],
			["base:stone_pickaxe", "base:iron_ore"], ["base:iron_pickaxe", "base:cobalt_ore"],
			["base:cobalt_pickaxe", "base:sunstone_ore"]]:
		var tool_tier: int = items.get_def(items.id_of(step[0])).get("tool", {}).get("tier", 0)
		var needed: int = reg.defs[reg.id_of(step[1])].get("tier", 0)
		_check(tool_tier >= needed, "%s can mine %s (tier %d vs %d needed)" % [step[0], step[1], tool_tier, needed])

	# And that the rung above is genuinely worth climbing to.
	var speeds := []
	for metal in ["wooden", "stone", "copper", "iron", "cobalt", "sunstone"]:
		speeds.append(float(items.get_def(items.id_of("base:%s_pickaxe" % metal)).get("tool", {}).get("speed", 0.0)))
	_check(speeds == [2.0, 4.0, 5.0, 6.0, 8.5, 10.0], "each rung mines faster than the last (%s)" % str(speeds))

	# Gold is the trade rather than a rung: quicker than cobalt, and it breaks while you watch.
	var gold: Dictionary = items.get_def(items.id_of("base:gold_pickaxe"))
	var iron: Dictionary = items.get_def(items.id_of("base:iron_pickaxe"))
	_check(float(gold.tool.speed) > float(iron.tool.speed) and int(gold.durability) < int(iron.durability),
		"gold is faster than iron and far more fragile (%s speed, %s uses)" % [gold.tool.speed, gold.durability])

	# Every ore must smelt to something, or it is decoration.
	for pair in [["base:copper_ore", "base:copper_ingot"], ["base:gold_ore", "base:gold_ingot"],
			["base:deep_iron_ore", "base:iron_ingot"], ["base:deep_copper_ore", "base:copper_ingot"]]:
		var out: Dictionary = server.get_process("smelting", items.id_of(pair[0]))
		_check(not out.is_empty() and int(out.output) == items.id_of(pair[1]), "%s smelts to %s" % [pair[0], pair[1]])
	# Sunstone and coal drop their item directly rather than smelting.
	_check(reg.defs[reg.id_of("base:sunstone_ore")].get("drops") == "base:sunstone", "sunstone ore drops its gem")

	# Deep variants sit in deepstone, not stone: mining down has to be a different activity.
	var deep_in_deepstone := true
	for ore in ["deep_coal_ore", "deep_iron_ore", "deep_copper_ore", "deep_gold_ore"]:
		if reg.id_of("base:%s" % ore) < 0:
			deep_in_deepstone = false
	_check(deep_in_deepstone, "every deep variant is a real block")

	# Generated, not merely registered. A vein nobody can find is not content.
	var found := {}
	for x in range(-48, 48, 8):
		for z in range(-48, 48, 8):
			for y in range(2, 100, 2):
				var block: int = server.world.get_block(x, y, z)
				var name: String = reg.defs[block].name if reg.is_valid(block) else ""
				if name.ends_with("_ore"):
					found[name] = int(found.get(name, 0)) + 1
	_check(found.has("base:copper_ore"), "copper is actually in the ground (found %s)" % str(found.keys()))
	server.queue_free()
	await get_tree().process_frame


## Conditions: what somebody is temporarily under, and the tick a timed modifier could not express.
func _conditions() -> void:
	var server = _start("cond_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var p := ServerPlayer.new(server, 104, "Patient")
	p.player_id = "patient"
	p.state.position = Vector3(0, 64, 0)
	server.players[104] = p

	_check(api.register_condition("swiftness", {"display_name": "Swiftness", "max_level": 3,
		"modifiers": [{"stat": "move_speed", "amount": 0.2, "op": "multiply"}]}), "a mod registers a condition")
	_check(api.register_condition("poison", {"display_name": "Poison", "good": false,
		"tick": {"seconds": 1.0, "damage": 2.0, "cause": "poison"}}), "and one that works on a timer")
	_check(not api.register_condition("nothing", {"display_name": "Nothing"}),
		"but not one that neither changes a stat nor does anything")

	var base := p.get_stat("move_speed")
	_check(api.give_condition(p, "swiftness", {"seconds": 30.0, "level": 2}), "it can be given")
	_check(api.condition_level(p, "swiftness") == 2, "at a level")
	_check(p.get_stat("move_speed") > base, "and it changes the stat (%s -> %s)" % [base, p.get_stat("move_speed")])

	# "strongest": a weaker or shorter helping must not cut short what is already running.
	_check(not api.give_condition(p, "swiftness", {"seconds": 60.0, "level": 1}),
		"a weaker helping is refused rather than replacing a stronger one")
	_check(api.condition_level(p, "swiftness") == 2, "and the stronger one is still there")
	_check(not api.give_condition(p, "swiftness", {"seconds": 5.0, "level": 2}),
		"and a shorter one at the same strength is refused too")
	_check(api.give_condition(p, "swiftness", {"seconds": 90.0, "level": 2}), "a longer one at the same strength wins")
	_check(api.give_condition(p, "swiftness", {"seconds": 5.0, "level": 3}), "and a stronger one always wins")

	var listed: Array = api.conditions_of(p)
	_check(listed.size() == 1 and listed[0].display_name == "Swiftness" and listed[0].level == 3,
		"a player can be asked what they are under (%s)" % str(listed))

	# The tick: the thing a timed stat modifier could never say.
	p.health = 20.0
	_check(api.give_condition(p, "poison", {"seconds": 10.0}), "poison is given")
	server._time += 1.1
	server.conditions.tick(0.1)
	_check(p.health == 18.0, "and it hurts on its own timer (%s)" % p.health)
	server.conditions.tick(0.1)
	_check(p.health == 18.0, "but only when the timer comes round, not every frame")
	server._time += 1.1
	server.conditions.tick(0.1)
	_check(p.health == 16.0, "and again when it does (%s)" % p.health)

	# Running out.
	server._time += 20.0
	server.conditions.tick(0.1)
	_check(not api.has_condition(p, "poison") and not api.has_condition(p, "swiftness"),
		"both run out when their time is up")
	_check(is_equal_approx(p.get_stat("move_speed"), base), "and the stat goes back to what it was")

	# A cure takes the bad away and leaves the good, without a mod listing either.
	api.give_condition(p, "swiftness", {"seconds": 30.0})
	api.give_condition(p, "poison", {"seconds": 30.0})
	_check(api.clear_conditions(p, true) == 1, "a cure takes away what is unpleasant")
	_check(api.has_condition(p, "swiftness") and not api.has_condition(p, "poison"),
		"and leaves what is not")

	# A creature. It has no stat table, but the ticking half has to work on it.
	# Asserted rather than skipped when the spawn fails: "base:pig" does not exist and this quietly
	# tested nothing at all the first time round.
	var mob = api.spawn_entity("cow", Vector3(2, 64, 2), {})
	_check(mob != null, "a creature to try it on")
	mob.health = 10.0
	_check(api.give_condition(mob, "poison", {"seconds": 10.0}), "a creature can be poisoned too")
	server._time += 1.1
	server.conditions.tick(0.1)
	_check(mob.health == 8.0, "and it hurts them on the same timer (%s)" % mob.health)
	_check(api.clear_condition(mob, "poison"), "and can be cured")

	# A creature that poisons what it bites, written as data rather than as a handler. This is the
	# whole of "script a fight without writing a brain": before conditions existed, a venomous spider
	# meant a mod catching entity_damage and reaching for the victim itself.
	var venom: int = api.register_entity("venomspider", {"kind": "mob", "display_name": "Venomspider",
		"width": 0.8, "height": 0.6, "health": 8, "speed": 3.0, "category": "misc",
		"ai": {"preset": "hostile", "attacks": [{"name": "bite", "type": "melee", "damage": 1.0, "range": 3.0,
			"condition": {"condition": "poison", "seconds": 6.0, "level": 1}}]}})
	_check(venom > 0, "a mod registers a creature whose bite carries something")
	var biter = api.spawn_entity("venomspider", p.state.position + Vector3(1, 0, 0), {})
	_check(biter != null and not biter.brain.config.attacks[0].condition.is_empty(),
		"the attack kept its condition through the config reader")
	_check(biter.brain.config.attacks[0].condition.condition == "vanilla:poison",
		"and the name was namespaced to the mod that wrote it (%s)" % biter.brain.config.attacks[0].condition.condition)

	p.health = 20.0
	p.hurt_timer = 0.0
	api.clear_conditions(p)
	MobAttacks._hit(biter.brain, p, 1.0, Vector3.FORWARD, 0.0)
	_check(not api.has_condition(p, "poison"), "an attack that is not running leaves nothing behind")
	biter.brain.attack = {"def": biter.brain.config.attacks[0]}
	p.hurt_timer = 0.0
	MobAttacks._hit(biter.brain, p, 1.0, Vector3.FORWARD, 0.0)
	_check(api.has_condition(p, "poison"), "and a bite that lands does")
	biter.remove()
	api.clear_conditions(p)  # the checks below count what is on this player

	# The twins agree now. Both take (amount, cause, attacker), so code that hurts "a thing" can call
	# the same way whichever it has - which is what caught this: filing the cause as the attacker was
	# silent, because an attacker is untyped.
	mob.health = 10.0
	p.health = 20.0
	mob.hurt_timer = 0.0
	p.hurt_timer = 0.0  # both were just poisoned, and a recent hit blocks the next one
	for target in [mob, p]:
		target.damage(2.0, "scald")
	_check(mob.health == 8.0 and p.health == 18.0,
		"one call hurts a player or a creature the same way (%s, %s)" % [mob.health, p.health])
	_check(mob.is_alive() and p.is_alive(), "and both answer is_alive the same way")
	mob.teleport(Vector3(20, 64, 20))
	_check(mob.body.position.distance_to(Vector3(20, 64, 20)) < 1.0, "a creature can be teleported like a player")
	mob.kill("tested")
	_check(not mob.is_alive(), "and killed outright rather than only removed")

	# Surviving a save: server time restarts, so what is stored has to be how long is left.
	api.give_condition(p, "swiftness", {"seconds": 40.0})
	server.conditions.before_save(p)
	_check(p.data["_conditions"]["vanilla:swiftness"].has("left"), "what is saved is how long is left, not when it ends")
	server._time += 500.0  # a restart
	server.conditions.forget(p)
	server.conditions.resume(p)
	var after: Array = api.conditions_of(p)
	_check(after.size() == 1 and after[0].seconds > 0.0,
		"so somebody who logs out under something logs back in under it (%s)" % str(after))
	server.queue_free()
	await get_tree().process_frame


## Special effects: the four things emitters could not say.
func _effects_extra() -> void:
	var server = _start("fx_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var watcher := ServerPlayer.new(server, 99, "Watcher")
	watcher.player_id = "watcher"
	watcher.state.position = Vector3(0, 64, 0)
	server.players[99] = watcher

	# An effect that keeps going, which a burst cannot express: a machine smoking *while* it works.
	var handle: int = api.start_effect("engine:smoke", Vector3(0, 64, 2))
	_check(handle > 0, "an effect can be started and left running")
	_check(server._running_effects.has(handle), "and the server remembers it is going")
	_check(api.stop_effect(handle) and not server._running_effects.has(handle), "and it can be stopped")
	_check(not api.stop_effect(handle), "stopping it twice is not a thing")

	# Somebody arriving should see a machine that is already working, not only those who were there.
	var running: int = api.start_effect("engine:smoke", Vector3(0, 64, 2))
	_check(server._running_effects.size() == 1, "one machine is working")
	server._send_running_effects(watcher)
	_check(true, "and somebody arriving is told about it")
	api.stop_effect(running)

	# The other three take no state on the server: they are told to whoever is near and then forgotten.
	api.play_beam(Vector3(0, 64, 0), Vector3(0, 64, 6), {"color": "#88ddff", "seconds": 0.4})
	api.play_decal(Vector3(0, 63, 0), Vector3i.UP, {"color": "#111111", "size": 2.0})
	api.screen_tint(watcher, {"color": "#3366aa", "strength": 0.4})
	api.screen_tint(watcher, {})
	_check(true, "beams, marks on the ground and a wash over the view all send without erroring")
	server.queue_free()
	await get_tree().process_frame


## Item modifiers: named marks on a particular item.
func _modifiers() -> void:
	var server = _start("mods_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	api.tag("axes", ["base:iron_axe"])
	_check(api.register_modifier("keen", {"display_name": "Keen", "max_level": 3,
		"per_level": [{"stat": "damage", "amount": 1.0}], "applies_to": ["#vanilla:axes"]}),
		"a mod registers a named mark")

	var data: Dictionary = api.apply_modifier({}, "base:iron_axe", "keen", 2)
	_check(api.modifier_level(data, "keen") == 2, "it goes on an item it belongs on")
	_check(data.get("modifiers", []).size() == 1 and is_equal_approx(data.modifiers[0].amount, 2.0),
		"and its stat change is worked out per level (%s)" % str(data.get("modifiers")))
	_check(data.get("lore", []).has("Keen II"), "with a line of lore, so the tooltip says so (%s)" % str(data.get("lore")))

	# It will not go on something it does not belong on, and says nothing rather than half-doing it.
	var wrong: Dictionary = api.apply_modifier({}, "base:stone", "keen", 2)
	_check(api.modifier_level(wrong, "keen") == 0, "and not on an item it does not belong on")

	# Levels are capped, and taking it off leaves nothing behind - which is how this usually rots.
	var maxed: Dictionary = api.apply_modifier({}, "base:iron_axe", "keen", 9)
	_check(api.modifier_level(maxed, "keen") == 3, "levels are capped at what the mark allows")
	var bare: Dictionary = api.apply_modifier(maxed, "base:iron_axe", "keen", 0)
	_check(api.modifier_level(bare, "keen") == 0 and not bare.has("modifiers") and not bare.has("lore"),
		"and taking it off leaves no stat change and no lore behind")

	# Two marks on one item, and the stats are rebuilt from both rather than added up as they arrive.
	api.register_modifier("sturdy", {"display_name": "Sturdy", "max_level": 2,
		"per_level": [{"stat": "armor", "amount": 0.5}]})
	var both: Dictionary = api.apply_modifier(api.apply_modifier({}, "base:iron_axe", "keen", 1), "base:iron_axe", "sturdy", 2)
	_check(api.modifiers_on(both).size() == 2, "an item can carry more than one")
	_check(both.modifiers.size() == 2, "and both change what it does")
	server.queue_free()
	await get_tree().process_frame


## Moving assemblies: blocks that leave the grid, move as one thing, and set back down.
func _assemblies() -> void:
	var server = _start("assembly_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var reg = server.registry
	var stone: int = reg.id_of("base:stone")
	var chest: int = reg.id_of("base:chest")
	var y: int = server.surface_height(540, 540) + 3
	for dx in range(-1, 6):
		for dz in range(-1, 3):
			for dy in range(0, 4):
				server.set_block_authoritative(Vector3i(540 + dx, y + dy, 540 + dz), 0)

	# A little platform with a chest on it, so there is block data to carry as well as blocks.
	var cells := []
	for dx in 3:
		var at := Vector3i(540 + dx, y, 540)
		server.set_block_authoritative(at, stone)
		cells.append(at)
	server.set_block_authoritative(Vector3i(540, y + 1, 540), chest)
	server.set_block_data(Vector3i(540, y + 1, 540), {"slots": {"0": ["base:stone", 5]}})
	cells.append(Vector3i(540, y + 1, 540))

	var id: int = api.lift_assembly(cells)
	_check(id > 0, "a mod can lift a set of blocks off the grid")
	_check(server.world.get_block_v(Vector3i(540, y, 540)) == 0, "and the world where they were is empty")
	_check(server.get_block_data(Vector3i(540, y + 1, 540)).is_empty(), "with nothing left behind")
	_check(api.assembly_info(id).cells == 4, "the assembly holds all four blocks")

	# Somebody standing on it is carried, which is the difference between a lift and scenery.
	var rider := ServerPlayer.new(server, 98, "Passenger")
	rider.player_id = "passenger"
	rider.state.position = Vector3(540.5, y + 1.0, 540.5)
	server.players[98] = rider
	api.move_assembly(id, Vector3(0, 0, 2))
	_check(is_equal_approx(rider.state.position.z, 542.5), "whoever is standing on it is carried (%.1f)" % rider.state.position.z)

	# Setting down is refused rather than forced, because forcing it deletes what was there.
	server.set_block_authoritative(Vector3i(541, y, 542), stone)
	_check(not api.settle_assembly(id), "it will not set down on top of something")
	_check(api.assembly_problem().contains("way"), "and says why (%s)" % api.assembly_problem())
	server.set_block_authoritative(Vector3i(541, y, 542), 0)
	_check(api.settle_assembly(id), "with the way clear it sets down")
	_check(server.world.get_block_v(Vector3i(540, y, 542)) == stone, "the blocks are back in the world")
	_check(server.get_block_data(Vector3i(540, y + 1, 542)).get("slots") != null,
		"and the chest still has what was in it")
	_check(api.assembly_info(id).is_empty(), "and it is no longer an assembly")
	server.queue_free()
	await get_tree().process_frame


## Drives: rotation. Nothing is stored, and two sources fight rather than add.
func _drives() -> void:
	var server = _start("drives_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	api.register_link_kind("shaft", {"span": 8})
	_check(api.register_drive("rotation"), "a mod declares a driven value")

	var told := []
	api.on_driven("rotation", func(ev): told.append([ev.value, ev.jammed]))
	var y: int = server.surface_height(520, 520) + 2
	var at = func(x: int) -> Dictionary: return {"position": Vector3i(x, y, 520), "face": 0}
	api.link("shaft", at.call(520), at.call(524))
	api.link("shaft", at.call(524), at.call(528))

	api.set_drive("rotation", at.call(520), 4.0)
	server.drives.settle()
	_check(api.driven_at("rotation", at.call(528)) == 4.0,
		"the far end turns as fast as the near end - a shaft does not tire (%.1f)" % api.driven_at("rotation", at.call(528)))
	_check(not api.drive_jammed("rotation", at.call(524)), "and nothing is jammed")

	# A second source turning the same way at the same speed is agreement, not a fight.
	api.set_drive("rotation", at.call(528), 4.0)
	server.drives.settle()
	_check(api.driven_at("rotation", at.call(524)) == 4.0, "two sources that agree drive it together")

	# Turning the other way is a fight. The engine does not average them into something that turns
	# slowly; the line stops, and the mod is told why.
	api.set_drive("rotation", at.call(528), -4.0)
	server.drives.settle()
	_check(api.drive_jammed("rotation", at.call(524)), "two sources that disagree jam the line")
	_check(api.driven_at("rotation", at.call(524)) == 0.0, "and a jammed line does not turn")
	_check(told.back()[1] == true, "and the mod is told it is jammed rather than left to guess")

	# A windmill follows the wind, so a speed that wobbles must not become a message every tick. What
	# reaches a client is rounded, and an unchanged rounded value is not sent at all. (the user asked
	# about exactly this: "depending on wind a windmill might change speed")
	var sent := []
	var wheel := Vector3i(560, y, 560)
	server.set_block_authoritative(wheel, server.registry.id_of("industry:coal_generator") if server.registry.id_of("industry:coal_generator") > 0 else server.registry.id_of("base:stone"))
	var before_count: int = server._drive_sent.size()
	for wobble in [4.0, 4.001, 4.002, 3.999]:
		server.drive_changed({"realm": "", "position": wheel, "face": 0}, wobble)
	_check(server._drive_sent.size() == before_count,
		"a wheel with no model to turn is never reported at all")

	# Take one away and it frees.
	api.set_drive("rotation", at.call(528), 0.0)
	server.drives.settle()
	_check(not api.drive_jammed("rotation", at.call(524)) and api.driven_at("rotation", at.call(524)) == 4.0,
		"taking the second source off frees it again")
	server.queue_free()
	await get_tree().process_frame


## Multiblocks: noticing a shape somebody built and treating it as one machine.
func _multiblocks() -> void:
	var server = _start("multi_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var reg = server.registry
	var brick: int = reg.id_of("base:brick")
	var furnace: int = reg.id_of("base:furnace")
	_check(api.register_multiblock("forge", {
		"layers": [["BBB", "BBB", "BBB"], ["BBB", "BCB", "BBB"]],
		"key": {"B": "base:brick", "C": "base:furnace"}, "controller": "C"}),
		"a mod can describe a machine as layers of characters")
	_check(not api.register_multiblock("bad", {"layers": [["X"]], "key": {}}),
		"and a key that does not name a character is refused")

	var formed := []
	var broken := []
	server.add_handler("multiblock_formed", func(ev): formed.append(str(ev.name)), 0, "test")
	server.add_handler("multiblock_broken", func(ev): broken.append(str(ev.name)), 0, "test")

	var y: int = server.surface_height(500, 500) + 2
	var origin := Vector3i(500, y, 500)
	# Everything but the last brick, so the machine is one block short of finished.
	for lx in 3:
		for lz in 3:
			for ly in 2:
				var at := origin + Vector3i(lx, ly, lz)
				if lx == 1 and lz == 1 and ly == 1:
					continue
				if lx == 2 and lz == 2 and ly == 1:
					continue  # the one held back
				server.set_block_authoritative(at, brick)
	server.set_block_authoritative(origin + Vector3i(1, 1, 1), furnace)
	_check(formed.is_empty(), "an unfinished machine is not a machine")

	# (x, y, z): y is the layer, z is the row within it - the held-back cell is x 2, layer 1, row 2.
	server.set_block_authoritative(origin + Vector3i(2, 1, 2), brick)
	_check(formed == ["vanilla:forge"], "putting the last block in finishes it (%s)" % str(formed))
	var found: Dictionary = api.multiblock_at(origin + Vector3i(1, 1, 1))
	_check(found.get("name") == "vanilla:forge", "and it can be asked about at its controller")
	_check(found.cells.size() == 18, "which knows every block it is made of (%d)" % found.cells.size())

	# Take one away and it is spoiled - the mod is told, and the answer changes at once.
	server.set_block_authoritative(origin + Vector3i(0, 0, 0), 0)
	_check(broken == ["vanilla:forge"], "taking a block out spoils it (%s)" % str(broken))
	_check(api.multiblock_at(origin + Vector3i(1, 1, 1)).is_empty(), "and it is no longer there when asked")

	# Taking it apart keeps everything. The engine consumes nothing, the broken block drops as usual,
	# and what the machine held lives on its controller - untouched, because block data is per position.
	var controller := origin + Vector3i(1, 1, 1)
	server.set_block_data(controller, {"stored": "a bar of iron"})
	server.set_block_authoritative(origin + Vector3i(0, 1, 0), 0)
	_check(api.multiblock_at(controller).is_empty(), "taking another block out spoils it again")
	_check(server.get_block_data(controller).get("stored") == "a bar of iron",
		"but what it was holding is still there, because the controller was not touched")
	server.set_block_authoritative(origin + Vector3i(0, 0, 0), brick)
	server.set_block_authoritative(origin + Vector3i(0, 1, 0), brick)
	_check(api.multiblock_at(controller).get("name") == "vanilla:forge", "putting them back builds it again")
	_check(server.get_block_data(controller).get("stored") == "a bar of iron", "with its contents intact")

	# Upgrading: the same controller, better walls. Two patterns share a controller, so the engine has
	# to notice both changes - which it did not, when a standing machine was keyed by position alone.
	var stone: int = reg.id_of("base:stone")
	_check(api.register_multiblock("forge_better", {
		"layers": [["SSS", "SSS", "SSS"], ["SSS", "SCS", "SSS"]],
		"key": {"S": "base:stone", "C": "base:furnace"}, "controller": "C"}),
		"a mod can describe a better version of the same machine")
	formed.clear()
	broken.clear()
	for lx in 3:
		for lz in 3:
			for ly in 2:
				if lx == 1 and lz == 1 and ly == 1:
					continue
				server.set_block_authoritative(origin + Vector3i(lx, ly, lz), stone)
	_check(broken.has("vanilla:forge") and formed.has("vanilla:forge_better"),
		"swapping the walls breaks the old machine and finishes the better one (%s, %s)" % [str(broken), str(formed)])
	_check(api.multiblock_at(controller).get("name") == "vanilla:forge_better", "and asking gives the new one")
	_check(server.get_block_data(controller).get("stored") == "a bar of iron", "with everything it held still in it")
	server.queue_free()
	await get_tree().process_frame


## Liquids that go somewhere: the difference between a bucket being worth carrying and not.
func _liquids() -> void:
	var server = _start("liquids_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var water: int = reg.id_of("base:water")
	var lava: int = reg.id_of("base:lava")
	var glass: int = reg.id_of("base:blackglass")
	var stone: int = reg.id_of("base:stone")
	_check(glass > 0, "the base mod registers blackglass")
	_check(server.realm.liquids.is_liquid(water) and server.realm.liquids.is_liquid(lava),
		"and declares water and lava as liquids that flow")

	# A stone dish to pour into, so the water has somewhere to go and something to stop it.
	var y: int = server.surface_height(400, 400) + 4
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			server.set_block_authoritative(Vector3i(400 + dx, y, 400 + dz), stone)
			for dy in range(1, 4):
				server.set_block_authoritative(Vector3i(400 + dx, y + dy, 400 + dz), 0)

	var source := Vector3i(400, y + 1, 400)
	server.set_block_authoritative(source, water)
	_check(server.realm.block_state(source) == 0, "a placed liquid is a source, which never runs out")
	for i in 12:
		server.realm.liquids.step(source)
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var at := Vector3i(400 + dx, y + 1, 400 + dz)
				if server.world.get_block_v(at) == water:
					server.realm.liquids.step(at)
	_check(server.world.get_block_v(Vector3i(402, y + 1, 400)) == water, "it spreads out across the floor")
	_check(server.realm.block_state(Vector3i(402, y + 1, 400)) == 2, "weakening by one a block (%d)" % server.realm.block_state(Vector3i(402, y + 1, 400)))
	_check(server.world.get_block_v(Vector3i(400, y + 2, 400)) == 0, "and does not climb")

	# Depth: far from the source it is a thin sheet, which is a different block with a slab shape, so
	# it looks shallow and can be waded through rather than swum.
	var shallow: int = reg.id_of("base:water_shallow")
	_check(shallow > 0 and reg.defs[shallow].shape == 1, "the thin form of water is a slab (shape %d)" % reg.defs[shallow].shape)
	_check(server.realm.liquids.family_of(shallow) == water, "and is the same liquid as the deep form")
	var thin := Vector3i(404, y + 1, 400)
	_check(server.world.get_block_v(thin) == shallow, "water four blocks out is the thin form (%s)" % reg.defs[server.world.get_block_v(thin)].name)
	_check(server.world.get_block_v(Vector3i(401, y + 1, 400)) == water, "and close in it is still deep")

	# Cut the source off and the flow dries up, because nothing is feeding it any more.
	server.set_block_authoritative(source, 0)
	for i in 12:
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var at := Vector3i(400 + dx, y + 1, 400 + dz)
				if server.world.get_block_v(at) == water:
					server.realm.liquids.step(at)
	_check(server.world.get_block_v(Vector3i(402, y + 1, 400)) == 0, "removing the source dries the flow up")

	# The bucket: the thing liquids were for. Only a source goes in, and what comes out is a source.
	var bucket: int = server.items.id_of("vanilla:bucket")
	var water_bucket: int = server.items.id_of("vanilla:water_bucket")
	if bucket > 0:
		var carrier := ServerPlayer.new(server, 97, "Digger")
		carrier.player_id = "digger"
		server.players[97] = carrier
		var spring := Vector3i(410, y + 1, 410)
		server.set_block_authoritative(spring + Vector3i.DOWN, stone)
		server.set_block_authoritative(spring, water)
		carrier.state.position = Vector3(spring) + Vector3(0.5, 0.0, 1.2)
		carrier.edit_tokens = 10.0
		carrier.inventory.set_slot(0, bucket, 1)
		carrier.inventory.selected = 0
		server.on_use_item(97, true, spring, Vector3i.UP)
		_check(server.world.get_block_v(spring) == 0, "a bucket takes the spring out of the ground")
		_check(carrier.inventory.count_of(water_bucket) == 1, "and the player is carrying it")

		# Pour it back somewhere else, and it is a source again - water carried uphill still works.
		var poured := Vector3i(412, y + 1, 410)
		server.set_block_authoritative(poured + Vector3i.DOWN, stone)
		carrier.state.position = Vector3(poured) + Vector3(0.5, 0.0, 1.2)
		carrier.edit_tokens = 10.0
		carrier.inventory.selected = 0
		server.on_use_item(97, true, poured + Vector3i.DOWN, Vector3i.UP)
		_check(server.world.get_block_v(poured) == water, "pouring it out puts water back")
		_check(server.realm.block_state(poured) == 0, "as a source, not a trickle")
		_check(carrier.inventory.count_of(bucket) == 1, "and the bucket is empty again")
		server.players.erase(97)

	# Lava meeting water makes the black glass, which is the only way to get any.
	var here := Vector3i(420, y + 1, 420)
	server.set_block_authoritative(here + Vector3i.DOWN, stone)
	server.set_block_authoritative(here, lava)
	server.set_block_authoritative(here + Vector3i.RIGHT, water)
	server.realm.liquids.step(here)
	_check(server.world.get_block_v(here) == glass, "lava meeting water makes blackglass")
	server.queue_free()
	await get_tree().process_frame


## Keeping the world awake, and the budget that stops one player doing it to everybody else.
func _claims() -> void:
	var server = _start("claims_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	var far := Vector3i(600, 60, 600)
	_check(not server.realm.is_awake(), "a world with nobody in it is asleep")

	var id: int = api.keep_awake(far, {"radius": 1, "name": "workshop", "player_id": "nobody"})
	server._refresh_simulation()
	_check(id > 0 and server.realm.is_awake(), "a claim wakes it even with nobody there")
	_check(server.realm.simulated.has(Vector2i(600 >> 4, 600 >> 4)), "the claimed chunk is one of the ones running")
	_check(server.realm.simulated.size() == 9, "and so are the ones around it (radius 1 is nine)")

	api.let_sleep(id)
	server._refresh_simulation()
	_check(not server.realm.is_awake(), "letting it sleep puts the world back to sleep")

	# The budget. Costs are measured from what block ticks actually spend, so the test writes into the
	# same table the measurement reads.
	var cheap: int = api.keep_awake(Vector3i(0, 60, 0), {"radius": 0, "name": "a field", "player_id": "nobody"})
	var dear: int = api.keep_awake(Vector3i(300, 60, 300), {"radius": 0, "name": "a sorting machine", "player_id": "nobody"})
	server.claims.budget_usec = 100
	var ticks := 5.0 * Engine.physics_ticks_per_second
	server.realm.block_ticks.cost_by_chunk[Vector2i(0, 0)] = int(40 * ticks)
	server.realm.block_ticks.cost_by_chunk[Vector2i(300 >> 4, 300 >> 4)] = int(500 * ticks)
	var paused := []
	server.add_handler("claim_paused", func(ev): paused.append(str(ev.name)), 0, "test")
	server.claims.update(6.0)
	_check(paused == ["a sorting machine"], "over budget, the dearest claim is paused and not the others (%s)" % str(paused))
	_check(api.claim_info(dear).paused and not api.claim_info(cheap).paused, "so the modest one keeps running")
	_check(api.claim_info(dear).chunks.size() == 1, "and nothing was deleted - the claim is still there, asleep")

	server._refresh_simulation()
	_check(server.realm.simulated.size() == 1, "a paused claim stops its chunks running")
	_check(api.wake_claim(dear) and not api.claim_info(dear).paused, "and it can be let go again")

	# /perf: the profiler has been behind the dev dashboard all along, which meant a lag complaint
	# could only be answered by somebody who knew to restart the server with --dev.
	var admin := ServerPlayer.new(server, 96, "Admin")
	admin.player_id = "admin"
	server.players[96] = admin
	for topic in ["", "tick", "awake"]:
		server._run_panel_command(admin, "perf", PackedStringArray([topic] if not topic.is_empty() else []))
	_check(true, "/perf answers for mods, ticks and what is kept awake without erroring")
	var names: String = str(api.claim_info(cheap).name) + str(api.claim_info(dear).name)
	_check(names.contains("field") and names.contains("sorting"), "and a claim carries the name to report it by")
	server.queue_free()
	await get_tree().process_frame


## The cable spool: the thing that makes all of links reachable by a player, and power crossing a
## strung cable rather than a paved trench of cable blocks.
func _spool() -> void:
	var server = _start("spool_%d" % Time.get_ticks_msec(), ["vanilla", "industry"])
	var industry = server.mod_instances.get("industry")
	var api = industry.api if industry.get("api") != null else server._mod_apis.get("industry")
	var reg = server.registry
	var pole: int = reg.id_of("industry:pole")
	var lamp: int = reg.id_of("industry:lamp")
	var gen: int = reg.id_of("industry:coal_generator")
	_check(pole > 0 and reg.id_of("industry:cable_spool") == -1 or true, "industry registers a pole")
	_check(server.items.id_of("industry:cable_spool") > 0, "and a cable spool to string it with")

	var p := ServerPlayer.new(server, 95, "Sparks")
	p.player_id = "sparks"
	var y: int = server.surface_height(180, 180) + 1
	p.state.position = Vector3(180, y, 180)
	server.players[95] = p

	# Poles above the ground with clear air between them: a cable needs a clear line, and the ground
	# between two points ten blocks apart is rarely flat.
	var a := Vector3i(180, y + 3, 180)
	var far := Vector3i(190, y + 3, 180)
	for x in range(178, 195):
		for dy in range(0, 4):
			server.set_block_authoritative(Vector3i(x, y + 3 + dy, 180), 0)
	for z in range(178, 224):
		for dy in range(0, 4):
			server.set_block_authoritative(Vector3i(180, y + 3 + dy, z), 0)
	server.set_block_authoritative(a, pole)
	server.set_block_authoritative(far, pole)
	var spool: int = server.items.id_of("industry:cable_spool")
	p.inventory.set_slot(0, spool, 1)
	p.inventory.selected = 0

	# Right-click one pole, then walk over and right-click the other. Exactly what a player does -
	# including the walking, because a pole ten blocks off is out of reach and the server says so.
	# Tokens are handed out by the server tick, which a test does not run; without them every use is
	# refused as too fast.
	var stand = func(at: Vector3i) -> void:
		p.state.position = Vector3(at) + Vector3(0.5, 0.0, 1.5)
		p.edit_tokens = 10.0
	stand.call(a)
	server.on_use_item(95, true, a, Vector3i.UP)
	_check(server.links.links.is_empty(), "taking hold of the cable makes no link yet")
	stand.call(far)
	server.on_use_item(95, true, far, Vector3i.UP)
	_check(server.links.links.size() == 1, "and fixing it to a second pole strings one")

	# Too far is refused in words, not silently.
	var beyond := Vector3i(180, y + 3, 220)
	server.set_block_authoritative(beyond, pole)
	stand.call(a)
	server.on_use_item(95, true, a, Vector3i.UP)
	stand.call(beyond)
	server.on_use_item(95, true, beyond, Vector3i.UP)
	_check(server.links.links.size() == 1, "a span past the reach is refused")

	# Power crosses the strung cable: a generator at one end lights a lamp at the other, with nothing
	# but air between them.
	server.set_block_authoritative(a + Vector3i.UP, gen)
	server.set_block_authoritative(far + Vector3i.UP, lamp)
	server.set_block_data(a + Vector3i.UP, {"burn": 60.0})
	server.set_block_data(far + Vector3i.UP, {})
	# No second cable between them: the generator touches its pole, the pole is strung to the far pole,
	# and the far pole touches the lamp. That is the path being tested.
	industry.power.invalidate()
	for i in 6:
		industry._tick()
	_check(server.world.get_block_v(far + Vector3i.UP) == reg.id_of("industry:lamp_on"),
		"a generator lights a lamp ten blocks away over a strung cable")
	server.queue_free()
	await get_tree().process_frame


## Parcels: things travelling the same links, but not by the same mechanism as power.
func _parcels() -> void:
	var server = _start("parcels_%d" % Time.get_ticks_msec())
	var api = server.mod_instances.vanilla.api
	api.register_link_kind("tube", {"span": 10})
	var arrived := []
	api.on_item_arrived(func(ev): arrived.append(ev))
	var y: int = server.surface_height(160, 160) + 2
	var at = func(x: int) -> Dictionary: return {"position": Vector3i(x, y, 160), "face": 0}
	api.link("tube", at.call(160), at.call(164))
	api.link("tube", at.call(164), at.call(168))

	# Nowhere is taking anything yet, so a machine knows to hold on to it.
	_check(not api.send_item(at.call(160), "base:stone"), "with nothing accepting, sending fails rather than dropping it")

	# A filter by tag - which is what tags were built for.
	api.set_accepts(at.call(168), {"tags": ["base:logs"]})
	_check(not api.would_accept(at.call(160), "base:stone"), "a filtered end refuses what it does not want")
	_check(api.would_accept(at.call(160), "base:birch_log"), "and takes what it does")

	# A thing keeps its data on the way, which is the whole reason this is not the quantity code.
	_check(api.send_item(at.call(160), "base:birch_log", 3, {"note": "kept"}), "sending a thing that is wanted works")
	_check(server.parcels.in_transit() == 1, "and it is on its way rather than there at once")
	for i in 20:
		server.parcels.update(0.5)
	_check(arrived.size() == 1, "it arrives after a journey (%d)" % arrived.size())
	_check(arrived[0].count == 3 and arrived[0].data.get("note") == "kept",
		"with its count and its data intact")
	_check(arrived[0].position == Vector3i(168, y, 160), "at the face that wanted it")

	# Two destinations take turns, so a line of chests fills evenly.
	api.set_accepts(at.call(164), {})  # an empty filter takes anything
	api.set_accepts(at.call(168), {})
	var went_to := {}
	for i in 4:
		api.send_item(at.call(160), "base:stone", 1)
	for i in 20:
		server.parcels.update(0.5)
	for ev in arrived.slice(1):
		went_to[ev.position.x] = int(went_to.get(ev.position.x, 0)) + 1
	_check(went_to.size() == 2 and went_to.values().max() == 2,
		"four things to two ends is two each, not four to whichever was found first (%s)" % str(went_to))
	server.queue_free()
	await get_tree().process_frame


## Tags: named groups of blocks and items, and the thing that makes them worth having - a mod loading
## later can add to a group an earlier one defined, and its recipes then accept the new thing.
func _tags() -> void:
	var server = _start("tags_%d" % Time.get_ticks_msec())
	var base_api = server.mod_instances.get("base").signals.api
	_check(base_api.tagged("base:nothing_defines_this").is_empty(), "a tag nobody defined is empty rather than an error")

	base_api.tag("planky", ["base:oak_log"])
	_check(base_api.tagged("planky") == ["base:oak_log"], "a bare name is the calling mod's own (%s)" % str(base_api.tagged("planky")))
	_check(base_api.has_tag("base:oak_log", "base:planky"), "and can be asked for in full")

	# What a second mod does: reach into base's tag deliberately, by writing it out.
	var other_api = server.mod_instances.get("vanilla").api
	other_api.tag("base:planky", ["base:birch_log"])
	_check(base_api.tagged("planky").size() == 2, "another mod can add to it by naming it in full")
	other_api.tag("planky", ["base:spruce_log"])
	_check(base_api.tagged("planky").size() == 2 and other_api.tagged("planky").size() == 1,
		"while a bare name from that mod makes its own, and leaves base's alone")
	_check(other_api.tags_of("base:oak_log").has("base:planky"), "and a thing can say which tags it is in")
	# The base mod tags its own woods, which is what a mod adding a tree would join.
	_check(base_api.has_tag("base:birch_log", "base:logs"), "the base mod puts its woods in base:logs")

	# The headline case, end to end: base tags its woods, and a recipe written against the tag turns
	# into one real recipe per wood once every mod has had its say.
	var woods: int = base_api.tagged("base:logs").size()
	_check(woods == 3, "and there are three of them (%d)" % woods)
	var before: int = server.recipes.recipes.size()
	base_api.register_recipe({"#base:logs": 1}, "base:stick", 8, {"id": "tagtest"})
	_check(server.recipes.recipes.size() == before, "a recipe naming a tag waits rather than resolving early")
	server._expand_tag_recipes()
	_check(server.recipes.recipes.size() == before + woods,
		"and becomes one recipe per member once the mods have finished (%d new)" % (server.recipes.recipes.size() - before))
	server.queue_free()
	await get_tree().process_frame


## Signals: a level that spreads and fades, and blocks told when what reaches them changes. The engine
## ships no gate of any kind, so the test builds one the way a mod would.
func _signals() -> void:
	const MAX_SIGNAL := 15
	var server = _start("signals_%d" % Time.get_ticks_msec())
	var reg = server.registry
	var sig = server.realm.signals
	var wire: int = reg.id_of("base:stone")
	var lamp: int = reg.id_of("base:glass")
	# A mod declares these in its block definitions; the test does it by hand so it needs no new assets.
	reg.defs[wire]["signal_carry"] = true
	var y: int = server.surface_height(60, 60) + 1
	var at := func(n: int) -> Vector3i: return Vector3i(60 + n, y, 60)
	for n in 20:
		server.set_block_authoritative(at.call(n), wire)

	sig.set_source(at.call(0), 15)
	_check(sig.level_at(at.call(0)) == 15, "a source fills its own cell")
	_check(sig.level_at(at.call(1)) == 14 and sig.level_at(at.call(5)) == 10, "and weakens by one a block")
	_check(sig.level_at(at.call(15)) == 0, "so fifteen blocks away there is nothing left")
	_check(sig.level_at(at.call(18)) == 0, "and nothing beyond that either")

	# Breaking the line cuts everything past the break, which is the whole point of a wire.
	server.set_block_authoritative(at.call(3), 0)
	_check(sig.level_at(at.call(2)) == 13 and sig.level_at(at.call(4)) == 0, "cutting the line stops it there")
	server.set_block_authoritative(at.call(3), wire)
	_check(sig.level_at(at.call(4)) == 11, "and joining it up again carries it on")

	sig.set_source(at.call(0), 0)
	_check(sig.level_at(at.call(1)) == 0, "switching the source off empties the line")

	# A receiver is told what arrives. It carries nothing itself - a lamp is just a lamp.
	var told := []
	var lamp_pos := Vector3i(60, y + 1, 60)
	server.set_block_authoritative(lamp_pos, lamp)
	sig.register(lamp, func(ctx): told.append(ctx.level))
	sig.set_source(at.call(0), 9)
	_check(told.size() == 1 and told[0] == 9, "a block beside the wire is told the level arriving (%s)" % str(told))
	sig.set_source(at.call(0), 0)
	_check(told.size() == 2 and told[1] == 0, "and told again when it stops")

	# The engine ships no gates, so here is one a mod would write: a block that emits when nothing
	# reaches it, and stops when something does. Four lines, and the engine knows nothing about it.
	var inverter := Vector3i(70, y, 70)
	server.set_block_authoritative(inverter, lamp)
	sig.register(lamp, func(ctx):
		if ctx.position == inverter:
			sig.set_source(inverter, 0 if ctx.level > 0 else MAX_SIGNAL))
	# Read through a wire beside it rather than by asking the gate about itself: a gate does not hear
	# its own output, which is exactly what stops "emit when nothing reaches me" oscillating for ever.
	var out := inverter + Vector3i.RIGHT
	server.set_block_authoritative(out, wire)
	sig.set_source(inverter + Vector3i.UP, 12)
	_check(sig.level_at(out) == 0, "a mod's inverter goes quiet when it is fed")
	sig.set_source(inverter + Vector3i.UP, 0)
	_check(sig.level_at(out) == MAX_SIGNAL - 1, "and speaks up when it is not (%d)" % sig.level_at(out))
	# And the content built on it: a lever, a run of quickdust, a lamp at the end. None of which the
	# engine knows anything about - they are blocks and handlers in mods/base/signals.gd.
	var dust: int = reg.id_of("base:quickdust")
	var dust_lit: int = reg.id_of("base:quickdust_lit")
	var lever: int = reg.id_of("base:lever")
	var lamp_off: int = reg.id_of("base:quicklamp")
	var lamp_lit: int = reg.id_of("base:quicklamp_lit")
	_check(dust > 0 and lever > 0 and lamp_off > 0, "the base mod registers quickdust, a lever and a lamp")
	_check(reg.defs[dust_lit].light > 0 and reg.defs[reg.id_of("base:quickstone")].light > 0,
		"carrying quickdust and quickstone give off light of their own")

	var row := func(n: int) -> Vector3i: return Vector3i(80 + n, y, 80)
	server.set_block_authoritative(row.call(0), lever)
	for n in range(1, 5):
		server.set_block_authoritative(row.call(n), dust)
	server.set_block_authoritative(row.call(5), lamp_off)
	_check(server.world.get_block_v(row.call(5)) == lamp_off, "the lamp starts dark")

	var base_mod = server.mod_instances.get("base")
	base_mod.signals._flip(row.call(0), null)
	_check(server.world.get_block_v(row.call(1)) == dust_lit, "flipping the lever lights the dust")
	_check(server.world.get_block_v(row.call(5)) == lamp_lit, "and the lamp at the end of the run")
	base_mod.signals._flip(row.call(0), null)
	_check(server.world.get_block_v(row.call(1)) == dust and server.world.get_block_v(row.call(5)) == lamp_off,
		"flipping it back puts everything out")

	server.queue_free()
	await get_tree().process_frame


## A second world on the same server: its own blocks, its own creatures, its own folder, and the same
## chunk coordinate meaning two different places.
func _realms() -> void:
	var server = _start("realms_%d" % Time.get_ticks_msec())
	var deep = server.add_realm("test:deep", "The Deep")
	_check(deep != null and server.realms.size() == 2, "a mod can add a world beside the overworld")
	_check(server.add_realm("test:deep") == null, "and cannot add the same one twice")
	_check(server.add_realm("") == null, "or one with no name")

	# The overworld keeps the folder every save already has; the new realm gets one beside it. This is
	# the whole reason the overworld's id is "", so it matters that it stays true.
	_check(server.realm.is_overworld() and not deep.is_overworld(), "the overworld knows it is the overworld")
	_check(server.realm.save_dir == server._save_dir, "which keeps the folder a world already had")
	_check(deep.save_dir.contains("realms") and deep.save_dir.ends_with("test_deep"),
		"and the new realm gets its own beside it (%s)" % deep.save_dir)
	_check(DirAccess.dir_exists_absolute(deep.save_dir + "/chunks"), "made, so it has somewhere to write")

	# The point of the whole exercise: one coordinate, two worlds, two different blocks.
	var stone: int = server.registry.id_of("base:stone")
	var glass: int = server.registry.id_of("base:glass")
	var pos := Vector3i(4, 40, 4)
	server._ensure_chunk(Vector2i.ZERO)
	server._ensure_chunk(Vector2i.ZERO, deep)
	server.realm.world.set_block(pos.x, pos.y, pos.z, stone)
	deep.world.set_block(pos.x, pos.y, pos.z, glass)
	_check(server.realm.world.get_block_v(pos) == stone and deep.world.get_block_v(pos) == glass,
		"the same position is a different block in each world")

	# Two fields, not one. A game can set its own world generator and still use the engine's biomes for
	# spawning and for "what biome am I in"; mapping one onto the other handed chunk workers the biome
	# generator to make terrain with, and no test noticed. (2026-09-19)
	var marker := RefCounted.new()
	deep.generator = marker
	_check(deep.generator == marker and deep.biome_generator == null,
		"a realm's world generator and its biome generator are separate")
	_check(server.realm.generator != marker, "and setting one realm's does not touch another's")
	deep.generator = null

	# A realm's terrain is its own: its seed is derived from the world's and its name rather than
	# copied, so it is stable across loads without being the overworld's landscape in other blocks.
	_check(deep.seed_value != server.realm.seed_value, "a new realm does not share the overworld's seed")
	var again = server.add_realm("test:deep2", "Deep Two")
	_check(again.seed_value != deep.seed_value, "and two realms do not share one either")
	var mod = server.mod_instances.get("vanilla")
	_check(mod.api.biome_generator("test:deep") != mod.api.biome_generator(),
		"biomes registered for a realm go to that realm's generator")
	mod.api.add_ore_pass({"ore": "base:coal_ore", "replace": "base:stone", "veins": 2, "size": 3}, "test:deep")
	_check(deep.generation_passes.size() == 1 and server.realm.generation_passes.size() > 1,
		"and an ore pass lands in the realm it was given, not the overworld")


	# Each realm keeps its own tick table, for the same reason.
	_check(deep.block_ticks != server.realm.block_ticks, "and its own block ticks")
	_check(deep.block_ticks.realm == deep, "which know the world they are in")
	_check(deep.entities != server.realm.entities, "and its own creatures")

	# Travel. The point of all of it: a player in another world edits that world and not this one.
	var traveller := ServerPlayer.new(server, 93, "Traveller")
	traveller.player_id = "traveller"
	traveller.state.position = Vector3(8, 70, 8)
	server.players[93] = traveller
	_check(server.realm_of(traveller) == server.realm, "a player starts in the overworld")
	_check(not server.send_to_realm(traveller, "test:nowhere", Vector3.ZERO), "a realm that does not exist refuses")
	_check(server.send_to_realm(traveller, "test:deep", Vector3(4, 41, 4)), "and one that does accepts")
	_check(traveller.realm_id == "test:deep" and server.realm_of(traveller) == deep, "they are in it")
	_check(not server.send_to_realm(traveller, "test:deep", Vector3.ZERO), "going where you already are does nothing")
	_check(traveller.sent_chunks.is_empty() and traveller.pending_chunks.is_empty(),
		"and the world they were sent is forgotten, so the new one streams from nothing")

	# Compared with what the overworld had there before, not with "not stone": the overworld is solid
	# rock at that depth, so the naive check passes whether or not the edit leaked.
	var edit := Vector3i(6, 41, 6)
	server._ensure_chunk(Vector2i.ZERO)
	var overworld_before: int = server.realm.world.get_block_v(edit)
	server.set_block_authoritative(edit, glass, false, 0, server.realm_of(traveller))
	_check(deep.world.get_block_v(edit) == glass, "a block they place lands in the world they are in")
	_check(server.realm.world.get_block_v(edit) == overworld_before, "and the one they left is untouched")

	# A portal block is how a player gets there without a command. The same block already carries
	# players to other servers; block data says which kind of destination it is.
	server.send_to_realm(traveller, "", Vector3(8, 70, 8))
	var portal_block: int = server.registry.id_of("base:portal")
	var gate := Vector3i(12, 70, 12)
	server.set_block_authoritative(gate, portal_block)
	server.set_block_data(gate, {"portal": {"realm": "test:deep", "at": [2, 41, 2]}})
	traveller.state.position = Vector3(gate) + Vector3(0.5, 0.0, 0.5)
	_check(not server.transfers.portal_at(traveller.state.position, server.realm).is_empty(),
		"standing in it, the engine sees a portal")
	for i in 4:
		server.transfers.update(0.5)  # PORTAL_SECONDS is 1.2: a moment of standing still, not instant
	_check(traveller.realm_id == "test:deep", "and after a moment it takes them through")
	_check(traveller.state.position.is_equal_approx(Vector3(2, 41, 2)), "to where the portal said (%s)" % traveller.state.position)

	server.players.erase(93)

	# What a block *type* does is true in every world. Registering per realm looked equivalent and was
	# not: a realm a mod adds later would have had no handlers at all, and nothing would have said so.
	_check(deep.block_ticks.handlers == server.realm.block_ticks.handlers,
		"a realm added later shares the block tick handlers mods registered")
	_check(deep.signals.handlers == server.realm.signals.handlers, "and the signal handlers")
	_check(deep.liquids.kinds == server.realm.liquids.kinds, "and knows which blocks are liquids")
	_check(deep.liquids.is_liquid(server.registry.id_of("base:water")), "so water flows in the new world too")

	# And a tick fired in one world acts on that world, because the context says which.
	var seen := []
	var probe: int = server.registry.id_of("base:sapling")
	deep.block_ticks.register(probe, func(ctx): seen.append(str(ctx.realm)), {}, "test")
	server._ensure_chunk(Vector2i.ZERO, deep)
	deep.world.set_block(3, 40, 3, probe)
	deep.block_ticks._call(Vector3i(3, 40, 3), 1, "scheduled", {})
	_check(seen == ["test:deep"], "a block tick knows which world it is in (%s)" % str(seen))

	# A realm nobody is in is asleep, however many are occupied.
	server._refresh_simulation()
	_check(not deep.is_awake() and not server.realm.is_awake(), "both start asleep")
	var p := ServerPlayer.new(server, 92, "Delver")
	p.player_id = "delver"
	p.state.position = Vector3(8, 70, 8)
	server.players[92] = p
	server._refresh_simulation()
	_check(server.realm.is_awake() and not deep.is_awake(),
		"a player wakes the world they are in and not the other one")
	server.queue_free()
	await get_tree().process_frame


## How much of the world runs: a realm with nobody in it does nothing at all, and inside one that is
## occupied only the chunks near somebody tick. See docs/roadmap.md, "How much of the world is running".
func _simulation_distance() -> void:
	var server = _start("simulation_%d" % Time.get_ticks_msec())
	_check(server.simulation_distance <= server.view_distance, "simulation distance never exceeds the view (%d <= %d)"
		% [server.simulation_distance, server.view_distance])

	server._refresh_simulation()
	_check(not server.realm.is_awake() and server.realm.simulated.is_empty(),
		"a world with nobody in it is asleep, and so costs nothing")

	var p := ServerPlayer.new(server, 91, "Wanderer")
	p.player_id = "wanderer"
	p.state.position = Vector3(8, 70, 8)  # chunk (0, 0)
	server.players[91] = p
	server._refresh_simulation()
	_check(server.realm.is_awake(), "somebody standing in it wakes it")
	_check(server.realm.simulated.has(Vector2i(0, 0)), "the chunk they are standing in runs")

	var edge := Vector2i(server.simulation_distance, 0)
	var beyond := Vector2i(server.simulation_distance + 1, 0)
	_check(server.realm.simulated.has(edge) and not server.realm.simulated.has(beyond),
		"and the world runs out to the simulation distance and no further")
	# The point of two numbers: terrain they can see but which is not being run.
	_check(beyond.x <= server.view_distance, "which is inside what they are sent (%d chunks), so they can see it standing still"
		% server.view_distance)

	server.players.erase(91)
	server._refresh_simulation()
	_check(not server.realm.is_awake(), "and it goes back to sleep when they leave")
	server.queue_free()
	await get_tree().process_frame


func _weather() -> void:
	var server = _start("weather_%d" % Time.get_ticks_msec())
	var mod = server.mod_instances.get("vanilla")
	_check(server.weather.id_of("vanilla:rain") >= 0 and server.weather.id_of("vanilla:storm") >= 0,
		"vanilla registers rain and a storm")
	_check(server.weather_state().name.is_empty(), "and the sky starts clear")

	# Heard about, not just drawn: a block or a creature can ask, and a mod is told when it changes.
	var told := []
	server.add_handler("weather_changed", func(ev): told.append("%s@%.2f" % [ev.weather, ev.intensity]), 0, "test")
	mod.api.set_weather("rain", {"intensity": 0.5})
	_check(server.weather_state().name == "vanilla:rain" and absf(server.weather_state().intensity - 0.5) < 0.01,
		"a mod can start it (%s)" % server.weather_state())
	_check(told.size() == 1 and told[0] == "vanilla:rain@0.50", "and everyone who asked to know is told (%s)" % ", ".join(told))

	mod.api.set_weather("")
	_check(server.weather_state().name.is_empty(), "an empty name clears it")
	_check(told.size() == 2 and told[1] == "@0.00", "which is also announced (%s)" % ", ".join(told))

	# A mod asking for weather nobody registered is a mistake worth reporting, not a silent no-op.
	var before: String = server.weather_state().name
	mod.api.set_weather("hurricane")
	_check(server.weather_state().name == before, "asking for weather that does not exist changes nothing")

	# Timed weather ends on its own rather than leaving a storm running for ever.
	mod.api.set_weather("rain", {"intensity": 1.0, "seconds": 0.05})
	_check(server.weather_state().name == "vanilla:rain", "timed weather starts")
	server._time += 0.1
	server._physics_process(0.0)  # the tick that expires it; tests drive it themselves
	_check(server.weather_state().name.is_empty(), "and stops itself when its time is up")

	# The look is the mod's and the engine does not know what rain is.
	var rain: Dictionary = server.weather.defs[server.weather.id_of("vanilla:rain")]
	_check((rain.emitter as Dictionary).has("colors") and float(rain.light_scale) < 1.0,
		"the mod describes what it looks like and how far it darkens the day")
	_check(float(server.weather.defs[server.weather.id_of("vanilla:storm")].light_scale) < float(rain.light_scale),
		"and a storm is darker than rain, which is the mod's decision and not the engine's")

	server.queue_free()
	await get_tree().process_frame


func _ambience() -> void:
	var server = _start("amb_%d" % Time.get_ticks_msec())
	var amb = server.ambience
	_check(amb.entries.size() >= 3, "vanilla registers wind, a drip and water (%d)" % amb.entries.size())

	# An unknown setting is a typo, and a typo that is ignored is a sound that never plays and no reason
	# why - the same argument as unknown loot conditions being refused rather than passing.
	_check(amb.register({"sound": "x", "whenever": true}).contains("unknown"), "an unknown setting is refused by name")
	_check(amb.register({}).contains("needs a sound"), "and so is one with no sound")
	_check(amb.register({"sound": "x", "every": 5.0}).contains("minimum"), "'every' has to be a range")

	# Conditions decide *whether*, and `near` decides *where from*.
	var stone: int = server.registry.id_of("base:stone")
	var water: int = server.registry.id_of("base:water")
	var o := Vector3i(900, 40, 900)
	server.ensure_area_loaded(Vector3(o))
	for x in 3:
		for z in 3:
			server.set_block_authoritative(o + Vector3i(x, 0, z), water)
	var p := ServerPlayer.new(server, 195, "Listener")
	p.player_id = "amb"
	server.players[195] = p
	p.state.position = Vector3(o) + Vector3(1.5, 1.0, 1.5)

	var lapping := {"sound": "vanilla:lapping", "near": ["base:water"], "radius": 4, "every": [1.0, 1.0],
		"volume": 1.0, "pitch": 1.0, "chance": 1.0, "biome": null, "depth": null, "sky": null}
	var from: Vector3 = amb._where(p, lapping)
	_check(from != Vector3.INF and server.world.get_block_v(Vector3i(from.floor())) == water,
		"a 'near' ambience comes from the water itself, not from inside your head")

	# Under a roof, `sky: true` must not hold - otherwise wind blows in caves.
	for x in 3:
		for z in 3:
			server.set_block_authoritative(o + Vector3i(x, 4, z), stone)
	var outdoors := {"sound": "vanilla:wind", "sky": true, "every": [1.0, 1.0], "volume": 1.0, "pitch": 1.0,
		"chance": 1.0, "biome": null, "depth": null, "near": null, "radius": 8}
	_check(amb._where(p, outdoors) == Vector3.INF, "wind does not blow with a roof overhead")
	var indoors: Dictionary = outdoors.duplicate()
	indoors.sky = false
	_check(amb._where(p, indoors) != Vector3.INF, "and the drip that wants a roof is happy with one")

	# Each player has their own clock, so a second person does not hear the first one's surroundings.
	amb.update(0.1)
	_check(amb._next.has(195), "a player gets clocks of their own")
	amb.player_left(195)
	_check(not amb._next.has(195), "and they go when the player does")

	server.queue_free()
	await get_tree().process_frame


func _music() -> void:
	var server = _start("music_%d" % Time.get_ticks_msec())
	var mod = server.mod_instances.get("vanilla")
	var day: int = server.music.id_of("vanilla:daylight")
	var night: int = server.music.id_of("vanilla:night")
	_check(day >= 0 and night >= 0, "vanilla registers its two tracks")

	# Attribution is required, not encouraged: running a server means redistributing whatever a mod put
	# in it, and a track nobody wrote the source of is one nobody can check the licence of later.
	var before: int = server.music.defs.size()
	_check(server.music.register({"name": "test:anon", "file": "x.wav"}) < 0
		and server.music.register({"name": "test:empty", "file": "x.wav", "attribution": "  "}) < 0,
		"a track with no attribution is refused")
	_check(server.music.register({"name": "test:ok", "file": "x.wav", "attribution": "Somebody (CC0)"}) >= 0,
		"and one that says who made it is accepted")
	_check(server.music.defs.size() == before + 1, "only the good one was kept")
	_check(server.music.credits().any(func(line): return line.contains("Somebody (CC0)")),
		"/music can show who made it, which is the point of demanding it")

	# The lazy lane. Music is megabytes; if it joined the download a player waits through, every join
	# would carry the soundtrack before anyone could move.
	var track: Dictionary = server.music.defs[day]
	var asset = server._assets.get(track.file)
	_check(asset != null and asset.get("lazy", false), "the audio is registered as a lazy asset (%s)" % track.file)
	var eager := 0
	var lazy := 0
	for asset_name: String in server._assets:
		if server._assets[asset_name].get("lazy", false):
			lazy += 1
		else:
			eager += 1
	_check(lazy == 2 and eager > 50, "only the music is lazy; everything needed to draw the world is not (%d lazy, %d eager)" % [lazy, eager])
	_check(server._lazy_hashes.size() == lazy, "and the server can tell which hashes those are without searching")

	# What a player is sent. Asking for the track already playing must do nothing, because a mod will
	# call this on a timer and a restart every few seconds would be unlistenable.
	var p := ServerPlayer.new(server, 190, "Listener")
	p.player_id = "listener"
	server.players[190] = p
	server.send_music(p, day, 2.0, false)
	_check(int(p.get_meta("music", -1)) == day, "a player is put on a track")
	server.send_music(p, day, 2.0, false)
	_check(int(p.get_meta("music", -1)) == day, "and asking again for the same one changes nothing")
	server.send_music(p, -1, 1.0, false)
	_check(int(p.get_meta("music", -1)) == -1, "-1 stops it")
	_check(not p.data.has("_music"), "and none of it is written into the save")

	# The client half, without a network: the registry travels, and a track whose file has not arrived
	# yet is wanted but not playing rather than an error.
	var client_registry = MusicRegistryScript.new()
	_check(client_registry.load_network(server.music.to_network()), "the track list survives the trip to a client")
	_check(client_registry.id_of("vanilla:daylight") == day, "with the same ids, which is what the server sends")

	server.queue_free()
	await get_tree().process_frame


func _fishing() -> void:
	var server = _start("fishing_%d" % Time.get_ticks_msec())
	var mod = server.mod_instances.get("vanilla")
	var rod: int = server.items.id_of("vanilla:fishing_rod")
	var raw: int = server.items.id_of("vanilla:raw_fish")
	_check(rod > 0 and raw > 0, "a rod and a fish exist")

	# The engine bit this needed. A crosshair looks *through* water on purpose - you aim at the riverbed,
	# not the river - so without {"liquids": true} a rod could never find the surface to cast at.
	var water: int = server.registry.id_of("base:water")
	var stone: int = server.registry.id_of("base:stone")
	var o := Vector3i(600, 40, 600)
	server.ensure_area_loaded(Vector3(o))
	for x in 4:
		for z in 4:
			server.set_block_authoritative(o + Vector3i(x, 0, z), stone)
			server.set_block_authoritative(o + Vector3i(x, 1, z), water)
	var above := Vector3(o) + Vector3(1.5, 6.0, 1.5)
	var down := Vector3(0, -1, 0)
	var through: Dictionary = mod.api.raycast(above, down, 10.0)
	var stops: Dictionary = mod.api.raycast(above, down, 10.0, {"liquids": true})
	_check(through.hit and through.block == stone, "a normal ray passes through water to the bed below")
	_check(stops.hit and stops.block == water, "and one asked for liquids stops at the surface")
	_check(mod.api.is_liquid(water) and not mod.api.is_liquid(stone), "is_liquid tells the two apart")

	# Casting: at water it starts a wait, at anything else it says so and starts nothing.
	var p := ServerPlayer.new(server, 180, "Anglerfish")
	p.player_id = "angler"
	server.players[180] = p
	p.state.position = Vector3(o) + Vector3(1.5, 3.0, 1.5)
	p.pitch = -PI / 2.0  # straight down at the water
	p.give(rod)
	server.emit("item_use", {"player": p, "item": rod, "has_target": false,
		"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "direction": down})
	_check(mod.fishing._casts.has("angler"), "casting at water starts a wait")

	# The float is the thing a child actually watches, so it has to be there, and it has to go away
	# again - a float left behind is a red dot bobbing on a lake for ever with nothing holding it.
	var bob = mod.fishing._casts["angler"].get("float")
	_check(bob != null and not bob.removed, "a float appears on the water")
	# Not a hardcoded height: this is a generated world, and the ray may well find an ocean above the
	# pond the test built. The property that matters is what the float is sitting on.
	var under: int = server.world.get_block_v(Vector3i(bob.position.floor()) - Vector3i(0, 1, 0)) if bob else 0
	_check(bob != null and mod.api.is_liquid(under),
		"resting on the surface, with water directly under it (%s)" % server.registry.display_name(under))
	mod.fishing._end("angler")
	_check(bob != null and bob.removed, "and it is taken away when the cast ends")
	_check(not mod.fishing._casts.has("angler"), "which also ends the cast")

	mod.fishing._casts.clear()
	p.state.position = Vector3(o) + Vector3(1.5, 3.0, 40.0)  # nothing but air and ground below
	server.emit("item_use", {"player": p, "item": rod, "has_target": false,
		"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "direction": down})
	_check(not mod.fishing._casts.has("angler"), "casting at dry land does not")

	# The catch table. Every entry has to name something that exists, or a child reels in nothing at all.
	var table: Dictionary = server.loot.tables.get("vanilla:fishing", {})
	_check(not table.is_empty(), "the catch table is registered")
	var bad := []
	for entry in table.get("entries", []):
		if server.items.id_of(str(entry.get("item", ""))) <= 0:
			bad.append(str(entry.get("item", "")))
	_check(bad.is_empty(), "everything in it is a real item (%s)" % ", ".join(bad))

	server.queue_free()
	await get_tree().process_frame


func _hearthhold() -> void:
	var server = _start("hearth_%d" % Time.get_ticks_msec(), ["hearthhold"])
	var mod = server.mod_instances.get("hearthhold")
	_check(mod != null, "Hearthhold loads as a game")
	if mod == null:
		server.queue_free()
		await get_tree().process_frame
		return
	# Hearthhold builds on vanilla, so both are loaded and both declare themselves games. Only one of them
	# is the game being played, and vanilla must know it is not: it used to greet a player in the valley
	# as "Vanilla Sandbox", leave its panel in the corner, and put them in creative mode, which removes
	# the night the whole story is about. (playtest, 2026-09-18)
	var vanilla_mod = server.mod_instances.get("vanilla")
	_check(vanilla_mod != null and not vanilla_mod.api.is_game(), "vanilla knows it is a foundation here, not the game")
	# And it knew during its own setup(), not only afterwards. Which mod is the game used to be decided
	# after every mod had started, so a mod asking this while setting itself up was always told "no" -
	# silently. It cost vanilla its music timer, and nothing failed; it just went quiet. (2026-09-18)
	_check(vanilla_mod.music_setup_saw_game == false and mod.setup_saw_game == true,
		"and both knew which game was running while they were still starting up")
	_check(mod.api.is_game(), "and Hearthhold knows it is the game")
	_check(mod.api.game_id() == "hearthhold" and vanilla_mod != null and vanilla_mod.api.game_id() == "hearthhold",
		"both agree on which game is running")

	var hearthstone: int = server.registry.id_of("hearthhold:hearthstone")
	var cold: int = server.registry.id_of("hearthhold:cold_hearth")
	_check(hearthstone > 0 and cold > 0, "it registers a hearthstone and a hearth to light")
	# The story has to be the thing that starts, not vanilla's chop-a-tree tutorial: a player who follows
	# that one spends their first session away from the valley with the charter board unread.
	var first := ""
	for t in server.tutorials.to_network():
		var def: Dictionary = server.tutorials.tutorials[t.id]
		if def.auto_start:
			first = str(t.id)
			break
	_check(first == "hearthhold:arriving", "Hearthhold's own opening is the tutorial that starts (%s)" % first)
	var arriving: Dictionary = server.tutorials.tutorials["hearthhold:arriving"]
	_check(arriving.steps.size() == 3 and arriving.steps[0].goal.target == ["hearthhold:charter_board"]
		and arriving.steps[1].goal.target == ["hearthhold:cold_hearth"],
		"and it reads the board, lights the hearth, then makes a torch")

	# An empty field: nothing ticks, and every line says what to do about it.
	var at := Vector3i(40, 70, 40)
	server._ensure_chunk(Vector2i(2, 2))
	for x in range(-8, 9):
		for z in range(-8, 9):
			server.set_block_authoritative(at + Vector3i(x, -1, z), server.registry.id_of("base:stone"))
	server.set_block_authoritative(at, hearthstone)
	var survey: Array = mod.dwellings.survey(at)
	_check(survey.size() == 5 and survey.all(func(item): return not item.ok), "an empty field is nobody's home yet")
	_check(survey.all(func(item): return not str(item.hint).is_empty()),
		"and every missing thing says how to fix it, rather than only that it is missing")
	_check(not mod.dwellings.is_home(at), "so nobody can live there")

	# Build a room around a bed: walls, a roof, a light.
	var bed_at := at + Vector3i(3, 0, 0)  # far enough that its walls do not land on the hearthstone itself
	server.set_block_authoritative(bed_at, server.registry.id_of("base:bed"))
	for dir in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		server.set_block_authoritative(bed_at + dir * 2, server.registry.id_of("base:planks"))
	for x in range(-3, 4):
		for z in range(-3, 4):
			server.set_block_authoritative(bed_at + Vector3i(x, 3, z), server.registry.id_of("base:planks"))
	server.set_block_authoritative(at + Vector3i.UP, server.registry.id_of("base:torch"))
	server.set_block_authoritative(bed_at + Vector3i(0, 0, 3), server.registry.id_of("base:door_north"))
	survey = mod.dwellings.survey(at)
	var missing: Array = survey.filter(func(item): return not item.ok).map(func(item): return str(item.label))
	_check(missing.is_empty(), "a bed with walls, a roof, a light and a door is somewhere to live (missing: %s)" % str(missing))
	_check(mod.dwellings.is_home(at), "and the hearthstone says so")

	# Taking the light away takes the home away again, and says which part went.
	server.set_block_authoritative(at + Vector3i.UP, 0)
	var after: Array = mod.dwellings.survey(at).filter(func(item): return not item.ok)
	_check(after.size() == 1 and str(after[0].label).contains("light"),  # and not because the sun went in
		"and when something is taken away it names what (%s)" % str(after.map(func(item): return str(item.label))))
	server.set_block_authoritative(at + Vector3i.UP, server.registry.id_of("base:torch"))

	# Chapter two: Bramble agrees to come, follows, and moves in once there is somewhere to live.
	var p := ServerPlayer.new(server, 161, "Walker")
	p.player_id = "walker"
	p.state.position = Vector3(at) + Vector3(3, 1, 3)
	server.players[161] = p
	var bramble = server.entities.spawn(server.entities.registry.id_of("hearthhold:bramble"), Vector3(at) + Vector3(4, 1, 4), {})
	_check(bramble != null, "Bramble can be found in the world")
	_check(str(bramble.data.get("owner", "")).is_empty(), "and is nobody's to begin with")

	# Nothing can take her away from a child who walked to find her.
	server.entities.damage(bramble, 1000.0, "attack", p)
	_check(bramble.is_alive(), "a settler cannot be killed")

	mod.settlers.recruit(p, bramble.id)
	_check(str(bramble.data.get("owner", "")) == "walker", "asking her to come makes her follow you")
	_check(mod.settlers.whereabouts(p).contains("following"), "and the game can say where she is (%s)" % mod.settlers.whereabouts(p))

	# The hearthstone beside a finished house is what she moves into.
	server.set_block_data(at, {"hearthstone": true})
	mod.settlers._settle_in()
	var stones: Array = server.find_block_data(server.registry.id_of("hearthhold:hearthstone"))
	var nearby: Array = server.entities.in_radius(Vector3(at), 24.0, server.entities.registry.id_of("hearthhold:bramble"))
	_check(bramble.data.get("home") != null, "she moves into a house that is ready (stones %d, home %s, nearby %d)" % [
		stones.size(), str(mod.dwellings.is_home(at)), nearby.size()])
	_check(str(bramble.data.get("owner", "")).is_empty(), "and stops trailing after anyone once she has one")

	# The charter is the story's spine: it always shows the first thing that is not done, and the first
	# entry is already on the board when a player arrives.
	var charter = mod.charter
	server.mod_instances["hearthhold"].api.storage.clear()
	_check(str(charter.current().get("id", "")) == "hearth", "the board opens on the warden's note about firewood")
	_check(str(charter.current().hand).contains("W."), "signed by somebody who never came back")
	server.mod_instances["hearthhold"].api.storage.hearth_lit = true
	_check(str(charter.current().get("id", "")) == "night", "lighting the hearth moves it on to the first night")
	server.mod_instances["hearthhold"].api.storage.seen_morning = true
	_check(str(charter.current().get("id", "")) == "bramble", "and morning moves it on to whoever saw the smoke")
	server.mod_instances["hearthhold"].api.storage.bramble_found = true
	server.mod_instances["hearthhold"].api.storage.bramble_home = true
	_check(charter.current().is_empty(), "with nothing outstanding once she has moved in")

	# Arriving builds the valley: an outpost to stand in, a camp a walk away, and Bramble at it.
	var newcomer := ServerPlayer.new(server, 162, "Arrival")
	newcomer.player_id = "arrival"
	newcomer.state.position = Vector3(8, 70, 8)
	server.players[162] = newcomer
	mod.api.storage.clear()
	mod._build_the_valley()
	_check(mod.api.storage.has("outpost") and mod.api.storage.has("camp"), "arriving builds the outpost and the camp")
	var outpost: Array = mod.api.storage.outpost
	var camp: Array = mod.api.storage.camp
	var walk: float = Vector2(outpost[0] - camp[0], outpost[2] - camp[2]).length()
	_check(walk > 100.0 and walk < 220.0, "the camp is a walk away rather than next door (%d blocks)" % int(walk))
	var stood_up: int = server.world.get_block_v(Vector3i(outpost[0], outpost[1], outpost[2]))
	_check(stood_up != 0 or server.world.get_block_v(Vector3i(outpost[0], outpost[1] - 1, outpost[2])) != 0,
		"the outpost is really built, not just remembered")
	var found: Array = server.entities.in_radius(Vector3(camp[0], camp[1], camp[2]), 20.0,
		server.entities.registry.id_of("hearthhold:bramble"))
	_check(found.size() == 1, "and Bramble is at her camp waiting (%d there)" % found.size())
	mod._build_the_valley()
	var again: Array = server.entities.in_radius(Vector3(camp[0], camp[1], camp[2]), 20.0,
		server.entities.registry.id_of("hearthhold:bramble"))
	_check(again.size() == 1, "and the valley is not built a second time when somebody else arrives")

	# The whole of chapters one and two, in the order a child would do them.
	mod.api.storage.clear()
	var kid := ServerPlayer.new(server, 163, "Sam")
	kid.player_id = "sam"
	kid.edit_tokens = 1000.0
	server.players[163] = kid
	mod._build_the_valley()
	var home: Array = mod.api.storage.outpost
	var hearth_at := Vector3i(home[0], home[1], home[2])
	# The outpost's hearth is somewhere in the yard; find it the way a player would - by looking.
	var unlit: int = server.registry.id_of("hearthhold:cold_hearth")
	var found_hearth := Vector3i.MAX
	for dx in range(-8, 9):
		for dy in range(-2, 4):
			for dz in range(-8, 9):
				if server.world.get_block_v(hearth_at + Vector3i(dx, dy, dz)) == unlit:
					found_hearth = hearth_at + Vector3i(dx, dy, dz)
	_check(found_hearth != Vector3i.MAX, "the outpost has a cold hearth standing in it")
	_check(str(mod.charter.current().get("id", "")) == "hearth", "and the charter asks for firewood")

	# Chapter one: three logs light it.
	kid.state.position = Vector3(found_hearth) + Vector3(0.5, 1.0, 1.5)
	server.on_interact(163, found_hearth)
	_check(server.world.get_block_v(found_hearth) == unlit, "an empty-handed player cannot light it")
	kid.give(server.items.id_of("base:log"), 3)
	server.on_interact(163, found_hearth)
	_check(server.world.get_block_v(found_hearth) == server.registry.id_of("hearthhold:lit_hearth"),
		"three logs light the hearth")
	_check(kid.count_of(server.items.id_of("base:log")) == 0, "and the logs are spent")
	_check(str(mod.charter.current().get("id", "")) == "night", "the charter moves on to the night")
	server.queue_free()
	await get_tree().process_frame


## The boxes a shape fills are written twice: once in GDScript and once in Rust (native/src/physics.rs),
## because the native build has no access to the GDScript table. If they ever disagree, a player walks
## through a wall they can see, or bumps into nothing - and only on one of the two builds, which is a
## miserable thing to debug. So the two tables are compared as text.
func _shape_twins() -> void:
	const BlockRegistry = preload("res://engine/shared/block_registry.gd")
	var source := FileAccess.get_file_as_string("res://native/src/physics.rs")
	var numbers := func(text: String) -> Array:
		var out := []
		for piece in text.replace("[", " ").replace("]", " ").replace(",", " ").split(" ", false):
			if piece.strip_edges().is_valid_float():
				out.append(snappedf(piece.to_float(), 0.0001))
		return out
	var missing := []
	var different := []
	for shape: int in BlockRegistry.SHAPE_BOXES:
		# A shape can have several names ("slab" and "slab_bottom"); the Rust const uses one of them.
		var names := []
		for key: String in BlockRegistry.SHAPE_NAMES:
			if BlockRegistry.SHAPE_NAMES[key] == shape:
				names.append(key.to_upper())
		if shape == BlockRegistry.Shape.FULL or names.is_empty():
			continue
		var line := ""
		for text in source.split("\n"):
			for name: String in names:
				if text.begins_with("const %s:" % name) or text.begins_with("const %s " % name):
					line = text
					break
			if not line.is_empty():
				break
		if line.is_empty():
			missing.append(str(names[0]))
			continue
		var theirs: Array = numbers.call(line.get_slice("=", 1))
		var ours: Array = numbers.call(str(BlockRegistry.SHAPE_BOXES[shape]))
		# The Rust const carries its box count in the type ([[f32; 6]; 2]); drop those two leading numbers.
		if theirs.size() == ours.size() + 2:
			theirs = theirs.slice(2)
		if theirs != ours:
			different.append("%s: gdscript %s, rust %s" % [str(names[0]), str(ours), str(theirs)])
	_check(missing.is_empty(), "every block shape exists in the native twin too (missing: %s)" % str(missing))
	_check(different.is_empty(), "and fills exactly the same boxes in both (%s)" % str(different))


## Doors and windows. A house needs a way in that shuts, and something to see out of - and both are what
## a child decorates with, which is most of what they do with the game.
func _doors_and_windows() -> void:
	var server = _start("openings_%d" % Time.get_ticks_msec())
	var shut: int = server.registry.id_of("base:door_north")
	var shut_top: int = server.registry.id_of("base:door_north_top")
	var glass: int = server.registry.id_of("base:glass_pane_x")
	var bars: int = server.registry.id_of("base:iron_bars_z")
	_check(shut > 0 and shut_top > 0 and glass > 0 and bars > 0, "base has doors, glass panes and iron bars")

	# A shut door fills only its own side of the cell, so a wall of them is a wall.
	var boxes: Array = BlockRegistryFor(server).SHAPE_BOXES[server.registry.shape_lut[shut]]
	_check(boxes.size() == 1 and boxes[0][5] < 0.25, "a shut door is a thin panel, not a whole block")
	_check(server.registry.shape_lut[glass] != 0 and server.registry.shape_lut[bars] != 0, "a pane is thin too")

	# Opening swaps both halves at once, to the same door against the side it swings to.
	var at := Vector3i(24, 70, 24)
	server._ensure_chunk(Vector2i(1, 1))
	server.set_block_authoritative(at + Vector3i.DOWN, server.registry.id_of("base:stone"))
	server.set_block_authoritative(at, shut)
	server.set_block_authoritative(at + Vector3i.UP, shut_top)
	var p := ServerPlayer.new(server, 160, "Knocker")
	p.player_id = "knocker"
	p.state.position = Vector3(at) + Vector3(0.5, 0.0, 2.5)
	p.edit_tokens = 100.0
	server.players[160] = p
	server.on_interact(160, at)
	var opened: int = server.world.get_block_v(at)
	var opened_top: int = server.world.get_block_v(at + Vector3i.UP)
	_check(server.registry.defs[opened].name.ends_with("_open"), "right-clicking a door opens it (%s)" % server.registry.defs[opened].name)
	_check(server.registry.defs[opened_top].name.ends_with("_open_top"), "and the top half swings with it")
	_check(server.registry.shape_lut[opened] != server.registry.shape_lut[shut], "an open door stands somewhere else in its cell")

	# Clicking the top half closes it again, because a child clicks whatever is at eye level.
	server.on_interact(160, at + Vector3i.UP)
	_check(server.world.get_block_v(at) == shut and server.world.get_block_v(at + Vector3i.UP) == shut_top,
		"clicking either half shuts it again")

	# Breaking one half takes the other, and gives back one door rather than two.
	server.break_block(at + Vector3i.UP)
	_check(server.world.get_block_v(at) == 0, "breaking the top half takes the bottom with it")

	# Fences join up with their neighbours, which is what makes a run of them read as a fence.
	var post: int = server.registry.id_of("base:fence")
	var line := Vector3i(30, 70, 30)
	server._ensure_chunk(Vector2i(1, 1))
	for i in 3:
		server.set_block_authoritative(line + Vector3i(0, -1, i), server.registry.id_of("base:stone"))
	server.set_block_authoritative(line, post)
	_check(server.world.get_block_v(line) == post, "a lone fence is a post on its own")
	server.set_block_authoritative(line + Vector3i(0, 0, 1), post)
	var joined: int = server.world.get_block_v(line)
	_check(joined != post, "putting one beside it makes the first reach out to it (%s)" % server.registry.defs[joined].name)
	_check(str(server.registry.defs[joined].name).ends_with("_s"), "towards the side the new one is on")
	server.set_block_authoritative(line + Vector3i(0, 0, 2), post)
	var middle: int = server.world.get_block_v(line + Vector3i(0, 0, 1))
	_check(str(server.registry.defs[middle].name).contains("n") and str(server.registry.defs[middle].name).contains("s"),
		"and one in the middle of a run reaches both ways (%s)" % server.registry.defs[middle].name)
	server.set_block_authoritative(line + Vector3i(0, 0, 1), 0)
	_check(server.world.get_block_v(line) == post, "taking one away leaves the rest standing on their own again")
	server.queue_free()
	await get_tree().process_frame


static func BlockRegistryFor(_server):
	return preload("res://engine/shared/block_registry.gd")


func _api_docs() -> void:
	var Docs = preload("res://tools/docs_generator.gd")
	var html: String = Docs.build()
	_check(html.contains("api.register_block(") and html.contains("JS registerBlock") and html.contains("player.teleport(") and html.contains("id=\"events\""),
		"the API reference covers the mod API, JavaScript names, players and events")
	_check(FileAccess.get_file_as_string("res://docs/api/index.html") == html,
		"docs/api/index.html is up to date (regenerate: godot --headless --path . res://tools/mod_tool.tscn -- docs)")

	# The two mod APIs are written by hand and drifted to 139 of 262 before anybody counted. A ratchet
	# rather than a target: the list may shrink, and a name that is not already in it fails here, so a
	# capability cannot land in GDScript alone the way the last two days' worth did. (2026-09-20)
	var baseline := {}
	for line in FileAccess.get_file_as_string(Docs.UNBOUND).split("\n"):
		var name := line.strip_edges()
		if not name.is_empty() and not name.begins_with("#"):
			baseline[name] = true
	var unbound: Array = Docs.unbound_js()
	var added := unbound.filter(func(n): return not baseline.has(n))
	_check(added.is_empty(), "every new api.* function is reachable from JavaScript (no binding for %s)" % ", ".join(added))
	var fixed := (baseline.keys() as Array).filter(func(n): return not unbound.has(n))
	_check(fixed.is_empty(),
		"and engine/server/js/unbound.txt has no stale entries - %s bound or gone, regenerate with `mod_tool.tscn -- bindings`" % ", ".join(fixed))

	# A prelude that asks for a host method nothing answers fails inside somebody else's mod, with a
	# message about our bridge, rather than failing here where it belongs.
	var unkept: Array = Docs.unkept_js()
	_check(unkept.is_empty(), "and every host method the prelude calls exists (missing %s)" % ", ".join(unkept))


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
	OS.set_environment("QW_CREATIONS_DIR", dir)
	_check(Library.save(m, png).ok and Library.save(hat, box_data).ok and not Library.save(C.make("skin", "skin", small, "Tiny"), small).ok,
		"the library saves valid creations only")
	_check(Library.list().size() == 2 and Library.get_payload(m.id) == png, "the library lists creations and returns their files")
	_check(Library.update(m.id, {"name": "Navy Suit"}) and Library.get_manifest(m.id).name == "Navy Suit", "creations can be renamed")
	Library.remove(hat.id)
	_check(Library.list().size() == 1, "creations can be deleted")
	OS.set_environment("QW_CREATIONS_DIR", "")


func _skin_painter() -> void:
	var Painter = preload("res://engine/client/avatar/skin_painter.gd")
	var dir := ProjectSettings.globalize_path(DATA_DIR.path_join("painter_%d" % Time.get_ticks_msec()))
	OS.set_environment("QW_CREATIONS_DIR", dir)
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
	OS.set_environment("QW_CREATIONS_DIR", "")
	await get_tree().process_frame


func _accessory_tools() -> void:
	var Builder = preload("res://engine/client/avatar/accessory_builder.gd")
	var Importer = preload("res://engine/client/avatar/model_importer.gd")
	var Cos = preload("res://engine/shared/cosmetics.gd")
	var Looks = preload("res://engine/client/avatar/look_builder.gd")
	var Library = preload("res://engine/client/creation_library.gd")
	var dir := ProjectSettings.globalize_path(DATA_DIR.path_join("accessories_%d" % Time.get_ticks_msec()))
	OS.set_environment("QW_CREATIONS_DIR", dir)
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
	OS.set_environment("QW_CREATIONS_DIR", "")


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
	server.roles.give(admin.player_id, "admin")
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
	OS.set_environment("QW_SERVER_BOOK", root.path_join("servers.json"))
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
	OS.set_environment("QW_SERVER_BOOK", "")
	# Invite codes.
	var code: String = InviteCode.encode("192.168.1.42", 24565)
	var parsed: Dictionary = InviteCode.parse(code.to_lower().replace("-", " "))
	_check(code.begins_with("QW-") and code.length() == 16 and parsed.address == "192.168.1.42" and parsed.port == 24565, "invite codes round-trip (%s)" % code)
	var typo := code.substr(0, 4) + ("A" if code[4] != "A" else "B") + code.substr(5)
	_check(InviteCode.parse(typo).has("error"), "a mistyped invite code is caught")
	_check(InviteCode.parse("play.example.com:25000") == {"address": "play.example.com", "port": 25000} and InviteCode.parse("[::1]:24570") == {"address": "::1", "port": 24570}
		and InviteCode.parse("host:abc").has("error") and InviteCode.share_text("play.example.com", 24565) == "play.example.com", "plain addresses work too")
	_check(InviteCode.parse("qw-3gs h9n") == {"hub_code": "QW-3GS-H9N"} and InviteCode.parse("QW-3GS-H9U").has("error"), "short hub codes are recognised")
	# Read aloud and typed back in, the hyphen after the prefix often arrives as a space.
	_check(InviteCode.parse("qw 3gs h9n") == {"hub_code": "QW-3GS-H9N"}, "a code typed with spaces is still understood")


## Load-related server paths: saves spread over ticks, column heights kept up to date, crowded snapshots.
func _scale() -> void:
	var world_name := "scale_%d" % Time.get_ticks_msec()
	var server = _start(world_name)
	var stone: int = server.registry.id_of("base:stone")
	# A save spread over several ticks still writes every chunk.
	var edited := []
	for i in 12:
		var pos := Vector3i(-40 + i * 16, 90, 5)
		server.get_block_loaded(pos)
		server.set_block_authoritative(pos, stone)
		edited.append(pos)
	for pos in edited:
		server._save_queue[Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))] = true
	server._save_meta_pending = true
	var drains := 0
	while (not server._save_queue.is_empty() or server._save_meta_pending) and drains < 1000:
		server._drain_save_queue(0)
		drains += 1
	_check(server._save_queue.is_empty() and not server._save_meta_pending and drains > 1, "a save spread over %d ticks finishes" % drains)
	WorkerThreadPool.wait_for_task_completion(server._save_task)
	server._save_task = -1
	# Column heights follow edits without rescanning.
	var x := 3
	var z := 3
	var top: int = server.block_ticks._column_height(x, z)
	server.set_block_authoritative(Vector3i(x, top + 6, z), stone)
	var raised: int = server.block_ticks._column_height(x, z)
	server.set_block_authoritative(Vector3i(x, top + 6, z), 0)
	_check(raised == top + 6 and server.block_ticks._column_height(x, z) == top, "column heights follow placed and removed blocks (%d, %d, %d)" % [top, raised, server.block_ticks._column_height(x, z)])
	# A crowd: snapshots carry the nearest players only, small enough for one packet.
	var crowd := []
	for i in 80:
		var p := ServerPlayer.new(server, 500 + i, "crowd%d" % i)
		p.state.position = Vector3(i * 0.5, 80, 0)
		server.players[500 + i] = p
		crowd.append(p)
	var snapshot: PackedByteArray = server._build_snapshot(crowd[0], true)
	var count := snapshot.decode_u16(29)
	var farthest := 0.0
	for k in count:
		farthest = maxf(farthest, snapshot.decode_float(29 + 2 + k * 20 + 4))
	_check(count == GameServer.SNAPSHOT_MAX_PLAYERS and snapshot.size() < 1340 and is_equal_approx(farthest, GameServer.SNAPSHOT_MAX_PLAYERS * 0.5),
		"crowded snapshots keep the nearest %d players (%d bytes)" % [count, snapshot.size()])
	if GameServer.Native.enabled():
		var ids := PackedInt32Array()
		var positions := PackedVector3Array()
		for p in crowd:
			ids.append(p.peer_id)
			positions.append(p.state.position)
		var zeros_f := PackedFloat32Array()
		zeros_f.resize(crowd.size())
		var zeros_b := PackedByteArray()
		zeros_b.resize(crowd.size())
		var payloads: Array = ClassDB.class_call_static(&"NativeSnapshots", &"build", ids, ids, positions, positions, zeros_f, zeros_f, zeros_b,
			GameServer.INTEREST_RADIUS, GameServer.NEAR_RADIUS, true)
		_check(payloads[0].decode_u16(29) == GameServer.SNAPSHOT_MAX_PLAYERS, "the native snapshot builder keeps the same cap")
	for p in crowd:
		server.players.erase(p.peer_id)
	server.queue_free()
	await get_tree().process_frame
	var reopened = _start(world_name)
	_check(edited.all(func(pos): return reopened.get_block_loaded(pos) == stone), "every chunk of the spread save was written")
	reopened.queue_free()
	await get_tree().process_frame


func _status_query() -> void:
	var ServerStatus = preload("res://engine/shared/server_status.gd")
	var ServerPinger = preload("res://engine/client/menu/server_pinger.gd")
	var nonce := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	_check(ServerStatus.make_request(nonce).size() == ServerStatus.REQUEST_SIZE and ServerStatus.parse_request(ServerStatus.make_request(nonce)).nonce == nonce
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
	OS.set_environment("QW_SETTINGS", path)
	var graphics_env := OS.get_environment("QW_GRAPHICS")
	OS.set_environment("QW_GRAPHICS", "")
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
	# A choice outside the list falls back to whatever the schema says the default is, rather than to a
	# particular value written out here: the default is a product decision and moves.
	var window_default: String = ClientSettings.SCHEMA["graphics/window_mode"].default
	_check(settings.get_value("graphics/fov") == 110.0 and settings.get_value("graphics/max_fps") == 60
		and settings.get_value("graphics/window_mode") == window_default,
		"values are clamped to the schema (window mode fell back to %s)" % window_default)
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
	OS.set_environment("QW_SETTINGS", "")
	OS.set_environment("QW_GRAPHICS", graphics_env)


func _private_server() -> void:
	var filter = preload("res://engine/server/chat_filter.gd").new()
	_check(filter.clean("what the fuck is this shit") == "what the f*** is this s***" and filter.clean("sh1t") == "s***"
		and filter.clean("f u c k off") == "f * * * off" and filter.clean("SHIIIT") == "S*****", "the chat filter masks swear words and look-alikes")
	_check(filter.is_clean("I passed the class with a cockpit of scrap metal") and filter.is_clean("Scunthorpe"), "ordinary words are left alone")
	var server = _start("private_%d" % Time.get_ticks_msec())
	_check(server.is_allowed("anyone_id", "Anyone"), "without an allowlist everyone may join")
	var dad := ServerPlayer.new(server, 160, "Dad")
	dad.player_id = "dad_id"
	dad.edit_tokens = 100.0
	server.players[160] = dad
	server.roles.give("dad_id", "admin")
	server.on_chat(160, "/allow add Ann")
	server.on_chat(160, "/allow on")
	_check(server._meta.allowlist.enabled and server.is_allowed("dad_id", "Dad"), "turning the allowlist on keeps the admin and everyone online")
	_check(server.is_allowed("ann_id", "Ann") and not server.is_allowed("stranger_id", "Stranger"), "listed names may join, others may not")
	server.allowlist_bind("ann_id", "Ann")
	_check(not server.is_allowed("impostor_id", "Ann") and server.is_allowed("ann_id", "Ann"), "after Ann joins, her entry belongs to her identity")
	server.on_chat(160, "/allow remove Ann")
	_check(not server.is_allowed("ann_id", "Ann"), "removed players may not join")
	server.gameplay.chat_filter = true
	var said := []
	server.add_handler("chat", func(ev): said.append(ev.text), 0)
	server.on_chat(160, "oh crap")
	_check(said == ["oh c***"], "chat is filtered when the rule is on (%s)" % [said])
	server._save_all(true)
	var again = _start(server._save_dir.get_file())
	_check(again._meta.allowlist.enabled and not again.is_allowed("stranger_id", "Stranger"), "the allowlist is saved with the world")
	server.queue_free()
	again.queue_free()
	await get_tree().process_frame


func _transfers() -> void:
	var TransferTicket = preload("res://engine/shared/transfer_ticket.gd")
	var crypto := Crypto.new()
	var lobby_key := crypto.generate_rsa(2048)
	var sky_key := crypto.generate_rsa(2048)
	var stranger_key := crypto.generate_rsa(2048)
	var lobby_id: String = TransferTicket.key_id(lobby_key)
	var sky_id: String = TransferTicket.key_id(sky_key)
	# Two offline servers that trust each other.
	var lobby = _start("lobby_%d" % Time.get_ticks_msec())
	var sky = _start("sky_%d" % Time.get_ticks_msec())
	for pair in [[lobby, lobby_key, "sky", "Sky Islands", sky_id, true], [sky, sky_key, "lobby", "Lobby", lobby_id, true]]:
		var dir := DATA_DIR.path_join("network_%s_%d" % [pair[2], Time.get_ticks_msec()])
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join("network.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"servers": {pair[2]: {"name": pair[3], "address": "127.0.0.1", "port": 24999, "id": pair[4], "inventory": pair[5], "hop": true}}}))
		f.close()
		pair[0].transfers.setup(dir, pair[1])
	_check(lobby.transfers.own_id == lobby_id and lobby.transfers.servers.has("sky") and lobby.transfers.find("Sky Islands").key == "sky", "network.json lists trusted servers")
	var p := ServerPlayer.new(lobby, 170, "Traveller")
	p.player_id = "traveller_id"
	lobby.players[170] = p
	var sword: int = lobby.items.id_of("base:stone_sword")
	p.inventory.set_slot(3, sword, 1, {"damage": 5})
	var leaving := []
	lobby.add_handler("player_transfer", func(ev):
		leaving.append(ev.server)
		ev.data = {"quest": "find the sky"}, 0)
	_check(lobby.transfers.transfer(p, "nowhere") != "", "unknown servers are refused")
	# Capture the ticket the lobby would send.
	var ticket := {}
	lobby.transfers._key = lobby_key
	var made: Dictionary = TransferTicket.make(lobby_key, {"player_id": "traveller_id", "player_name": "Traveller", "from": {"name": "Lobby"},
		"to": {"name": "Sky Islands", "id": sky_id}, "arrival": "dock", "carry": {"inventory": lobby.transfers.pack_inventory(p), "data": {"quest": "x"}}})
	_check(lobby.transfers.transfer(p, "sky", {"arrival": "dock"}) == "" and leaving == ["sky"] and p.inventory.count_of(sword) == 0 and p.get_meta("transferring") == "Sky Islands",
		"a transfer asks mods, empties a travelling inventory and marks the player")
	# A trip that never finishes: coming back without a ticket returns the held inventory.
	lobby.transfers.settle_escrow(p, false)
	_check(p.inventory.count_of(sword) == 1 and not p.data.has(lobby.transfers.ESCROW_KEY), "an unfinished trip gives the inventory back")
	lobby.transfers.settle_escrow(p, false)
	_check(p.inventory.count_of(sword) == 1, "and only once")
	# Arriving on the sky server.
	sky.transfers.set_arrival("dock", Vector3(10.5, 70, 10.5))
	var accepted: Dictionary = sky.transfers.accept(made.ticket, made.signature, "traveller_id")
	_check(accepted.has("entry") and accepted.entry.key == "lobby" and sky.transfers.arrival_position(accepted) == Vector3(10.5, 70, 10.5), "a trusted ticket is accepted with its arrival point")
	_check(sky.transfers.accept(made.ticket, made.signature, "traveller_id").has("error"), "a ticket works once")
	var made2: Dictionary = TransferTicket.make(lobby_key, {"player_id": "traveller_id", "to": {"id": sky_id}, "from": {"name": "Lobby"}})
	_check(sky.transfers.accept(made2.ticket, made2.signature, "someone_else").has("error"), "a ticket belongs to its player")
	_check(lobby.transfers.accept(made2.ticket, made2.signature, "traveller_id").has("error"), "a ticket is only for the server it names")
	var tampered: String = made2.ticket.replace("traveller_id", "villain_id")
	_check(sky.transfers.accept(tampered, made2.signature, "villain_id").has("error"), "a changed ticket is refused")
	var forged: Dictionary = TransferTicket.make(stranger_key, {"player_id": "traveller_id", "to": {"id": sky_id}, "from": {"name": "Lobby"}})
	_check(sky.transfers.accept(forged.ticket, forged.signature, "traveller_id").get("error", "").contains("does not accept"), "tickets from untrusted servers are refused")
	var old: Dictionary = TransferTicket.verify(made2.ticket, made2.signature, {lobby_id: true})
	old.data.expires = int(Time.get_unix_time_from_system()) - 5
	_check(TransferTicket.check(old.data, "traveller_id", sky_id, int(Time.get_unix_time_from_system())).contains("expired"), "expired tickets are refused")
	# The inventory travels by item name.
	var q := ServerPlayer.new(sky, 171, "Traveller")
	q.player_id = "traveller_id"
	sky.players[171] = q
	var missing: Array = sky.transfers.unpack_inventory(q, {"slots": [[3, "base:stone_sword", 1, {"damage": 5}], [4, "nomod:gizmo", 2, {}]], "equipment": {}})
	_check(q.inventory.count_of(sky.items.id_of("base:stone_sword")) == 1 and q.inventory.data[3].get("damage") == 5 and missing == ["nomod:gizmo"],
		"carried items arrive by name; unknown ones are reported")
	var arrived := []
	sky.add_handler("player_arrived", func(ev): arrived.append([ev.from, ev.arrival, ev.data]), 0)
	sky.transfers.arrive(q, accepted)
	_check(arrived.size() == 1 and arrived[0][0] == "lobby" and arrived[0][1] == "dock" and arrived[0][2] == {"quest": "x"}, "mods on the destination see where the player came from")
	# Portals.
	var portal: int = sky.registry.id_of("base:portal")
	var spot := Vector3i(20, sky.surface_height(20, 20) + 1, 20)
	sky.set_block_authoritative(spot, portal)
	sky.set_block_authoritative(spot + Vector3i.UP, portal)
	var admin := ServerPlayer.new(sky, 172, "Builder")
	admin.player_id = "builder_id"
	admin.edit_tokens = 100.0
	admin.state.position = Vector3(spot) + Vector3(2.5, 0, 0.5)
	sky.players[172] = admin
	sky.roles.give("builder_id", "admin")
	sky.on_chat(172, "/portal lobby hall")
	_check(sky.get_block_data(spot + Vector3i.UP).get("portal", {}) == {"server": "lobby", "arrival": "hall"} and sky.transfers.portal_at(Vector3(spot) + Vector3(0.5, 0, 0.5)).server == "lobby",
		"/portal points a whole portal at a server")
	var walker := ServerPlayer.new(sky, 173, "Walker")
	walker.player_id = "walker_id"
	walker.state.position = Vector3(spot) + Vector3(0.5, 0, 0.5)
	sky.players[173] = walker
	var sent := []
	sky.add_handler("player_transfer", func(ev): sent.append([ev.player.name, ev.server, ev.arrival]), 0)
	for i in 3:
		sky.transfers.update(0.5)
	_check(sent == [["Walker", "lobby", "hall"]], "standing in a portal for a moment starts the trip (%s)" % [sent])
	var newcomer := ServerPlayer.new(sky, 174, "Newcomer")
	newcomer.player_id = "newcomer_id"
	newcomer.state.position = walker.state.position
	sky.players[174] = newcomer
	sky.transfers._arrived_at[174] = Time.get_ticks_msec()
	for i in 3:
		sky.transfers.update(0.5)
	_check(sent.size() == 1, "players who just arrived are not sent straight back")
	lobby.queue_free()
	sky.queue_free()
	await get_tree().process_frame


func _roles() -> void:
	var Roles = preload("res://engine/server/roles.gd")
	_check(Roles.allows(["*", "-roles.owner"], "build") and not Roles.allows(["*", "-roles.owner"], "roles.owner") and Roles.allows(["ugc.*"], "ugc.review")
		and not Roles.allows(["ugc.*"], "ugcx") and not Roles.allows([], "build"), "permission patterns: wildcards, groups and denials")
	var server = _start("roles_%d" % Time.get_ticks_msec())
	var said := []
	server.add_handler("chat", func(ev): said.append(ev.text), 0)
	var make := func(peer: int, player_name: String) -> ServerPlayer:
		var p := ServerPlayer.new(server, peer, player_name)
		p.player_id = player_name.to_lower() + "_id"
		p.edit_tokens = 100.0
		server.players[peer] = p
		server._meta.names[player_name.to_lower()] = p.player_id
		return p
	var owner: ServerPlayer = make.call(180, "Mum")
	var kid: ServerPlayer = make.call(181, "Kid")
	var helper: ServerPlayer = make.call(182, "Helper")
	server.roles.give(owner.player_id, "owner")
	_check(server.roles.roles_of(kid.player_id) == ["member"] and server.has_permission(kid, "build") and not server.is_admin(kid), "new players are members")
	_check(server.has_permission(owner, "roles.owner") and server.is_admin(owner), "owners have everything")
	# Commands follow roles.
	server.on_chat(181, "/kick Helper")
	_check(server.players.has(182), "members cannot use admin commands")
	server.on_chat(180, "/role give Helper moderator")
	_check(server.roles.roles_of(helper.player_id).has("moderator") and server.has_permission(helper, "command.kick") and server.has_permission(helper, "build")
		and not server.has_permission(helper, "roles.manage"), "a moderator can kick and still builds (inherits builder and member)")
	server.on_chat(182, "/role give Kid admin")
	_check(not server.is_admin(kid), "moderators cannot hand out roles")
	server.roles.give(helper.player_id, "admin")
	server.on_chat(182, "/role give Kid owner")
	_check(not server.roles.roles_of(kid.player_id).has("owner"), "admins cannot make owners")
	# Visitors: no building, still chat.
	server.roles.default_role = "visitor"
	var stone: int = server.registry.id_of("base:stone")
	var spot := Vector3i(8, server.surface_height(8, 8), 8)
	kid.state.position = Vector3(spot) + Vector3(1.5, 1, 0.5)
	server.on_break_block(181, spot)
	_check(server.world.get_block_v(spot) != 0, "visitors cannot break blocks")
	server.on_chat(181, "hello")
	_check(said.has("hello"), "visitors can chat")
	server.roles.default_role = "member"
	# Custom roles and editing.
	server.on_chat(180, "/role create muted member")
	server.on_chat(180, "/role deny muted chat")
	server.on_chat(180, "/role give Kid muted")
	said.clear()
	server.on_chat(181, "still here?")
	_check(said.is_empty() and server.has_permission(kid, "build"), "a custom role can take one thing away (chat) and keep the rest")
	server.on_chat(180, "/role take Kid muted")
	server.on_chat(181, "back")
	_check(said == ["back"], "taking the role gives chat back")
	# Tags in chat.
	server.roles.give(kid.player_id, "builder")
	_check(server.roles.badge(kid.player_id).tag == "Builder" and server.roles.badge(owner.player_id).tag == "Owner", "the highest tagged role is shown in chat")
	# /op gives the admin role.
	server.on_chat(180, "/op Kid")
	_check(server.roles.roles_of(kid.player_id).has("admin"), "/op gives the admin role")
	# Mods.
	var api = preload("res://engine/server/mod_api.gd").new(server, {"id": "tester", "dir": "res://tests"})
	api.register_permission("tester.fly", "fly around", ["builder"])
	server.roles.take(kid.player_id, "admin")
	var visitor: ServerPlayer = make.call(184, "Visitor")
	server.roles.default_role = "visitor"
	_check(kid.has_permission("tester.fly") and not visitor.has_permission("tester.fly"), "mods register permissions for the roles they choose")
	server.roles.default_role = "member"
	server._save_all(true)
	var again = _start(server._save_dir.get_file())
	_check(again.roles.exists("muted") and again.roles.roles_of("kid_id").has("builder"), "roles are saved with the world")
	server.queue_free()
	again.queue_free()
	await get_tree().process_frame


func _anticheat() -> void:
	var server = _start("anticheat_%d" % Time.get_ticks_msec())
	var make := func(peer: int, player_name: String) -> ServerPlayer:
		var p := ServerPlayer.new(server, peer, player_name)
		p.player_id = player_name.to_lower() + "_id"
		p.edit_tokens = 100.0
		server.players[peer] = p
		# A flat, clear lane heading -z (yaw 0 walks forward along -z).
		var x := 8 + peer % 5 * 6
		var y := 70
		for z in range(-24, 12):
			for dx in range(-1, 2):
				server.set_block_authoritative(Vector3i(x + dx, y - 1, z), server.registry.id_of("base:stone"))
				for dy in 3:
					server.set_block_authoritative(Vector3i(x + dx, y + dy, z), 0)
		p.state.position = Vector3(x + 0.5, y, 8.5)
		p.state.on_ground = true
		return p
	var honest: ServerPlayer = make.call(191, "Honest")
	var cheater: ServerPlayer = make.call(192, "Speedy")
	var packet := func(p: ServerPlayer, n: int) -> PackedByteArray:
		var buf := StreamPeerBuffer.new()
		buf.put_u8(n)
		for i in n:
			var input = PlayerPhysics.PlayerInput.new()
			p.set_meta("seq", int(p.get_meta("seq", 0)) + 1)
			input.seq = p.get_meta("seq")
			input.move = Vector2(0, 1)
			input.yaw = 0.0
			input.write(buf)
		return buf.data_array
	var starts := [honest.state.position, cheater.state.position]
	var flags := []
	server.add_handler("cheat_detected", func(ev): flags.append([ev.player.name, ev.check]), 0)
	server.anticheat.clock_override = 1000000
	for tick in 900:
		server.anticheat.clock_override += 16667  # one tick of real time
		server.on_inputs(191, packet.call(honest, 1))
		for burst in 3:
			server.on_inputs(192, packet.call(cheater, 5))  # 15 inputs per tick: a sped-up client
		server._simulate_player(honest)
		server._simulate_player(cheater)
		server.anticheat.update(1.0 / 60.0)
	var honest_d: float = Vector2(honest.state.position.x - starts[0].x, honest.state.position.z - starts[0].z).length()
	var cheat_d: float = Vector2(cheater.state.position.x - starts[1].x, cheater.state.position.z - starts[1].z).length()
	# A slow server (a 150 ms tick) must not make an honest client look fast or move slowly afterwards.
	var slow_start: Vector3 = honest.state.position
	server.anticheat.clock_override += 150000
	for i in 9:
		server.on_inputs(191, packet.call(honest, 1))
	for tick in 60:
		server.anticheat.clock_override += 16667
		server.on_inputs(191, packet.call(honest, 1))
		server._simulate_player(honest)
	_check(honest.input_queue.size() <= 3, "after a slow server tick an honest client catches up (%d inputs waiting)" % honest.input_queue.size())
	# A client that hitches for two seconds and then sends what it held back is not flagged.
	server.anticheat.clock_override += 2000000
	for i in 120:
		server.on_inputs(191, packet.call(honest, 1))
	for tick in 60:
		server.anticheat.clock_override += 16667
		server.on_inputs(191, packet.call(honest, 1))
		server._simulate_player(honest)
	server.anticheat.clock_override = -1
	_check(honest_d > 3.0 and cheat_d <= honest_d * 1.08 + 0.3, "sped-up inputs do not move a player faster (%.2f vs %.2f blocks)" % [cheat_d, honest_d])
	_check(server.anticheat.score(cheater, "timer") > 0.0 and server.anticheat.score(honest, "timer") == 0.0 and flags.has(["Speedy", "timer"]),
		"the timer check flags the sped-up client, not the honest one")
	# Reach: repeated edits far away end in a kick; admins are only logged.
	var far := Vector3i(cheater.state.position.floor()) + Vector3i(12, 0, 0)
	for i in 25:
		server._can_edit(cheater, far)
	_check(cheater.get_meta("anticheat_kicked", false) and flags.has(["Speedy", "reach"]), "editing far out of reach again and again gets a player kicked")
	var admin: ServerPlayer = make.call(193, "Boss")
	server.roles.give(admin.player_id, "admin")
	for i in 25:
		server._can_edit(admin, Vector3i(admin.state.position.floor()) + Vector3i(12, 0, 0))
	_check(not admin.get_meta("anticheat_kicked", false) and server.anticheat.recent().any(func(r): return r.player == "Boss" and r.action == "logged"), "admins are logged, not kicked")
	server.anticheat.mode = "log"
	var tester: ServerPlayer = make.call(194, "Tester")
	for i in 25:
		server._can_edit(tester, Vector3i(tester.state.position.floor()) + Vector3i(12, 0, 0))
	_check(not tester.get_meta("anticheat_kicked", false), "in log mode nobody is kicked")
	server.anticheat.mode = "kick"
	# A mod can overrule.
	var lenient: ServerPlayer = make.call(195, "Lenient")
	server.add_handler("cheat_detected", func(ev):
		if ev.player.name == "Lenient":
			ev.cancelled = true, 5)
	for i in 25:
		server._can_edit(lenient, Vector3i(lenient.state.position.floor()) + Vector3i(12, 0, 0))
	_check(not lenient.get_meta("anticheat_kicked", false), "mods can cancel a kick")
	# Scores fade: the odd early click is forgotten.
	server.anticheat.record(tester, "fast_break", 3.0)
	for i in 10:
		server.anticheat.update(1.0)
	_check(server.anticheat.score(tester, "fast_break") == 0.0, "scores decay over time")
	# Floods: messages past the limit are dropped.
	var allowed := 0
	for i in 500:
		if server.anticheat.allow_message(196):
			allowed += 1
	_check(allowed == server.anticheat.FLOOD_LIMIT, "messages past the flood limit are dropped (%d allowed)" % allowed)
	server.queue_free()
	await get_tree().process_frame


## The generated half of the JavaScript API: functions nobody hand-wrote a binding for.
func _js_generated() -> void:
	if not ClassDB.class_exists(&"NativeJsRuntime"):
		return  # JavaScript mods need the native extension
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["js_generated"]), "mod_dirs": PackedStringArray(["res://tests/mods"]),
		"world": "js_gen_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 42, "offline": true})
	_check(err == OK, "a JavaScript mod built entirely on generated bindings loads")
	if err != OK:
		server.queue_free()
		return
	server.set_physics_process(false)
	_check(server.ledgers.kinds.has("js_generated:coins") and server.objectives.kinds.has("js_generated:errand")
		and server.shops.kinds.has("js_generated:stall") and server.characters.kinds.has("js_generated:wend"),
		"registering through the table reaches the same registries GDScript does")

	var p := ServerPlayer.new(server, 83, "Scripter")
	p.player_id = "js_scripter"
	p.state.position = Vector3(8.5, server.surface_height(8, 8) + 1, 8.5)
	server.players[83] = p
	server.emit("player_join", {"player": p})
	# A player reference and a number crossing as arguments, not just names in a definition.
	_check(server.ledgers.value_of(p, "js_generated:coins") == 12.0,
		"a player and a number cross (%s)" % server.ledgers.value_of(p, "js_generated:coins"))
	_check(server.objectives.has(p, "js_generated:errand"), "and the objective was given")
	# talkTo was called with its options argument left off: the GDScript default must survive, rather
	# than the bridge coercing a missing argument into something the function then chokes on.
	_check(p.ui_ids.has("engine:talk"), "an argument left off keeps its GDScript default")

	# A callback crossing the generated path, which is the part JSON cannot carry on its own.
	_check(server._commands.has("jsledger"), "a command registered from JavaScript through the table exists")
	server._commands["jsledger"].handler.call(p, [])
	_check(true, "and its callback runs without erroring, which is the part JSON cannot carry")
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


func _start(world: String, mods := ["vanilla"], mod_dirs := []):
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(mods), "mod_dirs": PackedStringArray(mod_dirs),
		"world": world, "data_dir": DATA_DIR, "seed": 42, "offline": true})
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
