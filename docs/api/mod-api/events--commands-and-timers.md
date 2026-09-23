# Events, commands and timers

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.cancel_assembly`

GDScript: `api.cancel_assembly(assembly_id: int) -> bool`

JavaScript: `api.cancelAssembly(assemblyId)`

Puts it back exactly where it was lifted from.

**See also:** `cancel`

### `api.on`

GDScript: `api.on(event: String, handler: Callable, priority := 0) -> void`

JavaScript: `api.on(event, handler, priority)`

Higher priority runs first.

```gdscript
api.on("entity_spawned", func(ev):
	if ev.entity.type == ids.grazer and not ev.entity.data.has("look"):
		ev.entity.set_look({"hide": ["collar"]}))
```

**See also:** `add_handler`

### `api.register_command`

GDScript: `api.register_command(command: String, description: String, handler: Callable, permission := "") -> void`

JavaScript: `api.registerCommand(command, description, handler, permission)`

`handler(player, args: PackedStringArray)` runs for "/name args...". permission "admin" restricts
it to server admins (QW_ADMINS, /op, or the local host).

```gdscript
api.register_command("trial", "Go into a private copy of a room", func(player, _args):
	var here: String = api.instance_of(player)
	if not here.is_empty():
		api.leave_instance(player)
		player.send_message("Back out.")
		return
	var run: String = api.open_instance("trial", {"data": {"opened_for": player.name}})
	if run.is_empty():
		player.send_message("No room to open one.")
		return
	api.enter_instance(player, run, Vector3(0.5, 66, 0.5))
	player.send_message("You are in %s." % run))
```

**See also:** `add_command`

### `api.after`

GDScript: `api.after(seconds: float, callback: Callable) -> int`

JavaScript: `api.after(seconds, callback)`

Runs `callback` once after `seconds`. Returns a task id for `cancel`.

**See also:** `schedule`

### `api.every`

GDScript: `api.every(seconds: float, callback: Callable) -> int`

JavaScript: `api.every(seconds, callback)`

Runs `callback` every `seconds`. Returns a task id for `cancel`.

**See also:** `schedule`

### `api.cancel`

GDScript: `api.cancel(task_id: int) -> void`

JavaScript: `api.cancel(taskId)`

Stops a timer started with after or every.

**See also:** `broadcast_player_event`, `cancel_task`, `settle`
