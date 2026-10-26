shader_type canvas_item;
// Fase 19: colorea los sprites de hongo (vienen en escala de grises y bastante oscuros). En vez de
// multiplicar (que los dejaba casi negros), usa el gris como luz: de la sombra del color del bolsón
// a una versión clara y brillante, para que se lea verde / morado / azul de un vistazo.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float l = clamp(t.r * 1.5, 0.0, 1.0);
	vec3 dark = tint.rgb * 0.18;
	vec3 bright = min(tint.rgb * 1.15 + vec3(0.03), vec3(1.0));
	COLOR = vec4(mix(dark, bright, l), t.a * tint.a);
}
