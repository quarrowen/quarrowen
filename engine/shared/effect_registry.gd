extends RefCounted
## Visual effects as data: particle emitters, a light flash, camera shake and a sound, played at a
## position or following a mob or player. The server only sends "play effect N here"; clients build
## and render everything, so mods need no client code. "engine:*" effects are built in.
##
## Effect def:
##   emitters: [{
##     amount: particles (1-256), burst: true (all at once) | false (continuous while the effect plays)
##     lifetime: seconds, speed: [min, max] blocks/s, direction: [x,y,z], spread: degrees (0-180)
##     gravity: blocks/s^2 (negative rises), drag: velocity damping
##     size: [start, end] blocks, colors: ["#rrggbb" or "#rrggbbaa", ...] over the particle's life
##     shape: "point" | "sphere" | "box", radius (sphere), extents [x,y,z] (box)
##     texture: "soft" | "spark" | "star" | "square" or an asset from the mod, blend: "add" | "mix"
##   }]
##   light: {color, energy, range, seconds}      a brief light flash
##   shake: {strength, seconds, radius}          camera shake for players within radius
##   sound: sound name
##   duration: seconds continuous emitters run (0 = one burst; -1 = until stopped, for held effects)
##   range: blocks within which players receive it
## Play options: color (tints), scale (size, speed and area), direction ([x,y,z], turns emitters),
## follow (a mob or player; engine sends its id), duration (overrides the def).

const MAX_EFFECTS := 2048
const MAX_EMITTERS := 8
const TEXTURES := ["soft", "spark", "star", "square"]

const BUILTIN := {
	"engine:hit": {"emitters": [{"amount": 10, "lifetime": 0.35, "speed": [2.5, 5.0], "spread": 180, "gravity": 8,
		"drag": 2.0, "size": [0.08, 0.02], "colors": ["#fff6d0", "#ffb040", "#ff604000"], "texture": "spark"}]},
	"engine:crit": {"emitters": [{"amount": 18, "lifetime": 0.6, "speed": [3.0, 6.0], "spread": 180, "gravity": 4,
		"drag": 3.0, "size": [0.14, 0.03], "colors": ["#ffffff", "#ffe060", "#ffa02000"], "texture": "star"}],
		"sound": "engine:crit"},
	"engine:smoke": {"emitters": [{"amount": 12, "lifetime": 1.4, "speed": [0.3, 1.0], "direction": [0, 1, 0], "spread": 50,
		"gravity": -0.6, "drag": 1.0, "size": [0.25, 0.7], "colors": ["#8a8a8acc", "#5a5a5a00"], "shape": "sphere",
		"radius": 0.3, "blend": "mix"}]},
	"engine:sparkle": {"emitters": [{"amount": 14, "lifetime": 0.9, "speed": [0.2, 0.8], "spread": 180, "gravity": -0.4,
		"size": [0.1, 0.0], "colors": ["#ffffff", "#fff0a0", "#ffe06000"], "texture": "star", "shape": "sphere", "radius": 0.5}]},
	"engine:magic": {"emitters": [{"amount": 24, "lifetime": 0.8, "speed": [1.0, 3.0], "spread": 180, "gravity": -1.0,
		"drag": 2.5, "size": [0.12, 0.02], "colors": ["#f0d0ff", "#a060ff", "#5020c000"]}],
		"light": {"color": "#a060ff", "energy": 2.0, "range": 5.0, "seconds": 0.35}},
	"engine:heal": {"emitters": [{"amount": 12, "lifetime": 1.0, "speed": [0.5, 1.2], "direction": [0, 1, 0], "spread": 30,
		"gravity": -0.5, "size": [0.12, 0.05], "colors": ["#c0ffc0", "#40d04000"], "shape": "box", "extents": [0.35, 0.9, 0.35], "texture": "square"}]},
	"engine:dust": {"emitters": [{"amount": 30, "lifetime": 0.9, "speed": [2.0, 5.0], "direction": [0, 0.2, 0], "spread": 90,
		"gravity": 2.0, "drag": 3.0, "size": [0.3, 0.8], "colors": ["#a08a6acc", "#7a6a5000"], "blend": "mix"}],
		"shake": {"strength": 0.5, "seconds": 0.45, "radius": 12.0}},
	"engine:explosion": {"emitters": [
		{"amount": 40, "lifetime": 0.5, "speed": [4.0, 9.0], "spread": 180, "gravity": 3, "drag": 4.0, "size": [0.35, 0.05],
			"colors": ["#ffffff", "#ffc040", "#ff402000"]},
		{"amount": 20, "lifetime": 1.6, "speed": [1.0, 3.0], "spread": 180, "gravity": -0.8, "drag": 2.0, "size": [0.6, 1.4],
			"colors": ["#6a6a6acc", "#3a3a3a00"], "blend": "mix", "shape": "sphere", "radius": 0.8}],
		"light": {"color": "#ffa040", "energy": 6.0, "range": 12.0, "seconds": 0.5},
		"shake": {"strength": 1.0, "seconds": 0.6, "radius": 24.0}},
}

var defs: Array[Dictionary] = []
var ids := {}  # name -> id


func _init() -> void:
	for effect_name in BUILTIN:
		var d: Dictionary = BUILTIN[effect_name].duplicate(true)
		d.name = effect_name
		register(d)


