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
	# drinks
	var D = load("res://scripts/drinks.gd")
	var totals := []
	for d in D.LIST:
		var p: float = F.pressure_from_energy(50.0, d.gain)
		totals.append(F.simulate_cap(p, 42.0, 0.0, 1.1, d.cap_speed).stop + F.simulate_spray(p, 42.0, 0.0, 1.1, d.spray))
	var mean: float = totals.reduce(func(a, b): return a + b) / totals.size()
	var spread: float = (totals.max() - totals.min()) / mean
	check("every drink's hard throw totals within 10% of the others", spread < 0.1,
			" / ".join(totals.map(func(x): return "%.0f" % x)))
	var cola = D.get_drink("cola")
	var spark = D.get_drink("sparkling")
	var band = D.get_drink("bandung")
	check("cola builds pressure fastest", F.pressure_from_energy(15.0, cola.gain) > F.pressure_from_energy(15.0, 1.0))
	check("sparkling water sends the cap furthest",
			F.simulate_cap(0.9, 42, 0, 1.1, spark.cap_speed).stop > F.simulate_cap(0.9, 42, 0, 1.1, cola.cap_speed).stop)
	check("sirap bandung sprays furthest", F.simulate_spray(0.9, 42, 0, 1.1, band.spray) > F.simulate_spray(0.9, 42, 0, 1.1, cola.spray))
	# target mode: the bin
	var in_all := true
	var lobs := []
	for x in [22.0, 45.0, 70.0, 90.0, 112.0]:
		var lob: Array = F.lob_for_bin(0.0, x)
		lobs.append("%d m: %.2f at %d°" % [x, lob[0], lob[1]])
		if not F.simulate_to_bin(lob[0], lob[1], 0.0, x)[0]:
			in_all = false
	check("a well-judged lob drops into the bin at every target distance (22-112 m)", in_all, ", ".join(lobs))
	var r2: Array = F.simulate_to_bin(F.pressure_for_bin(68.0, 0.0, 50.0), 68.0, 0.0, 53.0)
	check("a lob 3 m short does not count as in", not r2[0] and r2[1] > 1.0, "missed by %.1f" % r2[1])
	var hit: Array = F.bin_test(Vector3(49.5, 0.3, 0), Vector3(49.65, 0.3, 0), Vector3(12, 0, 0), Vector3(50, 0, 0))
	check("a cap skidding into the bin's wall bounces back off it", hit[0] == "hit" and hit[1].x < 0.0)
	check("points: 100 in the bin, 50 for a touch, none past 10 m",
			F.target_points(true, 0.0) == 100 and F.target_points(false, 0.0) == 50 and F.target_points(false, 10.0) == 0)
	print("\n%d failed" % fails)
	quit(1 if fails > 0 else 0)
