class_name EffectSetup
extends RefCounted
## Resolves entity model hilites into presentation-only particle generator placements.
##
## Source CreateLiveEntitySpecials (ENTITY.C:1766-1878) skips forms with
## FORM_BOOK_FLAG_NO_MODEL, reads static model 0 of an animated model and
## gives each hilite of every part the generator
## Entity_special_particle_generators names for its type. The table is read
## from the supplied executable ([ExeParticleGenerators]); when it cannot be
## located the frozen C table applies (types 3 and 4 exhaust, 5 dust, 6 fire).
## Collision hilites (type 0) start nothing. Any other type, a type whose
## generator is not a hilite generator, and a hilite not attached to a vertex
## are omitted with a diagnostic. An incomplete model's parts carry the
## hilites they borrow from their counterpart, as the game's do.

## Source HILITE_TYPE_COLLISION.
const HILITE_COLLISION: int = 0


## Fills [member EntityDefinition.particle_hilites] of every definition of
## level [param level] from its resolved model. [param generators] supplies
## the hilite generator table (read from [param data] when null) and
## [param theme] the map theme (the level's book theme when negative).
## Problems are appended to [param diagnostics].
static func resolve_hilites(data: AssetCatalog, level: int, definitions: Array[EntityDefinition], diagnostics: PackedStringArray, generators: ExeParticleGenerators = null, theme: int = -1) -> void:
	if data == null or not data.is_valid():
		return
	if generators == null:
		generators = data.tables.particle_generators()
	var table: PackedStringArray = generators.special_generators if not generators.special_generators.is_empty() else ExeParticleGenerators.C_SPECIAL_GENERATORS
	var map_theme: int = theme if theme >= 0 else FroggerIds.theme_of_level(level)
	for definition: EntityDefinition in definitions:
		definition.particle_hilites.clear()
		var form: FormBookEntry = data.tables.theme_book().get_form(map_theme, definition.form_id)
		if form == null or form.has_flag(FormBookEntry.FLAG_NO_MODEL):
			continue
		var model_id: int = EntityModelSelection.resource_for(data, level, form, definition)
		if model_id < 0:
			continue
		var model: MofFile = data.read_model(model_id, PackedStringArray())
		var label: String = "Entity %d model %d" % [definition.entity_index, model_id]
		definition.particle_hilites = hilites_of(model, table, label, diagnostics)


## The particle hilites of static model 0 of [param model], given the
## generator name per hilite type [param generators]; problems are reported
## under [param label] in [param diagnostics].
static func hilites_of(model: MofFile, generators: PackedStringArray, label: String, diagnostics: PackedStringArray) -> Array[ParticleHilite]:
	var result: Array[ParticleHilite] = []
	if model == null or model.static_models.is_empty():
		return result
	var parts: Array[MofPart] = model.static_models[0].parts
	for part_index: int in parts.size():
		var hilites: Array[MofPart.Hilite] = parts[part_index].hilites
		for hilite_index: int in hilites.size():
			var hilite: MofPart.Hilite = hilites[hilite_index]
			if hilite.type == HILITE_COLLISION:
				continue
			var place: String = "%s part %d hilite %d" % [label, part_index, hilite_index]
			var generator: String = generators[hilite.type] if hilite.type < generators.size() else ""
			var kind: int = kind_for_generator(generator)
			if kind < 0:
				diagnostics.append("%s: type %d starts no supported particle generator; omitted" % [place, hilite.type])
				continue
			if hilite.attach != MofPart.ATTACH_VERTEX:
				diagnostics.append("%s: attach type %d is not a vertex; omitted" % [place, hilite.attach])
				continue
			var particle := ParticleHilite.new()
			particle.kind = kind as ParticleHilite.Kind
			particle.part = part_index
			particle.vertex = hilite.index
			result.append(particle)
	return result


## The [enum ParticleHilite.Kind] of generator [param generator_name], or -1.
static func kind_for_generator(generator_name: String) -> int:
	match generator_name:
		"PGIN_hilite_exhaust":
			return ParticleHilite.Kind.EXHAUST
		"PGIN_hilite_dust":
			return ParticleHilite.Kind.DUST
		"PGIN_hilite_fire":
			return ParticleHilite.Kind.FIRE
	return -1
