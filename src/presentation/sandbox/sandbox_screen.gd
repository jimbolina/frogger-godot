class_name SandboxScreen
extends GameplayScreen
## Owner play-check scene: the flat sandbox arena with live entity spawning, teleport and reset that never ends.

const LEVEL_CODE: String = "SANDBOX"
const FACING_STEPS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const ZONE_COLOURS: Dictionary[StringName, Color] = {
	&"plain": Color(0.28, 0.42, 0.28),
	&"water": Color(0.14, 0.32, 0.78),
	&"ice": Color(0.72, 0.9, 0.97),
	&"freeform_ice": Color(0.5, 0.72, 0.95),
	&"bouncy": Color(0.92, 0.5, 0.82),
	&"deadly": Color(0.82, 0.14, 0.12),
	&"soft": Color(0.7, 0.58, 0.34),
	&"checkpoint": Color(0.95, 0.84, 0.18),
	&"cliff_steps": Color(0.58, 0.52, 0.46),
	&"cliff": Color(0.44, 0.38, 0.32),
	&"camera": Color(0.38, 0.36, 0.6),
}
const UNKNOWN_ZONE_COLOUR := Color(0.5, 0.5, 0.5)
const CHECKER_LIGHTEN: float = 0.1

var sandbox: SandboxLevel = null
var spawner: SandboxSpawner = null
var templates: SandboxEntityTemplates = null
var palette: SandboxPalette = null
## Why data-backed entities are unavailable, or "" when player data supplies them.
var data_status: String = ""
## Result of the latest palette or hotkey action.
var notice: String = ""
var debug_visible: bool = false
## Outcome of the latest preset load or add, or null before one.
var last_preset: SandboxPresets.Outcome = null
var _overlay: Label = null
var _outcomes := PackedStringArray()

func _ready() -> void:
	var open_from_arguments: bool = auto_open
	auto_open = false
	super._ready()
	auto_open = open_from_arguments
	level_code = LEVEL_CODE
	_build_sandbox_interface()
	if not auto_open:
		return
	var found: GameDataLocator.Located = ViewerArguments.locate_data(OS.get_cmdline_user_args())
	if found.is_ok():
		open_sandbox(GameData.open(found.source, found.version), true)
	else:
		open_sandbox(null)
		data_status = "No player data (%s); entities are placeholders" % found.error
		palette.refresh()

## Builds a fresh arena and spawner, borrowing `data` unless ownership is transferred; null data uses placeholders.
func open_sandbox(data: GameData, take_ownership: bool = false) -> String:
	_finish_pending()
	if data != _data:
		close_data()
		_owns_data = take_ownership and data != null
	else:
		_detach_game()
		_owns_data = (_owns_data or take_ownership) and data != null
	_data = data
	level_code = LEVEL_CODE
	sandbox = SandboxLevel.build()
	templates = null
	data_status = ""
	notice = ""
	if data == null:
		data_status = "No player data; entities are placeholders"
	elif not data.is_valid():
		data_status = "Player data is unusable (%s); entities are placeholders" % data.error
	else:
		data_status = _attach_data(data)
	spawner = SandboxSpawner.new(sandbox, templates)
	_build_arena()
	if palette != null:
		palette.refresh()
	return _respawn(SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION))

## Spawns the palette's selected entity on the frog's cell; returns the error or "".
func place_at_frog() -> String:
	return _place(frog_cell())

## Spawns the palette's selected entity on the cell the frog faces; returns the error or "".
func place_ahead() -> String:
	return _place(facing_cell())

## Spawns `entity_name` on `cell` and restarts the run with the frog where it stands; returns the error or "".
func place(entity_name: String, cell: Vector2i, preset: SandboxSpawner.Preset = SandboxSpawner.Preset.STATIC, speed: int = -1, form_name: String = "") -> String:
	if spawner == null:
		return _report("Open the sandbox first")
	_finish_pending()
	var result: SandboxSpawner.Result = spawner.add(entity_name, cell, preset, speed, form_name)
	if not result.error.is_empty():
		return _report(result.error)
	var issue: String = _respawn_in_place()
	if not issue.is_empty():
		return issue
	var form: String = result.placement.form_name
	return _report("", "Placed %s%s at %s" % [entity_name, "" if form.is_empty() else " (%s)" % form, cell])

