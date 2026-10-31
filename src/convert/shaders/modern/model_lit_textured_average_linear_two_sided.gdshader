shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, ambient_light_disabled;
#define TEXTURED
#define BLEND_AVERAGE
uniform sampler2D image : source_color, filter_linear_mipmap, repeat_disable;
#include "model_lit.gdshaderinc"
