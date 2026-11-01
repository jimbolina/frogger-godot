shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
#define TEXTURED
#define BLEND_AVERAGE
uniform sampler2D image : filter_nearest, repeat_disable;
#include "model_unlit.gdshaderinc"
