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
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.3);
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
				float high = texture(cloud_noise, plane * 0.055 + drift * 0.06).r;
				float low_layer = texture(cloud_noise, plane * 0.1 + drift * 0.1 + vec2(high * 0.08)).r;
				float edge = mix(0.66, 0.28, cloudiness);
				float density = smoothstep(edge, edge + 0.10, low_layer);
				density = mix(density, smoothstep(edge - 0.06, edge + 0.20, low_layer) * 0.55, 0.45);
				density = clamp(density * 1.35, 0.0, 1.0) * smoothstep(0.0, 0.16, u);
				float towards = max(dot(normalize(vec3(d.x, 0.35, d.z)), normalize(sun_direction)), 0.0);
				vec3 lit = mix(vec3(0.45, 0.48, 0.55), sun_tint * 1.35, pow(towards, 1.6));
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
