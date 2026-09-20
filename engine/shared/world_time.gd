extends RefCounted
## Day/night helpers shared by server and client. time_of_day: 0 = midnight, 0.25 = sunrise,
## 0.5 = noon, 0.75 = sunset.

const NIGHT_LIGHT := 0.12


## Sky light multiplier in [NIGHT_LIGHT, 1].
static func daylight(time_of_day: float) -> float:
	return clampf(0.5 + sin((time_of_day - 0.25) * TAU) * 1.4, NIGHT_LIGHT, 1.0)


## Which quarter of the day it is, as a word: "night", "dawn", "day", "dusk". Named here rather than in
## whichever mod asked first, so two mods cannot disagree about when dusk begins.
static func phase(time_of_day: float) -> String:
	var t := fposmod(time_of_day, 1.0)
	if t < 0.2 or t >= 0.8:
		return "night"
	if t < 0.3:
		return "dawn"
	return "day" if t < 0.7 else "dusk"
