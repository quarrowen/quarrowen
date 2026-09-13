extends RefCounted
## Access to the optional Rust extension (native/). Every native feature has a GDScript fallback, so
## the engine runs without the library; set VOXEL_NATIVE=0 to force the fallbacks for comparison.

static var _enabled := -1


static func enabled() -> bool:
	if _enabled == -1:
		_enabled = 1 if ClassDB.class_exists(&"NativeVoxelWorld") and OS.get_environment("VOXEL_NATIVE") != "0" else 0
	return _enabled == 1


## Returns a new instance of a native class, or null when the extension is unavailable.
static func create(native_class: StringName) -> Object:
	return ClassDB.instantiate(native_class) if enabled() and ClassDB.class_exists(native_class) else null
