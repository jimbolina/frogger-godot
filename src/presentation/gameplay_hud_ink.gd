class_name GameplayHudInk
extends Control
## Separate frozen-port averaged panels and lines of newfont text for the HUD canvas.
##
## The text is linearly filtered: the font's page holds each retail pixel as a 4 x 4 block,
## so the glyph pixels stay even at any window scale and exact at whole-number scales up to 4.

class Line extends RefCounted:
	## One line of text with its top-left canvas corner and colour.
	var at: Vector2
	var text: String
	var colour: Color

var panels: Array[Rect2] = []
var lines: Array[Line] = []
var font: Font

## Selects source compositing without changing sibling sprite blending.
func configure(blending: CanvasItemMaterial.BlendMode) -> void:
	var ink := CanvasItemMaterial.new()
	ink.blend_mode = blending
	material = ink
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

## Appends one line of [param value] whose top-left canvas corner is [param at], drawn in
## [param colour] with [member font]; draw submission remains on this canvas item.
func text(at: Vector2, value: String, colour: Color) -> void:
	var line := Line.new()
	line.at = at
	line.text = value
	line.colour = colour
	lines.append(line)

func _draw() -> void:
	for panel: Rect2 in panels:
		draw_rect(panel, Color(64.0 / 255.0, 64.0 / 255.0, 64.0 / 255.0, 0.5))
	if font != null:
		for line: Line in lines:
			draw_string(font, NewfontText.baseline(line.at), line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NewfontText.DRAW_SIZE, line.colour)
