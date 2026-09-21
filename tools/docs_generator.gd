extends RefCounted
## Builds the mod API reference (docs/api/index.html) from the engine's own sources, so it cannot drift:
## doc comments (##) above functions in engine/server/mod_api.gd, the player and entity scripts below
## their "Mod API" line, the event list, the TypeScript declarations for JavaScript mods, and the header
## comments of the scripts that define data formats. The output is deterministic (no dates), and
## tests/gameplay_test.gd fails when it is out of date: run `mod_tool.tscn -- docs`.

const Protocol = preload("res://engine/shared/protocol.gd")
const MOD_API := "res://engine/server/mod_api.gd"
const TYPES := "res://engine/server/js/quarrowen.d.ts"
const PRELUDE := "res://engine/server/js/prelude.js"
## The API a JavaScript mod cannot reach. A baseline rather than a target: it may shrink, and anything
## new in it fails the suite. Regenerate deliberately with `mod_tool.tscn -- bindings`.
const UNBOUND := "res://engine/server/js/unbound.txt"
## The generated half of the JavaScript API (tools/bindings_generator.gd).
const BINDINGS := "res://engine/server/js/bindings.json"
const UNBOUND_HEADER := """# Names a JavaScript mod cannot reach.
#
# Two, and both for the same structural reason: they take a GDScript object, which cannot cross JSON.
# Nothing else in the mod API is out of reach.
#
# It was 18 until 21 September 2026. Ten were real gaps on Player and Entity - saveItems,
# clearInventory and loadItems among them, without which a JavaScript mod could not hand out an arena
# gear set at all - and six were renames listed for information. Both kinds are gone now that Player
# and Entity are generated the way mod_api.gd already was, so a method added to either reaches
# JavaScript the moment it exists and cannot drift again.
#
# This list may only get shorter. tests/gameplay_test.gd fails when a name appears that is not already
# here, so a new capability cannot quietly land in one language and not the other - which is how it got
# to 128 of 262 in the first place (2026-09-20).
#
# Regenerate with: godot --headless --path . res://tools/mod_tool.tscn -- bindings
"""
const OBJECTS := [["Player", "res://engine/server/server_player.gd"], ["Entity", "res://engine/server/entity.gd"]]
## Reference pages: the header comment of each file.
const REFERENCES := [
	["mod.json and load order", "res://engine/server/mod_loader.gd"],
	["Mod script", "res://engine/server/mod.gd"],
	["Version ranges", "res://engine/shared/semver.gd"],
	["Blocks", "res://engine/shared/block_registry.gd"],
	["Blocks that join up", "res://engine/server/connect.gd"],
	["Items", "res://engine/shared/item_registry.gd"],
	["Entities", "res://engine/shared/entity_registry.gd"],
	["Mob AI settings", "res://engine/server/ai/mob_config.gd"],
	["Recipes", "res://engine/shared/recipe_registry.gd"],
	["Effects", "res://engine/shared/effect_registry.gd"],
	["Cosmetics", "res://engine/shared/cosmetics.gd"],
	["Biomes", "res://engine/server/worldgen/biome_generator.gd"],
	["World features", "res://engine/server/worldgen/features.gd"],
	["Caves", "res://engine/server/worldgen/cave_carver.gd"],
	["Structures", "res://engine/server/worldgen/structures.gd"],
	["Loot tables", "res://engine/server/loot.gd"],
	["Guidebook", "res://engine/shared/guide_registry.gd"],
	["Tutorials and tips", "res://engine/server/tutorials.gd"],
	["Crafting minigames", "res://engine/shared/minigame.gd"],
	["Stations", "res://engine/server/stations.gd"],
	["Spawning", "res://engine/server/spawning.gd"],
	["Explosions", "res://engine/server/explosions.gd"],
	["Sleep", "res://engine/server/sleep.gd"],
	["Hunger", "res://engine/server/hunger.gd"],
	["Logs and errors", "res://engine/server/dev_log.gd"],
	["Dev tools", "res://engine/server/dev_tools.gd"],
	["Dev dashboard", "res://engine/server/dev_web.gd"],
	["Reloading", "res://engine/server/mod_reload.gd"],
	["Validator", "res://engine/server/mod_validator.gd"],
]
## GDScript API sections, matched in order against function names.
const SECTIONS := [
	["Logging and debugging", ["info", "debug", "warn", "error", "debug_"]],
	["Events, commands and timers", ["on", "register_command", "after", "every", "cancel"]],
	["Guidebook and tutorials", ["guide", "tutorial", "_tip"]],
	["Crafting", ["recipe", "material", "part_type", "assembly", "minigame", "station", "container", "fuel", "process", "crafting"]],
	["Items", ["item"]],
	["Mobs and entities", ["entity", "entities", "spawn_", "projectile", "mob_", "noise", "explode", "drop_item", "spawn_caps", "spawn_rule"]],
	["World generation", ["generator", "biome", "feature", "cave", "structure", "loot", "pass"]],
	["Blocks and the world", ["block", "light", "clock", "fill", "surface", "sees_sky", "solid", "breakable", "drops", "facing", "world_time",
		"time_of_day", "daylight"]],
	["Players and gameplay", ["player", "broadcast", "gameplay", "physics", "equipment", "register_stat", "_rig", "cosmetic", "spawn_handler"]],
	["Sounds, effects and assets", ["sound", "effect", "asset"]],
	["Server", ["server_info", "storage", "world_seed"]],
]


