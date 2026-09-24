extends RefCounted
## Firstlight's story: twelve acts from waking up in a meadow to waking what is under it, and five
## side tasks that are worth doing and are never in the way.
##
## **Wick hands these out and the task list carries them** - the hybrid the user asked for
## (2026-09-24): "He tells me and it gets added to the task list yes." So the conversation is where
## the story *happens* and the list is where it is *remembered*, and a child who put the game down on
## Tuesday is not asked to recall what a man in a hat said.
##
## **The engine never decides a step is done.** `api.advance_objective` is the mod's to call, which
## is deliberate - the engine would otherwise have to learn what "find the deep stone" means. So each
## step carries a `goal`, and one handler per event kind walks whoever is holding a matching step.
## That is the whole design: **a table, not twelve bespoke watchers**. The first draft was the latter
## and act 7 quietly watched the wrong event for an hour before anybody noticed, because there was
## nowhere for the mistake to show up.
##
## Two rules about the *shape* of the chain, which matter more than any single act:
##
## - **Every act is finishable by playing normally.** Nothing asks the player to go somewhere the game
##   has not already given them a reason to go. The acts are a name for what a survival player does
##   anyway, until act 10, where the story asks for something it has not asked for before.
## - **Nothing is timed and nothing can be failed.** They are children, and an objective that expires
##   turns a story into homework.

const Acts = preload("res://mods/firstlight/acts.gd")

var api
var _by_goal := {}   # event kind -> [[objective name, step index, goal]]
var _ids := {}       # the block and item ids the goals name, resolved once at setup


func setup(mod_api) -> void:
	api = mod_api
	_resolve(api)
	# The chain sorts above the errands whatever order they are handed over in, which is what `order`
	# is for - see engine/server/objectives.gd. Passed explicitly rather than guessed from the shape
	# of the entry, so the one thing that decides what a player reads first is written down.
	_register_all(Acts.ACTS, 1)
	_register_all(Acts.SIDE, 2)
	_listen(api)


func _register_all(entries: Array, order: int) -> void:
	for act in entries:
		var steps := []
		for step in act.steps:
			steps.append({"text": String(step.text), "count": int(step.get("count", 1))})
		api.register_objective(String(act.id), {"display_name": String(act.name),
			"description": String(act.get("description", "")), "steps": steps,
			"repeatable": bool(act.get("repeatable", false)), "order": order})
		for i in (act.steps as Array).size():
			var goal: Dictionary = act.steps[i].get("goal", {})
			if goal.is_empty():
				continue
			var kind := String(goal.get("on", ""))
			if not _by_goal.has(kind):
				_by_goal[kind] = []
			_by_goal[kind].append([String(act.id), i, goal])


## The ids the goals name, looked up once. **`require_*` rather than `block`/`item`**, because those
## answer -1 for "not installed" and a -1 kept in a table is the bug this codebase has written down
## twice: it becomes 65535 when it is used as an id, and 65535 means unloaded.
func _resolve(api) -> void:
	for name in Acts.blocks_named():
		_ids[name] = api.require_block(name)
	for name in Acts.items_named():
		_ids[name] = api.require_item(name)


## One handler per event kind, each walking the steps that asked for it. A step only counts for a
## player who is actually on it, which `advance_objective` already enforces - so these do not have to
## know anything about where anybody is in the chain.
func _listen(api) -> void:
	api.on("block_broken", func(ev): _score("break", ev.player, ev.get("block", -1)))
	api.on("block_placed", func(ev): _score("place", ev.player, ev.get("block", -1)))
	api.on("item_crafted", func(ev): _score("craft", ev.player, ev.get("item", -1), int(ev.get("count", 1))))
	api.on("item_pickup", func(ev): _score("carry", ev.player, ev.get("item", -1), int(ev.get("count", 1))))
	api.on("player_eat", func(ev): _score("eat", ev.player, ev.get("item", -1)))
	api.on("entity_tamed", func(ev): _score("tame", ev.player, -1))
	# Waking up is the honest end of a night: sleeping through one and living through one both count,
	# and a child who hid in a hole until dawn has survived it just as much as one who found a bed.
	api.on("player_wake", func(ev): _score("night", ev.player, -1))
	api.on("time_changed", func(ev):
		if String(ev.get("phase", "")) == "day":
			for p in api.players():
				_score("night", p, -1))
	# Killing something the whole server was told about. Asked of the registry rather than listed
	# here, so a rare creature added later counts without this file hearing about it.
	api.on("entity_death", func(ev):
		if ev.get("attacker") == null or ev.entity == null:
			return
		if not api.notable_of(ev.entity.type).is_empty():
			_score("notable", ev.attacker, -1))
	# A multiblock is finished by *blocks*, not by a player, so the event names no-one. Credited to
	# whoever is standing near it, which in a game two children play together is both of them - and
	# that is the right answer: they built it together.
	api.on("multiblock_formed", func(ev):
		var at: Vector3 = Vector3(ev.get("controller", Vector3i.ZERO))
		for p in api.players():
			if p.position.distance_to(at) <= 32.0:
				_score("built", p, -1, 1, String(ev.get("name", ""))))
	# Depth is a state, not an event, so it is the one thing that has to be looked at rather than
	# waited for. Five seconds is plenty: nobody digs past a milestone and back in less.
	api.every(5.0, func():
		for p in api.players():
			_score("depth", p, -1, 1, "", p.position.y))


