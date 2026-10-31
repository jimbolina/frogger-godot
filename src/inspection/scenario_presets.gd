class_name ScenarioPresets
extends RefCounted
## Per-level and per-exploration inspection data: bounded level starts, the
## preferred inspection entity, capture milestones and overlay wording.

## Bounded entity-inspection starts by level code. `needs` is the reaction
## option that selects the start ("reactions" or "platforms"); a start that
## needs platforms also keeps platform runs on the bounded inspection path.
## `press` is the first tick's buttons. `contact_tick` is the authored
## pre-contact capture frame, or -1 when any tick before contact qualifies.
const LEVEL_STARTS: Dictionary[String, Dictionary] = {
	"DES2": {"needs": "reactions", "cell": Vector2i(17, 30), "direction": 1, "ticks": 80, "press": TickCommand.EAST, "contact_tick": 4, "diagnostic": ""},
	"JUN1": {"needs": "platforms", "cell": Vector2i(18, 5), "direction": 0, "ticks": 90, "press": TickCommand.NORTH, "contact_tick": -1,
		"diagnostic": "JUN1 inspection starts on authored water cell (18,5); no playable safe-bank route is implied"},
}

## Authored entity identities that viewers select first, by level code.
const PREFERRED_ENTITIES: Dictionary[String, int] = {"ORG1": 12}

## Exploration presets by name: the level each requires, whether it runs
## entity scripts, the preset whose capture milestones it extends (`base`), its own
## milestones as [stage, probe, minimum, maximum] rows, and its overlay text.
## Probes: `tick`, `cell_y`, `idle_cell_y` (cell row while the frog stands),
## `platform` (attached entity) and `killer` (lethal entity).
const EXPLORATIONS: Dictionary[String, Dictionary] = {
	"jun1-log-bank": {"level": "JUN1", "scripted": false, "base": "",
		"stages": [["platform-approach", "tick", 3, 3], ["platform-centring", "tick", 8, 8], ["platform-carry", "tick", 12, 12], ["platform-safe-return", "tick", 18, 18]],
		"title": "JUN1 BANK / LOG EXPLORATION", "instructions": "From reset: Left onto log, then Right after centring.\n", "detail": "river"},
	"org1-turtle-log-bank": {"level": "ORG1", "scripted": true, "base": "",
		"stages": [["org1-turtle-out", "tick", 4, 4], ["org1-log", "tick", 19, 19], ["org1-turtle-return", "tick", 40, 40], ["org1-bank-return", "tick", 52, 52],
			["org1-diving", "tick", 60, 60], ["org1-rising", "tick", 90, 90], ["org1-diver-attachment", "tick", 1234, 1234], ["org1-diver-drowning", "tick", 1255, 1255]],
		"title": "ORG1 BANK / TURTLE / LOG EXPLORATION", "instructions": "Hop Up to turtle, Up to log; return Down twice.\n", "detail": "river"},
	"org1-turtle-log-bank-visibility": {"level": "ORG1", "scripted": true, "base": "org1-turtle-log-bank",
		"stages": [["org1-diver-attachment", "tick", 174, 174], ["org1-diver-drowning", "tick", 203, 203], ["org1-pink-contact", "tick", 445, 445],
			["org1-pink-pickup", "tick", 446, 446], ["org1-pink-riding", "tick", 460, 460], ["org1-pink-death", "tick", 469, 469]],
		"title": "ORG1 BANK / TURTLE / LOG EXPLORATION", "instructions": "Hop Up to turtle, Up to log; return Down twice.\n", "detail": "river"},
	"org1-road-river": {"level": "ORG1", "scripted": true, "base": "",
		"stages": [["org1-road-start", "tick", 1, 1], ["org1-road-traffic", "cell_y", 2, 6], ["org1-road-bank", "idle_cell_y", 7, 7],
			["org1-road-river", "platform", 0, 23], ["org1-road-vehicle-death", "killer", 24, 47]],
		"title": "ORG1 ROAD / RIVER EXPLORATION", "instructions": "Cross traffic north to the bank, then turtle and log.\n", "detail": "road"},
}

## The bounded start for [param level_code], or an empty dictionary.
static func level_start(level_code: String) -> Dictionary:
	return LEVEL_STARTS.get(level_code.to_upper(), {})

## Whether [param level_code]'s bounded start is selected by platform
## reactions rather than by any entity reactions.
static func start_needs_platforms(level_code: String) -> bool:
	return level_start(level_code).get("needs", "") == "platforms"

## The authored identity to prefer for [param level_code], or -1.
static func preferred_entity_id(level_code: String) -> int:
	return PREFERRED_ENTITIES.get(level_code.to_upper(), -1)

## The level code exploration [param preset] requires, or "" for an unknown preset.
static func exploration_level(preset: String) -> String:
	var entry: Dictionary = EXPLORATIONS.get(preset, {})
	return entry.get("level", "")

## Whether exploration [param preset] runs entity scripts and custom updates.
static func exploration_scripted(preset: String) -> bool:
	var entry: Dictionary = EXPLORATIONS.get(preset, {})
	return entry.get("scripted", false)

## The milestone rows of [param preset], including those it extends.
static func capture_stages(preset: String) -> Array:
	var entry: Dictionary = EXPLORATIONS.get(preset, {})
	if entry.is_empty():
		return []
	var base: String = entry.base
	var own: Array = entry.stages
	var rows: Array = capture_stages(base) if not base.is_empty() else []
	rows.append_array(own)
	return rows

## Overlay title, instructions and detail for [param preset]; the JUN1 wording
## for any preset without its own.
static func overlay(preset: String) -> Dictionary[String, String]:
	var entry: Dictionary = EXPLORATIONS.get(preset, EXPLORATIONS["jun1-log-bank"])
	var result: Dictionary[String, String] = {}
	for key: String in ["title", "instructions", "detail"]:
		result[key] = entry[key]
	return result
