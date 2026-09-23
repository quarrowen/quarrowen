# Sounds, effects and assets

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.register_sound`

GDScript: `api.register_sound(sound_name: String, files, options := {}) -> int`

JavaScript: `api.registerSound(name: string, files: string | string[], options?: { volume?: number; pitch?: number; pitch_variance?: number; range?: number }): number`

Registers a sound from one or more audio files in the mod folder (.ogg or .wav; a random one plays
each time). options: volume (0-2), pitch, pitch_variance, range (blocks). Returns the sound id.

```gdscript
api.register_sound("chime", "music/daylight.ogg", {"volume": 0.4, "range": 24.0})
```

**See also:** `register`, `register_ambience`, `register_asset`, `reload`

### `api.register_effect`

GDScript: `api.register_effect(effect_name: String, def: Dictionary) -> int`

JavaScript: `api.registerEffect(effectName, def)`

Registers a visual effect: particle emitters, light flash, camera shake and sound (see
engine/shared/effect_registry.gd). Emitter textures are paths in this mod or "soft", "spark",
"star", "square". Returns the effect id, or -1.

```gdscript
api.register_effect("puff", {"particles": 12, "color": "#cccccc", "scale": 1.0, "duration": 0.6})
```

**See also:** `damage`, `qualified`, `register`, `register_asset`, `reload`

### `api.play_effect`

GDScript: `api.play_effect(effect_name: String, position: Vector3, options := {}) -> void`

JavaScript: `api.playEffect(effectName, position, options)`

Plays an effect for everyone in range. options: color ("#rrggbb", tints it), scale, direction
(Vector3), duration (seconds for continuous emitters), follow (an entity or player it moves with).
Built in: engine:hit, engine:crit, engine:smoke, engine:sparkle, engine:magic, engine:heal,
engine:dust, engine:explosion.

```gdscript
api.play_effect("puff", at + Vector3(0, 1, 0), {"scale": 1.0})
```

**See also:** `clean_options`, `follow`, `qualified`

### `api.play_sound`

GDScript: `api.play_sound(sound_name: String, position: Vector3, volume := 1.0, pitch := 1.0) -> void`

JavaScript: `api.playSound(name: string, position: Vec3, volume?: number, pitch?: number): void`

Plays a sound at a world position for everyone in range.

**See also:** `play_sound_at`, `qualified`

### `api.register_asset`

GDScript: `api.register_asset(relative_path: String, options := {}) -> String`

JavaScript: `api.registerAsset(relativePath, options)`

Makes a file from this mod's folder downloadable by clients. Returns its asset name.
options: {lazy} - a lazy asset is listed for the client but not part of the download it waits through
to join; it is fetched the first time something needs it. Use it for anything big and optional (music
is the reason it exists). Anything the world cannot be drawn without must stay eager.

```gdscript
api.register_asset("music/night.ogg", {"lazy": true})
```

**See also:** `add_asset`, `reload`

### `api.start_effect`

GDScript: `api.start_effect(effect_name: String, position: Vector3, options := {}, realm_id := "") -> int`

JavaScript: `api.startEffect(effectName, position, options, realmId)`

An effect that keeps going until you stop it, at a place. Returns a handle, or 0.

`play_effect` is a burst that forgets itself, which cannot say "this machine is working now".
Whoever walks up to a running machine sees it working, not only whoever was there when it started.

**See also:** `clean_options`, `qualified`, `realm_of`

### `api.stop_effect`

GDScript: `api.stop_effect(handle: int) -> bool`

JavaScript: `api.stopEffect(handle)`

Stops one started with start_effect.
