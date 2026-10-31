class_name EntitySetup
extends RefCounted
## Resolves authored map entities into detached base-transform definitions.

## Path movers that frozen ENTSTRUpdateMovingMOF projects onto the landscape.
const PROJECTED_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.PATH_FOLLOWER, EntityBehavior.Kind.FIREFLY, EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.HEDGEHOG, EntityBehavior.Kind.SWP_SLUG, EntityBehavior.Kind.NUCLEAR_BARREL]

## Desert path runners decoded from PATH_INFO alone.
const DESERT_PATH_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.DES_ROLLING_ROCK, EntityBehavior.Kind.DES_TUMBLE_WEED, EntityBehavior.Kind.DES_SNAKE, EntityBehavior.Kind.DES_VULTURE]
## Desert matrix entities with FrogLord subtype payloads after the matrix.
const DESERT_MATRIX_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.DES_FALLING_ROCK, EntityBehavior.Kind.DES_CROC_HEAD, EntityBehavior.Kind.DES_CRACK]
## FrogLord DESERT_FALLING_ROCK size and DESERT_FALLING_ROCK_TARGETS stride.
const FALLING_ROCK_SIZE: int = 188
const ROCK_TARGET_STRIDE: int = 12
## Jungle matrix entities with FrogLord subtype payloads after the matrix.
const JUNGLE_PAYLOAD_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.JUN_PLANT, EntityBehavior.Kind.JUN_ROPE_BRIDGE, EntityBehavior.Kind.JUN_OUTRO, EntityBehavior.Kind.JUN_PLINTH, EntityBehavior.Kind.JUN_GOLD_FROG, EntityBehavior.Kind.JUN_STONE_FROG]
## FrogLord JUN_OUTRO_ENTITY size and JUN_OUTRO_TARGETS stride.
const OUTRO_SIZE: int = 164
const OUTRO_TARGET_STRIDE: int = 12
## Swamp matrix entities with FrogLord subtype payloads after the matrix.
const SWAMP_PAYLOAD_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.SWP_SQUIRT, EntityBehavior.Kind.SWP_CRUSHER, EntityBehavior.Kind.SWP_PRESS, EntityBehavior.Kind.SWP_RAT]
## FrogLord SWAMP_SQUIRT, SWAMP_CRUSHER/SWAMP_PRESS, SWAMP_RAT and SWAMP_SLUG sizes.
const SQUIRT_SIZE: int = 44
const CRUSHER_SIZE: int = 40
const RAT_SIZE: int = 68
const SLUG_SIZE: int = 16
## Source SWP_WEIR_ROTATION applied about Z by ENTSTRSwpCreateWeir before the model is built.
const WEIR_ROTATION: int = 1024
## Entries in the source jun_plinth_table.
const PLINTH_TABLE_SIZE: int = 9
## SUBURBIA_TURTLE size: PATH_INFO then dive delay, rise delay and type words.
const SUBURBIA_TURTLE_SIZE: int = 24

var definitions: Array[EntityDefinition] = []
var diagnostics: Array[EntitySetupDiagnostic] = []
## Structural setup error; individual unsupported records use diagnostics.
var error: String = ""

