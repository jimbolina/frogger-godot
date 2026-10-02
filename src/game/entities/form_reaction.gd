class_name FormReaction
extends RefCounted
## Pure bounded reaction for a geometric FORM contact.

## Evaluates supported source flag precedence without changing frog state.
static func evaluate(definition: FormContactDefinition, contact: FormContactResult) -> FormReactionResult:
	var result := FormReactionResult.new()
	result.contact = contact.copy() if contact != null else null
	if definition == null or contact == null:
		result.status = FormReactionResult.INVALID
		result.reason = "Reaction requires a definition and contact"
		return result
	if contact.entity_index != definition.entity_index or contact.unique_id != definition.unique_id or contact.form_grid_id != definition.form_grid_id or contact.form_id != definition.form_id:
		result.status = FormReactionResult.INVALID
		result.reason = "Reaction contact identity does not match definition"
		return result
	if contact.status == FormContactResult.INVALID:
		result.status = FormReactionResult.INVALID
		result.reason = contact.reason
		return result
	if contact.status == FormContactResult.UNSUPPORTED:
		result.status = FormReactionResult.UNSUPPORTED
		result.reason = contact.reason
		return result
	if contact.status != FormContactResult.CONTACT:
		return result
	if not definition.reaction_unsupported_reason.is_empty():
		result.status = FormReactionResult.UNSUPPORTED
		result.reason = definition.reaction_unsupported_reason
		return result
	var flags: int = contact.cell_flags
	if (flags & 1) == 0:
		return result
	if flags & 64:
		result.status = FormReactionResult.UNSUPPORTED
		result.reason = "FORM checkpoint reaction is unsupported"
	elif flags & 2:
		result.status = FormReactionResult.UNSUPPORTED
		result.reason = "FORM safe attachment is unsupported"
	elif flags & 4096:
		result.status = FormReactionResult.POP
		result.kill_animation = 23
		result.hit = true
	elif flags & 4:
		if definition.death_type == 5:
			result.status = FormReactionResult.POP
			result.kill_animation = 23
			result.hit = true
		else:
			result.status = FormReactionResult.UNSUPPORTED
			result.reason = "FORM death type %d is unsupported" % definition.death_type
	elif flags & 16:
		result.status = FormReactionResult.HIT
		result.hit = true
	elif flags & 32:
		result.status = FormReactionResult.UNSUPPORTED
		result.reason = "FORM bounce reaction is unsupported"
	else:
		result.status = FormReactionResult.HIT
		result.hit = true
	return result
