extends Node
## The player's records and settings, kept on the device (on the web, in the browser's storage).
## Records are kept per game type and per drink:
##   best["distance"][drink] = {total, cap, spray}   the best single throw
##   best["target"][drink]   = {total}               the best five-target game, in points

const PATH := "user://fizz_fling.cfg"

var best := {"distance": {}, "target": {}}
var throws := 0
var sound := true
var drink := "orange"
var game_type := "distance"


func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	throws = c.get_value("stats", "throws", 0)
	sound = c.get_value("settings", "sound", true)
	drink = c.get_value("settings", "drink", "orange")
	game_type = c.get_value("settings", "game_type", "distance")
	best = c.get_value("records", "best", best)
	# records from before drinks existed were all thrown with the orange soda
	if c.has_section_key("best", "total") and not best.distance.has("orange"):
		best.distance["orange"] = {"total": c.get_value("best", "total", 0.0),
				"cap": c.get_value("best", "cap", 0.0), "spray": c.get_value("best", "spray", 0.0)}


func best_of(type: String, drink_id: String) -> Dictionary:
	return best[type].get(drink_id, {"total": 0.0, "cap": 0.0, "spray": 0.0})


## Records one solo distance throw. Returns true when it is a new best total for that drink.
func record_distance(drink_id: String, cap: float, spray: float) -> bool:
	var b := best_of("distance", drink_id)
	var is_best: bool = cap + spray > b.total
	if is_best:
		best.distance[drink_id] = {"total": cap + spray, "cap": cap, "spray": spray}
	write()
	return is_best


## Records a finished five-target game. Returns true when it is a new best for that drink.
func record_target(drink_id: String, points: int) -> bool:
	var is_best: bool = points > best_of("target", drink_id).total
	if is_best:
		best.target[drink_id] = {"total": float(points), "cap": 0.0, "spray": 0.0}
	write()
	return is_best


func count_throw() -> void:
	throws += 1


func write() -> void:
	if Motion.demo:
		return   # the self-playing demo must not overwrite a real player's records
	var c := ConfigFile.new()
	c.set_value("records", "best", best)
	c.set_value("stats", "throws", throws)
	c.set_value("settings", "sound", sound)
	c.set_value("settings", "drink", drink)
	c.set_value("settings", "game_type", game_type)
	c.save(PATH)
