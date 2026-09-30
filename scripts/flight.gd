class_name Flight
extends RefCounted
## The physics of one throw, kept free of scenes so tools/checks can run it headless.
##
## Shaking builds "energy"; energy becomes pressure (0..1) with diminishing returns, so
## frantic shaking helps but can never run away. Pressure sets how fast the cap leaves
## the bottle. The cap then flies with gravity, air drag and wind, bounces, and rolls
## to a stop. The soda spray is the same physics with heavier drag and a slower start.

const G := 9.81
const CAP_DRAG := 0.0032        # k in a = -k·|v|·v for the cap
const DROP_DRAG := 0.010        # the soda droplets slow down much faster
const ENERGY_63 := 22.0         # shake energy that gives 63% pressure (5 s of hard shaking ≈ 50)
const V_MIN := 4.0              # m/s at zero pressure
const V_MAX := 40.0             # m/s at full pressure
const SPRAY_SPEED := 0.55       # spray leaves at this fraction of the cap's speed
const BOUNCE := 0.32            # vertical speed kept on each bounce
const BOUNCE_SKID := 0.55       # horizontal speed kept on each bounce
const ROLL_DECEL := 10.0        # m/s² of friction once the cap is rolling on the grass
const MIN_ELEV := 10.0
const MAX_ELEV := 85.0
const STEP := 1.0 / 120.0


## `gain` is the drink's fizziness: how much pressure the same shaking builds.
static func pressure_from_energy(energy: float, gain := 1.0) -> float:
	return clampf(1.0 - exp(-maxf(energy, 0.0) * gain / ENERGY_63), 0.0, 1.0)


static func launch_speed(pressure: float) -> float:
	return lerpf(V_MIN, V_MAX, pow(clampf(pressure, 0.0, 1.0), 0.85))


static func spray_duration(pressure: float, mult := 1.0) -> float:
	return (0.8 + 1.8 * pressure) * mult


static func launch_velocity(pressure: float, elev_deg: float, speed_scale := 1.0) -> Vector3:
	var e := deg_to_rad(clampf(elev_deg, MIN_ELEV, MAX_ELEV))
	return Vector3(cos(e), sin(e), 0.0) * launch_speed(pressure) * speed_scale


## One integration step in the air. Returns [pos, vel].
static func air_step(pos: Vector3, vel: Vector3, wind: float, drag: float, dt: float) -> Array:
	var rel := vel - Vector3(wind, 0.0, 0.0)
	vel += (Vector3(0.0, -G, 0.0) - drag * rel.length() * rel) * dt
	return [pos + vel * dt, vel]


## The cap's full step: air, then bounce or roll once it reaches the grass.
## Returns [pos, vel, event] where event is "", "bounce", or "stop".
static func cap_step(pos: Vector3, vel: Vector3, wind: float, dt: float) -> Array:
	var ev := ""
	if pos.y <= 0.0 and absf(vel.y) < 0.01:
		# rolling along the ground
		var h := Vector2(vel.x, vel.z)
		var sp := h.length()
		sp = maxf(0.0, sp - ROLL_DECEL * dt)
		if sp <= 0.05:
			return [pos, Vector3.ZERO, "stop"]
		h = h.normalized() * sp
		vel = Vector3(h.x, 0.0, h.y)
		return [pos + vel * dt, vel, ""]
	var r := air_step(pos, vel, wind, CAP_DRAG, dt)
	pos = r[0]
	vel = r[1]
	if pos.y <= 0.0:
		pos.y = 0.0
		if absf(vel.y) > 1.2:
			vel = Vector3(vel.x * BOUNCE_SKID, -vel.y * BOUNCE, vel.z * BOUNCE_SKID)
			ev = "bounce"
		else:
			vel.y = 0.0
	return [pos, vel, ev]


## Where a throw ends up, without drawing anything. Used by the checks and the demo.
static func simulate_cap(pressure: float, elev_deg: float, wind: float, start_h := 1.1, speed_mult := 1.0) -> Dictionary:
	var pos := Vector3(0.0, start_h, 0.0)
	var vel := launch_velocity(pressure, elev_deg, speed_mult)
	var first_land := -1.0
	var peak := start_h
	var t := 0.0
	while t < 60.0:
		var r := cap_step(pos, vel, wind, STEP)
		pos = r[0]
		vel = r[1]
		peak = maxf(peak, pos.y)
		if first_land < 0.0 and pos.y <= 0.0:
			first_land = pos.x
		t += STEP
		if r[2] == "stop":
			break
	return {"land": first_land, "stop": pos.x, "peak": peak, "time": t}


