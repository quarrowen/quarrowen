extends RefCounted
## The server log for mod authors: every message with a level and a source (a mod id, "engine" or
## "server"), a ring buffer the dev tools read, a log file per world, and script errors caught with
## file, line and stack, attributed to the mod whose code was running and de-duplicated.
##
## - Mods log with api.debug / api.info / api.warn / api.error (JS: console.debug/log/warn/error).
##   Messages below a source's level are dropped (default "info"; `/log level <mod> debug`).
## - GDScript runtime errors and warnings come from Godot's Logger with script backtraces; the first
##   frame inside a mod folder names the mod. JavaScript errors come from js_mod with their JS stack.
## - Lines everything else prints ("[server] ...", "[arcana] ...") are kept too, tagged by their prefix.
## - Errors are grouped by source, file, line and message with a count; new ones (and repeats at most
##   once every REPEAT_NOTIFY seconds) are sent to the `error_added` listeners (admins' alerts).
## Files: <world>/logs/latest.log, rotated to <date>.log on start, KEEP_FILES kept.

const LEVELS := {"debug": 0, "info": 1, "warn": 2, "error": 3}
const MAX_ENTRIES := 2000
const MAX_ERRORS := 200
const KEEP_FILES := 5
const REPEAT_NOTIFY := 10.0

## Everything Godot prints or reports goes through here (on any thread).
class Capture extends Logger:
	var log  # DevLog (weak use: only `queue` and `mutex`)
	var mutex := Mutex.new()
	var queue: Array = []
	var quiet_thread := -1  # the thread currently writing a DevLog entry (its own print is skipped)

	func _log_message(message: String, error: bool) -> void:
		if OS.get_thread_caller_id() == quiet_thread:
			return
		mutex.lock()
		queue.append({"kind": "message", "text": message, "error": error})
		mutex.unlock()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var frames := []
		for bt in script_backtraces:
			for i in bt.get_frame_count():
				frames.append({"file": bt.get_frame_file(i), "line": bt.get_frame_line(i), "function": bt.get_frame_function(i)})
		mutex.lock()
		queue.append({"kind": "error", "function": function, "file": file, "line": line, "code": code, "rationale": rationale,
			"warning": error_type == Logger.ERROR_TYPE_WARNING, "script": error_type == Logger.ERROR_TYPE_SCRIPT, "frames": frames})
		mutex.unlock()


signal entry_added(entry: Dictionary)
signal error_added(error: Dictionary, first: bool)

var entries: Array[Dictionary] = []
var errors := {}  # key -> {id, source, level, message, file, line, stack, count, first, last}
var levels := {}  # source -> minimum level name
var default_level := "info"
var capture: Capture

var _seq := 0
var _error_seq := 0
var _mod_dirs := {}  # absolute folder (with trailing /) -> mod id
var _file: FileAccess
var _notified := {}  # error key -> time last sent


func _init() -> void:
	capture = Capture.new()
	OS.add_logger(capture)


func close() -> void:
	if capture != null:
		OS.remove_logger(capture)
		capture = null
	if _file != null:
		_file.close()
		_file = null


## Opens <save_dir>/logs/latest.log, moving the previous one aside.
func open_file(save_dir: String) -> void:
	var dir := save_dir.path_join("logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var latest := dir.path_join("latest.log")
	if FileAccess.file_exists(latest):
		var stamp := Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(latest)).replace(":", "-").replace("T", "_")
		DirAccess.rename_absolute(latest, dir.path_join("%s.log" % stamp))
	var old := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".log") and f != "latest.log")
	old.sort()
	while old.size() > KEEP_FILES - 1:
		DirAccess.remove_absolute(dir.path_join(old.pop_front()))
	_file = FileAccess.open(latest, FileAccess.WRITE)
	for e in entries:
		_write(e)


func add_mod_dir(mod_id: String, dir: String) -> void:
	var path := ProjectSettings.globalize_path(dir).simplify_path()
	_mod_dirs[path.trim_suffix("/") + "/"] = mod_id
	_mod_dirs[dir.trim_suffix("/") + "/"] = mod_id


## Which mod a script file belongs to ("" when none).
func mod_of_file(file: String) -> String:
	if file.is_empty():
		return ""
	var path := file if file.begins_with("res://") or file.begins_with("user://") else file.simplify_path()
	for dir: String in _mod_dirs:
		if path.begins_with(dir):
			return _mod_dirs[dir]
	var global := ProjectSettings.globalize_path(file).simplify_path()
	for dir: String in _mod_dirs:
		if global.begins_with(dir):
			return _mod_dirs[dir]
	return ""


func set_level(source: String, level: String) -> bool:
	if not LEVELS.has(level):
		return false
	if source == "all" or source.is_empty():
		default_level = level
		levels.clear()
	else:
		levels[source] = level
	return true


func level_of(source: String) -> String:
	return levels.get(source, default_level)


