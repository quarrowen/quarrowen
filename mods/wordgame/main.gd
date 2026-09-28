extends "res://engine/server/mod.gd"
## Stand On The Answer: a question, four coloured squares, and the wrong three fall away.
##
## **The world has no text in it**, which is the first thing this game had to solve. There is no way to
## write "because" on a block, so the answers are read out in the title text and the squares are
## *coloured* - "stand on crimson". `base` ships sixteen hues with plain spoken names, which is exactly
## the vocabulary this needs. (2026-09-28)
##
## **The questions are a JSON file** (the user, 28 September 2026: make it data, so anybody can write
## their own). Nothing in this file names a single question, and adding one needs no code.
##
## **A round climbs.** The questions carry a level and a round opens on the easiest band, stepping up
## every few questions. That is the one thing this game needed to be worth playing by a mixed room: a
## flat pool hands a new reader a word they cannot decode and hands somebody who has been doing sums for
## thirty years "how many days in a week", and neither of them is playing. Climbing costs no interface
## and no choice - everybody starts somewhere they can stand, and how far up a round gets is simply how
## far it got.
## (28 September 2026)
##
## **It is worth playing alone**, like everything at the Fairground: a solo round is an answer streak
## against the clock rather than a race, and scoring rather than elimination means a wrong answer costs
## you the question and not the game.

const Floor = preload("res://mods/wordgame/floor.gd")

## How long there is to read the question, work it out and walk somewhere. Generous on purpose: the
## clock is here to keep a round moving, and a game where the answer is known and the legs are too slow
## is measuring the wrong thing.
const THINKING := 9.0
## And how long the answer stays up before the next question.
const SETTLE := 3.0

## Levels, and how many questions are asked before the round steps up one. Five bands three questions
## apart fills about the first half of a 180-second round, so the back half is spent at the top - which
## is where a round should be decided.
const LEVELS := 5
const RAMP := 3

var pads := Floor.new()
## instance id -> {right, phase, until, count, used}
var runs := {}

## level -> Array of questions. Kept banded rather than filtered per question, because the filter would
## run every few seconds for the life of the server and the bands never change after load.
var _bands := {}
var _total := 0


func setup(api) -> void:
	_read_questions(api)
	pads.setup(api)

	api.on("fairground:games", func(ev): ev.games.append({
		"mod": "wordgame",
		"id": "answer",
		"display_name": "Stand On The Answer",
		"blurb": "Stand on the colour that is right.",
		"min_players": 1,
		"max_players": 8,
		"seconds": 180,
		"ends": "score",
		"spawn": Vector3(0.5, Floor.FLOOR_Y + 2, 0.5),
	}))

	api.on("fairground:round_start", func(ev):
		if not _mine(ev):
			return
		pads.build(String(ev.instance))
		runs[String(ev.instance)] = {"phase": "asking", "until": 0.0, "count": 0, "used": {}}
		for p in ev.players:
			p.send_message("Read the question. Stand on the colour that is right."))

	api.on("fairground:round_tick", func(ev):
		if _mine(ev):
			_run(api, ev))

	api.on("fairground:round_end", func(ev):
		if _mine(ev):
			runs.erase(String(ev.instance)))


func _mine(ev) -> bool:
	return String(ev.game).ends_with(":answer")


## **Read from disk rather than written here**, so somebody who wants a different question does not
## have to find this file. A missing or broken file is said out loud and leaves the game registered
## with nothing to ask, which is better than a mod that fails to load over a typo in a word list.
func _read_questions(api) -> void:
	var path := "res://mods/wordgame/questions.json"
	var text := FileAccess.get_file_as_string(path)
	var doc = JSON.parse_string(text) if not text.is_empty() else null
	if not (doc is Dictionary) or not (doc.get("questions") is Array):
		api.warn("questions.json could not be read; there is nothing to ask")
		return
	for entry in doc.questions:
		if not (entry is Dictionary) or not (entry.get("answers") is Array):
			continue
		# **Four, not "at least two".** There are four squares and `_ask` fills all of them, so a question
		# with three answers indexed off the end of its own shuffle - a crash in the round rather than a
		# complaint at load, which is the wrong end to find it.
		if (entry.answers as Array).size() < Floor.PADS:
			api.warn("question \"%s\" has fewer than %d answers and was skipped" % [
				String(entry.get("ask", "?")), Floor.PADS])
			continue
		# A question with no level is the easiest, so a hand-written file that knows nothing about bands
		# still works and simply plays flat.
		var level := clampi(int(entry.get("level", 1)), 1, LEVELS)
		if not _bands.has(level):
			_bands[level] = []
		# **The key is the question *and* its answer**, not the question text. Seven spelling questions all
		# ask "Which is spelled correctly?", so keying on the text alone would have marked the other six
		# used the moment one of them was asked - a band of twelve behaving like a band of six.
		var answers: Array = (entry.answers as Array).duplicate()
		_bands[level].append({
			"ask": String(entry.get("ask", "?")),
			"answers": answers,
			"key": "%s / %s" % [String(entry.get("ask", "?")), String(answers[0])],
		})
		_total += 1
	api.info("%d questions across %d levels" % [_total, _bands.size()])


