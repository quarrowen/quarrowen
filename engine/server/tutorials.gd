extends RefCounted
## Tutorials (guided goals in the player's own world) and contextual tips.
##
## Tutorial: {title, description, order, auto_start (starts on its own for a new player), modes (which game
##   modes it suits: ["survival"] by default, ["creative"], or both), reward: [[item, count]],
##   steps: [{title, text, icon (item), goal, hint, page (guide page), reward: [[item, count]]}]}
## Tip: {text, icon, page, trigger (a goal)}. Each tip shows once per player, at most one every TIP_GAP seconds.
##
## Goals are completed by real actions. Event goals count matching events; `target` is a name or a
## list of names ("*" wildcards, e.g. "base:*log") and `count` how many are needed (default 1):
##   break {target: block}   place {target: block}   craft {target: item} (counts items made)
##   pickup {target: item}   eat {target: item}      use_item {target: item}   use_block {target: block}
##   equip {target: item}    kill {target: entity}   breed {target: entity}    tame {target: entity}
##   learn {target: recipe}  read {target: page}     unlock_page {target: page}
##   sleep  respawn  death {target: cause}  damage {target: cause}  upgrade {target: station}
##   assemble {target: assembly}
##   event {event, who ("player"), field, target}   any engine or mod event
## Goals checked twice a second:
##   have {target: item, count}   depth {below: y}   reach {position: [x, y, z], radius}
##   biome {target}   hunger_below {value}   health_below {value}   night   flag {target: guide flag}
##   manual   (only api.advance_tutorial completes it)
## Hints point players at something: {block: name(s)} | {entity: name(s)} | {position: [x, y, z]};
## break/use_block, kill/breed/tame and reach goals get one automatically (hint: false turns it off).
## Events: tutorial_started {player, tutorial}, tutorial_step {player, tutorial, step, index},
##   tutorial_completed {player, tutorial}, tip_shown {player, tip}

const EVENT_GOALS := {
	"break": ["block_broken", "player", "block"],
	"place": ["block_placed", "player", "block"],
	"craft": ["item_crafted", "player", "item"],
	"pickup": ["item_pickup", "player", "item"],
	"eat": ["player_eat", "player", "item"],
	"use_item": ["item_use", "player", "item"],
	"use_block": ["block_interact", "player", "block"],
	"equip": ["equipment_changed", "player", "item"],
	"kill": ["entity_death", "attacker", "entity"],
	"breed": ["entity_bred", "player", "baby"],
	"tame": ["entity_tamed", "player", "entity"],
	"learn": ["recipe_learned", "player", "recipe"],
	"read": ["guide_page_read", "player", "page"],
	"unlock_page": ["guide_page_unlocked", "player", "page"],
	"sleep": ["player_sleep", "player", ""],
	"respawn": ["player_respawn", "player", ""],
	"death": ["player_death", "player", "cause"],
	"damage": ["player_damage", "player", "cause"],
	"upgrade": ["station_upgraded", "player", "station"],
	"assemble": ["tool_assembled", "player", "assembly"],
}
const POLL_GOALS := ["have", "depth", "reach", "biome", "hunger_below", "health_below", "night", "flag", "manual"]
## Of those, the ones an event can now tell us about the moment they change, so they are answered at
## once instead of up to POLL_INTERVAL late.
##
## **The poll stays as well, and that is deliberate.** Taking `have` out of it broke every have goal:
## `Inventory.set_slot` writes without calling `sync_inventory`, so nothing announced the change. Any
## code doing that leaves the client out of step too and is arguably already wrong - but a safety net
## that costs one inventory walk twice a second is cheaper than a tutorial that silently never
## advances. The event buys responsiveness here, not saved work. (2026-09-21)
const EVENT_DRIVEN := {"have": "inventory_changed", "health_below": "player_damaged", "night": "time_changed"}
## Goal fields holding names that belong to a mod (qualified with the registering mod's id).
const NAMED_FIELDS := ["block", "item", "entity", "baby", "recipe", "page", "assembly", "biome", "flag"]
const POLL_INTERVAL := 0.5
const TIP_GAP := 12.0  # seconds between two tips
const TIP_SECONDS := 9.0

