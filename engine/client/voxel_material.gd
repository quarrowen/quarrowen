extends RefCounted
## Materials for chunk meshes. Almost all of the "shader pack" look is precomputed into vertex data by
## the mesher, so per-pixel work stays tiny (one texture fetch plus arithmetic):
##   UV       texture coordinates in block units, repeated across greedy-merged quads
##   CUSTOM0  the tile's atlas rect
##   COLOR    r sky light, g block light, b directional face shade, a ambient occlusion
##   UV2.x    flags: 1 sway (foliage), 2 liquid, 4 emissive
## Uniforms carry time of day and the quality toggles from GraphicsSettings.

## The shader has two halves: the `unshaded` one every preset has always used, where the mesher's
## baked light *is* the final colour, and a **lit** one for the realistic preset, where the baked data
## becomes input to real lighting instead of a substitute for it. Chosen per material at creation, so
## no branch is paid for per pixel. (2026-09-21)
const SHADER_CODE := """
shader_type spatial;
render_mode %s%s;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
%s
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
	vec3 glint = vec3(0.0);
	// Set by anything that works out its own final colour (water). Everything else lets the lit
	// output derive albedo from the texture, or it would be lit twice - once by the unshaded
	// formula above and again by the renderer. (2026-09-21)
	bool custom = false;
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
	%s
}
"""

## What the unshaded half has always done: the computed colour *is* the pixel.
const UNSHADED_OUT := "ALBEDO = color;"

## The lit half. Three deliberate differences from above:
##
##   - **The baked face shade is dropped.** COLOR.b darkens the four side faces so a flat-lit world
##     still reads as three-dimensional. A real sun does that properly, and keeping both darkens
##     every north face twice.
##   - **Ambient occlusion becomes AO** rather than a multiplier on the final colour, so the engine
##     applies it to ambient light only - which is what it is for. Direct sun on a corner should not
##     be dimmed by the corner being a corner.
##   - **Block light becomes EMISSION.** A torch is not a light source the renderer knows about; the
##     mesher bakes its falloff into COLOR.g. Feeding that in as emission keeps torches glowing,
##     keeps caves working, and costs no real lights.
##
## Sky light still multiplies ALBEDO, which is not physically honest - albedo should not carry light.
## It is what keeps a cave dark without relying on a shadow map reaching underground, and swapping it
## for real shadows everywhere is the next question rather than this one.
## Translucent surfaces in the lit build keep the colour the water block computed - refraction, depth
## tint, reflection and glint are already in it, and recomputing ALBEDO from the texture would throw
## all of that away. Which is exactly what the first lit render did: the water went flat. (2026-09-21)
const LIT_TRANSLUCENT_OUT := """ALBEDO = custom ? color : tex.rgb * max(sky, 0.06);
	AO = enable_ao ? mix(0.35, 1.0, COLOR.a) : 1.0;
	EMISSION = glint;
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;"""

const LIT_OUT := """vec3 daylit = tex.rgb * max(sky, 0.06);
	ALBEDO = daylit;
	AO = enable_ao ? mix(0.35, 1.0, COLOR.a) : 1.0;
	AO_LIGHT_AFFECT = 1.0;
	EMISSION = tex.rgb * block * vec3(1.0, 0.82, 0.6) * 1.3;
	if (has_flag(flags, 4.0)) { EMISSION = tex.rgb * emissive_boost; }
	ROUGHNESS = 0.92;
	SPECULAR = 0.08;"""

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


## What the lit build adds at the top of the shader: the screen behind the surface, and how far away
## it is. Both are reads the cheap presets deliberately never do.
const LIT_TAPS := """uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.30, 0.62, 0.62);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.26);"""

