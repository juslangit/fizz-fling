extends Node3D
## Fizz Fling — the game loop.
##
##   TITLE → (SETUP for a party) → READY (tap) → COUNT (3·2·1) → SHAKE (5 s) → AIM (3 s)
##   → pop (in slow motion) → FLIGHT (cap and spray) → LANDED → RESULT → next turn …
##   → FINAL standings (party)
##
## Two game types, played solo or as a pass-the-phone party:
##   DISTANCE — score = where the cap comes to rest + how far the spray reached.
##   TARGET   — a bin stands on the field; points for how close the cap stops, 100 in the bin.
##              Solo is five targets, each further away; a party gets one target per turn.
## Four drinks (scripts/drinks.gd) change how the pressure builds and how cap and spray fly.
## A result can be replayed in slow motion, and shared from the phone as a picture.

enum S { TITLE, SETUP, READY, COUNT, SHAKE, AIM, FLIGHT, LANDED, RESULT, FINAL }

const SHAKE_TIME := 5.0
const AIM_TIME := 3.0
const COUNT_STEP := 0.55
const LANDED_TIME := 3.0
const CAP_SHOW_SCALE := 3.0     # a 4 cm cap is invisible from a chase camera, so it is drawn bigger in flight
const SLOWMO := 0.3             # time scale for the moment of the pop
const REPLAY_SLOWMO := 0.35
const TARGET_THROWS := 5
const TARGET_BANDS := [Vector2(20, 35), Vector2(35, 55), Vector2(55, 75), Vector2(75, 95), Vector2(95, 115)]
const SITE := "juslangit.itch.io/fizz-fling"

var world: Node3D
var spray: Node3D
var state := S.TITLE
var t := 0.0

# who is playing, and what
var mode := "solo"               # solo | party
var game_type := "distance"      # distance | target
var drink: Dictionary = Drinks.LIST[0]
var n_players := 2
var n_rounds := 1
var players := []                # [{name, color, best, cap, spray}]; target mode sums points into best
var turn := 0                    # counts through rounds × players (party) or targets (solo target)

# the current throw
var energy := 0.0
var pressure := 0.0
var elev := 60.0
var wind := 0.0
var cap_pos := Vector3.ZERO
var cap_vel := Vector3.ZERO
var cap_spin := Vector3.ZERO
var cap_stopped := false
var cap_dist := 0.0
var spray_dist := 0.0
var new_best := false
var target_x := 0.0
var in_bin := false
var miss := 0.0
var points := 0
var target_total := 0            # solo target game running total
var last_throw := {}             # everything needed to replay the throw
var replaying := false
var _acc := 0.0
var _count_shown := -1
var _cam_shake := 0.0
var _look := Vector3(0, 0.95, 0)
var _orbit := 0.0
var _share_ready := false
var _demo_elev := 68.0
var _demo_replayed := false

# 3D markers
var arrow: Node3D
var cap_mark: Label3D
var spray_mark: Label3D

# interface
var ui_root: Control
var screens := {}
var gauge: Control
var lbl_phase: Label
var lbl_timer: Label
var lbl_hint: Label
var lbl_dist: Label
var lbl_pop: Label
var lbl_watermark: Label
var chip_player: PanelContainer
var chip_wind: PanelContainer
var lbl_best: Label
var lbl_drink: Label
var lbl_trait: Label
var btn_types := {}
var btn_own_page: Button
var btn_sound: Button
var lbl_players: Label
var lbl_setup_mode: Label
var btn_rounds := []
var setup_dots: HBoxContainer
var ready_name: Label
var ready_chip: PanelContainer
var ready_how: Label
var res_rows: VBoxContainer
var res_title: Label
var res_buttons: HBoxContainer
var res_extra: HBoxContainer
var final_list: VBoxContainer
var final_title: Label
var final_buttons: Array[Control] = []


func _ready() -> void:
	randomize()
	world = preload("res://scripts/world.gd").new()
	add_child(world)
	spray = preload("res://scripts/spray.gd").new()
	add_child(spray)
	spray.splashed.connect(func(_p): Sfx.play("splash", -14.0, randf_range(0.9, 1.2)))
	_make_markers()
	_build_ui()
	game_type = "target" if Motion.demo_target else Save.game_type
	_set_drink(Motion.demo_drink if Motion.demo_drink != "" else Save.drink)
	_go(S.TITLE)


# ================================================================== state machine
func _go(s: S) -> void:
	state = s
	t = 0.0
	Motion.report_state(S.keys()[s])
	for k in screens:
		screens[k].visible = false
	match s:
		S.TITLE:
			Engine.time_scale = 1.0
			screens.title.visible = true
			world.reset_bottle()
			world.hide_target()
			spray.clear()
			_hide_markers()
			_refresh_title()
		S.SETUP:
			screens.setup.visible = true
			_refresh_setup()
		S.READY:
			_new_throw()
			screens.ready.visible = true
			screens.hud.visible = true
			_hud_for_ready()
		S.COUNT:
			screens.hud.visible = true
			_count_shown = -1
			lbl_phase.text = "GET READY"
			lbl_hint.text = "Hold the phone tight!"
		S.SHAKE:
			screens.hud.visible = true
			Motion.reset()
			Sfx.play("go")
			lbl_phase.text = "SHAKE!"
			lbl_hint.text = _shake_hint()
			gauge.visible = true
		S.AIM:
			screens.hud.visible = true
			Motion.reset_aim(60.0)
			if Motion.demo and game_type == "target":
				# the self-playing demo lobs at the bin, so target screenshots show a real attempt
				var lob := Flight.lob_for_bin(wind, target_x, drink.cap_speed)
				pressure = lob[0]
				_demo_elev = lob[1]
			world.bubbles.emitting = false
			Sfx.play("beep", -4.0, 1.3)
			lbl_phase.text = "TILT TO AIM!"
			lbl_hint.text = _aim_hint()
			arrow.visible = true
		S.FLIGHT:
			screens.hud.visible = true
			_pop()
		S.LANDED:
			screens.hud.visible = true
			_landed()
		S.RESULT:
			Engine.time_scale = 1.0
			screens.result.visible = true
			_show_result()
		S.FINAL:
			screens.final.visible = true
			_show_final()


