extends Node
## The player's records and settings, kept on the device (on the web, in the browser's storage).

const PATH := "user://fizz_fling.cfg"

var best_total := 0.0
var best_cap := 0.0
var best_spray := 0.0
var throws := 0
var sound := true
var seen_help := false


func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	best_total = c.get_value("best", "total", 0.0)
	best_cap = c.get_value("best", "cap", 0.0)
	best_spray = c.get_value("best", "spray", 0.0)
	throws = c.get_value("stats", "throws", 0)
	sound = c.get_value("settings", "sound", true)
	seen_help = c.get_value("settings", "seen_help", false)


## Records one solo throw. Returns true when it is a new best total.
func record(cap: float, spray: float) -> bool:
	throws += 1
	var total := cap + spray
	var is_best := total > best_total
	if is_best:
		best_total = total
	best_cap = maxf(best_cap, cap)
	best_spray = maxf(best_spray, spray)
	write()
	return is_best


func write() -> void:
	if Motion.demo:
		return   # the self-playing demo must not overwrite a real player's records
	var c := ConfigFile.new()
	c.set_value("best", "total", best_total)
	c.set_value("best", "cap", best_cap)
	c.set_value("best", "spray", best_spray)
	c.set_value("stats", "throws", throws)
	c.set_value("settings", "sound", sound)
	c.set_value("settings", "seen_help", seen_help)
	c.save(PATH)
