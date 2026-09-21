extends SceneTree
## Repaints the blocks a landscape shows, in one named style, so two renders of the same view differ
## only by the look being judged.
##
##   godot --headless --path . -s tools/look_lab.gd -- --style=flat
##   git checkout -- mods/base/textures    # put the real ones back
##
## **It overwrites `mods/base/textures/`**, on purpose: reusing base's real block definitions means
## the picture is of the game rather than of a mock-up. Restore them from git when you are done.
##
## Only the dozen or so textures a landscape actually shows are written. Restyling all 333 to make a
## decision would be doing the work before deciding whether to do it. (2026-09-21)

const TILE := 16
const OUT := "res://mods/base/textures/"

## Each style is a palette plus a way of painting a surface. Kept as data so a new one to try is four
## lines rather than a new script, and so the differences between them are readable side by side.
const STYLES := {
	"current": {
		"paint": "noise", "tile": 16, "noise": 0.07,
		"colors": {"stone": "#7d7d81", "dirt": "#78522f", "grass": "#61a340", "grass_side": "#78522f",
			"sand": "#ded6a3", "gravel": "#8a8a8a", "water": "#3a62c8", "log": "#6b5436",
			"log_top": "#8a7048", "leaves": "#3f7a35", "planks": "#a4824c", "snow": "#f2f6ff",
			"tall_grass": "#5d9c3c", "fern": "#4e8a38"}},
	"flat": {
		# No pixel noise at all: one colour a face. Shape and light carry everything, which is the
		# look closest to a toy world.
		"paint": "flat", "tile": 16, "noise": 0.0,
		"colors": {"stone": "#9aa0ad", "dirt": "#a9714a", "grass": "#7ec850", "grass_side": "#a9714a",
			"sand": "#f2e2ad", "gravel": "#b4b8bd", "water": "#47b7e5", "log": "#8a6035",
			"log_top": "#b08a55", "leaves": "#5fbf4a", "planks": "#d2a869", "snow": "#ffffff",
			"tall_grass": "#79c44c", "fern": "#63b544"}},
	"soft": {
		# The same pixel idea as now, but calmer: less noise, less contrast, a warmer light.
		"paint": "noise", "tile": 16, "noise": 0.025,
		"colors": {"stone": "#9a9690", "dirt": "#9c7350", "grass": "#84b063", "grass_side": "#9c7350",
			"sand": "#e8dcb4", "gravel": "#a8a49e", "water": "#5b8fd0", "log": "#8a6f4e",
			"log_top": "#a38a63", "leaves": "#6f9c5c", "planks": "#c0a074", "snow": "#f6f8fb",
			"tall_grass": "#80aa60", "fern": "#6f9757"}},
	"storybook": {
		# Muted and warm, with visible brush-ish variation rather than even noise - the look of a
		# painted picture book rather than a screen.
		"paint": "brush", "tile": 16, "noise": 0.05,
		"colors": {"stone": "#a39a8e", "dirt": "#9d7550", "grass": "#8fae5e", "grass_side": "#9d7550",
			"sand": "#e6d5a8", "gravel": "#ada396", "water": "#6d9ab8", "log": "#8b6b48",
			"log_top": "#a98d61", "leaves": "#7d9e57", "planks": "#c3a173", "snow": "#f4f1e8",
			"tall_grass": "#8aa95a", "fern": "#799a53"}},
	"crisp": {
		# Twice the resolution and real detail, closer to a modern texture pack.
		"paint": "detail", "tile": 32, "noise": 0.06,
		"colors": {"stone": "#8b8b90", "dirt": "#7d5733", "grass": "#5f9e3e", "grass_side": "#7d5733",
			"sand": "#dfd5a0", "gravel": "#90908f", "water": "#2f6bbf", "log": "#6d5637",
			"log_top": "#8d7149", "leaves": "#3c7a33", "planks": "#a5834d", "snow": "#f0f4ff",
			"tall_grass": "#5a9a3a", "fern": "#4d8836"}},
}

## Which texture file each palette colour is written to. Block definitions in `base` name these paths,
## so writing them is all it takes for the world to change.
const FILES := {
	"stone": ["stone.png"], "dirt": ["dirt.png"], "grass": ["grass_top.png"],
	"grass_side": ["grass_side.png"], "sand": ["sand.png"], "gravel": ["gravel.png"],
	"water": ["water.png"], "log": ["birch_log_side.png", "spruce_log_side.png"],
	"log_top": ["birch_log_top.png", "spruce_log_top.png"],
	"leaves": ["birch_leaves.png", "spruce_leaves.png"], "planks": ["planks.png"],
	"snow": ["snow.png"], "tall_grass": ["tall_grass.png"], "fern": ["fern.png"],
}

var rng := RandomNumberGenerator.new()


func _init() -> void:
	var style_name := "current"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--style="):
			style_name = arg.substr(8)
	if not STYLES.has(style_name):
		printerr("no such style '%s'. Known: %s" % [style_name, ", ".join(STYLES.keys())])
		quit(2)
		return
	var style: Dictionary = STYLES[style_name]
	# Seeded per style so a style is the same every time it is rendered - a comparison between two
	# renders has to be a comparison of the styles, not of two rolls of the dice.
	rng.seed = hash(style_name)
	var written := 0
	for key: String in FILES:
		var color := Color(String(style.colors[key]))
		for file: String in FILES[key]:
			_save(_surface(style, color, key), OUT + file)
			written += 1
	print("[look_lab] style '%s': wrote %d textures into %s" % [style_name, written, OUT])
	quit()


## One block face, painted the way this style paints.
func _surface(style: Dictionary, base: Color, key: String) -> Image:
	var size := int(style.tile)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var amount := float(style.noise)
	match String(style.paint):
		"flat":
			image.fill(base)
		"noise":
			for y in size:
				for x in size:
					image.set_pixel(x, y, _vary(base, amount))
		"brush":
			# Bands rather than per-pixel speckle, so it reads as something painted with a wide brush.
			for y in size:
				var band := _vary(base, amount)
				for x in size:
					image.set_pixel(x, y, _vary(band, amount * 0.35))
		"detail":
			# Fine speckle with a darker lower-right, which is what reads as "detailed" at a glance.
			for y in size:
				for x in size:
					var shade := 1.0 - (float(x + y) / float(size * 2)) * 0.18
					var c := _vary(base, amount)
					image.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade, 1.0))
	# Plants and leaves are drawn with holes in them, or they are opaque cubes of green.
	if key in ["leaves", "tall_grass", "fern"]:
		_punch_holes(image, 0.34 if key == "leaves" else 0.62)
	return image


## Makes a cutout texture: leaves you can see through, grass that is blades rather than a slab.
func _punch_holes(image: Image, share: float) -> void:
	for y in image.get_height():
		for x in image.get_width():
			if rng.randf() < share:
				image.set_pixel(x, y, Color(0, 0, 0, 0))


func _vary(c: Color, amount: float) -> Color:
	if amount <= 0.0:
		return c
	var v := rng.randf_range(-amount, amount)
	return Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v, 0, 1), c.a)


func _save(image: Image, path: String) -> void:
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("FAILED %s" % path)
