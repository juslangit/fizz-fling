extends Node
## Everything the phone's motion sensors (or their stand-ins) tell the game.
##
## On the web the sensor listeners live in the page itself (export_presets.cfg →
## html/head_include, the `window.fizz` object): the browser only hands motion to
## JavaScript, and iPhones only after a tap asks permission. This script polls that
## object every frame.
##
## When there is no motion — a desktop browser, the editor, or an iPhone inside itch's
## frame, which never gets sensor data — shaking falls back to rubbing the screen (or
## mashing Left/Right / A/D / Space) and aiming falls back to dragging (or the arrow keys).

const DEMO_ENERGY_RATE := 10.0   # what the self-playing demo "shakes" per second
const RUB_PX_PER_ENERGY := 260.0 # finger travel (in 720-wide pixels) worth one unit of energy
const KEY_ENERGY := 0.9          # one alternating key press
const AIM_DRAG_DEG_PER_PX := 0.18

var demo := false                # ?demo in the URL or `-- --demo`: the game plays itself
var demo_party := false          # ?demo&party: the demo plays a 2-player party instead
var _js = null                   # window.fizz on the web
var _fallback_energy := 0.0
var _recent := 0.0               # smoothed energy rate, for wobble visuals
var _drag_aim := 45.0
var _keys_aim := 0.0
var _last_key := ""
var _aim_smooth := 45.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("fizz")
		var q = JavaScriptBridge.eval("location.search", true)
		demo = str(q).find("demo") >= 0
		demo_party = str(q).find("party") >= 0
	if "--demo" in OS.get_cmdline_user_args():
		demo = true
	if "--party" in OS.get_cmdline_user_args():
		demo_party = true


# ------------------------------------------------------------------ what the page knows
func has_motion() -> bool:
	return _js != null and bool(_js.has)


func in_frame() -> bool:
	return _js != null and bool(_js.frame)


func is_touch() -> bool:
	return _js != null and bool(_js.touch)


func is_ios() -> bool:
	return _js != null and bool(_js.ios)


func permission() -> String:
	return str(_js.perm) if _js != null else "none"


## True for an iPhone inside itch's embed: it will never get motion there, so the title
## screen offers to reopen the game on its own page.
func needs_own_page() -> bool:
	return in_frame() and is_ios() and not has_motion()


func open_own_page() -> void:
	if _js != null:
		_js.goto = "self"   # the page acts on it inside the tap's own event (see head_include)


## Tells the page which screen is showing, so tools/shot.mjs can wait for one.
func report_state(name: String) -> void:
	if _js != null:
		_js.state = name


func vibrate(ms: int) -> void:
	if _js != null:
		JavaScriptBridge.eval("navigator.vibrate && navigator.vibrate(%d)" % ms, true)


# ------------------------------------------------------------------ shaking
## Energy shaken in since the last call. Call once per frame while the shake phase runs.
func take_shake(delta: float) -> float:
	var e := _fallback_energy
	_fallback_energy = 0.0
	if _js != null:
		e += float(_js.shake)
		_js.shake = 0.0
	if demo:
		e += DEMO_ENERGY_RATE * delta * (0.8 + 0.4 * sin(Time.get_ticks_msec() * 0.009))
	var rate := e / maxf(delta, 0.001)
	_recent = lerpf(_recent, rate, clampf(delta * 8.0, 0.0, 1.0))
	return e


## 0 = still, ~1 = shaking hard. For wobbling the bottle and the camera.
func intensity() -> float:
	return clampf(_recent / 12.0, 0.0, 1.6)


func reset() -> void:
	_fallback_energy = 0.0
	_recent = 0.0
	if _js != null:
		_js.shake = 0.0


# ------------------------------------------------------------------ aiming
## The launch angle the player is holding, in degrees above the ground (10–85).
## With sensors: tilt the phone's top to the right to lean the bottle down the field;
## upright = straight up, lying on its side = flat.
func aim_degrees(delta: float) -> float:
	var target := _drag_aim
	if demo:
		target = 42.0 + 3.0 * sin(Time.get_ticks_msec() * 0.003)
	elif has_motion():
		var roll := rad_to_deg(atan2(-float(_js.ux), float(_js.uy)))  # + = top leaning right
		target = 90.0 - roll
	else:
		_drag_aim = clampf(_drag_aim + _keys_aim * 70.0 * delta, Flight.MIN_ELEV, Flight.MAX_ELEV)
		target = _drag_aim
	target = clampf(target, Flight.MIN_ELEV, Flight.MAX_ELEV)
	_aim_smooth = lerpf(_aim_smooth, target, clampf(delta * 10.0, 0.0, 1.0))
	return _aim_smooth


func reset_aim(deg := 60.0) -> void:
	_drag_aim = deg
	_aim_smooth = deg


# ------------------------------------------------------------------ fallbacks
func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var scale := 720.0 / maxf(1.0, get_viewport().get_visible_rect().size.x)
		_fallback_energy += event.relative.length() * scale / RUB_PX_PER_ENERGY
		_drag_aim = clampf(_drag_aim - event.relative.x * scale * AIM_DRAG_DEG_PER_PX,
				Flight.MIN_ELEV, Flight.MAX_ELEV)
	elif event is InputEventKey and not event.echo:
		var k: String = OS.get_keycode_string(event.physical_keycode)
		if event.pressed and k in ["Left", "Right", "A", "D", "Space"]:
			if k != _last_key or k == "Space":
				_fallback_energy += KEY_ENERGY
			_last_key = k
		if k in ["Left", "A"]:
			_keys_aim = 1.0 if event.pressed else (0.0 if _keys_aim > 0 else _keys_aim)
		elif k in ["Right", "D"]:
			_keys_aim = -1.0 if event.pressed else (0.0 if _keys_aim < 0 else _keys_aim)
