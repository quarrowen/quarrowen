extends RefCounted
## A private copy of a space: a dungeon four players go into together, a puzzle room one player gets
## their own of, an arena that is thrown away when the fight ends.
##
##     api.register_instance("dungeon", {"generator": DungeonRooms.new(), "empty_seconds": 30,
##         "max_players": 4})
##
##     var run: String = api.open_instance("dungeon", {"seed": 7})
##     api.enter_instance(p, run, Vector3(8, 65, 8))   # remembers where they came from
##     api.leave_instance(p)                           # puts them back there
##
## **An instance is a realm with a lifetime**, which is why this is small: dimensions already built
## the hard half - a separate world with its own terrain, creatures, tickers and coordinate space, in
## the same server at the same time. What an instance adds is that it is made on demand, that it is
## private to the people in it, and that it goes away.
##
## Three things follow from "it goes away", and each is a decision rather than an omission:
##
## **Nothing is written to disk.** The realm is marked `ephemeral`, so `_save_all` skips it. A dungeon
## run that outlived the server would be a folder nobody can get back into, and a crash mid-run would
## leave one every time.
##
## **Everybody is put back where they came from.** The return point is taken when they enter, not
## guessed when they leave - by the time an instance closes, the place they came from may be the only
## thing left to know about them. Held here rather than on the player, so it is not part of the save
## format for something that never survives a restart.
##
## **Empty is not the same as finished.** An instance closes after `empty_seconds` with nobody in it,
## not the moment the last player steps out, because stepping out for a moment is a thing people do -
## and a dungeon that vanished behind you while you checked your bag would be a bug nobody could
## explain. A mod that really means "now" calls `close_instance`.

## The most instances that may be live at once, across all kinds. A ceiling rather than a policy: each
## one is a realm with its own world and entity set, and a mod with a loop in it should hit a wall
## with a name on it rather than the machine's memory.
const MAX_LIVE := 64
## How long an instance sits empty before it closes, when its kind does not say.
const DEFAULT_EMPTY_SECONDS := 30.0

var server
## Kinds a mod registered: name -> def.
var kinds := {}
## Instances that exist now: id -> {kind, realm_id, members, empty_since, data}.
var live := {}
## Where a player was before they entered: player id -> {realm, position}.
var _returns := {}
var _next := 1


func _init(game_server) -> void:
	server = game_server


## Why the last call refused, in words somebody can be shown.
var problem := ""


## Declares a kind of instance. `generator` is the terrain (the same object `set_world_generator`
## takes); without one the instance is empty air, which is what a mod building its own room wants.
##
## def: {generator, passes, empty_seconds, max_players, display_name}.
func register(kind_name: String, def: Dictionary) -> bool:
	if kind_name.is_empty():
		push_error("register_instance: needs a name")
		return false
	kinds[kind_name] = {
		"name": kind_name,
		"display_name": String(def.get("display_name", kind_name.get_slice(":", 1).capitalize())).left(48),
		"generator": def.get("generator"),
		"passes": def.get("passes") if def.get("passes") is Array else [],
		"empty_seconds": clampf(float(def.get("empty_seconds", DEFAULT_EMPTY_SECONDS)), 0.0, 3600.0),
		"max_players": clampi(int(def.get("max_players", 8)), 1, 64),
	}
	return true


## Makes one, and returns its id ("" if it could not be made).
##
## options: {seed, data (anything the mod wants to keep with it)}.
func open(kind_name: String, options := {}) -> String:
	problem = ""
	var kind: Dictionary = kinds.get(kind_name, {})
	if kind.is_empty():
		problem = "There is no '%s' to go into." % kind_name
		push_error("open_instance: no instance kind '%s' is registered" % kind_name)
		return ""
	if live.size() >= MAX_LIVE:
		problem = "Too many of those are open already."
		push_error("open_instance: %d instances are already live (MAX_LIVE)" % live.size())
		return ""
	# The number is part of the realm id, so two runs of the same dungeon are two different worlds
	# rather than two names for one.
	var instance_id := "%s#%d" % [kind_name, _next]
	_next += 1
	var made = server.add_realm(instance_id, String(kind.display_name))
	if made == null:
		problem = "That could not be opened."
		return ""
	made.ephemeral = true
	if kind.generator is Object:
		made.generator = kind.generator
	if not (kind.passes as Array).is_empty():
		made.generation_passes = (kind.passes as Array).duplicate()
	if options.has("seed"):
		made.seed_value = int(options.seed)
	live[instance_id] = {"kind": kind_name, "realm_id": instance_id, "members": {},
		"empty_since": server._time, "data": options.get("data", {})}
	server.emit("instance_opened", {"instance": instance_id, "kind": kind_name})
	return instance_id


