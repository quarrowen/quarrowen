extends RefCounted
## The player's settings, shared by the main menu and the game: one schema, saved to user://settings.cfg
## (QW_SETTINGS overrides the path, for tests). `changed(key)` fires on every change so whatever uses
## a setting can apply it at once. Keys are "section/name", the same as in the file.
##
## The schema drives the settings screen too: each entry has a label, a type (bool, float, choice) and
## the range or choices, so a new setting needs one line here plus the code that uses it.

signal changed(key: String)

const DEFAULT_PATH := "user://settings.cfg"
const BUS_WORLD := "World"
const BUS_INTERFACE := "Interface"

const GRAPHICS_PRESETS := ["fast", "balanced", "fancy", "custom"]
## Per-preset values of the graphics toggles (see engine/client/graphics_settings.gd).
const PRESET_VALUES := {
	"fast": {"ambient_occlusion": true, "sway": false, "fancy_water": false, "bloom": false, "grading": false, "fxaa": false, "render_scale": 0.7},
	"balanced": {"ambient_occlusion": true, "sway": true, "fancy_water": true, "bloom": true, "grading": true, "fxaa": false, "render_scale": 0.85},
	"fancy": {"ambient_occlusion": true, "sway": true, "fancy_water": true, "bloom": true, "grading": true, "fxaa": true, "render_scale": 1.0},
}

## key -> {tab, label, type, default, min/max/step or choices [[value, label]], help}
const SCHEMA := {
	"graphics/preset": {"tab": "Graphics", "label": "Quality", "type": "choice", "default": "balanced",
		"choices": [["fast", "Fast"], ["balanced", "Balanced"], ["fancy", "Fancy"], ["custom", "Custom"]],
		"help": "Fast suits older or integrated graphics. F4 cycles the presets in game."},
	"graphics/render_scale": {"tab": "Graphics", "label": "3D resolution", "type": "float", "default": 0.85, "min": 0.5, "max": 1.0, "step": 0.05, "percent": true,
		"help": "Below 100% the world is drawn smaller and upscaled (FSR): faster, a little softer."},
	"graphics/ambient_occlusion": {"tab": "Graphics", "label": "Soft shadows in corners", "type": "bool", "default": true},
	"graphics/sway": {"tab": "Graphics", "label": "Swaying plants", "type": "bool", "default": true},
	"graphics/fancy_water": {"tab": "Graphics", "label": "Fancy water", "type": "bool", "default": true},
	"graphics/bloom": {"tab": "Graphics", "label": "Glow around lights", "type": "bool", "default": true},
	"graphics/grading": {"tab": "Graphics", "label": "Colour grading", "type": "bool", "default": true},
	"graphics/fxaa": {"tab": "Graphics", "label": "Smooth edges (FXAA)", "type": "bool", "default": false},
	"graphics/fov": {"tab": "Graphics", "label": "Field of view", "type": "float", "default": 75.0, "min": 55.0, "max": 110.0, "step": 1.0, "suffix": "°"},
	"graphics/window_mode": {"tab": "Graphics", "label": "Window", "type": "choice", "default": "windowed",
		"choices": [["windowed", "Windowed"], ["maximized", "Maximized"], ["fullscreen", "Fullscreen"]]},
	"graphics/vsync": {"tab": "Graphics", "label": "V-Sync", "type": "bool", "default": true, "help": "Matches the screen's refresh rate: no tearing, steady frames."},
	"graphics/max_fps": {"tab": "Graphics", "label": "Frame rate limit", "type": "choice", "default": 0,
		"choices": [[0, "Unlimited"], [30, "30"], [60, "60"], [120, "120"], [144, "144"]]},
	"graphics/menu_backdrop": {"tab": "Graphics", "label": "Live world behind the menu", "type": "bool", "default": true},
	"audio/volume": {"tab": "Audio", "label": "Master volume", "type": "float", "default": 0.8, "min": 0.0, "max": 1.0, "step": 0.05, "percent": true},
	"audio/world": {"tab": "Audio", "label": "World sounds", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05, "percent": true,
		"help": "Blocks, creatures, machines and footsteps around you."},
	"audio/interface": {"tab": "Audio", "label": "Interface sounds", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05, "percent": true,
		"help": "Sounds that are not in the world: clicks, crafting, notifications."},
	"controls/mouse_sensitivity": {"tab": "Controls", "label": "Mouse sensitivity", "type": "float", "default": 1.0, "min": 0.2, "max": 3.0, "step": 0.05, "percent": true},
	"controls/invert_y": {"tab": "Controls", "label": "Invert mouse up and down", "type": "bool", "default": false},
	"controls/sprint_toggle": {"tab": "Controls", "label": "Sprint key toggles", "type": "bool", "default": false,
		"help": "Press once to start sprinting and again to stop, instead of holding it."},
	"interface/scale": {"tab": "Accessibility", "label": "Interface size", "type": "float", "default": 1.0, "min": 0.75, "max": 2.0, "step": 0.05, "percent": true,
		"help": "Menus, HUD and screens. 100% already adjusts for high-density (Retina) screens."},
	"accessibility/camera_shake": {"tab": "Accessibility", "label": "Camera shake", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05, "percent": true},
	"accessibility/flashes": {"tab": "Accessibility", "label": "Flashes", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05, "percent": true,
		"help": "Light bursts from effects and the red flash when you are hurt."},
	"crafting/relaxed_timing": {"tab": "Accessibility", "label": "Relaxed minigame timing", "type": "bool", "default": false,
		"help": "Slower markers, bigger zones and longer windows. Every result is still at least Standard."},
	"interface/compass": {"tab": "Accessibility", "label": "Compass at the top of the screen", "type": "bool", "default": true,
		"help": "Which way you are facing, with a mark for players nearby and for your home and grave."},
	"accessibility/menu_motion": {"tab": "Accessibility", "label": "Moving camera in the menu", "type": "bool", "default": true},
	"network/hub_url": {"tab": "Network", "label": "Server list hub", "type": "text", "default": "", "placeholder": "https://hub.example.org",
		"help": "The hub lists public servers in Multiplayer → Browse, resolves short invite codes and shows news. Empty: no hub."},
	"network/share_server": {"tab": "Network", "label": "Friends can see which server I'm on", "type": "bool", "default": true,
		"help": "Lets friends and your party see your server and join you. Off: they only see that you are online."},
	# Not shown in the settings screen (the menu's own field edits it), but saved like everything else.
	"player/name": {"tab": "hidden", "label": "Player name", "type": "text", "default": ""},
	"network/auto_update": {"tab": "Network", "label": "Tell me about new versions", "type": "bool", "default": true,
		"help": "Checks the project's release page when the menu opens. Updates are only ever downloaded from there."},
	"network/lan_discovery": {"tab": "Network", "label": "Find servers on my network", "type": "bool", "default": true,
		"help": "Multiplayer → LAN asks computers on your network (and this one) for games."},
}