## Resolves source-ordered entity spans and attaches validated source paths; supplied names report entity-type overrides.
static func from_map(map: MapFile, theme_book: ThemeBook, source_id: String = "", resource_id: int = -1, build_id: String = "", custom_behaviors_enabled: bool = false, names: GameNameLists = null) -> EntitySetup:
	var result := EntitySetup.new()
	if map == null or theme_book == null:
		result.error = "Entity setup requires a map and theme book"
		return result
	if not map.error.is_empty() or not theme_book.error.is_empty():
		result.error = "Cannot set up entities from invalid data: %s %s" % [map.error, theme_book.error]
		return result
	var packet: MapPacket = map.packets.get("EMTP")
	if packet == null or packet.count != map.entities.size() or packet.offsets.size() != packet.count:
		result.error = "EMTP record count does not match its pointer table"
		return result
	for index: int in map.entities.size():
		var span: MapEntitySpan = map.entities[index]
		if span == null or span.source_offset != packet.offsets[index]:
			result.error = "EMTP source identity does not match its pointer table"
			return result
	var paths: PathSetup = PathSetup.from_map(map, source_id, resource_id, build_id)
	if not paths.error.is_empty():
		result.error = paths.error
		return result
	var by_source_index: Dictionary[int, PathDefinition] = {}
	for path: PathDefinition in paths.definitions:
		by_source_index[path.path_index] = path
	for index: int in map.entities.size():
		var span: MapEntitySpan = map.entities[index]
		var form: FormBookEntry = theme_book.get_form(map.general.theme, span.form_id)
		if form == null:
			result._issue("invalid_form", "Form id does not resolve in the map theme", span, null, index, source_id, resource_id, build_id)
			continue
		if form.entity_name == "MULTIPOINT":
			result._issue("multiplayer_only", "MULTIPOINT requires multiplayer checkpoint rules", span, form, index, source_id, resource_id, build_id)
			continue
		if span.flags & ~127:
			result._issue("unknown_flags", "Entity has unknown flags 0x%X" % span.flags, span, form, index, source_id, resource_id, build_id)
			continue
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(form.entity_name)
		if (span.flags & 64 and (span.flags & 32 or not (custom_behaviors_enabled and behavior.kind in EntityRun.LOCALLY_ALIGNED_KINDS))) or (span.flags & 32 and not (custom_behaviors_enabled and behavior.kind in PROJECTED_KINDS)):
			result._issue("unsupported_transform", "PROJECT_ON_LAND or LOCAL_ALIGN transform is unsupported", span, form, index, source_id, resource_id, build_id)
			continue
		var definition := EntityDefinition.new()
		definition.source_id = source_id
		definition.build_id = build_id
		definition.resource_id = resource_id
		definition.entity_index = index
		definition.source_offset = span.source_offset
		definition.unique_id = span.unique_id
		definition.form_grid_id = span.form_grid_id
		definition.form_id = span.form_id
		definition.form_name = form.form_name
		definition.radius_squared = form.radius_squared
		definition.entity_name = form.entity_name
		definition.behavior = behavior
		definition.script_id = form.script_id
		definition.collision_callback = form.collision_callback
		definition.bonus_callback = form.bonus_callback
		definition.bonus_kind = FormCallbackCatalog.resolve(build_id, form.bonus_callback, true)
		if (FormCallbackCatalog.resolve(build_id, form.collision_callback) == FormCallback.Kind.VOL_COLOUR_SWITCH or definition.bonus_kind == FormCallback.Kind.VOL_COLOUR_SWITCH) and definition.behavior.kind != EntityBehavior.Kind.VOL_COLOUR_SWITCH:
			result._issue("incompatible_callback", "Colour-switch callback requires colour-switch behavior and payload", span, form, index, source_id, resource_id, build_id)
			continue
		if (FormCallbackCatalog.resolve(build_id, form.collision_callback) == FormCallback.Kind.TRIGGER or definition.bonus_kind == FormCallback.Kind.TRIGGER) and definition.behavior.kind != EntityBehavior.Kind.TRIGGER:
			result._issue("incompatible_callback", "Trigger callback requires trigger behavior and payload", span, form, index, source_id, resource_id, build_id)
			continue
		if definition.behavior.kind == EntityBehavior.Kind.FIREFLY and definition.bonus_kind == FormCallback.Kind.NONE:
			result._issue("incompatible_callback", "Firefly requires a verified bonus callback", span, form, index, source_id, resource_id, build_id)
			continue
		definition.form_flags = form.flags
		definition.flags = span.flags
		if definition.bonus_kind == FormCallback.Kind.BUTTERFLY_SCORE or FormCallbackCatalog.resolve(build_id, definition.collision_callback, false) == FormCallback.Kind.BUTTERFLY_SCORE:
			if span.payload.size() < 14 or span.payload.decode_u16(12) >= EntityBonusFly.REWARD_IDS.size():
				result._issue("invalid_payload", "Butterfly score callback requires an unsigned type from 0 through 18 at payload offset 12", span, form, index, source_id, resource_id, build_id)
				continue
			definition.butterfly_type = span.payload.decode_u16(12)
		if definition.behavior.layout == EntityBehavior.Layout.MATRIX and (definition.behavior.kind == EntityBehavior.Kind.STATIC or custom_behaviors_enabled):
			var matrix: MapEntityPayload = MapEntityPayload.read_matrix(span)
			if not matrix.error.is_empty():
				result._issue("invalid_payload", matrix.error, span, form, index, source_id, resource_id, build_id)
				continue
			if definition.behavior.kind == EntityBehavior.Kind.PICKUP:
				if span.payload.size() < 34 or span.payload.decode_u16(32) > 18:
					result._issue("invalid_payload", "BONUS_FLY requires a pickup type from 0 through 18", span, form, index, source_id, resource_id, build_id)
					continue
				definition.pickup_type = span.payload.decode_u16(32)
			if definition.behavior.kind == EntityBehavior.Kind.TRIGGER:
				var trigger_issue: String = _trigger_payload(definition, span.payload)
				if not trigger_issue.is_empty():
					result._issue("invalid_payload", trigger_issue, span, form, index, source_id, resource_id, build_id)
					continue
			definition.matrix12 = matrix.matrix12.duplicate()
			definition.behavior.execution = EntityBehavior.Execution.UPDATE if custom_behaviors_enabled else EntityBehavior.Execution.TRANSFORM
			if definition.behavior.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.LOG_SNAKE] and span.payload.size() >= 36:
				definition.parent_unique_id = span.payload.decode_s16(32)
				if definition.behavior.kind == EntityBehavior.Kind.LOG_SNAKE:
					definition.movement_speed = span.payload.decode_u16(34)
		elif definition.behavior.kind == EntityBehavior.Kind.PATH_FOLLOWER or (custom_behaviors_enabled and definition.behavior.kind in [EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.TURTLE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.DOG, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.HEDGEHOG, EntityBehavior.Kind.FIREFLY] + DESERT_PATH_KINDS + EntityBehavior.JUNGLE_PATH_KINDS + EntityBehavior.SWAMP_PATH_KINDS):
			var info: MapEntityPayload = MapEntityPayload.read_path_info(span)
			if not info.error.is_empty():
				result._issue("invalid_payload", info.error, span, form, index, source_id, resource_id, build_id)
				continue
			if info.motion_flags & ~14:
				result._issue("unsupported_motion_flags", "PATH_INFO has unsupported motion flags 0x%X" % info.motion_flags, span, form, index, source_id, resource_id, build_id)
				continue
			if not by_source_index.has(info.path_index):
				result._issue("invalid_path", "PATH_INFO path index %d is absent or unsupported" % info.path_index, span, form, index, source_id, resource_id, build_id)
				continue
			definition.path_definition = by_source_index[info.path_index].copy()
			var start := PathStart.new()
			start.segment_index = info.segment_index
			start.distance = info.segment_distance
			start.speed = info.speed
			start.flags = PathStart.ACTIVE | info.motion_flags
			if span.flags & 4:
				start.flags &= ~PathStart.ACTIVE
			var runner: PathRunner = PathRunner.create(definition.path_definition, start)
			if not runner.error.is_empty():
				result._issue("invalid_path_start", runner.error, span, form, index, source_id, resource_id, build_id)
				continue
			definition.path_start = start
			if definition.behavior.kind == EntityBehavior.Kind.DOG:
				if span.payload.size() < 16:
					result._issue("invalid_payload", "Dog requires its unsigned wait delay", span, form, index, source_id, resource_id, build_id)
					continue
				definition.authored_delay = span.payload.decode_u32(12)
				definition.behavior.execution = EntityBehavior.Execution.UPDATE
			if definition.behavior.kind == EntityBehavior.Kind.BEAVER:
				if span.payload.size() < 16 or not definition.path_definition.entity_list_error.is_empty():
					result._issue("invalid_payload", "Beaver requires its delay and a valid PATH entity list", span, form, index, source_id, resource_id, build_id)
					continue
				definition.authored_delay = span.payload.decode_s16(12)
				definition.behavior.execution = EntityBehavior.Execution.UPDATE
			if definition.behavior.kind in DESERT_PATH_KINDS:
				definition.behavior.execution = EntityBehavior.Execution.UPDATE
			if definition.behavior.kind == EntityBehavior.Kind.JUN_HIPPO and span.payload.size() < SUBURBIA_TURTLE_SIZE:
				result._issue("invalid_payload", "Jungle hippo requires PATH_INFO, dive and rise delays and its turtle type", span, form, index, source_id, resource_id, build_id)
				continue
			if definition.behavior.kind == EntityBehavior.Kind.SWP_SLUG:
				if span.payload.size() < SLUG_SIZE:
					result._issue("invalid_payload", "Swamp slug requires PATH_INFO and its motion type", span, form, index, source_id, resource_id, build_id)
					continue
				definition.swamp = EntitySwampDefinition.new()
				definition.swamp.motion_type = span.payload.decode_u32(12)
		else:
			result._issue("unknown_behavior", "No base-transform decoder for entity name %s" % form.entity_name, span, form, index, source_id, resource_id, build_id)
			continue
		if definition.behavior.kind in [EntityBehavior.Kind.HIVE, EntityBehavior.Kind.BREAKING_BRANCH, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.HEDGEHOG]:
			var payload_issue: String = _forest_payload(definition, span.payload)
			if not payload_issue.is_empty():
				result._issue("invalid_payload", payload_issue, span, form, index, source_id, resource_id, build_id)
				continue
			definition.behavior.execution = EntityBehavior.Execution.UPDATE
		if definition.behavior.kind in [EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.VOL_COLOUR_SWITCH, EntityBehavior.Kind.VOL_FALLING_PLATFORM]:
			var payload_issue: String = _volcano_payload(definition, span.payload)
			if not payload_issue.is_empty():
				result._issue("invalid_payload", payload_issue, span, form, index, source_id, resource_id, build_id)
				continue
			definition.volcano.play_chain_sound = map.general.theme == FroggerIds.THEMES.find("VOLCANO")
			definition.behavior.execution = EntityBehavior.Execution.UPDATE
		if definition.behavior.kind in [EntityBehavior.Kind.CAVE_LIGHT, EntityBehavior.Kind.FAT_FIRE_FLY]:
			var payload_issue: String = _cave_payload(definition, span.payload)
			if not payload_issue.is_empty():
				result._issue("invalid_payload", payload_issue, span, form, index, source_id, resource_id, build_id)
				continue
			definition.behavior.execution = EntityBehavior.Execution.UPDATE
		if definition.behavior.kind in DESERT_MATRIX_KINDS:
			var payload_issue: String = _desert_payload(definition, span.payload)
			if not payload_issue.is_empty():
				result._issue("invalid_payload", payload_issue, span, form, index, source_id, resource_id, build_id)
				continue
			definition.behavior.execution = EntityBehavior.Execution.UPDATE
		if definition.behavior.kind in JUNGLE_PAYLOAD_KINDS:
			var payload_issue: String = _jungle_payload(definition, span.payload)
			if not payload_issue.is_empty():
				result._issue("invalid_payload", payload_issue, span, form, index, source_id, resource_id, build_id)
				continue
		if definition.behavior.kind in SWAMP_PAYLOAD_KINDS:
			var payload_issue: String = _swamp_payload(definition, span.payload)
			if not payload_issue.is_empty():
				result._issue("invalid_payload", payload_issue, span, form, index, source_id, resource_id, build_id)
				continue
		if definition.behavior.kind == EntityBehavior.Kind.SWP_STAT_WEIR:
			definition.matrix12 = weir_matrix(definition.matrix12)
		result.definitions.append(definition)
		var stored_type: String = _stored_entity_name(names, form)
		if stored_type != form.entity_name:
			result._issue("entity_override", "FrogLord names this form %s; the executable entity type is %s" % [form.entity_name, stored_type], span, form, index, source_id, resource_id, build_id, false)
		if form.script_id != 0 or form.collision_callback != 0 or form.bonus_callback != 0:
			result._issue("unexecuted_hooks", "Script or callback addresses are retained but unexecuted in base-transform inspection", span, form, index, source_id, resource_id, build_id, false)
	return result