static func write(out_dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join("index.html")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(build())
	f.close()
	return path


static func build() -> String:
	var api := parse_gdscript(FileAccess.get_file_as_string(MOD_API), "")
	var js_members := parse_ts_interface(FileAccess.get_file_as_string(TYPES), "Api")
	var js_names := {}
	for m in js_members:
		js_names[m.name] = m
	var reachable := js_reachable()
	var nav := PackedStringArray()
	var body := PackedStringArray()

	body.append(_intro())
	nav.append('<a href="#start">Getting started</a>')

	# GDScript API by section.
	var placed := {}
	var sections := []
	for s in SECTIONS:
		var fns := api.filter(func(fn): return not placed.has(fn.name) and s[1].any(func(k): return _matches(fn.name, k)))
		for fn in fns:
			placed[fn.name] = true
		sections.append([s[0], fns])
	sections.append(["Other", api.filter(func(fn): return not placed.has(fn.name))])
	nav.append('<div class="group">Mod API (api.*)</div>')
	for s in sections:
		if s[1].is_empty():
			continue
		var anchor := _slug("api-" + s[0])
		nav.append('<a href="#%s">%s</a>' % [anchor, _esc(s[0])])
		body.append('<section id="%s"><h2>%s</h2>' % [anchor, _esc(s[0])])
		for fn in s[1]:
			var camel := _camel(fn.name)
			body.append(_function_card("api", fn, camel if reachable.has(camel) else "", js_names.get(camel, {})))
		body.append("</section>")

	# Events.
	nav.append('<div class="group">Events</div><a href="#events">All events</a>')
	body.append('<section id="events"><h2>Events</h2><p>Register with <code>api.on(event, handler, priority)</code> (JS: <code>api.on</code>). Handlers get one dictionary; set <code>cancelled = true</code> where noted.</p><pre class="block">%s</pre></section>' % _esc(_header_block(FileAccess.get_file_as_string(MOD_API), "Events")))

	# Player and Entity.
	nav.append('<div class="group">Objects</div>')
	for obj in OBJECTS:
		var source := FileAccess.get_file_as_string(obj[1])
		var marker := source.find("# --- Mod API")
		var fns := parse_gdscript(source.substr(marker) if marker >= 0 else source, "")
		var ts := parse_ts_interface(FileAccess.get_file_as_string(TYPES), obj[0])
		var ts_names := {}
		for m in ts:
			ts_names[m.name] = m
		var anchor := _slug("obj-" + obj[0])
		nav.append('<a href="#%s">%s</a>' % [anchor, obj[0]])
		body.append('<section id="%s"><h2>%s</h2><p>%s</p>' % [anchor, obj[0], _esc(_file_header(source))])
		for fn in fns:
			var camel := _camel(fn.name)
			body.append(_function_card(obj[0].to_lower(), fn, camel if ts_names.has(camel) else "", ts_names.get(camel, {})))
		body.append("</section>")

	# JavaScript.
	nav.append('<div class="group">JavaScript</div><a href="#js-api">Api members</a><a href="#js-types">quarrowen.d.ts</a>')
	body.append('<section id="js-api"><h2>JavaScript: Api members</h2><p>JavaScript mods export <code>setup(api)</code>. Every GDScript function above has a camelCase twin where marked <span class="tag js">JS</span>. The full declarations:</p>')
	for m in js_members:
		body.append('<div class="card" data-search="%s"><div class="sig"><code>api.%s</code></div>%s</div>' % [_esc(m.name.to_lower()), _esc(m.signature), "<p>%s</p>" % _esc(m.doc) if not m.doc.is_empty() else ""])
	body.append("</section>")
	body.append('<section id="js-types"><h2>quarrowen.d.ts</h2><p>Copy it next to your mod (new mods get it in <code>types/</code>) for editor autocomplete.</p><pre class="block">%s</pre></section>' % _esc(FileAccess.get_file_as_string(TYPES)))

	# References.
	nav.append('<div class="group">Reference</div>')
	for r in REFERENCES:
		if not FileAccess.file_exists(r[1]):
			continue
		var anchor := _slug("ref-" + r[0])
		nav.append('<a href="#%s">%s</a>' % [anchor, _esc(r[0])])
		body.append('<section id="%s" class="ref"><h2>%s <span class="file">%s</span></h2><pre class="block">%s</pre></section>' % [
			anchor, _esc(r[0]), _esc(r[1].trim_prefix("res://")), _esc(_file_header(FileAccess.get_file_as_string(r[1])))])

	return PAGE.replace("{{nav}}", "\n".join(nav)).replace("{{body}}", "\n".join(body)).replace("{{api_version}}", Protocol.MOD_API_VERSION) \
		.replace("{{game_version}}", Protocol.GAME_VERSION)


## Every `api.*` function a JavaScript mod cannot reach, sorted. The two APIs are written by hand and
## drifted to nearly half (2026-09-20), so this is what `engine/server/js/unbound.txt` is checked
## against: the list may shrink, and a name that is not already in it fails the suite.
##
## Bound means the same thing the reference page means by it - a declaration in the `Api` interface, or
## a prelude entry - so the page and the test can never disagree about what a JavaScript mod can call.
static func unbound_js() -> Array:
	var reachable := js_reachable()
	var out := []
	for fn in parse_gdscript(FileAccess.get_file_as_string(MOD_API), ""):
		if not String(fn.signature).ends_with("(property)") and not reachable.has(_camel(fn.name)):
			out.append(String(fn.name))
	# Player and Entity too. Leaving them out let Entity.kill and Entity.teleport be added with no
	# JavaScript binding and nothing said about it, which is exactly what this list is for. (2026-09-20)
	var generated_objects: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(BINDINGS)) as Dictionary).get("objects", {})
	for obj in OBJECTS:
		var source := FileAccess.get_file_as_string(obj[1])
		var marker := source.find("# --- Mod API")
		var declared := {}
		for m in parse_ts_interface(FileAccess.get_file_as_string(TYPES), obj[0]):
			declared[m.name] = true
		var prelude := FileAccess.get_file_as_string(PRELUDE)
		for fn in parse_gdscript(source.substr(marker) if marker >= 0 else source, ""):
			if String(fn.signature).ends_with("(property)"):
				continue
			var camel := _camel(fn.name)
			if declared.has(camel) or prelude.contains("    %s(" % camel) or prelude.contains("    %s:" % camel):
				continue
			# Or generated, since 21 September 2026: Player and Entity get the same treatment mod_api
			# does, so a method added to either reaches JavaScript the moment it exists and only the
			# genuinely uncrossable are left here.
			if generated_objects.get(String(obj[0]).to_lower(), {}).has(camel):
				continue
			# What is left is mostly the rename class - perform_attack is reachable as `attack`, is_alive
			# as `alive`. Listed anyway: a name that differs between the two languages is worth knowing
			# about, and the ratchet only cares that the list does not grow.
			out.append("%s.%s" % [String(obj[0]).to_lower(), String(fn.name)])
	out.sort()
	return out


