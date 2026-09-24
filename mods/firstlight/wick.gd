extends RefCounted
## Wick, the lamplighter: the voice that guides Firstlight, and the only creature this game registers.
##
## **Why a game owns a creature at all.** `base` owns nouns - things any game might want. Wick is not
## one: he is this story's narrator with a body, and no other game would take him. The rule the header
## of `main.gd` states is that a game registers no blocks and no items, and that still holds; a
## storyteller is neither. (2026-09-24)
##
## **He cannot be hurt.** `health: 0` is the engine's "cannot be damaged" (EntityRegistry), which
## matters more than it sounds: he follows a child through a survival world at night, and the first
## time a Dustling killed him a child would be genuinely upset and the story would simply stop.
##
## **He follows by being a companion, not by new code.** Taming already does the hard parts - he keeps
## up, he does not despawn, and he *teleports* to you rather than being left on the wrong side of a
## ravine. That last one is the whole reason this is not a pathfinding problem. `api.tame` was added
## for him: the behaviour existed and no mod could ask for it.
##
## The voice, which is the thing to protect: warm, slightly apologetic, never grand. He cannot fight,
## which is why he needs a child who can, and why the child is the one who gets to act. There is no
## villain in this story and nothing threatens anyone the player loves.

## One Wick each, told apart by the colour of his coat. Two identical men in hats is a thing a child
## notices immediately and asks about; two men in *different coats* is just two people. Chosen from a
## fixed list rather than at random so the same child keeps the same Wick across sessions - the colour
## is derived from their player id, which does not change. (the user, 2026-09-24)
const COATS := [
	["#8a6a45", "Brown"], ["#4f6b52", "Green"], ["#6b4f6b", "Plum"], ["#4f5f7a", "Blue"],
	["#7a4f4f", "Rust"], ["#6b6340", "Olive"],
]

var api
var ids := {}


func setup(mod_api) -> void:
	api = mod_api
	_register(api)
	_conversation(api)
	# One each. Two children on a server should not be arguing about whose turn it is to have the
	# guide, and a Wick apiece costs nothing - he is a talking signpost, not a resource.
	api.on("player_join", func(ev):
		if ev.player != null:
			_ensure_wick(ev.player))
	# Right-click him to talk. The engine draws the conversation, so it looks like every other
	# character in every other mod - a child who has learned one has learned all of them.
	_watch(api)
	api.on("entity_interact", func(ev):
		if ev.entity != null and ev.entity.type == ids.get("wick", -1):
			api.talk_to(ev.player, "wick")
			ev.cancelled = true)


func _register(api) -> void:
	ids.wick = api.register_entity("wick", {"kind": "mob", "display_name": "Wick",
		"model": "models/wick.glb",
		"width": 0.6, "height": 1.5,
		# **Zero is "cannot be damaged", not "dies instantly".** See EntityRegistry: a definition with
		# no health is a thing the damage system refuses to touch.
		"health": 0,
		"speed": 4.2,  # a little faster than a player walks, so keeping up is his problem and not yours
		"category": "misc", "persistent": true,
		"nameplate": {"show_health": false},
		"interactive": true,
		# No `items`: he is never tamed by feeding, only handed over by `api.tame` when you first meet.
		# The distances are what stop him being lost - he teleports rather than pathing round a ravine.
		"taming": {"items": [], "chance": 0.0, "follow_distance": 2.5, "teleport_distance": 24.0},
		"ai": {"preset": "passive", "wander_radius": 4}})


## The first conversation. Everything else he says comes later, as the acts land.
##
## Written to be read aloud by a child: short lines, no clause stacking, and no word an eight-year-old
## would have to stop at. `options` are what the *player* says, so they are written as a child would
## say them rather than as a menu.
func _conversation(api) -> void:
	api.register_character("wick", {"display_name": "Wick", "color": "#e8a33d", "lines": {
		"start": {"text": "Oh - you're up. And in one piece. That's more than most.", "options": [
			{"text": "Who are you?", "goes_to": "who"},
			{"text": "What is this place?", "goes_to": "where"},
			{"text": "I should go", "does": "bye"}]},
		"who": {"text": "Wick. I keep the lights. Keeping them badly, lately, but keeping them.", "options": [
			{"text": "What lights?", "goes_to": "lights"},
			{"text": "Can you help me?", "goes_to": "help"}]},
		"lights": {"text": "The ones that kept the dark thin. They've been going out, one at a time, and I'm not quick enough to be everywhere.", "options": [
			{"text": "Why are they going out?", "goes_to": "why"},
			{"text": "Can you help me?", "goes_to": "help"}]},
		"why": {"text": "Something under the world woke up. While it's awake the nights are full. I've known for a long time and I've never once gone down to look.", "options": [
			{"text": "I could look", "goes_to": "help"},
			{"text": "That sounds bad", "goes_to": "help"}]},
		"where": {"text": "Somewhere that gets dark. That's all anywhere is, really, until somebody lights it.", "options": [
			{"text": "Who are you?", "goes_to": "who"},
			{"text": "Can you help me?", "goes_to": "help"}]},
		"help": {"text": "I can walk with you and I can tell you what I know. I can't fight - I'd be no use at all. But you look like you might be.", "options": [
			{"text": "All right", "does": "begin"},
			{"text": "Later", "does": "bye"}]},
		# Once the story is running he opens straight onto whatever comes next.
		"onward": {"text": "Still here. Still lit. What's next, then?", "options": [
			{"text": "Remind me what I'm doing", "does": "remind"},
			{"text": "Nothing", "does": "bye"}]},
	}})


