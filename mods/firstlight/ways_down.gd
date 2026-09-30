extends RefCounted
## The two ways into the descent: one you find, and one you build.
##
## **They are the same object**, which is the whole design. A portal standing on deepstone is a way down -
## that is the rule, and it is checked where somebody stands rather than written into a block when it is
## placed. So the one you stumble on in a chamber underground and the one you build yourself are
## indistinguishable, and learning either teaches the other.
##
## **No new block, and that is deliberate.** The obvious move was a `firstlight:deepway` block, which
## would have meant a new noun in a game mod (`base` owns nouns) and a texture in a mod that has none.
## `base:portal` already exists and already means "a doorway that goes somewhere": the engine's
## server-to-server travel reads a destination out of its block data, and a portal with no destination is
## inert to it. So the noun was already there and only the rule was missing, which is what the engine and
## mod split is supposed to feel like when it is working.
##
## **Deepstone is the gate, and it needs no gating code.** Deepstone is only found well below the surface,
## so building a deepway requires having already been down there - which is the progression, enforced by
## where the material is rather than by a check. (28 September 2026)

## How often somebody standing in a doorway is noticed. Half a second: fast enough that stepping in feels
## like it did something, slow enough that this is a rounding error next to the rest of a tick.
const LOOK := 0.5
const UI := "firstlight:deepway"

var api
var descent
## player_id -> true while their panel is up, so walking about in a doorway does not reopen it every tick.
var _asking := {}

## **Resolved once, with `require_`.** `api.block` answers -1 for something missing, and -1 compared
## against a block read out of the world is a comparison that can never be true - so a missing dependency
## would present as doorways simply not working rather than as anything saying so. (CLAUDE.md)
var _door := -1
var _rock := -1


func setup(mod_api, the_descent) -> void:
	api = mod_api
	descent = the_descent
	_door = api.require_block("base:portal")
	_rock = api.require_block("base:deepstone")
	_a_found_one()
	api.every(LOOK, _look_around)
	api.on("ui_action", _chose)
	# Their panel goes with them, or somebody who logs out mid-question can never be asked again.
	api.on("player_leave", func(ev): _asking.erase(ev.player.player_id))
	# Said once, when somebody builds one, because a portal placed on deepstone *becoming* something is
	# not a thing anybody would guess from looking at the blocks.
	api.on("block_placed", func(ev):
		if int(ev.block) == _door and _stands_on_deepstone(ev.player, ev.position):
			ev.player.send_message("The doorway settles into the deepstone. Step in when you are ready.")
	)


## The chamber world generation hides underground: a room of deepstone with a doorway standing in it.
##
## **Block data cannot be placed by a structure** - a template is a palette and a list of cells - which is
## the other reason the rule is "a portal on deepstone" rather than a marker written into the block. A
## found doorway carries nothing and does not need to.
func _a_found_one() -> void:
	var span := 7
	var high := 6
	var rock := 0
	var door := 1
	var lamp := 2
	var air := 3
	var blocks := []
	for x in span:
		for z in span:
			blocks.append([x, 0, z, rock])
			blocks.append([x, high - 1, z, rock])
	for y in range(1, high - 1):
		for x in span:
			for z in span:
				var wall: bool = x == 0 or z == 0 or x == span - 1 or z == span - 1
				blocks.append([x, y, z, rock if wall else air])
	# Four lights near the ceiling, so the room reads as somewhere that was made rather than a cave.
	for spot in [[1, high - 2, 1], [span - 2, high - 2, 1], [1, high - 2, span - 2], [span - 2, high - 2, span - 2]]:
		blocks.append([spot[0], spot[1], spot[2], lamp])
	blocks.append([span / 2, 1, span / 2, door])
	api.register_structure_template("deepway_chamber", {"size": [span, high, span],
		"palette": ["base:deepstone", "base:portal", "base:sunstone_block", "engine:air"],
		"blocks": blocks})
	# **`spacing` is in chunks** - the lesson the altar paid an afternoon for. 12 chunks is about 190
	# blocks: these are meant to be stumbled on while mining rather than sought, so they are a good deal
	# more common than the altar's ruin, and `chance` under one keeps them off a grid anybody could learn.
	api.register_structure("deepway_site", {"templates": [{"template": "firstlight:deepway_chamber"}],
		"place": "underground", "y": 28, "spacing": 12, "separation": 5, "chance": 0.7})


## Anybody standing in a doorway that is not already in a descent.
##
## **A poll rather than a region**, and the reason is worth keeping: a region has to be *placed*, and
## world generation puts these chambers wherever it likes without telling anybody - `find_structure` can
## compute where the nearest one is, but covering every one in the world would mean a region per chamber
## and there are 256 in the whole server. Reading one block under each online player costs nothing by
## comparison. The descent's own floors *do* use regions, because a mod that built the floor knows
## exactly where it put the stairs.
func _look_around() -> void:
	for player in api.players():
		if player == null or player.dead:
			continue
		if descent.depth_of(player) > 0 or _asking.has(player.player_id):
			continue
		if not api.instance_of(player).is_empty():
			continue
		var at := Vector3i(player.position.floor())
		if not _is_deepway(at, api.realm_of(player)):
			at = Vector3i((player.position + Vector3(0, 1, 0)).floor())
			if not _is_deepway(at, api.realm_of(player)):
				continue
		_ask(player)


## A doorway on deepstone, with nowhere else already written into it: a portal an admin pointed at
## another server is that portal's business and not this one's.
func _is_deepway(at: Vector3i, realm: String) -> bool:
	if api.get_loaded_block(at, realm) != _door:
		return false
	if api.get_loaded_block(at - Vector3i(0, 1, 0), realm) != _rock:
		return false
	var settings = api.get_block_data(at, realm).get("portal", {})
	if settings is Dictionary:
		return String(settings.get("server", "")).is_empty() and String(settings.get("realm", "")).is_empty()
	return true


func _stands_on_deepstone(player, at: Vector3i) -> bool:
	return api.get_loaded_block(at - Vector3i(0, 1, 0), api.realm_of(player)) == _rock


## The choice, which is the only thing this needs an interface for. Two buttons rather than two blocks or
## two commands: whether you are risking what you carry is the one decision worth making at the door, and
## it should be made at the door.
func _ask(player) -> void:
	_asking[player.player_id] = true
	player.show_ui(UI, {"anchor": "center", "children": [
		{"type": "label", "text": "The Deepway", "size": 20},
		{"type": "label", "text": "Down is harder the further you go. There is a way back up on every floor.", "size": 13},
		{"type": "button", "text": "Go down - keep your things if you fall", "action": "gentle"},
		{"type": "button", "text": "Go down - risk everything you carry", "action": "harsh"},
		{"type": "button", "text": "Not yet", "action": "no"},
	]})


func _chose(ev) -> void:
	if String(ev.ui_id) != UI:
		return
	var player = ev.player
	_asking.erase(player.player_id)
	player.hide_ui(UI)
	var action := String(ev.action)
	if action == "gentle" or action == "harsh":
		# The answer is printed here too. This path ignored it, so somebody who could not afford harsh
		# pressed the button and nothing happened at all - the worst of the three ways to refuse.
		if not descent.enter(player, action == "harsh") and not descent.problem.is_empty():
			player.send_message(descent.problem)
