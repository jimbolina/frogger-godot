shader_type spatial;
render_mode unshaded, blend_sub, depth_draw_never, cull_disabled;
#define TEXTURED
#define BLEND_SUBTRACT
uniform sampler2D image : filter_linear_mipmap, repeat_disable;
#include "model_unlit.gdshaderinc"
