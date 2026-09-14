extends RefCounted
## Creates starter mods: GDScript or JavaScript, an add-on (played with another game, e.g. vanilla) or
## a game (its own world). Each comes with a block, an item and recipes, an event handler that logs and
## draws debug shapes, a command, a guide page, a tutorial, generated textures and a README with the
## development loop (--dev, F8, save to reload, /validate, packing).
## Used by the Host menu's "Create a mod" and `tools/mod_tool.tscn -- new`.

const ModLoader = preload("res://engine/server/mod_loader.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const TYPES_SOURCE := "res://engine/server/js/voxelcraft.d.ts"


## options: id, name, language ("gdscript" | "javascript"), kind ("addon" | "game"), author, description.
## Returns {ok, dir, files: [relative paths], error}.
static func create(parent_dir: String, options: Dictionary) -> Dictionary:
	var id := str(options.get("id", ""))
	if not ModLoader._is_valid_id(id):
		return {"ok": false, "error": "the id must be 1-32 characters of a-z, 0-9 and _"}
	if id in ["base", "vanilla", "engine"]:
		return {"ok": false, "error": "'%s' is taken by the engine or a bundled mod" % id}
	var dir := parent_dir.path_join(id)
	if DirAccess.dir_exists_absolute(dir) or FileAccess.file_exists(dir.path_join("mod.json")):
		return {"ok": false, "error": "%s already exists" % dir}
	var js := str(options.get("language", "gdscript")).begins_with("j")
	var game := str(options.get("kind", "addon")) == "game"
	var vars := {
		"id": id,
		"name": str(options.get("name", id.capitalize())).strip_edges(),
		"author": str(options.get("author", "")).strip_edges(),
		"engine": "^%s.0" % Protocol.MOD_API_VERSION.get_slice(".", 0),
	}
	if vars.name.is_empty():
		vars.name = id.capitalize()
	var description := str(options.get("description", ""))
	if description.is_empty():
		description = "A new game made with VoxelCraft." if game else "Adds a crate, a gem and a little tutorial. Play it with any game, e.g. --mods=vanilla,%s" % id
	var manifest := {"id": id, "name": vars.name, "version": "0.1.0", "description": description, "authors": [vars.author] if not vars.author.is_empty() else [],
		"engine": vars.engine, "depends": ["base@^1.0"], "game": game}
	if js:
		manifest.main = "main.js"
	var files := {"mod.json": JSON.stringify(manifest, "\t") + "\n", "README.md": _fill(README, vars, js, game)}
	if js:
		files["main.js"] = _fill(JS_MAIN, vars, js, game)
		if FileAccess.file_exists(TYPES_SOURCE):
			files["types/voxelcraft.d.ts"] = FileAccess.get_file_as_string(TYPES_SOURCE)
		files["jsconfig.json"] = JSON.stringify({"compilerOptions": {"checkJs": true, "module": "es2020", "target": "es2020"}, "include": ["main.js", "types"]}, "\t") + "\n"
	else:
		files["main.gd"] = _fill(GD_MAIN, vars, js, game)
		files["guide.gd"] = _fill(GD_GUIDE, vars, js, game)
	DirAccess.make_dir_recursive_absolute(dir.path_join("textures"))
	for rel in files:
		DirAccess.make_dir_recursive_absolute(dir.path_join(rel).get_base_dir())
		var f := FileAccess.open(dir.path_join(rel), FileAccess.WRITE)
		if f == null:
			return {"ok": false, "error": "could not write %s (%s)" % [dir.path_join(rel), error_string(FileAccess.get_open_error())]}
		f.store_string(files[rel])
		f.close()
	_crate_texture().save_png(dir.path_join("textures/crate.png"))
	_gem_icon().save_png(dir.path_join("textures/gem.png"))
	var written: Array = files.keys()
	written.append_array(["textures/crate.png", "textures/gem.png"])
	return {"ok": true, "dir": dir, "files": written, "game": game, "language": "javascript" if js else "gdscript"}


## A valid id from a display name ("My Cool Mod" -> "my_cool_mod").
static func id_from_name(display_name: String) -> String:
	var out := ""
	for c in display_name.to_lower():
		if c in "abcdefghijklmnopqrstuvwxyz0123456789":
			out += c
		elif not out.ends_with("_") and not out.is_empty():
			out += "_"
	out = out.trim_suffix("_").left(32)
	if not out.is_empty() and out[0] in "0123456789":
		out = "mod_" + out.left(28)
	return out


static func _fill(template: String, vars: Dictionary, js: bool, game: bool) -> String:
	var text := template
	# {{#game}} ... {{/game}} and {{^game}} ... {{/game}} sections.
	for tag in ["game"]:
		var on := game
		text = _section(text, "{{#%s}}" % tag, "{{/%s}}" % tag, on)
		text = _section(text, "{{^%s}}" % tag, "{{/%s}}" % tag, not on)
	text = _section(text, "{{#js}}", "{{/js}}", js)
	text = _section(text, "{{^js}}", "{{/js}}", not js)
	for key in vars:
		text = text.replace("{{%s}}" % key, str(vars[key]))
	return text


static func _section(text: String, open: String, close: String, keep: bool) -> String:
	while true:
		var start := text.find(open)
		if start < 0:
			return text
		var end := text.find(close, start)
		if end < 0:
			return text
		var inner := text.substr(start + open.length(), end - start - open.length())
		text = text.left(start) + (inner if keep else "") + text.substr(end + close.length())
	return text


static func _crate_texture() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in 16:
		for x in 16:
			var edge := x == 0 or y == 0 or x == 15 or y == 15
			var brace := absi(x - y) <= 1 or absi(x - (15 - y)) <= 1
			var base := Color(0.62, 0.43, 0.24) if not (edge or brace) else Color(0.42, 0.27, 0.13)
			var v := rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(base.r + v, base.g + v, base.b + v))
	return img


