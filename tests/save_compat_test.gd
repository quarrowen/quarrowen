extends Node
## Worlds saved by earlier releases must load with everything in place: builds, chest contents, animals and
## every player's inventory and worn equipment. Each fixture in tests/fixtures/saves/<version>/ was written
## by that release (tools/make_save_fixture.tscn) together with expected.json.
##   godot --headless --path . res://tests/save_compat_test.tscn

const GameServer = preload("res://engine/server/game_server.gd")
const FIXTURES := "res://tests/fixtures/saves"

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var versions := DirAccess.get_directories_at(FIXTURES)
	_check(not versions.is_empty(), "there are save fixtures to check")
	for version in versions:
		await _check_fixture(version)
	print("[saves] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_fixture(version: String) -> void:
	var source := FIXTURES.path_join(version)
	var expected = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("expected.json")))
	if not (expected is Dictionary):
		_check(false, "%s: expected.json is readable" % version)
		return
	# Load a copy (loading saves it again in the current format).
	var work := "user://save_compat_%s_%d" % [version, Time.get_ticks_msec()]
	_copy_tree(source, work)
	var server = GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(expected.mods), "world": expected.world, "data_dir": work, "seed": 1, "offline": true})
	_check(err == OK, "%s: the world starts" % version)
	if err != OK:
		server.queue_free()
		return
	var origin := Vector3i(int(expected.origin[0]), int(expected.origin[1]), int(expected.origin[2]))
	for b in expected.blocks:
		var at := origin + Vector3i(int(b[0]), int(b[1]) - 1, int(b[2]))
		server._ensure_chunk(Vector2i(floori(at.x / 16.0), floori(at.z / 16.0)))
		var got: String = server.registry.defs[server.world.get_block_v(at)].name
		_check(got == b[3], "%s: block %s at %s (%s)" % [version, b[3], at, got])
	var chest_pos := Vector3i(int(expected.chest[0]), int(expected.chest[1]), int(expected.chest[2]))
	var chest = server.containers.get_container(chest_pos)
	for c in expected.chest_items:
		var slot: Dictionary = chest.get_item(int(c[0])) if chest != null else {}
		_check(not slot.is_empty() and server.items.name_of(slot.item) == c[1] and slot.count == int(c[2]), "%s: chest slot %d holds %d %s" % [version, int(c[0]), int(c[2]), c[1]])
	var pig_near := Vector3(float(expected.pig_near[0]), float(expected.pig_near[1]), float(expected.pig_near[2]))
	server.ensure_area_loaded(pig_near)
	_check(server.entities.in_radius(pig_near, 3.0, server.entities.registry.id_of("vanilla:pig")).size() == 1, "%s: the pig is still there" % version)
	# The player's inventory, as it loads when they join.
	server._spawn_player(71, "Fixture", str(expected.player_id))
	var p = server.players[71]
	for s in expected.inventory:
		var index := int(s[0])
		var name_there: String = server.items.name_of(p.inventory.ids[index]) if p.inventory.ids[index] > 0 else "(empty)"
		_check(name_there == s[1] and p.inventory.counts[index] == int(s[2]) and p.inventory.data[index] == s[3],
			"%s: inventory slot %d holds %d %s (%s x%d)" % [version, index, int(s[2]), s[1], name_there, p.inventory.counts[index]])
	for slot_name: String in expected.equipment:
		var index: int = p.inventory.equipment_index(slot_name)
		var worn: String = server.items.name_of(p.inventory.ids[index]) if index >= 0 and p.inventory.ids[index] > 0 else "(nothing)"
		_check(worn == expected.equipment[slot_name][0], "%s: wears %s as %s (%s)" % [version, expected.equipment[slot_name][0], slot_name, worn])
	# And again after this version saved it.
	server._store_player(p)
	server.players.erase(71)
	server._save_all(true)
	var world_dir: String = server._save_dir
	server.queue_free()
	await get_tree().process_frame
	var again = GameServer.new()
	add_child(again)
	again.start({"mods": PackedStringArray(expected.mods), "world": expected.world, "data_dir": work, "seed": 1, "offline": true})
	again._spawn_player(72, "Fixture", str(expected.player_id))
	var q = again.players[72]
	var same := true
	for s in expected.inventory:
		same = same and again.items.name_of(q.inventory.ids[int(s[0])]) == s[1] and q.inventory.counts[int(s[0])] == int(s[2])
	_check(same, "%s: the inventory survives being saved again by this version" % version)
	again.queue_free()
	await get_tree().process_frame
	_remove_tree(world_dir.get_base_dir())


func _check(ok: bool, what: String) -> void:
	print("[saves] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for sub in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(sub), to.path_join(sub))
	for file in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(file), to.path_join(file))


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
