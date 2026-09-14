extends RefCounted
## Computes a player's stats from base values, equipped items, the held item, per-item modifiers in
## item data and timed modifiers. Mods can then adjust the result in the `player_stats` event.
##
## Modifiers are {stat, amount, op: "add" | "multiply"}: all adds are summed first, then multipliers
## (1 + amount each) are applied, so {"stat": "attack_damage", "amount": 0.25, "op": "multiply"} is +25%.

const Inventory = preload("res://engine/shared/inventory.gd")

## Damage causes armor protects against.
const ARMOR_CAUSES := ["attack", "mob", "projectile", "explosion", "contact"]


static func compute(p, items) -> Dictionary:
	var stats: Dictionary = items.stats.duplicate()
	var adds := {}
	var multiplies := {}
	var inv = p.inventory
	for i in inv.equipment_slots.size():
		var index: int = Inventory.SIZE + i
		var id: int = inv.ids[index]
		if id <= 0 or inv.counts[index] <= 0:
			continue
		var def: Dictionary = items.get_def(id)
		var slot_name: String = inv.equipment_slots[i]
		var worn := slot_name != "offhand" or String(def.get("equip_slot", "")) == "offhand"
		if not worn:
			continue
		var armor: Dictionary = def.get("armor", {})
		for key in ["armor", "toughness", "knockback_resistance"]:
			if armor.has(key):
				adds[key] = float(adds.get(key, 0.0)) + float(armor[key])
		_collect(def.get("modifiers", []), adds, multiplies)
		_collect(inv.data[index].get("modifiers", []), adds, multiplies)
	var held: int = inv.selected_item()
	if held > 0:
		var def: Dictionary = items.get_def(held)
		var weapon: Dictionary = items.weapon_of(held, inv.data[inv.selected])
		if not weapon.is_empty():
			stats.attack_damage = float(weapon.damage)
			stats.attack_cooldown = float(weapon.cooldown)
			stats.reach = float(weapon.reach)
			adds.crit_chance = float(adds.get("crit_chance", 0.0)) + float(weapon.crit_chance)
			multiplies.knockback = float(multiplies.get("knockback", 1.0)) * float(weapon.knockback)
		if String(def.get("equip_slot", "")).is_empty():
			_collect(def.get("modifiers", []), adds, multiplies)
		_collect(inv.data[inv.selected].get("modifiers", []), adds, multiplies)
	var now: float = p._server._time
	for id in p.modifiers.keys():
		var m: Dictionary = p.modifiers[id]
		if m.expires > 0.0 and now >= m.expires:
			p.modifiers.erase(id)
			continue
		_collect([m], adds, multiplies)
	for key in adds:
		stats[key] = float(stats.get(key, 0.0)) + float(adds[key])
	for key in multiplies:
		stats[key] = float(stats.get(key, 0.0)) * float(multiplies[key])
	stats.knockback_resistance = clampf(stats.knockback_resistance, 0.0, 1.0)
	stats.max_health = maxf(stats.max_health, 1.0)
	stats.attack_cooldown = maxf(stats.attack_cooldown, 0.05)
	stats.reach = clampf(stats.reach, 1.0, 12.0)
	stats.move_speed = clampf(stats.move_speed, 0.0, 5.0)
	return stats


static func _collect(modifiers, adds: Dictionary, multiplies: Dictionary) -> void:
	if not (modifiers is Array):
		return
	for m in modifiers:
		if not (m is Dictionary) or not (m.get("stat") is String):
			continue
		var amount := float(m.get("amount", 0.0))
		if m.get("op") == "multiply":
			multiplies[m.stat] = float(multiplies.get(m.stat, 1.0)) * (1.0 + amount)
		else:
			adds[m.stat] = float(adds.get(m.stat, 0.0)) + amount


## Damage left after armor: armor points absorb up to 80% of a hit, less against big hits unless
## toughness is high (the same curve players know from Minecraft).
static func apply_armor(amount: float, armor: float, toughness: float) -> float:
	if armor <= 0.0:
		return amount
	var effective := clampf(maxf(armor / 5.0, armor - amount / (2.0 + toughness / 4.0)), 0.0, 20.0)
	return amount * (1.0 - effective / 25.0)
