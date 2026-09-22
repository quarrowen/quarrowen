extends RefCounted
## Which capabilities the Proving Ground actually exercises, and which it only claims to.
##
## CLAUDE.md says the Proving Ground "uses **every** capability the engine has", and that claim is the
## whole reason the mod exists: before it, the engine was tested through the games bundled with it, so
## coverage was whatever the content happened to use. Measured on 2026-09-22 the claim was **wrong** -
## 40 of 56 `register_*` functions, with sixteen capabilities not exercised in either language. Among
## them `register_biome`, `register_sound`, `register_structure` and `register_minigame`, which are not
## corners: they are things games are made of.
##
## Nobody had lied; nobody had counted. That is the same shape as the JavaScript bridge drifting to 139
## of 262 before anybody counted, and it has the same fix - a number the suite checks, rather than a
## sentence in a document.
##
## **A ratchet, like `unbound.txt`.** The baseline is checked in and may only shrink: a capability that
## is not already listed and is not exercised fails the suite, so a new `register_*` cannot land
## without the Proving Ground using it. Removing a line means the Proving Ground now covers it, which
## is the direction this is supposed to move.
##
## Regenerate with: godot --headless --path . res://tools/mod_tool.tscn -- coverage

const MOD_API := "res://engine/server/mod_api.gd"
const PROVING := "res://tests/mods/proving"
const PROVING_JS := "res://tests/mods/proving_js"
const OUT := "res://tests/mods/proving/uncovered.txt"

const HEADER := """# Capabilities the Proving Ground does not exercise.
#
# It is supposed to exercise all of them - that is what it is for - so every line here is a gap, not an
# exemption. The list may only get shorter: tests/proving_test.gd fails when a capability appears that
# is not already here, which is what stops a new register_* landing with nothing using it.
#
# Sixteen when it was first measured (2026-09-22), because nobody had ever counted. Fixing one means
# using it in tests/mods/proving/ and deleting its line.
#
# Regenerate with: godot --headless --path . res://tools/mod_tool.tscn -- coverage

"""


## `register_*` functions no part of the Proving Ground calls, in either language, sorted.
##
## Only `register_*`: those are the capabilities. The rest of the API is queries and setters a mod uses
## when it happens to need them, and demanding every getter be called would measure diligence rather
## than coverage.
static func uncovered() -> Array:
	var used := _called()
	var out: Array = []
	for name: String in _capabilities():
		if not used.has(name):
			out.append(name)
	out.sort()
	return out


## Every `register_*` the mod API offers.
static func _capabilities() -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(MOD_API).split("\n"):
		var text: String = line
		if not text.begins_with("func register_"):
			continue
		out.append(text.get_slice("func ", 1).get_slice("(", 0).strip_edges())
	return out


## Names the Proving Ground calls, from both halves. The JavaScript side is checked in its own spelling,
## because the bridge renames on the way across and a mod written there is still the capability covered.
static func _called() -> Dictionary:
	var used := {}
	var gd := RegEx.create_from_string("api\\.([a-z_][a-z0-9_]*)\\s*\\(")
	for path: String in _files(PROVING, ".gd"):
		for m in gd.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = true
	var js := RegEx.create_from_string("api\\.([a-zA-Z][a-zA-Z0-9]*)\\s*\\(")
	var js_used := {}
	for path: String in _files(PROVING_JS, ".js"):
		for m in js.search_all(FileAccess.get_file_as_string(path)):
			js_used[m.get_string(1)] = true
	for name: String in _capabilities():
		if js_used.has(_camel(name)):
			used[name] = true
	return used


static func baseline() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(OUT):
		return out
	for line in FileAccess.get_file_as_string(OUT).split("\n"):
		var trimmed := String(line).strip_edges()
		if not trimmed.is_empty() and not trimmed.begins_with("#"):
			out.append(trimmed)
	return out


static func write() -> int:
	var lines: Array = uncovered()
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(HEADER + "\n".join(lines) + "\n")
	file.close()
	return lines.size()


static func _camel(snake: String) -> String:
	var parts := snake.split("_")
	var out := parts[0]
	for i in range(1, parts.size()):
		out += String(parts[i]).capitalize().replace(" ", "")
	return out


static func _files(root: String, suffix: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for name in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(name))
		for name in DirAccess.get_files_at(dir):
			if String(name).ends_with(suffix):
				out.append(dir.path_join(name))
	return out
