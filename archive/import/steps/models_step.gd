extends ImportStep
## Writes every model of the archive under [method ImportContext.model_dir].
##
## For each model in MWI order (an incomplete model joined to its counterpart
## as [method GameData.read_model] joins it) the folder holds:
## [br]- [code]model.res[/code], the [MofFile] record;
## [br]- [code]part_NN.res[/code], the [ArrayMesh] of each part that draws
##   something, flipbook cels as blend shapes;
## [br]- [code]mesh.res[/code], the [ModelMesh] built by [ModelMeshBuilder]
##   from static model 0, referring to the part files and holding the flipbook
##   cel atlases, texture tracks and their frame materials;
## [br]- [code]model.tscn[/code], a [Node3D] with one [MeshInstance3D] per part
##   named [code]Part_NN[/code], an animated model posed at action 0 frame 0;
## [br]- [code]preview.res[/code] for an animated (XAR) model, an
##   [AnimationLibrary] with one [Animation] per valid action keying every
##   part's [code]transform[/code] once per game frame (30 a second). It is a
##   preview only: the game samples [MofAnimated] itself.
## [br]A model is built with every texture bank, its WAD's bank first, every
## image's texture being its imported PNG. An ordinary textured surface uses the
## shared material at [method ImportContext.material_path]; untextured
## surfaces share one material inside the mesh, and texture-animation surfaces
## keep their own original and frame materials there.

## Game frames per second, the key spacing of the preview animations.
const FRAMES_PER_SECOND: float = 30.0


func step_name() -> String:
	return "models"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	var library: TextureLibrary = imported_library(context)
	var materials: Dictionary[String, ShaderMaterial] = {}
	var folders: Dictionary[String, int] = {}
	for entry: MwiEntry in context.data.model_entries():
		var model_name: String = context.entry_name(entry.index)
		if folders.has(model_name):
			context.report("models: %s names resources %d and %d" % [model_name, folders[model_name], entry.index])
			continue
		folders[model_name] = entry.index
		var problems := PackedStringArray()
		var file: MofFile = context.data.read_model(entry.index, problems)
		if file == null:
			context.report("models: %s: %s" % [model_name, "; ".join(problems)])
			continue
		var preferred: VloFile = bank_by_id(context, context.data.texture_bank_for_wad(context.data.wad_holding(entry.index)))
		write_model(context, context.model_dir(model_name), model_name, file,
			ModelMeshBuilder.new(library, preferred), materials)


## Every texture bank of the archive by MWI display name without extension
## ([member ImportContext.banks]), each image's [member VloImage.texture] set
## to its imported PNG. Banks the textures step left there are reused.
static func imported_banks(context: ImportContext) -> Dictionary[String, VloFile]:
	for entry: MwiEntry in context.data.texture_bank_entries():
		var bank_name: String = context.entry_name(entry.index)
		var bank: VloFile = context.banks.get(bank_name, null)
		if bank == null:
			var problems := PackedStringArray()
			bank = context.data.read_texture_bank(entry.index, problems)
			if bank == null:
				context.report("models: texture bank %s: %s" % [bank_name, "; ".join(problems)])
				continue
			context.banks[bank_name] = bank
		for image: VloImage in bank.images:
			if image.texture != null:
				continue
			var path: String = context.texture_png_path(image.texture_id)
			image.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
			if image.texture == null:
				context.report("models: texture %d of %s is not imported at %s" % [image.texture_id, bank_name, path])
	return context.banks


## The bank with resource id [param resource_id] once [method imported_banks] has run, or null.
static func bank_by_id(context: ImportContext, resource_id: int) -> VloFile:
	if resource_id <= 0:
		return null
	return context.banks.get(context.entry_name(resource_id), null)


## A library of every imported bank in MWI order.
static func imported_library(context: ImportContext) -> TextureLibrary:
	var library := TextureLibrary.new()
	var banks: Dictionary[String, VloFile] = imported_banks(context)
	for entry: MwiEntry in context.data.texture_bank_entries():
		var bank_name: String = context.entry_name(entry.index)
		if banks.has(bank_name):
			library.add_bank(banks[bank_name], entry.display_name())
	return library


## Writes [param file]'s record, part meshes, mesh, scene and (for an animated
## model) preview animations into [param folder], building with [param builder].
## [param materials] holds the shared materials saved so far, by path.
static func write_model(context: ImportContext, folder: String, model_name: String, file: MofFile,
		builder: ModelMeshBuilder, materials: Dictionary[String, ShaderMaterial]) -> void:
	file.resource_name = model_name
	ImportContext.number_sub_resources(file)
	context.save_resource(file, folder.path_join("model.res"))
	var mesh: ModelMesh = builder.build_animated(file) if not file.static_models.is_empty() else ModelMesh.new()
	_share_materials(context, model_name, mesh, builder.two_sided, materials)
	for part_index: int in mesh.part_meshes.size():
		var part: ArrayMesh = mesh.part_meshes[part_index]
		if part == null:
			continue
		part.resource_name = "%s part %d" % [model_name, part_index]
		ImportContext.number_sub_resources(part)
		context.save_resource(part, folder.path_join("part_%02d.res" % part_index))
	mesh.resource_name = model_name
	ImportContext.number_sub_resources(mesh)
	context.save_resource(mesh, folder.path_join("mesh.res"))
	_write_scene(context, folder, model_name, file, mesh)
	if file.animated != null:
		_write_preview(context, folder, model_name, file, mesh.part_meshes.size())


