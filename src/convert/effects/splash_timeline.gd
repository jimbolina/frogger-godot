class_name SplashTimeline
extends RefCounted
## A 3D sprite's animation list as MRProcessSpriteAnim runs it (MR_SPRT.C:975-1350).
##
## A sprite starts with no image, scale 4<<16, colour 0x808080, speed 1 and
## count 1. Each [method update] decrements the count; at zero it runs
## commands until one stops (NOP, SETIMAGE and KILL stop; SETSPEED, SETSCALE
## and SETCOLOUR continue), reloading the count from the speed after each.
## KILL keeps its position and marks the sprite for removal at display.
## [method splash_list] is FrogSplashAnimList (COLLIDE.C:43-65), which
## TurtleSplashAnimList (scripter.c:31-55) repeats.

## Source MR_SPRT commands the splash lists use.
enum Op { NOP, SETIMAGE, SETSPEED, SETSCALE, SETCOLOUR, KILL }

## Default MRCreate3DSprite scale, colour, speed and count.
const DEFAULT_SCALE: int = 4 << 16
const DEFAULT_COLOUR: int = 0x808080
const DEFAULT_SPEED: int = 1
const FORCE_NEXT: int = 1
const OP_NAMES: PackedStringArray = ["NOP", "SETIMAGE", "SETSPEED", "SETSCALE", "SETCOLOUR", "KILL"]

## One list command with its value or image symbol.
class Command extends RefCounted:
	var op: Op = Op.NOP
	var value: int = 0
	var image: String = ""

	func _init(command_op: Op = Op.NOP, command_value: int = 0, command_image: String = "") -> void:
		op = command_op
		value = command_value
		image = command_image

var commands: Array[Command] = []
## Current image symbol, "" before the first SETIMAGE.
var image: String = ""
## 16.16 scale.
var scale: int = DEFAULT_SCALE
## Packed grey colour.
var colour: int = DEFAULT_COLOUR
var speed: int = DEFAULT_SPEED
var count: int = FORCE_NEXT
var position: int = 0
var killed: bool = false
## Updates run so far.
var updates: int = 0
## Command names the latest update ran.
var executed: PackedStringArray = PackedStringArray()


func _init(list: Array[Command] = []) -> void:
	commands = list if not list.is_empty() else splash_list()


## Runs one MRUpdateObjects step of the list.
func update() -> void:
	executed = PackedStringArray()
	if killed:
		return
	updates += 1
	count -= 1
	if count != 0:
		return
	while position < commands.size():
		var command: Command = commands[position]
		executed.append(OP_NAMES[command.op])
		match command.op:
			Op.SETSPEED:
				speed = command.value
			Op.SETSCALE:
				scale = command.value
			Op.SETCOLOUR:
				colour = command.value
			Op.SETIMAGE:
				image = command.image
		if command.op == Op.KILL:
			killed = true
		else:
			position += 1
		count = speed
		if command.op not in [Op.SETSPEED, Op.SETSCALE, Op.SETCOLOUR]:
			break


## True while the sprite shows an image.
func drawn() -> bool:
	return not killed and not image.is_empty()


## Colour bytes (r, g, b) of the current packed colour.
func rgb() -> Vector3i:
	return Vector3i((colour >> 16) & 0xff, (colour >> 8) & 0xff, colour & 0xff)


## The source frog and turtle splash list with its six ripple image symbols.
static func splash_list(ripples: PackedStringArray = EffectResources.RIPPLE_SYMBOLS) -> Array[Command]:
	var list: Array[Command] = [Command.new(Op.NOP), Command.new(Op.NOP), Command.new(Op.NOP), Command.new(Op.NOP),
		Command.new(Op.SETSPEED, 2), Command.new(Op.SETSCALE, 8 << 16)]
	for symbol: String in ripples:
		list.append(Command.new(Op.SETIMAGE, 0, symbol))
	var last: String = ripples[ripples.size() - 1]
	for fade: int in ExeSplashAnimLists.FADES:
		list.append(Command.new(Op.SETCOLOUR, fade))
		list.append(Command.new(Op.SETIMAGE, 0, last))
	list.append(Command.new(Op.KILL))
	return list
