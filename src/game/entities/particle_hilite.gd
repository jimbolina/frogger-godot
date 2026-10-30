class_name ParticleHilite
extends RefCounted
## One particle generator an entity model's hilite starts when the entity goes live.
##
## Source CreateLiveEntitySpecials (ENTITY.C:1766-1878) reads static model 0
## of the entity's model and creates the generator its hilite type selects
## through Entity_special_particle_generators at the hilite's partcel-0
## vertex. Effects are presentation only; gameplay never reads these.

## Which generator the hilite creates: PGIN_hilite_exhaust, PGIN_hilite_dust or PGIN_hilite_fire.
enum Kind { EXHAUST, DUST, FIRE }

var kind: Kind = Kind.EXHAUST
## Part of static model 0 the vertex belongs to.
var part: int = 0
## Vertex index in that part's partcel 0.
var vertex: int = 0


## Returns an independent value.
func copy() -> ParticleHilite:
	var result := ParticleHilite.new()
	result.kind = kind
	result.part = part
	result.vertex = vertex
	return result
