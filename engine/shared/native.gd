extends RefCounted
## Access to the Rust extension (native/), which is **required**.
##
## It used to be optional: every native feature had a GDScript twin and the engine ran either way,
## slowly, with `QW_NATIVE=0` forcing the twins so the suite could exercise them. That ended on
## 2026-09-23, once the library built for all four target platforms - Windows, macOS, iOS and Android.
##
## The twins were deleted because they cost more than they were worth. Measured: the mesher ran 15x
## slower, player physics 15x, the entity tick 3.5x - and worse, **the meshers were not the same
## algorithm**, so the twin drew a different-looking world with two orders of magnitude more geometry.
## They were 833 lines that had to be kept in step with the Rust by hand, which CLAUDE.md lists first
## under "things that must change together", and in the project's whole history the fallback suite
## never once caught a real bug. It raised three false alarms that cost a day between them.
##
## **So a missing library is now an error, loudly, at the first thing that asks for it.** That is the
## deliberate trade: before, a library that failed to load meant "the game is slow" and nobody could
## tell; now it means "the game says what is wrong". A silent degradation nobody can see is worse than
## a stop nobody can miss.

## Set once the first check has run, so the error is printed once rather than per call.
static var _checked := false


## Whether the extension is loaded. Kept as a function because a handful of callers want to *report*
## it (the server's startup line, the benchmark's labels) rather than depend on it.
static func enabled() -> bool:
	return ClassDB.class_exists(&"NativeVoxelWorld")


## A new instance of a native class. Never null in a working build; says what is wrong when it is.
static func create(native_class: StringName) -> Object:
	if ClassDB.class_exists(native_class):
		return ClassDB.instantiate(native_class)
	if not _checked:
		_checked = true
		push_error("The Quarrowen native extension is not loaded, so '%s' does not exist. Build it with "
			% native_class + "tools/build_native.sh (see quarrowen_native.gdextension for the platforms).")
	return null
