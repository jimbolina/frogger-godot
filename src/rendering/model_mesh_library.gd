class_name ModelMeshLibrary
extends RefCounted
## Finds the drawable mesh of a model: the importer's committed [code]mesh.res[/code]
## when the game plays from the imported assets, otherwise one built from the
## model record with [ModelMeshBuilder].
##
## A committed mesh is the shared loaded resource, so every caller asking for
## the same model gets the same [ModelMesh] and the same materials. When the
## catalog draws another texture for any of the mesh's images (a texture
## pack's or a lettering image), the shared mesh is one converted
## [ModelMeshCopy] per model and [TextureSet], kept here.

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
	var key: String = "%s|%s" % [path, imported.texture_set().key()]
	if not _converted.has(key):
		_converted[key] = ModelMeshCopy.of(loaded, imported) if _draws_replacement(loaded, imported) else null
	var converted: ModelMesh = _converted[key]
	return converted if converted != null else loaded


static func _draws_replacement(mesh: ModelMesh, imported: ImportedAssets) -> bool:
	var materials: Array[ShaderMaterial] = []
	for part: ArrayMesh in mesh.part_meshes:
		_add_materials(part, materials)
	for morph: ModelMorphMesh in mesh.morph_meshes:
		if morph != null:
			_add_materials(morph.mesh, materials)
	for tracks: Array in mesh.texture_tracks:
		for track: ModelMesh.TextureTrack in tracks:
			materials.append(track.original)
			materials.append_array(track.frames)
	for material: ShaderMaterial in materials:
		var image: Texture2D = material.get_shader_parameter("image") if material != null else null
		if image != null and imported.texture_counterpart(image) != image:
			return true
	return false


static func _add_materials(mesh: ArrayMesh, materials: Array[ShaderMaterial]) -> void:
	if mesh == null:
		return
	for surface: int in mesh.get_surface_count():
		materials.append(mesh.surface_get_material(surface) as ShaderMaterial)