## Every camelCase name a JavaScript mod can call: declared in the TypeScript, written by hand in the
## prelude, or generated into bindings.json. One answer, so the reference page and the suite cannot
## disagree about what a JavaScript mod can reach.
static func js_reachable() -> Dictionary:
	var out := {}
	for m in parse_ts_interface(FileAccess.get_file_as_string(TYPES), "Api"):
		out[m.name] = true
	var prelude := FileAccess.get_file_as_string(PRELUDE)
	for name in (JSON.parse_string(FileAccess.get_file_as_string(BINDINGS)) as Dictionary).get("methods", {}):
		out[String(name)] = true
	for fn in parse_gdscript(FileAccess.get_file_as_string(MOD_API), ""):
		var camel := _camel(fn.name)
		if prelude.contains("    %s:" % camel) or prelude.contains("    %s(" % camel):
			out[camel] = true
	return out


## Events emitted by engine/server that the `## Events` block in mod_api.gd does not describe, sorted.
##
## 46 of 112 were undocumented when this was first counted (2026-09-21), including whole families - the
## condition_*, field_*, objective_* and vehicle_* events among them - which made several capabilities
## look absent to a mod author when they were merely unwritten. Emitting an event nobody can discover
## is most of the way to not having it.
static func undocumented_events() -> Array:
	var source := FileAccess.get_file_as_string(MOD_API)
	var documented := {}
	for line in _header_block(source, "Events").split("\n"):
		var name := line.strip_edges().get_slice(" ", 0).strip_edges()
		if not name.is_empty():
			documented[name] = true
		# Some lines describe two events, the second after the first one's payload.
		var extra := RegEx.create_from_string("\\}\\s+([a-z_]+)\\s+\\{")
		for m in extra.search_all(line):
			documented[m.get_string(1)] = true
	var emitted := {}
	var call := RegEx.create_from_string('emit\\("([a-z_]+)"')
	for path in _scripts_under("res://engine/server"):
		for m in call.search_all(FileAccess.get_file_as_string(path)):
			emitted[m.get_string(1)] = true
	var out := []
	for name: String in emitted:
		if not documented.has(name):
			out.append(name)
	out.sort()
	return out


