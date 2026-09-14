extends RefCounted
## Hunger and food. Every survival player has hunger (0-20, shown as ten drumsticks) and hidden
## saturation (0-hunger), which is used up before hunger. Activity adds exhaustion; every 4 points
## of exhaustion cost 1 saturation, or 1 hunger once saturation is empty.
##
## - Natural regeneration needs hunger 18+ (faster while saturated at full hunger) and each point of
##   health healed adds exhaustion.
## - At hunger 6 or less you cannot sprint.
## - At hunger 0 you take starvation damage down to the `starvation_min_health` rule (0 = can starve).
## - Food items (`food` in the item definition) are eaten by holding use for `eat_time` seconds.
##
## Stats: `exhaustion` multiplies exhaustion gained; `hunger_drain` adds exhaustion per second (food
## poisoning). The `hunger` gameplay rule turns all of this off; creative players never get hungry.

const MAX := 20.0
const EXHAUSTION_PER_POINT := 4.0
const REGEN_MIN_HUNGER := 18.0
const SPRINT_MIN_HUNGER := 6.0
const STARVE_INTERVAL := 4.0
const SATURATED_REGEN_INTERVAL := 1.0
const HEAL_EXHAUSTION := 6.0
## Exhaustion per action.
const SPRINT_PER_METER := 0.1
const SWIM_PER_METER := 0.01
const JUMP := 0.05
const SPRINT_JUMP := 0.2
const BREAK_BLOCK := 0.005
const ATTACK := 0.1
const DAMAGED := 0.1
const EAT_SOUND_INTERVAL := 0.4  # one munch per chomp of the animation
const GULP_SOUND_INTERVAL := 0.45


var _server


func _init(game_server) -> void:
	_server = game_server


func enabled(p) -> bool:
	return bool(_server.gameplay.get("hunger", true)) and not p.inventory.creative


func add_exhaustion(p, amount: float) -> void:
	if amount <= 0.0 or not enabled(p) or p.dead:
		return
	p.exhaustion += amount * maxf(float(p.get_stats().get("exhaustion", 1.0)), 0.0)
	while p.exhaustion >= EXHAUSTION_PER_POINT:
		p.exhaustion -= EXHAUSTION_PER_POINT
		if p.saturation > 0.0:
			p.saturation = maxf(p.saturation - 1.0, 0.0)
		else:
			set_hunger(p, p.hunger - 1.0)
	sync(p)


func set_hunger(p, value: float, saturation := -1.0) -> void:
	var before: float = p.hunger
	p.hunger = clampf(value, 0.0, MAX)
	if saturation >= 0.0:
		p.saturation = saturation
	p.saturation = clampf(p.saturation, 0.0, p.hunger)
	if (before > SPRINT_MIN_HUNGER) != (p.hunger > SPRINT_MIN_HUNGER):
		_update_sprint(p)
	sync(p)


func _update_sprint(p) -> void:
	if p.hunger <= SPRINT_MIN_HUNGER and enabled(p):
		if not p.modifiers.has("engine:hunger"):
			p.add_modifier("engine:hunger", "sprint", -1.0, "multiply")
	elif p.modifiers.has("engine:hunger"):
		p.remove_modifier("engine:hunger")


## Sends hunger when it changes (-1 while the `hunger` rule is off, which hides the bar).
func sync(p, force := false) -> void:
	var on := bool(_server.gameplay.get("hunger", true))
	var shown := Vector2(p.hunger if on else -1.0, snappedf(p.saturation, 0.1))
	if (force or shown != p._sent_hunger) and p._online():
		p._sent_hunger = shown
		Net.s_hunger.rpc_id(p.peer_id, shown.x, shown.y)


## Each tick: movement exhaustion, hunger drain, regeneration, starvation and eating.
## `moved`: how far the player's inputs moved them this tick, over `move_time` seconds of simulation.
func update(p, delta: float, moved: Vector3, move_time: float, was_on_ground: bool) -> void:
	if p.dead:
		stop_eating(p)
		return
	_update_eating(p)
	if not enabled(p):
		if p.modifiers.has("engine:hunger"):
			p.remove_modifier("engine:hunger")
		sync(p)
		return
	if p.hunger <= SPRINT_MIN_HUNGER and not p.modifiers.has("engine:hunger"):
		_update_sprint(p)  # back in survival while starving
	var flat := Vector2(moved.x, moved.z).length()
	var feet: int = _server.world.get_block(floori(p.state.position.x), floori(p.state.position.y + 0.2), floori(p.state.position.z))
	var gained := 0.0
	if _server.registry.liquid_lut[feet] == 1:
		gained += flat * SWIM_PER_METER
	var sprinting: bool = move_time > 0.0 and flat > _server.rules.walk_speed * move_time * 1.15
	if sprinting and _server.registry.liquid_lut[feet] != 1:
		gained += flat * SPRINT_PER_METER
	if was_on_ground and not p.state.on_ground and p.state.velocity.y > 0.0:
		gained += SPRINT_JUMP if sprinting else JUMP
	gained += maxf(float(p.get_stats().get("hunger_drain", 0.0)), 0.0) * delta
	if gained > 0.0:
		add_exhaustion(p, gained)
	# Starvation.
	if p.hunger <= 0.0:
		p.starve_timer += delta
		if p.starve_timer >= STARVE_INTERVAL:
			p.starve_timer = 0.0
			var floor_health := maxf(float(_server.gameplay.get("starvation_min_health", 1.0)), 0.0)
			if p.health > floor_health:
				_server.damage_player(p, minf(1.0, p.health - floor_health) if floor_health > 0.0 else 1.0, "starvation", null, Vector3.ZERO, true, 0.0)
	else:
		p.starve_timer = 0.0