var tutorials := {}  # id -> def
var tips := {}  # id -> def
var _server
var _listening := {}  # event name -> true
var _poll := 0.0


func _init(game_server) -> void:
	_server = game_server
	# The goals that used to wait for the next poll now hear about the change as it happens. Checked
	# for one player where the event names one, rather than sweeping everybody.
	for goal_type: String in EVENT_DRIVEN:
		_server.add_handler(String(EVENT_DRIVEN[goal_type]), _on_state_change, -1000000, "engine")


func _on_state_change(ev: Dictionary) -> void:
	var p = ev.get("player")
	if p != null:
		if not p.dead:
			_check_polled(p)
		return
	# time_changed names nobody, so nightfall is the one that still sweeps - once, when it happens.
	for other in _server.players.values():
		if not other.dead:
			_check_polled(other)


# --- Registration -----------------------------------------------------------------------------------

## `qualify(name) -> String` turns local names into full ones.
func register_tutorial(id: String, def: Dictionary, qualify: Callable) -> bool:
	var steps := []
	for s in (def.get("steps") if def.get("steps") is Array else []):
		if not (s is Dictionary):
			continue
		var goal := _clean_goal(s.get("goal", {"type": "manual"}), qualify)
		if goal.is_empty():
			push_error("[tutorials] %s: step '%s' has an unknown goal" % [id, s.get("title", "")])
			return false
		steps.append({"title": str(s.get("title", "")).left(80), "text": str(s.get("text", "")).left(600),
			"icon": qualify.call(str(s.get("icon", ""))), "goal": goal, "hint": _hint_for(s.get("hint", null), goal, qualify),
			"page": qualify.call(str(s.get("page", ""))), "reward": _clean_rewards(s.get("reward"), qualify)})
	if steps.is_empty():
		return false
	for step in steps:
		if step.goal.has("event"):
			_listen(step.goal.event)
	tutorials[id] = {"id": id, "title": str(def.get("title", id.get_slice(":", 1).capitalize())).left(64),
		"description": str(def.get("description", "")).left(300), "order": float(def.get("order", 100.0)),
		"auto_start": bool(def.get("auto_start", false)), "owner": str(def.get("owner", "")),
		"modes": (def.get("modes") as Array).map(func(m): return str(m)) if def.get("modes") is Array else ["survival"],
		"reward": _clean_rewards(def.get("reward"), qualify), "steps": steps}
	return true


func register_tip(id: String, def: Dictionary, qualify: Callable) -> bool:
	var trigger := _clean_goal(def.get("trigger", {"type": "manual"}), qualify)
	if trigger.is_empty() or str(def.get("text", "")).is_empty():
		return false
	tips[id] = {"id": id, "text": str(def.text).left(400), "icon": qualify.call(str(def.get("icon", ""))),
		"page": qualify.call(str(def.get("page", ""))), "trigger": trigger, "owner": str(def.get("owner", ""))}
	if trigger.has("event"):
		_listen(trigger.event)
	return true


func _clean_goal(goal, qualify: Callable) -> Dictionary:
	if goal is String:
		goal = {"type": goal}
	if not (goal is Dictionary):
		return {}
	var type := str(goal.get("type", ""))
	var g: Dictionary = goal.duplicate(true)
	g.count = maxi(1, int(goal.get("count", 1)))
	if type == "event":
		if str(goal.get("event", "")).is_empty():
			return {}
		g.who = str(goal.get("who", "player"))
		g.field = str(goal.get("field", ""))
	elif EVENT_GOALS.has(type):
		g.event = EVENT_GOALS[type][0]
		g.who = EVENT_GOALS[type][1]
		g.field = EVENT_GOALS[type][2]
	elif not type in POLL_GOALS:
		return {}
	var field := str(g.get("field", ""))
	if type in ["have", "biome", "flag"]:
		field = {"have": "item", "biome": "biome", "flag": "flag"}[type]
	if g.has("target") and (field in NAMED_FIELDS):
		var targets: Array = g.target if g.target is Array else [g.target]
		g.target = targets.map(func(t): return qualify.call(str(t)))
	elif g.has("target"):
		g.target = (g.target if g.target is Array else [g.target]).map(func(t): return str(t))
	return g


