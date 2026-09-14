extends RefCounted
## Skill crafting minigames. Deterministic, so the server scores exactly what the client drew: a game
## is a dictionary {def, seed, assist, bonus, team, strikes: [t...], holds: [[t, down]...],
## keys: [[t, key]...]} with times in seconds since the game started.
##
## Types (mods pick one per minigame and tune it):
##   timing:   a marker sweeps a bar; strike while it is inside the zone (`rounds` strikes). With
##             `cool` the work cools and the marker speeds up. With `team`, a second player works
##             the bellows: heat must stay in the band (too cold shrinks the zone, too hot ruins a
##             strike) and pumping just before a strike gives a sync bonus.
##   hold:     keep a gauge inside a drifting band by holding and releasing for `duration` seconds.
##   sequence: press the prompted directions in order (`rounds` prompts, `window` seconds each).
## Every result is at least Standard: minigames are an optional bonus.

const TYPES := ["timing", "hold", "sequence"]
const KEYS := ["up", "right", "down", "left"]
const QUALITIES := [
	{"tier": 0, "name": "Standard", "bonus": 0.0, "color": "#d8d8d8", "min": 0.0},
	{"tier": 1, "name": "Fine", "bonus": 0.1, "color": "#8fe07a", "min": 0.45},
	{"tier": 2, "name": "Superior", "bonus": 0.2, "color": "#6fb4ff", "min": 0.7},
	{"tier": 3, "name": "Masterwork", "bonus": 0.3, "color": "#ffd24a", "min": 0.92},
]
## Team heat band and rates (per second).
const HEAT_START := 0.55
const HEAT_LOW := 0.4
const HEAT_HIGH := 0.8
const HEAT_BURN := 0.95
const HEAT_UP := 0.45
const HEAT_DOWN := 0.2
const SYNC_WINDOW := 0.8
## Relaxed timing: slower marker, bigger zones, longer windows.
const ASSIST_SPEED := 0.6
const ASSIST_ZONE := 1.5


static func clean_def(game_name: String, def: Dictionary) -> Dictionary:
	var type := str(def.get("type", "timing"))
	return {"name": game_name, "title": str(def.get("title", "Craft by hand")).left(40), "type": type if type in TYPES else "timing",
		"verb": str(def.get("verb", "Strike")).left(20), "rounds": clampi(int(def.get("rounds", 5)), 1, 12),
		"speed": clampf(float(def.get("speed", 0.8)), 0.1, 4.0), "zone": clampf(float(def.get("zone", 0.2)), 0.03, 0.8),
		"cool": clampf(float(def.get("cool", 0.0)), 0.0, 120.0), "team": bool(def.get("team", false)),
		"duration": clampf(float(def.get("duration", 8.0)), 2.0, 60.0), "window": clampf(float(def.get("window", 1.5)), 0.3, 10.0),
		"sound": str(def.get("sound", "")), "roles": ["bellows", "hammer"] if bool(def.get("team", false)) else []}


static func new_game(def: Dictionary, game_seed: int, assist: bool, bonus: float, team: bool) -> Dictionary:
	return {"def": def, "seed": game_seed, "assist": assist, "bonus": clampf(bonus, 0.0, 1.0), "team": team and def.team and def.type == "timing",
		"strikes": [], "holds": [], "keys": []}


## Seconds after which the game ends even without more input.
static func time_limit(g: Dictionary) -> float:
	var d: Dictionary = g.def
	match d.type:
		"hold":
			return d.duration
		"sequence":
			return window(g) * d.rounds + 1.0
	var per := 3.0 / speed(g)
	return maxf(d.cool * 1.5, per * d.rounds) if d.cool > 0.0 else per * d.rounds + 4.0


## Whether the game has everything it needs (all strikes, prompts or the full duration).
static func complete(g: Dictionary, t: float) -> bool:
	match g.def.type:
		"timing":
			return g.strikes.size() >= g.def.rounds
		"sequence":
			return sequence_progress(g).index >= g.def.rounds
	return t >= g.def.duration


# --- Timing ---------------------------------------------------------------------------------------

static func speed(g: Dictionary) -> float:
	return g.def.speed * (ASSIST_SPEED if g.assist else 1.0)


## Marker position 0..1 at time t (sweeping back and forth, faster as the work cools).
static func marker(g: Dictionary, t: float) -> float:
	t = maxf(t, 0.0)
	var cool: float = g.def.cool
	var phase := speed(g) * (t + t * t / (2.0 * cool) if cool > 0.0 and not g.team else t)
	var p := fposmod(phase, 2.0)
	return p if p <= 1.0 else 2.0 - p


