shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
#define MAP_LIT_TRANSLUCENT
#define MAP_LIT_AVERAGE
#define MAP_LIT_FAR
#include "map_lit.gdshaderinc"
