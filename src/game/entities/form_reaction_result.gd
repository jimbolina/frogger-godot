class_name FormReactionResult
extends RefCounted
## Detached reaction of one geometric FORM query.

const NONE: String = "none"
const HIT: String = "hit"
const POP: String = "pop"
const SQUISH: String = "squish"
const SAFE: String = "safe"
const UNSUPPORTED: String = "unsupported"
const INVALID: String = "invalid"

var contact: FormContactResult = null
var status: String = NONE
var reason: String = ""
var hit: bool = false
var kill_animation: int = -1

## Returns an independently mutable reaction and contact.
func copy() -> FormReactionResult:
	var result := FormReactionResult.new()
	result.contact = contact.copy() if contact != null else null
	result.status = status
	result.reason = reason
	result.hit = hit
	result.kill_animation = kill_animation
	return result
