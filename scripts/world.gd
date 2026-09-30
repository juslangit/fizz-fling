extends Node3D
## The park. A mown field runs down +X from the bottle, with a painted line every 10 m and a
## numbered sign on the far side of each one. The picnic table and bottle sit at x = 0.
## Trees, bushes, a fence and rocks line the field; clouds drift overhead with the wind.
## Every model comes from assets/models (built in Blender by tools/blender/build_assets.py);
## repeated ones are drawn with MultiMesh so the whole park costs a handful of draw calls.

const FIELD_LEN := 180.0
const LANE_HALF := 5.0          # the mown lane is 10 m wide, lines at z = ±5
const TABLE_TOP := 0.791        # height of the cloth the bottle stands on
const CAP_ON_BOTTLE := 0.305    # cap centre above the bottle's base, along its axis
const SIGN_Z := -6.4

var font: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
var bottle: Node3D
var liquid: Node3D
var cap: Node3D
var cap_mesh: MeshInstance3D
var bubbles: CPUParticles3D
var trail: CPUParticles3D
var flag: Node3D
var flag_label: Label3D
var camera: Camera3D
var sun: DirectionalLight3D
var _clouds: Array[Node3D] = []
var wind := 0.0
var target: Node3D              # the bin and its rings, for the target mode
var _mat_bottle: BaseMaterial3D
var _mat_liquid: BaseMaterial3D
var _mat_label: BaseMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 11
	_environment()
	_ground()
	_signs()
	_scenery()
	_start_area()
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true


func model(name: String) -> Node3D:
	return load("res://assets/models/%s.glb" % name).instantiate()


func _mesh_of(name: String) -> Mesh:
	var n := model(name)
	var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
	var m := mi.mesh
	n.free()
	return m


func _multimesh(name: String, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh_of(name)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _xf(pos: Vector3, scale := 1.0, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)


# ------------------------------------------------------------------ sky, light
func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.55, 0.92)
	sky_mat.sky_horizon_color = Color(0.72, 0.87, 0.98)
	sky_mat.ground_horizon_color = Color(0.72, 0.87, 0.98)
	sky_mat.ground_bottom_color = Color(0.3, 0.5, 0.3)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.87, 0.97)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)


