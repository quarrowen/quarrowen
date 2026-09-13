extends SceneTree
## Paints the placeholder 16x16 block textures used by the bundled mods and writes them as PNGs.
##   godot --headless --path . -s tools/generate_textures.gd

const TILE := 16

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1337
	var stone := Color(0.49, 0.49, 0.51)
	var dirt := Color(0.47, 0.32, 0.2)
	var grass := Color(0.38, 0.64, 0.25)
	var snow := Color(0.95, 0.97, 1.0)
	var base := "res://mods/base/textures/"

	_save(_noise(stone, 0.07), base + "stone.png")
	_save(_noise(dirt, 0.07), base + "dirt.png")
	_save(_noise(grass, 0.09), base + "grass_top.png")
	_save(_cap(_noise(dirt, 0.07), grass, 3), base + "grass_side.png")
	_save(_noise(Color(0.87, 0.82, 0.58), 0.04), base + "sand.png")
	_save(_log_side(), base + "log_side.png")
	_save(_log_top(), base + "log_top.png")
	_save(_leaves(), base + "leaves.png")
	_save(_planks(), base + "planks.png")
	_save(_cobblestone(), base + "cobblestone.png")
	_save(_noise(Color(0.22, 0.42, 0.86, 0.72), 0.03), base + "water.png")
	_save(_noise(Color(0.28, 0.28, 0.28), 0.18), base + "bedrock.png")
	_save(_glass(), base + "glass.png")
	_save(_ore(stone, Color(0.12, 0.12, 0.12)), base + "coal_ore.png")
	_save(_ore(stone, Color(0.85, 0.68, 0.52)), base + "iron_ore.png")
	_save(_noise(snow, 0.03), base + "snow.png")
	_save(_cap(_noise(dirt, 0.07), snow, 4), base + "snow_side.png")
	_save(_brick(), base + "brick.png")
	_save(_noise(Color(0.52, 0.49, 0.47), 0.16), base + "gravel.png")

	_save(_generator(), "res://mods/skyblock/textures/generator.png")

	var industry := "res://mods/industry/textures/"
	_save(_cable(), industry + "cable.png")
	_save(_icon(Color(0.35, 0.35, 0.38), Color(1.0, 0.55, 0.15), "flame"), industry + "coal_generator_icon.png")
	_save(_icon(Color(0.2, 0.25, 0.45), Color(0.45, 0.75, 1.0), "grid"), industry + "solar_panel_icon.png")
	_save(_icon(Color(0.25, 0.28, 0.25), Color(0.4, 0.95, 0.4), "bars"), industry + "battery_icon.png")
	_save(_icon(Color(0.3, 0.3, 0.3), Color(1.0, 0.85, 0.3), "bulb"), industry + "lamp_icon.png")
	_save(_icon(Color(0.45, 0.4, 0.2), Color(0.85, 0.85, 0.9), "drill"), industry + "miner_icon.png")

	_save(_item(Color(0.1, 0.1, 0.12), "lump"), base + "coal.png")
	var arcana := "res://mods/arcana/textures/"
	_save(_ore(stone, Color(0.75, 0.4, 1.0)), arcana + "mana_crystal_ore.png")
	_save(_item(Color(0.72, 0.42, 1.0), "shard"), arcana + "mana_shard.png")
	_save(_item(Color(0.45, 0.8, 1.0), "wand"), arcana + "wand_of_blink.png")
	_save(_item(Color(1.0, 0.85, 0.35), "wand"), arcana + "wand_of_light.png")
	_save(_icon(Color(0.3, 0.3, 0.36), Color(0.75, 0.45, 1.0), "bulb"), arcana + "mana_pylon_icon.png")
	var orb := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 7.5, y - 7.5).length()
			orb.set_pixel(x, y, Color(1.0, 0.95, 0.7, 1.0) if d < 3.0 else Color(0, 0, 0, 0))
	_save(orb, arcana + "light_orb.png")

	var guild := "res://mods/guild/textures/"
	_save(_item(Color(1.0, 0.8, 0.25), "coin"), guild + "gold_coin.png")
	_save(_ore(stone, Color(1.0, 0.82, 0.3)), guild + "gold_ore.png")
	_save(_meteorite(true), guild + "meteorite.png")
	_save(_meteorite(false), guild + "meteorite_cooled.png")
	_save(_icon(Color(0.45, 0.32, 0.2), Color(0.95, 0.85, 0.6), "grid"), guild + "quest_board_icon.png")

	# Gameplay items (appended last so the random sequence for earlier textures is unchanged).
	_save(_item(Color(0.62, 0.45, 0.25), "sword"), base + "wooden_sword.png")
	_save(_item(Color(0.6, 0.6, 0.63), "sword"), base + "stone_sword.png")
	_save(_item(Color(0.85, 0.15, 0.15), "apple"), base + "apple.png")
	var vanilla := "res://mods/vanilla/textures/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vanilla))
	_save(_item(Color(0.95, 0.55, 0.55), "meat"), vanilla + "porkchop.png")
	_save(_item(Color(0.35, 0.9, 1.0), "wand"), arcana + "wand_of_sparks.png")
	var spark := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 7.5, y - 7.5)
			var star := minf(absf(d.x), absf(d.y)) < 1.0 and d.length() < 7.0
			if d.length() < 3.0 or star:
				spark.set_pixel(x, y, Color(0.75, 0.95, 1.0) if d.length() < 2.0 else Color(0.35, 0.8, 1.0, 0.9))
	_save(spark, arcana + "spark.png")
	quit()