## Counts one thing that happened towards every step waiting for it.
##
## `subject` is the block or item id, `tag` a name (a multiblock's), `value` a number (how deep). A
## goal matches when everything it asked for matches; a goal that asked for nothing matches anything,
## which is what "cook ten things" wants.
func _score(kind: String, player, subject: int, amount := 1, tag := "", value := 0.0) -> void:
	if player == null:
		return
	for entry in _by_goal.get(kind, []):
		var objective_name: String = entry[0]
		var step: int = entry[1]
		var goal: Dictionary = entry[2]
		if not api.has_objective(player, objective_name):
			continue
		if not _on_step(player, objective_name, step):
			continue
		if goal.has("name") and String(goal.name) != tag:
			continue
		if goal.has("below") and value >= float(goal.below):
			continue
		if goal.has("any"):
			# A list of ids, any of which counts - "an iron tool" is four items and one idea.
			var wanted := false
			for want in goal.any:
				if _ids.get(String(want), -1) == subject:
					wanted = true
					break
			if not wanted:
				continue
		elif goal.has("is") and _ids.get(String(goal.is), -1) != subject:
			continue
		api.advance_objective(player, objective_name, amount)


## Whether this player is on that step right now. Steps within one objective are in an order and only
## the current one may be counted towards; without this, chopping logs would also fill "mine stone"
## the moment the two shared an event.
func _on_step(player, objective_name: String, step: int) -> bool:
	for task in api.objectives_of(player):
		# The list comes back with names qualified ("firstlight:act_iron"); the table here is written
		# in the mod's own short names, the way every other api call takes them.
		var held := String(task.get("name", ""))
		if held == objective_name or held.ends_with(":" + objective_name):
			return int(task.get("step", -1)) == step
	return false


## Starts the chain, or picks it up where it was left. Called when the player accepts Wick's offer.
func begin(player) -> void:
	if player == null:
		return
	advance_to_next(player)
	# The side tasks all at once, and quietly. They are things worth doing that are never in the way,
	# so they belong in the list from the start rather than being handed over one at a time as though
	# they mattered as much as the chain does.
	for side in Acts.SIDE:
		api.give_objective(player, String(side.id))


## Gives whichever act comes next, once, in order. Safe to call whenever: an act already held or
## already finished is skipped, so this doubles as "did anything get missed".
func advance_to_next(player) -> bool:
	for act in Acts.ACTS:
		var act_id := String(act.id)
		if api.objective_finished(player, act_id) > 0:
			continue
		if api.has_objective(player, act_id):
			return false  # they are in the middle of this one
		api.give_objective(player, act_id)
		player.send_message("[Wick] %s" % String(act.get("said", act.name)))
		# The page that explains what he just asked for, where there is one. Unlocked rather than
		# opened: a book that opens itself over the world is a thing you have to close, and a child
		# who wants it will see the badge count go up.
		var page := String(act.get("page", ""))
		if not page.is_empty():
			api.unlock_guide_page(player, page)
		return true
	return false


## What he says when asked to repeat himself, which children do and should.
func remind(player) -> String:
	var tasks: Array = api.objectives_of(player)
	if tasks.is_empty():
		return "Nothing pressing. Enjoy it while it lasts."
	var first: Dictionary = tasks[0]
	return "%s. That's where we are." % String(first.get("text", "Keeping going"))