static func zone_center(g: Dictionary, i: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([g.seed, i])
	return rng.randf_range(0.2, 0.8)


## Zone width for strike i (narrower each strike; the station's quality bonus widens it).
static func zone_width(g: Dictionary, i: int, t := -1.0) -> float:
	var w: float = g.def.zone * (1.0 + g.bonus * 2.0) * (ASSIST_ZONE if g.assist else 1.0) * pow(0.9, i)
	if g.team and t >= 0.0 and heat(g, t) < HEAT_LOW:
		w *= 0.5
	return w


## Solo with `cool`: 1 falling to 0. Team: simulated from the bellows' presses and releases.
static func heat(g: Dictionary, t: float) -> float:
	if not g.team:
		return clampf(1.0 - t / g.def.cool, 0.0, 1.0) if g.def.cool > 0.0 else 1.0
	var h := HEAT_START
	var last := 0.0
	var down := false
	for e in g.holds:
		var et := minf(float(e[0]), t)
		h = clampf(h + (HEAT_UP if down else -HEAT_DOWN) * (et - last), 0.0, 1.0)
		last = et
		if float(e[0]) > t:
			return h
		down = bool(e[1])
	return clampf(h + (HEAT_UP if down else -HEAT_DOWN) * (t - last), 0.0, 1.0)


## {grade: "perfect" | "good" | "miss" | "burnt", score, synced} for strike i at time t.
static func rate_strike(g: Dictionary, i: int, t: float) -> Dictionary:
	var synced := false
	if g.team:
		if heat(g, t) >= HEAT_BURN:
			return {"grade": "burnt", "score": 0.0, "synced": false}
		var h := heat(g, t)
		if h >= HEAT_LOW and h <= HEAT_HIGH:
			for e in g.holds:
				if bool(e[1]) and float(e[0]) <= t and float(e[0]) >= t - SYNC_WINDOW:
					synced = true
	var off := absf(marker(g, t) - zone_center(g, i))
	var half := zone_width(g, i, t) * 0.5
	if off <= half * 0.4:
		return {"grade": "perfect", "score": 1.0, "synced": synced}
	if off <= half:
		return {"grade": "good", "score": 0.6, "synced": synced}
	return {"grade": "miss", "score": 0.0, "synced": false}


# --- Hold -----------------------------------------------------------------------------------------

## The band's center at time t (drifts slowly).
static func band_center(g: Dictionary, t: float) -> float:
	var offset := float(g.seed % 1000) / 159.0
	return 0.55 + 0.2 * sin(t * 0.7 + offset) * (0.6 if g.assist else 1.0)


static func band_half(g: Dictionary) -> float:
	return g.def.zone * 0.5 * (1.0 + g.bonus * 2.0) * (ASSIST_ZONE if g.assist else 1.0)


## Gauge value at time t: rises while held, falls otherwise.
static func gauge(g: Dictionary, t: float) -> float:
	var saved: bool = g.team
	g.team = true
	var v := heat(g, t)
	g.team = saved
	return v


static func hold_fraction(g: Dictionary, until: float) -> float:
	var steps := int(ceilf(minf(until, g.def.duration) * 20.0))
	if steps <= 0:
		return 0.0
	var inside := 0
	for s in steps:
		var t := (s + 0.5) / 20.0
		if absf(gauge(g, t) - band_center(g, t)) <= band_half(g):
			inside += 1
	return float(inside) / (g.def.duration * 20.0)


# --- Sequence -------------------------------------------------------------------------------------

static func window(g: Dictionary) -> float:
	return g.def.window * (2.0 if g.assist else 1.0)


static func prompt(g: Dictionary, i: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([g.seed, "key", i])
	return KEYS[rng.randi() % KEYS.size()]


## {index (current prompt), hits, started (when the current prompt appeared)} replaying key presses.
static func sequence_progress(g: Dictionary, t := INF) -> Dictionary:
	var index := 0
	var hits := 0
	var started := 0.0
	for e in g.keys:
		var et := float(e[0])
		if et > t:
			break
		while index < g.def.rounds and et - started > window(g):
			started += window(g)  # timed out: that prompt failed
			index += 1
		if index >= g.def.rounds:
			break
		if str(e[1]) == prompt(g, index):
			hits += 1
		index += 1
		started = et
	if t != INF:
		while index < g.def.rounds and t - started > window(g):
			started += window(g)
			index += 1
	return {"index": index, "hits": hits, "started": started}


# --- Scoring --------------------------------------------------------------------------------------

## 0..1 (team timing can reach a little over 1 with sync).
static func score(g: Dictionary, t: float) -> float:
	var d: Dictionary = g.def
	match d.type:
		"hold":
			return hold_fraction(g, t)
		"sequence":
			return float(sequence_progress(g).hits) / d.rounds
	var total := 0.0
	var synced := 0
	for i in g.strikes.size():
		var r := rate_strike(g, i, float(g.strikes[i]))
		total += r.score
		synced += 1 if r.synced else 0
	return total / d.rounds + (0.25 * synced / d.rounds if g.team else 0.0)


static func quality_for(value: float) -> Dictionary:
	var best: Dictionary = QUALITIES[0]
	for q in QUALITIES:
		if value >= q.min - 0.0001:
			best = q
	return best
