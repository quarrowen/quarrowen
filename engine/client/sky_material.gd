extends RefCounted
## The realistic preset's sky: scattering, clouds and stars in one shader.
##
## `PhysicalSkyMaterial` gives real scattering and cannot draw a cloud, and an empty gradient is the
## single biggest thing missing from our sky - a real sky is mostly cloud. So this is a sky shader of
## our own: an analytic scattering approximation good enough to be indistinguishable at a glance, with
## two layers of cloud lit by the same sun, and the starfield behind. (2026-09-21)
##
## **Clouds are two layers of scrolling noise, not a raymarch.** A volumetric cloud is dozens of
## samples per pixel across the whole upper hemisphere, which is the sort of thing that turns a
## 60 fps preset into a 20 fps one - and the preset already has to earn its place on an M1 Air. Two
## layers at different heights and speeds, the lower one shaped by the upper, reads as depth from the
## ground, which is where the player is standing.
##
## The sun's position arrives as a uniform rather than being read from the DirectionalLight, so the
## sky and the world cannot disagree about where it is.

const SHADER_CODE := """
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.97, 0.92);
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float cloudiness : hint_range(0.0, 1.0) = 0.55;
uniform float wind_offset = 0.0;
uniform vec3 wind_direction = vec3(0.7, 0.0, -0.7);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.3;
uniform sampler2D stars : source_color, filter_linear;
uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform vec3 zenith_day : source_color = vec3(0.18, 0.37, 0.80);
uniform vec3 horizon_day : source_color = vec3(0.70, 0.82, 0.95);
uniform vec3 zenith_night : source_color = vec3(0.012, 0.018, 0.045);
uniform vec3 horizon_night : source_color = vec3(0.05, 0.06, 0.11);

// Noise arrives as a seamless texture built once at startup (FastNoiseLite, fractal) rather than
// being evaluated here. The hand-rolled version cost 32 sin() per pixel across the whole sky - 45 fps,
// measured - and a cloud has no detail worth that. Two taps at different scales give the same shape.
// (2026-09-21)

void sky() {
	// **Clouds are computed at half resolution and sampled back.** That is what use_half_res_pass is
	// for, and declaring it without branching on AT_HALF_RES_PASS merely adds a pass rather than
	// saving one: ten octaves of noise per pixel across the whole sky cost 45 fps, measured, which is
	// the same mistake SSAO made earlier today. A cloud has no detail at a pixel anyway. (2026-09-21)
	// if/else rather than an early return: a sky() function may not `return`, and doing so compiles to
	// nothing and draws a black sky - which then measured *faster*, because it was drawing nothing at
	// all. (2026-09-21)
	if (AT_HALF_RES_PASS) {
		vec3 d = EYEDIR;
		float u = clamp(d.y, -1.0, 1.0);
		if (u <= 0.0) {
			COLOR = vec3(0.0);
			ALPHA = 0.0;
		} else {
				vec2 plane = d.xz / max(u, 0.06) * 0.9;
				vec2 drift = wind_direction.xz * wind_offset;
				// A strong wind pulls cloud out into streaks along its own heading. Kept gentle: at
				// full strength it smears the puffs into overcast, which is the opposite of the point.
				plane -= wind_direction.xz * dot(plane, wind_direction.xz) * wind_strength * 0.15;
				float high = texture(cloud_noise, plane * 0.055 + drift * 0.06).r;
				vec2 low_uv = plane * 0.1 + drift * 0.1 + vec2(high * 0.08);
				float low_layer = texture(cloud_noise, low_uv).r;
				float edge = mix(0.70, 0.30, cloudiness);
				// Cumulus, not cirrus: a hard core with a thin fringe rather than a wide soft ramp. A
				// wide smoothstep can only ever give you haze. (2026-09-22)
				float density = smoothstep(edge, edge + 0.05, low_layer);
				density = mix(density, smoothstep(edge - 0.03, edge + 0.13, low_layer) * 0.4, 0.28);
				density = clamp(density * 1.5, 0.0, 1.0) * smoothstep(0.0, 0.13, u);

				// **Self-shadowing, which is what was actually missing.** The old lighting came from
				// the *view* direction against the sun, so every cloud in a given direction was lit
				// identically and the whole deck read as painted on. What gives a cloud bulk is that
				// its own far side is in its own shadow - so take one more tap a step toward the sun
				// and darken by how much cloud is in the way. One texture fetch for the entire
				// difference between "overcast" and "fluffy". (2026-09-22, the user: "i dont recall
				// seeing it")
				//
				// **One tap, not two.** The first version took two steps toward the sun for a softer
				// falloff and cost 30% of the frame with the sky filling the screen - 50 fps to 35,
				// repeatably. A single step at the far distance, with the near shading inferred from
				// this pixel's own density, is within a few percent of the look for half the cost.
				// The sky is drawn at half resolution but it is still every pixel above the horizon,
				// so a tap here is never cheap. (2026-09-22)
				vec2 sunward = normalize(sun_direction.xz + vec2(1e-4, 1e-4));
				float ahead = texture(cloud_noise, low_uv + sunward * 0.07).r;
				float shaded = smoothstep(edge - 0.02, edge + 0.20, ahead) * 0.7 + density * 0.3;

				float towards = max(dot(normalize(vec3(d.x, 0.35, d.z)), normalize(sun_direction)), 0.0);
				// Looking *up* at a cloud you mostly see its base, which is the shaded side.
				float under = 1.0 - smoothstep(0.1, 0.55, u);
				vec3 sunlit = mix(vec3(0.88, 0.90, 0.95), sun_tint * 1.6, pow(towards, 1.3));
				vec3 shadow_color = vec3(0.42, 0.45, 0.55);
				vec3 lit = mix(sunlit, shadow_color, shaded * 0.78);
				lit = mix(lit, shadow_color, under * 0.45);
				// A bright rim where the cloud thins out: the sun coming through the edge is half of
				// why a real cumulus reads as three-dimensional rather than as a cut-out.
				lit += sun_tint * (1.0 - density) * density * pow(towards, 2.0) * 0.9;
				lit = mix(lit * 0.35, lit, daylight);
				lit += sun_tint * pow(towards, 8.0) * (1.0 - density) * daylight * 0.8;
				COLOR = lit;
				ALPHA = density * 0.92;
			}
		} else {
		vec3 dir = EYEDIR;
		float up = clamp(dir.y, -1.0, 1.0);
		// Scattering, approximated: more air towards the horizon, so more of the blue is scattered out of
		// the line of sight and what is left is pale. The curve is what makes it read as atmosphere
		// rather than as a linear fade.
		float height = pow(clamp(up, 0.0, 1.0), 0.42);
		vec3 zenith = mix(zenith_night, zenith_day, daylight);
		vec3 horizon = mix(horizon_night, horizon_day, daylight);
		vec3 color = mix(horizon, zenith, height);

		// Mie scattering: the glow around the sun, and the warm band along the horizon under it. This is
		// what makes a sunset, and it falls out of the sun's own position rather than a ramp.
		float to_sun = max(dot(dir, normalize(sun_direction)), 0.0);
		float low = 1.0 - clamp(abs(sun_direction.y) * 2.0, 0.0, 1.0);
		vec3 warm = vec3(1.0, 0.55, 0.26);
		color += warm * pow(to_sun, 5.0) * low * daylight * 1.4;
		color += sun_tint * pow(to_sun, 900.0) * 14.0 * step(0.0, sun_direction.y);
		color += warm * pow(1.0 - abs(up), 14.0) * low * daylight * 0.5;

		// Stars, behind everything, fading as the sky brightens.
		float night = 1.0 - smoothstep(0.0, 0.42, daylight);
		if (night > 0.001) {
			vec2 star_uv = vec2(atan(dir.z, dir.x) / 6.2831853 + 0.5, acos(clamp(up, -1.0, 1.0)) / 3.1415927);
			color += texture(stars, star_uv).rgb * night;
		}

	// The clouds worked out in the half-resolution pass above.
		color = mix(color, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
		COLOR = color;
	}
}
"""


static func create(stars: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("stars", stars)
	material.set_shader_parameter("cloud_noise", _noise())
	return material


## Seamless fractal noise for the cloud deck, generated once.
##
## `seamless` matters: the deck tiles across the sky, and a visible join overhead is the kind of thing
## nobody can un-see once they have noticed it.
static func _noise() -> NoiseTexture2D:
	var source := FastNoiseLite.new()
	source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	source.frequency = 0.005
	source.fractal_type = FastNoiseLite.FRACTAL_FBM
	source.fractal_octaves = 5
	source.fractal_lacunarity = 2.1
	source.fractal_gain = 0.5
	var texture := NoiseTexture2D.new()
	texture.noise = source
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	return texture