static func _gem_icon() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := absf(x - 7.5) + absf(y - 8.0) * 1.3
			if d < 7.0:
				var shade := 1.0 - d / 9.0
				img.set_pixel(x, y, Color(0.3 * shade, 0.75 * shade + 0.2, 0.95 * shade + 0.05))
			if d < 2.5 and x < 8 and y < 8:
				img.set_pixel(x, y, Color(0.85, 1.0, 1.0))
	return img


const GD_MAIN := """extends "res://engine/server/mod.gd"
## {{name}}: a starter mod. Start a dev server (see README.md), change anything here and save: the server
## reloads the mod by itself. F8 opens the dev tools (logs, errors, inspector, events, profiler).

const Guide = preload("guide.gd")

var api


func setup(mod_api) -> void:
	api = mod_api
	api.info("{{name}} is loading")
{{#game}}
	# The world: one grassy biome with trees (see README for more biomes and features).
	api.set_server_info({"name": "{{name}}", "motd": "Welcome to {{name}}! Press G for the guide."})
	api.use_biome_generator()
	api.register_feature("tree", {"type": "tree", "trunk": "base:log", "leaves": "base:leaves", "height": [4, 6]})
	api.register_biome("meadow", {"climate": {}, "height": {"base": 50, "variation": 4},
		"features": [{"feature": "tree", "per_chunk": 1.5}],
		"plants": [{"block": "base:tall_grass", "chance": 0.2, "on": ["base:grass"]}]})
	api.on("player_join", func(ev):
		if ev.first_time:
			ev.player.give(api.item("base:planks"), 8))
{{/game}}

	# A block. Textures are files in this mod's folder; sounds come from base.
	api.register_block("crate", {"display_name": "{{name}} Crate", "textures": "textures/crate.png", "hardness": 1.5, "tool": "axe",
		"sounds": {"break": "base:wood", "place": "base:wood", "step": "base:wood_step"}})
	# An item, and recipes for both (the crate at a crafting table, gems by hand).
	api.register_item("gem", {"display_name": "Shiny Gem", "icon": "textures/gem.png", "lore": ["Found in {{name}} crates."]})
	api.register_recipe({"base:planks": 4, "base:cobblestone": 1}, "crate", 1, {"station": "crafting_table", "unlock": "known"})
	api.register_recipe({"{{id}}:gem": 2}, "base:torch", 4, {"unlock": "pickup"})

	# Events: breaking a crate sometimes gives a gem.
	api.on("block_broken", _on_block_broken)
	# A command: /{{id}}
	api.register_command("{{id}}", "- say hello and get a gem", func(player, _args):
		player.send_message("Hello from {{name}}!")
		player.give(api.item("gem"), 1))

	Guide.new().setup(api)


func _on_block_broken(ev: Dictionary) -> void:
	if ev.block != api.block("crate"):
		return
	var at := Vector3(ev.position) + Vector3(0.5, 0.5, 0.5)
	# Debug lines only show with `/log level {{id}} debug`; debug shapes with F8 > Draw.
	api.debug("crate broken at %s" % ev.position)
	api.debug_box(Vector3(ev.position), Vector3(ev.position) + Vector3.ONE, "#ffcc00", 3.0, "crate")
	if randf() < 0.6:
		api.drop_item(api.item("gem"), 1, at)
"""

