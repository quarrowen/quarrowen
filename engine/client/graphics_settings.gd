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
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR


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
