extends RefCounted
## Player-made content ("creations"): the shared format, checks and ids used by the editors, the local
## library, uploads and servers.
##
## A creation is a small manifest plus one payload:
##   {id, kind, name, category, author, author_name, created, color, tint, model_transform}
##   kind "skin":      payload = a 64x64 PNG in the skin layout (base and overlay layers), worn in the
##                     "skin" category under everything else
##   kind "accessory": payload = JSON {boxes: [{from [x,y,z], size [w,h,d], color, shade}]} in skin
##                     pixels at the category's attachment point (hat, hair, glasses, back, face)
##   kind "model":     payload = a GLB accessory (checked: size, triangles, textures) with a transform
## The id is "ugc:" + the first 24 hex digits of SHA-256 over the kind, category and payload, so the
## same content always has the same id (servers can block a removed creation for good) and names or
## colors can change without making a new creation.
## `to_cosmetic` turns a creation into a cosmetic definition (engine/shared/cosmetics.gd) whose texture
## or model asset is named after the id.

const Cosmetics = preload("res://engine/shared/cosmetics.gd")

const PREFIX := "ugc:"
const KINDS := ["skin", "accessory", "model"]
const SKIN_SIZE := 64
const MAX_NAME := 40
const MAX_BOXES := 64
const MAX_BOX_EXTENT := 24.0  # skin pixels from the attachment point
const MAX_SKIN_BYTES := 64 * 1024
const MAX_ACCESSORY_BYTES := 16 * 1024
const MAX_MODEL_BYTES := 512 * 1024
const MAX_MODEL_TRIANGLES := 4000
const MAX_MODEL_TEXTURE := 256
## Categories each kind may go in.
const ACCESSORY_CATEGORIES := ["hat", "hair", "glasses", "back", "face"]


## The id for a creation's content.
static func content_id(kind: String, category: String, payload: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%s|%s|" % [kind, category]).to_utf8_buffer())
	ctx.update(payload)
	return PREFIX + ctx.finish().hex_encode().left(24)


static func is_id(text: String) -> bool:
	return text.begins_with(PREFIX) and text.length() == PREFIX.length() + 24 and text.substr(PREFIX.length()).is_valid_hex_number()


## Builds a manifest for new content (the id comes from the payload).
static func make(kind: String, category: String, payload: PackedByteArray, name: String, author := "", author_name := "", extra := {}) -> Dictionary:
	var m := {"kind": kind, "category": category, "name": name.strip_edges().left(MAX_NAME), "author": author, "author_name": author_name.left(32),
		"created": int(Time.get_unix_time_from_system()), "color": str(extra.get("color", "#ffffff")), "tint": bool(extra.get("tint", false))}
	if kind == "model":
		m.model_transform = extra.get("model_transform", {"position": [0, 0, 0], "rotation": [0, 0, 0], "scale": 1.0})
	m.id = content_id(kind, category, payload)
	return m


## Checks a manifest and its payload. Returns {ok, error, manifest (cleaned), info} where info carries
## what was measured (triangles, texture sizes, box count).
static func validate(manifest, payload: PackedByteArray) -> Dictionary:
	if not (manifest is Dictionary):
		return _fail("not a creation")
	var kind := str(manifest.get("kind", ""))
	if not kind in KINDS:
		return _fail("unknown kind '%s'" % kind)
	var category := str(manifest.get("category", ""))
	match kind:
		"skin":
			category = "skin"
		_:
			if not category in ACCESSORY_CATEGORIES:
				return _fail("an %s goes in one of %s" % [kind, ", ".join(ACCESSORY_CATEGORIES)])
	var name := str(manifest.get("name", "")).strip_edges().left(MAX_NAME)
	if name.is_empty():
		return _fail("give it a name")
	var info := {}
	match kind:
		"skin":
			if payload.size() > MAX_SKIN_BYTES:
				return _fail("the skin file is too large (%d KB, at most %d KB)" % [payload.size() / 1024, MAX_SKIN_BYTES / 1024])
			var img := Image.new()
			if payload.size() < 8 or img.load_png_from_buffer(payload) != OK:
				return _fail("the skin is not a PNG image")
			if img.get_width() != SKIN_SIZE or img.get_height() != SKIN_SIZE:
				return _fail("a skin must be %dx%d pixels (this one is %dx%d)" % [SKIN_SIZE, SKIN_SIZE, img.get_width(), img.get_height()])
		"accessory":
			if payload.size() > MAX_ACCESSORY_BYTES:
				return _fail("the accessory data is too large")
			var data = JSON.parse_string(payload.get_string_from_utf8())
			if not (data is Dictionary) or not (data.get("boxes") is Array):
				return _fail("the accessory data is not readable")
			if data.boxes.is_empty():
				return _fail("an accessory needs at least one box")
			if data.boxes.size() > MAX_BOXES:
				return _fail("an accessory may have at most %d boxes (this one has %d)" % [MAX_BOXES, data.boxes.size()])
			for b in data.boxes:
				if not (b is Dictionary) or not _vec_ok(b.get("from"), -MAX_BOX_EXTENT, MAX_BOX_EXTENT) or not _vec_ok(b.get("size"), 0.25, MAX_BOX_EXTENT) \
						or not Cosmetics.is_color(b.get("color", "#ffffff")):
					return _fail("a box is outside the allowed %d-pixel space or has a bad color" % int(MAX_BOX_EXTENT))
			info.boxes = data.boxes.size()
		"model":
			if payload.size() > MAX_MODEL_BYTES:
				return _fail("the model is too large (%d KB, at most %d KB)" % [payload.size() / 1024, MAX_MODEL_BYTES / 1024])
			var measured := measure_model(payload)
			if measured.has("error"):
				return _fail(measured.error)
			if measured.triangles > MAX_MODEL_TRIANGLES:
				return _fail("the model has %d triangles (at most %d)" % [measured.triangles, MAX_MODEL_TRIANGLES])
			if measured.max_texture > MAX_MODEL_TEXTURE:
				return _fail("a model texture is %d pixels (at most %d)" % [measured.max_texture, MAX_MODEL_TEXTURE])
			info = measured
	var expected := content_id(kind, category, payload)
	if str(manifest.get("id", expected)) != expected:
		return _fail("the id does not match the content")
	var clean := {"id": expected, "kind": kind, "category": category, "name": name, "author": str(manifest.get("author", "")).left(64),
		"author_name": str(manifest.get("author_name", "")).left(32), "created": int(manifest.get("created", 0)),
		"color": Cosmetics.clean_color(manifest.get("color"), "#ffffff"), "tint": bool(manifest.get("tint", false))}
	if kind == "model":
		clean.model_transform = Cosmetics._transform(manifest.get("model_transform"))
	return {"ok": true, "error": "", "manifest": clean, "info": info}


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "manifest": {}, "info": {}}