## Every .gd under a folder, walked once.
static func _scripts_under(root: String) -> Array:
	var out := []
	var dirs := [root]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for name in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(name))
		for name in DirAccess.get_files_at(dir):
			if String(name).ends_with(".gd"):
				out.append(dir.path_join(name))
	return out


## Host methods the prelude calls that `js_mod.gd` does not answer. Checked against the prelude rather
## than the TypeScript because the prelude is what actually calls across, and it renames on the way
## (`registerLootTable` asks for `registerLoot`) - comparing declared names instead reports both of
## those as broken when neither is.
##
## A miss here is invisible until a mod runs the line: the bridge returns "unknown method" from inside
## somebody else's game rather than failing in our suite.
static func unkept_js() -> Array:
	var host := FileAccess.get_file_as_string("res://engine/server/js_mod.gd")
	var prelude := FileAccess.get_file_as_string(PRELUDE)
	var seen := {}
	var out := []
	var wanted := RegEx.create_from_string('host\\(\\s*"([A-Za-z0-9_.]+)"')
	for m in wanted.search_all(prelude):
		var name := m.get_string(1)
		if seen.has(name):
			continue
		seen[name] = true
		# player.* and entity.* are dispatched by prefix, not by a case of their own.
		var stem := name.get_slice(".", 0)
		if not host.contains('"%s"' % name) and not host.contains('"%s."' % stem):
			out.append(name)
	out.sort()
	return out


## Public functions with their doc comments: [{name, signature, doc}].
static func parse_gdscript(source: String, _prefix: String) -> Array:
	var out := []
	var lines := source.split("\n")
	var doc := PackedStringArray()
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		if line.begins_with("##"):
			doc.append(line.substr(2).strip_edges() if line.length() > 2 else "")
			i += 1
			continue
		if line.begins_with("func ") or line.begins_with("static func "):
			var sig := line
			while not sig.strip_edges().ends_with(":") and i + 1 < lines.size():
				i += 1
				sig += " " + lines[i].strip_edges()
			var name := sig.get_slice("func ", 1).get_slice("(", 0).strip_edges()
			if not name.begins_with("_"):
				out.append({"name": name, "signature": sig.trim_suffix(":").replace("static func ", "static ").replace("func ", "").strip_edges(),
					"doc": "\n".join(doc)})
		elif line.begins_with("var ") and not line.begins_with("var _") and not doc.is_empty():
			var name := line.substr(4).get_slice(":", 0).get_slice(" ", 0).strip_edges()
			out.append({"name": name, "signature": line.trim_suffix(":").substr(4).strip_edges() + "  (property)", "doc": "\n".join(doc)})
		if not line.begins_with("##"):
			doc = PackedStringArray()
		i += 1
	return out


