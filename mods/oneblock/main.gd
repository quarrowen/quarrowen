extends "res://engine/server/mod.gd"
## One Block: everybody stands over the void on a single block. Break it and it comes back as something
## else - soil, then stone and ores, then stranger things - and now and then a creature or a crate
## instead. Build outwards from whatever you collect.
##
## **This existed before.** 190 lines, deleted on 21 September 2026 with the other games for being
## content rather than for being wrong (`git show 00edd6c^:mods/oneblock/main.gd`). A capability audit
## before rewriting it found that nothing here needs engine work: void generation, `void_below` physics,
## the `block_broken` hook, weighted tables, per-player `data`, entity spawning and containers all
## existed then and exist now. So this is a port, and the old file was the specification. (2026-09-27)
##
## What changed, because `base` was re-scoped to nouns in between: tools come from `simple_gear` rather
## than `base`, and the creatures are `base`'s own seventeen rather than a deleted game's.

const PhaseTables = preload("res://mods/oneblock/phases.gd")

## Islands are spaced along X in one persistent world. **Not the instances capability**: an instance is
## ephemeral by design and never written to disk, so a child's island and every break they had made
## would evaporate the moment they logged out. Chunks only load near players, so fifty islands cost
## nothing. (2026-09-27)
const BLOCK_SPACING := 512
const BLOCK_Y := 64
## Below this a player is put back on their block. **Kinder than dying**, and it catches them well above
## the engine's own void damage at y = -32, so the fall is a surprise rather than a punishment.
const VOID_Y := -12.0
## Blocks to break before the phase turns.
const PHASE_LENGTH := 60
## **The loop does not go back to the beginning.** After the first pass the phases cycle from here on,
## so a child who has reached the depths never drops back to dirt - which reads as punishment rather
## than as a new lap. (the user, 2026-09-25: endless, phases keep cycling)
const LOOP_FROM := 2
## One break in this many is something extraordinary rather than ordinary. The whole game is "what is it
## going to be?", and a rare thrill sharpens every ordinary break around it.
const JACKPOT_ONE_IN := 200

var api
## Which island belongs to whom, by origin x: index -> player id. Rebuilt from storage on setup, so a
## visitor breaking somebody's block mends *their* island rather than leaving a hole.
var _owner_of := {}


func setup(mod_api) -> void:
	api = mod_api
	api.set_server_info({"name": "One Block", "motd": "Break the block. See what comes back."})
	api.set_physics({"void_below": true})
	# Nothing would catch a dropped item out here, so what you mine goes straight into the backpack.
	api.set_gameplay({"item_drops": "inventory", "keep_inventory": true, "mob_spawning": false})
	api.set_world_generator(VoidGenerator.new())
	api.set_spawn_handler(func(player): return _spawn_for(player))
	api.on("player_join", _on_join)
	api.on("block_broken", _on_block_broken)
	# **Look, don't touch.** A sibling may walk round your island and see what you built; they may not
	# change it. Nobody can spoil what somebody else made, which matters more between siblings than the
	# ability to help. (the user, 2026-09-27)
	api.on("block_break", _guard_edit)
	api.on("block_place", _guard_edit)
	api.every(0.25, _check_void)
	api.register_command("oneblock", "Go back to your block; 'visit <name>' to see somebody else's", _cmd_oneblock)
	_register_milestones()
	_register_music()


class VoidGenerator:
	func generate(_chunk) -> void:
		pass  # empty sky; each player's block is placed for them


# --- Milestones -----------------------------------------------------------------------------------

## **Markers to aim at, in a game that otherwise has none.** Breaking a block forever is a counter, not
## a goal; a title card saying what you have just done is what turns one into the other. The engine has
## had milestones since September and nothing was using them.
func _register_milestones() -> void:
	for entry in [
			["first_break", "A start", "Break the block for the very first time.", 1],
			["hundred", "A hundred", "Break the block a hundred times.", 100],
			["five_hundred", "Five hundred", "Break the block five hundred times.", 500],
			["thousand", "A thousand", "Break the block a thousand times.", 1000]]:
		api.register_milestone(String(entry[0]), {
			"title": String(entry[1]), "description": String(entry[2]),
			"goal": {"type": "break", "count": int(entry[3])}, "announce": false})