func _hint_for(hint, goal: Dictionary, qualify: Callable) -> Dictionary:
	if hint is bool and not hint:
		return {}
	if hint is Dictionary:
		for key in ["block", "entity"]:
			if hint.has(key):
				var names: Array = hint[key] if hint[key] is Array else [hint[key]]
				return {key: names.map(func(n): return qualify.call(str(n)))}
		if hint.get("position") is Array and hint.position.size() == 3:
			return {"position": hint.position.map(func(v): return float(v))}
		return {}
	match str(goal.type):
		"break", "place", "use_block":
			if goal.has("target") and goal.type != "place":
				return {"block": goal.target}
		"kill", "breed", "tame":
			if goal.has("target"):
				return {"entity": goal.target}
		"reach":
			if goal.get("position") is Array and goal.position.size() == 3:
				return {"position": goal.position.map(func(v): return float(v))}
	return {}


func _clean_rewards(rewards, qualify: Callable) -> Array:
	var out := []
	for r in (rewards if rewards is Array else []):
		if r is Array and r.size() >= 1:
			out.append([qualify.call(str(r[0])), int(r[1]) if r.size() > 1 else 1])
	return out


func _listen(event: String) -> void:
	if _listening.has(event):
		return
	_listening[event] = true
	# Lowest priority: mods have had their say (a cancelled break never counts).
	_server.add_handler(event, _on_event.bind(event), -1000000)


## Drops a mod's tutorials and tips (before it registers them again on reload). Players in one of its
## tutorials keep their place if the tutorial comes back with enough steps.
func remove_owner(owner: String) -> void:
	for id in tutorials.keys():
		if tutorials[id].owner == owner:
			tutorials.erase(id)
	for id in tips.keys():
		if tips[id].owner == owner:
			tips.erase(id)


## Checks players' tutorial progress after a reload, and resends their trackers.
func revalidate() -> void:
	for p in _server.players.values():
		var s := state_of(p)
		if not s.active.is_empty() and (not tutorials.has(s.active) or s.step >= tutorials[s.active].steps.size()):
			s.active = ""
		sync(p)


## Tutorials in order: [{id, title, description, steps}] for clients.
func to_network() -> Array:
	var list: Array = tutorials.values().map(func(t): return {"id": t.id, "title": t.title, "description": t.description, "steps": t.steps.size(), "order": t.order})
	list.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.title < b.title)
	return list


# --- Player state -----------------------------------------------------------------------------------

## {active, step, progress, done: {id: true}, stopped: {id: true}, tips: {id: true}, tips_off}
static func state_of(p) -> Dictionary:
	if p.tutorial.is_empty():
		p.tutorial = {"active": "", "step": 0, "progress": 0, "done": {}, "stopped": {}, "tips": {}, "tips_off": false,
			"pending_tips": [], "next_tip": 0.0}
	return p.tutorial


func load_player(p, saved) -> void:
	var s := state_of(p)
	if not (saved is Dictionary):
		return
	s.active = str(saved.get("active", ""))
	s.step = int(saved.get("step", 0))
	s.progress = int(saved.get("progress", 0))
	s.tips_off = bool(saved.get("tips_off", false))
	for key in ["done", "stopped", "tips"]:
		for id in (saved.get(key) if saved.get(key) is Array else []):
			s[key][str(id)] = true
	if not tutorials.has(s.active) or s.step >= tutorials[s.active].steps.size():
		s.active = ""


