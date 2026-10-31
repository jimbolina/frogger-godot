class_name ModelMeshLibrary
extends RefCounted
## Finds the drawable mesh of a model: the importer's committed [code]mesh.res[/code]
## when the game plays from the imported assets, otherwise one built from the
## model record with [ModelMeshBuilder].
##
## A committed mesh is the shared loaded resource, so every caller asking for
## the same model gets the same [ModelMesh] and the same materials. When the
## catalog draws from an upscaled [TextureSet] or under the modern
## [RenderingProfile], the shared mesh is one converted [ModelMeshCopy] per
## model, set and profile, kept here.

## The file of each model's mesh inside its folder under [code]models/[/code].
const MESH_FILE: String = "mesh.res"

static var _converted: Dictionary[String, ModelMesh] = {}


## The committed mesh path of model [param resource_id] under [param assets_root],
## inside the sub-folder [param folder] of [code]models/[/code] when it is not
## empty; "" when the archive index does not know the model.
static func mesh_path(catalog: AssetCatalog, assets_root: String, resource_id: int, folder: String = "") -> String:
	var entry: MwiEntry = catalog.mwi.get_entry(resource_id) if catalog != null and catalog.mwi != null else null
	if entry == null:
		return ""
	var models: String = assets_root.path_join("models")
	if not folder.is_empty():
		models = models.path_join(folder)
	return models.path_join(entry.display_name().get_basename()).path_join(MESH_FILE)


## The mesh of model [param resource_id], textured from [param library] with
## [param preferred] first when it has to be built; null when the model cannot
## be read. [param folder] picks a sub-folder of committed meshes built with
## other banks, such as [code]options[/code].
static func mesh_for(catalog: AssetCatalog, resource_id: int, library: TextureLibrary, preferred: VloFile,
		folder: String = "") -> ModelMesh:
	if catalog is ImportedAssets:
		var imported: ImportedAssets = catalog
		var path: String = mesh_path(catalog, imported.root, resource_id, folder)
		if not path.is_empty() and ResourceLoader.exists(path):
			var loaded: ModelMesh = ResourceLoader.load(path) as ModelMesh
			if loaded != null:
				return _for_drawing(loaded, path, imported)
	if catalog == null:
		return null
	var file: MofFile = catalog.read_model(resource_id)
	if file == null or not file.error.is_empty() or file.static_models.is_empty():
		return null
	return ModelMeshBuilder.new(library, preferred).build_animated(file)


static func _for_drawing(loaded: ModelMesh, path: String, imported: ImportedAssets) -> ModelMesh:
	var set: TextureSet = imported.texture_set()
	var profile: RenderingProfile = imported.rendering_profile()
	if set.is_retail() and not profile.is_modern():
		return loaded
	var key: String = "%s|%s|%s" % [path, set.set_name, profile.profile_name]
	if not _converted.has(key):
		_converted[key] = ModelMeshCopy.of(loaded, imported)
	return _converted[key]
