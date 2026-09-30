extends RefCounted
## The descent: one entrance, floors that get harder the further down you go, and you leave when you
## choose.
##
## **There is one mechanic here, not two.** The scope started as "a dungeon" and "a roguelike run" -
## a floor with an exit against floors until you die - and the user's four answers collapsed them:
## depth is the difficulty, the floors do not stop, and you leave when you decide to. A dungeon trip is
## a shallow descent somebody left early; a run is the same descent taken further. One generator, one
## set of rooms, and the difference is the player's nerve. So the word "mode" does not appear in this
## file. (28 September 2026)
##
## **The way out is the whole design.** If floors are endless and depth is the difficulty, then the
## question on every floor is "deeper, or out?" - and that question only exists if there is a way out
## that is not dying. Without one, endless floors means playing until you lose, which deletes the
## decision that makes the thing good. So every floor has a way up, three blocks from where you land,
## and taking it keeps everything you are carrying. Going down is the easy thing; choosing to stop is
## the hard one.
##
## **Harsh and gentle are one rule apart**, not two dungeons: `keep_inventory`, set on the floor's own
## realm. That is what per-realm gameplay was built for, and it means the engine enforces it rather
## than this file remembering to.
##
## **A floor is an instance** - the engine's word for a realm with a lifetime. Never written to disk,
## thrown away when you leave it, and a fresh one every time anybody comes down. Going deeper enters the
## next floor and *then* closes the one behind, which needed a small engine change: a player who moved
## between instances stayed on the old one's member list, so closing the floor you had left threw you
## out of the floor in front of you.
##
## **Solo, for now.** A floor takes one player. A descent with a party has real questions in it - if one
## of you takes the way down, what happens to the others standing on floor four - and answering them
## badly is worse than not answering them yet. Recorded in PROGRESS rather than guessed at.

const Strata = preload("res://mods/firstlight/strata.gd")

const KIND := "floor"
## The ledger a descent pays into, and what harsh costs to take. **Harsh is bought with gentle runs**,
## which is the user's "gate it behind some kind of in-game currency so it is more of a choice"
## (28 September 2026) answered with the only currency the descent could honestly mint: depth already
## survived. A first run is therefore always gentle, and risking everything is something you work up to
## rather than something you pick off a menu on day one. Coming out pays the depth you reached, so the
## cost is a little over two floors' worth - enough to be a decision, not enough to be a wall.
const MARKS := "marks"
const HARSH_COST := 10.0
## Where a boss stands. Every fifth floor, in the room with the way down, so choosing to go deeper is
## also choosing to fight - and a boss that turns up from a spawner is not an event, which is why the
## Barrow Warden is deliberately not in the nest bands.
const BOSS_EVERY := 5
const BOSS := "base:barrow_warden"
## A player's deepest floor, kept in their own saved data so it survives the run that set it.
const BEST := "firstlight:deepest"
## A floor nobody is in closes quickly: it is procedural, it is not saved, and there is nothing in it
## anybody could come back for. `out` and `_deeper` both close explicitly, so this is only the net.
const EMPTY := 15.0

var api
var strata := Strata.new()
## player_id -> {depth, instance, harsh, entry, regions}
var runs := {}
## Why the last `enter` refused, or "". The caller prints one message or the other, never both: a
## player told exactly what a run costs and *then* told "you cannot go down from here" has been
## answered and then contradicted.
var problem := ""


func setup(mod_api) -> void:
	api = mod_api
	strata.setup(api)
	api.register_ledger(MARKS, {"display_name": "Depth Marks", "min": 0})
	# No generator, deliberately: an instance without one is empty air, and `strata` fills it with rock
	# and then cuts rooms out of that.
	api.register_instance(KIND, {"display_name": "The Descent", "empty_seconds": EMPTY, "max_players": 1})
	api.on("region_entered", _on_region)
	api.on("player_respawn", _on_respawn)
	# Somebody who logs out mid-run: the floor has to go, or it sits there until `empty_seconds` and
	# their run is still live in this dictionary when they come back to a realm that has gone.
	api.on("player_leave", func(ev): abandon(ev.player))