const TABS := ["Graphics", "Audio", "Controls", "Accessibility", "Network"]

## Rebindable actions: [action, label, default events]. Events are "key:<physical keycode name>" or
## "mouse:<button index>".
const ACTIONS := [
	["move_forward", "Move forward", ["key:W", "key:Up"]],
	["move_back", "Move back", ["key:S", "key:Down"]],
	["move_left", "Move left", ["key:A", "key:Left"]],
	["move_right", "Move right", ["key:D", "key:Right"]],
	["jump", "Jump / swim up", ["key:Space"]],
	# Ctrl matches what children coming from other block games expect (Shift is crouch, below). Whether
	# macOS turns Ctrl+click into a right click while the mouse is captured is worth watching in a
	# playtest - if it does, sprint needs its own key rather than a second binding that fights crouch.
	["sprint", "Sprint", ["key:Ctrl"]],
	["sneak", "Crouch (and sink while flying)", ["key:Shift"]],
	["break", "Break / attack", ["mouse:1"]],
	["place", "Place / use", ["mouse:2"]],
	["inventory", "Inventory", ["key:E", "key:Tab"]],
	["crafting", "Crafting", ["key:C"]],
	["drop", "Drop item", ["key:Q"]],
	["guide", "Guide book", ["key:G"]],
	["map", "Map", ["key:M"]],
	["chat", "Chat", ["key:T", "key:Enter"]],
	["camera", "Camera view", ["key:F5"]],
	["graphics", "Cycle graphics quality", ["key:F4"]],
	["toggle_debug", "Debug info", ["key:F3"]],
	["dev", "Dev tools", ["key:F8"]],
	["pause", "Pause / close", ["key:Escape"]],
]

static var _shared = null

var path := DEFAULT_PATH
var _cfg := ConfigFile.new()


## The settings every part of the client shares (loaded on first use).
static func shared():
	if _shared == null:
		_shared = load("res://engine/client/settings/client_settings.gd").new()
		_shared.load_file()
	return _shared


func load_file() -> void:
	var override := OS.get_environment("QW_SETTINGS")
	path = override if not override.is_empty() else DEFAULT_PATH
	_cfg = ConfigFile.new()
	_cfg.load(path)


func save() -> void:
	_cfg.save(path)


func get_value(key: String):
	var entry: Dictionary = SCHEMA.get(key, {})
	var parts := key.split("/")
	if key == "graphics/preset":
		var forced := OS.get_environment("QW_GRAPHICS")
		if forced in GRAPHICS_PRESETS:
			return forced
	# Graphics toggles follow the preset unless it is "custom".
	if parts[0] == "graphics" and PRESET_VALUES.fast.has(parts[1]):
		var preset: String = get_value("graphics/preset")
		if preset != "custom":
			return PRESET_VALUES[preset][parts[1]]
	return _clean(entry, _cfg.get_value(parts[0], parts[1], entry.get("default")))