static func _vec_ok(v, lo: float, hi: float) -> bool:
	if not (v is Array) or v.size() != 3:
		return false
	for x in v:
		if not (x is float or x is int) or float(x) < lo or float(x) > hi:
			return false
	return true


## Triangles and the largest texture in a GLB, or {error}.
static func measure_model(bytes: PackedByteArray) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "glTF" or doc.append_from_buffer(bytes, "", state) != OK:
		return {"error": "the model is not a GLB (binary glTF) file"}
	var triangles := 0
	for m in state.get_meshes():
		var importer: ImporterMesh = m.mesh
		for s in importer.get_surface_count():
			var arrays := importer.get_surface_arrays(s)
			var indices = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if indices is PackedInt32Array and not indices.is_empty() else verts.size()) / 3
	var max_texture := 0
	for img in state.get_images():
		if img is Texture2D:
			max_texture = maxi(max_texture, maxi(img.get_width(), img.get_height()))
	if triangles == 0:
		return {"error": "the model has no triangles"}
	return {"triangles": triangles, "max_texture": max_texture}


## The cosmetic definition that draws a creation. `asset` is the texture or model asset name clients load
## (by default the id itself).
static func to_cosmetic(manifest: Dictionary, payload: PackedByteArray) -> Dictionary:
	var d := {"name": manifest.id, "category": manifest.category, "display_name": manifest.name, "color": manifest.get("color", "#ffffff"),
		"tint": manifest.get("tint", false), "description": "Made by %s" % manifest.author_name if not str(manifest.get("author_name", "")).is_empty() else "",
		"unlocked": true}
	match manifest.kind:
		"skin":
			d.texture = asset_name(manifest)
		"accessory":
			var data = JSON.parse_string(payload.get_string_from_utf8())
			d.boxes = data.get("boxes", []) if data is Dictionary else []
		"model":
			d.model = asset_name(manifest)
			d.model_transform = manifest.get("model_transform", {})
	return d


static func asset_name(manifest: Dictionary) -> String:
	return "%s.%s" % [manifest.id, "png" if manifest.kind == "skin" else ("glb" if manifest.kind == "model" else "json")]


static func payload_extension(kind: String) -> String:
	return {"skin": "png", "accessory": "json", "model": "glb"}.get(kind, "bin")