func _issue(code: String, message: String, span: MapEntitySpan, form: FormBookEntry, index: int, source_id: String, resource_id: int, build_id: String, omitted: bool = true) -> void:
	var diagnostic := EntitySetupDiagnostic.new()
	diagnostic.code = code
	diagnostic.source_id = source_id
	diagnostic.resource_id = resource_id
	diagnostic.build_id = build_id
	diagnostic.entity_index = index
	diagnostic.form_id = span.form_id
	diagnostic.form_name = form.form_name if form != null else ""
	diagnostic.source_offset = span.source_offset
	diagnostic.message = message
	diagnostic.fallback = "Entity omitted; valid neighbors remain" if omitted else "Base transform remains available for inspection"
	diagnostics.append(diagnostic)

## Decodes Forest subtype operands after their validated matrix or path prefix.
static func _forest_payload(definition: EntityDefinition, payload: PackedByteArray) -> String:
	var forest := EntityForestDefinition.new()
	match definition.behavior.kind:
		EntityBehavior.Kind.HIVE:
			if payload.size() < 40:
				return "Hive requires release distance and swarm speed"
			forest.release_distance = payload.decode_s32(32)
			forest.swarm_speed = payload.decode_s32(36)
		EntityBehavior.Kind.BREAKING_BRANCH:
			if payload.size() < 36:
				return "Breaking branch requires its delay and fall-speed record"
			definition.authored_delay = payload.decode_u16(32)
		EntityBehavior.Kind.SQUIRREL:
			if payload.size() < 16:
				return "Squirrel requires its authored turn duration"
			definition.authored_delay = payload.decode_s32(12)
		EntityBehavior.Kind.HEDGEHOG:
			if payload.size() < 20:
				return "Hedgehog requires run/roll timing and speeds"
			forest.run_time = payload.decode_u16(12)
			forest.roll_time = payload.decode_u16(14)
			forest.run_speed = payload.decode_u16(16)
			forest.roll_speed = payload.decode_u16(18)
	definition.forest = forest
	return ""

