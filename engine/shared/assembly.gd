extends RefCounted
## Tools and weapons built from parts. Shared by the server (which builds them) and clients (which
## preview them before building).
##
## Material: {display_name, item (the raw material), color, tier, speed, durability, damage,
##            handle (durability multiplier when used as a handle), trait: {name, description,
##            modifiers, durability_mult, speed_mult, damage_add, glow}}
## Part type: {display_name, sprite (asset), cost (material items per part)}
## Assembly: {display_name, item (the tool item the result is), slots: [{name, part, label}],
##            tool_type ("pickaxe", "" for weapons), damage, cooldown, reach, sweep, station}
## The head (first slot) decides tier, mining speed and damage; the handle scales durability; every
## part adds its material's trait once.

var materials := {}  # name -> def
var part_types := {}  # name -> def
var assemblies := {}  # name -> def
var part_items := {}  # part item id -> part type name


func add_material(material_name: String, def: Dictionary) -> void:
	var t: Dictionary = def.get("trait", {}) if def.get("trait") is Dictionary else {}
	materials[material_name] = {"name": material_name, "display_name": str(def.get("display_name", material_name.get_slice(":", 1).capitalize())),
		"item": int(def.get("item", 0)), "color": str(def.get("color", "#ffffff")), "tier": int(def.get("tier", 1)),
		"speed": float(def.get("speed", 2.0)), "durability": int(def.get("durability", 60)), "damage": float(def.get("damage", 0.0)),
		"handle": float(def.get("handle", 1.0)),
		"trait": {"name": str(t.get("name", "")), "description": str(t.get("description", "")),
			"modifiers": t.get("modifiers", []) if t.get("modifiers") is Array else [], "durability_mult": float(t.get("durability_mult", 0.0)),
			"speed_mult": float(t.get("speed_mult", 0.0)), "damage_add": float(t.get("damage_add", 0.0)),
			"glow": t.get("glow", {}) if t.get("glow") is Dictionary else {}}}


func add_part_type(part_name: String, def: Dictionary) -> void:
	part_types[part_name] = {"name": part_name, "display_name": str(def.get("display_name", part_name.get_slice(":", 1).capitalize())),
		"sprite": str(def.get("sprite", "")), "cost": clampi(int(def.get("cost", 1)), 1, 64), "item": int(def.get("item", 0)),
		"station": str(def.get("station", ""))}
	if int(def.get("item", 0)) > 0:
		part_items[int(def.item)] = part_name


func add_assembly(assembly_name: String, def: Dictionary) -> void:
	var slots := []
	for s in (def.get("slots") if def.get("slots") is Array else []):
		if s is Dictionary and part_types.has(str(s.get("part", ""))):
			slots.append({"name": str(s.get("name", "")), "part": str(s.part), "label": str(s.get("label", str(s.get("name", "")).capitalize()))})
	assemblies[assembly_name] = {"name": assembly_name, "display_name": str(def.get("display_name", assembly_name.get_slice(":", 1).capitalize())),
		"item": int(def.get("item", 0)), "slots": slots, "tool_type": str(def.get("tool_type", "")), "damage": float(def.get("damage", 1.0)),
		"cooldown": float(def.get("cooldown", 0.5)), "reach": float(def.get("reach", 4.5)), "sweep": float(def.get("sweep", 0.0)),
		"station": str(def.get("station", ""))}


## Item data for a part made of a material.
func part_data(part_name: String, material_name: String) -> Dictionary:
	var part: Dictionary = part_types.get(part_name, {})
	var m: Dictionary = materials.get(material_name, {})
	if part.is_empty() or m.is_empty():
		return {}
	return {"material": material_name, "name": "%s %s" % [m.display_name, part.display_name],
		"icon_layers": [{"sprite": part.sprite, "color": m.color}]}


## The finished tool's item data from {slot name: material name}, or {} if something is invalid.
func build(assembly_name: String, chosen: Dictionary) -> Dictionary:
	var a: Dictionary = assemblies.get(assembly_name, {})
	if a.is_empty() or a.slots.is_empty():
		return {}
	var mats := []
	for s in a.slots:
		var m: Dictionary = materials.get(str(chosen.get(s.name, "")), {})
		if m.is_empty():
			return {}
		mats.append(m)
	var head: Dictionary = mats[0]
	var handle: Dictionary = mats[1] if mats.size() > 1 else head
	var traits := {}
	for m in mats:
		if not m.trait.name.is_empty():
			traits[m.trait.name] = m.trait
	var speed_mult := 1.0
	var durability_mult: float = handle.handle
	var damage: float = a.damage + head.damage
	var modifiers := []
	var glow := {}
	for t in traits.values():
		speed_mult += t.speed_mult
		durability_mult *= 1.0 + t.durability_mult
		damage += t.damage_add
		modifiers.append_array(t.modifiers)
		if not t.glow.is_empty():
			glow = t.glow
	var data := {
		"name": "%s %s" % [head.display_name, a.display_name],
		"parts": chosen.duplicate(),
		"durability": maxi(1, roundi(head.durability * durability_mult)),
		"weapon": {"damage": snappedf(damage, 0.1), "cooldown": a.cooldown, "reach": a.reach, "sweep": a.sweep},
		"modifiers": modifiers,
		"icon_layers": [],
		"lore": [],
	}
	if not a.tool_type.is_empty():
		data.tool = {"type": a.tool_type, "tier": head.tier, "speed": snappedf(head.speed * speed_mult, 0.1)}
	if not glow.is_empty():
		data.glow = glow
	# Handle first so the head draws on top, then the rest.
	var order := range(a.slots.size())
	if order.size() > 1:
		order = [1, 0] + order.slice(2)
	for i in order:
		data.icon_layers.append({"sprite": part_types[a.slots[i].part].sprite, "color": mats[i].color})
	var names := PackedStringArray()
	for i in a.slots.size():
		names.append("%s: %s" % [a.slots[i].label, mats[i].display_name])
	data.lore.append(" · ".join(names))
	for t in traits.values():
		data.lore.append("%s: %s" % [t.name, t.description])
	return data


func to_network() -> Dictionary:
	return {"materials": materials, "part_types": part_types, "assemblies": assemblies}


func load_network(data) -> void:
	if not (data is Dictionary):
		return
	for key in (data.get("materials") if data.get("materials") is Dictionary else {}):
		add_material(str(key), data.materials[key])
	for key in (data.get("part_types") if data.get("part_types") is Dictionary else {}):
		add_part_type(str(key), data.part_types[key])
	for key in (data.get("assemblies") if data.get("assemblies") is Dictionary else {}):
		add_assembly(str(key), data.assemblies[key])
