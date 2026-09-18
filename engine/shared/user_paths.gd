extends RefCounted
## Where the client keeps its things, and how a test run keeps out of the player's folder.
##
## `user://` is not a private sandbox here: `project.godot` sets `use_custom_user_dir`, so a Godot run
## from this checkout writes to exactly the same place the installed app does. That is right for the
## game and wrong for the tests, which used to overwrite the player's identity and settings, and after
## those were fixed one at a time went on quietly filling their asset cache, their unpacked-mod cache
## and their log folder, and resetting their pinned recipe.
##
## Fixing it a path at a time is what let it come back, so this is the one place to ask. `QW_USER_DIR`
## moves everything underneath it; tools/run_tests.sh sets it, and nothing else should.
##
## Deliberately *not* routed through here: worlds, creations and identity, which already have their own
## overrides (`QW_DATA_DIR`, `QW_SETTINGS`, `QW_IDENTITY_DIR`) and are named separately because losing
## one of those is a different kind of bad from losing a cache.

const ENV := "QW_USER_DIR"


## `relative` is what would have followed `user://`, e.g. "cache/assets" or "crafting_pins.cfg".
static func path(relative: String) -> String:
	var override := OS.get_environment(ENV)
	if override.is_empty():
		return "user://".path_join(relative)
	DirAccess.make_dir_recursive_absolute(override)
	return override.path_join(relative)


## Whether this process has been moved out of the player's folder. Tests assert on it, because the whole
## point is that it is true while they run and false while somebody is playing.
static func redirected() -> bool:
	return not OS.get_environment(ENV).is_empty()