## Sets and saves a value (clamped to the schema) and emits `changed`. Changing a graphics toggle while a
## preset is selected switches to "custom", starting from that preset's values.
func set_value(key: String, value, save_now := true) -> void:
	var entry: Dictionary = SCHEMA.get(key, {})
	if entry.is_empty():
		return
	var parts := key.split("/")
	if parts[0] == "graphics" and PRESET_VALUES.fast.has(parts[1]):
		var preset: String = get_value("graphics/preset")
		if preset != "custom":
			for k: String in PRESET_VALUES[preset]:
				_cfg.set_value("graphics", k, PRESET_VALUES[preset][k])
			_cfg.set_value("graphics", "preset", "custom")
			changed.emit("graphics/preset")
	_cfg.set_value(parts[0], parts[1], _clean(entry, value))
	if save_now:
		save()
	changed.emit(key)


func reset_tab(tab: String) -> void:
	for key: String in SCHEMA:
		if SCHEMA[key].tab == tab:
			var parts := key.split("/")
			if _cfg.has_section_key(parts[0], parts[1]):
				_cfg.erase_section_key(parts[0], parts[1])
			changed.emit(key)
	if tab == "Controls":
		if _cfg.has_section("bindings"):
			_cfg.erase_section("bindings")
		apply_bindings()
		changed.emit("bindings")
	save()


static func _clean(entry: Dictionary, value):
	if entry.is_empty():
		return value
	match entry.type:
		"bool":
			return bool(value) if (value is bool or value is int or value is float) else entry.default
		"float":
			return clampf(float(value), entry.min, entry.max) if (value is float or value is int) else entry.default
		"text":
			return str(value).strip_edges().left(int(entry.get("max_length", 300))) if value != null else entry.default
		"choice":
			for c in entry.choices:
				if c[0] is int and (value is int or value is float):
					if int(value) == c[0]:
						return c[0]
				elif typeof(c[0]) == typeof(value) and c[0] == value:
					return c[0]
			return entry.default
	return value


# --- Key bindings -------------------------------------------------------------------------------

static func default_events(action: String) -> Array:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return []


## The events for an action (saved bindings, else defaults) as descriptors.
func events(action: String) -> Array:
	var saved = _cfg.get_value("bindings", action) if _cfg.has_section_key("bindings", action) else null
	if saved is Array:
		return saved.filter(func(e): return e is String and not event_from(e) == null)
	return default_events(action)


func set_events(action: String, descriptors: Array) -> void:
	_cfg.set_value("bindings", action, descriptors.slice(0, 2))
	save()
	apply_bindings()
	changed.emit("bindings")


## Which action (if any, other than `except`) already uses an event.
func action_using(descriptor: String, except := "") -> String:
	for a in ACTIONS:
		if a[0] != except and events(a[0]).has(descriptor):
			return a[0]
	return ""


## Registers every action in the InputMap with the player's bindings.
func apply_bindings() -> void:
	for a in ACTIONS:
		var action: String = a[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for descriptor in events(action):
			var ev = event_from(descriptor)
			if ev != null:
				InputMap.action_add_event(action, ev)


static func event_from(descriptor: String) -> InputEvent:
	if descriptor.begins_with("key:"):
		var code := OS.find_keycode_from_string(descriptor.substr(4))
		if code == KEY_NONE:
			return null
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		return ev
	if descriptor.begins_with("mouse:") and descriptor.substr(6).is_valid_int():
		var mb := InputEventMouseButton.new()
		mb.button_index = int(descriptor.substr(6)) as MouseButton
		return mb
	return null


## The descriptor for a pressed key or mouse button, or "" for anything else.
static func descriptor_of(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return "key:" + OS.get_keycode_string(code) if code != KEY_NONE else ""
	if event is InputEventMouseButton and event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return "mouse:%d" % event.button_index
	return ""


static func describe(descriptor: String) -> String:
	if descriptor.begins_with("key:"):
		return descriptor.substr(4)
	match descriptor:
		"mouse:1": return "Left mouse"
		"mouse:2": return "Right mouse"
		"mouse:3": return "Middle mouse"
	return "Mouse %s" % descriptor.substr(6)


# --- Applying display and audio settings --------------------------------------------------------

## Window mode, v-sync, frame rate limit and interface scale.
func apply_display(window: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("graphics/vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("graphics/max_fps"))
	var mode: String = get_value("graphics/window_mode")
	var wanted: Window.Mode = {"windowed": Window.MODE_WINDOWED, "maximized": Window.MODE_MAXIMIZED, "fullscreen": Window.MODE_FULLSCREEN}[mode]
	if window.mode != wanted and not (mode == "windowed" and window.mode == Window.MODE_MINIMIZED):
		window.mode = wanted
	apply_ui_scale(window)


## Interface size: the screen's own density (Retina = 2) times the player's choice.
func apply_ui_scale(window: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_factor = maxf(1.0, DisplayServer.screen_get_scale(window.current_screen)) * float(get_value("interface/scale"))


## Master volume on the Master bus; World and Interface buses (created when missing) below it.
func apply_audio() -> void:
	for bus_name in [BUS_WORLD, BUS_INTERFACE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for pair in [["Master", "audio/volume"], [BUS_WORLD, "audio/world"], [BUS_INTERFACE, "audio/interface"]]:
		var index := AudioServer.get_bus_index(pair[0])
		var v := float(get_value(pair[1]))
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(index, v <= 0.001)
