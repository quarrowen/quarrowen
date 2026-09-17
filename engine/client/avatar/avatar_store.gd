extends RefCounted
## The player's portable avatar (built-in cosmetics and colors), saved on this computer and sent to
## every server on join. QW_AVATAR_FILE overrides the location.

const Cosmetics = preload("res://engine/shared/cosmetics.gd")

const PATH := "user://avatar.json"


static func path() -> String:
	var override := OS.get_environment("QW_AVATAR_FILE")
	return override if not override.is_empty() else PATH


static func load_avatar() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path()))
	var registry := Cosmetics.new()
	preload("res://engine/client/creation_library.gd").register_all(registry, {})  # the player's own creations are portable too
	return registry.sanitize_avatar(parsed.get("avatar") if parsed is Dictionary else null)


static func save_avatar(avatar: Dictionary) -> bool:
	var file := FileAccess.open(path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "avatar": avatar}, "\t"))
	return true
