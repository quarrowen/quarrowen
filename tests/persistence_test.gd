extends Node
## Offline test of delta world saves (no networking):
##   godot --headless --path . res://tests/persistence_test.tscn

const GameServer = preload("res://engine/server/game_server.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const WorldBackups = preload("res://engine/server/world_backups.gd")

const DATA_DIR := "user://persistence_test"
var _failures := 0


func _ready() -> void:
	var world := "delta_%d" % Time.get_ticks_msec()
	var pos := Vector3i(3, 70, 5)
	var reverted := Vector3i(6, 70, 5)

	var first = _start(world)
	var generator: int = first.registry.id_of("proving:core")
	var original: int = first.world.get_block_v(reverted)
	first.set_block_authoritative(pos, generator, false, 3)
	first.set_block_data(pos, {"burn": 12.5, "note": "hello"})
	first.set_block_authoritative(reverted, first.registry.id_of("base:brick"))
	first.set_block_authoritative(reverted, original)  # back to generated terrain: no delta needed
	first._ensure_chunk(Vector2i(5, 5))  # loaded but never edited
	# A shared store has no position, so it is not in any chunk file - it rides in the world's meta.
	var vault = first.mod_instances.proving.api.get_shared("vault")
	_check(vault != null, "the shared store the mod declared exists")
	if vault != null:
		vault.set_item(0, first.items.id_of("proving:grain"), 9, {})
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
	# The store survived, and survived the merge that runs after the mods redeclare it: declaring on
	# load used to replace the saved table outright, which emptied every vault on restart.
	var vault_again = second.mod_instances.proving.api.get_shared("vault")
	_check(vault_again != null and vault_again.get_item(0).count == 9,
		"a shared store keeps its contents across a restart (%d)" % (vault_again.get_item(0).count if vault_again else -1))
	second.set_block_authoritative(pos, 0)
	_check(second.get_block_data(pos).is_empty(), "breaking the block cleared its data")
	second._save_all(true)
	_check(not FileAccess.file_exists(dir + "/chunks/0_0.json") or JSON.parse_string(FileAccess.get_file_as_string(dir + "/chunks/0_0.json")).blocks.size() == 2,
		"removing the only machine leaves just the air edit")
	second.queue_free()
	await get_tree().process_frame

	# Backups: archive, change the world, restore the archive at startup, prune old archives.
	var third = _start(world, {"backup_keep": 2})
	var brick: int = third.registry.id_of("base:brick")
	third.set_block_authoritative(pos, brick)
	for i in 3:
		_check(third.backup_now(), "backup %d started" % (i + 1))
		_check(not third.backup_now(), "second concurrent backup refused")
		while third._backup_task != -1:
			third._poll_backup(0.0)
			await get_tree().process_frame
		_check(third._backup_job.error == "", "backup %d written %s" % [i + 1, third._backup_job.error])
		await get_tree().create_timer(1.1).timeout  # distinct timestamps in names
	var backups := WorldBackups.list(third._backup_dir)
	_check(backups.size() == 2, "old backups pruned to backup_keep (%d)" % backups.size())
	third.set_block_authoritative(pos, 0)
	third.queue_free()
	await get_tree().process_frame
	var restored = _start(world, {"restore": "latest"})
	_check(restored.world.get_block_v(pos) == brick, "restoring the latest backup brings the block back")
	var aside := Array(DirAccess.get_directories_at(DATA_DIR)).filter(func(d): return d.begins_with(world + ".before-restore-"))
	_check(aside.size() == 1, "previous world kept aside (%s)" % str(aside))
	restored.queue_free()
	await get_tree().process_frame
	var missing = GameServer.new()
	add_child(missing)
	_check(missing.start({"mods": PackedStringArray(["base", "proving"]), "mod_dirs": PackedStringArray(["res://tests/mods"]), "world": world, "data_dir": DATA_DIR, "offline": true, "restore": "nope.zip"}) != OK,
		"restoring a missing backup refuses to start")
	missing.queue_free()
	await get_tree().process_frame
	_remove_tree(ProjectSettings.globalize_path(DATA_DIR))
	print("[persistence] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _start(world: String, extra := {}):
	var server := GameServer.new()
	add_child(server)
	var config := {"mods": PackedStringArray(["base", "proving"]), "mod_dirs": PackedStringArray(["res://tests/mods"]), "world": world, "data_dir": DATA_DIR, "seed": 42, "offline": true}
	config.merge(extra, true)
	var err: Error = server.start(config)
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
