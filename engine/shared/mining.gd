extends RefCounted
## Timed block breaking, shared by the server (validation) and the client (prediction and the crack
## animation). Blocks define `hardness` (seconds to break by hand ~ hardness * 1.5), `tier` (the tool
## tier needed to get drops) and `tool` (the tool type that is effective). Tools define `type`,
## `tier` and `speed` (a multiplier on breaking speed when the type matches).
##
##   dirt (0.5, shovel) by hand: 0.75 s     stone (1.5, pickaxe, tier 1) by hand: 7.5 s, no drops
##   stone with a wooden pickaxe (tier 1, speed 2): 1.1 s

const HAND_FACTOR := 1.5
## Mining a block the tool is too weak for takes this much longer (and yields nothing).
const WRONG_TIER_PENALTY := 3.3


## Seconds to break `block` (a BlockRegistry def) holding `tool` ({type, tier, speed} or {}),
## with the player's `mining_speed` stat. 0 = instant.
static func break_time(block: Dictionary, tool: Dictionary, mining_speed := 1.0) -> float:
	var hardness := float(block.get("hardness", 0.0))
	if hardness <= 0.0:
		return 0.0
	var speed := 1.0
	var effective := not String(block.get("tool", "")).is_empty() and String(tool.get("type", "")) == String(block.get("tool", ""))
	if effective:
		speed = maxf(float(tool.get("speed", 1.0)), 0.1)
	var seconds := hardness * HAND_FACTOR / (speed * maxf(mining_speed, 0.05))
	if not can_harvest(block, tool):
		seconds *= WRONG_TIER_PENALTY
	return seconds


## True if breaking the block with this tool yields its drops.
static func can_harvest(block: Dictionary, tool: Dictionary) -> bool:
	var tier := int(block.get("tier", 0))
	if tier <= 0:
		return true
	return String(tool.get("type", "")) == String(block.get("tool", "")) and int(tool.get("tier", 0)) >= tier


## Crack animation stage 0-9 for progress 0-1.
static func stage(progress: float) -> int:
	return clampi(floori(progress * 10.0), 0, 9)
