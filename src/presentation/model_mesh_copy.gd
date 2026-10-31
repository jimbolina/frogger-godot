class_name ModelMeshCopy
extends RefCounted
## A drawing copy of a shared [ModelMesh] whose materials a view may change.
##
## Committed meshes and their materials are shared loaded resources: a view that
## sets a shader parameter on them, such as [code]projection_scale[/code] or the
## frog's [code]depth_bias[/code], would change every other user of the same
## material, and flipbook parts write their cel pose into their surface's
## material. The copy has its own part and morph meshes and one material copy
## per part surface, shared as in a mesh built at runtime: a morph mesh's
## surface and a texture track's original use their part surface's copy, so a
## parameter set on the part's materials reaches them, and a track's frames are
## the track's own. Geometry, cel atlases and textures stay shared.


## A copy of [param shared] with its own materials, or null for null.
static func of(shared: ModelMesh) -> ModelMesh:
	if shared == null:
		return null
	var copy := ModelMesh.new()
	copy.triangle_count = shared.triangle_count
	copy.surface_count = shared.surface_count
	copy.skipped_polygons = shared.skipped_polygons
	copy.missing_image_ids = shared.missing_image_ids.duplicate()
	copy.diagnostics = shared.diagnostics.duplicate()
	copy.bounds = shared.bounds
	copy.part_bounds = shared.part_bounds.duplicate()
	copy.action_bounds = shared.action_bounds.duplicate()
	for mesh: ArrayMesh in shared.part_meshes:
		copy.part_meshes.append(_mesh(mesh))
	for part: int in shared.morph_meshes.size():
		var part_mesh: ArrayMesh = copy.part_meshes[part] if part < copy.part_meshes.size() else null
		copy.morph_meshes.append(_morph(shared.morph_meshes[part], part_mesh))
	for part: int in shared.texture_tracks.size():
		var copied: Array = []
		var part_mesh: ArrayMesh = copy.part_meshes[part] if part < copy.part_meshes.size() else null
		for track: ModelMesh.TextureTrack in shared.texture_tracks[part]:
			copied.append(_track(track, part_mesh))
		copy.texture_tracks.append(copied)
	return copy


static func _mesh(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null:
		return null
	var copy: ArrayMesh = mesh.duplicate() as ArrayMesh
	for surface: int in copy.get_surface_count():
		var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
		if material != null:
			copy.surface_set_material(surface, material.duplicate() as ShaderMaterial)
	return copy


static func _morph(morph: ModelMorphMesh, part_mesh: ArrayMesh) -> ModelMorphMesh:
	if morph == null:
		return null
	var copy := ModelMorphMesh.new()
	copy.mesh = _mesh(morph.mesh)
	if copy.mesh != null and part_mesh != null:
		for surface: int in mini(copy.mesh.get_surface_count(), part_mesh.get_surface_count()):
			var material: ShaderMaterial = part_mesh.surface_get_material(surface) as ShaderMaterial
			if material != null:
				copy.mesh.surface_set_material(surface, material)
	copy.textures = morph.textures.duplicate()
	copy.vertex_counts = morph.vertex_counts.duplicate()
	return copy


static func _track(track: ModelMesh.TextureTrack, part_mesh: ArrayMesh) -> ModelMesh.TextureTrack:
	var copy := ModelMesh.TextureTrack.new()
	copy.surface = track.surface
	copy.target = track.target
	var surface_material: ShaderMaterial = null
	if part_mesh != null and track.surface >= 0 and track.surface < part_mesh.get_surface_count():
		surface_material = part_mesh.surface_get_material(track.surface) as ShaderMaterial
	copy.original = surface_material if surface_material != null else _duplicate(track.original)
	for frame: ShaderMaterial in track.frames:
		copy.frames.append(_duplicate(frame))
	return copy


static func _duplicate(material: ShaderMaterial) -> ShaderMaterial:
	return material.duplicate() as ShaderMaterial if material != null else null
