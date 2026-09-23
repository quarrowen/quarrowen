extends RefCounted
## The creatures the whole server is told about: the rare ones, announced when they arrive, marked on
## everybody's map and compass while they are about, and gone again if nobody comes.
##
## **Why this is engine rather than mod.** A mod can already say a line (`api.broadcast`) and put a
## marker down (`api.set_world_marker`), and that is most of this. What it cannot do cheaply is the
## *following*: the creature wanders, so the marker has to move with it, and a mod doing that needs a
## handler running every tick across every entity to find out where its monster got to. Here it is one
## sweep over a list that is almost always empty.
##
## Modelled on `GameServer.announce_rare_loot`, which had already answered the same question for a
## rare drop: say it in chat, make a noise, and leave something on screen so the find is not lost. A
## hunt is that shape with the quarry moving - so the marker follows, and there is a clock on it.
##
## **The clock is the part that makes it a hunt.** Without one the creature stands where it spawned
## until somebody wanders past, the compass needle stops meaning "go now", and a night's worth of them
## pile up on the map. With one, the announcement is an invitation with an end to it. (the user,
## 2026-09-23)
##
## What opts a creature in is `notable` on its definition; `EntityRegistry._read_notable` says what
## may go in it. Nothing here decides *which* creatures are rare - that is a spawn rule, and spawn
## rules belong to a game.

## Prefix for the markers this puts on the world map. Distinct so a marker left behind by a crash can
## be recognised and swept, which `rebuild` does on the way in.
const MARKER_PREFIX := "engine:notable-"

## How often the markers catch up with what they are following. Finer than a compass needle can show,
## and it costs one loop over a list that is nearly always empty.
const UPDATE_SECONDS := 1.0

var _server
## "<realm>#<entity id>" -> {marker, realm, until, says}. Keyed by realm as well as id because entity
## ids are handed out per realm, so two worlds each have an entity 5 and one would take the other's
## marker off the map. Not saved: a marker outlives its creature by at most one tick, and a world
## reloaded from disk rebuilds the list from the creatures actually in it.
var _tracked := {}
var _task := 0


func _init(server) -> void:
	_server = server


## Starts the sweep. Called once the server is running, because `schedule` needs its clock.
func start() -> void:
	if _task == 0:
		_task = _server.schedule(UPDATE_SECONDS, update, UPDATE_SECONDS)


## A creature has appeared. Announces it and marks it, if it is one of the notable ones.
##
## Every spawn comes through here, including the ordinary ones, so the first line is the one that
## matters: `notable_of` answers `{}` for almost everything and this returns having done nothing.
func arrived(e) -> void:
	if e == null or _tracked.has(_key(e)):
		return
	var says: Dictionary = _server.entities.registry.notable_of(e.type)
	if says.is_empty():
		return
	var key := _key(e)
	_tracked[key] = _entry(e, key, says)
	_mark(e, _tracked[key])
	# Said once in a creature's life, not once per spawn. A persistent creature comes back through the
	# same door when its chunk is loaded again, and a Wisp that announced itself afresh every time
	# somebody walked out of sight and back would make the line mean nothing. The clock does start
	# again, which is a reprieve rather than a bug: nobody was near enough to be hunting it.
	var seen: bool = bool(e.data.get("notable_seen", false))
	e.data["notable_seen"] = true
	var line := str(says.get("announce", ""))
	if seen or line.is_empty():
		return
	_server.broadcast_chat("✦ " + line)
	# The same sound a rare find makes, on purpose: a child learns one noise for "something good is
	# happening" rather than two.
	for p in _server.players.values():
		if p._online():
			_server.play_sound_to(p, "engine:discover")


## It died. Says who, then clears up.
func slain(e, attacker) -> void:
	var entry = _tracked.get(_key(e)) if e != null else null
	if entry == null:
		return
	var line := str(entry.says.get("slain", ""))
	var who := str(attacker.name) if attacker != null and attacker.get("name") != null else ""
	if not line.is_empty() and line.count("%s") == 1:
		line = line % (who if not who.is_empty() else "Somebody")
	if not line.is_empty():
		_server.broadcast_chat("✦ " + line)
	gone(e)


