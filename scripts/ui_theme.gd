class_name UiTheme
extends RefCounted
## One place for every size and colour in the interface. The look is a soda can:
## cherry red, fizz yellow, cream, chunky rounded type with a dark outline, and pill buttons
## with a thick bottom edge so they look pressable. The screen is 720 wide.

const RED := Color("e3262c")
const ORANGE := Color("ff8a1f")
const YELLOW := Color("ffc428")
const CREAM := Color("fff6e6")
const DEEP := Color("5a0d16")       # outlines and dark text
const SKY := Color("2ea7e0")
const GREEN := Color("3fae49")
const WHITE := Color.WHITE

const PLAYER_COLORS := [Color("e3262c"), Color("2e7de0"), Color("3fae49"), Color("f2b01e"),
		Color("9b4fd6"), Color("ff7a1f")]

const BODY := 38
const BUTTON := 58
const HEADING := 64
const HUGE := 150
const BUTTON_H := 128
const OUTLINE := 12

static var font: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = BODY
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_outline_color", "Label", DEEP)
	t.set_constant("outline_size", "Label", 10)
	t.set_constant("shadow_offset_y", "Label", 5)
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_color("font_shadow_color", "Label", Color(DEEP, 0.55))
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(s, "Button", pill(YELLOW, s))
	t.set_font_size("font_size", "Button", BUTTON)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", DEEP)
	t.set_stylebox("panel", "PanelContainer", card(CREAM, RED))
	return t


static func pill(col: Color, state := "normal") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col.lightened(0.12) if state == "hover" else col
	s.set_corner_radius_all(64)
	s.border_color = col.darkened(0.45)
	s.set_border_width_all(5)
	s.border_width_bottom = 5 if state == "pressed" else 14
	s.content_margin_left = 40
	s.content_margin_right = 40
	s.content_margin_top = 14 if state != "pressed" else 22
	s.content_margin_bottom = 14
	if state == "focus":
		s.draw_center = false
		s.border_color = Color(0, 0, 0, 0)
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 6)
	return s


static func card(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(48)
	s.border_color = edge
	s.set_border_width_all(8)
	s.set_content_margin_all(36)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 10)
	return s


static func chip(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(40)
	s.border_color = DEEP
	s.set_border_width_all(5)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func label(text: String, size := BODY, col := WHITE, outline := OUTLINE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", outline)
	if outline == 0:
		# dark text on the cream cards: no drop shadow, which doubled small type (a hyphen read as "=")
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func button(text: String, col := YELLOW, size := BUTTON) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_H)
	b.add_theme_font_size_override("font_size", size)
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, pill(col, s))
	var txt := DEEP if col.get_luminance() > 0.55 else WHITE
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, txt)
	return b
