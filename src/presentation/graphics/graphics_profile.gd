class_name GraphicsProfile
extends RefCounted
## The live graphics settings shared by every view.
##
## One persistent record stands behind [method current]; changes replace its
## values in place and go out once through its [signal Resource.changed], so
## subscribers keep the same record for the whole run.

static var _current: GraphicsSettings


## The live settings record, the same instance on every call.
static func current() -> GraphicsSettings:
	if _current == null:
		_current = GraphicsSettings.new()
	return _current


## Copies [param values] into the live record and emits its change once.
static func replace(values: GraphicsSettings) -> void:
	var live: GraphicsSettings = current()
	live.assign(values)
	live.emit_changed()


## Restores the defaults into the live record and emits its change once.
static func reset() -> void:
	replace(GraphicsSettings.new())
