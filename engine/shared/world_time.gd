extends RefCounted
## Day/night helpers shared by server and client. time_of_day: 0 = midnight, 0.25 = sunrise,
## 0.5 = noon, 0.75 = sunset.

const NIGHT_LIGHT := 0.12


## Sky light multiplier in [NIGHT_LIGHT, 1].
static func daylight(time_of_day: float) -> float:
	return clampf(0.5 + sin((time_of_day - 0.25) * TAU) * 1.4, NIGHT_LIGHT, 1.0)
