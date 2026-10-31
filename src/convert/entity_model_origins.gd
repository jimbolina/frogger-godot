class_name EntityModelOrigins
extends RefCounted
## Per-slot source theme and level that resolve entity models when no map scene supplies them.

## Borrowed player data; the caller keeps it open while any consumer draws from it.
var data: AssetCatalog = null
## Theme book index owning each slot's form, or -1 for a slot drawn as a placeholder.
var themes: PackedInt32Array = PackedInt32Array()
## Level number selecting each slot's model WAD, or -1 for a slot drawn as a placeholder.
var levels: PackedInt32Array = PackedInt32Array()

## Borrows `game_data`, which may be null when every slot uses a placeholder.
func _init(game_data: AssetCatalog = null) -> void:
	data = game_data

## Appends the next slot's origin; negative values request a placeholder.
func add(theme: int, level: int) -> void:
	themes.append(theme)
	levels.append(level)

## Number of recorded slots.
func size() -> int:
	return themes.size()

## Whether `slot` names a theme and level that a model lookup can use.
func resolvable(slot: int) -> bool:
	return slot >= 0 and slot < themes.size() and slot < levels.size() and themes[slot] >= 0 and levels[slot] >= 0
