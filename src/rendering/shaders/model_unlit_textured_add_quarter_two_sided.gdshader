shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
#define TEXTURED
#define BLEND_ADD_QUARTER
uniform sampler2D image : filter_nearest, repeat_disable;
#include "model_unlit.gdshaderinc"
