class_name SandboxPresets
extends RefCounted
## Named sandbox layouts defined in code and applied entry by entry through a SandboxSpawner.

## One requested spawn: a FrogLord entity name on a cell with its path, speed and optional form.
class Entry extends RefCounted:
	var entity_name: String = ""
	var cell: Vector2i = Vector2i.ZERO
	var path: SandboxSpawner.Preset = SandboxSpawner.Preset.STATIC
	var speed: int = -1
	var form_name: String = ""

	## Creates an entry; `entry_speed` < 0 keeps the authored or default speed and "" selects the first form.
	func _init(entry_entity_name: String, entry_cell: Vector2i, entry_path: SandboxSpawner.Preset, entry_speed: int, entry_form_name: String) -> void:
		entity_name = entry_entity_name
		cell = entry_cell
		path = entry_path
		speed = entry_speed
		form_name = entry_form_name

	## Describes the entry for skip reports.
	func label() -> String:
		var form: String = "" if form_name.is_empty() else " (%s)" % form_name
		return "%s%s at %s" % [entity_name, form, cell]

## A named, ordered list of entries and the safe cell the frog starts from when the layout is loaded.
class Layout extends RefCounted:
	var name: String = ""
	var description: String = ""
	var start_cell: Vector2i = SandboxLevel.SPAWN_CELL
	var entries: Array[Entry] = []

	## Creates an empty layout whose loaded frog starts on `layout_start_cell` facing north.
	func _init(layout_name: String, layout_description: String, layout_start_cell: Vector2i) -> void:
		name = layout_name
		description = layout_description
		start_cell = layout_start_cell

	## Appends one entry and returns this layout so entries can be chained.
	func add(entity_name: String, cell: Vector2i, path: SandboxSpawner.Preset = SandboxSpawner.Preset.STATIC, speed: int = -1, form_name: String = "") -> Layout:
		entries.append(Entry.new(entity_name, cell, path, speed, form_name))
		return self

## Result of applying one layout: the placements made and a reason for every skipped entry.
class Outcome extends RefCounted:
	var layout_name: String = ""
	var placed: Array[SandboxSpawner.Placement] = []
	var skipped: PackedStringArray = PackedStringArray()

	## One-line summary naming the layout, its placed count and each skipped entry with its reason.
	func summary() -> String:
		var text: String = "%s: %d placed" % [layout_name, placed.size()]
		if skipped.is_empty():
			return text
		return "%s, %d skipped (%s)" % [text, skipped.size(), "; ".join(skipped)]

## Returns every built-in layout in menu order; a new mechanic adds an entry here or a new layout.
static func all() -> Array[Layout]:
	var result: Array[Layout] = []
	result.append(Layout.new("river", "Logs and turtles crossing the water zone", Vector2i(5, 5))
		.add("MOVING", Vector2i(3, 6), SandboxSpawner.Preset.LINE, -1, "ORG_LOG_LARGE")
		.add("SUB_TURTLE", Vector2i(3, 7), SandboxSpawner.Preset.LINE)
		.add("MOVING", Vector2i(3, 8), SandboxSpawner.Preset.SPEED, -1, "ORG_LOG_MEDIUM")
		.add("SUB_TURTLE", Vector2i(4, 9), SandboxSpawner.Preset.LINE)
		.add("ORG_CROC_HEAD", Vector2i(8, 9)))
	result.append(Layout.new("ice slide", "Obstacles and pickups across the ice and freeform ice zones", Vector2i(12, 5))
		.add("STATIC", Vector2i(12, 9))
		.add("DYNAMIC", Vector2i(13, 7))
		.add("BONUS_FLY", Vector2i(14, 11))
		.add("STATIC", Vector2i(19, 9))
		.add("BONUS_FLY", Vector2i(18, 11)))
	result.append(Layout.new("platform gauntlet", "Falling, switching, breaking and moving platforms over the deadly zone", Vector2i(5, 13))
		.add("VOL_FALLING_PLATFORM", Vector2i(4, 14))
		.add("VOL_COLOUR_SWITCH", Vector2i(6, 14))
		.add("MOVING", Vector2i(3, 15), SandboxSpawner.Preset.LINE, -1, "ORG_LOG_SMALL")
		.add("FOR_BREAKING_BRANCH", Vector2i(8, 15))
		.add("MOVING_PLATFORM", Vector2i(3, 16), SandboxSpawner.Preset.LINE)
		.add("VOL_FALLING_PLATFORM", Vector2i(8, 16)))
	result.append(Layout.new("enemy lane", "Vehicles and walking enemies crossing open floor", Vector2i(16, 19))
		.add("MOVING", Vector2i(13, 20), SandboxSpawner.Preset.LINE, -1, "ORG_CAR_BLUE")
		.add("MOVING", Vector2i(13, 21), SandboxSpawner.Preset.SPEED, -1, "ORG_LORRY")
		.add("MOVING", Vector2i(21, 22), SandboxSpawner.Preset.LINE, -1, "ORG_TRUCK_RED")
		.add("SUB_DOG", Vector2i(13, 23), SandboxSpawner.Preset.LINE)
		.add("FOR_HEDGEHOG", Vector2i(13, 24), SandboxSpawner.Preset.LINE)
		.add("FOR_SQUIRREL", Vector2i(24, 24), SandboxSpawner.Preset.LOOP)
		.add("ORG_BEAVER", Vector2i(13, 26), SandboxSpawner.Preset.LINE))
	result.append(Layout.new("zone tour", "One entity in every terrain zone", SandboxLevel.SPAWN_CELL)
		.add("SUB_TURTLE", Vector2i(3, 8), SandboxSpawner.Preset.LINE)
		.add("STATIC", Vector2i(12, 8))
		.add("DYNAMIC", Vector2i(19, 8))
		.add("GEN_GOLD_FROG", Vector2i(25, 8))
		.add("VOL_FALLING_PLATFORM", Vector2i(5, 15))
		.add("BONUS_FLY", Vector2i(12, 15))
		.add("CHECKPOINT", Vector2i(17, 14))
		.add("ORG_FLY", Vector2i(24, 16))
		.add("MOVING_TONGUEABLE", Vector2i(24, 18))
		.add("FIREFLY", Vector2i(4, 23), SandboxSpawner.Preset.LOOP))
	return result

## Lists the built-in layout names in menu order.
static func names() -> PackedStringArray:
	var result := PackedStringArray()
	for layout: Layout in all():
		result.append(layout.name)
	return result

## Returns the built-in layout called `layout_name`, or null when none has that name.
static func named(layout_name: String) -> Layout:
	for layout: Layout in all():
		if layout.name == layout_name:
			return layout
	return null

## Spawns each of `layout`'s entries in order, after clearing `spawner` when `replace` is set; entries that fail are skipped and reported.
static func apply(spawner: SandboxSpawner, layout: Layout, replace: bool) -> Outcome:
	var outcome := Outcome.new()
	if layout == null:
		outcome.skipped.append("No such preset")
		return outcome
	outcome.layout_name = layout.name
	if spawner == null:
		outcome.skipped.append("The sandbox is not open")
		return outcome
	if replace:
		spawner.clear()
	for entry: Entry in layout.entries:
		var result: SandboxSpawner.Result = spawner.add(entry.entity_name, entry.cell, entry.path, entry.speed, entry.form_name)
		if result.error.is_empty():
			outcome.placed.append(result.placement)
		else:
			outcome.skipped.append("%s: %s" % [entry.label(), result.error])
	return outcome
