shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled;
#define TEXTURED
#define BLEND_OPAQUE
uniform sampler2D image : filter_nearest, repeat_disable;
#include "model_unlit.gdshaderinc"
