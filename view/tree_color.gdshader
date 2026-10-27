shader_type canvas_item;
// Fase 16: colorea los árboles (el sprite viene en escala de grises). La parte baja de la imagen
// (tronco y raíces) sale café; la copa, del tono de follaje que manda `PlantView` como color de
// `draw_texture_rect` (uno distinto por árbol). El gris original da las luces y sombras.
// Fase 26: `snow` (invierno) blanquea las partes más claras de la copa, como nieve apoyada arriba.

uniform vec3 trunk_dark = vec3(0.20, 0.12, 0.06);
uniform vec3 trunk_light = vec3(0.62, 0.44, 0.27);
// Desde qué altura (0 arriba, 1 abajo) empieza el tronco; la mezcla es gradual para que la copa
// que cuelga sobre el tronco no quede cortada en seco.
uniform float trunk_from = 0.58;
uniform float trunk_to = 0.72;
uniform float snow = 0.0;
uniform vec3 snow_color = vec3(0.93, 0.96, 1.0);
// Fase 29: corta el sprite desde esta altura (0 arriba, 1 abajo) con un borde irregular en
// escalones de pixel: la copa del árbol madre se dibuja sin su tronco y sin un corte recto.
// 2.0 = no corta (los demás árboles).
uniform float leaf_cut = 2.0;

varying vec4 leaf_tint;

void vertex() {
	leaf_tint = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	if (leaf_cut < 1.5) {
		vec2 px = floor(UV / TEXTURE_PIXEL_SIZE / 2.0);
		float jag = fract(sin(px.x * 12.9898) * 43758.5453) * 0.1 + fract(sin(px.x * 3.17) * 1913.7) * 0.05;
		if (UV.y > leaf_cut - jag) {
			discard;
		}
	}
	float l = t.r;
	vec3 leaves = mix(leaf_tint.rgb * 0.22, min(leaf_tint.rgb * 1.25, vec3(1.0)), l);
	// La nieve se queda en lo iluminado (luz del sprite) y más en la mitad de arriba de la copa.
	float cover = snow * smoothstep(0.45, 0.75, l) * (1.0 - smoothstep(0.15, 0.55, UV.y) * 0.6);
	leaves = mix(leaves, snow_color * (0.75 + 0.25 * l), clamp(cover, 0.0, 1.0));
	vec3 trunk = mix(trunk_dark, trunk_light, l);
	float m = smoothstep(trunk_from, trunk_to, UV.y);
	COLOR = vec4(mix(leaves, trunk, m), t.a);
}