func save_player(p) -> Dictionary:
	var s := state_of(p)
	return {"active": s.active, "step": s.step, "progress": s.progress, "done": s.done.keys(), "stopped": s.stopped.keys(),
		"tips": s.tips.keys(), "tips_off": s.tips_off}


## After joining (or switching to survival): resumes the active tutorial or starts the first
## auto-start one not yet done or stopped.
func on_join(p) -> void:
	var s := state_of(p)
	if s.active.is_empty() and bool(_server.gameplay.get("tutorials", true)):
		var mode := "creative" if p.inventory.creative else "survival"
		for t in to_network():
			var def: Dictionary = tutorials[t.id]
			var modes: Array = def.get("modes", ["survival"]) if def.get("modes") is Array else ["survival"]
			if def.auto_start and modes.has(mode) and not s.done.has(t.id) and not s.stopped.has(t.id):
				start(p, t.id)
				return
	sync(p)


func start(p, id: String) -> bool:
	if not tutorials.has(id):
		return false
	var s := state_of(p)
	s.active = id
	s.step = 0
	s.progress = 0
	s.stopped.erase(id)
	_server.emit("tutorial_started", {"player": p, "tutorial": id})
	sync(p)
	_check_polled(p)  # already holding the goal items, say
	return true


## Stops the active tutorial (it will not start by itself again).
func stop(p) -> void:
	var s := state_of(p)
	if s.active.is_empty():
		return
	s.stopped[s.active] = true
	s.active = ""
	sync(p)


## Completes the current step (skip, or a "manual" goal done by a mod).
func advance(p, skipped := false) -> void:
	var s := state_of(p)
	if s.active.is_empty():
		return
	var t: Dictionary = tutorials[s.active]
	var step: Dictionary = t.steps[s.step]
	if not skipped:
		_give(p, step.reward)
	_server.emit("tutorial_step", {"player": p, "tutorial": t.id, "step": step.title, "index": s.step, "skipped": skipped})
	s.step += 1
	s.progress = 0
	if s.step >= t.steps.size():
		s.done[t.id] = true
		s.active = ""
		_give(p, t.reward)
		if p._online():
			Net.s_tutorial_event.rpc_id(p.peer_id, "completed", t.title)
		_server.play_sound_to(p, "engine:discover")
		_server.emit("tutorial_completed", {"player": p, "tutorial": t.id})
	elif p._online():
		Net.s_tutorial_event.rpc_id(p.peer_id, "skipped" if skipped else "step", step.title)
		if not skipped:
			_server.play_sound_to(p, "engine:craft")
	sync(p)
	if not s.active.is_empty():
		_check_polled(p)


func _give(p, rewards: Array) -> void:
	for r in rewards:
		var id: int = _server.items.id_of(r[0])
		if id > 0:
			p.give(id, r[1])  # a full pack drops the rest at their feet (ServerPlayer.give)


## The tracker the client draws: {} when no tutorial is running.
func view(p) -> Dictionary:
	var s := state_of(p)
	var out := {"done": s.done.keys(), "tips_off": s.tips_off}
	if s.active.is_empty():
		return out
	var t: Dictionary = tutorials[s.active]
	var step: Dictionary = t.steps[s.step]
	out.merge({"tutorial": t.id, "title": t.title, "index": s.step, "total": t.steps.size(),
		"step": {"title": step.title, "text": step.text, "icon": step.icon, "page": step.page, "hint": step.hint,
			"progress": s.progress, "count": step.goal.count}})
	return out


func sync(p) -> void:
	if p._online():
		Net.s_tutorial.rpc_id(p.peer_id, view(p))


func set_tips(p, on: bool) -> void:
	state_of(p).tips_off = not on
	sync(p)


## Shows a tip now (registered id), even if it was seen before.
func show_tip(p, id: String) -> bool:
	if not tips.has(id):
		return false
	var tip: Dictionary = tips[id]
	var s := state_of(p)
	s.tips[id] = true
	s.next_tip = _server._time + TIP_GAP
	if p._online():
		Net.s_tip.rpc_id(p.peer_id, {"id": id, "text": tip.text, "icon": tip.icon, "page": tip.page, "seconds": TIP_SECONDS})
	_server.emit("tip_shown", {"player": p, "tip": id})
	return true


