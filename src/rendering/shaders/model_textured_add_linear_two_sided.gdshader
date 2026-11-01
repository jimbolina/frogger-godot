shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, ambient_light_disabled;
#define TEXTURED
#define BLEND_ADD
uniform sampler2D image : source_color, filter_linear_mipmap, repeat_disable;
#include "model.gdshaderinc"
