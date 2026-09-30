extends Control
## Soda bubbles drifting up behind the menus.

var _b := []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 34:
		_b.append([randf(), randf(), randf_range(6, 26), randf_range(40, 140), randf() * TAU])


func _process(delta: float) -> void:
	for b in _b:
		b[1] -= b[3] * delta / maxf(size.y, 1.0)
		b[4] += delta * 2.0
		if b[1] < -0.05:
			b[1] = 1.05
			b[0] = randf()
	queue_redraw()


func _draw() -> void:
	for b in _b:
		var p := Vector2(b[0] * size.x + sin(b[4]) * 12.0, b[1] * size.y)
		draw_circle(p, b[2], Color(1, 1, 1, 0.18))
		draw_arc(p, b[2], 0, TAU, 20, Color(1, 1, 1, 0.55), 3.0, true)
		draw_circle(p + Vector2(-b[2] * 0.35, -b[2] * 0.35), b[2] * 0.22, Color(1, 1, 1, 0.7))
