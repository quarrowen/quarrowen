extends RefCounted
## Small client-side visuals for items: tooltips, wear bars, the block crack overlay and HUD icons.
## Everything is drawn from item definitions and item data the server sent.

const STAGES := 10
const TILE := 16

static var _crack_textures: Array[ImageTexture] = []
static var _crack_material: StandardMaterial3D


## Tooltip text: name (item data "name" overrides), stats from the definition, durability, then lore
## from the definition and from item data ("lore": [...]).
static func tooltip_lines(items, id: int, item_data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(String(item_data.get("name", items.display_name(id))))
	var def: Dictionary = items.get_def(id)
	var weapon: Dictionary = items.weapon_of(id, item_data)
	if not weapon.is_empty():
		lines.append("%s attack damage" % _number(weapon.damage))
		lines.append("%.2f s attack cooldown" % float(weapon.cooldown))
	var tool: Dictionary = items.tool_of(id, item_data)
	if not tool.is_empty():
		lines.append("%s, tier %d, speed %s" % [String(tool.type).capitalize(), int(tool.tier), _number(tool.speed)])
	var armor: Dictionary = def.get("armor", {})
	if not armor.is_empty():
		lines.append("+%s armor%s" % [_number(armor.armor), ", +%s toughness" % _number(armor.toughness) if float(armor.toughness) > 0.0 else ""])
	for list in [def.get("modifiers", []), item_data.get("modifiers", [])]:
		for m in (list if list is Array else []):
			if m is Dictionary and m.get("stat") is String:
				var amount := float(m.get("amount", 0.0))
				var text := ("%+d%%" % roundi(amount * 100.0)) if m.get("op") == "multiply" else ("%+s" % _number(amount))
				lines.append("%s %s" % [text, String(m.stat).replace("_", " ")])
	var food: Dictionary = def.get("food", {})
	if not food.is_empty():
		lines.append("Restores %s hunger (hold use to eat)" % _number(food.hunger))
	var teaches = item_data.get("teaches", def.get("teaches", []))
	if teaches is Array and not teaches.is_empty():
		lines.append("Blueprint: right-click to learn %d recipe%s" % [teaches.size(), "" if teaches.size() == 1 else "s"])
	var durability: int = items.max_durability(id, item_data)
	if durability > 0:
		lines.append("Durability %d / %d" % [durability - int(item_data.get("damage", 0)), durability])
	for list in [def.get("lore", []), item_data.get("lore", [])]:
		for line in (list if list is Array else []):
			lines.append(String(line).left(120))
	return lines


static func _number(value) -> String:
	var f := float(value)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


## Adds or updates a thin bar along the bottom of an item slot showing remaining durability.
static func update_wear_bar(slot: Control, items, id: int, item_data: Dictionary) -> void:
	var bar: ColorRect = slot.get_node_or_null("Wear")
	var durability: int = items.max_durability(id, item_data) if id > 0 else 0
	var damage := int(item_data.get("damage", 0))
	if durability <= 0 or damage <= 0:
		if bar:
			bar.visible = false
		return
	if bar == null:
		bar = ColorRect.new()
		bar.name = "Wear"
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bar)
	var left := clampf(1.0 - float(damage) / durability, 0.0, 1.0)
	bar.visible = true
	bar.color = Color(1.0, 0.25, 0.2).lerp(Color(0.3, 0.95, 0.35), left)
	var width := slot.custom_minimum_size.x - 10.0
	bar.position = Vector2(5, slot.custom_minimum_size.y - 7)
	bar.size = Vector2(maxf(width * left, 1.0), 3)


static func crack_node() -> MeshInstance3D:
	if _crack_textures.is_empty():
		_build_crack_textures()
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.006
	node.mesh = box
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _crack_material.duplicate()
	set_crack_stage(node, 0)
	return node


static func set_crack_stage(node: MeshInstance3D, stage: int) -> void:
	var material := node.material_override as StandardMaterial3D
	var texture := _crack_textures[clampi(stage, 0, STAGES - 1)]
	if material.albedo_texture != texture:
		material.albedo_texture = texture


## Ten crack images of increasing damage, drawn once: random walks from a few seeds.
static func _build_crack_textures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var walkers: Array[Vector2i] = []
	for stage in STAGES:
		for i in 2:
			walkers.append(Vector2i(rng.randi_range(2, 13), rng.randi_range(2, 13)))
		for w in walkers.size():
			for step in 3 + stage:
				var p := walkers[w]
				img.set_pixel(p.x, p.y, Color(0.05, 0.04, 0.03, 0.85))
				p += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
				walkers[w] = Vector2i(clampi(p.x, 0, TILE - 1), clampi(p.y, 0, TILE - 1))
		_crack_textures.append(ImageTexture.create_from_image(img.duplicate()))
	_crack_material = StandardMaterial3D.new()
	_crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_crack_material.uv1_scale = Vector3(3, 2, 1)  # BoxMesh lays its six faces out 3x2


## 9x9 shield: `fill` 1 = full, 0.5 = left half, 0 = empty outline.
static func shield_icon(fill: float) -> ImageTexture:
	var rows := ["111111111", "111111111", "111111111", "111111111", "011111110", "011111110", "001111100", "000111000"]
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in 9:
			if rows[y][x] != "1":
				continue
			var lit := fill >= 1.0 or (fill > 0.0 and x < 5)
			img.set_pixel(x, y, Color(0.82, 0.84, 0.9) if lit else Color(0.15, 0.16, 0.2, 0.85))
	return ImageTexture.create_from_image(img)