const GD_GUIDE := """extends RefCounted
## {{name}}'s pages in the guidebook (G) and a short tutorial.


func setup(api) -> void:
	api.register_guide_chapter("{{id}}", {"title": "{{name}}", "icon": "{{id}}:gem", "order": 60,
		"description": "What {{name}} adds."})
	api.register_guide_page("crates", {"chapter": "{{id}}", "title": "Crates and Gems", "icon": "{{id}}:crate",
		"keywords": "crate gem",
		"blocks": [
			{"type": "text", "text": "Build a [b]crate[/b] at a crafting table, then break it: most crates hold a gem."},
			{"type": "recipe", "output": "{{id}}:crate"},
			{"type": "items", "items": ["{{id}}:crate", "{{id}}:gem"]},
			{"type": "tip", "text": "Type /{{id}} for a free gem."},
		]})
	api.register_tutorial("first_gem", {"title": "{{name}}: First Gem", "order": 50,
		"description": "Make a crate and find a gem.",
		"steps": [
			{"title": "Build a crate", "text": "Craft a crate at a crafting table.", "icon": "{{id}}:crate",
				"goal": {"type": "craft", "target": "{{id}}:crate"}, "page": "{{id}}:crates"},
			{"title": "Break it open", "text": "Place the crate and break it.", "icon": "{{id}}:crate",
				"goal": {"type": "break", "target": "{{id}}:crate"}},
			{"title": "Hold a gem", "icon": "{{id}}:gem", "goal": {"type": "have", "target": "{{id}}:gem"}},
		]})
"""

