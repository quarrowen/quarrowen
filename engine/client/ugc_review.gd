extends Control
## Review panel for player creations (admins): lists pending, reported, approved, rejected and removed
## creations with a preview (the skin image, or the accessory or model on an avatar), who made it,
## reports and their reasons, and actions: approve, reject with a reason, remove for good, clear reports,
## trust or untrust the creator, ban or unban them.

signal action_requested(action: String, args: Dictionary)
signal fetch_requested(ids: Array)
signal closed

const Avatar = preload("res://engine/client/avatar/avatar.gd")
const Creations = preload("res://engine/shared/creations.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")

const FILTERS := [["pending", "Waiting"], ["reported", "Reported"], ["approved", "Approved"], ["rejected", "Rejected"], ["removed", "Removed"], ["all", "All"]]

var cosmetics
var looks
var images := {}  # the client's asset images (skins)
var rig: Dictionary
var items: Array = []
var filter := "pending"
var selected_id := ""

var _list: ItemList
var _detail: VBoxContainer
var _filter_buttons := {}
var _search: LineEdit
var _preview_texture: TextureRect
var _preview_view: SubViewportContainer
var _preview: Avatar
var _pivot: Node3D
var _info: RichTextLabel
var _reason: LineEdit
var _buttons: HFlowContainer
var _empty: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.11, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Review player creations"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	for f in FILTERS:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.pressed.connect(set_filter.bind(f[0]))
		bar.add_child(b)
		_filter_buttons[f[0]] = b
	_search = LineEdit.new()
	_search.placeholder_text = "Search name or creator"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): refresh())
	bar.add_child(_search)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(380, 0)
	_list.item_selected.connect(func(i): select(items[i].id))
	body.add_child(_list)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	body.add_child(_detail)
	var preview_row := HBoxContainer.new()
	preview_row.custom_minimum_size = Vector2(0, 300)
	_detail.add_child(preview_row)
	_preview_texture = TextureRect.new()
	_preview_texture.custom_minimum_size = Vector2(288, 288)
	_preview_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_row.add_child(_preview_texture)
	_preview_view = SubViewportContainer.new()
	_preview_view.stretch = true
	_preview_view.custom_minimum_size = Vector2(300, 300)
	_preview_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(_preview_view)
	_preview_view.add_child(_build_preview())
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.selection_enabled = true
	_detail.add_child(_info)
	_reason = LineEdit.new()
	_reason.placeholder_text = "Reason (shown to the creator when rejecting or removing)"
	_detail.add_child(_reason)
	_buttons = HFlowContainer.new()
	_detail.add_child(_buttons)
	_empty = Label.new()
	_empty.text = "Nothing here."
	_empty.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	_detail.add_child(_empty)
	set_filter("pending")


func _build_preview() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.2, 0.27)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.environment.ambient_light_energy = 0.8
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.position = Vector3(0, 1.2, 4.0)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.0, 0))
	_pivot = Node3D.new()
	_pivot.rotation.y = PI + 0.5
	viewport.add_child(_pivot)
	_preview = Avatar.new()
	_pivot.add_child(_preview)
	_preview.build(rig)
	return viewport


func _process(delta: float) -> void:
	if _preview != null and visible:
		_preview.animate(delta, Vector3.ZERO, true, 0.0)
		_pivot.rotation.y += delta * 0.4


func set_filter(f: String) -> void:
	filter = f
	for key in _filter_buttons:
		_filter_buttons[key].button_pressed = key == f
	refresh()


func refresh() -> void:
	action_requested.emit("list", {"filter": filter, "text": _search.text if _search != null else ""})


