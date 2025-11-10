shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D albedo : source_color;

void fragment() {
	vec4 tex = texture(albedo, SCREEN_UV);
	ALBEDO = tex.rgb;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
