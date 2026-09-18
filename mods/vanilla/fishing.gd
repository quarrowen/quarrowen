extends RefCounted
## Fishing: cast at water, wait, and strike when something tugs.
##
## The waiting is the point. Everything else here rewards doing, and a child who has spent the night
## running from zombies benefits from one thing that asks them to stand still by a lake for a minute. So
## the wait is real (four to fourteen seconds), the bite is loud, and missing it costs nothing but the
## wait - a penalty would turn the quiet part into another thing to be anxious about.
##
## What the engine had to grow for this: `api.raycast(..., {"liquids": true})`. A player's crosshair
## deliberately looks straight through water - you aim at the riverbed, not the river - so no mod could
## ask where the surface was. Everything else is loot tables and timers that already existed.

const ROD := "vanilla:fishing_rod"

var api
var _casts := {}  # player_id -> {player, at, bite_generation, biting, deadline}
var _generation := 0


func setup(mod_api) -> void:
	api = mod_api
	api.register_item("fishing_rod", {"display_name": "Fishing Rod", "icon": "textures/fishing_rod.png",
		"usable": true, "max_stack": 1, "durability": 64})
	# Sticks and string, in the bent-rod shape people expect, so it is guessable in the Experiment tab.
	api.register_recipe({}, ROD, 1, {"category": "tools", "unlock": "experiment",
		"pattern": ["  S", " ST", "S T"], "key": {"S": "base:stick", "T": "vanilla:string"}})

	api.register_item("raw_fish", {"display_name": "Raw Fish", "icon": "textures/raw_fish.png",
		"food": {"hunger": 2, "saturation": 1.2, "color": "#8fa8b8"}})
	api.register_item("cooked_fish", {"display_name": "Cooked Fish", "icon": "textures/cooked_fish.png",
		"food": {"hunger": 6, "saturation": 7.0, "color": "#c88f56", "heal": 1.0}})
	api.register_recipe({"vanilla:raw_fish": 1}, "vanilla:cooked_fish", 1,
		{"station": "furnace", "time": 6.0, "category": "food"})

	# What comes out of the water. Fish mostly; the rest is what keeps a child casting, because a table
	# that only ever gives fish is one you stop reading after the third one.
	api.register_loot_table("fishing", {"rolls": 1, "entries": [
		{"item": "vanilla:raw_fish", "weight": 60},
		{"item": "vanilla:string", "weight": 10},
		{"item": "base:stick", "weight": 8},
		{"item": "base:coal", "weight": 5},
		{"item": "base:iron_ingot", "weight": 3},
		{"item": "vanilla:bone", "weight": 6, "when": {"time": "night"}},
	]})

	api.register_sound("fishing_cast", "sounds/fishing_cast.ogg", {"pitch_variance": 0.12})
	api.register_sound("fishing_bite", "sounds/fishing_bite.ogg", {"pitch_variance": 0.04})

	api.on("item_use", _on_use)
	api.on("player_leave", func(ev): _casts.erase(ev.player.player_id))


# --- Casting ------------------------------------------------------------------------------------

## Right-click: the first one casts, the second either strikes or pulls the line back in.
func _on_use(ev: Dictionary) -> void:
	if ev.item != api.item(ROD):
		return
	var player = ev.player
	if _casts.has(player.player_id):
		_reel_in(player)
		return
	var hit: Dictionary = api.raycast(player.get_eye_position(), api.look_direction(player), 7.0, {"liquids": true})
	if not hit.hit or not api.is_liquid(hit.block):
		player.show_title("", "Stand by some water and cast into it", 2.0)
		return
	_generation += 1
	var generation := _generation
	_casts[player.player_id] = {"player": player, "at": Vector3(hit.position), "biting": false,
		"generation": generation}
	player.play_sound("vanilla:fishing_cast")
	player.show_title("", "The float settles. Wait for it to dip.", 2.5)
	api.after(randf_range(4.0, 14.0), _bite.bind(player.player_id, generation))


## Something takes the bait, if the player is still standing where they cast from.
func _bite(player_id: String, generation: int) -> void:
	var cast = _casts.get(player_id)
	if cast == null or cast.generation != generation:
		return  # reeled in, or cast again, while this was waiting
	var player = cast.player
	# Wandering off ends it, rather than telling a player in a cave that a fish waited for them.
	if player.position.distance_to(cast.at) > 12.0:
		_casts.erase(player_id)
		player.show_title("", "You walked away from your line", 2.0)
		return
	cast.biting = true
	# The sound matters more than the words here: a child watching the water is not reading the screen.
	player.play_sound("vanilla:fishing_bite")
	player.show_title("", "Something is tugging! Use the rod!", 1.6)
	# 1.6 seconds is long enough for an eight-year-old to read that, find the mouse and click. Two
	# thirds of a second, which is what a grown-up game would give, is not.
	api.after(1.6, _got_away.bind(player_id, generation))


func _got_away(player_id: String, generation: int) -> void:
	var cast = _casts.get(player_id)
	if cast == null or cast.generation != generation or not cast.biting:
		return
	_casts.erase(player_id)
	cast.player.show_title("", "It got away", 2.0)


## Pulling the line back in, whether or not there was anything on the end of it.
func _reel_in(player) -> void:
	var cast: Dictionary = _casts[player.player_id]
	_casts.erase(player.player_id)
	if not cast.biting:
		# Struck early, or gave up. No penalty beyond casting again - see the note at the top.
		player.show_title("", "Nothing yet. The line comes back empty.", 2.0)
		return
	var caught: Array = api.roll_loot("vanilla:fishing", {"player": player, "position": cast.at})
	if caught.is_empty():
		player.show_title("", "It got away", 2.0)
		return
	for entry in caught:
		player.give(entry[0], entry[1])
	player.show_title("", "You caught %s!" % api.item_display_name(caught[0][0]), 2.5)
	player.damage_item(player.selected_slot, 1, "use")