func receive(list: Array, policy: Dictionary) -> void:
	if policy.get("denied", false):
		items = []
		_list.clear()
		_empty.text = "Only admins can review creations on this server."
		_show_detail({})
		return
	items = list
	_list.clear()
	for item in items:
		var reports: int = item.get("reports", []).size()
		var index := _list.add_item("%s  ·  %s  ·  %s%s" % [item.manifest.name, item.manifest.author_name, item.manifest.kind,
			"  ⚑%d" % reports if reports > 0 else ""])
		if reports > 0:
			_list.set_item_custom_fg_color(index, Color(1.0, 0.7, 0.5))
	_empty.text = "Nothing here." if items.is_empty() else ""
	var still := items.filter(func(i): return i.id == selected_id)
	_show_detail(still[0] if not still.is_empty() else (items[0] if not items.is_empty() else {}))


func select(id: String) -> void:
	var found := items.filter(func(i): return i.id == id)
	_show_detail(found[0] if not found.is_empty() else {})


## A creation's files arrived: draw its preview if it is the one on show.
func creation_ready(id: String) -> void:
	if id == selected_id:
		select(id)


func _show_detail(item: Dictionary) -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	selected_id = str(item.get("id", ""))
	_info.visible = not item.is_empty()
	_reason.visible = not item.is_empty()
	_preview_texture.visible = false
	_preview_view.visible = false
	if item.is_empty():
		return
	var m: Dictionary = item.manifest
	var reports: Array = item.get("reports", [])
	var text := "[b]%s[/b]  (%s in %s)\n" % [m.name, m.kind, m.category]
	text += "By [b]%s[/b]%s%s · %d KB · uploaded %s\n" % [m.author_name, "  [color=#8fd88f]trusted[/color]" if item.get("author_trusted", false) else "",
		"  [color=#ff8a70]banned[/color]" if item.get("author_banned", false) else "", int(item.get("size", 0)) / 1024,
		Time.get_datetime_string_from_unix_time(int(item.get("uploaded_at", 0))).replace("T", " ")]
	text += "Status: [b]%s[/b]%s\n" % [item.status, " — " + str(item.reason) if not str(item.get("reason", "")).is_empty() else ""]
	text += "[color=#888]%s[/color]\n" % item.id
	if not reports.is_empty():
		text += "\n[b]Reports (%d)[/b]\n" % reports.size()
		for r in reports:
			text += "• %s: %s%s\n" % [r.get("name", "?"), r.get("reason", ""), " — " + str(r.details) if not str(r.get("details", "")).is_empty() else ""]
	_info.text = text
	# Preview.
	if cosmetics.get_def(selected_id).is_empty():
		fetch_requested.emit([selected_id])
	elif m.kind == "skin" and images.has(Creations.asset_name(m)):
		_preview_texture.texture = ImageTexture.create_from_image(images[Creations.asset_name(m)])
		_preview_texture.visible = true
		_apply_preview(m)
	else:
		_apply_preview(m)
	# Actions.
	var id: String = item.id
	if item.status != "approved":
		_action("Approve", func(): _set_status(id, "approved"))
	if item.status in ["approved", "pending"]:
		_action("Reject", func(): _set_status(id, "rejected"))
	if item.status != "removed":
		_action("Remove for good", func(): _set_status(id, "removed"))
	if not reports.is_empty():
		_action("Clear reports", func(): action_requested.emit("clear_reports", {"id": id, "filter": filter}))
	var trusted: bool = item.get("author_trusted", false)
	_action("Untrust creator" if trusted else "Trust creator", func(): action_requested.emit("trust", {"player_id": item.uploaded_by, "on": not trusted, "filter": filter}))
	var banned: bool = item.get("author_banned", false)
	_action("Unban creator" if banned else "Ban creator", func(): action_requested.emit("ban", {"player_id": item.uploaded_by, "on": not banned,
		"reason": _reason.text, "filter": filter}))


func _apply_preview(m: Dictionary) -> void:
	_preview_view.visible = true
	var look := Cosmetics.default_avatar("Preview")
	look.wear[m.category] = {"id": m.id, "color": m.get("color", "#ffffff")}
	looks.apply(_preview, look, "Preview")


func _set_status(id: String, status: String) -> void:
	action_requested.emit("set_status", {"id": id, "status": status, "reason": _reason.text, "filter": filter})
	_reason.text = ""


func _action(text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(callback)
	_buttons.add_child(b)
