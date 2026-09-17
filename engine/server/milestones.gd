extends RefCounted
## Milestones: the things a player has done, remembered for as long as the world lasts.
##
## A tutorial asks you to do something now and forgets it once you have. A milestone is the opposite: it
## watches quietly for the whole life of a world and pays out once, so what a player is wearing says
## where they have been. That is the point of the feature - the reward is usually a cosmetic, and a
## cosmetic is a thing other people can see.
##
##     api.register_milestone("colossus", {"title": "Colossus", "description": "Bring down the Ancient Colossus.",
##         "goal": {"kill": "vanilla:colossus"}, "reward": {"cosmetic": "vanilla:colossus_crown"}})
##
## Goals are written exactly as tutorial goals are (see engine/server/tutorials.gd): {type, target, count},
## where the type is one of the event goals - break, place, craft, pickup, kill, eat, tame, ... - or the
## generic `event` for anything a mod emits. The only difference is that the count is a lifetime total, so
## "mine five hundred stone" and "kill the boss once" are the same kind of thing.
##
## Sharing that vocabulary is deliberate: a mod author who has written one tutorial can write a milestone
## without learning anything new, and there is one table of event names to keep right rather than two.
## The poll goals tutorials also accept (have, depth, night, ...) are not offered here: a milestone is a
## thing you did, not a state you are briefly in.
##
## Fields: {title, description, goal, icon (an item, for the list), order, secret (hidden until reached),
##   announce (tell everyone, not just the player), reward: {items: [[item, count]], cosmetic: name}}
##
## State lives in `player.data.milestones`, which is already saved with the player, so adding milestones
## to a running world costs nothing and taking them away loses nothing: an unknown id is simply ignored
## on the way in, and progress towards a milestone that came back is still there.
##
## Events: milestone_reached {player, milestone, title}

