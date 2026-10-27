class_name EntitySetup
extends RefCounted
## Resolves authored map entities into detached base-transform definitions.

var definitions: Array[EntityDefinition] = []
var diagnostics: Array[EntitySetupDiagnostic] = []
## Structural setup error; individual unsupported records use diagnostics.
var error: String = ""

## Resolves source-ordered entity spans and attaches validated source paths.
static func from_map(map: MapFile, theme_book: ThemeBook, source_id: String = "", resource_id: int = -1, build_id: String = "", custom_behaviors_enabled: bool = false) -> EntitySetup:
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
		if span.flags & (32 | 64):
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
		definition.behavior = EntityBehaviorCatalog.resolve(form.entity_name)
		definition.script_id = form.script_id
		definition.collision_callback = form.collision_callback
		definition.bonus_callback = form.bonus_callback
		definition.bonus_kind = FormCallbackCatalog.resolve(build_id, form.bonus_callback, true)
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
			definition.matrix12 = matrix.matrix12.duplicate()
			definition.behavior.execution = EntityBehavior.Execution.UPDATE if custom_behaviors_enabled else EntityBehavior.Execution.TRANSFORM
			if definition.behavior.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.LOG_SNAKE] and span.payload.size() >= 36:
				definition.parent_unique_id = span.payload.decode_s16(32)
				if definition.behavior.kind == EntityBehavior.Kind.LOG_SNAKE:
					definition.movement_speed = span.payload.decode_u16(34)
		elif definition.behavior.kind == EntityBehavior.Kind.PATH_FOLLOWER or (custom_behaviors_enabled and definition.behavior.kind in [EntityBehavior.Kind.TURTLE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.DOG]):
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
		else:
			result._issue("unknown_behavior", "No base-transform decoder for entity name %s" % form.entity_name, span, form, index, source_id, resource_id, build_id)
			continue
		result.definitions.append(definition)
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
