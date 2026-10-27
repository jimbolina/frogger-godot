class_name RewardDefinition
extends RefCounted
## Typed detached SCORE_BOOK payload supplied by application setup.

const SCORE: int = 1
const LIGHT: int = 2
const TIME: int = 4
const REDUCE: int = 8
const LIFE: int = 16
const POWERUP: int = 32
var value: int = 0
var flags: int = 0

## Detaches the executable-derived values before gameplay retains them.
func copy() -> RewardDefinition:
	var result := RewardDefinition.new()
	result.value = value
	result.flags = flags
	return result