## Applies the named preset; replacing clears the layout and moves the frog to the preset start, adding keeps both. Returns the error or "".
func load_preset(preset_name: String, replace: bool = true) -> String:
	if spawner == null:
		return _report("Open the sandbox first")
	var layout: SandboxPresets.Layout = SandboxPresets.named(preset_name)
	if layout == null:
		return _report("No preset named %s" % preset_name)
	_finish_pending()
	last_preset = SandboxPresets.apply(spawner, layout, replace)
	var issue: String = _respawn(SandboxSpawner.run_start(layout.start_cell, SandboxLevel.SPAWN_DIRECTION)) if replace else _respawn_in_place()
	if not issue.is_empty():
		return issue
	notice = ("Loaded " if replace else "Added ") + last_preset.summary()
	if palette != null:
		palette.set_status(notice, not last_preset.skipped.is_empty())
	return ""

## Removes the most recent placement; returns the error or "".
func remove_last() -> String:
	if spawner == null or not spawner.remove_last():
		return _report("No entity to delete")
	return _after_removal("Deleted the last entity")

## Removes every placement on the frog's cell; returns the error or "".
func remove_at_frog() -> String:
	if spawner == null:
		return _report("No entity to delete")
	var cell: Vector2i = frog_cell()
	var removed: int = spawner.remove_at(cell)
	if removed == 0:
		return _report("No entity placed at %s" % cell)
	return _after_removal("Deleted %d at %s" % [removed, cell])

## Removes every placement; returns the error or "".
func clear_entities() -> String:
	if spawner == null:
		return _report("Open the sandbox first")
	spawner.clear()
	return _after_removal("Cleared every entity")

## Moves the frog to `cell`, keeping its direction unless one is given; returns the error or "".
func teleport_to_cell(cell: Vector2i, direction: int = -1) -> String:
	if spawner == null:
		return _report("Open the sandbox first")
	if sandbox.flags_at(cell) < 0:
		return _report("Cell %s is outside the sandbox" % cell)
	_finish_pending()
	var facing: int = direction if direction >= 0 else (run.snapshot().frog.direction if run != null else SandboxLevel.SPAWN_DIRECTION)
	var issue: String = _respawn(SandboxSpawner.run_start(cell, facing))
	if not issue.is_empty():
		return issue
	return _report("", "Teleported to %s" % cell)

## Moves the frog to the safe approach of the zone named `zone_name`, facing north; returns the error or "".
func teleport_to_zone(zone_name: StringName) -> String:
	if sandbox == null:
		return _report("Open the sandbox first")
	var cell: Vector2i = zone_target(zone_name)
	if cell == Vector2i(-1, -1):
		return _report("No zone named %s" % zone_name)
	var issue: String = teleport_to_cell(cell, SandboxLevel.SPAWN_DIRECTION)
	if not issue.is_empty():
		return issue
	return _report("", "Teleported to %s at %s" % [zone_name, cell])

## Returns the cell a zone teleport uses: the spawn for the floor, a safe zone's centre, otherwise the cell south of it.
func zone_target(zone_name: StringName) -> Vector2i:
	var zone: SandboxLevel.Zone = sandbox.zone_named(zone_name) if sandbox != null else null
	if zone == null:
		return Vector2i(-1, -1)
	if zone.name == &"plain":
		return SandboxLevel.SPAWN_CELL
	@warning_ignore("integer_division")
	var centre: Vector2i = zone.cells.position + zone.cells.size / 2
	if sandbox.flags_at(centre) & GridSquareFlags.SAFE:
		return centre
	return Vector2i(centre.x, maxi(0, zone.cells.position.y - 1))

## Returns the frog to the spawn cell and direction with full lives and time; returns the error or "".
func reset_frog() -> String:
	var issue: String = teleport_to_cell(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION)
	if not issue.is_empty():
		return issue
	return _report("", "Frog reset to spawn")

