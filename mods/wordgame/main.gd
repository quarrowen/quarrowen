extends "res://engine/server/mod.gd"
## Stand On The Answer: a question, four coloured squares, and the wrong three fall away.
##
## **The world has no text in it**, which is the first thing this game had to solve. There is no way to
## write "because" on a block, so the answers are read out in the title text and the squares are
## *coloured* - "stand on crimson". `base` ships sixteen hues whose names were deliberately chosen to be
## sayable by an eight-year-old, which is exactly the vocabulary this needs. (2026-09-28)
##
## **The questions are a JSON file** (the user, 28 September 2026: make it data, so the children can
## write their own). Nothing in this file names a single question, and adding one needs no code.
##
## **It is worth playing alone**, like everything at the Fairground: a solo round is an answer streak
## against the clock rather than a race, and scoring rather than elimination means a wrong answer costs
## you the question and not the game.

const Floor = preload("res://mods/wordgame/floor.gd")

## How long there is to read the question and get somewhere. Generous: this is not a reflex game, and a
## child sounding out "b-e-c-a-u-s-e" needs longer than one who can already spell it.
const THINKING := 9.0
## And how long the answer stays up before the next question.
const SETTLE := 3.0

var pads := Floor.new()
## instance id -> {question, answers, right, phase, until, asked}
var runs := {}

var _questions: Array = []


func setup(api) -> void:
	_questions = _read_questions(api)
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
		runs[String(ev.instance)] = {"phase": "asking", "until": 0.0, "asked": -1}
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
func _read_questions(api) -> Array:
	var path := "res://mods/wordgame/questions.json"
	var text := FileAccess.get_file_as_string(path)
	var doc = JSON.parse_string(text) if not text.is_empty() else null
	if not (doc is Dictionary) or not (doc.get("questions") is Array):
		api.warn("questions.json could not be read; there is nothing to ask")
		return []
	var out := []
	for entry in doc.questions:
		if entry is Dictionary and entry.get("answers") is Array and (entry.answers as Array).size() >= 2:
			out.append({"ask": String(entry.get("ask", "?")), "answers": (entry.answers as Array).duplicate()})
	api.info("%d questions" % out.size())
	return out


## A round is a loop of two phases: asking, then the floor falling away.
func _run(api, ev) -> void:
	var run: Dictionary = runs.get(String(ev.instance), {})
	if run.is_empty() or _questions.is_empty():
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
	var index := randi() % _questions.size()
	var q: Dictionary = _questions[index]
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


## The floor falls away under everybody who is not on the right square.
func _judge(api, ev, run: Dictionary) -> void:
	if not run.has("right"):
		return
	var right := int(run.right)
	for pad in Floor.PADS:
		if pad == right:
			continue
		# **Taken away rather than made deadly.** A square that drops you is a consequence a child can
		# see coming and laugh at; a square that hurts you is a punishment. The Fairground turned fall
		# damage off in the arena, so the worst that happens is the walk back up.
		pads.clear_pad(String(ev.instance), pad)
	for p in ev.players:
		if p == null:
			continue
		if pads.pad_under(p.position) == right:
			ev.scores[p.player_id] = int(ev.scores.get(p.player_id, 0)) + 1
			p.show_title("", "Right", 1.5)
