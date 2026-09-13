extends Node
## Offline test of delta world saves (no networking):
##   godot --headless --path . res://tests/persistence_test.tscn

const GameServer = preload("res://engine/server/game_server.gd")
const Chunk = preload("res://engine/shared/chunk.gd")

const DATA_DIR := "user://persistence_test"
var _failures := 0


func _ready() -> void:
	var world := "delta_%d" % Time.get_ticks_msec()
	var pos := Vector3i(3, 70, 5)
	var reverted := Vector3i(6, 70, 5)

	var first = _start(world)
	var generator: int = first.registry.id_of("industry:coal_generator")
	var original: int = first.world.get_block_v(reverted)
	first.set_block_authoritative(pos, generator, false, 3)
	first.set_block_data(pos, {"burn": 12.5, "note": "hello"})
	first.set_block_authoritative(reverted, first.registry.id_of("base:brick"))
	first.set_block_authoritative(reverted, original)  # back to generated terrain: no delta needed
	first._ensure_chunk(Vector2i(5, 5))  # loaded but never edited
	first._save_all(true)
	var dir: String = first._save_dir
	first.queue_free()
	await get_tree().process_frame

	var saved = JSON.parse_string(FileAccess.get_file_as_string(dir + "/chunks/0_0.json"))
	_check(saved is Dictionary and saved.blocks.size() == 2, "chunk file holds exactly one edit (%s)" % str(saved.get("blocks") if saved is Dictionary else saved))
	_check(not FileAccess.file_exists(dir + "/chunks/5_5.json"), "untouched chunk was not written")

	var second = _start(world)
	_check(second.world.get_block_v(pos) == generator, "edited block restored on top of generated terrain")
	_check(second.get_block_state(pos) == 3, "block state (facing) restored")
	_check(second.world.get_block_v(reverted) == original, "reverted edit left generated terrain")
	var data: Dictionary = second.get_block_data(pos)
	_check(data.get("burn") == 12.5 and data.get("note") == "hello", "block data restored (%s)" % data)
	second.set_block_authoritative(pos, 0)
	_check(second.get_block_data(pos).is_empty(), "breaking the block cleared its data")
	second._save_all(true)
	_check(not FileAccess.file_exists(dir + "/chunks/0_0.json") or JSON.parse_string(FileAccess.get_file_as_string(dir + "/chunks/0_0.json")).blocks.size() == 2,
		"removing the only machine leaves just the air edit")
	second.queue_free()
	await get_tree().process_frame
	_remove_tree(ProjectSettings.globalize_path(DATA_DIR))
	print("[persistence] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _start(world: String):
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["vanilla", "industry"]), "world": world, "data_dir": DATA_DIR, "seed": 42, "offline": true})
	if err != OK:
		_check(false, "server start: %s" % error_string(err))
	return server


func _check(ok: bool, what: String) -> void:
	print("[persistence] %s %s" % ["ok  " if ok else "FAIL", what])
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