## Copies FrogLord Volcano subtype operands into detached behavior definitions.
static func _volcano_payload(definition: EntityDefinition, payload: PackedByteArray) -> String:
	var volcano := EntityVolcanoDefinition.new()
	match definition.behavior.kind:
		EntityBehavior.Kind.MOVING_PLATFORM:
			if payload.size() < 12:
				return "Moving platform requires PATH_INFO"
			volcano.initial_movement = payload.decode_u32(12) if payload.size() >= 16 else 0
		EntityBehavior.Kind.VOL_COLOUR_SWITCH:
			if payload.size() < 56:
				return "Colour switch requires its type, colour and ten target IDs"
			volcano.trigger_type = payload.decode_u16(32)
			volcano.colour = payload.decode_u16(34)
			if volcano.trigger_type > 2 or volcano.colour > 8:
				return "Colour switch type or colour is outside the supported source range"
			for index: int in 10:
				var identity: int = payload.decode_s16(36 + index * 2)
				volcano.target_ids.append(-1 if identity == -1 else identity & 65535)
		EntityBehavior.Kind.VOL_FALLING_PLATFORM:
			if payload.size() < 36:
				return "Falling platform requires its delay and hop count"
			definition.authored_delay = payload.decode_u16(32)
			volcano.hops_before = payload.decode_u16(34)
	definition.volcano = volcano
	return ""

