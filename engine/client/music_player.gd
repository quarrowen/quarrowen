extends Node
## Plays the one track the server has asked for, crossfading when it changes.
##
## Two players rather than one, because a cut between tracks is jarring and a fade needs both playing at
## once for a moment. The outgoing one is freed when it reaches silence.
##
## Music files are lazy assets: they are not part of the download a player waits through to join, so the
## first time a track is asked for it may not be here yet. That is not an error - the request goes out,
## the track starts when it arrives, and if the server has moved on to a different one by then the late
## arrival is dropped. Nothing waits for music and music never makes anything wait.

const MusicRegistry = preload("res://engine/shared/music_registry.gd")
const ContentCache = preload("res://engine/client/content_cache.gd")
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")

var registry := MusicRegistry.new()
## Set by the client: fetch_lazy_asset(asset_name, then) from GameClient.
var fetch := Callable()
## asset name -> {hash, size}; set by the client once content has loaded, as for sounds.
var manifest := {}
## The track the server last asked for, whether or not it is audible yet (read by tests).
var wanted := -1
## What is actually playing (read by tests).
var playing := -1

var _current: AudioStreamPlayer = null
var _fading: Array[Dictionary] = []  # {player, from, seconds, elapsed}
var _streams := {}  # asset name -> AudioStream


func _ready() -> void:
	set_process(true)


## The server's instruction. -1 stops.
func play(track_id: int, fade: float, restart: bool) -> void:
	if track_id == wanted and not restart:
		return
	wanted = track_id
	if track_id < 0 or not registry.is_valid(track_id):
		_fade_out(fade)
		playing = -1
		return
	var asset_name: String = registry.defs[track_id].file
	if _streams.has(asset_name):
		_start(track_id, fade)
		return
	if fetch.is_valid():
		fetch.call(asset_name, func(name: String): _arrived(name, track_id, fade))


## A lazy asset finished downloading. It may have taken a while, so check the server still wants it.
func _arrived(asset_name: String, track_id: int, fade: float) -> void:
	var stream := _decode(asset_name)
	if stream == null:
		return
	_streams[asset_name] = stream
	if wanted == track_id:
		_start(track_id, fade)


## The same decode the sound player does, from the content cache by hash.
func _decode(asset_name: String) -> AudioStream:
	if not manifest.has(asset_name):
		return null
	var bytes := ContentCache.read(manifest[asset_name].hash)
	if bytes.is_empty():
		return null
	match asset_name.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	push_warning("[client] Unsupported music format: %s" % asset_name)
	return null


func _start(track_id: int, fade: float) -> void:
	var def: Dictionary = registry.defs[track_id]
	var stream: AudioStream = _streams.get(def.file)
	if stream == null:
		return
	_fade_out(fade)
	var voice := AudioStreamPlayer.new()
	voice.bus = ClientSettings.BUS_MUSIC
	voice.stream = stream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = bool(def.loop)
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if bool(def.loop) else AudioStreamWAV.LOOP_DISABLED
	add_child(voice)
	voice.volume_db = linear_to_db(0.001)
	voice.play()
	_current = voice
	playing = track_id
	_fading.append({"player": voice, "from": 0.001, "to": float(def.volume), "seconds": maxf(fade, 0.01), "elapsed": 0.0})


func _fade_out(seconds: float) -> void:
	if _current == null:
		return
	_fading = _fading.filter(func(f): return f.player != _current)
	_fading.append({"player": _current, "from": db_to_linear(_current.volume_db), "to": 0.0,
		"seconds": maxf(seconds, 0.01), "elapsed": 0.0})
	_current = null


func _process(delta: float) -> void:
	if _fading.is_empty():
		return
	var still := []
	for f: Dictionary in _fading:
		var voice: AudioStreamPlayer = f.player
		if not is_instance_valid(voice):
			continue
		f.elapsed += delta
		var t: float = clampf(f.elapsed / f.seconds, 0.0, 1.0)
		var level: float = lerpf(float(f.from), float(f.to), t)
		voice.volume_db = linear_to_db(maxf(level, 0.0001))
		if t < 1.0:
			still.append(f)
		elif float(f.to) <= 0.0:
			voice.stop()
			voice.queue_free()
	_fading.assign(still)


## Everything the server is carrying, as lines to show a player. Music must say who made it.
func credits() -> Array:
	return registry.credits()

