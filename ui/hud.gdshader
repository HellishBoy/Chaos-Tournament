shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_edge : hint_range(0.0, 1.0) = 0.4;
uniform vec4 vignette_color : source_color = vec4(0.5, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float vignette = smoothstep(inner_edge, 1.2, length(uv));
	COLOR = vec4(vignette_color.rgb, vignette * intensity);
}