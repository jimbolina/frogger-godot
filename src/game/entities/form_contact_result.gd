class_name FormContactResult
extends RefCounted
## Detached outcome of one frog-point versus entity FORM contact query.

const CONTACT: String = "contact"
const MISS: String = "miss"
const DISABLED: String = "disabled"
const UNSUPPORTED: String = "unsupported"
const INVALID: String = "invalid"

var status: String = INVALID
var reason: String = ""
var entity_index: int = -1
var unique_id: int = 0
var form_grid_id: int = -1
var form_id: int = -1
var form_name: String = ""
var local_position: Vector3i = Vector3i.ZERO
var cell: Vector2i = Vector2i(-1, -1)
var height: int = 0
var cell_flags: int = 0

## Returns a detached copy of the contact outcome.
func copy() -> FormContactResult:
	var result := FormContactResult.new()
	result.status = status
	result.reason = reason
	result.entity_index = entity_index
	result.unique_id = unique_id
	result.form_grid_id = form_grid_id
	result.form_id = form_id
	result.form_name = form_name
	result.local_position = local_position
	result.cell = cell
	result.height = height
	result.cell_flags = cell_flags
	return result
