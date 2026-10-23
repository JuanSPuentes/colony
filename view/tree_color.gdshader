shader_type canvas_item;
// Fase 16: colorea los árboles (el sprite viene en escala de grises). La parte baja de la imagen
// (tronco y raíces) sale café; la copa, del tono de follaje que manda `PlantView` como color de
// `draw_texture_rect` (uno distinto por árbol). El gris original da las luces y sombras.

uniform vec3 trunk_dark = vec3(0.20, 0.12, 0.06);
uniform vec3 trunk_light = vec3(0.62, 0.44, 0.27);
// Desde qué altura (0 arriba, 1 abajo) empieza el tronco; la mezcla es gradual para que la copa
// que cuelga sobre el tronco no quede cortada en seco.
uniform float trunk_from = 0.58;
uniform float trunk_to = 0.72;

varying vec4 leaf_tint;

void vertex() {
	leaf_tint = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float l = t.r;
	vec3 leaves = mix(leaf_tint.rgb * 0.22, min(leaf_tint.rgb * 1.25, vec3(1.0)), l);
	vec3 trunk = mix(trunk_dark, trunk_light, l);
	float m = smoothstep(trunk_from, trunk_to, UV.y);
	COLOR = vec4(mix(leaves, trunk, m), t.a);
}