## Members of `export interface <name>` or `export class <name>`: [{name, signature, doc}].
static func parse_ts_interface(source: String, interface_name: String) -> Array:
	var start := -1
	# Player and Entity are declared as classes, not interfaces, and looking only for interfaces meant
	# the reference page never tagged a single one of their methods as reachable from JavaScript -
	# quietly, for as long as the page has existed. (2026-09-20)
	for keyword in ["interface", "class"]:
		start = source.find("export %s %s {" % [keyword, interface_name])
		if start < 0:
			start = source.find("export %s %s " % [keyword, interface_name])
		if start >= 0:
			break
	if start < 0:
		return []
	var i := source.find("{", start) + 1
	var depth := 1
	var out := []
	var current := ""
	var doc := ""
	while i < source.length() and depth > 0:
		var c := source[i]
		if source.substr(i, 3) == "/**":
			var end := source.find("*/", i)
			doc = source.substr(i + 3, end - i - 3).replace("*", "").strip_edges()
			i = end + 2
			continue
		if c in "{(<[":
			depth += 1
		elif c in "})>]":
			depth -= 1
			if depth == 0:
				break
		if c == ";" and depth == 1:
			var member := " ".join(current.strip_edges().split("\n")).strip_edges()
			var name := member.get_slice("(", 0).get_slice(":", 0).get_slice("<", 0).strip_edges().trim_suffix("?")
			if not name.is_empty():
				out.append({"name": name, "signature": _collapse(member), "doc": doc})
			current = ""
			doc = ""
		else:
			current += c
		i += 1
	return out


static func _collapse(text: String) -> String:
	var out := text
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out


static func _function_card(owner: String, fn: Dictionary, js: String, ts: Dictionary) -> String:
	var tags := '<span class="tag js" title="%s">JS %s</span>' % [_esc(ts.get("signature", js)), _esc(js)] if not js.is_empty() else ""
	var doc: String = fn.doc
	return '<div class="card" id="%s" data-search="%s"><div class="sig"><code>%s.%s</code>%s</div>%s</div>' % [
		_slug(owner + "-" + fn.name), _esc((fn.name + " " + js + " " + doc).to_lower()), owner, _esc(fn.signature), tags,
		"<p>%s</p>" % _esc(doc).replace("\n", "<br>") if not doc.is_empty() else '<p class="muted">No description yet.</p>']


## The leading ## comment block of a file (after `extends` / class_name).
static func _file_header(source: String) -> String:
	var lines := PackedStringArray()
	var started := false
	for line in source.split("\n"):
		if line.begins_with("##"):
			started = true
			lines.append(line.substr(3) if line.length() > 2 else "")
		elif started:
			break
		elif not (line.begins_with("extends") or line.begins_with("class_name") or line.strip_edges().is_empty() or line.begins_with("@")):
			break
	return "\n".join(lines)


## The ## lines after "## <title>" in a file's header, up to the first line that is not a comment.
static func _header_block(source: String, title: String) -> String:
	var lines := PackedStringArray()
	var inside := false
	for line in source.split("\n"):
		if not inside and line.begins_with("## %s" % title):
			inside = true
			continue
		if inside:
			if not line.begins_with("##"):
				break
			lines.append(line.substr(3) if line.length() > 2 else "")
	return "\n".join(lines)


## Short keys must match the whole name; longer ones anywhere in it.
static func _matches(name: String, key: String) -> bool:
	return name == key or (key.length() > 3 and name.contains(key))


## Shared with tools/bindings_generator.gd, which must name a host method exactly the way the reference
## page says it is named.
static func camel(snake: String) -> String:
	return _camel(snake)


static func _camel(snake: String) -> String:
	var parts := snake.split("_")
	var out := parts[0]
	for i in range(1, parts.size()):
		out += parts[i].capitalize()
	return out


