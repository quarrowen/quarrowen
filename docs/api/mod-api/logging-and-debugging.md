# Logging and debugging

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.info`

GDScript: `api.info(message) -> void`

JavaScript: `api.info(...parts: unknown[]): void`

Logs a line from this mod (console, <world>/logs/latest.log and the dev tools).

### `api.debug_box`

GDScript: `api.debug_box(from: Vector3, to: Vector3, color := "#ffcc00", seconds := 2.0, label := "") -> void`

JavaScript: `api.debugBox(from, to, color, seconds, label)`

Debug drawing for developers (shown to admins with the dev overlay's Draw toggle on; cheap when
nobody watches). Shapes expire after `seconds`. Colors are "#rrggbb" or "#rrggbbaa".

**See also:** `debug_text`, `draw`

### `api.debug_line`

GDScript: `api.debug_line(from: Vector3, to: Vector3, color := "#ffcc00", seconds := 2.0) -> void`

JavaScript: `api.debugLine(from, to, color, seconds)`

A debug line between two points (see debug_box).

**See also:** `draw`

### `api.debug_text`

GDScript: `api.debug_text(position: Vector3, text: String, color := "#ffffff", seconds := 2.0) -> void`

JavaScript: `api.debugText(position, text, color, seconds)`

A debug label floating at a position, always facing the camera (see debug_box).

**See also:** `draw`

### `api.debug_path`

GDScript: `api.debug_path(points: Array, color := "#60ff90", seconds := 2.0) -> void`

JavaScript: `api.debugPath(points, color, seconds)`

A debug path through a list of points (Vector3 or [x, y, z]), with a dot at each (see debug_box).

**See also:** `draw`

### `api.debug_sphere`

GDScript: `api.debug_sphere(center: Vector3, radius := 0.5, color := "#6090ff", seconds := 2.0) -> void`

JavaScript: `api.debugSphere(center, radius, color, seconds)`

A debug wire sphere (see debug_box).

**See also:** `draw`

### `api.debug`

GDScript: `api.debug(message) -> void`

JavaScript: `api.debug(...parts: unknown[]): void`

Log levels for authors: debug lines only appear with `/log level <mod> debug` (or --log-level).
Messages go to the server console, <world>/logs/latest.log and the dev tools.

### `api.warn`

GDScript: `api.warn(message) -> void`

JavaScript: `api.warn(...parts: unknown[]): void`

Logs a warning from this mod (shown in yellow in the dev tools).

### `api.error`

GDScript: `api.error(message) -> void`

JavaScript: `api.error(...parts: unknown[]): void`

Logs an error from the mod (grouped like script errors and shown to admins).

### `api.set_server_info`

GDScript: `api.set_server_info(values: Dictionary) -> void`

JavaScript: `api.setServerInfo(values: { name?: string; description?: string; motd?: string }): void`

Sets the server name/description shown to connecting clients.

```gdscript
api.set_server_info({"name": "Proving Ground", "motd": "Nothing here is meant to be fun."})
```

### `api.company_info`

GDScript: `api.company_info(company_id: int) -> Dictionary`

JavaScript: `api.companyInfo(companyId)`

**See also:** `claim_plot`, `plot_problem`

### `api.assembly_info`

GDScript: `api.assembly_info(assembly_id: int) -> Dictionary`

JavaScript: `api.assemblyInfo(assemblyId)`

{id, realm, origin, offset, cells, name}, or {}.

### `api.claim_info`

GDScript: `api.claim_info(claim_id: int) -> Dictionary`

JavaScript: `api.claimInfo(claimId)`

One claim: {realm, chunks, owner, player_id, name, centre, cost, paused}, or {}.

### `api.link_info`

GDScript: `api.link_info(id: int) -> Dictionary`

JavaScript: `api.linkInfo(id)`

One link: {kind, a, b, length}, or {} if there is no such link.