# ------------------------------------------------------------------ the field
const GROUND_SHADER := """
shader_type spatial;
render_mode specular_disabled;
uniform vec3 grass_a : source_color = vec3(0.42, 0.72, 0.28);
uniform vec3 grass_b : source_color = vec3(0.36, 0.65, 0.24);
uniform vec3 rough : source_color = vec3(0.33, 0.56, 0.22);
uniform float lane_half = 5.0;
uniform float field_len = 180.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float band(float d, float w) { float a = fwidth(d) + 0.001; return 1.0 - smoothstep(w - a, w + a, d); }
void fragment() {
	float inside = step(abs(wp.z), lane_half) * step(-0.5, wp.x) * step(wp.x, field_len);
	vec3 c = mix(grass_a, grass_b, step(0.5, fract(wp.x / 5.0)));
	float n = fract(sin(dot(floor(wp.xz * 1.7), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 outside = rough * (0.92 + 0.12 * n);
	c = mix(outside, c * (0.96 + 0.06 * n), inside);
	float d10 = abs(fract(wp.x / 10.0 + 0.5) - 0.5) * 10.0;
	float d1 = abs(fract(wp.x + 0.5) - 0.5);
	float lines = band(d10, 0.07) * inside;
	float ticks = band(d1, 0.03) * step(lane_half - 0.6, abs(wp.z)) * inside;
	float side = band(abs(abs(wp.z) - lane_half), 0.07) * step(-0.5, wp.x) * step(wp.x, field_len);
	c = mix(c, vec3(0.96, 0.97, 0.93), clamp(lines + ticks + side, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""


func _ground() -> void:
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("lane_half", LANE_HALF)
	m.set_shader_parameter("field_len", FIELD_LEN)
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 400)
	plane.material = m
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.position = Vector3(80, 0, -40)
	add_child(g)
	# distant hills to close off the horizon
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.3, 0.55, 0.3)
	for i in 9:
		var s := SphereMesh.new()
		s.radial_segments = 10
		s.rings = 5
		s.material = hill_mat
		var h := MeshInstance3D.new()
		h.mesh = s
		var r := _rng.randf_range(45, 80)
		h.scale = Vector3(r * 1.8, r * 0.45, r)
		h.position = Vector3(-60 + i * 38 + _rng.randf_range(-10, 10), -r * 0.12, -170 - _rng.randf_range(0, 40))
		add_child(h)


func _signs() -> void:
	var xforms := []
	for d in range(10, int(FIELD_LEN) + 1, 10):
		xforms.append(_xf(Vector3(d, 0, SIGN_Z)))
		var l := Label3D.new()
		l.text = "%d" % d
		l.font = font
		l.font_size = 96
		l.pixel_size = 0.0055
		l.modulate = Color(0.85, 0.12, 0.15)
		l.outline_size = 0
		l.position = Vector3(d, 1.47, SIGN_Z + 0.06)
		add_child(l)
	_multimesh("sign", xforms)


func _scenery() -> void:
	var round_t := []
	var pine_t := []
	var bush_t := []
	var rock_t := []
	var fence_t := []
	var x := -30.0
	while x < FIELD_LEN + 40:
		var z := -_rng.randf_range(12, 24)
		var t := _xf(Vector3(x, 0, z), _rng.randf_range(0.9, 1.5), _rng.randf() * TAU)
		(round_t if _rng.randf() < 0.55 else pine_t).append(t)
		if _rng.randf() < 0.7:
			var z2 := -_rng.randf_range(28, 55)
			var t2 := _xf(Vector3(x + _rng.randf_range(-3, 3), 0, z2), _rng.randf_range(1.2, 2.0), _rng.randf() * TAU)
			(round_t if _rng.randf() < 0.4 else pine_t).append(t2)
		x += _rng.randf_range(4.5, 9.0)
	x = -25.0
	while x < FIELD_LEN + 30:
		(round_t if _rng.randf() < 0.6 else pine_t).append(
			_xf(Vector3(x, 0, _rng.randf_range(16, 26)), _rng.randf_range(0.9, 1.4), _rng.randf() * TAU))
		x += _rng.randf_range(9, 16)
	for i in 70:
		bush_t.append(_xf(Vector3(_rng.randf_range(-15, FIELD_LEN + 20), 0, -_rng.randf_range(9.2, 11.5)),
				_rng.randf_range(0.7, 1.2), _rng.randf() * TAU))
	for i in 40:
		var side := -1.0 if _rng.randf() < 0.6 else 1.0
		rock_t.append(_xf(Vector3(_rng.randf_range(-5, FIELD_LEN), 0, side * _rng.randf_range(6.2, 8.0)),
				_rng.randf_range(0.5, 1.3), _rng.randf() * TAU))
	var fx := -12.0
	while fx < FIELD_LEN + 20:
		fence_t.append(_xf(Vector3(fx, 0, -8.3)))
		fx += 2.1
	_multimesh("tree_round", round_t)
	_multimesh("tree_pine", pine_t)
	_multimesh("bush", bush_t)
	_multimesh("rock", rock_t)
	_multimesh("fence", fence_t)
	for i in 16:
		var c := model("cloud")
		c.position = Vector3(_rng.randf_range(-40, 240), _rng.randf_range(24, 40), -_rng.randf_range(40, 130))
		c.scale = Vector3.ONE * _rng.randf_range(1.5, 3.2)
		c.rotation.y = _rng.randf_range(-0.3, 0.3)
		add_child(c)
		_clouds.append(c)


# ------------------------------------------------------------------ table, bottle, cap
func _start_area() -> void:
	var table := model("table")
	table.position = Vector3(-0.45, 0, 0)
	add_child(table)
	bottle = model("bottle")
	bottle.position = Vector3(0, TABLE_TOP, 0)
	add_child(bottle)
	liquid = bottle.find_child("Liquid", true, false)
	_fix_bottle_materials()
	cap = model("cap")
	add_child(cap)
	cap_mesh = cap.find_children("*", "MeshInstance3D", true, false)[0]
	reset_bottle()
	# fizz rising inside the soda while it is being shaken
	bubbles = CPUParticles3D.new()
	bubbles.amount = 60
	bubbles.lifetime = 0.7
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bubbles.emission_box_extents = Vector3(0.03, 0.09, 0.03)
	bubbles.position = Vector3(0, 0.12, 0)
	bubbles.direction = Vector3.UP
	bubbles.spread = 25.0
	bubbles.gravity = Vector3(0, 0.25, 0)
	bubbles.initial_velocity_min = 0.05
	bubbles.initial_velocity_max = 0.2
	bubbles.scale_amount_min = 0.4
	bubbles.scale_amount_max = 1.0
	bubbles.mesh = _sphere(0.006, Color(1, 1, 1, 0.9), true)
	bubbles.emitting = false
	bottle.add_child(bubbles)
	# droplets streaming off the flying cap
	trail = CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.direction = Vector3.ZERO
	trail.spread = 180.0
	trail.gravity = Vector3(0, -6, 0)
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.2
	trail.mesh = _sphere(0.02, Color(1.0, 0.72, 0.3), true)
	trail.emitting = false
	cap.add_child(trail)
	flag = model("flag")
	flag.visible = false
	add_child(flag)
	target = Node3D.new()
	target.add_child(model("rings"))
	target.add_child(model("bin"))
	target.visible = false
	add_child(target)
	flag_label = Label3D.new()
	flag_label.font = font
	flag_label.font_size = 64
	flag_label.pixel_size = 0.008
	flag_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flag_label.outline_size = 14
	flag_label.outline_modulate = Color(0.35, 0.2, 0.0)
	flag_label.modulate = Color(1.0, 0.85, 0.2)
	flag_label.position = Vector3(0.3, 2.45, 0)
	flag.add_child(flag_label)


func _sphere(r: float, col: Color, unshaded := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material = m
	return s


## The glTF plastic comes in opaque on some exporters; make sure it is see-through,
## drawn after the soda, and the soda is a bright cartoon orange.
func _fix_bottle_materials() -> void:
	for mi in bottle.find_children("*", "MeshInstance3D", true, false):
		var m: BaseMaterial3D = mi.get_active_material(0)
		if m == null:
			continue
		m = m.duplicate()
		match String(mi.name):
			"Bottle":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(0.75, 0.95, 0.8, 0.3)
				m.roughness = 0.05
				m.metallic_specular = 0.9
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.render_priority = 1
			"Liquid":
				m.albedo_color = Color(1.0, 0.5, 0.06)
				m.emission_enabled = true
				m.emission = Color(0.45, 0.16, 0.0)
		mi.set_surface_override_material(0, m)
		match String(mi.name):
			"Bottle": _mat_bottle = m
			"Liquid": _mat_liquid = m
			"Label": _mat_label = m


## Dresses the bottle as one of the drinks in scripts/drinks.gd.
func apply_drink(d: Dictionary) -> void:
	_mat_liquid.albedo_color = d.liquid
	_mat_liquid.emission = d.glow
	_mat_bottle.albedo_color = d.plastic
	_mat_label.albedo_texture = load(d.label)
	set_cap_color(d.cap)
	trail.mesh.material.albedo_color = d.drop2


func show_target(x: float) -> void:
	target.position = Vector3(x, 0, 0)
	target.visible = true


func hide_target() -> void:
	target.visible = false


func set_cap_color(c: Color) -> void:
	var m: BaseMaterial3D = cap_mesh.get_active_material(0).duplicate()
	m.albedo_color = c
	cap_mesh.set_surface_override_material(0, m)


## The bottle's current mouth position (where the cap sits), from its lean.
func mouth() -> Vector3:
	return bottle.global_transform * Vector3(0, CAP_ON_BOTTLE, 0)


func reset_bottle() -> void:
	bottle.rotation = Vector3.ZERO
	bottle.position = Vector3(0, TABLE_TOP, 0)
	liquid.scale = Vector3.ONE
	cap.visible = true
	cap.scale = Vector3.ONE
	cap.rotation = Vector3.ZERO
	cap.global_position = mouth()


## Lean the bottle so it points at `elev` degrees above the ground, towards +X.
func lean_bottle(elev: float) -> void:
	bottle.rotation = Vector3(0, 0, -deg_to_rad(90.0 - elev))


func place_flag(x: float, text: String) -> void:
	flag.visible = x > 0.5
	flag_label.visible = true
	flag.position = Vector3(x, 0, -1.2)
	flag_label.text = text


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += (0.6 + wind * 0.9) * delta
		if c.position.x > 260:
			c.position.x = -60
		elif c.position.x < -70:
			c.position.x = 250