## Starts a descent. `harsh` loses what you are carrying when you die and ends the run; gentle puts you
## back at the top of the floor and carries on.
func enter(player, harsh: bool) -> bool:
	problem = ""
	if player == null or runs.has(player.player_id):
		return false
	if not api.instance_of(player).is_empty():
		problem = "Not from in here."
		return false
	# Said before anything is opened, and said in full: what it costs, and what they have. A refusal
	# that only says no is a refusal somebody has to go and research.
	if harsh and not api.spend_balance(player, MARKS, HARSH_COST):
		problem = ("Risking everything costs %d depth marks and you have %d. Marks come from coming "
			+ "back up: a run pays the floor you reached.") % [int(HARSH_COST),
			int(api.balance_of(player, MARKS))]
		return false
	runs[player.player_id] = {"depth": 0, "instance": "", "harsh": harsh,
		"entry": Vector3.ZERO, "regions": []}
	if not _open(player, 1):
		runs.erase(player.player_id)
		return false
	player.show_title("The Descent",
		"Everything you carry is at risk" if harsh else "Your things are safe down there", 5.0)
	return true


## Opens the next floor, puts them in it, and shuts the one behind.
func _open(player, depth: int) -> bool:
	var run: Dictionary = runs.get(player.player_id, {})
	if run.is_empty():
		return false
	var instance: String = api.open_instance(KIND, {"data": {"depth": depth}})
	if instance.is_empty():
		player.send_message("The way down will not open just now.")
		return false
	# **On the instance's own id, not the kind's.** Each floor is its own realm, so the rules go on the
	# realm that was just opened rather than on the name it was opened from - which would set them on a
	# realm that does not exist and silently do nothing.
	api.set_gameplay({"keep_inventory": not bool(run.harsh), "pvp": false,
		"mob_spawning": true, "hunger": true}, instance)
	var made: Dictionary = strata.build(instance, depth)

	# Held before the new ones replace them, so the floor being left takes its regions with it. There
	# are only 256 regions in the server and a descent of thirty floors would eat them all.
	var leaving := String(run.instance)
	var stale: Array = (run.regions as Array).duplicate()

	run.depth = depth
	run.instance = instance
	run.entry = made.entry
	run.regions = [
		_pad(instance, made.up, "up"),
		_pad(instance, made.down, "down"),
	]
	# **Checked, and said out loud when it fails.** `enter_instance` can refuse - the instance closed
	# under us, or it is full - and a mod that ignores the answer leaves the player standing in the
	# overworld with a run recorded as being on floor three. Two screenshots were taken of somebody
	# standing in a field before anything asked whether this had worked. (2026-09-28)
	if not api.enter_instance(player, instance, made.entry):
		api.warn("could not put %s into %s: %s" % [player.name, instance, api.instance_problem()])
		player.send_message("The way down closed before you could take it.")
		api.close_instance(instance)
		for id in run.regions:
			if int(id) > 0:
				api.remove_region(int(id))
		run.instance = leaving
		run.regions = stale
		return false
	if not leaving.is_empty():
		_shut(leaving, stale)
	api.info("%s is on floor %d (%s, %d rooms)" % [player.name, depth, instance, int(made.rooms)])
	player.show_title("Floor %d" % depth, "%d rooms" % int(made.rooms), 3.0)
	# Deeper is lower. The same cue at a falling pitch says "further down" without a single new sound
	# file, and it is the one thing a player hears on every floor.
	api.play_sound("engine:discover", run.entry, 0.9, maxf(1.05 - 0.05 * depth, 0.55), instance)
	if depth % BOSS_EVERY == 0:
		_wake_the_warden(instance, made.down)
	_mark_best(player, depth)
	_show_run(player, run)
	return true


## The boss stands in the room with the way down, so choosing to go deeper is also choosing to fight.
##
## Spawned into the air above the pad and then placed, because `spawn_entity` refuses a spot with no
## room to stand and hands back null, and a mod that does not check carries on as though it worked. The
## Warden is `persistent`, so it is not swept for having nobody near it before the player walks in.
func _wake_the_warden(instance: String, at: Vector3i) -> void:
	var boss = api.spawn_entity(BOSS, Vector3(at) + Vector3(0.5, 2.0, 0.5), {"realm": instance})
	if boss == null:
		api.warn("no room for the Warden on this floor (%s)" % instance)
		return
	boss.position = Vector3(at) + Vector3(0.5, 0.0, 0.5)
	api.play_sound("engine:crit", boss.position, 1.0, 0.6, instance)
	api.play_effect("engine:smoke", boss.position, {"scale": 2.0}, instance)


## Deepest floor reached, kept in the player's own saved data so it outlives the run that set it. The
## Fairground's boards give its games a number to beat; this is the descent's, and it is a reason to
## come back up rather than a reason to stop.
func _mark_best(player, depth: int) -> void:
	if depth <= int(player.data.get(BEST, 0)):
		return
	player.data[BEST] = depth
	if depth > 1:
		player.send_message("A new deepest: floor %d." % depth)