# --- Music ----------------------------------------------------------------------------------------

## **Per player, not per world.** Every child is on their own island in their own phase, so world-level
## ambience cannot express this - one of them is in a meadow while another is in the depths, in the same
## world at the same moment. `play_music(player, ...)` is what the API has for exactly that.
func _register_music() -> void:
	var credit := "Quarrowen placeholder, generated by tools/generate_music.py (CC0)"
	for track in ["open", "deep", "bright", "night"]:
		api.register_music(track, "music/%s.ogg" % track, {"volume": 0.85, "attribution": credit})


## Plays the mood this phase wants, if it is not already playing. Tracked per player so a fade does not
## restart every time a block is broken - sixty times a phase would be unbearable.
func _music_for(player, phase: Dictionary) -> void:
	var data := _data(player)
	var wanted := String(phase.get("music", "open"))
	if String(data.get("music", "")) == wanted:
		return
	data.music = wanted
	api.play_music(player, wanted, {"fade": 6.0})


# --- The block ------------------------------------------------------------------------------------

func _data(player) -> Dictionary:
	if not player.data.has("oneblock"):
		player.data.oneblock = {}
	return player.data.oneblock


func _origin(index: int) -> Vector3i:
	return Vector3i(index * BLOCK_SPACING + 8, BLOCK_Y, 8)


## Whose island a position belongs to, or "" for none. **The old mod could not answer this**, which is
## why a visitor breaking somebody's block left a hole that never came back: the handler returned early
## unless the position was your own origin. (2026-09-27)
func _island_at(position: Vector3i) -> int:
	if position.y != BLOCK_Y or position.z != 8:
		return -1
	var index: int = (position.x - 8) / BLOCK_SPACING
	return index if index >= 0 and _origin(index) == position else -1


func _spawn_for(player) -> Vector3:
	var data := _data(player)
	if not data.has("index"):
		_assign(player)
	var o := _origin(int(data.index))
	return Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)


func _assign(player) -> void:
	var index := int(api.storage.get("next_block", 0))
	api.storage.next_block = index + 1
	var data := _data(player)
	data.index = index
	data.broken = 0
	data.phase = 0
	_owner_of[index] = player.player_id
	var owners: Dictionary = api.storage.get("owners", {})
	owners[str(index)] = player.player_id
	api.storage.owners = owners
	var o := _origin(index)
	api.set_block(o, api.block("base:grass"))
	api.set_block(o + Vector3i(0, 1, 0), 0)
	api.info("One Block #%d is %s's" % [index, player.name])


# --- Playing --------------------------------------------------------------------------------------

func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	if ev.first_time:
		# Tools rather than bare hands: the first minute should be playable, not a puzzle about how to
		# start. (the user, 2026-09-27)
		for tool_name in ["simple_gear:wooden_pickaxe", "simple_gear:wooden_axe"]:
			var id: int = api.item(tool_name)
			if id > 0:
				player.give(id)
		player.show_title("One Block", "Break it. Something else takes its place.", 5.0)
	var phases: Array = PhaseTables.PHASES
	_music_for(player, phases[mini(int(_data(player).get("phase", 0)), phases.size() - 1)])
	_show_progress(player)


## Refuses a change to somebody else's island. Their own is theirs entirely.
func _guard_edit(ev: Dictionary) -> void:
	var player = ev.get("player")
	if player == null:
		return
	var data := _data(player)
	if not data.has("index"):
		return
	var here := _island_of_position(Vector3i(ev.position))
	if here >= 0 and here != int(data.index):
		ev.cancelled = true
		player.send_message("This is somebody else's island - you can look, but not build.")