func _meteorite(hot: bool) -> Image:
	var img := _noise(Color(0.2, 0.18, 0.2), 0.06)
	for i in 5:
		var x := rng.randi_range(0, 15)
		var y := rng.randi_range(0, 15)
		for n in 10:
			x = clampi(x + rng.randi_range(-1, 1), 0, 15)
			y = clampi(y + rng.randi_range(-1, 1), 0, 15)
			img.set_pixel(x, y, _vary(Color(1.0, 0.55, 0.15) if hot else Color(0.35, 0.3, 0.32), 0.08))
	return img


## Transparent-background item sprites.
func _item(color: Color, glyph: String) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var on := false
			match glyph:
				"lump": on = Vector2(x - 7.5, (y - 8.0) * 1.2).length() < 5.0 and rng.randf() > 0.08
				"shard": on = absf(x - 7.5) + absf(y - 7.5) * 0.45 < 3.2
				"wand": on = absi(x - (15 - y)) <= 0 and y > 3 or (Vector2(x - 11.5, y - 3.5).length() < 2.0)
				"coin": on = Vector2(x - 7.5, y - 7.5).length() < 5.5 and not (Vector2(x - 7.5, y - 7.5).length() < 3.5 and x == 7)
				"sword": on = (absi(x - (15 - y)) <= 1 and y < 11) or (absi(x - y) <= 0 and y > 8 and y < 13) or (x < 4 and y > 11)
				"apple": on = Vector2(x - 7.5, y - 9.0).length() < 5.0 or (x == 8 and y > 2 and y < 5)
				"meat": on = Vector2((x - 7.0) * 0.8, y - 8.0).length() < 5.0 or (x > 10 and absi(y - 12) <= 1)
			if on:
				var c := color if glyph != "wand" or y > 5 else color.lightened(0.4)
				if glyph == "wand" and y > 5:
					c = Color(0.45, 0.3, 0.18)
				if glyph == "sword" and y > 9:
					c = Color(0.4, 0.26, 0.14)  # hilt
				if glyph == "apple" and y < 5:
					c = Color(0.4, 0.26, 0.14)
				if glyph == "meat" and x > 10 and absi(y - 12) <= 1:
					c = Color(0.95, 0.92, 0.85)  # bone
				img.set_pixel(x, y, _vary(c, 0.06))
	return img


func _cable() -> Image:
	var img := _noise(Color(0.22, 0.22, 0.24), 0.03)
	for i in TILE:
		for w in range(6, 10):
			img.set_pixel(i, w, _vary(Color(0.78, 0.45, 0.2), 0.05))
			img.set_pixel(w, i, _vary(Color(0.78, 0.45, 0.2), 0.05))
	return img


## Simple item-style icons for model blocks (shown in the hotbar).
func _icon(frame: Color, accent: Color, glyph: String) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var edge := x < 2 or y < 2 or x > 13 or y > 13
			img.set_pixel(x, y, frame.darkened(0.3) if edge else _vary(frame, 0.04))
	for y in range(3, 13):
		for x in range(3, 13):
			var on := false
			match glyph:
				"flame": on = absf(x - 7.5) < (y - 3) * 0.45 and y > 4
				"grid": on = x % 3 == 0 or y % 3 == 0
				"bars": on = (x in [4, 5, 7, 8, 10, 11]) and y > 12 - (x / 3) * 2
				"bulb": on = Vector2(x - 7.5, y - 6.5).length() < 3.5 or (x in [7, 8] and y > 9)
				"drill": on = absf(x - 7.5) < (12 - y) * 0.35 or (y < 5 and x > 3 and x < 12)
			if on:
				img.set_pixel(x, y, _vary(accent, 0.06))
	return img


