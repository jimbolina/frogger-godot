class_name FrogAnimationContext
extends RefCounted
## Run-owned shared animation condition counter and source random stream.

var random: SourceRandom
var theme: StringName = &"SUB"
var if_counter: int = 0

## Borrows the run's random stream; metadata setup supplies the source theme name.
static func create(source_random: SourceRandom, theme_name: StringName = &"SUB") -> FrogAnimationContext:
	var result := FrogAnimationContext.new()
	result.random = source_random
	result.theme = theme_name
	return result

## Copies condition state while borrowing the copied run's shared random stream.
func copy(source_random: SourceRandom) -> FrogAnimationContext:
	var result: FrogAnimationContext = create(source_random, theme)
	result.if_counter = if_counter
	return result
