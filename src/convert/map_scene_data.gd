class_name MapSceneData
extends RefCounted
## One level's decoded map and rendering dependencies, owned by its active viewer.
## All resource choices come from the supplied executable; no retail IDs are baked in.

## Selected level and detail.
var level: int = 0
var low_poly: bool = false
## Decoded immutable source records.
var map: MapFile
var sky_land: SkyLandFile
## Texture lookup in the original general-then-theme load order.
var library: TextureLibrary = TextureLibrary.new()
## Whole physical texture pages, shared by this scene's cached map materials.
var texture_pages := MapTexturePages.new()
var preferred: VloFile
var remap: TextureRemap
var sky_remap: TextureRemap
var environment_image: VloImage
## Cave terrain parameters in squared game units, not a gameplay light controller.
var cave_enabled: bool = false
var cave_min_r2: int = 1
var cave_max_r2: int = 1
## Raw bounds and midpoint (C integer division truncates toward zero).
var bounds_min: Vector3i = Vector3i.ZERO
var bounds_max: Vector3i = Vector3i.ZERO
var midpoint: Vector3i = Vector3i.ZERO
## Resource and source diagnostics, displayed by the viewer.
var diagnostics := PackedStringArray()
var error: String = ""


## Resolves a level from the player's map/theme books and reads only its dependencies.
static func load_level(data: GameData, level_number: int, use_low_poly: bool = false) -> MapSceneData:
	var scene := MapSceneData.new()
	scene.level = level_number
	scene.low_poly = use_low_poly
	scene.diagnostics.append_array(data.warnings)
	var row: MapBookEntry = data.map_book_entry(level_number)
	if row == null or row.is_dummy() or row.map_id(use_low_poly) <= 0:
		scene.error = "No map for level %d" % level_number
		return scene
	scene.map = data.read_map(row.map_id(use_low_poly), scene.diagnostics)
	if scene.map == null:
		scene.error = "; ".join(scene.diagnostics)
		return scene
	for warning: String in scene.map.warnings:
		scene.diagnostics.append(warning)
	scene._measure_bounds()
	scene.remap = data.remap_for_resource(row.map_id(use_low_poly))
	if scene.remap == null or not data.tables.remaps().error.is_empty():
		scene.error = "Map texture remap is unavailable: %s" % data.tables.remaps().error
		return scene
	var multiplayer: bool = GameData.is_multiplayer_level(level_number)
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	var theme: ThemeBookEntry = data.theme_book_entry(scene.map.general.theme)
	if general == null or theme == null:
		scene.error = "Map theme is unavailable"
		return scene
	scene._load_bank(data, general, multiplayer)
	scene.preferred = scene._load_bank(data, theme, multiplayer)
	if not scene.error.is_empty():
		return scene
	# This pointer is for model environment mapping. Terrain always uses its
	# own remapped polygon texture, including polygons with ENVMAP UVs.
	if row.environment_texture_pointer != 0:
		scene.environment_image = scene.library.image_for_pointer(data.tables.bmp_pointers(), row.environment_texture_pointer, scene.preferred)
	scene.cave_enabled = row.use_cave_lights
	if scene.cave_enabled:
		scene._read_cave_light(data)
	if scene.map.general.theme == 8:
		scene.sky_land = data.read_sky_land(use_low_poly, scene.diagnostics)
		scene.sky_remap = data.tables.remaps().find_by_name("txl_sky_land")
		if scene.sky_land == null or scene.sky_remap == null:
			scene.error = "Sky-land data or texture remap is unavailable"
	return scene


## Resolves a local map texture; callers use a visible fallback when missing.
func image_for_local(local_id: int) -> VloImage:
	return library.image_for_local(remap, local_id, preferred) if remap != null else null


## True when terrain needs camera-relative environment UVs.
func uses_environment() -> bool:
	for polygon: MapPolygon in map.polygons:
		if polygon.texture_id >= 0 and polygon.flags & 2:
			return true
	return false


func _load_bank(data: GameData, theme: ThemeBookEntry, multiplayer: bool) -> VloFile:
	var id: int = theme.vlo_id(multiplayer, low_poly)
	if id == 0:
		id = theme.vlo_id(false, low_poly)
	var bank: VloFile = data.read_texture_bank(id, diagnostics)
	if bank == null:
		error = "Texture bank %d could not be read" % id
		return null
	var entry: MwiEntry = data.mwi.get_entry(id)
	library.add_bank(bank, entry.display_name() if entry != null else str(id))
	return bank


func _measure_bounds() -> void:
	if map.vertices.is_empty():
		return
	bounds_min = map.vertices[0]
	bounds_max = bounds_min
	for vertex: Vector3i in map.vertices:
		bounds_min = bounds_min.min(vertex)
		bounds_max = bounds_max.max(vertex)
	midpoint = Vector3i((bounds_min.x + bounds_max.x) / 2,
		(bounds_min.y + bounds_max.y) / 2, (bounds_min.z + bounds_max.z) / 2)


func _read_cave_light(data: GameData) -> void:
	var found: bool = false
	for entity: MapEntitySpan in map.entities:
		var form: FormBookEntry = data.tables.theme_book().get_form(map.general.theme, entity.form_id)
		if form == null:
			diagnostics.append("Unknown form %d; no cave-light payload decoded" % entity.form_id)
			continue
		if form.entity_name != "CAV_FROGGER_LIGHT":
			continue
		if entity.payload.size() < 44:
			error = "Cave-light entity %d has a truncated payload" % entity.unique_id
			return
		var radius: int = entity.payload.decode_u32(36)
		if radius < 1 or radius > 255:
			error = "Cave-light entity %d has an unsafe maximum radius" % entity.unique_id
			return
		var radii: PackedInt64Array = MapLighting.initial_cave_radii(radius)
		cave_min_r2 = radii[0]
		cave_max_r2 = radii[1]
		found = true
	if not found:
		cave_enabled = false
		diagnostics.append("No named cave-light payload; showing stored terrain colours")
