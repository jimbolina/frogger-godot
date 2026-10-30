class_name EntityParticleFields
extends RefCounted
## The particle fields of every live entity's model hilites, by entity slot.
##
## Source CreateLiveEntitySpecials (ENTITY.C:1766-1878) creates one generator
## per particle hilite when an entity goes live: [code]PGIN_hilite_exhaust[/code]
## for the exhaust and cloud types, [code]PGIN_hilite_dust[/code] for smoke
## and [code]PGIN_hilite_fire[/code] for fire. KillLiveEntitySpecials
## (ENTITY.C:1975-2003) flags each one [code]MR_OBJ_DESTROY_BY_DISPLAY[/code]
## when the entity retires; the dust and fire displays draw nothing once
## flagged and the object is destroyed with its display, so a released or
## replaced slot's fields end at once. Each field's random stream is seeded
## from the configured seed, the slot, the live generation and the hilite
## index, so captures repeat. Fields are presentation only and never touch
## gameplay state.

## Every generator an entity hilite can start, for [method ParticleSpriteView.configure].
const GENERATOR_NAMES: PackedStringArray = ["PGIN_hilite_exhaust", "PGIN_hilite_dust", "PGIN_hilite_fire"]
## Field kind per [enum ParticleHilite.Kind].
const FIELD_KINDS: Array[ParticleField.Kind] = [ParticleField.Kind.HILITE_EXHAUST, ParticleField.Kind.HILITE_DUST, ParticleField.Kind.HILITE_FIRE]

## The fields one live generation of an entity slot owns, in hilite order.
class Slot extends RefCounted:
	var generation: int = 0
	var fields: Array[ParticleField] = []

var _effects: EffectResources = null
var _seed: int = 0
var _slots: Dictionary[int, Slot] = {}


## Uses the generator records of [param effects] and seeds every field from
## [param seed]; drops all fields.
func configure(effects: EffectResources, seed: int) -> void:
	_effects = effects
	_seed = seed
	_slots.clear()


## (Re)creates the fields of entity [param slot] for live [param generation]
## from its model [param hilites]; does nothing when that generation already
## has them. A hilite whose record is unavailable gets a finished field, so
## hilite indices stay aligned.
func ensure(slot: int, generation: int, hilites: Array[ParticleHilite]) -> void:
	var current: Slot = _slots.get(slot)
	if current != null and current.generation == generation:
		return
	var created := Slot.new()
	created.generation = generation
	for hilite_index: int in hilites.size():
		var kind: int = hilites[hilite_index].kind
		var record: ParticleGeneratorRecord = _record(kind)
		created.fields.append(ParticleField.new(FIELD_KINDS[kind], record, 0, hash([_seed, slot, generation, hilite_index])))
	_slots[slot] = created


## Ends the fields of entity [param slot] when the entity retires.
func release(slot: int) -> void:
	_slots.erase(slot)


## Steps hilite [param hilite_index] of entity [param slot] once with its
## frame [param owner_m12], the owner's [param moving] test and committed
## [param colour_scale]; unknown slots and indices are ignored.
func step(slot: int, hilite_index: int, owner_m12: PackedInt32Array, moving: bool, colour_scale: Vector3i) -> void:
	var current: Slot = _slots.get(slot)
	if current == null or hilite_index < 0 or hilite_index >= current.fields.size():
		return
	current.fields[hilite_index].step(owner_m12, moving, colour_scale)


## Every field still drawing, in slot then hilite order.
func fields() -> Array[ParticleField]:
	var result: Array[ParticleField] = []
	var slots: Array[int] = []
	slots.assign(_slots.keys())
	slots.sort()
	for slot: int in slots:
		for field: ParticleField in _slots[slot].fields:
			if not field.finished:
				result.append(field)
	return result


## Drops every field at once.
func collapse() -> void:
	_slots.clear()


func _record(kind: int) -> ParticleGeneratorRecord:
	if _effects == null or _effects.generators == null or kind < 0 or kind >= GENERATOR_NAMES.size():
		return null
	return _effects.generators.find(GENERATOR_NAMES[kind])