## Sends a player in, remembering where they were so `leave` can put them back.
func enter(player, instance_id: String, position: Vector3) -> bool:
	problem = ""
	var it: Dictionary = live.get(instance_id, {})
	if it.is_empty():
		problem = "That is not open any more."
		return false
	var kind: Dictionary = kinds.get(String(it.kind), {})
	if it.members.size() >= int(kind.get("max_players", 8)) and not it.members.has(player.player_id):
		problem = "That is full."
		return false
	# Taken before the move, because after it their realm is the instance and the way back is gone.
	if not _returns.has(player.player_id):
		_returns[player.player_id] = {"realm": String(player.realm_id), "position": player.state.position}
	if not server.send_to_realm(player, instance_id, position):
		_returns.erase(player.player_id)
		problem = "That could not be entered."
		return false
	it.members[player.player_id] = true
	server.emit("instance_entered", {"player": player, "instance": instance_id, "kind": it.kind})
	return true


## Puts a player back where they were before they entered. Returns false if they were not in one.
func leave(player) -> bool:
	var instance_id := id_of(player)
	if instance_id.is_empty():
		return false
	var back: Dictionary = _returns.get(player.player_id, {})
	_returns.erase(player.player_id)
	var it: Dictionary = live.get(instance_id, {})
	if not it.is_empty():
		it.members.erase(player.player_id)
		if it.members.is_empty():
			it.empty_since = server._time
	# Somewhere rather than nowhere: a return point that has gone (the realm was removed while they
	# were inside) still has to put them down in a world that exists.
	var to_realm := String(back.get("realm", ""))
	if not server.realms.has(to_realm):
		to_realm = ""
	var to_position: Vector3 = back.get("position", Vector3.ZERO) if back.has("position") else server._default_spawn()
	server.send_to_realm(player, to_realm, to_position)
	server.emit("instance_left", {"player": player, "instance": instance_id})
	return true


## Closes one now: everybody inside goes back, and the realm is thrown away.
func close(instance_id: String) -> bool:
	var it: Dictionary = live.get(instance_id, {})
	if it.is_empty():
		return false
	for player_id in it.members.keys():
		var p = server.player_by_id(String(player_id))
		if p != null:
			leave(p)
	# Anybody offline inside it: their saved position is in a realm that is about to stop existing, so
	# move the record rather than leave them to load into nowhere.
	for p in server.players.values():
		if String(p.realm_id) == instance_id:
			leave(p)
	live.erase(instance_id)
	server.remove_realm(instance_id)
	server.emit("instance_closed", {"instance": instance_id, "kind": it.kind})
	return true


## The instance a player is in, or "".
func id_of(player) -> String:
	if player == null:
		return ""
	return String(player.realm_id) if live.has(String(player.realm_id)) else ""


## What a mod kept with an instance when it opened it.
func data_of(instance_id: String) -> Dictionary:
	var it: Dictionary = live.get(instance_id, {})
	return it.get("data", {}) if it.get("data") is Dictionary else {}


## Closes instances that have been empty long enough. Called each tick.
func update(_delta: float) -> void:
	if live.is_empty():
		return
	for instance_id in live.keys():
		var it: Dictionary = live[instance_id]
		if not it.members.is_empty():
			continue
		var after := float(kinds.get(String(it.kind), {}).get("empty_seconds", DEFAULT_EMPTY_SECONDS))
		if server._time - float(it.empty_since) >= after:
			close(String(instance_id))
