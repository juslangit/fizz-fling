extends Node
## Every screen must fit the phone's width with every drink and game type. On 2026-09-30
## "SPARKLING WATER" made the drink card wider than the screen, which dragged the title's
## buttons past the right edge on Luqman's iPhone. The narrowest screen is the 720-wide base.
## Run as a scene (tools/checks/layout_check.tscn), so the project's autoloads exist.

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var width: float = ProjectSettings.get_setting("display/window/size/viewport_width")
	for type in ["distance", "target"]:
		for d in Drinks.LIST:
			game.game_type = type
			game._set_drink(d.id)
			game._refresh_title()
			await get_tree().process_frame
			var need: float = game.screens.title.get_combined_minimum_size().x
			check("title fits with %s (%s)" % [d.name, type], need <= width, "needs %d of %d px" % [need, width])
	# the widest chips: a party target turn with the longest drink name
	game.game_type = "target"
	game._set_drink("sparkling")
	game.n_players = 6
	game.n_rounds = 3
	game._start_party()
	game.target_x = 100.0
	game.turn = 17
	game._hud_for_ready()
	await get_tree().process_frame
	var hud: float = game.screens.hud.get_combined_minimum_size().x
	check("the turn chips fit on a party target turn", hud <= width, "needs %d of %d px" % [hud, width])
	game.mode = "solo"
	game._go(game.S.READY)
	await get_tree().process_frame
	var chip: float = game.ready_chip.get_combined_minimum_size().x
	check("the get-ready name chip fits with SPARKLING WATER", chip <= width, "needs %d of %d px" % [chip, width])
	print("\n%d failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)
