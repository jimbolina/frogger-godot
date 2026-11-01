shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;
#define TEXTURED
#define BLEND_OPAQUE
uniform sampler2D image : source_color, filter_linear_mipmap, repeat_disable;
#include "model.gdshaderinc"