## Restarts the sandbox at the spawn with every placement, full lives and a full timer.
func restart() -> String:
	if spawner == null:
		return _show_error("Open the sandbox first")
	var issue: String = _respawn(SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION))
	if not issue.is_empty():
		return issue
	return _report("", "Sandbox restarted")

## Shows or hides the frog and sandbox debug overlay.
func set_debug_visible(shown: bool) -> void:
	debug_visible = shown
	if palette != null:
		palette.sync_debug(shown)
	_refresh_overlay()

## The committed frog cell, or the spawn before a run exists.
func frog_cell() -> Vector2i:
	return _current.frog.cell if _current != null else SandboxLevel.SPAWN_CELL

## The cell in front of the committed frog, clamped to the arena.
func facing_cell() -> Vector2i:
	var direction: int = _current.frog.direction if _current != null else SandboxLevel.SPAWN_DIRECTION
	var cell: Vector2i = frog_cell() + FACING_STEPS[direction & 3]
	return cell.clamp(Vector2i.ZERO, SandboxLevel.DIMENSIONS - Vector2i.ONE)

## Text shown by the debug overlay for the committed state.
func overlay_text() -> String:
	if _current == null or sandbox == null:
		return ""
	var zone: SandboxLevel.Zone = sandbox.zone_at(_current.frog.cell)
	var text: String = "SANDBOX | zone %s | entities %d | platform %d\n" % [zone.name if zone != null else &"outside", spawner.placements.size(), _current.attachment.current_entity_index]
	text += "lives %d | time %d | score %d | phase %s\n" % [_current.frog.lives, ceili(_current.flow.remaining_time / 30.0), _current.flow.score, LevelFlowState.Phase.keys()[_current.flow.phase]]
	return text + GameplayStateFacts.frog_lines(_current, _outcomes)

## Executes an explicit command, restarting the sandbox if the run ended.
func step_command(command: TickCommand, capture_phases: bool = true) -> TickResult:
	var result: TickResult = super.step_command(command, capture_phases)
	_keep_alive()
	return result

func _process(delta: float) -> void:
	super._process(delta)
	_keep_alive()

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and _sandbox_key(key.physical_keycode):
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)

func _sandbox_key(code: Key) -> bool:
	match code:
		KEY_TAB: palette.visible = not palette.visible
		KEY_P: place_at_frog()
		KEY_F: place_ahead()
		KEY_BACKSPACE: remove_last()
		KEY_DELETE, KEY_X: remove_at_frog()
		KEY_C: clear_entities()
		KEY_BRACKETLEFT: palette.cycle_kind(-1)
		KEY_BRACKETRIGHT: palette.cycle_kind(1)
		KEY_1: palette.select_preset(SandboxSpawner.Preset.STATIC)
		KEY_2: palette.select_preset(SandboxSpawner.Preset.LINE)
		KEY_3: palette.select_preset(SandboxSpawner.Preset.LOOP)
		KEY_4: palette.select_preset(SandboxSpawner.Preset.SPEED)
		KEY_O: palette.cycle_layout(1)
		KEY_L: load_preset(palette.selected_layout(), true)
		KEY_K: load_preset(palette.selected_layout(), false)
		KEY_Z: teleport_to_zone(palette.selected_zone())
		KEY_T: teleport_to_cell(palette.selected_cell())
		KEY_H: reset_frog()
		KEY_F3: set_debug_visible(not debug_visible)
		_: return false
	return true

func _attach_data(data: GameData) -> String:
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(data)
	if not assets.error.is_empty():
		return "Frog assets are unavailable (%s); entities are placeholders" % assets.error
	build_frog(assets)
	var hud_error: String = _hud.configure(data)
	var loaded: SandboxEntityTemplates = SandboxEntityTemplates.from_data(data, assets.model, assets.action_lengths)
	if not loaded.error.is_empty():
		return "Entity templates are unavailable (%s); entities are placeholders" % loaded.error
	templates = loaded
	if voice_view() != null:
		configure_audio(AudioResources.from_data(data, loaded.sounds))
	var problems := PackedStringArray()
	if not hud_error.is_empty():
		problems.append("HUD is unavailable (%s)" % hud_error)
	if not loaded.sound_error.is_empty():
		problems.append("Sounds are unavailable (%s)" % loaded.sound_error)
	return "; ".join(problems)