## Copies the ENTSTR_TRIGGER type and ten target IDs; the trailing frame count is never read.
static func _trigger_payload(definition: EntityDefinition, payload: PackedByteArray) -> String:
	if payload.size() < 56:
		return "Trigger requires its type and ten target IDs"
	var trigger := EntityTriggerDefinition.new()
	trigger.trigger_type = payload.decode_u32(32)
	if trigger.trigger_type > EntityTrigger.Type.BEGIN:
		return "Trigger type is outside the supported source range"
	for index: int in 10:
		var identity: int = payload.decode_s16(36 + index * 2)
		trigger.target_ids.append(-1 if identity == -1 else identity & 65535)
	definition.trigger = trigger
	return ""

## Copies FrogLord Cave operands and the frozen unsigned frogger-light precomputation.
static func _cave_payload(definition: EntityDefinition, payload: PackedByteArray) -> String:
	match definition.behavior.kind:
		EntityBehavior.Kind.CAVE_LIGHT:
			if payload.size() < 48:
				return "Frogger light requires min/max radii and die speed"
			var cave := EntityCaveDefinition.new()
			cave.min_radius = payload.decode_s32(32)
			cave.max_radius = payload.decode_s32(36)
			cave.die_speed = payload.decode_s32(40)
			if cave.min_radius <= 1 or cave.min_radius >= cave.max_radius or cave.max_radius > 255:
				return "Frogger light requires 1 < minimum radius < maximum radius <= 255"
			cave.light_min_squared = _unsigned_square(cave.min_radius << 8)
			cave.light_max_squared = _unsigned_square(cave.max_radius << 8)
			cave.light_die = _unsigned_square(((cave.die_speed << 8) & 0xffffffff) / 30) >> 8
			definition.cave = cave
		EntityBehavior.Kind.FAT_FIRE_FLY:
			if payload.size() < 34 or payload.decode_u16(32) >= EntityBonusFly.REWARD_IDS.size():
				return "Fat fire fly requires a fly type from 0 through 18"
			definition.pickup_type = payload.decode_u16(32)
	return ""