static func _share_materials(context: ImportContext, model_name: String, mesh: ModelMesh, two_sided: bool,
		materials: Dictionary[String, ShaderMaterial]) -> void:
	var plain: ShaderMaterial = null
	for part_index: int in mesh.part_meshes.size():
		var part: ArrayMesh = mesh.part_meshes[part_index]
		if part == null:
			continue
		var morph: ModelMorphMesh = mesh.morph_meshes[part_index] if part_index < mesh.morph_meshes.size() else null
		for surface: int in part.get_surface_count():
			var key: String = part.surface_get_name(surface)
			var built: ShaderMaterial = part.surface_get_material(surface) as ShaderMaterial
			var shared: ShaderMaterial = null
			if key == "plain":
				if plain == null:
					plain = built
					plain.resource_name = "plain"
				shared = plain
			elif key.begins_with("texture "):
				shared = _shared_material(context, model_name, key, built, two_sided, materials)
			else:
				built.resource_name = "%s part %d %s" % [model_name, part_index, key]
			if shared == null:
				continue
			part.surface_set_material(surface, shared)
			if morph != null:
				morph.mesh.surface_set_material(surface, shared)
	for tracks: Array in mesh.texture_tracks:
		for track: ModelTextureTrack in tracks:
			for frame: int in track.frames.size():
				if track.frames[frame] != track.original:
					track.frames[frame].resource_name = "%s frame %d" % [track.original.resource_name, frame]


static func _shared_material(context: ImportContext, model_name: String, key: String, built: ShaderMaterial,
		two_sided: bool, materials: Dictionary[String, ShaderMaterial]) -> ShaderMaterial:
	var words: PackedStringArray = key.split(" ")
	var texture_id: int = int(words[1])
	var blend: int = 0
	if words.size() >= 4:
		blend = int(words[3])
	var path: String = context.material_path(texture_id, blend, two_sided)
	if materials.has(path):
		return materials[path]
	var image: Variant = built.get_shader_parameter("image")
	var texture: Texture2D = image if image is Texture2D else null
	if texture == null or texture.resource_path != context.texture_png_path(texture_id):
		context.report("models: %s surface %s does not use the imported texture" % [model_name, key])
		return null
	built.resource_name = path.get_file().get_basename()
	built.shader.set_id_for_path(path, "1_shader")
	texture.set_id_for_path(path, "2_image")
	context.save_resource(built, path)
	materials[path] = built
	return built


static func _write_scene(context: ImportContext, folder: String, model_name: String, file: MofFile, mesh: ModelMesh) -> void:
	var scene_path: String = folder.path_join("model.tscn")
	var root := Node3D.new()
	root.name = model_name.validate_node_name()
	var posed: bool = file.animated != null and ModelAnimationPlayer.new(file).action_error(0).is_empty()
	for part_index: int in mesh.part_meshes.size():
		var node := MeshInstance3D.new()
		node.name = "Part_%02d" % part_index
		var part: ArrayMesh = mesh.part_meshes[part_index]
		if part != null:
			part.set_id_for_path(scene_path, "%d_part_%02d" % [part_index + 1, part_index])
			node.mesh = part
		if posed:
			node.transform = GameSpace.transform(file.animated.sample_matrix(0, 0, 0, part_index))
		root.add_child(node)
		node.owner = root
	var packed := PackedScene.new()
	var result: Error = packed.pack(root)
	root.free()
	if result != OK:
		context.report("models: cannot pack %s (%s)" % [scene_path, error_string(result)])
		return
	context.save_resource(packed, scene_path)


static func _write_preview(context: ImportContext, folder: String, model_name: String, file: MofFile, part_count: int) -> void:
	var player := ModelAnimationPlayer.new(file)
	var names: NameBank = null
	if context.data.names != null and context.data.names.anims != null:
		names = context.data.names.anims.get_sub_bank(model_name)
	var library := AnimationLibrary.new()
	library.resource_name = model_name
	for action: int in player.action_count():
		if not player.action_error(action).is_empty():
			continue
		var animation_name: String = "action_%02d" % action
		if names != null and action < names.size():
			var named: String = names.name_of(action).validate_node_name().replace(",", "_").replace("[", "_")
			if not named.is_empty() and not library.has_animation(named):
				animation_name = named
		var frames: int = player.action_frame_count(action)
		var animation := Animation.new()
		animation.resource_name = animation_name
		animation.length = frames / FRAMES_PER_SECOND
		animation.step = 1.0 / FRAMES_PER_SECOND
		animation.loop_mode = Animation.LOOP_LINEAR
		for part: int in part_count:
			var track: int = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, NodePath("Part_%02d:transform" % part))
			animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
			for frame: int in frames:
				animation.track_insert_key(track, frame / FRAMES_PER_SECOND,
					GameSpace.transform(file.animated.sample_matrix(0, action, frame, part)))
		library.add_animation(animation_name, animation)
	ImportContext.number_sub_resources(library)
	context.save_resource(library, folder.path_join("preview.res"))