## The only thing on screen that says a run is happening, and how it is going.
func _show_run(player, run: Dictionary) -> void:
	player.show_ui("firstlight:descent", {"anchor": "top_right", "children": [
		{"type": "label", "text": "Floor %d" % int(run.depth), "size": 18},
		{"type": "label", "text": "Deepest  %d" % int(player.data.get(BEST, 0)), "size": 13},
		{"type": "label", "text": "Everything at risk" if bool(run.harsh) else "Your things are safe",
			"size": 12}]})


## A region over one of the two pads. Three blocks across and three tall, so stepping onto it counts and
## walking past it does not.
func _pad(instance: String, at: Vector3i, which: String) -> int:
	return api.add_region("descent_%s" % which, Vector3(at) + Vector3(-1.0, 0.0, -1.0),
		Vector3(at) + Vector3(2.0, 3.0, 2.0),
		{"realm": instance, "data": {"descent": which}})


func _on_region(ev) -> void:
	var which := String(ev.data.get("descent", ""))
	if which.is_empty() or ev.player == null:
		return
	var run: Dictionary = runs.get(ev.player.player_id, {})
	# A pad in a floor this player is not on: impossible today with one player to a floor, and cheap to
	# refuse rather than rely on that staying true.
	if run.is_empty() or String(run.instance) != api.instance_of(ev.player):
		return
	if which == "down":
		_open(ev.player, int(run.depth) + 1)
	else:
		out(ev.player)


## Leaving with everything, which is the decision the whole thing turns on.
func out(player) -> void:
	var run: Dictionary = runs.get(player.player_id, {})
	if run.is_empty():
		return
	var depth := int(run.depth)
	runs.erase(player.player_id)
	api.leave_instance(player)
	_shut(String(run.instance), run.get("regions", []))
	player.hide_ui("firstlight:descent")
	# **The floor you reached, paid for reaching it and coming back.** Dying pays nothing, which is what
	# makes the way up worth taking: a run is only worth what you carry out of it.
	api.add_balance(player, MARKS, float(depth))
	api.play_sound("engine:discover", player.position, 1.0, 1.2, api.realm_of(player))
	player.show_title("Back up", "Floor %d  ·  %d marks" % [depth, depth], 5.0)


## A run that ends without anybody choosing: logging out, or the mod reloading. **No message**, because
## there is nobody to read one.
func abandon(player) -> void:
	var run: Dictionary = runs.get(player.player_id, {})
	if run.is_empty():
		return
	runs.erase(player.player_id)
	api.leave_instance(player)
	_shut(String(run.instance), run.get("regions", []))
	player.hide_ui("firstlight:descent")


func _shut(instance: String, regions: Array) -> void:
	for id in regions:
		if int(id) > 0:
			api.remove_region(int(id))
	api.close_instance(instance)


## Where somebody comes back after dying, which is the only difference between harsh and gentle that
## this file has to write out - the rest is `keep_inventory` on the realm.
func _on_respawn(ev) -> void:
	var run: Dictionary = runs.get(ev.player.player_id, {})
	if run.is_empty():
		return
	if not bool(run.harsh):
		# Still in the floor, at the top of it, with everything. The run carries on.
		ev.position = run.entry
		ev.player.send_message("Back at the top of floor %d." % int(run.depth))
		_show_run(ev.player, run)
		return
	# Harsh: the run is over and what you were carrying is on the floor where you fell - in *that* realm,
	# which the engine only started doing correctly on 28 September 2026. Before that it went to the same
	# coordinates in the overworld, which is the mechanic not working at all rather than working harshly.
	var depth := int(run.depth)
	runs.erase(ev.player.player_id)
	api.leave_instance(ev.player)
	_shut(String(run.instance), run.get("regions", []))
	ev.player.hide_ui("firstlight:descent")
	# `leave_instance` has already moved them; the respawn teleport that follows this handler would
	# otherwise put them back at a spawn point in a realm that no longer exists.
	ev.position = ev.player.position
	ev.player.show_title("The run is over", "You got to floor %d" % depth, 6.0)


## Whether somebody is down there, and how deep. For the guidebook and for anything that wants to ask.
func depth_of(player) -> int:
	return int(runs.get(player.player_id, {}).get("depth", 0)) if player != null else 0
