extends RefCounted
## Graphics presets. Everything here is chosen to stay cheap on integrated GPUs (baseline: base M1
## MacBook Air): lighting and occlusion are baked into chunk meshes, the block shader does one texture
## fetch, bloom uses only a few small mip levels, and the "fast" preset renders 3D at reduced
## resolution with FSR upscaling. No real-time shadows, SSAO, SSR or global illumination.

const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const PRESETS := ["fast", "balanced", "fancy", "realistic"]

## The current preset name ("custom" when the player changed single toggles). Values live in the shared
## client settings (engine/client/settings/client_settings.gd).
var preset: String:
	get:
		return ClientSettings.shared().get_value("graphics/preset")


func load_saved() -> void:
	pass  # the shared settings load on first use


## F4: the next preset (from "custom", back to the first).
func cycle() -> void:
	var i := PRESETS.find(preset)
	ClientSettings.shared().set_value("graphics/preset", PRESETS[(i + 1) % PRESETS.size()])


func value(key: String):
	return ClientSettings.shared().get_value("graphics/" + key)


## Applies post-processing and resolution settings. Material and mesher toggles are applied by the
## client since they need its materials and a remesh.
func apply_environment(env: Environment, viewport: Viewport) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if value("grading") else Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = value("bloom")
	if value("bloom"):
		# Only the mid/low-resolution mips: soft halos around lights for very little fill rate.
		for level in 7:
			env.set_glow_level(level, 0.0)
		env.set_glow_level(3, 0.8)
		env.set_glow_level(4, 1.0)
		env.set_glow_level(5, 0.7)
		env.glow_intensity = 1.0
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.05
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = value("grading")
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	apply_realism(env, bool(value("realistic")))
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value("fxaa") else Viewport.SCREEN_SPACE_AA_DISABLED
	var scale: float = value("render_scale")
	viewport.scaling_3d_scale = scale
	# **FSR is Forward+ only, and mobile devices do not run Forward+.** Godot's default
	# `rendering_method.mobile` is the Mobile renderer, so every iOS and Android build takes this path -
	# and asking for FSR there printed "FSR1 3D scaling is only available when using the Forward+
	# renderer" on every launch and then silently upscaled some other way. It mattered more than a
	# stray warning suggests: dropping the render scale is exactly the lever you reach for on a tablet,
	# so the one upscaler we use was the one unavailable where it was most needed. Found by running the
	# Mobile renderer on the desktop, which nothing had ever done. (2026-09-25)
	var fsr_available := RenderingServer.get_current_rendering_method() == "forward_plus"
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 and fsr_available \
		else Viewport.SCALING_3D_MODE_BILINEAR


## The realistic preset's half of the environment. Split out so it can be turned on and off while the
## game is running rather than only at startup - somebody whose frame rate has collapsed should be
## able to get it back from the settings screen without restarting.
##
## Sun shadows themselves live on the light, not here; see `light_the_sun` in game_client.gd.
## Which parts of the realistic preset to leave off, for finding out what a frame is being spent on:
##   QW_REAL_OFF=ssil,ssao,shadows,lit,sky
## Empty in normal use. Bisecting beats guessing, and 22 fps on a 24-core M1 Max is not a preset being
## expensive - it is something being wrong. (2026-09-21)
static func off(part: String) -> bool:
	return part in OS.get_environment("QW_REAL_OFF").split(",", false)


static func apply_realism(env: Environment, on: bool) -> void:
	# Light from the sky rather than a flat white wash is most of the difference: it makes the shaded
	# side of things take the sky's colour instead of going evenly grey.
	var sky_ambient := on and not off("sky")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if sky_ambient else Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.9 if on else 0.55
	env.ambient_light_sky_contribution = 1.0 if sky_ambient else 0.0
	# **No SSAO.** It halved the frame rate on a 24-core M1 Max - 60 median down to 32, and switching
	# it off alone put all of it back - which was never it being expensive so much as it being
	# redundant: the mesher already bakes ambient occlusion per vertex from the actual neighbouring
	# blocks, exactly, for free, and the lit shader feeds that in as AO. Computing it a second time by
	# guessing at it from the depth buffer is worse and costs half the frame. (2026-09-21)
	#
	# Left switchable for measuring, off in the preset.
	env.ssao_enabled = on and off("ssao+")
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	# **No SSIL either.** Measured on an M1 Max: 44 median with it, 60 (vsync-capped, so at least
	# 36% more) without. It is bounce light, and between the mesher's baked occlusion and ambient
	# taken from the sky the world already has most of what it was adding - for a third of the frame.
	# The base M1 Air the children play on gets 16 fps with all of this on, which is the number that
	# actually decides what ships. Left switchable for measuring. (2026-09-22)
	env.ssil_enabled = on and off("ssil+")
	env.ssil_intensity = 0.6
	# **No fog on the sky.** 0.35 was meant as haze and instead washed the whole dome towards the
	# horizon colour, so the scattering computed a deep blue zenith and the fog painted over it. Fog
	# belongs on distance, not on the thing that is infinitely far away. (2026-09-21)
	env.fog_sky_affect = 0.0
	if on:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 4.0
	if on and not off("haze"):
		_haze(env)
	else:
		# Back to the plain distance fog. Without this, turning the preset off left the haze behind -
		# `apply_realism` is called on every settings change, and a one-way setting is a setting that
		# looks like it does nothing the second time you use it.
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_aerial_perspective = 0.0
		env.fog_sun_scatter = 0.0
		env.fog_height_density = 0.0


## Aerial perspective: distance reading as *air* rather than as a fade-out.
##
## What the world had was a depth fog starting at 55% of the render distance, which is a cutoff - it
## hides the edge of the loaded world and does nothing before it, so everything nearer than that is
## equally crisp and the distance has no depth to it. Real distance is hazy all the way: a hill two
## miles off is paler than one at one mile, and both are paler at their base than at their ridge,
## because haze is thicker where the air is. That progressive paling is most of what separates a
## photograph of a landscape from a render of one. (2026-09-22)
##
## Four things, none of them volumetric - volumetric fog is a raymarch and this preset already has to
## earn its place on a base M1 Air:
##
##   - **`fog_aerial_perspective`** blends the sky itself into the fog, per direction. That is the
##     actual feature and it is what makes distant terrain take the colour of the sky *behind* it
##     rather than one flat fog tint - which is why `fog_light_color` alone never looked right.
##   - **Exponential rather than depth mode**, so it thickens smoothly from the camera instead of
##     switching on at a distance. There is no longer a near edge to notice.
##   - **Height falloff**, so haze pools low and thins out above. Standing on a hill you look over it;
##     standing in a valley you look through it.
##
## The numbers are small on purpose, and the first set were not: density 0.0016 with a height density
## of 0.55 turned trees sixty blocks away into white silhouettes. Aerial perspective is a thing you are
## supposed to notice only when you compare two distances - the moment it reads as *fog*, it has stopped
## being air. (2026-09-22)
##   - **Sun scatter**, so looking toward the sun through haze brightens it. Free, and it is half of
##     why a photograph into the sun looks the way it does.
static func _haze(env: Environment) -> void:
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.6
	env.fog_sun_scatter = 0.25
	env.fog_height = 48.0
	# Positive: denser *below* fog_height. Negative pools it above, which is a ceiling of cloud and not
	# what this is for.
	env.fog_height_density = 0.18
	# Still nothing on the sky. 0.35 was tried as haze and washed the whole dome flat - the sky is
	# infinitely far away, so "how much air is in front of it" is a question with no answer.
	env.fog_sky_affect = 0.0
