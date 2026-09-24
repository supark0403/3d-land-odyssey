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

static func _sb(path: String, m := MARGIN) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path) as Texture2D
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
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
	# 트랙 + 손잡이 모두 패널 에셋 사용
	var bg := _sb(PANEL_BG, 4.0)
	bg.content_margin_top = 4.0
	bg.content_margin_bottom = 4.0
	s.add_theme_stylebox_override("background", bg)
	var area := StyleBoxEmpty.new()
	s.add_theme_stylebox_override("grabber_area", area)
	s.add_theme_stylebox_override("grabber_area_highlight", area)
	s.add_theme_icon_override("grabber", _tile_grab(Color(0.55, 0.95, 1.0)))
	s.add_theme_icon_override("grabber_highlight", _tile_grab(Color(0.75, 1.0, 1.0)))
	s.add_theme_icon_override("grabber_disabled", _tile_grab(Color(0.4, 0.45, 0.5)))

static var _grab_cache := {}

static func _tile_grab(edge: Color) -> ImageTexture:
	# 키 설정 타일 버튼을 정사각형 손잡이로: 속찬 사각 + 밝은 테두리
	var key := str(edge)
	if _grab_cache.has(key):
		return _grab_cache[key] as ImageTexture
	var s := 44
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.35, 0.42, 1.0))
	for y in range(s):
		for x in range(s):
			if x < 4 or y < 4 or x >= s - 4 or y >= s - 4:
				img.set_pixel(x, y, edge)
	_grab_cache[key] = ImageTexture.create_from_image(img)
	return _grab_cache[key] as ImageTexture

static func fit_group(btns: Array, h: float, pad := 44.0) -> Vector2:
	# 가장 긴 글자에 맞춰 동일 크기로: 반환된 크기를 다른 버튼에 재사용 가능
	var font := ThemeDB.fallback_font
	var w := 0.0
	for c in btns:
		var cc := c as Control
		var fs: int = cc.get_theme_font_size("font_size")
		if fs <= 0:
			fs = 16
		w = maxf(w, font.get_string_size(str(cc.get("text")), HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x)
	var size := Vector2(w + pad, h)
	for c in btns:
		var cc := c as Control
		cc.custom_minimum_size = size
		cc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return size

static func fit_pause(root: Node) -> void:
	build_pause(root)

static var open_game_select := false

const SCENE_GAME := {
	"game.tscn": "g2048",
	"suika.tscn": "suika",
	"survivors.tscn": "surv",
	"charselect.tscn": "surv",
	"flappy.tscn": "flight",
	"shmup.tscn": "shmup",
	"tetris.tscn": "tetris",
	"breakout.tscn": "breakout",
	"snake.tscn": "snake",
	"mines3d.tscn": "mines",
	"stack.tscn": "stack",
}

static func game_of(ui: Node) -> String:
	var cs := ui.get_tree().current_scene
	if cs != null and cs.scene_file_path != "":
		return str(SCENE_GAME.get(cs.scene_file_path.get_file(), "global"))
	return "global"

static func build_pause(ui: Node) -> void:
	# 일시정지 패널 2x2 등분: 계속하기|설정 / 다른 게임|메인 메뉴 (타이틀 제거)
	var panel := ui.get_node_or_null("PausePanel") as PanelContainer
	if panel == null:
		return
	var vbox := panel.get_node_or_null("VBox") as VBoxContainer
	if vbox == null:
		return # 이미 재구성됨
	var cont := vbox.get_node_or_null("ContinueButton") as Button
	var menub := vbox.get_node_or_null("MenuButton") as Button
	if cont == null or menub == null:
		return
	var pl := vbox.get_node_or_null("PauseLabel")
	if pl != null:
		pl.queue_free()
	panel.remove_child(vbox)
	# 배경 기준 균등 분할: 고정 패널 + 균등 마진 + 셀 가득 채움
	panel.offset_left = -200.0
	panel.offset_right = 200.0
	panel.offset_top = -130.0
	panel.offset_bottom = 130.0
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	margin.add_child(grid)
	vbox.remove_child(cont)
	vbox.remove_child(menub)
	vbox.queue_free()
	var setb := Button.new()
	setb.name = "SettingButton"
	setb.text = "설정"
	var otherb := Button.new()
	otherb.name = "OtherButton"
	otherb.text = "다른 게임"
	for b in [cont, setb, otherb, menub]:
		var bb := b as Button
		grid.add_child(bb)
		bb.add_theme_font_size_override("font_size", 22)
		style_button(bb)
	fit_group([cont, setb, otherb, menub], 64.0)
	for b in [cont, setb, otherb, menub]:
		# fit_group 뒤에 적용: 셀을 가득 채워 균등 분할
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(b as Button).size_flags_vertical = Control.SIZE_EXPAND_FILL
	setb.pressed.connect(_toggle_ps.bind(ui))
	otherb.pressed.connect(_to_select.bind(otherb))
	# 인게임 설정 패널 부착 (공통 + 해당 게임 키만)
	if ui.get_node_or_null("PauseSettings") == null:
		var ps := PauseSettings.new()
		ps.name = "PauseSettings"
		ps.process_mode = Node.PROCESS_MODE_ALWAYS
		ps.visible = false
		ui.add_child(ps)
		ps.setup(game_of(ui))

static func _toggle_ps(ui: Node) -> void:
	var ps := ui.get_node_or_null("PauseSettings")
	if ps != null:
		(ps as Control).visible = not (ps as Control).visible

static func _to_select(b: Button) -> void:
	open_game_select = true
	_to_menu(b)

static var _pause_tex: Texture2D = null

static func pause_glyph() -> Texture2D:
	if _pause_tex != null:
		return _pause_tex
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(11, 10, 10, 28), Color(1, 1, 1))
	img.fill_rect(Rect2i(27, 10, 10, 28), Color(1, 1, 1))
	_pause_tex = ImageTexture.create_from_image(img)
	return _pause_tex

