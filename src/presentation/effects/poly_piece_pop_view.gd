class_name PolyPiecePopView
extends Node3D
## Draws entity poly-piece pops from committed entity snapshots.
##
## The first committed snapshot of a live generation with [code]pop_allocated[/code]
## starts a pop (LiveEntityInitPop and LiveEntityStartPolyPiecePop, ENTITY.C:3360-3465):
## the slot's model is split once per model file by [ModelPolyPieces] from
## static model 0, a [PolyPiecePopState] starts from the entity matrix, and
## one mesh instance per piece is created. Each committed tick advances the
## state to the snapshot's [code]pop_remaining[/code] and points its
## [code]lwtrans[/code] at the entity's current matrix, as
## [code]pp_lwtrans[/code] does. The source draws the pieces at the fixed
## ordering slot FROG_POPPING_FIXED_OT, so their materials skip the depth test
## and draw after other translucent polygons, like the pop ring. The pieces
## are freed when the timer reaches 0, the pop is cleared or the entity
## retires; the entity's own model is hidden by the world view.

## One running or finished pop of one entity generation.
class Pop extends RefCounted:
	var generation: int = 0
	var state := PolyPiecePopState.new()
	var pieces: ModelPolyPieces
	var nodes: Array[MeshInstance3D] = []
	var materials: Dictionary[String, ShaderMaterial] = {}
	var finished: bool = false

## The model a slot pops, with the banks its textures come from.
class Source extends RefCounted:
	var file: MofFile
	var library: TextureLibrary
	var preferred: VloFile

const _ALBEDO_LINE: String = "ALBEDO = to_linear(clamp(shown, vec3(0.0), vec3(1.0)));"

static var _front_shaders: Dictionary[String, Shader] = {}

var _sources: Dictionary[int, Source] = {}
var _prepared: Dictionary[int, ModelPolyPieces] = {}
var _cache: Dictionary[MofFile, ModelPolyPieces] = {}
var _pops: Dictionary[int, Pop] = {}
var _projection_scale := Vector2.ONE


## Names the model slot [param slot] pops, with its texture [param library] and [param preferred] bank.
func set_model(slot: int, file: MofFile, library: TextureLibrary, preferred: VloFile) -> void:
	var source := Source.new()
	source.file = file
	source.library = library
	source.preferred = preferred
	_sources[slot] = source


## Supplies prepared pieces for [param slot] directly, for models built elsewhere.
func set_pieces(slot: int, pieces: ModelPolyPieces) -> void:
	_prepared[slot] = pieces


## Forgets every model and pop.
func clear() -> void:
	collapse()
	_sources.clear()
	_prepared.clear()
	_cache.clear()


## Frees every pop's pieces.
func collapse() -> void:
	for slot: int in _pops.keys():
		_free_nodes(_pops[slot])
	_pops.clear()


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	for slot: int in _pops:
		for material: ShaderMaterial in _pops[slot].materials.values():
			material.set_shader_parameter("projection_scale", scale)


## Starts, steps and frees pops for one committed tick of [param entities].
func accept(entities: Array[EntitySnapshot]) -> void:
	for slot: int in _pops.keys():
		var entity: EntitySnapshot = entities[slot] if slot < entities.size() else null
		if entity == null or not entity.live or not entity.pop_allocated or entity.generation != _pops[slot].generation:
			_free_nodes(_pops[slot])
			_pops.erase(slot)
	for slot: int in entities.size():
		var entity: EntitySnapshot = entities[slot]
		if not entity.live or not entity.pop_allocated:
			continue
		var pop: Pop = _pops.get(slot)
		if pop == null:
			var pieces: ModelPolyPieces = _pieces_for(slot)
			if pieces == null or pieces.pieces.is_empty():
				continue
			pop = _start(entity, pieces)
			_pops[slot] = pop
		if pop.finished:
			continue
		pop.state.advance_to(entity.pop_remaining)
		pop.state.lwtrans = entity.matrix12.duplicate()
		if pop.state.timer == 0:
			_free_nodes(pop)
			pop.finished = true
			continue
		for index: int in pop.nodes.size():
			pop.nodes[index].transform = pop.state.transform_for(index)


## The pop of [param slot], or null.
func pop_for(slot: int) -> Pop:
	return _pops.get(slot)


## Number of piece instances drawn.
func piece_count() -> int:
	var count: int = 0
	for slot: int in _pops:
		count += _pops[slot].nodes.size()
	return count


## An unlit variant of the piece material [param original] that skips the depth
## test and draws after other translucent polygons, keeping its texture and blend.
static func front_material(original: ShaderMaterial, blend: ModelShaders.Blend, projection_scale: Vector2) -> ShaderMaterial:
	var texture: Texture2D = null
	if original != null:
		texture = original.get_shader_parameter("image")
	var key: String = "%s/%d" % [texture != null, blend]
	if not _front_shaders.has(key):
		var code: String = ModelShaders.shader_code(texture != null, blend, false).replace("render_mode unshaded, ", "render_mode unshaded, depth_test_disabled, ")
		if blend == ModelShaders.Blend.OPAQUE:
			code = code.replace("depth_draw_opaque", "depth_draw_never").replace(_ALBEDO_LINE, _ALBEDO_LINE + "\n\tALPHA = 1.0;")
		var shader := Shader.new()
		shader.code = code
		_front_shaders[key] = shader
	var material := ShaderMaterial.new()
	material.shader = _front_shaders[key]
	material.render_priority = EffectSpriteMaterial.FRONT_PRIORITY
	if texture != null:
		material.set_shader_parameter("image", texture)
	material.set_shader_parameter("projection_scale", projection_scale)
	return material


func _pieces_for(slot: int) -> ModelPolyPieces:
	if _prepared.has(slot):
		return _prepared[slot]
	var source: Source = _sources.get(slot)
	if source == null or source.file == null or source.file.static_models.is_empty():
		return null
	if not _cache.has(source.file):
		_cache[source.file] = ModelPolyPieces.build(source.file.static_models[0], source.library, source.preferred)
	return _cache[source.file]


func _start(entity: EntitySnapshot, pieces: ModelPolyPieces) -> Pop:
	var pop := Pop.new()
	pop.generation = entity.generation
	pop.pieces = pieces
	pop.state.start(entity.matrix12, pieces.origins())
	for piece: ModelPolyPieces.Piece in pieces.pieces:
		if not pop.materials.has(piece.material_key):
			var original: ShaderMaterial = pieces.materials.get(piece.material_key)
			pop.materials[piece.material_key] = front_material(original, piece.blend, _projection_scale)
		var node := MeshInstance3D.new()
		node.mesh = piece.mesh
		node.material_override = pop.materials[piece.material_key]
		add_child(node)
		pop.nodes.append(node)
	return pop


func _free_nodes(pop: Pop) -> void:
	for node: MeshInstance3D in pop.nodes:
		remove_child(node)
		node.queue_free()
	pop.nodes.clear()
