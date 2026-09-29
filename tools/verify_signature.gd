extends SceneTree
## Would a shipped client accept the signature beside `QW_VERIFY_FILE`?
##
## Signing proves the key was readable; it does not prove the key is the one this build's updater
## trusts. Those two come apart the moment a key is rotated, or a release is cut on a machine holding an
## older one - and the failure is silent and late: the site looks right, the manifest looks right, and
## every installed game refuses the update with a line in a log nobody is reading.
##
##   QW_VERIFY_FILE=build/release/update.json godot --headless --path . -s tools/verify_signature.gd
##
## Exit 0 when a client would accept it, 1 when it would not, 2 when the files could not be read.
##
## **`quit()` does not return.** It asks the main loop to stop and execution carries straight on, so the
## first version of this printed its success line, fell through, printed the failure line and exited 1 -
## it would have failed every release, including the correct ones. Every `quit()` here is followed by a
## `return`, and both outcomes are tested in `tests/gameplay_test.gd`. (2026-09-29)
func _init() -> void:
	var Updater = load("res://engine/client/updater.gd")
	var path := OS.get_environment("QW_VERIFY_FILE")
	var text := FileAccess.get_file_as_string(path)
	var sig := FileAccess.get_file_as_string(path + ".sig")
	if text.is_empty() or sig.is_empty():
		print("verify: could not read %s or its signature" % path)
		quit(2)
		return
	if Updater.RELEASE_KEYS.is_empty():
		print("verify: this build trusts no release keys, so any manifest would be accepted")
		quit(0)
		return
	if Updater.signature_ok(text, sig):
		print("verify: the signature matches a key this build trusts")
		quit(0)
		return
	print("verify: SIGNED WITH A KEY NO CLIENT TRUSTS - see updater.gd RELEASE_KEYS")
	quit(1)
