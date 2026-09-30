extends Control
## The pressure meter: a soda bottle drawn on screen that fills from the bottom as you shake,
## yellow at first, turning orange and then red near full, with bubbles racing up inside.

var value := 0.0          # 0..1
var shake := 0.0          # live shake intensity, makes the bubbles race
var _bubbles := []
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(150, 460)
	for i in 14:
		_bubbles.append(Vector2(randf(), randf()))


func _process(delta: float) -> void:
	_t += delta
	for i in _bubbles.size():
		var b: Vector2 = _bubbles[i]
		b.y -= delta * (0.15 + shake * 0.9) * (0.6 + 0.4 * sin(i * 3.1))
		if b.y < 0.0:
			b = Vector2(randf(), 1.0)
		_bubbles[i] = b
	queue_redraw()


func _outline() -> PackedVector2Array:
	# half a bottle silhouette (neck, shoulder, body), mirrored to a full outline
	var w := size.x
	var h := size.y
	var half := [Vector2(0.18, 0.0), Vector2(0.18, 0.12), Vector2(0.45, 0.25), Vector2(0.5, 0.33),
			Vector2(0.5, 0.95), Vector2(0.42, 1.0)]
	var pts := PackedVector2Array()
	for p in half:
		pts.append(Vector2(w * (0.5 + p.x), h * p.y))
	for i in range(half.size() - 1, -1, -1):
		pts.append(Vector2(w * (0.5 - half[i].x), h * half[i].y))
	return pts


func _draw() -> void:
	var w := size.x
	var h := size.y
	var outline := _outline()
	draw_colored_polygon(outline, Color(1, 1, 1, 0.35))
	# the soda: clip the fill to the bottle by intersecting with a rectangle
	var level := h * (1.0 - clampf(value, 0.0, 1.0) * 0.97)
	var col := UiTheme.YELLOW.lerp(UiTheme.ORANGE, clampf(value * 1.6, 0, 1))
	col = col.lerp(UiTheme.RED, clampf((value - 0.7) * 3.3, 0, 1))
	var wave := PackedVector2Array()
	for i in 13:
		var x := w * i / 12.0
		wave.append(Vector2(x, level + sin(_t * 9.0 + i * 0.9) * (3.0 + shake * 8.0)))
	wave.append(Vector2(w, h + 2))
	wave.append(Vector2(0, h + 2))
	var fill := Geometry2D.intersect_polygons(outline, wave)
	for poly in fill:
		draw_colored_polygon(poly, col)
	for b in _bubbles:
		var p := Vector2(w * (0.25 + b.x * 0.5), h * (0.35 + b.y * 0.62))
		if p.y > level + 6:
			draw_circle(p, 5.0 + 3.0 * b.x, Color(1, 1, 1, 0.75))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, UiTheme.DEEP, 8.0, true)
	# cap
	draw_rect(Rect2(w * 0.3, -h * 0.05, w * 0.4, h * 0.06), UiTheme.RED)
	draw_rect(Rect2(w * 0.3, -h * 0.05, w * 0.4, h * 0.06), UiTheme.DEEP, false, 6.0)