## Which island a position is *on*, by how far along X it is - not whether it is the origin block. An
## island is everything a child built outwards from theirs, so the whole column of X belongs to them.
func _island_of_position(position: Vector3i) -> int:
	var index := int(floor((float(position.x) - 8.0 + float(BLOCK_SPACING) * 0.5) / float(BLOCK_SPACING)))
	return index if index >= 0 and int(api.storage.get("next_block", 0)) > index else -1


func _on_block_broken(ev: Dictionary) -> void:
	var player = ev.player
	if player == null:
		return
	# The break counts for whoever owns the island, not for whoever swung - which is how a visitor is
	# harmless rather than helpful. They cannot get this far anyway; `_guard_edit` refuses first.
	var index := _island_at(Vector3i(ev.position))
	if index < 0:
		return
	var data := _data(player)
	if not data.has("index") or index != int(data.index):
		return
	data.broken = int(data.get("broken", 0)) + 1
	var phases: Array = PhaseTables.PHASES
	var reached := int(data.broken) / PHASE_LENGTH
	var phase_index: int = reached if reached < phases.size() else \
		LOOP_FROM + (reached - phases.size()) % maxi(1, phases.size() - LOOP_FROM)
	if phase_index != int(data.get("phase", 0)):
		data.phase = phase_index
		var phase: Dictionary = phases[phase_index]
		player.show_title(String(phase.name), String(phase.get("says", "The block has changed")), 4.0)
		# One sound per phase, so the turn is heard before it is read. Real ambience wants audio this
		# project does not have yet - see the AI-audio phase in PROGRESS. (2026-09-27)
		api.play_sound(String(phase.get("sound", "engine:level_up")), player.position)
	_music_for(player, phases[phase_index])
	_replace(player, _origin(int(data.index)), phases[phase_index])
	_show_progress(player)


## Puts something new where the block was: usually a block, now and then a creature, a crate, or - very
## rarely - something worth telling somebody about.
func _replace(player, position: Vector3i, phase: Dictionary) -> void:
	if randi() % JACKPOT_ONE_IN == 0 and _jackpot(player, position, phase):
		return
	api.set_block(position, _pick_block(phase))
	if randf() < float(phase.get("mob_chance", 0.0)):
		var mob: String = _pick(phase.get("mobs", []), func(n): return api.entity_type(n) >= 0)
		if not mob.is_empty():
			# Spawned into the air above rather than into the block itself: `spawn_entity` refuses solid
			# rock and returns null quietly. (PROGRESS, 2026-09-24)
			api.spawn_entity(mob, Vector3(position) + Vector3(0.5, 1.2, 0.5))
			return
	if randf() < float(phase.get("crate_chance", 0.0)):
		var given := []
		for entry in phase.get("crate", []):
			var item: int = api.item(String(entry[0]))
			if item > 0:
				player.give(item, int(entry[1]))
				given.append("%d %s" % [int(entry[1]), String(entry[0]).get_slice(":", 1).replace("_", " ")])
		if not given.is_empty():
			player.show_title("", "A crate! " + ", ".join(given), 2.5)


## The rare one. Returns whether it happened, so an ordinary block is not also placed on top of it.
func _jackpot(player, position: Vector3i, phase: Dictionary) -> bool:
	var prize: String = _pick(phase.get("jackpot", []), func(n): return api.block(n) > 0)
	if prize.is_empty():
		return false
	api.set_block(position, api.block(prize))
	player.show_title("!", "%s" % prize.get_slice(":", 1).replace("_", " ").capitalize(), 3.0)
	api.play_sound("engine:discover", player.position)
	return true


func _pick_block(phase: Dictionary) -> int:
	var name: String = _pick(phase.get("blocks", []), func(n): return api.block(n) > 0)
	return api.block(name) if not name.is_empty() else api.block("base:dirt")


