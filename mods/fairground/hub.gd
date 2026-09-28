extends RefCounted
## The hub: a lit floor with a door for each game, and a board beside each one showing the best anybody
## has managed. Where you arrive, where you come back to, and the only place in this game that is saved.
##
## **Built rather than generated.** A hub is eight doors in a ring - a generator would be more code to
## write, more code to read, and would produce a different fairground every time the server restarted,
## which is the opposite of what a place you come home to should do.
##
## **The hub is the ordinary world, not a realm of its own**, and that is a correction rather than a
## simplification. It was a realm at first, entered with `send_to_realm` during `player_join` - which
## works, and which starts a *second* full world stream on top of the one the join is already sending.
## The client's UDP buffer overflows, the chunks are dropped, and the player stands in an empty sky
## with a fully built hub in a world they are never shown. The log said `Buffer full, dropping
## packets!` and nothing else did. (2026-09-28)
##
## A separate realm bought nothing anyway: this game generates no world of its own, so there is nothing
## for the hub to be separate *from*. Arenas are still instances, thrown away when a round ends.

const RADIUS := 14
const FLOOR_Y := 64
## Where a door stands, as an angle round the ring. Eight slots, which is more games than are written
## and fewer than would make the walk boring.
const SLOTS := 8
## Feet on the floor, in the middle, facing the first door.
const SPAWN := Vector3(0.5, 65.0, 0.5)
## The hub is the ordinary world, so everything below writes to realm "".
const REALM := ""

var api
var boards
## slot -> {game, region, position}
var doors := {}

var _ids := {}


func setup(mod_api, board_keeper) -> void:
	api = mod_api
	boards = board_keeper
	# `base` owns the nouns and this game owns none of them, so the fairground is built out of what
	# already exists: brick underfoot, sunstone for the lit doorways, sandstone for the wall.
	_ids.floor_block = api.require_block("base:brick")
	_ids.door_block = api.require_block("base:sunstone_block")
	_ids.edge = api.require_block("base:sandstone")
	# Nothing but sky; the hub below is the only thing in it. Arenas generate nothing either - they are
	# built by whichever game owns the round.
	api.set_world_generator(VoidGenerator.new())
	# **Everybody, every time.** The two handlers were split apart precisely so a lobby could say this
	# without also dragging a story's returning players out of their beds.
	# **A spawn handler answers *where*, not *which world*** - and that is the whole trap. Returning the
	# hub's coordinates put the player at those coordinates in the *overworld*, which this game never
	# generates, so the first thing anybody saw was themselves falling through fog. The realm is a field
	# on the player and the handler is handed the player, so it is set here before the position is
	# returned and `ensure_area_loaded` then loads the right world. (found by looking, 2026-09-28)
	#
	# The two handlers take different arguments, which is easy to get the wrong way round: the first-time
	# one is handed only the player, the returning one also where they logged out so it may leave them
	# there. A lobby answers both the same way, which is what the split was written for.
	# **Everybody, every time.** The two handlers were split apart precisely so a lobby could say this
	# without also dragging a story's returning players out of their beds. They take different
	# arguments, which is easy to get the wrong way round: the first-time one is handed only the player,
	# the returning one also where they logged out so it may leave them there.
	api.set_spawn_handler(func(_player): return SPAWN)
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
	api.fill(Vector3i(-RADIUS, FLOOR_Y, -RADIUS), Vector3i(RADIUS, FLOOR_Y, RADIUS), _ids.floor_block, REALM)
	# A low wall, so a child who walks to the edge finds one rather than the void.
	for y in [FLOOR_Y + 1, FLOOR_Y + 2]:
		api.fill(Vector3i(-RADIUS, y, -RADIUS), Vector3i(RADIUS, y, -RADIUS), _ids.edge, REALM)
		api.fill(Vector3i(-RADIUS, y, RADIUS), Vector3i(RADIUS, y, RADIUS), _ids.edge, REALM)
		api.fill(Vector3i(-RADIUS, y, -RADIUS), Vector3i(-RADIUS, y, RADIUS), _ids.edge, REALM)
		api.fill(Vector3i(RADIUS, y, -RADIUS), Vector3i(RADIUS, y, RADIUS), _ids.edge, REALM)


## One door: a lit arch you walk into, and a region that notices.
func _raise_door(slot: int, game: Dictionary) -> void:
	var angle := TAU * float(slot) / float(SLOTS)
	var at := Vector3i(roundi(cos(angle) * (RADIUS - 2)), FLOOR_Y + 1, roundi(sin(angle) * (RADIUS - 2)))
	for y in 3:
		api.set_block(at + Vector3i(0, y, 0), _ids.door_block, REALM)
	# **The region is the door, not the block.** A block you have to click is a block a child has to
	# know to click; walking into the light is the whole instruction.
	var id: int = api.add_region("door_%d" % slot, Vector3(at) + Vector3(-0.6, 0, -0.6),
		Vector3(at) + Vector3(1.6, 3, 1.6), {"realm": REALM, "data": {"game": String(game.id)}})
	doors[slot] = {"game": String(game.id), "region": id, "position": at}
	# The board goes up with the door rather than in a second pass, so a door can never exist without one.
	boards.raise(slot, game, at, angle)


class VoidGenerator:
	func generate(_chunk) -> void:
		pass  # sky, and the hub that `build` lays into it