func _place(cell: Vector2i) -> String:
	if palette == null:
		return _report("The palette is not built")
	return place(palette.selected_kind(), cell, palette.selected_preset(), palette.selected_speed(), palette.selected_form())

func _after_removal(message: String) -> String:
	_finish_pending()
	var issue: String = _respawn_in_place()
	if not issue.is_empty():
		return issue
	return _report("", message)

func _respawn_in_place() -> String:
	if run == null:
		return _respawn(SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION))
	return _respawn(SandboxSpawner.run_start_from(run.snapshot()))

func _respawn(start: RunStart) -> String:
	_outcomes.clear()
	var issue: String = open_run(spawner.level_definition(), start, spawner.model_origins(_data))
	_frog.visible = _frog_model == null and run != null
	_refresh_overlay()
	if not issue.is_empty():
		return _report(issue)
	return ""

func _keep_alive() -> void:
	if spawner == null or _current == null or not _current.completed or not last_error.is_empty():
		return
	var ended: String = "completed" if _current.flow.phase == LevelFlowState.Phase.COMPLETE else "ended"
	if restart().is_empty():
		_report("", "Run %s; sandbox restarted with full lives" % ended)

func _report(error: String, message: String = "") -> String:
	notice = error if not error.is_empty() else message
	if palette != null:
		palette.set_status(notice, not error.is_empty())
	return error

func _update_interface(events: Array[TickEvent] = []) -> void:
	super._update_interface(events)
	if not events.is_empty():
		_outcomes = PackedStringArray(TickEvent.trace_lines(events))
	_refresh_overlay()

func _refresh_overlay() -> void:
	if _overlay == null:
		return
	_overlay.visible = debug_visible
	if debug_visible:
		_overlay.text = overlay_text()

func _build_sandbox_interface() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_overlay = Label.new()
	_overlay.position = Vector2(212, 40)
	_overlay.size = Vector2(424, 200)
	_overlay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay.add_theme_font_size_override("font_size", 10)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 3)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	layer.add_child(_overlay)
	palette = SandboxPalette.new()
	layer.add_child(palette)
	palette.build(self)

func _build_arena() -> void:
	for child: Node in _ground.get_children():
		_ground.remove_child(child)
		child.queue_free()
	var groups: Dictionary[String, PackedVector3Array] = {}
	var colours: Dictionary[String, Color] = {}
	var grid: GridDefinition = sandbox.level.grid
	for z: int in SandboxLevel.DIMENSIONS.y:
		for x: int in SandboxLevel.DIMENSIONS.x:
			var cell := Vector2i(x, z)
			var zone: SandboxLevel.Zone = sandbox.zone_at(cell)
			var square: GridSquareDefinition = grid.squares[grid.stack_at(cell).first_square_index]
			var key: String = "%s:%d" % [zone.name, (x + z) & 1]
			if not groups.has(key):
				groups[key] = PackedVector3Array()
				var colour: Color = ZONE_COLOURS.get(zone.name, UNKNOWN_ZONE_COLOUR)
				colours[key] = colour.lightened(CHECKER_LIGHTEN) if (x + z) & 1 else colour
			var vertices: PackedVector3Array = groups[key]
			for index: int in [0, 1, 2, 2, 1, 3]:
				var vertex: Vector3i = square.vertices[index]
				vertices.append(GameSpace.position(vertex.x, vertex.y, vertex.z))
			groups[key] = vertices
	for key: String in groups:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = groups[key]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var face := MeshInstance3D.new()
		face.name = key.replace(":", "_")
		face.mesh = mesh
		face.material_override = _material(colours[key])
		_ground.add_child(face)
	_projection_size = Vector2i.ZERO
