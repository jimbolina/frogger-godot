shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back;
#define MAP_LIT_TRANSLUCENT
#define MAP_LIT_QUARTER
#define MAP_LIT_FAR
#include "map_lit.gdshaderinc"