## Copies FrogLord Desert falling-rock, croc-head and crack operands; rock targets stay authored until grid resolution.
static func _desert_payload(definition: EntityDefinition, payload: PackedByteArray) -> String:
	var desert := EntityDesertDefinition.new()
	match definition.behavior.kind:
		EntityBehavior.Kind.DES_FALLING_ROCK:
			if payload.size() < FALLING_ROCK_SIZE:
				return "Falling rock requires twelve targets, delay, bounce count, flags and sound"
			for index: int in EntityDesertDefinition.MAX_ROCK_TARGETS:
				var offset: int = 32 + index * ROCK_TARGET_STRIDE
				desert.rock_targets.append(Vector3i(payload.decode_s16(offset), payload.decode_s16(offset + 2), payload.decode_s16(offset + 4)))
				desert.rock_times.append(payload.decode_u16(offset + 8))
			desert.rock_delay = payload.decode_u16(176)
			desert.rock_bounces = payload.decode_u8(178)
			desert.rock_flags = payload.decode_s32(180)
			desert.rock_targets_resolved = desert.rock_flags == EntityDesertDefinition.TARGETS_RESOLVED
			if desert.rock_bounces < 1 or desert.rock_bounces > EntityDesertDefinition.MAX_ROCK_TARGETS:
				return "Falling rock requires 1 to 12 bounces, got %d" % desert.rock_bounces
			for index: int in desert.rock_bounces:
				if desert.rock_times[index] <= 0:
					return "Falling rock target %d requires a positive time" % index
		EntityBehavior.Kind.DES_CROC_HEAD:
			if payload.size() < 44:
				return "Desert croc head requires rise, snap, pause and submerged timing"
			desert.rise_height = payload.decode_u16(32)
			desert.rise_speed = payload.decode_u16(34)
			desert.snap_delay = payload.decode_u16(36)
			desert.pause_delay = payload.decode_u16(38)
			desert.snap_flag = payload.decode_u16(40)
			desert.submerged_delay = payload.decode_u16(42)
		EntityBehavior.Kind.DES_CRACK:
			if payload.size() < 36:
				return "Desert crack requires its fall delay and hop count"
			desert.fall_delay = payload.decode_u16(32)
			desert.hops_before = payload.decode_u16(34)
	definition.desert = desert
	return ""