const Tutorials = preload("res://engine/server/tutorials.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

var milestones := {}  # id -> def
var _server
var _listening := {}  # event name -> true


func _init(game_server) -> void:
	_server = game_server


## Registers one. `qualify` turns a bare name into a mod-qualified one, as it does for tutorials.
func register(id: String, def: Dictionary, qualify: Callable) -> bool:
	var goal := _clean_goal(def.get("goal"), qualify)
	if goal.is_empty():
		return false
	var reward: Dictionary = def.get("reward", {}) if def.get("reward") is Dictionary else {}
	milestones[id] = {
		"id": id,
		"title": str(def.get("title", id)).left(80),
		"description": str(def.get("description", "")).left(240),
		"icon": qualify.call(str(def.get("icon", ""))) if not str(def.get("icon", "")).is_empty() else "",
		"order": int(def.get("order", 0)),
		"secret": bool(def.get("secret", false)),
		"announce": bool(def.get("announce", false)),
		"goal": goal,
		"reward": {
			"items": _clean_items(reward.get("items"), qualify),
			"cosmetic": qualify.call(str(reward.get("cosmetic", ""))) if not str(reward.get("cosmetic", "")).is_empty() else "",
		},
	}
	_listen(goal.event)
	return true


## A goal in the tutorial vocabulary, reduced to the event it listens for and what counts as a match.
## Only the event goals: a milestone that cannot be reached by doing something is not a milestone.
func _clean_goal(goal, qualify: Callable) -> Dictionary:
	if goal is String:
		goal = {"type": goal}
	if not (goal is Dictionary):
		return {}
	var type := str(goal.get("type", ""))
	var g := {"type": type, "count": maxi(1, int(goal.get("count", 1)))}
	if type == "event":
		if str(goal.get("event", "")).is_empty():
			return {}
		g.event = str(goal.event)
		g.who = str(goal.get("who", "player"))
		g.field = str(goal.get("field", ""))
	elif Tutorials.EVENT_GOALS.has(type):
		var spec: Array = Tutorials.EVENT_GOALS[type]
		g.event = spec[0]
		g.who = spec[1]
		g.field = spec[2]
	else:
		return {}
	if goal.has("target"):
		var targets: Array = goal.target if goal.target is Array else [goal.target]
		var named: bool = str(g.field) in Tutorials.NAMED_FIELDS
		g.target = targets.map(func(t): return qualify.call(str(t)) if named else str(t))
	else:
		g.field = ""  # no target means anything of that kind counts
	return g


func _clean_items(items, qualify: Callable) -> Array:
	var out := []
	for r in (items if items is Array else []):
		if r is Array and r.size() >= 1:
			out.append([qualify.call(str(r[0])), int(r[1]) if r.size() > 1 else 1])
	return out


func _listen(event: String) -> void:
	if _listening.has(event):
		return
	_listening[event] = true
	# Lowest priority, as tutorials do: a break a mod cancelled never happened.
	_server.add_handler(event, _on_event.bind(event), -1000000)


## Drops a mod's milestones before it registers them again on reload. What players have already reached
## stays in their data, so a reload does not hand the rewards out twice.
func remove_owner(owner: String) -> void:
	for id in milestones.keys():
		if id.begins_with(owner + ":"):
			milestones.erase(id)


static func state_of(p) -> Dictionary:
	if not (p.data.get("milestones") is Dictionary):
		p.data.milestones = {"counts": {}, "done": {}}
	var s: Dictionary = p.data.milestones
	if not (s.get("counts") is Dictionary):
		s.counts = {}
	if not (s.get("done") is Dictionary):
		s.done = {}
	return s


func _on_event(ev: Dictionary, event: String) -> void:
	if ev.get("cancelled", false):
		return
	for m in milestones.values():
		if m.goal.event != event:
			continue
		# `kill` reports whoever landed the blow, which is often a mob killing another mob.
		var p = ev.get(m.goal.who)
		if not (p is ServerPlayer):
			continue
		var s := state_of(p)
		if s.done.has(m.id) or not _matches(m.goal, ev, p):
			continue
		var count := int(s.counts.get(m.id, 0)) + _amount(m.goal, ev)
		s.counts[m.id] = count
		if count >= m.goal.count:
			_award(p, m)


func _matches(goal: Dictionary, ev: Dictionary, p) -> bool:
	if ev.get(goal.who) != p:
		return false
	if goal.field.is_empty():
		return true
	return Tutorials._name_matches(goal.target, _name_of(goal.field, ev.get(goal.field)))


func _amount(goal: Dictionary, ev: Dictionary) -> int:
	return maxi(1, int(ev.get("count", 1))) if goal.type in ["craft", "pickup"] else 1


func _name_of(field: String, value) -> String:
	if value is Object:
		var def = value.get("def")
		return str(def.name) if def is Dictionary else ""
	if value is int:
		if field == "block":
			return _server.registry.defs[value].name if _server.registry.is_valid(value) else ""
		if field == "item":
			return _server.items.name_of(value)
	return str(value)


## Reached. Pays out once and says so; the announcement is the reward as much as the hat is.
func _award(p, m: Dictionary) -> void:
	var s := state_of(p)
	s.done[m.id] = true
	s.counts.erase(m.id)  # the count has done its job; the flag is what matters now
	for r in m.reward.items:
		var id: int = _server.items.id_of(r[0])
		if id > 0:
			p.give(id, r[1])  # a full pack drops the rest at their feet (ServerPlayer.give)
	if not m.reward.cosmetic.is_empty():
		p.grant_cosmetic(m.reward.cosmetic)
	p.show_title(str(m.title), str(m.description), 4.0)
	p.send_message("✦ %s - %s" % [m.title, m.description])
	_server.play_effect("engine:sparkle", p.position + Vector3(0, 1.2, 0), {"scale": 1.2})
	_server.play_sound_at("engine:discover", p.position)
	if m.announce:
		_server.broadcast_chat("✦ %s reached %s" % [p.name, m.title])
	_server.emit("milestone_reached", {"player": p, "milestone": m.id, "title": m.title})


## Whether this player has reached one, for mods that want to gate something behind it.
func reached(p, id: String) -> bool:
	return state_of(p).done.has(id)


## The list a player sees: what they have done, what is left, and how far along they are. Secret ones
## stay out of the list until they are reached, so the surprise survives being able to read the list.
func view(p) -> Array:
	var s := state_of(p)
	var out := []
	for m in milestones.values():
		var done: bool = s.done.has(m.id)
		if m.secret and not done:
			continue
		out.append({"id": m.id, "title": m.title, "description": m.description, "icon": m.icon,
			"order": m.order, "done": done, "progress": int(s.counts.get(m.id, 0)), "goal": m.goal.count})
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.title < b.title)
	return out