static func style_pause(b: Button) -> void:
	b.text = ""
	b.tooltip_text = "일시정지"
	b.icon = pause_glyph()
	b.expand_icon = true
	# 위치는 씬 설정 유지, 크기는 정사각형으로 압축 (우상단 기준)
	b.offset_left = b.offset_right - 56.0
	b.offset_bottom = b.offset_top + 56.0
	b.custom_minimum_size = Vector2(56, 56)

static func style_tile(b: Button, m := MARGIN) -> void:
	# 게임 선택 셀: 버튼 에셋 대신 반투명 패널 에셋 사용
	var n := _sb(PANEL_BG, m)
	var h := _sb(PANEL_BG, m)
	h.modulate_color = Color(1.25, 1.25, 1.25)
	var p := _sb(PANEL_BG, m)
	p.modulate_color = Color(0.7, 0.75, 0.85)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_color_override("font_color", Color(0.95, 0.99, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.8, 0.9, 0.95))

static func ensure_over_menu(root: Node) -> void:
	# 모든 게임 오버 패널: 메시지 높임 + 버튼 핏 + 패널 확장
	for p in root.find_children("MsgPanel", "PanelContainer", true, false):
		var panel := p as PanelContainer
		var vbox := panel.get_node_or_null("VBox") as VBoxContainer
		if vbox == null:
			continue
		panel.offset_left = -230.0
		panel.offset_right = 230.0
		panel.offset_top = -125.0
		panel.offset_bottom = 125.0
		vbox.add_theme_constant_override("separation", 16)
		var msg := vbox.get_node_or_null("MsgLabel") as Label
		if msg != null:
			msg.custom_minimum_size = Vector2(0, 64)
			msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var restart := vbox.get_node_or_null("RestartButton") as Button
		if vbox.get_node_or_null("OverMenuButton") == null:
			var b := Button.new()
			b.name = "OverMenuButton"
			b.text = "메인 메뉴"
			b.add_theme_font_size_override("font_size", 20)
			vbox.add_child(b)
			style_button(b)
			b.pressed.connect(_to_menu.bind(b))
		var over := vbox.get_node_or_null("OverMenuButton") as Button
		if restart != null and over != null:
			fit_group([restart, over], 64.0, 36.0)

static func _to_menu(b: Button) -> void:
	var t := b.get_tree()
	if t != null:
		t.paused = false
		t.change_scene_to_file("res://scenes/main_menu.tscn")

static func skin_scene(root: Node) -> void:
	for b in root.find_children("*", "Button", true, false):
		style_button(b as Button)
		if (b as Button).name == "PauseButton":
			style_pause(b as Button)
	ensure_over_menu(root)
	fit_pause(root)
	for p in root.find_children("*", "PanelContainer", true, false):
		style_panel(p as PanelContainer)
	for s in root.find_children("*", "HSlider", true, false):
		style_slider(s as HSlider)