## Copies FrogLord Jungle plant, rope-bridge, outro-target and plinth-id operands after the matrix.
static func _jungle_payload(definition: EntityDefinition, payload: PackedByteArray) -> String:
	var jungle := EntityJungleDefinition.new()
	match definition.behavior.kind:
		EntityBehavior.Kind.JUN_PLANT:
			if payload.size() < 36:
				return "Jungle plant requires its snap time and delay"
			jungle.snap_time = payload.decode_s16(32)
			jungle.snap_delay = payload.decode_s16(34)
		EntityBehavior.Kind.JUN_ROPE_BRIDGE:
			if payload.size() < 36:
				return "Jungle rope bridge requires its fall delay and hop count"
			jungle.fall_delay = payload.decode_u16(32)
			jungle.hops_before = payload.decode_u16(34)
		EntityBehavior.Kind.JUN_OUTRO:
			if payload.size() < OUTRO_SIZE:
				return "Jungle outro requires %d targets and times" % EntityJungleDefinition.OUTRO_TARGET_COUNT
			for index: int in EntityJungleDefinition.OUTRO_TARGET_COUNT:
				var offset: int = 32 + index * OUTRO_TARGET_STRIDE
				jungle.outro_targets.append(Vector3i(payload.decode_s16(offset), payload.decode_s16(offset + 2), payload.decode_s16(offset + 4)))
				jungle.outro_times.append(payload.decode_u32(offset + 8))
		EntityBehavior.Kind.JUN_PLINTH, EntityBehavior.Kind.JUN_GOLD_FROG, EntityBehavior.Kind.JUN_STONE_FROG:
			if payload.size() < 36:
				return "Jungle outro plinth entity requires its id"
			jungle.op_id = payload.decode_s32(32)
			if definition.behavior.kind == EntityBehavior.Kind.JUN_PLINTH and (jungle.op_id < 0 or jungle.op_id >= PLINTH_TABLE_SIZE):
				return "Jungle plinth id %d is outside the source plinth table" % jungle.op_id
	definition.jungle = jungle
	return ""

## Copies FrogLord Swamp squirt, crusher, press and rat operands after the matrix and resolves the
## rat timing the source computes at creation.
static func _swamp_payload(definition: EntityDefinition, payload: PackedByteArray) -> String:
	var swamp := EntitySwampDefinition.new()
	match definition.behavior.kind:
		EntityBehavior.Kind.SWP_SQUIRT:
			if payload.size() < SQUIRT_SIZE:
				return "Swamp squirt requires its delay, drop time and target"
			swamp.time_delay = payload.decode_s16(32)
			swamp.drop_time = payload.decode_s16(34)
			swamp.target = _svec(payload, 36)
			if swamp.drop_time == 0:
				return "Swamp squirt drop time of zero divides by zero in the source"
		EntityBehavior.Kind.SWP_CRUSHER, EntityBehavior.Kind.SWP_PRESS:
			if payload.size() < CRUSHER_SIZE:
				return "Swamp crusher and press require their speed, distance, direction and delay"
			swamp.speed = payload.decode_s16(32)
			swamp.distance = payload.decode_s16(34)
			swamp.direction = payload.decode_s16(36)
			swamp.delay = payload.decode_s16(38)
		EntityBehavior.Kind.SWP_RAT:
			if payload.size() < RAT_SIZE:
				return "Swamp rat requires its speed and four targets"
			swamp.rat_speed = payload.decode_s16(32)
			for index: int in 4:
				swamp.rat_targets.append(_svec(payload, 36 + index * 8))
			var issue: String = swamp.resolve_rat()
			if not issue.is_empty():
				return issue
	definition.swamp = swamp
	return ""

## Source ENTSTRSwpCreateWeir: MRRotMatrix of a Z rotation of SWP_WEIR_ROTATION replaces the
## authored rotation in place; only the translation survives.
static func weir_matrix(matrix12: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = PlatformMath.z_rotation(WEIR_ROTATION)
	for axis: int in 3:
		result[9 + axis] = matrix12[9 + axis]
	return result

static func _svec(payload: PackedByteArray, offset: int) -> Vector3i:
	return Vector3i(payload.decode_s16(offset), payload.decode_s16(offset + 2), payload.decode_s16(offset + 4))

static func _unsigned_square(value: int) -> int:
	return (value * value) & 0xffffffff

static func _stored_entity_name(names: GameNameLists, form: FormBookEntry) -> String:
	if names == null or names.entities == null:
		return form.entity_name
	return names.entities.name_of(form.entity_type) if names.entities.has_name(form.entity_type) else "unnamed type %d" % form.entity_type