func enabled(source: String, level: String) -> bool:
	return LEVELS.get(level, 1) >= LEVELS[level_of(source)]


## Adds a message. Returns the entry, or {} when filtered out.
## `echo` prints it to the console (off for lines that were captured from the console already).
func add(level: String, source: String, message: String, extra := {}, echo := true) -> Dictionary:
	if not LEVELS.has(level):
		level = "info"
	if level != "error" and not enabled(source, level):
		return {}
	_seq += 1
	var entry := {"id": _seq, "time": Time.get_unix_time_from_system(), "level": level, "source": source, "message": message.left(4000)}
	entry.merge(extra)
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	_write(entry)
	if not echo:
		entry_added.emit(entry)
		return entry
	# Echo to the console like print() would, without capturing our own line again.
	var line := "[%s] %s%s" % [source, "" if level == "info" else level.to_upper() + ": ", message]
	if capture != null:
		capture.quiet_thread = OS.get_thread_caller_id()
	if level == "error" or level == "warn":
		printerr(line)
	else:
		print(line)
	if capture != null:
		capture.quiet_thread = -1
	entry_added.emit(entry)
	return entry


## Records an error (grouped with identical ones) and logs it once per group.
func report_error(source: String, message: String, file := "", line := 0, stack := [], level := "error") -> Dictionary:
	var key := "%s|%s|%d|%s" % [source, file, line, message]
	var now := Time.get_unix_time_from_system()
	var first := not errors.has(key)
	if first:
		if errors.size() >= MAX_ERRORS:
			var oldest: String = errors.keys()[0]
			errors.erase(oldest)
		_error_seq += 1
		errors[key] = {"id": _error_seq, "key": key, "source": source, "level": level, "message": message.left(2000), "file": file,
			"line": line, "stack": stack.slice(0, 16), "count": 0, "first": now, "last": now}
	var e: Dictionary = errors[key]
	e.count += 1
	e.last = now
	if first:
		add(level, source, "%s%s" % [message, " (%s:%d)" % [file.get_file(), line] if not file.is_empty() else ""], {"error": e.id})
	if first or now - float(_notified.get(key, 0.0)) >= REPEAT_NOTIFY:
		_notified[key] = now
		error_added.emit(e, first)
	return e


func clear_errors(source := "") -> void:
	for key in errors.keys():
		if source.is_empty() or errors[key].source == source:
			errors.erase(key)
			_notified.erase(key)


## Recent entries, newest last: filtered by source ("" = all), minimum level and text.
func recent(count := 50, source := "", min_level := "debug", text := "") -> Array:
	var out := []
	var needle := text.to_lower()
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if (source.is_empty() or e.source == source) and LEVELS[e.level] >= LEVELS.get(min_level, 0) \
				and (needle.is_empty() or e.message.to_lower().contains(needle)):
			out.append(e)
			if out.size() >= count:
				break
	out.reverse()
	return out


func sorted_errors() -> Array:
	var out := errors.values()
	out.sort_custom(func(a, b): return a.last > b.last)
	return out


## Moves what Godot reported (from any thread) into the log. Call every frame on the main thread.
func drain() -> void:
	if capture == null:
		return
	capture.mutex.lock()
	var items := capture.queue
	capture.queue = []
	capture.mutex.unlock()
	for item in items:
		if item.kind == "message":
			_from_message(item.text, item.error)
		else:
			_from_error(item)
	if _file != null and not items.is_empty():
		_file.flush()


func _from_message(text: String, error: bool) -> void:
	var line := text.strip_edges(false, true)
	if line.is_empty():
		return
	var source := "godot"
	if line.begins_with("[") and line.find("] ") > 1 and line.find("] ") < 40:
		source = line.substr(1, line.find("] ") - 1)
		line = line.substr(line.find("] ") + 2)
	add("error" if error else "info", source, line, {}, false)


func _from_error(item: Dictionary) -> void:
	var message: String = item.rationale if not str(item.rationale).is_empty() else item.code
	if not str(item.rationale).is_empty() and not str(item.code).is_empty() and item.code != item.rationale:
		message = "%s (%s)" % [item.rationale, item.code]
	var file: String = item.file
	var line: int = item.line
	var source := ""
	var stack := []
	for f in item.frames:
		stack.append("%s:%d in %s()" % [f.file, f.line, f.function])
		if source.is_empty():
			source = mod_of_file(f.file)
			if not source.is_empty():
				file = f.file
				line = f.line
	if source.is_empty():
		source = mod_of_file(file)
	if source.is_empty():
		source = "engine"
	report_error(source, message, file, line, stack, "warn" if item.warning else "error")


func _write(entry: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line("%s %-5s [%s] %s" % [Time.get_datetime_string_from_unix_time(int(entry.time)).replace("T", " "), entry.level.to_upper(), entry.source, entry.message])
