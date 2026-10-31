class_name TerrainCaptureStages
extends RefCounted
## Inspection-specific capture milestones, separate from the reusable viewer;
## the milestones and wording come from [ScenarioPresets].

## Returns the selected exploration's milestones reached at the observed state.
static func platform(scenario: TerrainScenario, state: GameplayState) -> Array[String]:
	var platform_stages: Array[String] = []
	for value: Variant in ScenarioPresets.capture_stages(scenario.options.exploration_preset):
		var row: Array = value
		var stage: String = row[0]
		var probe: String = row[1]
		var low: int = row[2]
		var high: int = row[3]
		var observed: int = _probe(probe, state)
		if observed >= low and observed <= high:
			platform_stages.append(stage)
	return platform_stages

## Selects the authored pre-contact frame where a level start requires one.
static func before_contact(scenario: TerrainScenario, state: GameplayState) -> bool:
	var contact_tick: int = ScenarioPresets.level_start(scenario.level_code).get("contact_tick", -1)
	return contact_tick < 0 or state.tick_index == contact_tick

## Whether entity lighting is part of the selected inspection contract.
static func entity_lighting(scenario: TerrainScenario) -> bool:
	return scenario.options.scripted_entities

## Route-specific overlay wording for the bounded inspection.
static func overlay(scenario: TerrainScenario) -> Dictionary[String, String]:
	return ScenarioPresets.overlay(scenario.options.exploration_preset)

static func _probe(probe: String, state: GameplayState) -> int:
	match probe:
		"tick":
			return state.tick_index
		"cell_y":
			return state.frog.cell.y
		"idle_cell_y":
			return state.frog.cell.y if state.frog.mode == 0 else -1
		"platform":
			return state.attachment.current_entity_index
		"killer":
			return state.attachment.death_entity_index
	return -1
