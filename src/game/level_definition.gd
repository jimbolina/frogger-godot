class_name LevelDefinition
extends RefCounted
## Setup-supplied terrain and scalar source identity for a single-player run.

var grid: GridDefinition = null
var entity_collision: EntityCollisionDefinition = null
## Optional inspection restriction; null leaves ordinary terrain behavior unchanged.
var exploration_guard: ExplorationGuard = null
var source_id: String = ""
var resource_id: int = -1
## Source Map_library index (Game_map), distinct from archive resource identity.
var map_index: int = -1
var spawn_cell: Vector2i = Vector2i.ZERO
var spawn_direction: int = 0
var camera_bounds: Rect2i = Rect2i()
## Component fixtures may omit collision; actual play supplies source fade/death limits.
var collision_enabled: bool = false
var collision_bounds: Rect2i = Rect2i(Vector2i(-32767, -32767), Vector2i(65534, 65534))
var theme_death_height: int = 30000
var theme: int = 0
## Optional only for explicitly isolated component fixtures. Integrated runs supply both.
var camera: GameplayCameraDefinition = null
var frog_action_lengths: PackedInt32Array = PackedInt32Array()
var theme_name: StringName = &"SUB"