## Water for the realistic preset: it is what water *does to what is behind it* that makes it read as
## water, and the cheap path cannot see behind itself at all.
##
##   - **Depth tint.** How far the floor is beneath the surface decides the colour, so a beach shelves
##     from clear green to deep blue instead of being one flat sheet.
##   - **Refraction.** The screen behind is sampled offset by the wave normal, so a shoreline bends.
##     The offset shrinks with depth, or shallow water tears at its own edge.
##   - **A real glint** rather than a power function on the sun vector, and it goes to EMISSION so the
##     tonemapper and bloom treat it like a bright thing rather than a pale patch.
const LIT_WATER := """
	if (has_flag(flags, 2.0)) {
		custom = true;
		vec3 view = normalize(world_pos - CAMERA_POSITION_WORLD);
		// Two wave sets at different scales and speeds; one alone reads as a moving pattern.
		bool surface = world_normal.y > 0.5;
		// **Finer and shallower than it was.** At a wavelength of about five blocks and an amplitude
		// of 0.07 these were not ripples: a grazing view swings fresnel hard on a small change of
		// normal, so gentle waves five blocks apart came out as broad white bands marching across the
		// lake, regular enough to look like a rendering fault. Real ripples are much finer than the
		// blocks they sit on. The two sets are also deliberately not aligned to the axes, or the
		// interference pattern itself becomes a grid. (2026-09-22)
		vec3 n = surface ? normalize(vec3(
			sin(dot(world_pos.xz, vec2(4.7, 2.1)) + TIME * 1.9) * 0.022
				+ sin(dot(world_pos.xz, vec2(-1.9, 5.3)) - TIME * 2.6) * 0.014,
			1.0,
			cos(dot(world_pos.xz, vec2(2.3, -4.9)) + TIME * 1.7) * 0.022
				+ cos(dot(world_pos.xz, vec2(5.1, 1.7)) + TIME * 2.3) * 0.014))
			: world_normal;
		float raw = texture(depth_texture, SCREEN_UV).r;
		vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		float floor_depth = -(behind.xyz / behind.w).z;
		float thickness = clamp((floor_depth + VERTEX.z) * 0.22, 0.0, 1.0);
		vec2 offset = surface ? n.xz * 0.045 * (1.0 - thickness * 0.6) : vec2(0.0);
		vec3 refracted = texture(screen_texture, SCREEN_UV + offset).rgb;
		vec3 tint = mix(shallow_color, deep_color, thickness);
		// The floor still shows through shallow water and stops showing through deep water.
		color = mix(refracted * mix(vec3(1.0), tint, 0.65), tint, thickness * 0.95) * max(daylight, 0.06);
		float fresnel = pow(1.0 - clamp(dot(-view, n), 0.0, 1.0), 5.0);
		// Only a surface mirrors. A wall of water seen from the side is something you look *through*,
		// and reflecting the sky off it turns a river's edge into a pane of glass.
		if (surface) {
			vec3 reflection = mix(horizon_color, sky_color, clamp(reflect(view, n).y * 1.5, 0.0, 1.0)) * max(daylight, 0.08);
			// **Reflect the world, not just the sky.** Water that mirrors the bank it runs past is
			// what makes water read as water; a fresnel tint of the sky colour reads as blue glass.
			// Godot's own screen-space reflections cannot help - they run on opaque geometry and
			// water is transparent - so this marches the reflected ray through the depth buffer.
			//
			// **The ray is converted to view space first, and that was the whole bug.** `view` and
			// `n` are world-space, so `reflect` gives a world-space direction; `VERTEX` is view
			// space. Marching one with the other walks off in a direction that means nothing, and
			// the march never hit anything - at any angle, over any water, with a reach of nine
			// blocks or of a hundred. It took forcing every hit to draw red to see that it was not
			// hitting at all rather than reflecting something dull. (2026-09-22)
			vec3 ray = normalize((VIEW_MATRIX * vec4(reflect(view, n), 0.0)).xyz);
			vec3 at = VERTEX;
			// Steps grow: fine near the surface where the reflection is sharp, coarse further out.
			float step_len = 0.22;
			// **Jittered, or the steps show.** Every pixel marching from the same offsets means every
			// pixel at a given distance hits or misses together, and the surface comes out banded in
			// stripes that follow constant range from the camera - which is what those white lines
			// across the lake were, not cloud reflections. Breaking the phase per pixel turns the
			// banding into noise, which the eye forgives. (2026-09-22)
			at += ray * fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453) * step_len;
			float hit = 0.0;
			vec2 hit_uv = vec2(0.0);
			for (int i = 0; i < 16; i++) {
				at += ray * step_len;
				step_len *= 1.36;
				vec4 clip = PROJECTION_MATRIX * vec4(at, 1.0);
				if (clip.w <= 0.0) { break; }
				vec2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
				if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { break; }
				float scene = texture(depth_texture, uv).r;
				vec4 world_at = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, scene, 1.0);
				float scene_z = -(world_at.xyz / world_at.w).z;
				float ray_z = -at.z;
				// Behind the surface by a plausible amount: a huge gap is the sky, or something far
				// away that the ray only appears to touch.
				if (ray_z > scene_z && ray_z - scene_z < 2.2) {
					// Walk back half a step a few times to land on the surface rather than wherever
					// the stride happened to stop: the difference between a reflection and a smear.
					vec3 back = at;
					float half_step = step_len * 0.5;
					for (int j = 0; j < 4; j++) {
						back -= ray * half_step;
						half_step *= 0.5;
						vec4 c2 = PROJECTION_MATRIX * vec4(back, 1.0);
						if (c2.w <= 0.0) { break; }
						vec2 u2 = (c2.xy / c2.w) * 0.5 + 0.5;
						float s2 = texture(depth_texture, u2).r;
						vec4 w2 = INV_PROJECTION_MATRIX * vec4(u2 * 2.0 - 1.0, s2, 1.0);
						if (-back.z > -(w2.xyz / w2.w).z) { back += ray * half_step; } else { uv = u2; }
					}
					hit = 1.0;
					hit_uv = uv;
					break;
				}
			}
			if (hit > 0.5) {
				// Faded at the screen edges, where the information simply is not there.
				vec2 edge = smoothstep(vec2(0.0), vec2(0.14), hit_uv) * smoothstep(vec2(0.0), vec2(0.14), 1.0 - hit_uv);
				reflection = mix(reflection, texture(screen_texture, hit_uv).rgb, edge.x * edge.y * 0.9);
			}
			// Capped well short of a mirror. Physically a grazing view is almost entirely reflection,
			// and a lake that obeyed that came out white - the sky is much brighter than the water,
			// so the colour washes out completely and what is left reads as milk. Water keeps some
			// of its own colour at every angle. (2026-09-22)
			// **Strong.** Capping this at two thirds was an over-correction after a lake came out
			// white: the reference water *is* bright silver where it mirrors sky and dark where it
			// mirrors a building, which is simply what a reflection does. Weakening it everywhere to
			// avoid the bright case cost the dark one too, and a roofline came out as a smudge.
			// (2026-09-22)
			color = mix(color, reflection, clamp(0.10 + 0.92 * fresnel, 0.0, 0.88));
			vec3 half_vector = normalize(normalize(sun_direction) - view);
			glint = sun_tint * pow(max(dot(n, half_vector), 0.0), 220.0) * daylight * 2.2;
		}
		// **Alpha follows depth, steeply.** A flat 0.45 meant a block of water with the ground right
		// behind it composited a refracted copy of that ground over the ground itself, at half
		// strength - which reads as a pale panel hanging in the grass, not as water. Where there is
		// nothing behind the surface there is nothing to tint, so it gets out of the way.
		ALPHA = clamp(0.08 + 0.42 * fresnel + thickness * 0.85, 0.0, 1.0);
	}
"""


static func create(atlas: Texture2D, translucent: bool, lit := false) -> ShaderMaterial:
	var shader := Shader.new()
	var mode := "" if lit else "unshaded, "
	var taps := LIT_TAPS if lit else ""
	if translucent:
		# Keeps writing depth, like every other preset. `depth_draw_never` was tried so the refraction
		# could not read the water drawing it - but the screen texture is captured before transparent
		# geometry anyway, so there was nothing to avoid, and it applied to *every* translucent block:
		# glass and foliage stopped writing depth and started sorting through each other. (2026-09-21)
		var render := TRANSLUCENT_RENDER
		var water := LIT_WATER if lit else TRANSLUCENT_EXTRA
		var out := LIT_TRANSLUCENT_OUT if lit else UNSHADED_OUT
		shader.code = SHADER_CODE % [mode, render, taps, TRANSLUCENT_ALPHA, water, out]
	else:
		shader.code = SHADER_CODE % [mode, SOLID_RENDER, taps, SOLID_ALPHA, SOLID_EXTRA,
			LIT_OUT if lit else UNSHADED_OUT]
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", atlas)
	return material
