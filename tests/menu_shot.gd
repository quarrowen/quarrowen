extends Node
## Photographs the main menu, which nothing else could look at without a person sitting at the machine.
##
##   godot --path . res://tests/menu_shot.tscn -- --out=/tmp/menu.png [--page=settings] [--tab=Account]
##
## Pages are `MainMenu.PAGES`: play, multiplayer, create, mods, settings.
##
## `tests/screenshot.gd` covers the game and the in-game overlays, and its `--settings` opens the
## *pause* settings, which is a different screen from the menu's. So the menu's own pages - the account
## page, the server list, hosting - were the one part of the interface that could only be checked by
## launching the game and clicking, which is exactly the check that does not get done. (2026-09-25)
##
## Needs a real window, like the other shot tool: an offscreen viewport renders nothing.

const MainMenu = preload("res://engine/client/menu/main_menu.gd")
const SocialClient = preload("res://engine/client/social/social_client.gd")

## Long enough for the fonts, the theme and the backdrop to settle. The menu does no terrain work, so
## this is about the first frames rather than about loading.
const SETTLE_FRAMES := 30


func _ready() -> void:
	var options := {"out": "user://menu.png", "page": "", "tab": ""}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and options.has(kv[0]):
			options[kv[0]] = kv[1]

	var menu := MainMenu.new()
	# The friends panel connects to the social client's signals as it is built, so the menu cannot be
	# constructed without one - `engine/main.gd` sets it before adding the menu and so must this. It never
	# signs in here: `NetAccess` keeps a test run off the network, so it sits in its "not signed in" state,
	# which is the state the account page should be photographed in anyway.
	menu.social = SocialClient.new()
	add_child(menu.social)
	add_child(menu)
	await get_tree().process_frame
	if not String(options.page).is_empty():
		menu.show_page(String(options.page))
	await get_tree().process_frame
	# The tab is found by asking for the method rather than by walking a known path, the way
	# screenshot.gd finds the pause settings: the menu's layout changes and a path would rot silently
	# into a shot of the wrong page.
	if not String(options.tab).is_empty():
		var tabbed := menu.find_children("*", "", true, false).filter(func(n): return n.has_method("show_tab"))
		if tabbed.is_empty():
			printerr("[menu_shot] nothing on this screen has tabs")
		else:
			tabbed[0].show_tab(String(options.tab))
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(String(options.out))
	print("[menu_shot] %s %s" % ["wrote" if err == OK else "FAILED to write", ProjectSettings.globalize_path(String(options.out))])
	get_tree().quit(0 if err == OK else 1)