## Whether natural regeneration may heal now, and how often: 0 = not at all.
func regen_interval(p, normal_interval: float) -> float:
	if not enabled(p):
		return normal_interval
	if p.hunger >= MAX and p.saturation > 0.0:
		return SATURATED_REGEN_INTERVAL
	return normal_interval if p.hunger >= REGEN_MIN_HUNGER else 0.0


func healed(p, amount: float) -> void:
	add_exhaustion(p, HEAL_EXHAUSTION * amount)


# --- Eating ---------------------------------------------------------------------------------------

## Starts eating the held food. Returns false (with a reason shown) if it cannot be eaten now.
func start_eating(p) -> bool:
	if p.dead:
		return false
	var item: int = p.inventory.selected_item()
	var food: Dictionary = _server.items.get_def(item).get("food", {}) if item > 0 else {}
	if food.is_empty():
		return false
	if enabled(p) and p.hunger >= MAX and not food.get("always", false):
		p.show_title("", "You are not hungry", 1.0)
		return false
	p.eating = {"slot": p.inventory.selected, "item": item, "started": _server._time, "sound": _server._time}
	_broadcast(p, item)
	return true


func stop_eating(p) -> void:
	if not p.eating.is_empty():
		p.eating = {}
		_broadcast(p, 0)


## Tells every client who is eating what (0 = stopped), for the eating animation.
func _broadcast(p, item: int) -> void:
	for other in _server.players.values():
		if other._online():
			Net.s_player_eating.rpc_id(other.peer_id, p.peer_id, item)


func _update_eating(p) -> void:
	if p.eating.is_empty():
		return
	var slot: int = p.eating.slot
	if p.inventory.selected != slot or p.inventory.ids[slot] != int(p.eating.item) or p.inventory.counts[slot] <= 0:
		stop_eating(p)
		return
	var food: Dictionary = _server.items.get_def(int(p.eating.item)).get("food", {})
	var now: float = _server._time
	var drink: bool = food.get("style", "plate") == "drink"
	if now - float(p.eating.sound) >= (GULP_SOUND_INTERVAL if drink else EAT_SOUND_INTERVAL):
		p.eating.sound = now
		var sound := str(food.get("sound", ""))
		_server.play_sound_at(sound if not sound.is_empty() else ("engine:gulp" if drink else "engine:munch"), p.get_eye_position(), 0.8, randf_range(0.85, 1.15))
	if now - float(p.eating.started) >= float(food.get("eat_time", 1.2)):
		stop_eating(p)
		finish_eating(p, slot)


## Eats one item from a slot right away (also used by mods and tests).
func finish_eating(p, slot: int) -> bool:
	var item: int = p.inventory.ids[slot]
	var item_data: Dictionary = p.inventory.data[slot]
	var food: Dictionary = _server.items.get_def(item).get("food", {}) if item > 0 else {}
	if food.is_empty() or p.inventory.counts[slot] <= 0:
		return false
	# Crafting quality makes food more filling.
	var bonus := 0.1 * clampi(int(item_data.get("quality", 0)), 0, 3)
	var ev: Dictionary = _server.emit("player_eat", {"player": p, "item": item, "hunger": float(food.hunger) * (1.0 + bonus),
		"saturation": float(food.saturation) * (1.0 + bonus), "heal": float(food.get("heal", 0.0)), "effects": food.get("effects", []), "cancelled": false})
	if ev.cancelled:
		return false
	if not p.inventory.creative:
		p.inventory.counts[slot] -= 1
		if p.inventory.counts[slot] <= 0:
			p.inventory.clear_slot(slot)
		var remainder := str(food.get("remainder", ""))
		if not remainder.is_empty() and _server.items.id_of(remainder) > 0:
			var left: int = p.inventory.add(_server.items.id_of(remainder), 1)
			if left > 0:
				p.drop(_server.items.id_of(remainder), left)
		p.sync_inventory()
	var gained: float = float(ev.hunger)
	set_hunger(p, p.hunger + gained, minf(p.saturation + float(ev.saturation), p.hunger + gained))
	if float(ev.heal) > 0.0:
		_server.heal_player(p, float(ev.heal))
	var n := 0
	for e in (ev.effects if ev.effects is Array else []):
		n += 1
		if e is Dictionary and randf() < float(e.get("chance", 1.0)):
			p.add_modifier("food:%s:%d" % [str(_server.items.get_def(item).get("name", item)), n], str(e.get("stat", "")),
				float(e.get("amount", 0.0)), str(e.get("op", "add")), float(e.get("seconds", 30.0)))
			if not str(e.get("message", "")).is_empty():
				p.show_title("", str(e.message), 1.5)
	if food.get("style", "plate") != "drink":
		_server.play_sound_at("engine:burp", p.get_eye_position(), 0.7, randf_range(0.9, 1.1))
	return true