const JS_MAIN := """// {{name}}: a starter mod. Start a dev server (see README.md), change anything here and save: the
// server reloads the mod by itself. F8 opens the dev tools (logs, errors, inspector, events, profiler).
// Types for editor autocomplete: types/voxelcraft.d.ts (kept up to date by the engine's copy).
// @ts-check

/** @param {import("voxelcraft").Api} api */
export function setup(api) {
  console.log("{{name}} is loading");
{{#game}}
  // The world: one grassy biome with trees (see README for more biomes and features).
  api.setServerInfo({ name: "{{name}}", motd: "Welcome to {{name}}! Press G for the guide." });
  api.useBiomeGenerator();
  api.registerFeature("tree", { type: "tree", trunk: "base:log", leaves: "base:leaves", height: [4, 6] });
  api.registerBiome("meadow", { climate: {}, height: { base: 50, variation: 4 },
    features: [{ feature: "tree", per_chunk: 1.5 }],
    plants: [{ block: "base:tall_grass", chance: 0.2, on: ["base:grass"] }] });
  api.on("player_join", ({ player, first_time }) => {
    if (first_time) player.give(api.item("base:planks"), 8);
  });
{{/game}}

  // A block. Textures are files in this mod's folder; sounds come from base.
  const crate = api.registerBlock("crate", { display_name: "{{name}} Crate", textures: "textures/crate.png", hardness: 1.5, tool: "axe",
    sounds: { break: "base:wood", place: "base:wood", step: "base:wood_step" } });
  // An item, and recipes for both (the crate at a crafting table, torches from gems by hand).
  const gem = api.registerItem("gem", { display_name: "Shiny Gem", icon: "textures/gem.png", lore: ["Found in {{name}} crates."] });
  api.registerRecipe({ "base:planks": 4, "base:cobblestone": 1 }, "{{id}}:crate", 1, { station: "crafting_table", unlock: "known" });
  api.registerRecipe({ "{{id}}:gem": 2 }, "base:torch", 4, { unlock: "pickup" });

  // Events: breaking a crate sometimes gives a gem.
  api.on("block_broken", ({ block, position }) => {
    if (block !== crate) return;
    // Debug lines only show with `/log level {{id}} debug`; debug shapes with F8 > Draw.
    console.debug(`crate broken at ${position.x}, ${position.y}, ${position.z}`);
    api.draw.box(position, { x: position.x + 1, y: position.y + 1, z: position.z + 1 }, "#ffcc00", 3, "crate");
    if (Math.random() < 0.6) api.dropItem(gem, 1, { x: position.x + 0.5, y: position.y + 0.5, z: position.z + 0.5 });
  });

  // A command: /{{id}}
  api.command("{{id}}", "- say hello and get a gem", (player) => {
    player.sendMessage("Hello from {{name}}!");
    player.give(gem, 1);
  });

  // The guidebook (G) and a short tutorial.
  api.registerGuideChapter("{{id}}", { title: "{{name}}", icon: "{{id}}:gem", order: 60, description: "What {{name}} adds." });
  api.registerGuidePage("crates", { chapter: "{{id}}", title: "Crates and Gems", icon: "{{id}}:crate", keywords: "crate gem",
    blocks: [
      { type: "text", text: "Build a [b]crate[/b] at a crafting table, then break it: most crates hold a gem." },
      { type: "recipe", output: "{{id}}:crate" },
      { type: "items", items: ["{{id}}:crate", "{{id}}:gem"] },
      { type: "tip", text: "Type /{{id}} for a free gem." },
    ] });
  api.registerTutorial("first_gem", { title: "{{name}}: First Gem", order: 50, description: "Make a crate and find a gem.",
    steps: [
      { title: "Build a crate", text: "Craft a crate at a crafting table.", icon: "{{id}}:crate", goal: { type: "craft", target: "{{id}}:crate" }, page: "{{id}}:crates" },
      { title: "Break it open", text: "Place the crate and break it.", icon: "{{id}}:crate", goal: { type: "break", target: "{{id}}:crate" } },
      { title: "Hold a gem", icon: "{{id}}:gem", goal: { type: "have", target: "{{id}}:gem" } },
    ] });
}
"""

const README := """# {{name}}

{{#game}}A game{{/game}}{{^game}}An add-on{{/game}} made with VoxelCraft ({{#js}}JavaScript{{/js}}{{^js}}GDScript{{/js}}).

## Try it

From the game's menu, **Create a mod** hosts it for you. Or from the command line (project folder):

```
godot --path . -- --host={{#game}}{{id}}{{/game}}{{^game}}vanilla,{{id}}{{/game}} --dev
```

`--dev` turns on the developer tools for everyone on the server and the file watcher.

## The loop

- Edit `{{#js}}main.js{{/js}}{{^js}}main.gd{{/js}}` and save: the server reloads the mod within a second and says so in chat.
  New blocks, items, textures or sounds need `/reload full` (you reconnect automatically).
- **F8** opens the dev tools: Logs, Errors (with file:line), Inspect (look at something), Events (a live
  trace), Perf (time per mod) and Draw (debug shapes, mob AI). The server also prints a dashboard link.
- `/log level {{id}} debug` shows your debug lines; `/errors` lists script errors.
- `/{{id}}` runs the example command; press **G** for the guide page and the pause menu for the tutorial.

## Check and share

```
godot --headless --path . res://tools/mod_tool.tscn -- validate {{id}}
godot --headless --path . res://tools/mod_tool.tscn -- pack {{id}}
```

`validate` finds mistakes (typos in mod.json, missing textures, names that do not exist). `pack` writes
`build/mods/{{id}}-0.1.0.zip`, which any server loads from its mods folder. Bump `version` in mod.json
for each release; other mods can depend on it with `"{{id}}@^0.1"`.

The API reference is in `docs/api/index.html` in the engine folder.
"""