func _process(delta: float) -> void:
	t += delta
	_cam_shake = maxf(0.0, _cam_shake - delta)
	match state:
		S.TITLE:
			_orbit += delta * 0.18
			# close round the bottle, so the drink picker's change shows on the table
			_cam(Vector3(sin(_orbit) * 1.5 - 0.2, 1.3, cos(_orbit) * 1.5 + 0.2), Vector3(0.05, 0.74, 0), 2.0, delta)
			if Motion.auto_nav and t > 1.2:
				if Motion.demo_party:
					_go(S.SETUP)
				else:
					_start_solo()
		S.SETUP:
			_cam(Vector3(-2.2, 1.5, 2.2), Vector3(0, 0.9, 0), 2.0, delta)
			if Motion.auto_nav and t > 1.2:
				_start_party()
		S.READY:
			_cam_close(delta)
			if Motion.auto_nav and t > 0.8:
				_go(S.COUNT)
		S.COUNT:
			_cam_close(delta)
			var n := 3 - int(t / COUNT_STEP)
			if n != _count_shown and n >= 1:
				_count_shown = n
				lbl_timer.text = str(n)
				_pulse(lbl_timer)
				Sfx.play("beep")
			if t >= COUNT_STEP * 3:
				_go(S.SHAKE)
		S.SHAKE:
			_update_shake(delta)
		S.AIM:
			_update_aim(delta)
		S.FLIGHT:
			_update_flight(delta)
		S.LANDED:
			_update_landed(delta)
		S.RESULT, S.FINAL:
			_cam_overview(delta)
			if not _share_ready and t > 0.45:
				_share_ready = true
				_prepare_share()
			if Motion.demo_replay and state == S.RESULT and t > 1.5 and not _demo_replayed:
				_demo_replayed = true
				_replay()
			elif Motion.auto_nav and state == S.RESULT and t > 3.0:
				_next_turn()
			elif Motion.auto_nav and state == S.FINAL and t > 5.0:
				_start_party()


# ================================================================== drinks
func _set_drink(id: String) -> void:
	drink = Drinks.get_drink(id)
	world.apply_drink(drink)


func _cycle_drink(step: int) -> void:
	var i := (Drinks.index_of(drink.id) + step + Drinks.LIST.size()) % Drinks.LIST.size()
	_set_drink(Drinks.LIST[i].id)
	Save.drink = drink.id
	Save.write()
	Sfx.play("slosh1", -6.0)
	_refresh_title()


func _set_type(type: String) -> void:
	game_type = type
	Save.game_type = type
	Save.write()
	Sfx.play("click")
	_refresh_title()


# ================================================================== the throw
func _new_throw() -> void:
	energy = 0.0
	pressure = 0.0
	cap_stopped = false
	cap_dist = 0.0
	spray_dist = 0.0
	in_bin = false
	miss = 0.0
	points = 0
	new_best = false
	replaying = false
	_share_ready = false
	elev = 60.0
	wind = 0.0 if randf() < 0.2 else snappedf(randf_range(-3.0, 3.0), 0.1)
	world.wind = wind
	world.reset_bottle()
	world.apply_drink(drink)
	world.set_cap_color(_player().color if mode == "party" else drink.cap)
	spray.clear()
	_hide_markers()
	world.flag.visible = false
	if game_type == "target":
		var band: Vector2 = TARGET_BANDS[mini(turn, TARGET_THROWS - 1)] if mode == "solo" else Vector2(25, 100)
		target_x = snappedf(randf_range(band.x, band.y), 0.5)
		world.show_target(target_x)
	else:
		world.hide_target()
		_place_best_flag()
	gauge.value = 0.0
	Motion.reset()


func _place_best_flag() -> void:
	if mode == "solo":
		world.place_flag(Save.best_of("distance", drink.id).cap, "BEST")
	elif not players.is_empty():
		var lead := _leader()
		world.place_flag(lead.cap, lead.name)


func _update_shake(delta: float) -> void:
	energy += Motion.take_shake(delta)
	pressure = Flight.pressure_from_energy(energy, drink.gain)
	var k := Motion.intensity()
	gauge.value = pressure
	gauge.shake = k
	lbl_timer.text = str(maxi(1, ceili(SHAKE_TIME - t)))
	# the bottle rattles on the table as hard as you shake it
	world.bottle.rotation = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.06 * k
	world.bottle.position = Vector3(randf_range(-1, 1) * 0.004 * k, world.TABLE_TOP, 0)
	world.cap.global_position = world.mouth()
	world.cap.rotation = world.bottle.rotation
	world.bubbles.emitting = pressure > 0.02
	world.bubbles.speed_scale = 1.0 + k * 2.0
	Sfx.slosh(k, delta)
	_cam_shake = maxf(_cam_shake, k * 0.12)
	_cam_close(delta)
	if t >= SHAKE_TIME:
		_go(S.AIM)


func _update_aim(delta: float) -> void:
	elev = _demo_elev if Motion.demo and game_type == "target" else Motion.aim_degrees(delta)
	world.bottle.position = Vector3(0, world.TABLE_TOP, 0)
	world.lean_bottle(elev)
	world.cap.global_position = world.mouth()
	world.cap.rotation = world.bottle.rotation
	var mouth: Vector3 = world.mouth()
	var dir := Vector3(cos(deg_to_rad(elev)), sin(deg_to_rad(elev)), 0)
	arrow.global_position = mouth + dir * 0.04
	arrow.basis = Basis(Vector3(0, 0, 1), deg_to_rad(elev - 90.0)).scaled(Vector3.ONE * (0.8 + pressure * 0.9))
	lbl_timer.text = "%d°" % roundi(elev)
	_cam(Vector3(0.35, 1.2, 1.7), Vector3(0.45, 1.05, 0), 3.0, delta)
	if t >= AIM_TIME:
		_go(S.FLIGHT)


