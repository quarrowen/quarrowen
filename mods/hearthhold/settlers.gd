extends RefCounted
## The people you bring home. Phase one has one of them, Bramble, because the whole design rests on a
## single question: is walking someone home a journey or a chore? Everything else waits on that answer.
##
## A settler follows the way a tamed animal does - the engine already paths, waits and teleports to catch
## up when badly stuck (engine/server/taming.gd), which is exactly what a person walking home needs and
## is already proven by wolves. What a settler adds on top is having something to say, and somewhere to
## live once you get her there.
##
## Settlers cannot die. They are hurt and they hide, and they come back in the morning: a child who walked
## three hundred blocks for Bramble must never lose her to a stray arrow.

## How close a settler stands when she has nowhere to be.
const FOLLOW_DISTANCE := 3.0
const TELEPORT_DISTANCE := 24.0

var api
var dwellings
var ids := {}


func setup(mod_api, dwellings_ref) -> void:
	api = mod_api
	dwellings = dwellings_ref
	ids.bramble = api.register_entity("bramble", {
		"kind": "mob", "display_name": "Bramble", "model": "models/settler.glb",
		"width": 0.6, "height": 1.85, "health": 20, "speed": 3.4, "persistent": true, "category": "misc",
		# No taming items: you cannot tame a person. The config is here because it is what gives her the
		# engine's follow-your-owner behaviour once she has agreed to come.
		"taming": {"items": [], "chance": 0.0, "follow_distance": FOLLOW_DISTANCE, "teleport_distance": TELEPORT_DISTANCE},
		"ai": {"preset": "passive", "wander_radius": 4, "flee_from": [], "sight_range": 12},
	})
	api.on("entity_interact", _on_talk)
	api.on("entity_damage", _protect)
	api.every(2.0, _settle_in)


## Nothing kills a settler. Damage is absorbed and she keeps going; the story never takes a person away.
func _protect(ev: Dictionary) -> void:
	if ev.entity.type == ids.bramble:
		ev.cancelled = true


## Three lines, never more. What she says depends only on where she is in her own small story, so a child
## always gets an answer that makes sense from wherever they pick her up.
func _on_talk(ev: Dictionary) -> void:
	if ev.entity.type != ids.bramble:
		return
	ev.cancelled = true
	var e = ev.entity
	var player = ev.player
	if not str(e.data.get("owner", "")).is_empty() and e.data.get("home") == null:
		_say(player, e, "Still with you. Somewhere to sleep and I will stop following you about.",
			["A roof, a bed, a door and a light. I am building it."])
		return
	if e.data.get("home") != null:
		_say(player, e, "This will do nicely. Come in when the pot is on.", ["Anything you need?"])
		return
	_say(player, e, "Oh - somebody. I saw your fire from the ridge and I have been walking since.",
		["I can cook, if there is anything to cook on. Is there a roof where you came from?"], true)


func _say(player, entity, line: String, extra: Array, offer := false) -> void:
	var children: Array = [{"type": "label", "text": "Bramble", "size": 20, "color": "#ffd166"},
		{"type": "label", "text": line}]
	for more in extra:
		children.append({"type": "label", "text": str(more)})
	children.append({"type": "spacer", "size": 6})
	if offer:
		children.append({"type": "button", "text": "Come with me", "action": "recruit:%d" % entity.id})
	children.append({"type": "button", "text": "Close", "action": "close"})
	player.show_ui("hearthhold:talk", {"anchor": "center", "modal": true, "children": children})


## Agreeing to come is the whole of chapter two. She follows from here, and the guide says what to do next.
func recruit(player, entity_id: int) -> void:
	var e = api.get_entity(entity_id)
	if e == null or e.type != ids.bramble or not str(e.data.get("owner", "")).is_empty():
		return
	e.data.owner = player.player_id
	e.data.owner_name = player.name
	api.play_sound("engine:discover", e.body.position)
	player.show_title("Bramble is coming with you", "She will need somewhere to live", 4.0)
	api.broadcast("%s found Bramble, who is coming back to Hearthhold." % player.name)


## Where she is, for a player who has lost her - which will happen, because a valley is large.
func whereabouts(player) -> String:
	for e in api.get_entities(player.position, 512.0, "hearthhold:bramble"):
		if e.data.get("home") != null:
			return "Bramble is at home, and says the pot is on."
		if not str(e.data.get("owner", "")).is_empty():
			return "Bramble is following you, %d blocks back." % int(e.body.position.distance_to(player.position))
		return "Bramble is %d blocks away, towards %s." % [int(e.body.position.distance_to(player.position)),
			_compass(e.body.position - player.position)]
	return "Nobody has seen Bramble. Light the hearth and let the smoke carry."


static func _compass(delta: Vector3) -> String:
	if absf(delta.x) > absf(delta.z):
		return "east" if delta.x > 0.0 else "west"
	return "south" if delta.z > 0.0 else "north"


## Once a hearthstone nearby says somebody could live there, she moves in: she stops following, stays by
## the house, and the place has its first chimney.
func _settle_in() -> void:
	# Looked at from the houses rather than from the people: there are few hearthstones and they are easy
	# to find, whereas the settlers are wherever they have wandered to.
	for at: Vector3i in api.find_block_data(api.block("hearthhold:hearthstone")):
		if not dwellings.is_home(at):
			continue
		for e in api.get_entities(Vector3(at), 24.0, "hearthhold:bramble"):
			if str(e.data.get("owner", "")).is_empty() or e.data.get("home") != null:
				continue
			e.data.home = [at.x, at.y, at.z]
			e.data.erase("owner")  # she lives here now, rather than trailing after anyone
			e.set_home(Vector3(at) + Vector3(0.5, 1.0, 0.5))
			api.play_effect("engine:sparkle", Vector3(at) + Vector3(0.5, 1.2, 0.5), {"scale": 1.0})
			api.broadcast("Bramble has moved in. Hearthhold has one chimney.")
			return
