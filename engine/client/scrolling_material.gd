extends RefCounted
## The material a conveyor belt wears: its texture slides along while it runs.
##
## The speed rides in the MultiMesh's **per-instance custom data**, so one belt can run while the one
## beside it is stopped, and starting one costs a single float per instance rather than rebuilding the
## chunk it is in. That is the same reason rotation is done per instance: a mesh rebuild to start a
## machine would be felt.
##
## The texture comes off the model's own material, so a mod draws its belt in a modelling program the
## way it draws everything else and does not have to know this exists.

const SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D albedo : source_color, filter_nearest;
// x: how fast the surface slides. y: 0 slides along u, 1 slides along v.
varying float speed;
varying float along_v;

void vertex() {
	speed = INSTANCE_CUSTOM.x;
	along_v = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 uv = UV;
	float shift = fract(speed * TIME);
	if (along_v > 0.5) {
		uv.y = fract(uv.y + shift);
	} else {
		uv.x = fract(uv.x + shift);
	}
	vec4 c = texture(albedo, uv);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
}
"""

static var _shader: Shader


## A material that scrolls `texture`. One shader for every belt; one material per texture.
static func create(texture: Texture2D) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("albedo", texture)
	return material


## The albedo texture a loaded model is drawn with, so the belt keeps its own look.
static func texture_of(mesh: Mesh) -> Texture2D:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var material := mesh.surface_get_material(0)
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_texture
	return null
