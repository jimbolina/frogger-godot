class_name EntityLiveFlags
extends RefCounted
## Named source bit values; numeric trace representations remain unchanged.

const DESTROY: int = (1 << 0)
const ANIMATED: int = (1 << 1)
const CARRIES_FROG_0: int = (1 << 2)
const CARRIES_FROG_1: int = (1 << 3)
const CARRIES_FROG_2: int = (1 << 4)
const CARRIES_FROG_3: int = (1 << 5)
const HIT_FROG_0: int = (1 << 6)
const HIT_FROG_1: int = (1 << 7)
const HIT_FROG_2: int = (1 << 8)
const HIT_FROG_3: int = (1 << 9)
const TARGETTED: int = (1 << 10)
const TONGUED: int = (1 << 11)
const FLIPBOOK: int = (1 << 12)
const RESPECT_SCALE_COLOURS: int = (1 << 13)
const RESPECT_AMBIENT_COLOURS: int = (1 << 14)
const NO_COLOUR_FADE: int = (1 << 15)
const NO_SCREEN_FADE: int = (1 << 16)
const CARRIES_FROG: int = (CARRIES_FROG_0 | CARRIES_FROG_1 | CARRIES_FROG_2 | CARRIES_FROG_3)
const HIT_FROG: int = (HIT_FROG_0 | HIT_FROG_1 | HIT_FROG_2 | HIT_FROG_3)
const CLEAR_MASK: int = (CARRIES_FROG | HIT_FROG | RESPECT_SCALE_COLOURS | RESPECT_AMBIENT_COLOURS)
