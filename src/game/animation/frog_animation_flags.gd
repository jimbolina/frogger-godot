class_name FrogAnimationFlags
extends RefCounted
## FROG_ANIM and MR_ANIM_ENV masks transcribed from froganim.h and MR_ANIM.H.

const ACTIVE: int = 1 << 0
const QUEUE: int = 1 << 1
const BIN_IF_ANIM_PLAYING: int = 1 << 2
const OVERRIDE_PREV_ANIM: int = 1 << 3
const RESTORE_AFTER: int = 1 << 4
const DO_NOT_OVERRIDE: int = 1 << 5
const ENV_ONE_SHOT: int = 1 << 8
const ENV_STEP: int = 1 << 10
const ENV_UPDATE: int = 1 << 11
const ENV_DISPLAY: int = 1 << 12
const ENV_DEFAULT: int = ENV_STEP | ENV_UPDATE | ENV_DISPLAY
