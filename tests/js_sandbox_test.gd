extends Node
## Checks the JavaScript mod sandbox limits:
##   godot --headless --path . res://tests/js_sandbox_test.tscn

var _failures := 0


func _ready() -> void:
	if not ClassDB.class_exists(&"NativeJsRuntime"):
		print("[sandbox] native extension missing")
		get_tree().quit(1)
		return
	var js: Object = ClassDB.instantiate(&"NativeJsRuntime")
	js.set_time_budget_ms(200)

	var started := Time.get_ticks_msec()
	var error: String = js.eval_script("spin.js", "while (true) {}")
	var elapsed := Time.get_ticks_msec() - started
	_check(not error.is_empty() and elapsed < 1000, "infinite loop interrupted after %d ms (%s)" % [elapsed, error.left(60)])

	error = js.eval_script("hog.js", "const hog = []; while (true) hog.push(new Array(100000).fill(3.14));")
	_check(error.to_lower().contains("memory"), "memory bomb stopped by the heap limit (%s)" % error.left(60))

	js.eval_script("probe.js", "globalThis.probe = () => JSON.stringify([typeof require, typeof std, typeof os, typeof process, typeof fetch, typeof XMLHttpRequest]);")
	var probe: String = js.call_function("probe", "")
	_check(probe == '["undefined","undefined","undefined","undefined","undefined","undefined"]', "no filesystem, process or network globals (%s)" % probe)

	js.eval_script("boom.js", "globalThis.boom = () => { throw new TypeError('bad mod'); };")
	var reply = JSON.parse_string(js.call_function("boom", ""))
	_check(reply is Dictionary and String(reply.get("__error", "")).contains("bad mod"), "exceptions come back as errors, not crashes")

	js.eval_script("ok.js", "globalThis.ok = (s) => `still alive: ${s}`;")
	_check(js.call_function("ok", "yes") == "still alive: yes", "runtime keeps working after failures")
	print("[sandbox] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("[sandbox] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
