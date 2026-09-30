extends SceneTree
## Headless rules for the throw physics (scripts/flight.gd). Each line prints PASS or FAIL.
## Run: tools/checks/run.sh

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func _init() -> void:
	var F = load("res://scripts/flight.gd")
	# pressure
	check("no shaking gives no pressure", F.pressure_from_energy(0.0) == 0.0)
	check("pressure never passes 1", F.pressure_from_energy(10000.0) <= 1.0)
	var mono := true
	for e in range(0, 200, 5):
		if F.pressure_from_energy(e + 5) <= F.pressure_from_energy(e):
			mono = false
	check("more shaking always means more pressure", mono)
	check("5 s of hard shaking (~50 energy) reaches 85-95%", absf(F.pressure_from_energy(50.0) - 0.9) < 0.05,
			"%.2f" % F.pressure_from_energy(50.0))
	# distance
	var prev := -1.0
	var grows := true
	for p in [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
		var d: float = F.simulate_cap(p, 42.0, 0.0).stop
		if d <= prev:
			grows = false
		prev = d
	check("more pressure always flies further", grows)
	var best: float = F.simulate_cap(1.0, 42.0, 0.0).stop
	check("a perfect throw lands inside the 180 m field", best > 100.0 and best < 175.0, "%.1f m" % best)
	var weak: float = F.simulate_cap(0.05, 42.0, 0.0).stop
	check("a barely-shaken bottle still pops a few metres", weak > 2.0 and weak < 15.0, "%.1f m" % weak)
	var best_a := 0
	var best_d := 0.0
	for a in range(10, 86):
		var d: float = F.simulate_cap(0.9, a, 0.0).stop
		if d > best_d:
			best_d = d
			best_a = a
	check("the best angle is between 35° and 45° (the hint says about 40°)", best_a >= 35 and best_a <= 45, "%d°" % best_a)
	var flat: float = F.simulate_cap(0.9, 15.0, 0.0).stop
	check("aiming badly costs at least a third of the distance", flat < best_d * 0.67, "15°: %.0f vs %.0f" % [flat, best_d])
	var tail: float = F.simulate_cap(0.9, 40.0, 3.0).stop
	var head: float = F.simulate_cap(0.9, 40.0, -3.0).stop
	var calm: float = F.simulate_cap(0.9, 40.0, 0.0).stop
	check("a tailwind helps and a headwind hurts", tail > calm and calm > head, "%.0f / %.0f / %.0f" % [head, calm, tail])
	check("wind changes a throw by under 10%", absf(tail - calm) / calm < 0.1)
	var r: Dictionary = F.simulate_cap(0.9, 40.0, 0.0)
	check("the cap rolls on after landing, but not far", r.stop > r.land and r.stop - r.land < 25.0,
			"lands %.0f, stops %.0f" % [r.land, r.stop])
	check("a throw finishes in under 12 s", r.time < 12.0, "%.1f s" % r.time)
	# spray
	var sp: float = F.simulate_spray(0.9, 42.0, 0.0)
	check("the spray reaches less far than the cap", sp < r.land, "%.1f m" % sp)
	check("a strong spray reaches 20-40 m", sp > 20.0 and sp < 40.0)
	check("more pressure sprays further", F.simulate_spray(0.9, 42, 0) > F.simulate_spray(0.4, 42, 0))
	print("\n%d failed" % fails)
	quit(1 if fails > 0 else 0)
