class_name ScenarioOptions
extends RefCounted
## Explicit inspection execution and input provenance, validated before assembly.

enum Reaction { NONE, POP, PLATFORMS }
enum Lifecycle { ALL_ATTACHED, VISIBILITY }

var reactions: Reaction = Reaction.NONE
var lifecycle: Lifecycle = Lifecycle.ALL_ATTACHED
var collision_enabled_authored: bool = false
var authored_fixture: bool = false
var tick_limit_override: bool = false
var exploration_preset: String = ""
var entity_reactions: bool:
	get: return reactions != Reaction.NONE
var platforms_enabled: bool:
	get: return reactions == Reaction.PLATFORMS
var entity_lifecycle: bool:
	get: return lifecycle == Lifecycle.VISIBILITY

## Resolves explicit selections and fixture defaults, preserving command-line diagnostics.
func configure(scenario: TerrainScenario, reaction: String, lifetime: String, preset: String, requested_level: String, data_available: bool, seed_text: String, limit_text: String) -> String:
	exploration_preset = preset
	if not exploration_preset.is_empty() and exploration_preset not in [Jun1ExplorationSetup.PRESET, Org1ExplorationSetup.PRESET, Org1ExplorationSetup.ROAD_PRESET, Org1ExplorationSetup.VISIBILITY_PRESET]:
		return "exploration must be jun1-log-bank, org1-turtle-log-bank or org1-road-river"
	if not reaction.is_empty() and reaction not in ["pop", "platforms"]:
		return "entity-reactions must be pop or platforms"
	if not lifetime.is_empty() and lifetime not in ["all-attached", "visibility"]:
		return "entity-lifecycle must be all-attached or visibility"
	if not exploration_preset.is_empty():
		var required_level: String = "ORG1" if exploration_preset in [Org1ExplorationSetup.PRESET, Org1ExplorationSetup.ROAD_PRESET, Org1ExplorationSetup.VISIBILITY_PRESET] else "JUN1"
		if exploration_preset != Org1ExplorationSetup.VISIBILITY_PRESET and (lifetime == "visibility" or (scenario.entity_collision != null and scenario.entity_collision.lifecycle != null)):
			return exploration_preset + " cannot be combined with visibility lifecycle"
		if not reaction.is_empty() and reaction != "platforms":
			return exploration_preset + " requires platform reactions"
		if requested_level.to_upper() != required_level:
			return exploration_preset + " requires --level=" + required_level
		if not data_available:
			return exploration_preset + " requires player data"
		reaction = "platforms"
		if exploration_preset == Org1ExplorationSetup.VISIBILITY_PRESET and lifetime == "all-attached":
			return exploration_preset + " requires visibility lifecycle"
		lifetime = "visibility" if exploration_preset == Org1ExplorationSetup.VISIBILITY_PRESET else "all-attached"
	reactions = Reaction.POP if reaction in ["pop", "platforms"] or not lifetime.is_empty() or (scenario.entity_collision != null and scenario.entity_collision.lifecycle != null) else Reaction.NONE
	if entity_reactions and (reaction == "platforms" or (reaction.is_empty() and scenario.entity_collision != null and scenario.entity_collision.platforms_enabled)):
		reactions = Reaction.PLATFORMS
	lifecycle = Lifecycle.VISIBILITY if lifetime == "visibility" or (lifetime.is_empty() and scenario.entity_collision != null and scenario.entity_collision.lifecycle != null) else Lifecycle.ALL_ATTACHED
	if entity_lifecycle and scenario.level.camera == null:
		return "Visibility lifecycle requires a gameplay camera"
	if entity_lifecycle and scenario.entity_collision == null:
		if not data_available or (requested_level.is_empty() and scenario.level_code.is_empty()):
			return "Visibility lifecycle requires an authored entity fixture or player data with --level"
	scenario.level.entity_collision = scenario.entity_collision.copy() if entity_reactions and scenario.entity_collision != null else null
	if scenario.level.entity_collision != null:
		scenario.level.entity_collision.platforms_enabled = platforms_enabled
		if entity_lifecycle and scenario.level.entity_collision.lifecycle == null:
			return "Visibility lifecycle requires map-group polygon counts"
		if not entity_lifecycle:
			scenario.level.entity_collision.lifecycle = null
	if entity_reactions and scenario.entity_collision != null:
		if collision_enabled_authored and not scenario.level.collision_enabled:
			return "Entity reaction scenario requires collision_enabled=true"
		scenario.level.collision_enabled = true
	for key: String in ["seed", "tick-limit"]:
		var text: String = seed_text if key == "seed" else limit_text
		if text.is_empty():
			continue
		if not text.is_valid_int():
			return "%s must be an integer" % key
		var number: int = text.to_int()
		if key == "seed":
			if number < 0 or number > 0xffffffff:
				return "seed must be in 0..4294967295"
			scenario.initial.seed = number
		else:
			if number < 0 or number > 100000:
				return "tick-limit must be in 0..100000"
			scenario.tick_limit = number
			tick_limit_override = true
	return ""