## Pops the cap. A fresh throw draws its random bits and keeps them in `last_throw`, so a
## replay can pop exactly the same throw again.
func _pop() -> void:
	arrow.visible = false
	gauge.visible = false
	lbl_phase.text = ""
	lbl_timer.text = ""
	lbl_hint.text = ""
	if not replaying:
		# a little sideways drift makes every distance throw different; at a bin 30 cm wide it
		# would only make it luck, so the target mode keeps it tiny
		var drift := 0.3 if game_type == "distance" else 0.03
		last_throw = {"pressure": pressure, "elev": elev, "wind": wind, "side": randf_range(-drift, drift),
				"spin": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
				"seed": randi(), "target_x": target_x}
		Motion.report("throw", {"pressure": snappedf(pressure, 0.001), "elev": snappedf(elev, 0.1),
				"energy": snappedf(energy, 0.01), "drink": drink.id})
	cap_stopped = false
	in_bin = false
	_acc = 0.0
	cap_pos = world.mouth()
	cap_vel = Flight.launch_velocity(pressure, elev, drink.cap_speed) + Vector3(0, 0, last_throw.side)
	cap_spin = last_throw.spin * (10.0 + pressure * 25.0)
	spray.start(world.mouth, elev, pressure, wind, last_throw.seed, drink)
	Sfx.play("pop", 0.0, 0.8 if replaying else randf_range(0.95, 1.05))
	Sfx.play("spray", -3.0)
	if not replaying:
		Motion.vibrate(120)
	world.trail.emitting = true
	world.cap.scale = Vector3.ONE * CAP_SHOW_SCALE
	_cam_shake = 0.5
	lbl_pop.text = "REPLAY" if replaying else "POP!"
	lbl_pop.visible = true
	lbl_pop.scale = Vector2(0.3, 0.3)
	lbl_pop.modulate.a = 1.0
	var tw := create_tween().set_ignore_time_scale()
	tw.tween_property(lbl_pop, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(lbl_pop, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): lbl_pop.visible = false)
	# the moment of the pop in slow motion, then back up to speed (timed in real seconds)
	Engine.time_scale = REPLAY_SLOWMO if replaying else SLOWMO
	var hold := 1.6 if replaying else 0.55
	var ramp := create_tween().set_ignore_time_scale()
	ramp.tween_interval(hold)
	ramp.tween_property(Engine, "time_scale", 1.0, 0.4)
	# the bottle kicks back and the soda level drops as it sprays out
	var base_rot: Vector3 = world.bottle.rotation
	var kick := create_tween()
	kick.tween_property(world.bottle, "rotation", base_rot + Vector3(0, 0, 0.18), 0.06)
	kick.tween_property(world.bottle, "rotation", base_rot, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var drain := create_tween()
	drain.tween_property(world.liquid, "scale:y", 0.22 + (1.0 - pressure) * 0.5,
			Flight.spray_duration(pressure, drink.spray_time)).set_ease(Tween.EASE_OUT)


func _update_flight(delta: float) -> void:
	_acc += delta
	var bin := Vector3(target_x, 0, 0)
	while _acc >= Flight.STEP and not cap_stopped:
		_acc -= Flight.STEP
		var prev := cap_pos
		var r := Flight.cap_step(cap_pos, cap_vel, wind, Flight.STEP)
		cap_pos = r[0]
		cap_vel = r[1]
		if game_type == "target":
			var b := Flight.bin_test(prev, cap_pos, cap_vel, bin)
			if b[0] == "in":
				in_bin = true
				cap_stopped = true
				cap_pos = Vector3(bin.x, 0.35, bin.z)
				cap_vel = Vector3.ZERO
				Sfx.play("cap_land", 0.0, 0.7)
				break
			elif b[0] == "hit":
				cap_vel = b[1]
				Sfx.play("cap_land", -2.0, 1.4)
		if r[2] == "bounce":
			Sfx.play("cap_land", clampf(-20.0 + absf(cap_vel.y) * 4.0, -20.0, 0.0), randf_range(0.9, 1.2))
		elif r[2] == "stop":
			cap_stopped = true
	world.cap.global_position = cap_pos + Vector3(0, 0.011 * CAP_SHOW_SCALE, 0)
	world.cap.visible = not in_bin
	var on_ground := cap_pos.y <= 0.001
	cap_spin *= 0.97 if on_ground else 0.999
	world.cap.rotation += cap_spin * delta
	if on_ground and cap_vel.length() < 2.0:
		# settle flat as it slows
		world.cap.rotation.x = lerp_angle(world.cap.rotation.x, 0.0, delta * 6.0)
		world.cap.rotation.z = lerp_angle(world.cap.rotation.z, 0.0, delta * 6.0)
	world.trail.emitting = not on_ground and not in_bin and cap_vel.length() > 3.0
	lbl_dist.text = "%.1f m" % maxf(0.0, cap_pos.x)
	# a wide shot of the pop and the jet, then the camera locks beside the cap. The cap's
	# path is already smooth, so a locked camera never loses it, however fast it flies.
	var wide_pos := Vector3(0.6, 1.5, 3.4)
	var wide_look := Vector3(2.2, 1.4, 0)
	var k := smoothstep(0.5, 1.0, t)
	var lock_pos := cap_pos + Vector3(-2.6, 0.7, 4.0)
	lock_pos.y = maxf(lock_pos.y, 0.8)
	var lock_look := cap_pos + Vector3(1.0, -0.25, 0)
	var cam: Camera3D = world.camera
	cam.position = wide_pos.lerp(lock_pos, k) + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _cam_shake * 0.08
	_look = wide_look.lerp(lock_look, k)
	cam.look_at(_look, Vector3.UP)
	if (cap_stopped and spray.is_done()) or t > 20.0:
		if replaying:
			world.trail.emitting = false
			_go(S.RESULT)   # a replay changes no score, not even the spray's last splat
		else:
			cap_dist = maxf(0.0, cap_pos.x)
			spray_dist = maxf(0.0, spray.reach)
			_go(S.LANDED)


func _landed() -> void:
	world.trail.emitting = false
	world.cap.rotation = Vector3(0, world.cap.rotation.y, 0)
	lbl_dist.text = "%.1f m" % cap_dist
	Save.count_throw()
	if game_type == "target":
		_score_target()
	else:
		_score_distance()
	Motion.report("result", {"type": game_type, "cap": snappedf(cap_dist, 0.1), "spray": snappedf(spray_dist, 0.1),
			"points": points, "in_bin": in_bin, "pressure": snappedf(pressure, 0.001), "elev": snappedf(elev, 0.1)})
	Sfx.play("cap_land", -6.0)


func _score_distance() -> void:
	cap_mark.text = "%.1f m" % cap_dist
	cap_mark.modulate = _player().color.lightened(0.3)
	cap_mark.position = Vector3(cap_pos.x, 0.45, cap_pos.z)
	cap_mark.visible = true
	spray_mark.text = "SPRAY %.1f m" % spray_dist
	spray_mark.position = Vector3(spray_dist, 0.6, 0.0)
	spray_mark.visible = spray_dist > 0.3
	var total := cap_dist + spray_dist
	if mode == "solo":
		new_best = Save.record_distance(drink.id, cap_dist, spray_dist)
		_place_best_flag()
		world.flag_label.visible = absf(Save.best_of("distance", drink.id).cap - cap_dist) > 3.0   # the cap's own label says it
	else:
		var p: Dictionary = _player()
		new_best = total > p.best
		if new_best:
			p.best = total
			p.cap = cap_dist
			p.spray = spray_dist
		_place_best_flag()
	if new_best and total > 1.0:
		Sfx.play("cheer", -4.0)
		Sfx.play("best", -2.0)


func _score_target() -> void:
	miss = 0.0 if in_bin else Vector2(cap_pos.x - target_x, cap_pos.z).length()
	points = Flight.target_points(in_bin, miss)
	cap_mark.text = "IN THE BIN!" if in_bin else "MISSED BY\n%.1f m" % miss
	cap_mark.modulate = UiTheme.YELLOW if in_bin else Color.WHITE
	cap_mark.position = Vector3(target_x if in_bin else cap_pos.x, 1.3 if in_bin else 0.45, cap_pos.z)
	cap_mark.visible = true
	if mode == "solo":
		target_total += points
		if turn + 1 >= TARGET_THROWS:
			new_best = Save.record_target(drink.id, target_total)
	else:
		_player().best += points
	if in_bin:
		Sfx.play("cheer", -2.0)
		Sfx.play("best", -2.0)
	elif points >= 30:
		Sfx.play("cheer", -10.0)


func _update_landed(delta: float) -> void:
	if t < 1.6:
		_orbit += delta * 0.6
		var at := Vector3(target_x, 0, 0) if in_bin else cap_pos
		_cam(at + Vector3(sin(_orbit) * 2.4 - 1.5, 1.4, cos(_orbit) * 1.2 + 3.0), at + Vector3(0, 0.4, 0), 3.5, delta)
	else:
		if game_type == "distance":
			cap_mark.visible = false
		_cam_overview(delta)
	if t >= LANDED_TIME:
		_go(S.RESULT)


func _replay() -> void:
	if last_throw.is_empty():
		return
	Sfx.play("click")
	replaying = true
	_share_ready = true    # the card already made stays valid
	for k in screens:
		screens[k].visible = false
	screens.hud.visible = true
	state = S.FLIGHT
	t = 0.0
	Motion.report_state("REPLAY")
	pressure = last_throw.pressure
	elev = last_throw.elev
	wind = last_throw.wind
	target_x = last_throw.target_x
	world.reset_bottle()
	world.lean_bottle(elev)
	world.cap.global_position = world.mouth()
	world.cap.rotation = world.bottle.rotation
	cap_mark.visible = false
	spray_mark.visible = false
	lbl_dist.text = ""
	_pop()


# ================================================================== turns & scoring
func _player() -> Dictionary:
	if mode == "solo" or players.is_empty():
		var b := Save.best_of(game_type, drink.id)
		return {"name": "YOU", "color": UiTheme.RED, "best": b.total, "cap": b.cap, "spray": b.spray}
	return players[turn % players.size()]


func _leader() -> Dictionary:
	var best: Dictionary = players[0]
	for p in players:
		if p.best > best.best:
			best = p
	return best


func _start_solo() -> void:
	Sfx.play("click")
	mode = "solo"
	players = []
	turn = 0
	target_total = 0
	_go(S.READY)


func _start_party() -> void:
	Sfx.play("click")
	mode = "party"
	players = []
	for i in n_players:
		players.append({"name": "PLAYER %d" % (i + 1), "color": UiTheme.PLAYER_COLORS[i], "best": 0.0, "cap": 0.0, "spray": 0.0})
	turn = 0
	_go(S.READY)


func _next_turn() -> void:
	Sfx.play("click")
	if mode == "party":
		turn += 1
		if turn >= n_players * n_rounds:
			_go(S.FINAL)
			return
	elif game_type == "target":
		turn += 1
		if turn >= TARGET_THROWS:
			turn = 0
			target_total = 0
	_go(S.READY)


func _units(v: float) -> String:
	return "%d pts" % roundi(v) if game_type == "target" else "%.1f m" % v


# ================================================================== share card
## Takes a picture of the result screen, with the buttons swapped for the game's name and
## address, and hands it to the page. The SHARE button then shares it from inside the tap.
func _prepare_share() -> void:
	if not Motion.can_share():
		return
	var hide: Array = [res_buttons, res_extra] if state == S.RESULT else final_buttons
	for c in hide:
		c.modulate.a = 0.0
	lbl_watermark.visible = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	for c in hide:
		c.modulate.a = 1.0
	lbl_watermark.visible = false
	if img.get_width() > 1080:
		img.resize(1080, roundi(img.get_height() * 1080.0 / img.get_width()), Image.INTERPOLATE_BILINEAR)
	Motion.set_share(img.save_jpg_to_buffer(0.86), _share_text())
	Motion.report("share_ready", img.get_size())


func _share_text() -> String:
	if state == S.FINAL:
		var w := _leader()
		if players.filter(func(p): return is_equal_approx(p.best, w.best)).size() > 1:
			return "Our Fizz Fling party ended in a tie at %s! https://%s" % [_units(w.best), SITE]
		return "%s won our Fizz Fling party with %s! https://%s" % [w.name, _units(w.best), SITE]
	if game_type == "target":
		if in_bin:
			return "I got the cap IN THE BIN from %.0f m in Fizz Fling! https://%s" % [target_x, SITE]
		return "I missed the bin by %.1f m in Fizz Fling. Beat that! https://%s" % [miss, SITE]
	return "I flung a %s cap %.1f m (+%.1f m of spray) in Fizz Fling! https://%s" % [drink.name, cap_dist, spray_dist, SITE]


# ================================================================== camera
func _cam(pos: Vector3, look: Vector3, rate: float, delta: float, look_rate := -1.0) -> void:
	var cam: Camera3D = world.camera
	var a := 1.0 - exp(-rate * delta)
	var b := 1.0 - exp(-(look_rate if look_rate > 0 else rate) * delta)
	cam.position = cam.position.lerp(pos, a)
	_look = _look.lerp(look, b)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _cam_shake * 0.08
	cam.position += shake
	if cam.position.distance_to(_look) > 0.01:
		cam.look_at(_look, Vector3.UP)


func _cam_close(delta: float) -> void:
	_cam(Vector3(0.3, 0.99, 0.8), Vector3(0.02, 0.97, 0), 3.0, delta)


## Distance: stands just past the end of the soda splats and looks back along the trail to the
## picnic table. Target: looks at the bin from beside it, with the cap in view. Both pitched
## down so the scene sits in the top half of the screen, above the result card.
func _cam_overview(delta: float) -> void:
	if game_type == "target":
		var mid := (target_x + (target_x if in_bin else cap_pos.x)) * 0.5
		var span := 3.0 + miss * 0.6
		_cam(Vector3(mid - 2.0, 2.4 + span * 0.35, 4.5 + span), Vector3(mid, -1.8, -0.4), 2.0, delta)
		return
	var r := maxf(spray_dist, 3.0)
	_cam(Vector3(r + 3.0, 2.2 + r * 0.06, 3.4 + r * 0.05), Vector3(r * 0.4, -1.6 - r * 0.02, -0.4), 2.0, delta)


# ================================================================== 3D markers
func _make_markers() -> void:
	arrow = Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UiTheme.YELLOW
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = 0.3
	cm.material = mat
	shaft.mesh = cm
	shaft.position = Vector3(0, 0.15, 0)
	arrow.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.035
	cone.height = 0.08
	cone.material = mat
	head.mesh = cone
	head.position = Vector3(0, 0.34, 0)
	arrow.add_child(head)
	arrow.visible = false
	add_child(arrow)
	cap_mark = _marker(Color.WHITE)
	spray_mark = _marker(Color(1.0, 0.8, 0.45))


func _marker(col: Color) -> Label3D:
	var l := Label3D.new()
	l.font = UiTheme.font
	l.font_size = 72
	l.pixel_size = 0.0012
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 16
	l.outline_modulate = UiTheme.DEEP
	l.modulate = col
	l.visible = false
	add_child(l)
	return l


func _hide_markers() -> void:
	arrow.visible = false
	cap_mark.visible = false
	spray_mark.visible = false


# ================================================================== interface
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiTheme.make()
	layer.add_child(ui_root)
	screens.title = _build_title()
	screens.setup = _build_setup()
	screens.hud = _build_hud()
	screens.ready = _build_ready()
	screens.result = _build_result()
	screens.final = _build_final()
	lbl_pop = UiTheme.label("POP!", 210, UiTheme.YELLOW, 22)
	lbl_pop.set_anchors_preset(Control.PRESET_CENTER)
	lbl_pop.size = Vector2(720, 280)
	lbl_pop.position = Vector2(-360, -380)
	lbl_pop.pivot_offset = Vector2(360, 140)
	lbl_pop.rotation = deg_to_rad(-6)
	lbl_pop.visible = false
	ui_root.add_child(lbl_pop)
	# written into the share picture where the buttons were
	lbl_watermark = UiTheme.label("FIZZ FLING\n" + SITE, 40, UiTheme.YELLOW, 12)
	lbl_watermark.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_watermark.offset_left = -360
	lbl_watermark.offset_right = 360
	lbl_watermark.offset_top = -250
	lbl_watermark.offset_bottom = -60
	lbl_watermark.visible = false
	ui_root.add_child(lbl_watermark)


func _screen(margin := 44) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	m.add_theme_constant_override("margin_top", margin + 30)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(m)
	return m


func _vbox(parent: Control, sep := 20) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


func _hbox(parent: Control, sep := 20) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	return h


func _spacer(parent: Control, h := 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h > 0:
		c.custom_minimum_size.y = h
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


func _chip(parent: Control, text: String, bg: Color, size := 34) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.chip(bg))
	var l := UiTheme.label(text, size, UiTheme.WHITE, 8)
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(p)
	return p


func _chip_text(c: PanelContainer, text: String, bg: Color) -> void:
	(c.get_child(0) as Label).text = text
	c.add_theme_stylebox_override("panel", UiTheme.chip(bg))


func _paint(b: Button, col: Color) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, UiTheme.pill(col, st))


