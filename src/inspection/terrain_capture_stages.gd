class_name TerrainCaptureStages
extends RefCounted
## Inspection-specific capture milestones, separate from the reusable viewer.

## Returns route milestones at the observed state.
static func platform(scenario: TerrainScenario, state: GameplayState) -> Array[String]:
	var platform_stages: Array[String] = []
	if scenario.options.exploration_preset in [Org1ExplorationSetup.PRESET, Org1ExplorationSetup.VISIBILITY_PRESET]:
		var stages: Dictionary[int, String] = {4: "org1-turtle-out", 19: "org1-log", 40: "org1-turtle-return", 52: "org1-bank-return", 60: "org1-diving", 90: "org1-rising", 1234: "org1-diver-attachment", 1255: "org1-diver-drowning"}
		if scenario.options.entity_lifecycle:
			stages[174] = "org1-diver-attachment"
			stages[203] = "org1-diver-drowning"
			stages[445] = "org1-pink-contact"
			stages[446] = "org1-pink-pickup"
			stages[460] = "org1-pink-riding"
			stages[469] = "org1-pink-death"
		if stages.has(state.tick_index):
			platform_stages.append(stages[state.tick_index])
	elif scenario.options.exploration_preset == Org1ExplorationSetup.ROAD_PRESET:
		if state.tick_index == 1:
			platform_stages.append("org1-road-start")
		if state.frog.cell.y >= 2 and state.frog.cell.y <= 6:
			platform_stages.append("org1-road-traffic")
		if state.frog.cell.y == 7 and state.frog.mode == 0:
			platform_stages.append("org1-road-bank")
		if state.attachment.current_entity_index >= 0 and state.attachment.current_entity_index < 24:
			platform_stages.append("org1-road-river")
		if state.attachment.death_entity_index >= 24 and state.attachment.death_entity_index <= 47:
			platform_stages.append("org1-road-vehicle-death")
	elif scenario.level.tick_guard != null:
		if state.tick_index == 3:
			platform_stages.append("platform-approach")
		if state.tick_index == 8:
			platform_stages.append("platform-centring")
		if state.tick_index == 12:
			platform_stages.append("platform-carry")
		if state.tick_index == 18:
			platform_stages.append("platform-safe-return")
	return platform_stages

## Selects the authored pre-contact frame where a preset requires one.
static func before_contact(scenario: TerrainScenario, state: GameplayState) -> bool:
	return scenario.level_code.to_upper() != "DES2" or state.tick_index == 4

## Whether entity lighting is part of the selected inspection contract.
static func entity_lighting(scenario: TerrainScenario) -> bool:
	return scenario.options.scripted_entities

## Route-specific overlay wording for the bounded inspection.
static func overlay(scenario: TerrainScenario) -> Dictionary[String, String]:
	if scenario.options.exploration_preset == Org1ExplorationSetup.ROAD_PRESET:
		return {"title": "ORG1 ROAD / RIVER EXPLORATION", "instructions": "Cross traffic north to the bank, then turtle and log.\n", "detail": "road"}
	if scenario.options.exploration_preset in [Org1ExplorationSetup.PRESET, Org1ExplorationSetup.VISIBILITY_PRESET]:
		return {"title": "ORG1 BANK / TURTLE / LOG EXPLORATION", "instructions": "Hop Up to turtle, Up to log; return Down twice.\n", "detail": "river"}
	return {"title": "JUN1 BANK / LOG EXPLORATION", "instructions": "From reset: Left onto log, then Right after centring.\n", "detail": "river"}