func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("%s %s" % ["wrote" if err == OK else "FAILED", path])


func _blank() -> Image:
	return Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)


func _vary(c: Color, amount: float) -> Color:
	var v := rng.randf_range(-amount, amount)
	return Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v, 0, 1), c.a)


func _noise(base: Color, amount: float) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _vary(base, amount))
	return img


## Colored top rows with a ragged edge (grass / snow sides).
func _cap(img: Image, color: Color, rows: int) -> Image:
	for x in TILE:
		for y in rows + rng.randi_range(0, 2):
			img.set_pixel(x, y, _vary(color, 0.06))
	return img


func _log_side() -> Image:
	var img := _blank()
	var bark := Color(0.4, 0.29, 0.16)
	for x in TILE:
		for y in TILE:
			img.set_pixel(x, y, _vary(bark.darkened(0.07 if x % 4 == 1 else 0.0), 0.04))
	return img


func _log_top() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			var ring := int(Vector2(x - 7.5, y - 7.5).length()) % 2 == 0
			var c := Color(0.4, 0.29, 0.16) if edge else (Color(0.62, 0.48, 0.3) if ring else Color(0.7, 0.56, 0.36))
			img.set_pixel(x, y, _vary(c, 0.03))
	return img


func _leaves() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, Color(0, 0, 0, 0) if rng.randf() < 0.18 else _vary(Color(0.24, 0.52, 0.18), 0.1))
	return img


func _planks() -> Image:
	var img := _blank()
	var wood := Color(0.68, 0.52, 0.32)
	for y in TILE:
		for x in TILE:
			var seam := y % 4 == 3 or x == (4 if (y / 4) % 2 == 0 else 12)
			img.set_pixel(x, y, wood.darkened(0.35) if seam else _vary(wood, 0.04))
	return img


func _cobblestone() -> Image:
	var img := _blank()
	var points: Array[Vector2] = []
	var shades: Array[float] = []
	for i in 9:
		points.append(Vector2(rng.randf() * TILE, rng.randf() * TILE))
		shades.append(rng.randf_range(0.42, 0.6))
	for y in TILE:
		for x in TILE:
			var best := 1e9
			var second := 1e9
			var shade := 0.5
			for i in points.size():
				# Wrapped distances keep the tile seamless.
				var d := Vector2(x, y) - points[i]
				d = Vector2(minf(absf(d.x), TILE - absf(d.x)), minf(absf(d.y), TILE - absf(d.y)))
				var dist := d.length()
				if dist < best:
					second = best
					best = dist
					shade = shades[i]
				elif dist < second:
					second = dist
			var c := Color(0.3, 0.3, 0.3) if second - best < 1.2 else Color(shade, shade, shade + 0.02)
			img.set_pixel(x, y, _vary(c, 0.03))
	return img


func _glass() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			var streak := (x == y + 3 or x == y + 4) and x > 3 and x < 9
			img.set_pixel(x, y, Color(0.82, 0.9, 0.95) if edge or streak else Color(0, 0, 0, 0))
	return img


func _ore(stone: Color, ore: Color) -> Image:
	var img := _noise(stone, 0.07)
	for i in 5:
		var cx := rng.randi_range(2, 13)
		var cy := rng.randi_range(2, 13)
		for n in 4:
			img.set_pixel(clampi(cx + rng.randi_range(-1, 1), 0, 15), clampi(cy + rng.randi_range(-1, 1), 0, 15), _vary(ore, 0.06))
	return img


func _brick() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var mortar := y % 4 == 3 or (x + (4 if (y / 4) % 2 == 1 else 0)) % 8 == 7
			img.set_pixel(x, y, Color(0.72, 0.7, 0.66) if mortar else _vary(Color(0.62, 0.27, 0.2), 0.05))
	return img


func _generator() -> Image:
	var img := _noise(Color(0.3, 0.3, 0.33), 0.05)
	for y in TILE:
		for x in TILE:
			if x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1:
				img.set_pixel(x, y, Color(0.15, 0.15, 0.17))
			elif x >= 3 and x <= 12 and y >= 3 and y <= 12:
				var hot := x < 8
				var c := Color(0.95, 0.5, 0.15) if hot else Color(0.25, 0.5, 0.95)
				img.set_pixel(x, y, _vary(c, 0.1))
	return img