func _build_title() -> Control:
	var s := _screen()
	var bubbles := preload("res://scripts/bubbles.gd").new()
	bubbles.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(bubbles)
	var v := _vbox(s, 12)
	_spacer(v, 10)
	var fizz := UiTheme.label("FIZZ", 170, UiTheme.YELLOW, 24)
	fizz.add_theme_constant_override("shadow_offset_y", 11)
	v.add_child(fizz)
	var fling := UiTheme.label("FLING", 128, UiTheme.WHITE, 22)
	fling.add_theme_constant_override("shadow_offset_y", 9)
	v.add_child(fling)
	var best_chip := _chip(v, "", UiTheme.RED, 36)
	lbl_best = best_chip.get_child(0)
	_spacer(v)
	# the drink picker: the bottle on the table behind changes with it
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card(Color(1, 0.965, 0.9, 0.92), UiTheme.RED))
	v.add_child(card)
	var row := _hbox(card, 10)
	var prev := UiTheme.button("<", UiTheme.YELLOW, 64)
	prev.custom_minimum_size = Vector2(104, 104)
	prev.pressed.connect(func(): _cycle_drink(-1))
	row.add_child(prev)
	var mid := _vbox(row, 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_drink = UiTheme.label("", 50, UiTheme.RED, 0)
	mid.add_child(lbl_drink)
	lbl_trait = UiTheme.label("", 28, UiTheme.DEEP, 0)
	mid.add_child(lbl_trait)
	var nxt := UiTheme.button(">", UiTheme.YELLOW, 64)
	nxt.custom_minimum_size = Vector2(104, 104)
	nxt.pressed.connect(func(): _cycle_drink(1))
	row.add_child(nxt)
	# the game type
	var types := _hbox(v, 16)
	for pair in [["distance", "DISTANCE"], ["target", "TARGET"]]:
		var b := UiTheme.button(pair[1], UiTheme.CREAM, 44)
		b.custom_minimum_size = Vector2(300, 100)
		b.pressed.connect(func(): _set_type(pair[0]))
		types.add_child(b)
		btn_types[pair[0]] = b
	btn_own_page = UiTheme.button("PLAY FULL SCREEN", UiTheme.GREEN)
	btn_own_page.button_down.connect(Motion.open_own_page)
	v.add_child(btn_own_page)
	var solo := UiTheme.button("PLAY SOLO", UiTheme.YELLOW, 64)
	solo.pressed.connect(_start_solo)
	v.add_child(solo)
	var party := UiTheme.button("PARTY  (2-6 PLAYERS)", UiTheme.SKY, 50)
	party.pressed.connect(func(): Sfx.play("click"); _go(S.SETUP))
	v.add_child(party)
	btn_sound = UiTheme.button("", UiTheme.CREAM, 32)
	btn_sound.custom_minimum_size = Vector2(250, 80)
	btn_sound.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_sound.pressed.connect(func():
		Save.sound = not Save.sound
		Save.write()
		Sfx.play("click")
		_refresh_title())
	v.add_child(btn_sound)
	return s


func _refresh_title() -> void:
	var b := Save.best_of(game_type, drink.id)
	if b.total <= 0:
		lbl_best.text = "NO %s GAMES YET" % game_type.to_upper() if game_type == "target" else "NO THROWS YET"
	else:
		lbl_best.text = "BEST  %s" % _units(b.total)
	lbl_drink.text = drink.name
	lbl_trait.text = drink.trait
	for k in btn_types:
		_paint(btn_types[k], UiTheme.YELLOW if k == game_type else UiTheme.CREAM)
	btn_own_page.visible = Motion.needs_own_page()
	btn_sound.text = "SOUND: ON" if Save.sound else "SOUND: OFF"


func _build_setup() -> Control:
	var s := _screen()
	var v := _vbox(s, 26)
	_spacer(v)
	var card := PanelContainer.new()
	v.add_child(card)
	var c := _vbox(card, 22)
	c.add_child(UiTheme.label("PARTY", 96, UiTheme.RED, 14))
	lbl_setup_mode = UiTheme.label("", 34, UiTheme.DEEP, 0)
	c.add_child(lbl_setup_mode)
	c.add_child(UiTheme.label("PLAYERS", 44, UiTheme.DEEP, 0))
	var row := _hbox(c, 28)
	var minus := UiTheme.button("-", UiTheme.RED, 80)
	minus.custom_minimum_size = Vector2(128, 128)
	minus.pressed.connect(func(): n_players = maxi(2, n_players - 1); Sfx.play("click"); _refresh_setup())
	row.add_child(minus)
	lbl_players = UiTheme.label("2", 110, UiTheme.RED, 14)
	lbl_players.custom_minimum_size.x = 120
	row.add_child(lbl_players)
	var plus := UiTheme.button("+", UiTheme.GREEN, 80)
	plus.custom_minimum_size = Vector2(128, 128)
	plus.pressed.connect(func(): n_players = mini(6, n_players + 1); Sfx.play("click"); _refresh_setup())
	row.add_child(plus)
	setup_dots = _hbox(c, 12)
	c.add_child(UiTheme.label("ROUNDS", 44, UiTheme.DEEP, 0))
	var rr := _hbox(c, 28)
	for n in [1, 3]:
		var b := UiTheme.button(str(n), UiTheme.CREAM, 64)
		b.custom_minimum_size = Vector2(170, 120)
		b.pressed.connect(func(): n_rounds = n; Sfx.play("click"); _refresh_setup())
		rr.add_child(b)
		btn_rounds.append(b)
	_spacer(v, 10)
	var go := UiTheme.button("START", UiTheme.YELLOW, 70)
	go.pressed.connect(_start_party)
	v.add_child(go)
	var back := UiTheme.button("BACK", UiTheme.CREAM, 44)
	back.custom_minimum_size.y = 100
	back.pressed.connect(func(): Sfx.play("click"); _go(S.TITLE))
	v.add_child(back)
	_spacer(v)
	return s


func _refresh_setup() -> void:
	lbl_players.text = str(n_players)
	if game_type == "target":
		lbl_setup_mode.text = "TARGET with %s\nPoints add up - most points wins!" % drink.name
	else:
		lbl_setup_mode.text = "DISTANCE with %s\nBest throw wins!" % drink.name
	for ch in setup_dots.get_children():
		ch.queue_free()
	for i in n_players:
		_chip(setup_dots, "P%d" % (i + 1), UiTheme.PLAYER_COLORS[i], 30)
	for i in btn_rounds.size():
		_paint(btn_rounds[i], UiTheme.YELLOW if [1, 3][i] == n_rounds else UiTheme.CREAM)


func _build_hud() -> Control:
	var s := _screen(30)
	var v := _vbox(s, 10)
	var top := VBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	chip_player = _chip(top, "", UiTheme.RED, 32)
	chip_wind = _chip(top, "", UiTheme.GREEN, 32)
	lbl_dist = UiTheme.label("", 96, UiTheme.WHITE, 16)
	v.add_child(lbl_dist)
	lbl_phase = UiTheme.label("", 100, UiTheme.YELLOW, 20)
	v.add_child(lbl_phase)
	lbl_timer = UiTheme.label("", 170, UiTheme.WHITE, 22)
	lbl_timer.pivot_offset = Vector2(320, 100)
	v.add_child(lbl_timer)
	_spacer(v)
	lbl_hint = UiTheme.label("", 36, UiTheme.WHITE, 12)
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lbl_hint)
	_spacer(v, 30)
	gauge = preload("res://scripts/gauge.gd").new()
	gauge.visible = false
	ui_root.add_child(gauge)
	gauge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	gauge.offset_left = -160
	gauge.offset_right = -30
	gauge.offset_top = -120
	gauge.offset_bottom = 300
	return s


