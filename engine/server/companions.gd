extends RefCounted
## What a tamed creature is currently being told to do.
##
## Taming already gave three of the four things a companion needs: it follows, it belongs to somebody,
## and it does not despawn, so it is still there tomorrow. The fourth - **taking instruction** - was one
## boolean, `sitting`, toggled by right-clicking. That is fine for a dog and runs out immediately for
## anything else: a mod wanting "guard the gate" or "carry this home" had nowhere to put it.
##
##     api.register_order("fetch", {"display_name": "Fetch that", "behavior": "my_mod:fetch"})
##     api.order(dog, "fetch")
##
## Three orders are the engine's own, because all three are about *where*, which the engine already
## knows how to do:
##   follow  walk after the owner (what a tamed creature does by default)
##   stay    sit down here and do not move
##   guard   hold this spot, but deal with anything that comes near it
##
## Anything else is a mod's, and maps to a behaviour registered with `register_mob_behavior` - the
## engine sets the order, the behaviour decides what that looks like.
##
## **The order is shown, not toggled.** Right-clicking your own companion opens a panel listing what it
## can be told, the same way talking to a character opens a conversation. A toggle stops working the
## moment there are three things to say, and a child cannot discover what they cannot see.

const KEY := "order"
const FOLLOW := "engine:follow"
const STAY := "engine:stay"
const GUARD := "engine:guard"
## How far from its post a guarding creature will go before coming back.
const GUARD_RANGE := 6.0

var server

## Name -> {name, display_name, behavior, owner}
var kinds := {}
## peer id -> entity id, for whoever has the panel open.
var _open := {}


func _init(game_server) -> void:
	server = game_server
	for built_in in [[FOLLOW, "Follow me"], [STAY, "Stay here"], [GUARD, "Guard this spot"]]:
		kinds[built_in[0]] = {"name": built_in[0], "display_name": built_in[1], "behavior": "", "owner": "engine"}


func register(order_name: String, def: Dictionary, owner := "engine") -> bool:
	if order_name.is_empty() or kinds.has(order_name):
		push_error("Invalid or duplicate order '%s'" % order_name)
		return false
	kinds[order_name] = {"name": order_name, "owner": owner,
		"display_name": String(def.get("display_name", order_name.get_slice(":", 1).capitalize())),
		# The behaviour that carries it out. Empty for the engine's three, which it handles itself.
		"behavior": String(def.get("behavior", ""))}
	return true


## What it is being told to do now. Everything defaults to following, which is what a creature that has
## just been tamed should do without anybody saying so.
func order_of(entity) -> String:
	if entity == null:
		return ""
	var order = entity.data.get(KEY)
	return String(order.get("name", FOLLOW)) if order is Dictionary else FOLLOW


## Where it was told to hold, for guard. Vector3.INF when it has no post.
func post_of(entity) -> Vector3:
	var order = entity.data.get(KEY) if entity != null else null
	if not (order is Dictionary) or not (order.get("at") is Array) or (order.at as Array).size() != 3:
		return Vector3.INF
	return Vector3(float(order.at[0]), float(order.at[1]), float(order.at[2]))


## Tells it something. `options.at` is where, for orders that need a place; it defaults to where the
## creature is standing, which is what "guard this spot" means when somebody says it out loud.
func give(entity, order_name: String, options := {}) -> bool:
	var kind: Dictionary = kinds.get(order_name, {})
	if entity == null or kind.is_empty() or not entity.is_alive():
		return false
	var at = options.get("at", entity.body.position)
	entity.data[KEY] = {"name": order_name, "at": [at.x, at.y, at.z]}
	# `sitting` stays what it always was rather than becoming a second opinion about the same thing:
	# the sit behaviour and its pose are proven, and "stay" is exactly what they already did.
	if order_name == STAY:
		server.entities.taming.set_sitting(entity, true)
	elif bool(entity.data.get("sitting", false)):
		server.entities.taming.set_sitting(entity, false)
	if not String(kind.behavior).is_empty() and entity.brain != null:
		entity.brain.behavior = String(kind.behavior)
	entity.wake()
	server.emit("entity_ordered", {"entity": entity, "order": order_name, "at": at})
	return true


## The orders this creature can be given: the engine's three, plus any a mod registered for its type.
## A mod restricts them by handling `companion_orders`, which is cheaper than a registry of which
## creature may be told what.
func orders_for(entity) -> Array:
	var out := []
	for order_name: String in kinds:
		out.append({"name": order_name, "display_name": String(kinds[order_name].display_name)})
	var ev: Dictionary = server.emit("companion_orders", {"entity": entity, "orders": out})
	return ev.orders if ev.get("orders") is Array else out


## The panel. Drawn by the engine so every companion in every mod is told what to do the same way.
func show(player, entity) -> bool:
	if player == null or entity == null:
		return false
	_open[player.peer_id] = int(entity.id)
	var current := order_of(entity)
	var children: Array = [{"type": "label", "text": String(entity.def.get("display_name", "Companion")), "size": 20}]
	for order in orders_for(entity):
		var name := String(order.name)
		children.append({"type": "button", "text": ("> %s" % order.display_name) if name == current else String(order.display_name),
			"action": "order:%s" % name, "disabled": name == current})
	children.append({"type": "spacer", "size": 6})
	children.append({"type": "button", "text": "Never mind", "action": "close"})
	player.show_ui("engine:orders", {"anchor": "center", "modal": true, "children": children})
	return true


func on_action(player, action: String) -> bool:
	if not action.begins_with("order:"):
		return false
	# The player's own realm: a companion followed you into an instance and then could not be
	# found, because this looked in the overworld. (2026-09-21)
	var entity = server.realm_of(player).entities.entities.get(int(_open.get(player.peer_id, -1)))
	if entity == null:
		return true
	# Checked again here rather than trusting the panel: a stale one, or a crafted action, must not let
	# somebody order a creature that is not theirs.
	if String(entity.data.get("owner", "")) != String(player.player_id):
		return true
	give(entity, action.substr(6), {"at": entity.body.position})
	_open.erase(player.peer_id)
	player.hide_ui("engine:orders")
	return true


func player_left(peer_id: int) -> void:
	_open.erase(peer_id)


# --- The guard behaviour ------------------------------------------------------------------------

## Registered into the AI the way sit and follow-owner are. Guarding is holding a spot: it fights what
## comes to it, and walks back when whatever it was fighting drew it away.
func score(brain) -> float:
	var e = brain.entity
	if order_of(e) != GUARD or not e.is_alive():
		return 0.0
	var post := post_of(e)
	if post == Vector3.INF:
		return 0.0
	# Below the brain's own combat scores, so a guard that is being attacked deals with that first and
	# only then walks home.
	return 0.5 if e.body.position.distance_to(post) > GUARD_RANGE else 0.0


func update(brain, _delta: float) -> void:
	var post := post_of(brain.entity)
	if post != Vector3.INF:
		brain.move_to(post, 1.1, 1.5)
