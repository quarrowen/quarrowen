extends "res://engine/server/mod.gd"
## The Fairground: a hub with a door to each game, and a round that begins when you walk through one.
##
## **This registers no blocks and no items.** It is a *game* in the sense the other three are - rules
## over `base`'s nouns - and the rules here are about rounds rather than about survival. If this file
## ever needs a block of its own, the line has moved.
##
## **The games are other mods.** The Fairground raises `fairground:games` at setup and every mod that
## has one appends it; the round loop then asks that mod how the round is going, every second, in the
## payload of `fairground:round_tick`. Nothing here knows what any game *is* - it knows a timer, who is
## in, and who is out. See `protocol.gd`, which is the contract.
##
## That arrangement is only possible because of `api.emit`, added the same day: until then a mod could
## listen to the engine and never to another mod, so a registry like this would have had to be an
## engine capability - which would have meant the engine learning what a contest was.
##
## **Every game must be worth playing alone** (the user, 28 September 2026: "usually solo, sometimes
## together"). So a round of one is a normal round, scoring is the default ending, and the hub's boards
## are personal bests rather than a ladder. A game that only works as a crowd is a game these children
## would rarely get to play.

const Hub = preload("res://mods/fairground/hub.gd")
const Rounds = preload("res://mods/fairground/rounds.gd")
const Boards = preload("res://mods/fairground/boards.gd")

## Kept as members: a RefCounted nobody holds is freed the moment setup returns, taking its handlers
## with it, silently (CLAUDE.md).
var hub := Hub.new()
var rounds := Rounds.new()
var boards := Boards.new()


func setup(api) -> void:
	_rules(api)
	boards.setup(api)
	hub.setup(api, boards)
	rounds.setup(api, hub, boards)
	# The hub is built by the roll call rather than here, because how many doors there are depends on
	# how many games answered - and nothing can answer until every mod has finished loading.
	_doors(api)


## What kind of game this is. Almost everything is off: the Fairground is a place you pass through on
## the way to a round, and a hub where you can starve is a hub that has misunderstood itself.
func _rules(api) -> void:
	api.set_server_info({"name": "The Fairground", "motd": "Pick a door."})
	api.set_gameplay({"hunger": false, "natural_regeneration": true, "mob_spawning": false,
		"pvp": false, "keep_inventory": true, "fall_damage": false, "tutorials": false})


## Walking into a door starts a round. **A region rather than a block you click**, because a block you
## have to know to click is an instruction a seven-year-old has to be told; walking into the light is
## the whole of it.
func _doors(api) -> void:
	api.on("region_entered", func(ev):
		var game_id := String(ev.data.get("game", ""))
		if game_id.is_empty():
			return
		# Already in a round: a door inside an arena is not a thing, but a player who leaves one and
		# walks straight back through the same door should not open a second.
		if not api.instance_of(ev.player).is_empty():
			return
		rounds.begin(game_id, [ev.player]))
