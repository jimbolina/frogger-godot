shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;
#define TEXTURED
#define BLEND_ADD_QUARTER
uniform sampler2D image : source_color, filter_nearest, repeat_disable;
#include "model.gdshaderinc"