## Registers an effect (see the header). Returns its id, or -1.
func register(def: Dictionary) -> int:
	var effect_name := str(def.get("name", ""))
	if effect_name.is_empty() or ids.has(effect_name) or defs.size() >= MAX_EFFECTS:
		push_error("Invalid or duplicate effect '%s'" % effect_name)
		return -1
	var emitters := []
	for e in (def.get("emitters") if def.get("emitters") is Array else []).slice(0, MAX_EMITTERS):
		if e is Dictionary:
			emitters.append(_emitter(e))
	var d := {
		"name": effect_name,
		"emitters": emitters,
		"light": {},
		"shake": {},
		"sound": str(def.get("sound", "")).left(128),
		"duration": clampf(_num(def.get("duration"), 0.0), -1.0, 600.0),
		"range": clampf(_num(def.get("range"), 48.0), 4.0, 256.0),
	}
	if def.get("light") is Dictionary:
		var l: Dictionary = def.light
		d.light = {"color": clean_color(l.get("color"), "#ffffff"), "energy": clampf(_num(l.get("energy"), 2.0), 0.0, 16.0),
			"range": clampf(_num(l.get("range"), 6.0), 0.5, 32.0), "seconds": clampf(_num(l.get("seconds"), 0.3), 0.05, 10.0)}
	if def.get("shake") is Dictionary:
		var s: Dictionary = def.shake
		d.shake = {"strength": clampf(_num(s.get("strength"), 0.5), 0.0, 3.0), "seconds": clampf(_num(s.get("seconds"), 0.4), 0.05, 5.0),
			"radius": clampf(_num(s.get("radius"), 16.0), 1.0, 128.0)}
	var id := defs.size()
	d.id = id
	defs.append(d)
	ids[effect_name] = id
	return id


func id_of(effect_name: String) -> int:
	return ids.get(effect_name, -1)


func is_valid(id: int) -> bool:
	return id >= 0 and id < defs.size()


## Cleans play options for the network: {color, scale, direction, duration}.
static func clean_options(options) -> Dictionary:
	var out := {}
	if not (options is Dictionary):
		return out
	if options.has("color") and is_color(options.color):
		out.color = clean_color(options.color, "#ffffff")
	if options.get("scale") is float or options.get("scale") is int:
		out.scale = clampf(float(options.scale), 0.05, 20.0)
	if options.get("direction") is Vector3:
		out.direction = options.direction
	elif options.get("direction") is Array and options.direction.size() == 3:
		out.direction = Vector3(_num(options.direction[0], 0.0), _num(options.direction[1], 1.0), _num(options.direction[2], 0.0))
	if options.get("duration") is float or options.get("duration") is int:
		out.duration = clampf(float(options.duration), -1.0, 600.0)
	for key in ["follow_entity", "follow_player"]:
		if options.get(key) is int:
			out[key] = options[key]
	return out


func to_network() -> Array:
	return defs.duplicate(true)


func load_network(data) -> bool:
	if not (data is Array) or data.size() > MAX_EFFECTS:
		return false
	defs.clear()
	ids.clear()
	for entry in data:
		if not (entry is Dictionary) or not (entry.get("name") is String) or register(entry) < 0:
			return false
	return true


static func is_color(value) -> bool:
	return value is String and (value as String).length() in [4, 7, 9] and (value as String).begins_with("#") and Color.html_is_valid(value)


static func clean_color(value, fallback: String) -> String:
	return "#" + Color.html(value).to_html(true) if is_color(value) else fallback


static func _num(value, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback


static func _emitter(e: Dictionary) -> Dictionary:
	var speed = e.get("speed", [1.0, 2.0])
	var size = e.get("size", [0.1, 0.05])
	var colors := []
	for c in (e.get("colors") if e.get("colors") is Array else ["#ffffff"]).slice(0, 8):
		if is_color(c):
			colors.append(clean_color(c, "#ffffff"))
	if colors.is_empty():
		colors = ["#ffffff"]
	var direction = e.get("direction", [0, 1, 0])
	var extents = e.get("extents", [0.5, 0.5, 0.5])
	var texture := str(e.get("texture", "soft")).left(256)
	return {
		"amount": clampi(int(_num(e.get("amount"), 12)), 1, 256),
		"burst": bool(e.get("burst", true)),
		"lifetime": clampf(_num(e.get("lifetime"), 0.6), 0.05, 10.0),
		"speed": [clampf(_num(speed[0], 1.0), 0.0, 64.0), clampf(_num(speed[1], 2.0), 0.0, 64.0)] if speed is Array and speed.size() == 2 else [1.0, 2.0],
		"direction": [_num(direction[0], 0.0), _num(direction[1], 1.0), _num(direction[2], 0.0)] if direction is Array and direction.size() == 3 else [0.0, 1.0, 0.0],
		"spread": clampf(_num(e.get("spread"), 45.0), 0.0, 180.0),
		"gravity": clampf(_num(e.get("gravity"), 0.0), -64.0, 64.0),
		"drag": clampf(_num(e.get("drag"), 0.0), 0.0, 32.0),
		"size": [clampf(_num(size[0], 0.1), 0.0, 8.0), clampf(_num(size[1], 0.05), 0.0, 8.0)] if size is Array and size.size() == 2 else [0.1, 0.05],
		"colors": colors,
		"shape": str(e.get("shape", "point")) if str(e.get("shape", "point")) in ["point", "sphere", "box"] else "point",
		"radius": clampf(_num(e.get("radius"), 0.5), 0.0, 32.0),
		"extents": [clampf(_num(extents[0], 0.5), 0.0, 32.0), clampf(_num(extents[1], 0.5), 0.0, 32.0), clampf(_num(extents[2], 0.5), 0.0, 32.0)] if extents is Array and extents.size() == 3 else [0.5, 0.5, 0.5],
		"texture": texture,
		"blend": "mix" if e.get("blend") == "mix" else "add",
	}