## How far the leading droplet of the spray reaches.
static func simulate_spray(pressure: float, elev_deg: float, wind: float, start_h := 1.1, speed_mult := 1.0) -> float:
	var pos := Vector3(0.0, start_h, 0.0)
	var vel := launch_velocity(pressure, elev_deg, SPRAY_SPEED * speed_mult)
	var t := 0.0
	while pos.y > 0.0 and t < 30.0:
		var r := air_step(pos, vel, wind, DROP_DRAG, STEP)
		pos = r[0]
		vel = r[1]
		t += STEP
	return pos.x


# ------------------------------------------------------------------ target mode: the bin
const BIN_R := 0.30          # inside radius of the bin's opening
const BIN_WALL := 0.36       # outside radius of its wall
const BIN_H := 0.85          # height of the rim
const CAP_R := 0.02


## Checks one step of the cap against a bin standing at `bin` (x, 0, z).
## Returns "in" when the cap drops through the opening, "hit" when it strikes the wall
## (the returned velocity is bounced off it), or "" otherwise. Returns [event, vel].
static func bin_test(prev: Vector3, pos: Vector3, vel: Vector3, bin: Vector3) -> Array:
	if prev.y > BIN_H and pos.y <= BIN_H:
		# where did it cross the rim's height?
		var f := (prev.y - BIN_H) / maxf(prev.y - pos.y, 0.0001)
		var at := prev.lerp(pos, f)
		if Vector2(at.x - bin.x, at.z - bin.z).length() < BIN_R - CAP_R:
			return ["in", vel]
	if pos.y < BIN_H:
		var d := Vector2(pos.x - bin.x, pos.z - bin.z)
		if d.length() < BIN_WALL + CAP_R:
			var n := d.normalized() if d.length() > 0.001 else Vector2(-1, 0)
			var h := Vector2(vel.x, vel.z)
			if h.dot(n) < 0.0:
				h = (h - 2.0 * h.dot(n) * n) * 0.45
				return ["hit", Vector3(h.x, vel.y * 0.6, h.y)]
	return ["", vel]


## Flies a throw at a bin and reports [in_bin, miss]; the miss is where the cap stopped.
static func simulate_to_bin(pressure: float, elev_deg: float, wind: float, bin_x: float, speed_mult := 1.0) -> Array:
	var pos := Vector3(0.0, 1.1, 0.0)
	var vel := launch_velocity(pressure, elev_deg, speed_mult)
	var bin := Vector3(bin_x, 0.0, 0.0)
	var t := 0.0
	while t < 60.0:
		var prev := pos
		var r := cap_step(pos, vel, wind, STEP)
		pos = r[0]
		vel = r[1]
		var b := bin_test(prev, pos, vel, bin)
		if b[0] == "in":
			return [true, 0.0]
		vel = b[1]
		t += STEP
		if r[2] == "stop":
			break
	return [false, absf(pos.x - bin_x)]


## The pressure that drops a lob at `elev_deg` into a bin at `bin_x` (the demo's aim, and a check
## that every target distance can be binned). Bisects on where the cap crosses the rim's height.
static func pressure_for_bin(elev_deg: float, wind: float, bin_x: float, speed_mult := 1.0) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 30:
		var p := (lo + hi) * 0.5
		var pos := Vector3(0.0, 1.1, 0.0)
		var vel := launch_velocity(p, elev_deg, speed_mult)
		while not (vel.y < 0.0 and pos.y <= BIN_H) and pos.y > -1.0:
			var r := air_step(pos, vel, wind, CAP_DRAG, STEP)
			pos = r[0]
			vel = r[1]
		if pos.x < bin_x:
			lo = p
		else:
			hi = p
	return (lo + hi) * 0.5


## A lob that lands in the bin: the steepest angle (from 70°, 5° at a time) that can still reach
## it with less than full pressure. Returns [pressure, elev_deg].
static func lob_for_bin(wind: float, bin_x: float, speed_mult := 1.0) -> Array:
	var elev := 70.0
	while elev > 20.0:
		var p := pressure_for_bin(elev, wind, bin_x, speed_mult)
		if p < 0.99:
			return [p, elev]
		elev -= 5.0
	return [1.0, 42.0]


## Points for a target throw: 100 in the bin, then 50 for a touch, falling 5 per metre missed.
static func target_points(in_bin: bool, miss: float) -> int:
	if in_bin:
		return 100
	return maxi(0, roundi(50.0 - miss * 5.0))
