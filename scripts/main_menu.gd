extends Control
## 메인 메뉴: 게임 시작, 설정(마스터/SFX 음량)

const GAMES := [
	{"id": "g2048", "name": "2048", "scene": "res://scenes/game.tscn"},
	{"id": "suika", "name": "Suika", "scene": "res://scenes/suika.tscn"},
	{"id": "surv", "name": "Survivor", "scene": "res://scenes/charselect.tscn"},
	{"id": "flight", "name": "Flight", "scene": "res://scenes/flappy.tscn"},
	{"id": "tetris", "name": "Tetris", "scene": "res://scenes/tetris.tscn"},
	{"id": "shmup", "name": "Shooter", "scene": "res://scenes/shmup.tscn"},
	{"id": "breakout", "name": "Breakout", "scene": "res://scenes/breakout.tscn"},
	{"id": "snake", "name": "Snake", "scene": "res://scenes/snake.tscn"},
	{"id": "mines", "name": "Minesweeper", "scene": "res://scenes/mines3d.tscn"},
	{"id": "stack", "name": "Stack", "scene": "res://scenes/stack.tscn"},
]

@onready var start_btn: Button = $Center/VBox/StartButton
@onready var list_panel: PanelContainer = $GameListPanel
@onready var grid: GridContainer = $GameListPanel/Margin/VBox/Scroll/GridCenter/Grid
@onready var list_back_btn: Button = $GameListPanel/Margin/VBox/ListBackButton
@onready var settings_btn: Button = $Center/VBox/SettingsButton
@onready var score_btn: Button = $Center/VBox/ScoreButton
@onready var score_panel: PanelContainer = $ScorePanel
@onready var score_vbox: VBoxContainer = $ScorePanel/Margin/VBox/Scroll/ScoreVBox
@onready var score_back_btn: Button = $ScorePanel/Margin/VBox/ScoreBackButton
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var master_slider: HSlider = $SettingsPanel/Margin/VBox/MasterRow/MasterSlider
@onready var master_value: Label = $SettingsPanel/Margin/VBox/MasterRow/MasterValue
@onready var sfx_slider: HSlider = $SettingsPanel/Margin/VBox/SfxRow/SfxSlider
@onready var sfx_value: Label = $SettingsPanel/Margin/VBox/SfxRow/SfxValue
@onready var back_btn: Button = $SettingsPanel/Margin/VBox/BackButton
@onready var mobile_check: Button = $SettingsPanel/Margin/VBox/MobileCheck
@onready var key_btn: Button = $SettingsPanel/Margin/VBox/KeyButton
@onready var key_panel: PanelContainer = $KeyPanel
@onready var key_vbox: VBoxContainer = $KeyPanel/Margin/VBox/Scroll/KeyVBox
@onready var key_back_btn: Button = $KeyPanel/Margin/VBox/KeyBackButton
var _listening = null # [game, action, Button] or null
@onready var click_player: AudioStreamPlayer = $ClickPlayer

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene(self)
	master_slider.value = AudioSetup.get_vol("master", 100.0)
	sfx_slider.value = AudioSetup.get_vol("sfx", 100.0)
	_update_vol_labels()
	start_btn.pressed.connect(_on_select)
	_build_game_buttons()
	list_back_btn.pressed.connect(_on_list_back)
	settings_btn.pressed.connect(_on_settings)
	score_btn.pressed.connect(_on_score)
	score_back_btn.pressed.connect(_on_score_back)
	back_btn.pressed.connect(_on_back)
	key_btn.pressed.connect(_on_keys)
	key_back_btn.pressed.connect(_on_keys_back)
	mobile_check.button_pressed = AudioSetup.mobile_enabled()
	mobile_check.toggled.connect(_on_mobile_toggled)
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	# 버튼 핏: 설정 3종 동일 크기 → 키 설정 닫기·게임 선택 닫기도 동일 크기
	var trio_size := UISkin.fit_group([key_btn, mobile_check, back_btn], 64.0)
	key_back_btn.custom_minimum_size = trio_size
	key_back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	score_back_btn.custom_minimum_size = trio_size
	score_back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list_back_btn.custom_minimum_size = trio_size
	list_back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UISkin.fit_group([start_btn, settings_btn, score_btn], 78.0, 80.0)
	if UISkin.open_game_select:
		UISkin.open_game_select = false
		list_panel.visible = true
	start_btn.grab_focus()

func _click() -> void:
	click_player.play()

func _build_game_buttons() -> void:
	for g in GAMES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 180)
		b.text = str(g["name"])
		b.tooltip_text = str(g["name"])
		_fit_cell(b, str(g["name"]))
		UISkin.style_tile(b)
		grid.add_child(b)
		var scene: String = str(g["scene"])
		b.pressed.connect(_on_game.bind(scene))

func _on_game(scene: String) -> void:
	_click()
	get_tree().change_scene_to_file(scene)

const CELL_MAXW := 150.0

