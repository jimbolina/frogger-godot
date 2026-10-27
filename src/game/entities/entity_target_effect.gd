class_name EntityTargetEffect
extends RefCounted
## Ordered switch request against a live authored unique identity.

enum Kind { INITIALIZE, TOGGLE, REVERSE }

var unique_id: int = -1
var kind: Kind = Kind.INITIALIZE

## Creates one source-ordered cross-entity request.
static func create(identity: int, operation: Kind) -> EntityTargetEffect:
	var result := EntityTargetEffect.new()
	result.unique_id = identity
	result.kind = operation
	return result
