class_name GameplayHudInk
extends Control
## Separate frozen-port averaged panels and opaque font glyphs for the HUD canvas.

class Glyph extends RefCounted:
	## One atlas glyph with a source-space destination and source tint.
	var at: Vector2
	var region: Rect2
	var colour: Color

var panels: Array[Rect2] = []
var glyphs: Array[Glyph] = []
var font_texture: Texture2D

## Selects source compositing without changing sibling sprite blending.
func configure(blending: CanvasItemMaterial.BlendMode) -> void:
	var ink := CanvasItemMaterial.new()
	ink.blend_mode = blending
	material = ink
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Appends one font atlas sample; draw submission remains on this canvas item.
func glyph(at: Vector2, region: Rect2, colour: Color) -> void:
	var sample := Glyph.new()
	sample.at = at
	sample.region = region
	sample.colour = colour
	glyphs.append(sample)

func _draw() -> void:
	for panel: Rect2 in panels:
		draw_rect(panel, Color(64.0 / 255.0, 64.0 / 255.0, 64.0 / 255.0, 0.5))
	if font_texture != null:
		for sample: Glyph in glyphs:
			draw_texture_rect_region(font_texture, Rect2(sample.at, sample.region.size), sample.region, sample.colour)