static func _slug(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if c in "abcdefghijklmnopqrstuvwxyz0123456789-" else "-"
	return out


static func _esc(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


static func _intro() -> String:
	return """<section id="start"><h1>Quarrowen mod API</h1>
<p class="lead">Mod API {{api_version}} · game {{game_version}}. Generated from the engine sources by <code>mod_tool.tscn -- docs</code>.</p>
<h3>Make a mod in a minute</h3>
<ol>
<li>In the game menu choose <b>Create a mod</b>, or run <code>godot --headless --path . res://tools/mod_tool.tscn -- new my_mod [--lang=js] [--kind=game]</code>.</li>
<li>Host it with developer tools: <code>godot --path . -- --host=vanilla,my_mod --dev</code>.</li>
<li>Edit <code>main.gd</code> or <code>main.js</code> and save: the server reloads the mod. Press <b>F8</b> for logs, errors, the inspector, the event trace and the profiler.</li>
<li>Check it with <code>mod_tool.tscn -- validate my_mod</code> and share it with <code>mod_tool.tscn -- pack my_mod</code>.</li>
</ol>
<p>A GDScript mod is a folder with <code>mod.json</code> and <code>main.gd</code> (<code>extends "res://engine/server/mod.gd"</code>, <code>func setup(api)</code>); a JavaScript mod exports <code>setup(api)</code> from <code>main.js</code>. Names without a colon are your mod's own (<code>"crate"</code> means <code>"my_mod:crate"</code>).</p>
</section>"""


const PAGE := """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Quarrowen Mod API {{api_version}}</title>
<style>
:root { --bg: #fbfaf7; --panel: #ffffff; --line: #e6e2d8; --text: #25231f; --muted: #7a7466; --accent: #2f6fd0; --code: #f3f0e8; --tag: #e7f0ff; }
@media (prefers-color-scheme: dark) { :root { --bg: #111317; --panel: #171a20; --line: #2a2f38; --text: #dde1e7; --muted: #8b919c; --accent: #7fb0ff; --code: #1f232b; --tag: #1d2a40; } }
* { box-sizing: border-box; }
body { margin: 0; font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; background: var(--bg); color: var(--text); }
.layout { display: grid; grid-template-columns: 260px minmax(0, 1fr); min-height: 100vh; }
@media (max-width: 800px) { .layout { grid-template-columns: 1fr; } nav { position: static !important; height: auto !important; } }
nav { position: sticky; top: 0; height: 100vh; overflow: auto; padding: 16px; border-right: 1px solid var(--line); background: var(--panel); }
nav a { display: block; padding: 3px 6px; color: var(--text); text-decoration: none; border-radius: 4px; font-size: 14px; }
nav a:hover { background: var(--code); }
nav .group { margin: 14px 0 4px; font-size: 12px; text-transform: uppercase; letter-spacing: .05em; color: var(--muted); }
#search { width: 100%; padding: 8px 10px; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--text); font: inherit; }
main { padding: 24px clamp(16px, 4vw, 48px); max-width: 1100px; }
h1 { margin-top: 0; } h2 { margin-top: 40px; border-bottom: 1px solid var(--line); padding-bottom: 6px; }
.lead { color: var(--muted); }
code { background: var(--code); padding: 1px 5px; border-radius: 4px; font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; }
pre.block { background: var(--code); padding: 12px 14px; border-radius: 6px; overflow-x: auto; font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; white-space: pre; }
.card { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 10px 14px; margin: 10px 0; }
.card p { margin: 6px 0 0; }
.sig { display: flex; flex-wrap: wrap; gap: 8px; align-items: baseline; }
.sig code { background: none; padding: 0; font-size: 14px; font-weight: 600; white-space: pre-wrap; word-break: break-word; }
.tag { font-size: 12px; padding: 1px 7px; border-radius: 10px; background: var(--tag); color: var(--accent); cursor: help; }
.muted { color: var(--muted); }
.file { font-size: 13px; font-weight: normal; color: var(--muted); }
.hidden { display: none; }
</style>
</head>
<body>
<div class="layout">
<nav>
<input id="search" type="search" placeholder="Search functions…" autocomplete="off">
{{nav}}
</nav>
<main>
{{body}}
</main>
</div>
<script>
const search = document.getElementById("search");
search.addEventListener("input", () => {
  const q = search.value.trim().toLowerCase();
  document.querySelectorAll(".card").forEach((c) => c.classList.toggle("hidden", q !== "" && !c.dataset.search.includes(q)));
  document.querySelectorAll("section").forEach((s) => {
    const cards = s.querySelectorAll(".card");
    s.classList.toggle("hidden", q !== "" && (cards.length === 0 || [...cards].every((c) => c.classList.contains("hidden"))));
  });
});
</script>
</body>
</html>
"""
