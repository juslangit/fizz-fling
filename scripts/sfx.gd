extends Node
## Sound: one-shot effects from a small pool, plus the slosh that follows how hard you shake.

const FILES := {
	"pop": "pop.mp3", "spray": "spray.mp3", "cap_land": "cap_land.mp3", "cheer": "cheer.mp3",
	"splash": "splash.mp3", "slosh1": "slosh1.mp3", "slosh2": "slosh2.mp3", "slosh3": "slosh3.mp3",
	"beep": "beep.mp3", "go": "go.mp3", "best": "best.ogg", "win": "win.ogg", "click": "click.ogg",
}

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _slosh_cool := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in FILES:
		_streams[k] = load("res://assets/sfx/" + FILES[k])
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not Save.sound or not _streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## Called every frame of the shake: the harder the shake, the more often the soda sloshes.
func slosh(intensity: float, delta: float) -> void:
	_slosh_cool -= delta
	if intensity < 0.15 or _slosh_cool > 0.0:
		return
	_slosh_cool = lerpf(0.5, 0.16, clampf(intensity, 0.0, 1.0))
	play(["slosh1", "slosh2", "slosh3"].pick_random(), lerpf(-12.0, -2.0, clampf(intensity, 0.0, 1.0)),
			randf_range(0.9, 1.15))