## Which band a round is on, and the nearest one that has anything in it.
##
## **Searches downwards first.** A file with a gap in it - or one that only fills three of the five
## bands - then plays as though the ramp simply stops where the questions stop, which is what somebody
## writing four levels expects. Only when there is nothing at or below the wanted level does it look
## up, so a file written entirely at level 5 is hard from the first question rather than silent.
func _band(count: int) -> Array:
	var want := clampi(1 + count / RAMP, 1, LEVELS)
	for level in range(want, 0, -1):
		if _bands.has(level) and not (_bands[level] as Array).is_empty():
			return _bands[level]
	for level in range(want + 1, LEVELS + 1):
		if _bands.has(level) and not (_bands[level] as Array).is_empty():
			return _bands[level]
	return []


## A round is a loop of two phases: asking, then the floor falling away.
func _run(api, ev) -> void:
	var run: Dictionary = runs.get(String(ev.instance), {})
	if run.is_empty() or _total == 0:
		return
	run.until = float(run.until) - 1.0
	if float(run.until) > 0.0:
		return
	if String(run.phase) == "asking":
		_judge(api, ev, run)
		run.phase = "settling"
		run.until = SETTLE
	else:
		_ask(ev, run)
		run.phase = "asking"
		run.until = THINKING


## Puts a question up and the squares back.
func _ask(ev, run: Dictionary) -> void:
	pads.reset(String(ev.instance))
	var band := _band(int(run.count))
	if band.is_empty():
		return
	run.count = int(run.count) + 1
	var q: Dictionary = _pick(band, run.used)
	# The right answer is always first in the file, so nobody writing a question has to think about
	# where to hide it. Shuffled here, which is the only place that should care.
	var order := range((q.answers as Array).size())
	order.shuffle()
	order = order.slice(0, Floor.PADS)
	var right_pad := order.find(0)
	if right_pad < 0:
		# The correct answer did not make the cut for this shuffle: put it on the first square rather
		# than asking a question with no right answer on the floor.
		right_pad = 0
		order[0] = 0
	run.right = right_pad
	var lines := []
	for pad in Floor.PADS:
		lines.append("%s: %s" % [Floor.colour_name(pad), String(q.answers[order[pad]])])
	for p in ev.players:
		p.show_title(String(q.ask), "  ".join(lines), THINKING)


## One question nobody has been asked yet this round.
##
## **A round used to repeat itself**, because the picker chose uniformly and a band of twelve gives a
## repeat inside fifteen questions more often than not - which reads as the game running out of ideas.
## Tried at random a few times and then walked, so the common case costs one draw and the last question
## in an exhausted band still finds itself rather than looping.
func _pick(band: Array, used: Dictionary) -> Dictionary:
	for _attempt in 8:
		var q: Dictionary = band[randi() % band.size()]
		if not used.has(q.key):
			used[q.key] = true
			return q
	for q: Dictionary in band:
		if not used.has(q.key):
			used[q.key] = true
			return q
	# Every question in this band has been asked. Better to ask one again than to stop the round.
	return band[randi() % band.size()]


## The floor falls away under everybody who is not on the right square.
func _judge(api, ev, run: Dictionary) -> void:
	if not run.has("right"):
		return
	var right := int(run.right)
	for pad in Floor.PADS:
		if pad == right:
			continue
		# **Taken away rather than made deadly.** A square that drops you is a consequence you watch
		# coming; a square that hurts you is a punishment. The Fairground turned fall damage off in the
		# arena, so the worst that happens is the walk back up.
		pads.clear_pad(String(ev.instance), pad)
	for p in ev.players:
		if p == null:
			continue
		if pads.pad_under(p.position) == right:
			ev.scores[p.player_id] = int(ev.scores.get(p.player_id, 0)) + 1
			p.show_title("", "Right", 1.5)
