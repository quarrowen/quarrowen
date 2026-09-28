extends RefCounted
## The hub: a lit floor with a door for each game, and a board beside each one showing the best anybody
## has managed. Where you arrive, where you come back to, and the only place in this game that is saved.
##
## **Built rather than generated.** A hub is eight doors in a ring - a generator would be more code to
## write, more code to read, and would produce a different fairground every time the server restarted,
## which is the opposite of what a place you come home to should do.
##
## **It is the only persistent realm here.** Arenas are instances, thrown away when a round ends; this
## one is an ordinary realm and is saved, because a best-scores board nobody remembers is not a board.

const RADIUS := 14
const FLOOR_Y := 64
## Where a door stands, as an angle round the ring. Eight slots, which is more games than are written
## and fewer than would make the walk boring.
const SLOTS := 8
## Feet on the floor, in the middle, facing the first door.
const SPAWN := Vector3(0.5, 65.0, 0.5)

var api
## slot -> {game, region, position}
var doors := {}

var _ids := {}


func setup(mod_api) -> void:
	api = mod_api
	# `base` owns the nouns and this game owns none of them, so the fairground is built out of what
	# already exists: brick underfoot, sunstone for the lit doorways, sandstone for the wall.
	_ids.floor_block = api.require_block("base:brick")
	_ids.door_block = api.require_block("base:sunstone_block")
	_ids.edge = api.require_block("base:sandstone")
	# A realm of its own rather than a corner of the overworld: the games each want their own rules and
	# the hub wants none of them, and a hub carved out of a survival world is a hub somebody can mine.
	api.add_realm("hub", {"name": "The Fairground"})
	# Nothing grows, nothing spawns, nobody starves, and nobody can hit anybody. A waiting room should
	# be the safest place in the game. This is what per-realm rules were built for.
	api.set_gameplay({"mob_spawning": false, "hunger": false, "fall_damage": false,
		"pvp": false, "keep_inventory": true}, "hub")
	# **Everybody, every time.** The two handlers were split apart precisely so a lobby could say this
	# without also dragging a story's returning players out of their beds.
	api.set_spawn_handler(func(_player, _saved): return SPAWN)
	api.set_rejoin_handler(func(_player, _saved): return SPAWN)


## Lays the floor and puts a door up for each game. Called once the games are known, because the
## number of them decides how many doors there are.
func build(games: Dictionary) -> void:
	_lay_floor()
	var slot := 0
	for game_id: String in games:
		if slot >= SLOTS:
			api.warn("more games than doors; %s has nowhere to stand" % game_id)
			break
		_raise_door(slot, games[game_id])
		slot += 1


func _lay_floor() -> void:
	# `fill` rather than a loop of `set_block`: it is the admin path, with no events, no drops and no
	# edit budget, which is what building a room out of nothing wants.
	api.fill(Vector3i(-RADIUS, FLOOR_Y, -RADIUS), Vector3i(RADIUS, FLOOR_Y, RADIUS), _ids.floor_block, "hub")
	# A low wall, so a child who walks to the edge finds one rather than the void.
	for y in [FLOOR_Y + 1, FLOOR_Y + 2]:
		api.fill(Vector3i(-RADIUS, y, -RADIUS), Vector3i(RADIUS, y, -RADIUS), _ids.edge, "hub")
		api.fill(Vector3i(-RADIUS, y, RADIUS), Vector3i(RADIUS, y, RADIUS), _ids.edge, "hub")
		api.fill(Vector3i(-RADIUS, y, -RADIUS), Vector3i(-RADIUS, y, RADIUS), _ids.edge, "hub")
		api.fill(Vector3i(RADIUS, y, -RADIUS), Vector3i(RADIUS, y, RADIUS), _ids.edge, "hub")


## One door: a lit arch you walk into, and a region that notices.
func _raise_door(slot: int, game: Dictionary) -> void:
	var angle := TAU * float(slot) / float(SLOTS)
	var at := Vector3i(roundi(cos(angle) * (RADIUS - 2)), FLOOR_Y + 1, roundi(sin(angle) * (RADIUS - 2)))
	for y in 3:
		api.set_block(at + Vector3i(0, y, 0), _ids.door_block, "hub")
	# **The region is the door, not the block.** A block you have to click is a block a child has to
	# know to click; walking into the light is the whole instruction.
	var id: int = api.add_region("door_%d" % slot, Vector3(at) + Vector3(-0.6, 0, -0.6),
		Vector3(at) + Vector3(1.6, 3, 1.6), {"realm": "hub", "data": {"game": String(game.id)}})
	doors[slot] = {"game": String(game.id), "region": id, "position": at}