func _hud_for_ready() -> void:
	var lines := []
	if mode == "party":
		lines.append("%s  -  ROUND %d/%d" % [_player().name, turn / n_players + 1, n_rounds])
	if game_type == "target":
		lines.append(("TARGET %d/%d  -  " % [turn + 1, TARGET_THROWS] if mode == "solo" else "") + "BIN AT %.0f m" % target_x)
	chip_player.visible = not lines.is_empty()
	_chip_text(chip_player, "   ".join(lines), _player().color if mode == "party" else UiTheme.DEEP)
	if absf(wind) < 0.05:
		_chip_text(chip_wind, "NO WIND", UiTheme.SKY)
	elif wind > 0:
		_chip_text(chip_wind, "TAILWIND  %.1f m/s" % wind, UiTheme.GREEN)
	else:
		_chip_text(chip_wind, "HEADWIND  %.1f m/s" % -wind, UiTheme.ORANGE)
	lbl_phase.text = ""
	lbl_timer.text = ""
	lbl_hint.text = ""
	lbl_dist.text = ""
	gauge.visible = false


func _shake_hint() -> String:
	if Motion.has_motion() or Motion.demo:
		return "SHAKE THE PHONE AS HARD AS YOU CAN!" if game_type == "distance" else "SHAKE - but only as hard as the bin needs!"
	if Motion.is_touch():
		return "No motion sensor here - RUB THE SCREEN FAST!"
	return "RUB the screen with the mouse, or MASH LEFT / RIGHT!"


