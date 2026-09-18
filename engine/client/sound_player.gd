extends Node3D
## Plays sounds described by the server's SoundRegistry. Audio files are downloaded assets (.ogg or
## .wav), decoded on first use and cached; "engine:*" sounds are built into the client. A fixed pool of
## voices keeps the cost bounded: when all are busy the oldest one is reused.

const SoundRegistry = preload("res://engine/shared/sound_registry.gd")
const ContentCache = preload("res://engine/client/content_cache.gd")

const VOICES_3D := 16
const VOICES_2D := 4
const BUILTIN_DIR := "res://engine/client/sounds/"
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")

var registry := SoundRegistry.new()
## asset name -> {hash, size}; set by the client once content has loaded.
var manifest := {}
## The master volume (the "audio/volume" setting).
var volume: float:
	get:
		return ClientSettings.shared().get_value("audio/volume")
	set(value):
		ClientSettings.shared().set_value("audio/volume", value)
## Sounds started so far (read by tests).
var played := 0

var _voices_3d: Array[AudioStreamPlayer3D] = []
var _voices_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _streams := {}  # asset name -> AudioStream (null when undecodable)


func _ready() -> void:
	for i in VOICES_3D:
		var voice := AudioStreamPlayer3D.new()
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.unit_size = 4.0
		voice.max_polyphony = 1
		voice.bus = ClientSettings.BUS_WORLD
		add_child(voice)
		_voices_3d.append(voice)
	for i in VOICES_2D:
		var voice := AudioStreamPlayer.new()
		voice.bus = ClientSettings.BUS_INTERFACE
		add_child(voice)
		_voices_2d.append(voice)
	ClientSettings.shared().apply_audio()


func play_name(sound_name: String, pos: Vector3, volume_scale := 1.0, pitch := 1.0, positional := true) -> void:
	var id := registry.id_of(sound_name)
	if id >= 0:
		play(id, pos, volume_scale, pitch, positional)


func play(id: int, pos: Vector3, volume_scale := 1.0, pitch := 1.0, positional := true) -> void:
	if not registry.is_valid(id) or not is_finite(volume_scale) or not is_finite(pitch):
		return
	var def: Dictionary = registry.defs[id]
	var stream := _stream_for(def)
	if stream == null:
		return
	var final_pitch := clampf(def.pitch * pitch + randf_range(-def.pitch_variance, def.pitch_variance), 0.25, 4.0)
	var db := linear_to_db(maxf(clampf(def.volume * volume_scale, 0.0, 4.0), 0.0001))
	played += 1
	if positional:
		var voice := _voices_3d[_next_3d]
		_next_3d = (_next_3d + 1) % VOICES_3D
		voice.stream = stream
		voice.global_position = pos
		voice.max_distance = def.range
		voice.volume_db = db
		voice.pitch_scale = final_pitch
		voice.play()
	else:
		var voice := _voices_2d[_next_2d]
		_next_2d = (_next_2d + 1) % VOICES_2D
		voice.stream = stream
		voice.volume_db = db
		voice.pitch_scale = final_pitch
		voice.play()


func _stream_for(def: Dictionary) -> AudioStream:
	var files: Array = def.files
	if files.is_empty():
		if not String(def.name).begins_with("engine:"):
			return null
		# Ogg where there is one (Kenney's are Ogg and a quarter the size), the generated .wav otherwise.
		var stem := BUILTIN_DIR + String(def.name).get_slice(":", 1)
		var builtin := stem + ".ogg" if ResourceLoader.exists(stem + ".ogg") else stem + ".wav"
		if not _streams.has(builtin):
			_streams[builtin] = load(builtin) if ResourceLoader.exists(builtin) else null
		return _streams[builtin]
	var asset: String = files[randi() % files.size()]
	if not _streams.has(asset):
		_streams[asset] = _decode(asset)
	return _streams[asset]


func _decode(asset: String) -> AudioStream:
	if not manifest.has(asset):
		return null
	var bytes := ContentCache.read(manifest[asset].hash)
	if bytes.is_empty():
		return null
	match asset.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	push_warning("[client] Unsupported sound format: %s" % asset)
	return null
