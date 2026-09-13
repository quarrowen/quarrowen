extends RefCounted
## Materials for chunk meshes. Almost all of the "shader pack" look is precomputed into vertex data by
## the mesher, so per-pixel work stays tiny (one texture fetch plus arithmetic):
##   UV       texture coordinates in block units, repeated across greedy-merged quads
##   CUSTOM0  the tile's atlas rect
##   COLOR    r sky light, g block light, b directional face shade, a ambient occlusion
##   UV2.x    flags: 1 sway (foliage), 2 liquid, 4 emissive
## Uniforms carry time of day and the quality toggles from GraphicsSettings.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, %s;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_scissor = 0.5;
uniform bool enable_sway = true;
uniform bool enable_ao = true;
uniform bool fancy_water = true;
uniform float emissive_boost = 1.0;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 sky_color : source_color = vec3(0.32, 0.54, 0.92);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.96);
uniform vec3 sun_direction = vec3(0.4, 0.8, 0.45);

varying vec4 tile;
varying float flags;
varying vec3 world_pos;
varying vec3 world_normal;

bool has_flag(float value, float bit) {
	return mod(floor(value / bit), 2.0) >= 1.0;
}

void vertex() {
	tile = CUSTOM0;
	flags = UV2.x;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (enable_sway && has_flag(flags, 1.0)) {
		float t = TIME * 1.6 + world_pos.x * 0.35 + world_pos.z * 0.27;
		VERTEX.x += sin(t) * 0.035;
		VERTEX.z += cos(t * 0.8) * 0.035;
	}
	if (fancy_water && has_flag(flags, 2.0) && NORMAL.y > 0.5) {
		VERTEX.y += sin(TIME * 1.3 + world_pos.x * 0.7 + world_pos.z * 0.5) * 0.025 - 0.025;
	}
}

void fragment() {
	// Inset slightly so neighbouring atlas tiles never bleed in at block edges.
	vec2 local = clamp(fract(UV), vec2(0.001), vec2(0.999));
	vec4 tex = texture(atlas, tile.xy + local * tile.zw);
	%s
	float sky = pow(0.8, (1.0 - COLOR.r) * 15.0) * daylight;
	float block = pow(0.8, (1.0 - COLOR.g) * 15.0);
	vec3 light = max(sun_tint * sky, vec3(block) * vec3(1.0, 0.82, 0.6));
	float ao = enable_ao ? mix(0.42, 1.0, COLOR.a) : 1.0;
	vec3 color = tex.rgb * max(light, vec3(0.025)) * COLOR.b * ao;
	if (has_flag(flags, 4.0)) {
		// Light sources render at full brightness; values above 1 feed the bloom pass.
		color = max(color, tex.rgb * emissive_boost);
	}
	%s
	ALBEDO = color;
}
"""

const SOLID_RENDER := "cull_back, depth_draw_opaque"
const SOLID_ALPHA := "if (tex.a < alpha_scissor) { discard; }"
const SOLID_EXTRA := ""

const TRANSLUCENT_RENDER := "cull_disabled, blend_mix, depth_draw_opaque"
const TRANSLUCENT_ALPHA := "ALPHA = tex.a;"
## Water: cheap analytic ripples, sky reflection with Fresnel falloff and a sun glint. No reflection
## passes or screen reads.
const TRANSLUCENT_EXTRA := """
	if (fancy_water && has_flag(flags, 2.0) && world_normal.y > 0.5) {
		vec3 view = normalize(world_pos - CAMERA_POSITION_WORLD);
		vec3 n = normalize(vec3(
			sin(world_pos.x * 1.3 + TIME * 1.5) * 0.06 + sin(world_pos.z * 2.1 - TIME * 1.1) * 0.03,
			1.0,
			cos(world_pos.z * 1.2 + TIME * 1.3) * 0.06 + cos(world_pos.x * 1.9 + TIME * 0.9) * 0.03));
		float fresnel = pow(1.0 - clamp(dot(-view, n), 0.0, 1.0), 4.0);
		vec3 r = reflect(view, n);
		vec3 reflection = mix(horizon_color, sky_color, clamp(r.y * 1.5, 0.0, 1.0)) * max(daylight, 0.08);
		color = mix(color, reflection, 0.2 + 0.7 * fresnel);
		color += pow(max(dot(r, normalize(sun_direction)), 0.0), 80.0) * daylight * sun_tint * 1.5;
		ALPHA = mix(0.6, 0.95, fresnel);
	}
"""


static func create(atlas: Texture2D, translucent: bool) -> ShaderMaterial:
	var shader := Shader.new()
	if translucent:
		shader.code = SHADER_CODE % [TRANSLUCENT_RENDER, TRANSLUCENT_ALPHA, TRANSLUCENT_EXTRA]
	else:
		shader.code = SHADER_CODE % [SOLID_RENDER, SOLID_ALPHA, SOLID_EXTRA]
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", atlas)
	return material