## It is no longer in the world, for whatever reason. Takes its marker off the map.
func gone(e) -> void:
	var key := _key(e) if e != null else ""
	if not _tracked.has(key):
		return
	_server.world_markers.erase(str(_tracked[key].marker))
	_tracked.erase(key)


## Moves each marker to where its creature is now, and sees off the ones whose time has run out.
func update() -> void:
	if _tracked.is_empty():
		return
	var now: float = _server.uptime()
	for key: String in _tracked.keys():
		var entry: Dictionary = _tracked[key]
		var realm = _server.realms.get(str(entry.realm))
		var e = realm.entities.entities.get(int(key.get_slice("#", 1))) if realm != null else null
		if e == null or not e.is_alive():
			_server.world_markers.erase(str(entry.marker))
			_tracked.erase(key)
			continue
		if now >= float(entry.until):
			var line := str(entry.says.get("gone", ""))
			if not line.is_empty():
				_server.broadcast_chat(line)
			_server.world_markers.erase(str(entry.marker))
			_tracked.erase(key)
			realm.entities.remove(e)
			continue
		_mark(e, entry)


## Rebuilds the list from the creatures actually in the world, and sweeps any marker left behind.
##
## Called after a world loads. Notable creatures are saved with their chunk, so one can outlive the
## session it appeared in - and its marker is saved with the world too, which would otherwise leave a
## compass pointing at a monster that had long since been dealt with. Nothing is re-announced: a line
## in chat is for the moment it happened.
func rebuild() -> void:
	_tracked.clear()
	for id: String in _server.world_markers.keys():
		if id.begins_with(MARKER_PREFIX):
			_server.world_markers.erase(id)
	for realm_id: String in _server.realms:
		var realm = _server.realms[realm_id]
		for e in realm.entities.entities.values():
			if not e.is_alive():
				continue
			var says: Dictionary = _server.entities.registry.notable_of(e.type)
			if says.is_empty():
				continue
			var key := _key(e)
			_tracked[key] = _entry(e, key, says)
			_mark(e, _tracked[key])


## How many are being tracked, for the tests and for an admin wondering what is loose.
func count() -> int:
	return _tracked.size()


## Which realm's entity 5 this is. Taken from the creature rather than passed in, so the three hooks
## in `entities.gd` cannot disagree about where something is.
func _key(e) -> String:
	return "%s#%d" % [_realm_of(e), e.id]


func _realm_of(e) -> String:
	if e == null or e._manager == null or e._manager.realm == null:
		return ""
	return str(e._manager.realm.id)


func _entry(e, key: String, says: Dictionary) -> Dictionary:
	var minutes: float = float(says.get("minutes", 10.0))
	# Bracketed rather than trusting the conditional's precedence inside a dictionary value: an `until`
	# that came out as `uptime() + INF` would read as "never" and the clock would silently not exist.
	return {"marker": MARKER_PREFIX + key, "realm": _realm_of(e), "says": says,
		"until": (_server.uptime() + minutes * 60.0) if minutes > 0.0 else INF}


func _mark(e, entry: Dictionary) -> void:
	_server.world_markers[str(entry.marker)] = {"label": _label(entry),
		"position": e.body.position, "color": str(entry.says.get("color", "#ffd166")),
		"dimension": str(entry.realm)}


## The marker's text: what it is, and how long is left to reach it.
##
## The countdown rides in the label rather than in anything new, which is the whole reason it costs
## nothing: the marker is already redrawn on the map and the compass every second, already carries a
## label, and already reaches the client over the map reply - so a clock the players can watch needed
## no new message, no client change and no protocol bump. (the user, 2026-09-23)
func _label(entry: Dictionary) -> String:
	var name := str(entry.says.get("label", ""))
	var left: float = float(entry.until) - _server.uptime()
	if not is_finite(left):
		return name.left(32)
	# Seconds near the end, because "0m" on a thing that is about to go is worse than no clock at all.
	var clock := "%ds" % maxi(int(ceil(left)), 0) if left < 60.0 else "%dm" % int(ceil(left / 60.0))
	return ("%s · %s" % [name, clock]).left(32)
