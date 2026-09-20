extends RefCounted
## A piece of ground with an owner, which the engine asks before letting anybody change a block in it.
##
## Called a plot rather than a claim because `claims.gd` already means something else here - keeping
## part of the world awake - and two things with one name in one engine is how somebody ends up
## reading the wrong file at midnight.
##
## **What may be claimed, how much, and what it costs are the mod's.** The engine stores a box, an
## owner and a list of who else may build, and consults it on every edit. It has no opinion about
## whether land is bought, earned, granted or simply taken.
##
## The owner is either a player or a **company**, which is the whole reason companies are separate:
## a plot belonging to a guild outlives whichever member happened to mark it out.
##
## Admins are never stopped. Somebody has to be able to put right a plot marked over a village, and a
## server where the person running it cannot fix things is a server that eventually cannot be fixed.

const MAX_PLOTS := 4096
## The biggest a single plot may be, in blocks. A mod may allow less; it may not allow more, because
## one enormous plot is indistinguishable from turning building off for everybody else.
const MAX_VOLUME := 262144

var server

## id -> {id, realm, from, to, owner_player, owner_company, name, members: {player_id: true}, open}
var plots := {}
var _next_id := 1
## Why the last claim was refused, in words somebody can be shown.
var problem := ""


func _init(game_server) -> void:
	server = game_server


## Marks out a plot. `owner` is a player id, or use `company` for one owned by a group.
func claim(realm_id: String, from: Vector3i, to: Vector3i, options := {}) -> int:
	problem = ""
	var low := Vector3i(mini(from.x, to.x), mini(from.y, to.y), mini(from.z, to.z))
	var high := Vector3i(maxi(from.x, to.x), maxi(from.y, to.y), maxi(from.z, to.z))
	var size := high - low + Vector3i.ONE
	var volume := size.x * size.y * size.z
	if volume > MAX_VOLUME:
		problem = "That is %d blocks; a plot may be %d." % [volume, MAX_VOLUME]
		return 0
	if plots.size() >= MAX_PLOTS:
		problem = "This world has as many plots as it can hold."
		return 0
	var owner_player := String(options.get("owner", ""))
	var owner_company := int(options.get("company", 0))
	if owner_player.is_empty() and owner_company <= 0:
		problem = "A plot needs somebody to belong to."
		return 0
	# Overlapping is refused rather than nested or split: two owners of one block is a question with no
	# good answer, and every game that has tried has regretted it.
	for id: int in plots:
		var other: Dictionary = plots[id]
		if other.realm == realm_id and _overlaps(low, high, other.from, other.to):
			problem = "That overlaps %s." % (String(other.name) if not String(other.name).is_empty() else "another plot")
			return 0
	var id := _next_id
	_next_id += 1
	plots[id] = {"id": id, "realm": realm_id, "from": low, "to": high, "name": String(options.get("name", "")),
		"owner_player": owner_player, "owner_company": owner_company, "members": {}, "open": bool(options.get("open", false))}
	server.emit("plot_claimed", {"plot": id, "realm": realm_id, "from": low, "to": high,
		"owner": owner_player, "company": owner_company})
	return id


func release(id: int) -> bool:
	var plot: Dictionary = plots.get(id, {})
	if plot.is_empty():
		return false
	plots.erase(id)
	server.emit("plot_released", {"plot": id, "realm": plot.realm})
	return true


static func _overlaps(a_low: Vector3i, a_high: Vector3i, b_low: Vector3i, b_high: Vector3i) -> bool:
	return a_low.x <= b_high.x and a_high.x >= b_low.x and a_low.y <= b_high.y and a_high.y >= b_low.y \
		and a_low.z <= b_high.z and a_high.z >= b_low.z


## The plot a block is in, or {}.
func at(realm_id: String, pos: Vector3i) -> Dictionary:
	for id: int in plots:
		var plot: Dictionary = plots[id]
		if plot.realm != realm_id:
			continue
		if pos.x >= plot.from.x and pos.x <= plot.to.x and pos.y >= plot.from.y and pos.y <= plot.to.y \
				and pos.z >= plot.from.z and pos.z <= plot.to.z:
			return plot
	return {}


## Lets somebody else build here. A plot owned by a company already admits its members.
func add_member(id: int, player_id: String) -> bool:
	var plot: Dictionary = plots.get(id, {})
	if plot.is_empty() or player_id.is_empty():
		return false
	plot.members[player_id] = true
	return true


func remove_member(id: int, player_id: String) -> bool:
	var plot: Dictionary = plots.get(id, {})
	return not plot.is_empty() and plot.members.erase(player_id)


## Whether this player may change a block here. Everything outside a plot is allowed: the engine does
## not decide that the world is closed by default, because most of it is not anybody's.
func may_build(player, realm_id: String, pos: Vector3i) -> bool:
	var plot := at(realm_id, pos)
	if plot.is_empty():
		return true
	return may_build_in(player, plot)


func may_build_in(player, plot: Dictionary) -> bool:
	if player == null or plot.is_empty():
		return true
	if bool(plot.get("open", false)):
		return true
	# Admins are never stopped. Somebody has to be able to put right a plot marked over a village.
	if server.is_admin(player):
		return true
	var who := String(player.player_id)
	if who == String(plot.owner_player) or plot.members.has(who):
		return true
	var company := int(plot.owner_company)
	return company > 0 and server.companies.is_member(company, who)


## Every plot somebody has a say in, for a screen or a command.
func of_player(player_id: String) -> Array:
	var out := []
	for id: int in plots:
		var plot: Dictionary = plots[id]
		var company := int(plot.owner_company)
		if String(plot.owner_player) == player_id or plot.members.has(player_id) \
				or (company > 0 and server.companies.is_member(company, player_id)):
			out.append(info(id))
	return out


func info(id: int) -> Dictionary:
	var plot: Dictionary = plots.get(id, {})
	if plot.is_empty():
		return {}
	return {"id": id, "realm": plot.realm, "from": plot.from, "to": plot.to, "name": plot.name,
		"owner": plot.owner_player, "company": plot.owner_company, "members": (plot.members as Dictionary).keys(),
		"open": bool(plot.open)}


func to_saved() -> Array:
	var out := []
	for id: int in plots:
		var plot: Dictionary = plots[id]
		out.append({"id": id, "realm": plot.realm, "name": plot.name, "open": plot.open,
			"from": [plot.from.x, plot.from.y, plot.from.z], "to": [plot.to.x, plot.to.y, plot.to.z],
			"owner": plot.owner_player, "company": plot.owner_company, "members": (plot.members as Dictionary).keys()})
	return out


func load_saved(list) -> void:
	plots.clear()
	_next_id = 1
	if not (list is Array):
		return
	for entry in list:
		if not (entry is Dictionary) or not (entry.get("from") is Array) or not (entry.get("to") is Array):
			continue
		var from = entry.from
		var to = entry.to
		if from.size() != 3 or to.size() != 3:
			continue
		var id := int(entry.get("id", 0))
		if id <= 0:
			continue
		var members := {}
		for member in (entry.get("members", []) if entry.get("members") is Array else []):
			members[String(member)] = true
		plots[id] = {"id": id, "realm": String(entry.get("realm", "")), "name": String(entry.get("name", "")),
			"from": Vector3i(int(from[0]), int(from[1]), int(from[2])),
			"to": Vector3i(int(to[0]), int(to[1]), int(to[2])),
			"owner_player": String(entry.get("owner", "")), "owner_company": int(entry.get("company", 0)),
			"members": members, "open": bool(entry.get("open", false))}
		_next_id = maxi(_next_id, id + 1)
