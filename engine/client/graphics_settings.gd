extends RefCounted
## Graphics presets. Everything here is chosen to stay cheap on integrated GPUs (baseline: base M1
## MacBook Air): lighting and occlusion are baked into chunk meshes, the block shader does one texture
## fetch, bloom uses only a few small mip levels, and the "fast" preset renders 3D at reduced
## resolution with FSR upscaling. No real-time shadows, SSAO, SSR or global illumination.

const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const PRESETS := ["fast", "balanced", "fancy"]

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
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value("fxaa") else Viewport.SCREEN_SPACE_AA_DISABLED
	var scale: float = value("render_scale")
	viewport.scaling_3d_scale = scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
