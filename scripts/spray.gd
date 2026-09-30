extends Node3D
## The soda jet that follows the cap out of the bottle. Each droplet flies with the same
## physics as the cap (Flight.air_step, heavier drag), and leaves a foam splat where it hits
## the grass. `reach` is the furthest splat from the bottle: that is the spray score, so the
## number on screen is always the spot the player can see.

signal splashed(at: Vector3)

const MAX_DROPS := 700
const MAX_SPLATS := 360
const RATE := 280.0              # droplets per second at full pressure

var reach := 0.0
var emitting := false
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _size := PackedFloat32Array()
var _alive := PackedByteArray()
var _drops: MultiMesh
var _splats: MultiMesh
var _splat_next := 0
var _t := 0.0
var _dur := 0.0
var _speed := 0.0
var _elev := 45.0
var _wind := 0.0
var _mouth_fn: Callable
var _accum := 0.0
var _rng := RandomNumberGenerator.new()
var _splash_cool := 0.0


func _ready() -> void:
	_pos.resize(MAX_DROPS)
	_vel.resize(MAX_DROPS)
	_size.resize(MAX_DROPS)
	_alive.resize(MAX_DROPS)
	_drops = _make_mm(_drop_mesh(), MAX_DROPS)
	_splats = _make_mm(_splat_mesh(), MAX_SPLATS)
	clear()


func _make_mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	for i in n:
		mm.set_instance_color(i, Color(1.0, 0.95, 0.85))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _drop_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.02
	s.height = 0.04
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	# soda orange, tinted per droplet towards white foam through the instance colour
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.emission_enabled = true
	m.emission = Color(0.2, 0.05, 0.0)
	s.material = m
	return s


func _splat_mesh() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.3
	c.bottom_radius = 0.3
	c.height = 0.004
	c.radial_segments = 8
	c.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c.material = m
	return c


func clear() -> void:
	reach = 0.0
	emitting = false
	_splat_next = 0
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for i in MAX_DROPS:
		_alive[i] = 0
		_drops.set_instance_transform(i, hidden)
	for i in MAX_SPLATS:
		_splats.set_instance_transform(i, hidden)


## Starts the jet. `mouth_fn` returns the bottle mouth each frame (the bottle recoils).
func start(mouth_fn: Callable, elev: float, pressure: float, wind: float, seed_value: int) -> void:
	clear()
	_rng.seed = seed_value
	_mouth_fn = mouth_fn
	_elev = elev
	_wind = wind
	_speed = Flight.launch_speed(pressure) * Flight.SPRAY_SPEED
	_dur = Flight.spray_duration(pressure)
	_t = 0.0
	_accum = 0.0
	emitting = true


func active_count() -> int:
	return _alive.count(1)


func is_done() -> bool:
	return not emitting and active_count() == 0


func _spawn(strength: float) -> void:
	var i := _alive.find(0)
	if i < 0:
		return
	var e := deg_to_rad(_elev + _rng.randf_range(-3.5, 3.5))
	var side := deg_to_rad(_rng.randf_range(-3.0, 3.0))
	# the fastest droplets leave at exactly the nominal speed, so the leading edge of the
	# jet lands where Flight.simulate_spray predicts
	var sp := _speed * strength * _rng.randf_range(0.8, 1.0)
	var dir := Vector3(cos(e) * cos(side), sin(e), cos(e) * sin(side))
	_pos[i] = _mouth_fn.call()
	_vel[i] = dir * sp
	_size[i] = _rng.randf_range(0.6, 1.5)
	_alive[i] = 1
	var foam := _rng.randf() < 0.3
	_drops.set_instance_color(i, Color(1.0, 0.95, 0.85) if foam else Color(0.95, 0.32, 0.02).lerp(Color(1.0, 0.5, 0.1), _rng.randf()))


func _physics_process(delta: float) -> void:
	_splash_cool -= delta
	if emitting:
		_t += delta
		# the pressure falls away as the bottle empties
		var strength := pow(clampf(1.0 - _t / _dur, 0.0, 1.0), 0.6)
		_accum += RATE * (0.35 + 0.65 * strength) * delta
		while _accum >= 1.0:
			_accum -= 1.0
			_spawn(maxf(strength, 0.12))
		if _t >= _dur:
			emitting = false
	var steps := maxi(1, roundi(delta / Flight.STEP))
	var dt := delta / steps
	for i in MAX_DROPS:
		if _alive[i] == 0:
			continue
		var p := _pos[i]
		var v := _vel[i]
		for s in steps:
			var r := Flight.air_step(p, v, _wind, Flight.DROP_DRAG, dt)
			p = r[0]
			v = r[1]
		if p.y <= 0.0:
			p.y = 0.0
			_alive[i] = 0
			_drops.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
			_splat(p, _size[i])
			continue
		_pos[i] = p
		_vel[i] = v
		# stretch each droplet along its motion so the jet reads as a stream, not dots
		var sp := v.length()
		var b := Basis()
		if sp > 0.5:
			var fwd := v / sp
			var up := Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT
			b = Basis.looking_at(fwd, up)
		var sz := _size[i]
		_drops.set_instance_transform(i, Transform3D(b.scaled(Vector3(sz, sz, sz * (1.0 + sp * 0.05))), p))


func _splat(p: Vector3, size: float) -> void:
	reach = maxf(reach, p.x)
	var y := 0.02 + 0.002 * (_splat_next % 7)   # high enough to win the depth test from far away
	var s := size * _rng.randf_range(0.7, 1.3)
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, 1.0, s * _rng.randf_range(0.6, 1.0)))
	_splats.set_instance_transform(_splat_next % MAX_SPLATS, Transform3D(b, Vector3(p.x, y, p.z)))
	_splats.set_instance_color(_splat_next % MAX_SPLATS, Color(1.0, 0.62, 0.25).lerp(Color(1.0, 0.9, 0.75), _rng.randf()))
	_splat_next += 1
	if _splash_cool <= 0.0:
		_splash_cool = 0.25
		splashed.emit(p)
