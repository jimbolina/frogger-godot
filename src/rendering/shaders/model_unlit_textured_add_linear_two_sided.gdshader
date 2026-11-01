shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
#define TEXTURED
#define BLEND_ADD
uniform sampler2D image : filter_linear_mipmap, repeat_disable;
#include "model_unlit.gdshaderinc"