func _aim_hint() -> String:
	var tip := "About 40° flies furthest!" if game_type == "distance" else "Steep lobs drop into the bin!"
	if Motion.has_motion() or Motion.demo:
		return "Tip the top of the phone to the right.\n" + tip
	return "DRAG left / right (or arrow keys) to aim.\n" + tip


func _build_ready() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(s)
	var dim := ColorRect.new()
	dim.color = Color(0.2, 0.02, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(dim)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(m)
	var v := _vbox(m, 22)
	_spacer(v)
	ready_chip = _chip(v, "", UiTheme.RED, 56)
	ready_name = ready_chip.get_child(0)
	v.add_child(UiTheme.label("GET A GRIP!", 96, UiTheme.YELLOW, 18))
	ready_how = UiTheme.label("", 40, UiTheme.WHITE, 12)
	v.add_child(ready_how)
	_spacer(v, 40)
	var tap := UiTheme.label("TAP TO START", 70, UiTheme.WHITE, 16)
	v.add_child(tap)
	var tw := create_tween().set_loops()
	tw.tween_property(tap, "modulate:a", 0.35, 0.6)
	tw.tween_property(tap, "modulate:a", 1.0, 0.6)
	_spacer(v)
	var catcher := Button.new()
	catcher.flat = true
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	for st in ["normal", "hover", "pressed", "focus"]:
		catcher.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	catcher.pressed.connect(func():
		if state == S.READY:
			Sfx.play("click")
			_go(S.COUNT))
	s.add_child(catcher)
	s.visibility_changed.connect(func():
		if s.visible:
			var p := _player()
			ready_name.text = p.name if mode == "party" else drink.name
			ready_chip.add_theme_stylebox_override("panel", UiTheme.chip(p.color if mode == "party" else drink.cap.darkened(0.1)))
			if game_type == "target":
				ready_how.text = "1. SHAKE just enough\n2. TILT to aim\n3. POP! Land it in the bin at %.0f m" % target_x
			else:
				ready_how.text = "1. SHAKE hard for 5 seconds\n2. TILT to aim\n3. POP! Cap + spray = score")
	return s


func _build_result() -> Control:
	var s := _screen()
	var v := _vbox(s, 16)
	_spacer(v)
	var card := PanelContainer.new()
	v.add_child(card)
	var c := _vbox(card, 6)
	res_title = UiTheme.label("", 60, UiTheme.RED, 0)
	res_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(res_title)
	res_rows = _vbox(c, 4)
	res_extra = _hbox(v, 20)
	var replay := UiTheme.button("REPLAY", UiTheme.SKY, 40)
	replay.custom_minimum_size = Vector2(0, 96)
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replay.pressed.connect(_replay)
	res_extra.add_child(replay)
	var share := UiTheme.button("SHARE", UiTheme.GREEN, 40)
	share.custom_minimum_size = Vector2(0, 96)
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share.button_down.connect(Motion.arm_share)
	share.pressed.connect(func(): Sfx.play("click"))
	share.visible = Motion.can_share()
	res_extra.add_child(share)
	res_buttons = _hbox(v, 20)
	_spacer(v, 30)
	return s


func _row(parent: Control, name: String, value: String, size: int, col: Color) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var a := UiTheme.label(name, int(size * 0.6), UiTheme.DEEP, 0)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := UiTheme.label(value, size, col, 10)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(b)


func _line(parent: Control) -> void:
	var line := ColorRect.new()
	line.color = UiTheme.DEEP
	line.custom_minimum_size.y = 6
	parent.add_child(line)


func _button(parent: Control, text: String, col: Color, size: int, stretch: float, cb: Callable) -> void:
	var b := UiTheme.button(text, col, size)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = stretch
	b.pressed.connect(cb)
	parent.add_child(b)


func _show_result() -> void:
	for ch in res_rows.get_children():
		ch.queue_free()
	for ch in res_buttons.get_children():
		ch.queue_free()
	if game_type == "target":
		_result_target()
	else:
		_result_distance()
	var info := UiTheme.label("%s   -   pressure %d%%   -   angle %d°   -   wind %+.1f" % [drink.name.to_lower(), roundi(pressure * 100), roundi(elev), wind], 24, UiTheme.DEEP, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_rows.add_child(info)
	var menu_cb := func(): Sfx.play("click"); _go(S.TITLE)
	if mode == "solo":
		_button(res_buttons, "MENU", UiTheme.CREAM, 50, 1.0, menu_cb)
		var label := "AGAIN"
		if game_type == "target":
			label = "NEXT TARGET" if turn + 1 < TARGET_THROWS else "NEW GAME"
		_button(res_buttons, label, UiTheme.YELLOW, 54, 1.6, _next_turn)
	else:
		var last := turn + 1 >= n_players * n_rounds
		var nxt: Dictionary = players[(turn + 1) % players.size()]
		_button(res_buttons, "SEE THE WINNER" if last else "NEXT: %s" % nxt.name, UiTheme.YELLOW, 54, 1.0, _next_turn)
	if not replaying:
		var tw := create_tween()
		screens.result.modulate.a = 0.0
		tw.tween_property(screens.result, "modulate:a", 1.0, 0.25)
	replaying = false


func _result_distance() -> void:
	var total := cap_dist + spray_dist
	var p := _player()
	if new_best and total > 1.0:
		res_title.text = "NEW BEST!" if mode == "solo" else "%s - NEW BEST!" % p.name
	else:
		res_title.text = _verdict(total) if mode == "solo" else p.name
	res_title.add_theme_color_override("font_color", p.color if mode == "party" else UiTheme.RED)
	_row(res_rows, "CAP", "%.1f m" % cap_dist, 70, UiTheme.RED)
	_row(res_rows, "SPRAY", "%.1f m" % spray_dist, 70, UiTheme.ORANGE)
	_line(res_rows)
	_row(res_rows, "TOTAL", "%.1f m" % total, 110, UiTheme.GREEN)
	if mode == "solo":
		res_rows.add_child(UiTheme.label("BEST WITH %s  %.1f m" % [drink.name, Save.best_of("distance", drink.id).total], 32, UiTheme.RED, 0))


func _result_target() -> void:
	var p := _player()
	if in_bin:
		res_title.text = "IN THE BIN!"
	elif mode == "party":
		res_title.text = p.name
	else:
		res_title.text = "SO CLOSE!" if miss < 2.0 else ("NOT BAD!" if points > 0 else "MISSED!")
	res_title.add_theme_color_override("font_color", p.color if mode == "party" else UiTheme.RED)
	_row(res_rows, "BIN AT", "%.1f m" % target_x, 56, UiTheme.DEEP)
	_row(res_rows, "MISSED BY", "IN!" if in_bin else "%.1f m" % miss, 56, UiTheme.ORANGE)
	_line(res_rows)
	_row(res_rows, "POINTS", "+%d" % points, 100, UiTheme.GREEN)
	if mode == "solo":
		var done := turn + 1 >= TARGET_THROWS
		var line := "TOTAL %d pts after %d of %d" % [target_total, turn + 1, TARGET_THROWS]
		if done:
			line = ("NEW BEST!  " if new_best else "") + "FINAL %d pts  -  best %d" % [target_total, roundi(Save.best_of("target", drink.id).total)]
		res_rows.add_child(UiTheme.label(line, 34, UiTheme.RED, 0))
	else:
		res_rows.add_child(UiTheme.label("%s has %d pts" % [p.name, roundi(p.best)], 34, p.color, 0))


func _verdict(total: float) -> String:
	if total < 10: return "JUST A FIZZLE"
	if total < 40: return "NICE POP!"
	if total < 80: return "BIG FIZZ!"
	if total < 120: return "SODA ROCKET!"
	return "LEGENDARY FIZZ!"


func _build_final() -> Control:
	var s := _screen()
	var bubbles := preload("res://scripts/bubbles.gd").new()
	bubbles.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(bubbles)
	var v := _vbox(s, 20)
	_spacer(v)
	final_title = UiTheme.label("", 96, UiTheme.YELLOW, 20)
	final_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(final_title)
	var card := PanelContainer.new()
	v.add_child(card)
	final_list = _vbox(card, 10)
	_spacer(v, 10)
	var row := _hbox(v, 20)
	var again := UiTheme.button("REMATCH", UiTheme.YELLOW, 56)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(_start_party)
	row.add_child(again)
	var share := UiTheme.button("SHARE", UiTheme.GREEN, 44)
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share.button_down.connect(Motion.arm_share)
	share.pressed.connect(func(): Sfx.play("click"))
	share.visible = Motion.can_share()
	row.add_child(share)
	var menu := UiTheme.button("MENU", UiTheme.CREAM, 48)
	menu.custom_minimum_size.y = 104
	menu.pressed.connect(func(): Sfx.play("click"); _go(S.TITLE))
	v.add_child(menu)
	final_buttons = [row, menu]
	_spacer(v)
	return s


func _show_final() -> void:
	_share_ready = false
	for ch in final_list.get_children():
		ch.queue_free()
	var order := players.duplicate()
	order.sort_custom(func(a, b): return a.best > b.best)
	_hide_markers()
	var tied := order.filter(func(p): return is_equal_approx(p.best, order[0].best))
	if tied.size() > 1:
		final_title.text = "IT'S A TIE!\n" + " & ".join(tied.map(func(p): return p.name.replace("PLAYER ", "P")))
	else:
		final_title.text = "%s\nWINS!" % order[0].name
	final_title.add_theme_color_override("font_color", order[0].color.lightened(0.25))
	for i in order.size():
		var p: Dictionary = order[i]
		_row(final_list, "%d.  %s" % [i + 1, p.name], _units(p.best), 64 if i == 0 else 50, p.color)
	Motion.report("final", order.map(func(p): return [p.name, snappedf(p.best, 0.1)]))
	Sfx.play("win")
	Sfx.play("cheer", -3.0)


func _pulse(c: Control) -> void:
	c.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
