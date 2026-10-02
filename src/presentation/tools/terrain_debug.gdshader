shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 projection_scale = vec2(1.0);
void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.xy *= projection_scale;
}
void fragment() {
	ALBEDO = tint.rgb;
}
