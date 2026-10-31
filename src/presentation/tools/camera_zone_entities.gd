class_name CameraZoneEntities
extends Node3D
## Log model instances whose lifetimes follow committed camera-probe generations.

var _meshes: Array[ModelMesh] = []
var _files: Array[MofFile] = []
var _instances: Array[AnimatedModelInstance] = []
var _generations: Array[int] = []

## Builds shared draw resources from the supplied log models.
func configure(data: AssetCatalog, inspection: CameraZoneInspection) -> String:
	var cache: Dictionary[int, ModelMesh] = {}
	var files: Dictionary[int, MofFile] = {}
	var problems := PackedStringArray()
	for entity: EntityDefinition in inspection.entity_definitions:
		var form: FormBookEntry = data.tables.theme_book().get_form(inspection.map_scene.map.general.theme, entity.form_id)
		var resource: int = data.model_resource_for(form, inspection.map_scene.level)
		if not cache.has(resource):
			var file: MofFile = data.read_model(resource, problems)
			if file == null or not file.error.is_empty():
				return "Cannot render admitted JUN1 log: " + "; ".join(problems)
			files[resource] = file
			cache[resource] = ModelMeshBuilder.new(inspection.map_scene.library, inspection.map_scene.preferred).build_animated(file)
		_meshes.append(cache[resource])
		_files.append(files[resource])
		_instances.append(null)
		_generations.append(-1)
	return ""

## Releases dormant instances and creates fresh models on every generation change.
func present(snapshot: EntityRunSnapshot, scale: Vector2, reset_generation: bool = false) -> void:
	for slot: int in snapshot.entities.size():
		var entity: EntitySnapshot = snapshot.entities[slot]
		if _instances[slot] != null and (reset_generation or not entity.live or _generations[slot] != entity.generation):
			remove_child(_instances[slot])
			_instances[slot].queue_free()
			_instances[slot] = null
		if not entity.live:
			continue
		if _instances[slot] == null:
			var instance := AnimatedModelInstance.new()
			add_child(instance)
			instance.setup(_meshes[slot], ModelAnimationPlayer.new(_files[slot]))
			instance.smoothing_enabled = false
			_instances[slot] = instance
			_generations[slot] = entity.generation
		_instances[slot].transform = GameSpace.transform(entity.matrix12)
		for mesh: ArrayMesh in _meshes[slot].part_meshes:
			if mesh == null:
				continue
			for surface: int in mesh.get_surface_count():
				var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
				if material != null:
					material.set_shader_parameter("projection_scale", scale)