# --- Matching ---------------------------------------------------------------------------------------

func _on_event(ev: Dictionary, event: String) -> void:
	if ev.get("cancelled", false):
		return
	for p in _server.players.values():
		var s := state_of(p)
		if not s.active.is_empty():
			var step: Dictionary = tutorials[s.active].steps[s.step]
			if step.goal.get("event", "") == event and _matches(step.goal, ev, p):
				s.progress += _amount(step.goal, ev)
				if s.progress >= step.goal.count:
					advance(p)
				else:
					sync(p)
		if not s.tips_off:
			for tip in tips.values():
				if tip.trigger.get("event", "") == event and not s.tips.has(tip.id) and not s.pending_tips.has(tip.id) and _matches(tip.trigger, ev, p):
					s.pending_tips.append(tip.id)


func _matches(goal: Dictionary, ev: Dictionary, p) -> bool:
	if ev.get(goal.who) != p:
		return false
	if not goal.has("target") or goal.field.is_empty():
		return true
	return _name_matches(goal.target, _name_of(goal.field, ev.get(goal.field)))


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


static func _name_matches(targets: Array, actual: String) -> bool:
	for t in targets:
		if t == actual or (t.contains("*") and actual.match(t)):
			return true
	return false


func update(delta: float) -> void:
	_poll += delta
	if _poll < POLL_INTERVAL:
		return
	_poll = 0.0
	for p in _server.players.values():
		if p.dead:
			continue
		var s := state_of(p)
		_check_polled(p)
		if s.tips_off:
			s.pending_tips.clear()
			continue
		for tip in tips.values():
			if tip.trigger.type in POLL_GOALS and tip.trigger.type != "manual" and not s.tips.has(tip.id) \
					and not s.pending_tips.has(tip.id) and _poll_met(tip.trigger, p):
				s.pending_tips.append(tip.id)
		if not s.pending_tips.is_empty() and _server._time >= s.next_tip:
			show_tip(p, s.pending_tips.pop_front())


func _check_polled(p) -> void:
	var s := state_of(p)
	if s.active.is_empty():
		return
	var goal: Dictionary = tutorials[s.active].steps[s.step].goal
	if not goal.type in POLL_GOALS:
		return
	if goal.type == "have":
		var have := _have(p, goal)
		if have != s.progress:
			s.progress = mini(have, goal.count)
			if have < goal.count:
				sync(p)
	if _poll_met(goal, p):
		advance(p)


func _have(p, goal: Dictionary) -> int:
	var total := 0
	for i in p.inventory.total():
		var id: int = p.inventory.ids[i]
		if id > 0 and p.inventory.counts[i] > 0 and _name_matches(goal.get("target", []), _server.items.name_of(id)):
			total += p.inventory.counts[i]
	return total


func _poll_met(goal: Dictionary, p) -> bool:
	var pos: Vector3 = p.state.position
	match str(goal.type):
		"have":
			return _have(p, goal) >= goal.count
		"depth":
			return pos.y < float(goal.get("below", 0))
		"reach":
			var at = goal.get("position")
			return at is Array and at.size() == 3 and pos.distance_to(Vector3(at[0], at[1], at[2])) <= float(goal.get("radius", 3.0))
		"biome":
			return _server.biome_generator != null and _name_matches(goal.get("target", []), _server.biome_generator.biome_at(floori(pos.x), floori(pos.z)))
		"hunger_below":
			return bool(_server.gameplay.get("hunger", true)) and not p.inventory.creative and p.hunger < float(goal.get("value", 6))
		"health_below":
			return p.health < float(goal.get("value", 6))
		"night":
			return _server.sleep.is_night()
		"flag":
			return goal.get("target", []).any(func(f): return _server.guide.has_flag(p, f))
	return false