## One weighted entry ([name, weight]) whose name this world actually has, or "". **The existence filter
## is what lets a table name something optional**: `simple_machines` is an optional dependency, so its
## blocks simply do not come up when it is not installed.
func _pick(entries: Array, exists: Callable) -> String:
	var usable := []
	var total := 0
	for entry in entries:
		if entry is Array and entry.size() == 2 and exists.call(String(entry[0])):
			usable.append(entry)
			total += int(entry[1])
	if total <= 0:
		return ""
	var roll := randi() % total
	for entry in usable:
		roll -= int(entry[1])
		if roll < 0:
			return String(entry[0])
	return String(usable[0][0])


# --- Commands and falling -------------------------------------------------------------------------

func _cmd_oneblock(player, args: PackedStringArray) -> void:
	if args.size() > 0 and args[0] == "visit":
		_visit(player, " ".join(Array(args).slice(1)))
		return
	if args.size() > 0 and args[0] == "reset":
		# **Behind a confirmation.** It throws away an afternoon, and on a tablet one stray tap should
		# not be able to. (the user, 2026-09-27)
		if args.size() < 2 or args[1] != "yes":
			player.send_message("This throws away your island and everything you are carrying. Type '/oneblock reset yes' if you mean it.")
			return
		player.clear_inventory()
		_assign(player)
		player.show_title("A fresh block", "Good luck!", 3.0)
	var data := _data(player)
	var o := _origin(int(data.get("index", 0)))
	if api.get_loaded_block(o) == 0:
		api.set_block(o, api.block("base:grass"))  # never leave somebody standing over nothing
	player.teleport(_spawn_for(player))
	_show_progress(player)


func _visit(player, who: String) -> void:
	if who.strip_edges().is_empty():
		player.send_message("Who would you like to visit? '/oneblock visit <name>'")
		return
	for other in api.get_players():
		if other.name.to_lower() == who.strip_edges().to_lower():
			var data := _data(other)
			if not data.has("index"):
				break
			var o := _origin(int(data.index))
			player.teleport(Vector3(o.x + 0.5, o.y + 2, o.z + 0.5))
			player.show_title("", "%s's island. You can look, but not build." % other.name, 3.0)
			return
	player.send_message("Nobody called '%s' is here." % who)


func _check_void() -> void:
	for player in api.get_players():
		if player.position.y < VOID_Y:
			player.teleport(_spawn_for(player))
			player.show_title("", "The void spat you back out", 2.0)


# --- What the player sees --------------------------------------------------------------------------

func _show_progress(player) -> void:
	var data := _data(player)
	var broken := int(data.get("broken", 0))
	var phases: Array = PhaseTables.PHASES
	var phase: Dictionary = phases[mini(int(data.get("phase", 0)), phases.size() - 1)]
	var next: int = PHASE_LENGTH - (broken % PHASE_LENGTH)
	var children := [
		{"type": "label", "text": "One Block", "size": 18, "color": "#ffd166"},
		{"type": "label", "text": "%s  -  %d broken" % [phase.name, broken]},
		{"type": "label", "text": "%d more to the next" % next, "size": 12},
	]
	# **What everybody else is up to.** Islands are 512 apart, so siblings are invisible to one another
	# otherwise, and a race nobody can see is not a race. (the user, 2026-09-27)
	# `api` is untyped by convention here, so `:=` on anything reached through it cannot infer.
	var others: Array = api.get_players().filter(func(p): return p != player and _data(p).has("index"))
	if not others.is_empty():
		children.append({"type": "label", "text": " ", "size": 6})
		for other in others:
			var their := _data(other)
			var their_phase: Dictionary = phases[mini(int(their.get("phase", 0)), phases.size() - 1)]
			children.append({"type": "label", "size": 12,
				"text": "%s  %s, %d" % [other.name, their_phase.name, int(their.get("broken", 0))]})
	player.show_ui("oneblock:progress", {"anchor": "top_right", "children": children})
