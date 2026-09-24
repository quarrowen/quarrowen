extends Node
## A server that puts an Illuminance chestplate on whoever joins, so the light can be photographed.
##
##   QW_PORT=24640 godot --headless --path . res://tools/illum_server.tscn
##
## Test scaffolding, the same shape as `ending_server.gd`: a mark is applied by a mod or a command
## nobody has written yet, so without this a screenshot of worn armour lighting the ground would mean
## building the whole enchanting flow first.

const ServerMain = preload("res://engine/server_main.gd")


func _ready() -> void:
	var main := ServerMain.new()
	main.name = "ServerMain"
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	var server = main.get_node_or_null("GameServer")
	if server == null:
		print("[illum] no server")
		return
	while server.players.is_empty():
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(2.0).timeout
	var chest: int = server.items.id_of("simple_gear:iron_chestplate")
	var level := int(OS.get_environment("QW_ILLUM_LEVEL")) if not OS.get_environment("QW_ILLUM_LEVEL").is_empty() else 3
	for p in server.players.values():
		var data: Dictionary = server.modifiers.apply({}, "simple_gear:iron_chestplate",
			"simple_gear:illuminance", level)
		var slot: int = p.inventory.equipment_index("chest")
		p.inventory.set_slot(slot, chest, 1, data)
		p.sync_inventory()
		server.refresh_appearance(p)
		print("[illum] dressed %s: %s" % [p.name, str(data.get("glow", {}))])
	await get_tree().create_timer(1.0).timeout
	print("[illum] appearance now: %s" % str(server.players.values()[0].appearance.get("armor_glow", {})))
