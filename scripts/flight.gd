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


static func pressure_from_energy(energy: float) -> float:
	return clampf(1.0 - exp(-maxf(energy, 0.0) / ENERGY_63), 0.0, 1.0)


static func launch_speed(pressure: float) -> float:
	return lerpf(V_MIN, V_MAX, pow(clampf(pressure, 0.0, 1.0), 0.85))


static func spray_duration(pressure: float) -> float:
	return 0.8 + 1.8 * pressure


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
static func simulate_cap(pressure: float, elev_deg: float, wind: float, start_h := 1.1) -> Dictionary:
	var pos := Vector3(0.0, start_h, 0.0)
	var vel := launch_velocity(pressure, elev_deg)
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
static func simulate_spray(pressure: float, elev_deg: float, wind: float, start_h := 1.1) -> float:
	var pos := Vector3(0.0, start_h, 0.0)
	var vel := launch_velocity(pressure, elev_deg, SPRAY_SPEED)
	var t := 0.0
	while pos.y > 0.0 and t < 30.0:
		var r := air_step(pos, vel, wind, DROP_DRAG, STEP)
		pos = r[0]
		vel = r[1]
		t += STEP
	return pos.x
