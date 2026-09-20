extends RefCounted
## Groups of players that things can belong to: a guild, a town, a crew, a family.
##
## **Deliberately separate from plots**, though a plot is the obvious thing for one to own. Plenty of
## servers want groups without land - a trading company, a team - and plenty want land without groups,
## where a plot simply belongs to whoever made it. Tying the two together would have meant every
## server that wanted one taking the other.
##
## The engine keeps who is in what and what rank they hold. What a rank *means* is the mod's: whether
## an officer may invite, whether a member may build on the company's land, whether there are dues.
## The engine has one opinion only, and it is about safety: **the last owner cannot leave or be
## demoted**, because a company nobody owns is one nobody can wind up, and its property becomes
## unreachable.

const SAVE_KEY := "companies"
const MAX_MEMBERS := 128
## Ranks, from least to most. A mod may call them what it likes; the engine only needs an order so it
## can say whether one person outranks another.
const RANKS := ["member", "officer", "owner"]

var server

## id -> {id, name, members: {player_id: rank}, data}
var companies := {}
var _next_id := 1


func _init(game_server) -> void:
	server = game_server


func create(company_name: String, founder_id: String) -> int:
	if company_name.strip_edges().is_empty() or founder_id.is_empty():
		return 0
	var id := _next_id
	_next_id += 1
	companies[id] = {"id": id, "name": company_name.strip_edges().left(48),
		"members": {founder_id: "owner"}, "data": {}}
	server.emit("company_founded", {"company": id, "name": company_name, "founder": founder_id})
	return id


func disband(id: int) -> bool:
	var company: Dictionary = companies.get(id, {})
	if company.is_empty():
		return false
	companies.erase(id)
	server.emit("company_disbanded", {"company": id, "name": company.name})
	return true


func rank_of(id: int, player_id: String) -> String:
	return String(companies.get(id, {}).get("members", {}).get(player_id, ""))


func is_member(id: int, player_id: String) -> bool:
	return not rank_of(id, player_id).is_empty()


## Whether this person is at least this rank.
func at_least(id: int, player_id: String, rank: String) -> bool:
	var theirs := RANKS.find(rank_of(id, player_id))
	var wanted := RANKS.find(rank)
	return theirs >= 0 and wanted >= 0 and theirs >= wanted


func set_rank(id: int, player_id: String, rank: String) -> bool:
	var company: Dictionary = companies.get(id, {})
	if company.is_empty() or not RANKS.has(rank) or player_id.is_empty():
		return false
	if company.members.size() >= MAX_MEMBERS and not company.members.has(player_id):
		return false
	# The last owner may not be demoted. A company nobody owns cannot be wound up and everything it
	# holds becomes unreachable, which is a worse outcome than refusing.
	if rank_of(id, player_id) == "owner" and rank != "owner" and _owners(company) <= 1:
		return false
	company.members[player_id] = rank
	server.emit("company_rank", {"company": id, "player_id": player_id, "rank": rank})
	return true


func remove(id: int, player_id: String) -> bool:
	var company: Dictionary = companies.get(id, {})
	if company.is_empty() or not company.members.has(player_id):
		return false
	if rank_of(id, player_id) == "owner" and _owners(company) <= 1:
		return false  # see set_rank
	company.members.erase(player_id)
	server.emit("company_left", {"company": id, "player_id": player_id})
	return true


func _owners(company: Dictionary) -> int:
	var count := 0
	for member_id in company.members:
		if String(company.members[member_id]) == "owner":
			count += 1
	return count


## Every company someone is in: [{id, name, rank}].
func of_player(player_id: String) -> Array:
	var out := []
	for id: int in companies:
		var rank := rank_of(id, player_id)
		if not rank.is_empty():
			out.append({"id": id, "name": String(companies[id].name), "rank": rank})
	return out


func info(id: int) -> Dictionary:
	var company: Dictionary = companies.get(id, {})
	return {} if company.is_empty() else {"id": id, "name": String(company.name),
		"members": (company.members as Dictionary).duplicate(), "data": (company.data as Dictionary).duplicate(true)}


func to_saved() -> Array:
	var out := []
	for id: int in companies:
		var company: Dictionary = companies[id]
		out.append({"id": id, "name": company.name, "members": company.members, "data": company.data})
	return out


func load_saved(list) -> void:
	companies.clear()
	_next_id = 1
	if not (list is Array):
		return
	for entry in list:
		if not (entry is Dictionary) or not (entry.get("members") is Dictionary):
			continue
		var id := int(entry.get("id", 0))
		if id <= 0:
			continue
		companies[id] = {"id": id, "name": String(entry.get("name", "")),
			"members": entry.members, "data": entry.get("data", {}) if entry.get("data") is Dictionary else {}}
		_next_id = maxi(_next_id, id + 1)
