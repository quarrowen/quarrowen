# Players and gameplay

Part of the [Mod API reference](../mod-api.md). Mod API 1.1.0 · game 0.42.1


### `api.players`

GDScript: `api.players() -> Array`

JavaScript: `api.players(): Player[]`

Everyone playing on this server right now, as an Array of players.

**See also:** `register_weather`

### `api.set_player_rig`

GDScript: `api.set_player_rig(def: Dictionary) -> void`

JavaScript: `api.setPlayerRig(def)`

Replaces the player character rig for this server (see engine/shared/player_rig.gd).

**See also:** `reload`, `sanitize`

### `api.register_cosmetic`

GDScript: `api.register_cosmetic(cosmetic_name: String, def: Dictionary) -> String`

JavaScript: `api.registerCosmetic(cosmeticName, def)`

Registers a server cosmetic players can wear on this server (see engine/shared/cosmetics.gd for
the def: category, paint, pixels, boxes, texture, model, color, covers, unlocked...). `texture` and
`model` are paths in this mod. `unlocked: false` makes it wearable only after player.grant_cosmetic.
Returns the cosmetic's full name ("mod:name"), or "" when invalid.

```gdscript
api.register_cosmetic("cap", {"category": "hat", "display_name": "Cap", "unlocked": true,
	"boxes": [{"from": [-4, 8, -4], "size": [8, 2, 8], "color": "#4488cc"}]})
```

**See also:** `attach`, `register`, `register_asset`, `reload`

### `api.register_cosmetic_category`

GDScript: `api.register_cosmetic_category(category_name: String, def := {}) -> bool`

JavaScript: `api.registerCosmeticCategory(categoryName, def)`

Adds a cosmetic category. def: display_name, attach (rig attachment point for boxes and models),
covers (armor slots its cosmetics replace by default).

```gdscript
api.register_cosmetic_category("hat", {"display_name": "Hats"})
```

**See also:** `register_category`

### `api.set_cosmetics_policy`

GDScript: `api.set_cosmetics_policy(values: Dictionary) -> void`

JavaScript: `api.setCosmeticsPolicy(values)`

Sets how cosmetics work on this server. values (any subset):
allow_builtin: players may wear built-in cosmetics (their own look from other servers)
allow_colors:  players may recolor cosmetics and choose skin colors
armor: "player" (each player chooses per slot), "armor" (armor always shows), "cosmetics"
blocked: [cosmetic names or categories]
uniform: avatar data laid over every player, e.g. {wear: {shirt: {id: "builtin:tshirt", color: "#d94c4c"}}}
For per-player looks (teams, disguises) use player.set_avatar_override or the avatar_change event.

**See also:** `item`, `refresh_avatar`, `set_policy`, `worn`

### `api.register_equipment_slot`

GDScript: `api.register_equipment_slot(slot_name: String, def := {}) -> bool`

JavaScript: `api.registerEquipmentSlot(slotName, def)`

```gdscript
api.register_equipment_slot("charm", {"display_name": "Charm"})
```

**See also:** `get_stat`, `register_slot`

### `api.register_stat`

GDScript: `api.register_stat(stat_name: String, base: float) -> bool`

JavaScript: `api.registerStat(statName, base)`

Adds a player stat with a base value. Items and effects change it with modifiers; read it with
player.get_stat(name). Engine stats: see ItemRegistry.BASE_STATS.

```gdscript
api.register_stat("proving:resolve", 1.0)
```

**See also:** `can_see_target`, `health_fraction`

### `api.set_gameplay`

GDScript: `api.set_gameplay(values: Dictionary, realm_id := "") -> void`

JavaScript: `api.setGameplay(values, realmId)`

Game-wide rules: item_drops ("entity" | "inventory"), keep_inventory, pvp, fall_damage,
natural_regeneration, mob_spawning, flight (false stops the double-tap in a survival game; `/fly`
still obeys an admin who means it). See GameServer.gameplay for the full list and the defaults.
`realm_id` sets them for one world instead of the whole server, and **overlays rather than
replaces**: a lobby that only wants PvP off says that and inherits everything else, and a rule the
engine gains later reaches it without this call being edited. Names without ":" are this mod's.

```gdscript
api.set_gameplay({"pvp": false, "fall_damage": false}, "deep")
```

**See also:** `qualified`

### `api.get_gameplay`

GDScript: `api.get_gameplay(rule: String, realm_id := "")`

JavaScript: `api.getGameplay(rule, realmId)`

A gameplay rule's current value (see set_gameplay), or null. `realm_id` asks what is in force in one
world; "" is the server's own set, which every realm without an override of its own reads.

**See also:** `gameplay_in`, `qualified`

### `api.gameplay_for`

GDScript: `api.gameplay_for(player, rule: String)`

JavaScript: `api.gameplayFor(player, rule)`

What is in force where this player is standing, which is what a rule about hunger, falling or
hitting somebody always means. Null if they are gone.

**See also:** `gameplay_of`

### `api.players_in_region`

GDScript: `api.players_in_region(id: int) -> Array`

JavaScript: `api.playersInRegion(id)`

Who is standing in one right now.

**See also:** `players_in`, `register_condition`

### `api.player_roles`

GDScript: `api.player_roles(player_id: String) -> Array`

JavaScript: `api.playerRoles(playerId: string): string[]`

A player's roles by player id (the default role included).

**See also:** `roles_of`

### `api.set_player_role`

GDScript: `api.set_player_role(player_id: String, role: String, on := true) -> bool`

JavaScript: `api.setPlayerRole(playerId: string, role: string, on?: boolean): boolean`

Gives (or takes) a role. Returns whether anything changed.

**See also:** `give`, `take`

### `api.set_physics`

GDScript: `api.set_physics(values: Dictionary, realm_id := "") -> void`

JavaScript: `api.setPhysics(values: Record<string, number | boolean>, options?: { realm?: string }): void`

Movement tunables (walk_speed, sprint_speed, gravity, jump_velocity, ...) and `void_below`.

`realm_id` sets them for one world rather than the whole server, overlaying it the way
`set_gameplay` does - a low-gravity arena beside an ordinary world. Players are told the rules of
wherever they are standing, on joining and whenever they cross between worlds, because a client that
predicts movement the server is not simulating rubber-bands. Names without ":" are this mod's.

```gdscript
api.set_physics({"gravity": 8.0}, "deep")
```

**See also:** `qualified`, `set_rules`

### `api.get_players`

GDScript: `api.get_players() -> Array`

JavaScript: `api.getPlayers()`

Everyone online (player objects).

### `api.find_player`

GDScript: `api.find_player(player_name: String)`

JavaScript: `api.findPlayer(name: string): Player | null`

The online player with this name (any case), or null.

### `api.broadcast`

GDScript: `api.broadcast(text: String) -> void`

JavaScript: `api.broadcast(text: string): void`

Sends a chat message to everyone.

**See also:** `add_death_messages`, `broadcast_chat`
