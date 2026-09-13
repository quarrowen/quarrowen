extends RefCounted
## Graphics presets. Everything here is chosen to stay cheap on integrated GPUs (baseline: base M1
## MacBook Air): lighting and occlusion are baked into chunk meshes, the block shader does one texture
## fetch, bloom uses only a few small mip levels, and the "fast" preset renders 3D at reduced
## resolution with FSR upscaling. No real-time shadows, SSAO, SSR or global illumination.

const PATH := "user://settings.cfg"
const PRESETS := ["fast", "balanced", "fancy"]

const VALUES := {
	# render_scale: 3D resolution relative to the window (FSR upscales when below 1).
	"fast": {"ambient_occlusion": true, "sway": false, "fancy_water": false, "bloom": false, "grading": false, "fxaa": false, "render_scale": 0.7},
	"balanced": {"ambient_occlusion": true, "sway": true, "fancy_water": true, "bloom": true, "grading": true, "fxaa": false, "render_scale": 0.85},
	"fancy": {"ambient_occlusion": true, "sway": true, "fancy_water": true, "bloom": true, "grading": true, "fxaa": true, "render_scale": 1.0},
}

var preset := "balanced"


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var saved := String(cfg.get_value("graphics", "preset", preset))
		if saved in PRESETS:
			preset = saved
	var override := OS.get_environment("VOXEL_GRAPHICS")
	if override in PRESETS:
		preset = override


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("graphics", "preset", preset)
	cfg.save(PATH)


func cycle() -> void:
	preset = PRESETS[(PRESETS.find(preset) + 1) % PRESETS.size()]
	save()


func value(key: String):
	return VALUES[preset][key]


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
