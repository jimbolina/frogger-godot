class_name MaplessEntityResources
extends RefCounted
## Builds per-slot entity meshes from recorded theme and level origins, without a decoded map.

## Animated mesh for each slot, or null when the slot needs a placeholder.
var meshes: Array[ModelMesh] = []
## Decoded model for each slot, or null when the slot needs a placeholder.
var files: Array[MofFile] = []
## Unresolved slots and source problems, reported instead of failing.
var diagnostics := PackedStringArray()
var _scenes: Dictionary[int, MapSceneData] = {}

## Resolves every slot of `definitions` through `origins`; missing data leaves all slots unresolved.
static func resolve(definitions: Array[EntityDefinition], origins: EntityModelOrigins) -> MaplessEntityResources:
	var result := MaplessEntityResources.new()
	for _definition: EntityDefinition in definitions:
		result.meshes.append(null)
		result.files.append(null)
	if origins == null or origins.data == null or not origins.data.is_valid():
		if not definitions.is_empty():
			result.diagnostics.append("No player data; entities are drawn as placeholders")
		return result
	var meshes_by_key: Dictionary[Vector2i, ModelMesh] = {}
	var files_by_key: Dictionary[Vector2i, MofFile] = {}
	for slot: int in definitions.size():
		var entity: EntityDefinition = definitions[slot]
		if not origins.resolvable(slot):
			continue
		var theme: int = origins.themes[slot]
		var level: int = origins.levels[slot]
		var data: AssetCatalog = origins.data
		var form: FormBookEntry = data.tables.theme_book().get_form(theme, entity.form_id)
		if form == null:
			result.diagnostics.append("Slot %d form %d is not in theme %d" % [slot, entity.form_id, theme])
			continue
		if form.has_flag(FormBookEntry.FLAG_NO_MODEL) and entity.behavior.kind != EntityBehavior.Kind.VOL_COLOUR_SWITCH:
			continue
		var resource: int = EntityModelSelection.resource_for(data, level, form, entity)
		if resource < 0:
			result.diagnostics.append("Slot %d form %s has no model resource" % [slot, form.form_name])
			continue
		var scene: MapSceneData = result.scene_for(data, theme)
		if not scene.error.is_empty():
			result.diagnostics.append(scene.error)
			continue
		var key := Vector2i(resource, theme)
		if not meshes_by_key.has(key):
			var file: MofFile = data.read_model(resource, result.diagnostics)
			if file == null or not file.error.is_empty() or file.static_models.is_empty():
				result.diagnostics.append("Slot %d model %d could not be decoded" % [slot, resource])
				continue
			files_by_key[key] = file
			meshes_by_key[key] = ModelMeshLibrary.mesh_for(data, resource, scene.library, scene.preferred)
		result.meshes[slot] = meshes_by_key[key]
		result.files[slot] = files_by_key[key]
	return result

## Returns the GENERAL-then-theme texture bundle for `theme`; its `map` stays null.
func scene_for(data: AssetCatalog, theme: int) -> MapSceneData:
	if _scenes.has(theme):
		return _scenes[theme]
	var scene := MapSceneData.new()
	scene.library.catalog = data
	_scenes[theme] = scene
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	var owner: ThemeBookEntry = data.theme_book_entry(theme)
	if general == null or owner == null:
		scene.error = "Theme %d is unavailable" % theme
		return scene
	scene.preferred = _add_bank(data, scene, general)
	if theme != FroggerIds.THEME_GENERAL and scene.error.is_empty():
		scene.preferred = _add_bank(data, scene, owner)
	return scene

static func _add_bank(data: AssetCatalog, scene: MapSceneData, theme: ThemeBookEntry) -> VloFile:
	var id: int = theme.vlo_id(false, false)
	var bank: VloFile = data.read_texture_bank(id, scene.diagnostics)
	if bank == null:
		scene.error = "Texture bank %d could not be read" % id
		return null
	var entry: MwiEntry = data.mwi.get_entry(id)
	scene.library.add_bank(bank, entry.display_name() if entry != null else str(id))
	return bank
