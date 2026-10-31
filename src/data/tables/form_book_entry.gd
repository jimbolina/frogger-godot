class_name FormBookEntry
extends Resource
## One "form": the kind of object an entity on a map is (a car, a log, a bug...).
##
## Each theme has a library of forms in the executable, 32 bytes each
## (FrogLord's [code]FroggerFormEntry[/code]):
## [codeblock]
## s32 entity type      (behaviour; names in FrogLord's entity list)
## s32 model id         (index into the theme's WAD; 128 and up = the GENERAL WAD)
## s32 script id        (entity script, 0 = none)
## s32 flags            (see the FLAG_ constants)
## u32 collision callback (address of game code run when the frog touches it)
## s32 radius squared
## s32 death type       (how the frog dies, see [FroggerIds])
## u32 bonus callback   (address of game code run when it is eaten)
## [/codeblock]
## Callback addresses refer to original compiled game code and are retained
## for diagnostics. Application setup resolves a verified per-build address
## to a known name, then selects a supported implementation by that name.
## Unknown mappings remain excluded; script CallbackNames are a separate list.
##
## Maps refer to a form by a "form book id": the form's number inside its
## theme, with bit 15 ([constant GENERAL_BIT]) set for GENERAL forms.

## Size of a form in bytes.
const SIZE: int = 32
## Bit set in a map's form id when the form comes from the GENERAL theme.
const GENERAL_BIT: int = 0x8000
## Model ids from here on are in the GENERAL theme's WAD.
const FIRST_GENERAL_MODEL: int = 128

## Sprite rather than a model; no collision-primitive collision.
const FLAG_NO_MODEL: int = 1 << 0
## Frog rotation is not snapped when landing on it (lily pads).
const FLAG_NO_ROTATION_SNAPPING: int = 1 << 1
## No entity angle is calculated.
const FLAG_NO_ENTITY_ANGLE: int = 1 << 2
## Not reset when a checkpoint is collected.
const FLAG_DONT_RESET_ON_CHECKPOINT: int = 1 << 3
## Not reset when the frog dies.
const FLAG_DONT_RESET_ON_DEATH: int = 1 << 4
## Collision extends below the model.
const FLAG_THICK: int = 1 << 5
## Frog not centred along the entity's X axis, except at the ends.
const FLAG_DONT_CENTER_X: int = 1 << 6
## Frog not centred along the entity's Z axis, except at the ends (logs).
const FLAG_DONT_CENTER_Z: int = 1 << 7
## No colour fading for sprites (caves).
const FLAG_DONT_FADE_COLOR: int = 1 << 8
## Form depth forced to 256 units.
const FLAG_UNIT_FORM: int = 1 << 9

## Theme number the form belongs to.
@export var theme: int = 0
## Position inside the theme's library.
@export var local_id: int = 0
## Position in the whole game's form list (all themes in theme order); the
## index into FrogLord's form name list.
@export var global_id: int = 0
## Form name from FrogLord's list, e.g. "ORG_CAR_BLUE".
@export var form_name: String = ""
## Entity type number.
@export var entity_type: int = 0
## Entity type name (FrogLord's list, after its per-form overrides).
@export var entity_name: String = ""
## Model index (see [method wad_index]).
@export var model_id: int = 0
## Entity script number.
@export var script_id: int = 0
## Flag bits (FLAG_ constants).
@export var flags: int = 0
## Address of the collision callback in the game code (0 = none).
@export var collision_callback: int = 0
## Squared bounding radius.
@export var radius_squared: int = 0
## Death type number.
@export var death_type: int = 0
## Address of the bonus (eaten) callback in the game code (0 = none).
@export var bonus_callback: int = 0


## Reads one form at [param reader]'s cursor (see [ThemeBookRowReader]).
static func read(reader: ByteReader, theme_number: int, local: int, global: int) -> FormBookEntry:
	return ThemeBookRowReader.read_form(reader, theme_number, local, global)


## True if flag bit(s) [param flag] are set.
func has_flag(flag: int) -> bool:
	return flags & flag == flag


## The id a map uses for this form ([constant GENERAL_BIT] added for GENERAL forms).
func map_form_id() -> int:
	return local_id | GENERAL_BIT if theme == FroggerIds.THEME_GENERAL else local_id


## True when the model comes from the GENERAL theme's WAD.
func uses_general_wad() -> bool:
	return theme == FroggerIds.THEME_GENERAL or model_id >= FIRST_GENERAL_MODEL


## Position of the model in its WAD (GENERAL models are numbered from 128).
func wad_index() -> int:
	return model_id - FIRST_GENERAL_MODEL if uses_general_wad() else model_id


## Name of the death type, e.g. "DROWN".
func death_type_name() -> String:
	return FroggerIds.death_type_name(death_type)