func _fit_cell(b: Button, label: String) -> void:
	# 한 줄에 들어가면 폰트만 줄이고, 그래도 안 되면 두 줄로 나눔
	if label == "Minesweeper":
		b.text = "Mine\nSweeper"
		b.add_theme_font_size_override("font_size", 30)
		return
	var font := ThemeDB.fallback_font
	var fs := 40 if label.length() <= 7 else 28
	while fs > 20:
		if font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x <= CELL_MAXW:
			break
		fs -= 2
	if fs <= 20 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x > CELL_MAXW:
		label = _split_two(label)
		fs = 30
		for part in label.split("\n"):
			while fs > 16 and font.get_string_size(part, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x > CELL_MAXW:
				fs -= 2
	b.text = label
	b.add_theme_font_size_override("font_size", fs)

func _split_two(s: String) -> String:
	if " " in s:
		var i := s.find(" ")
		return s.left(i) + "\n" + s.substr(i + 1).strip_edges()
	var mid := s.length() / 2
	var cut := mid
	# 대문자 경계 우선 (가운데에서 가장 가까운 곳)
	var best_d := 1 << 30
	for i in range(1, s.length()):
		var c := s[i]
		if c >= "A" and c <= "Z":
			var d := absi(i - mid)
			if d < best_d:
				best_d = d
				cut = i
	if best_d == (1 << 30):
		cut = mid
	return s.left(cut) + "\n" + s.substr(cut)

func _on_select() -> void:
	_click()
	list_panel.visible = true

func _on_list_back() -> void:
	_click()
	list_panel.visible = false

func _on_settings() -> void:
	_click()
	settings_panel.visible = true

const SCORE_ROWS := [
	["2048", "best", "pts"],
	["Suika", "best_suika", "pts"],
	["Survivor", "best_surv", "kills"],
	["Flight", "best_flight", "time"],
	["Tetris", "best_tetris", "pts"],
	["Shooter", "best_shmup", "pts"],
	["Breakout", "best_breakout", "pts"],
	["Snake", "best_snake", "pts"],
	["Minesweeper", "best_mines", "clock"],
	["Stack", "best_stack", "floor"],
]

func _fmt_score(kind: String, v: float) -> String:
	match kind:
		"time":
			return "-" if v < 0.0 else "%.1f초" % v
		"clock":
			return "-" if v < 0.0 else "%d:%02d" % [int(v) / 60, int(v) % 60]
		"kills":
			return "%d킬" % int(v)
		"floor":
			return "%d층" % int(v)
		_:
			return "%d점" % int(v)

func _on_score() -> void:
	_click()
	for c in score_vbox.get_children():
		c.queue_free()
	var cfg := ConfigFile.new()
	cfg.load("user://g2048.cfg")
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	score_vbox.add_child(spacer)
	for r in SCORE_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := Label.new()
		lab.text = str(r[0])
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_font_size_override("font_size", 20)
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.clip_text = true
		row.add_child(lab)
		var val := Label.new()
		val.text = _fmt_score(str(r[2]), float(cfg.get_value("game", str(r[1]), -1.0 if str(r[2]) == "time" or str(r[2]) == "clock" else 0.0)))
		val.add_theme_font_size_override("font_size", 20)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		score_vbox.add_child(row)
	score_panel.visible = true

func _on_score_back() -> void:
	_click()
	score_panel.visible = false

func _on_back() -> void:
	_click()
	settings_panel.visible = false

func _on_keys() -> void:
	_click()
	_build_key_rows()
	key_panel.visible = true

func _on_keys_back() -> void:
	_click()
	_listening = null
	key_panel.visible = false

func _build_key_rows() -> void:
	for c in key_vbox.get_children():
		c.queue_free()
	for g in Controls.GAMES:
		var gid := str(g["id"])
		var head := Label.new()
		head.text = "〈 " + str(g["label"]) + " 〉"
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 22)
		key_vbox.add_child(head)
		for a in Controls.ACTIONS[gid]:
			var aid := str(a[0])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var lab := Label.new()
			lab.text = str(a[1])
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.add_theme_font_size_override("font_size", 17)
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lab.clip_text = true
			row.add_child(lab)
			var b := Button.new()
			b.custom_minimum_size = Vector2(130, 48)
			b.text = Controls.names(gid, aid)
			b.add_theme_font_size_override("font_size", 19)
			UISkin.style_tile(b, 8.0)
			b.pressed.connect(_on_remap.bind(gid, aid, b))
			row.add_child(b)
			key_vbox.add_child(row)

func _on_remap(gid: String, aid: String, b: Button) -> void:
	_listening = [gid, aid, b]
	b.text = "..."

func _unhandled_key_input(event: InputEvent) -> void:
	if _listening != null and event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.physical_keycode == KEY_ESCAPE:
			_listening[2].text = Controls.names(str(_listening[0]), str(_listening[1]))
			_listening = null
			return
		Controls.set_keys(str(_listening[0]), str(_listening[1]), [int(k.physical_keycode)])
		_listening[2].text = Controls.names(str(_listening[0]), str(_listening[1]))
		_listening = null
		return
	if settings_panel.visible or list_panel.visible:
		return
	if event is InputEventKey:
		var k2 := event as InputEventKey
		if k2.pressed and not k2.echo and (k2.physical_keycode == KEY_ENTER or k2.physical_keycode == KEY_KP_ENTER or k2.physical_keycode == KEY_SPACE):
			_on_select()

func _on_mobile_toggled(v: bool) -> void:
	AudioSetup.set_mobile(v)
	_click()

func _on_master_changed(v: float) -> void:
	AudioSetup.set_vol("master", v)
	_update_vol_labels()

func _on_sfx_changed(v: float) -> void:
	AudioSetup.set_vol("sfx", v)
	_update_vol_labels()
	_click() # 변경 즉시 확인음

func _update_vol_labels() -> void:
	master_value.text = "%d" % int(master_slider.value)
	sfx_value.text = "%d" % int(sfx_slider.value)
