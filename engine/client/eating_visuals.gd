extends RefCounted
## Shared timing and crumbs for eating and drinking animations (first-person view model and avatars).
## A meal lasts the food's `eat_time`: food is lifted to the mouth every CHOMP seconds and loses a
## bite at each third; drinks are tipped back in gulps instead.

const CHOMP := 0.4
const GULP := 0.45


## How many bites are gone (0-3; 3 = eaten) `t` seconds into a meal of `duration`.
static func bites(t: float, duration: float) -> int:
	return clampi(floori(t / maxf(duration, 0.05) * 3.0), 0, 3)


## 0..1..0 each chomp: how far the food is raised towards the mouth.
static func lift(t: float) -> float:
	var p := fposmod(t, CHOMP) / CHOMP
	return pow(sin(p * PI), 2.0)


## 0..1 over the meal, and a small wobble for each gulp.
static func gulp(t: float) -> float:
	return sin(fposmod(t, GULP) / GULP * TAU)


## A one-shot burst of pixel crumbs falling in world space.
static func crumbs(parent: Node, at: Vector3, color: Color, amount := 8, size := 0.03) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = amount
	particles.lifetime = 0.7
	particles.local_coords = false
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	box.material = material
	particles.mesh = box
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 70.0
	particles.initial_velocity_min = size * 20.0
	particles.initial_velocity_max = size * 45.0
	particles.gravity = Vector3(0, -size * 250.0, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	particles.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, 0.0))
	particles.color_ramp = ramp
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
