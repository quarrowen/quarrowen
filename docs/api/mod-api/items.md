# Items

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.register_item`

GDScript: `api.register_item(item_name: String, def: Dictionary) -> int`

JavaScript: `api.registerItem(name: string, def: ItemDef): ItemId`

Registers a non-block item. `icon` is a texture path; `usable` makes right-click fire item_use.
`group` names its drawer in the creative palette, as on a block; `hidden: true` keeps it out.
Returns the item id (>= 256), or -1.

```gdscript
ids.pail = api.register_item("pail", {"display_name": "Pail", "max_stack": 1, "usable": true})
```

**See also:** `is_excluded`, `qualified`, `register`, `register_asset`, `reload`

### `api.drop_item`

GDScript: `api.drop_item(item_id: int, count: int, position: Vector3, realm_id := "")`

JavaScript: `api.dropItem(item: ItemId, count: number, position: Vec3): Entity | null`

Drops an item stack entity (players walk over it to pick it up).

**See also:** `max_stack`, `qualified`, `register_instance`, `spawn`

### `api.item`

GDScript: `api.item(item_name: String) -> int`

JavaScript: `api.item(name: string): ItemId`

Looks up any block or item id by name ("base:coal", or a local name). -1 if unknown.

### `api.item_name`

GDScript: `api.item_name(id: int) -> String`

JavaScript: `api.itemName(id: ItemId): string`

The full name ("mod:name") of a block or item id, or "".

### `api.item_max_stack`

GDScript: `api.item_max_stack(id: int) -> int`

JavaScript: `api.itemMaxStack(id)`

How many of this item fit in one slot.

**See also:** `max_stack`

### `api.item_display_name`

GDScript: `api.item_display_name(id: int) -> String`

JavaScript: `api.itemDisplayName(id: ItemId): string`

The name players see for a block or item id.

### `api.item_tool`

GDScript: `api.item_tool(id: int, item_data := {}) -> Dictionary`

JavaScript: `api.itemTool(id, itemData)`

The tool stats in force for one stack: `{type, tier, speed}`, or `{}` when it is not a tool.

`item_data` is the stack's own data (`ev.data`, an inventory slot's data). **Pass it**: a tool built
from parts carries its stats there, so reading the definition alone reports the plain one's numbers.

Ask this rather than keeping a set of ids. `base`'s farming kept `ids.hoes` and filled it as it
registered each hoe, which meant tilling only worked for hoes `base` itself had registered - so the
moment the hoes moved to `simple_gear` (2026-09-23) grass stopped turning into farmland. A mod that
adds a better hoe now works without anything knowing it exists.

**See also:** `tool_of`

### `api.item_weapon`

GDScript: `api.item_weapon(id: int, item_data := {}) -> Dictionary`

JavaScript: `api.itemWeapon(id, itemData)`

The weapon stats in force for one stack: `{damage, cooldown, reach, crit_chance, knockback,
sweep}`, or `{}` when it is not a weapon. Per-stack data wins, as with `item_tool`.

**See also:** `category`, `key`, `unlock`, `weapon_of`

### `api.require_item`

GDScript: `api.require_item(item_name: String) -> int`

JavaScript: `api.requireItem(itemName)`

As require_block, for an item or a block (they share an id space).

```gdscript
ev.player.give(api.require_item("proving:prod"), 1)
```

**See also:** `item`

### `api.send_item`

GDScript: `api.send_item(from: Dictionary, item_name: String, count := 1, data := {}) -> bool`

JavaScript: `api.sendItem(from, itemName, count, data)`

Sends a thing along the links to whichever connected face will take it. Returns false if nothing
would, which is how a machine knows to hold on to it rather than dropping it on the floor.

**Things are not a quantity.** A pickaxe with twelve durability and a name somebody gave it cannot
be halved and is not interchangeable with the next one, so this is its own mechanism rather than
power with a different unit - though it travels the same links. Destinations take turns, so a line
of chests fills evenly rather than the first one found swallowing everything.

**See also:** `qualified`, `send`, `tag`

### `api.on_item_arrived`

GDScript: `api.on_item_arrived(handler: Callable) -> void`

JavaScript: `api.onItemArrived(handler)`

Told when something arrives: {realm, position, face, item, count, data, from}.

**See also:** `on_arrived`
