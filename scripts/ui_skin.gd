class_name UISkin
extends RefCounted
## pixel 번들 공용 스킨: 기본 버튼 5상태 + 다이얼로그 패널

const BTN_IDLE := "res://assets/pxui/button_cyan_48x20_idle.png"
const BTN_HOVER := "res://assets/pxui/button_cyan_48x20_hover.png"
const BTN_PRESSED := "res://assets/pxui/button_cyan_48x20_pressed.png"
const BTN_FOCUS := "res://assets/pxui/button_cyan_48x20_focus.png"
const BTN_DISABLED := "res://assets/pxui/button_cyan_48x20_selected.png"
const PANEL_BG := "res://assets/pxui/panel_cyan_translucent.png"
const MARGIN := 16.0

static func _sb(path: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path) as Texture2D
	sb.texture_margin_left = MARGIN
	sb.texture_margin_right = MARGIN
	sb.texture_margin_top = MARGIN
	sb.texture_margin_bottom = MARGIN
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _sb(BTN_IDLE))
	b.add_theme_stylebox_override("hover", _sb(BTN_HOVER))
	b.add_theme_stylebox_override("pressed", _sb(BTN_PRESSED))
	b.add_theme_stylebox_override("focus", _sb(BTN_FOCUS))
	b.add_theme_stylebox_override("disabled", _sb(BTN_DISABLED))
	b.add_theme_color_override("font_color", Color(0.95, 0.99, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.75, 0.9, 0.95))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.65))

static func style_panel(p: PanelContainer) -> void:
	p.add_theme_stylebox_override("panel", _sb(PANEL_BG))

static func style_slider(s: HSlider) -> void:
	# 테마 그래픽 없이 코드로 직관적 슬라이더 (트랙 + 손잡이)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.18)
	bg.set_corner_radius_all(6)
	bg.content_margin_top = 7.0
	bg.content_margin_bottom = 7.0
	bg.content_margin_left = 10.0
	bg.content_margin_right = 10.0
	s.add_theme_stylebox_override("background", bg)
	var area := StyleBoxEmpty.new()
	s.add_theme_stylebox_override("grabber_area", area)
	s.add_theme_stylebox_override("grabber_area_highlight", area)
	s.add_theme_icon_override("grabber", _grab_tex(Color(0.35, 0.8, 0.9)))
	s.add_theme_icon_override("grabber_highlight", _grab_tex(Color(0.55, 0.95, 1.0)))
	s.add_theme_icon_override("grabber_disabled", _grab_tex(Color(0.4, 0.45, 0.5)))

static func _grab_tex(c: Color) -> GradientTexture2D:
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.12, 0.88, 1.0])
	gr.colors = PackedColorArray([Color(0.05, 0.06, 0.1), c, c, Color(0.05, 0.06, 0.1)])
	var t := GradientTexture2D.new()
	t.gradient = gr
	t.width = 30
	t.height = 44
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	return t

static func skin_scene(root: Node) -> void:
	for b in root.find_children("*", "Button", true, false):
		style_button(b as Button)
	for p in root.find_children("*", "PanelContainer", true, false):
		style_panel(p as PanelContainer)
	for s in root.find_children("*", "HSlider", true, false):
		style_slider(s as HSlider)