## Makes sure this player has a Wick, and that he belongs to them.
func _ensure_wick(player) -> void:
	for e in api.get_entities(player.position, 64.0, "firstlight:wick"):
		if str(e.data.get("owner", "")) == str(player.player_id):
			return  # theirs already, and following
	var at: Vector3 = player.position + Vector3(1.5, 0.0, 1.5)
	var wick = api.spawn_entity("firstlight:wick", at)
	if wick == null:
		return
	api.tame(wick, player)
	wick.data["firstlight_owner"] = str(player.player_id)
	# Prefix-matched by the client, so "coat" catches the coat and "arm" both sleeves - the head, hat
	# and lantern keep their own colours, which is what makes him still read as Wick.
	var coat: Array = COATS[abs(hash(str(player.player_id))) % COATS.size()]
	# No nameplate set here: the engine writes "<player>'s" onto any tamed creature's plate, so his
	# says whose he is without this file knowing anything about plates.
	wick.set_look({"tint": {"coat": str(coat[0]), "arm": str(coat[0])}})


## What he says when you are simply near him.
##
## **The hybrid the user asked for** (2026-09-24): the task list carries the objective so nobody has to
## remember a conversation, and he still remarks as you go, "to make him more alive".
##
## The hard part of an ambient companion is that he becomes wallpaper. Three rules keep him worth
## listening to, and all three are about *restraint*:
##
## - **He never repeats a line in a session.** Each one is said once and retired.
## - **He waits.** `QUIET_SECONDS` between remarks however much you run past him, so he cannot chatter.
## - **He speaks to a moment, not a timer.** Nightfall, going underground, being hurt - things that
##   just happened to *you*, which is why it reads as noticing rather than as a script.
const QUIET_SECONDS := 90.0
const NEAR := 6.0

## Said when the moment is right, once each. Ordinary observations on purpose: a companion who only
## speaks at dramatic moments is a companion who is silent for an hour.
const REMARKS := {
	"first_dark": "It's going. The light, I mean. Best be somewhere with walls.",
	"first_dawn": "There. Morning. I never do get tired of that bit.",
	"underground": "Careful down here. Things don't need eyes if they've got patience.",
	"hurt": "You're bleeding. I'd offer to help but I'd only faint.",
	"deep": "The stone's changed. We're properly under it now.",
	"idle": "Don't mind me. I'm just glad of the company.",
}

var _said := {}       # player id -> {remark: true}
var _last_spoke := {} # player id -> seconds, against _elapsed
## Seconds since the game started, counted by our own timer: the mod API exposes the time *of day*,
## which runs on the world clock and is useless for "has he spoken recently".
var _elapsed := 0.0


## Called on a slow tick. Looks for a moment worth a line, and mostly finds none.
func _remark(player, wick) -> void:
	if wick == null or player == null:
		return
	if wick.body.position.distance_to(player.position) > NEAR:
		return
	var id := str(player.player_id)
	var now: float = _elapsed
	if now - float(_last_spoke.get(id, -QUIET_SECONDS)) < QUIET_SECONDS:
		return
	var said: Dictionary = _said.get(id, {})
	var pick := ""
	var daylight: float = api.get_daylight()
	if player.position.y < 30.0:
		pick = "deep"
	elif player.position.y < 55.0:
		pick = "underground"
	elif player.health < player.max_health * 0.5:
		pick = "hurt"
	elif daylight < 0.3:
		pick = "first_dark"
	elif daylight > 0.9:
		pick = "first_dawn"
	else:
		pick = "idle"
	if said.has(pick):
		return  # said once, and once is the point
	said[pick] = true
	_said[id] = said
	_last_spoke[id] = now
	player.send_message("[Wick] %s" % REMARKS[pick])


## Drives the remarks. One slow timer for everybody rather than a handler per player: he is allowed to
## notice things, not to think hard.
func _watch(api) -> void:
	api.every(5.0, func():
		_elapsed += 5.0
		for player in api.players():
			for e in api.get_entities(player.position, NEAR + 2.0, "firstlight:wick"):
				if str(e.data.get("owner", "")) == str(player.player_id):
					_remark(player, e)
					break)
