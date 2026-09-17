extends RefCounted
## Items you hold down to use: a bow drawn back, a sling wound up, a spell gathered before it is thrown.
##
## An item opts in with `charge`, and the engine turns holding and letting go into one event carrying how
## far it got:
##
##     api.register_item("bow", {"usable": true, "charge": {"seconds": 1.0, "minimum": 0.25}})
##     api.on("item_released", func(ev): if ev.item == bow: _shoot(ev.player, ev.charge))
##
## `charge` is 0..1 - how much of `seconds` was held - so a mod decides what a half-drawn bow means
## rather than the engine deciding for it. Releasing below `minimum` fires nothing at all, which is what
## stops a misclick costing an arrow.
##
## Why this is in the engine rather than in a mod: the client already tells the server when use starts and
## when it stops (eating needs both), but nothing except food could claim that hold. Every mod wanting a
## drawn weapon would otherwise have invented its own timing out of item_use plus a timer, and none of
## them would have agreed about what happens when the player switches slots halfway through.
##
## Fields: {seconds (default 1.0), minimum (default 0.0, the fraction below which release does nothing),
##   sound (played as the charge starts), cancel_on_switch (default true)}
##
## Events: item_charge {player, item, cancelled} as it starts (cancel it to refuse the draw),
##   item_released {player, item, slot, charge (0..1), seconds, direction}

const PlayerPhysics = preload("res://engine/shared/player_physics.gd")

var _server


func _init(game_server) -> void:
	_server = game_server


## Whether this item is held rather than clicked.
func config_of(item: int) -> Dictionary:
	if item <= 0:
		return {}
	var charge = _server.items.get_def(item).get("charge", {})
	return charge if charge is Dictionary else {}


## Begins a draw. Returns false when the item is not a charging one or a mod refused it.
func start(p, item: int) -> bool:
	var charge := config_of(item)
	if charge.is_empty() or p.dead:
		return false
	if _server.emit("item_charge", {"player": p, "item": item, "cancelled": false}).cancelled:
		return false
	p.charging = {"slot": p.inventory.selected, "item": item, "started": _server._time}
	var sound := str(charge.get("sound", ""))
	if not sound.is_empty():
		_server.play_sound_at(sound, p.get_eye_position(), 0.8)
	_server.broadcast_player_event(p, _server.Entities.Event.DRAW)
	return true


## Let go. Fires item_released when it was held long enough, and tells everyone the draw is over either way.
func release(p) -> void:
	if p.charging.is_empty():
		return
	var held: Dictionary = p.charging
	p.charging = {}
	_server.broadcast_player_event(p, _server.Entities.Event.RELEASE)
	var charge := config_of(int(held.item))
	var seconds: float = maxf(0.05, float(charge.get("seconds", 1.0)))
	var held_for: float = _server._time - float(held.started)
	var fraction: float = clampf(held_for / seconds, 0.0, 1.0)
	if fraction < float(charge.get("minimum", 0.0)):
		return
	_server.emit("item_released", {"player": p, "item": int(held.item), "slot": int(held.slot),
		"charge": fraction, "seconds": held_for, "direction": PlayerPhysics.look_direction(p.yaw, p.pitch)})


## Drops the draw without firing: the item left their hand, or they died holding it.
func cancel(p) -> void:
	if p.charging.is_empty():
		return
	p.charging = {}
	_server.broadcast_player_event(p, _server.Entities.Event.RELEASE)


## Called every tick: a draw belongs to the item that started it, so swapping slots or losing the item
## lets it go rather than leaving a player drawing something they are no longer holding.
func update(p) -> void:
	if p.charging.is_empty():
		return
	var slot: int = p.charging.slot
	if not bool(config_of(int(p.charging.item)).get("cancel_on_switch", true)):
		return
	if p.dead or p.inventory.selected != slot or p.inventory.ids[slot] != int(p.charging.item) \
			or p.inventory.counts[slot] <= 0:
		cancel(p)
