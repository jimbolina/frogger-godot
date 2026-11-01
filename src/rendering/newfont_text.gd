class_name NewfontText
extends RefCounted
## Where a line of [code]newfont[/code] text lands on the 640 x 480 canvas.
##
## Every glyph of the retail font is one fixed cell wide and high, so a line's
## width follows from its length, and its top-left corner sits one cell above
## the baseline that [method CanvasItem.draw_string] takes.

## Width and height of one glyph in canvas pixels.
const CELL: int = 8
## The size both fonts are drawn at: the retail font's fixed size, to which
## the x4 font's fixed size of 32 scales down.
const DRAW_SIZE: int = 8


## The canvas width of [param text]: one cell per character.
static func width(text: String) -> int:
	return text.length() * CELL


## The baseline to pass to [method CanvasItem.draw_string] for a line whose
## top-left corner is [param at]; the font's ascent is one cell.
static func baseline(at: Vector2) -> Vector2:
	return at + Vector2(0, CELL)
