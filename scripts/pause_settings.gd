class_name PauseSettings
extends PanelContainer
## 인게임 설정 패널: 볼륨 2종 + 모바일 모드 + 키 설정(공통 + 해당 게임만).
## 일시정지 상태에서 동작하므로 PROCESS_MODE_ALWAYS.

var _game := "global"
var _listening = null # [gid, aid, Button]
var _vbox: VBoxContainer
var _master_val: Label
var _sfx_val: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

func setup(game_id: String) -> void:
	_game = game_id
	UISkin.style_panel(self)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(_vbox)
	_add_slider("전체 음량", "master", "MasterSlider")
	_add_slider("효과음", "sfx", "SfxSlider")
	var mc := Button.new()
	mc.custom_minimum_size = Vector2(200, 54)
	mc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mc.add_theme_font_size_override("font_size", 20)
	mc.text = "모바일 모드"
	mc.toggle_mode = true
	UISkin.style_button(mc)
	mc.button_pressed = AudioSetup.mobile_enabled()
	mc.toggled.connect(_on_mobile_toggle.bind(mc))
	_vbox.add_child(mc)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_vbox.add_child(scroll)
	var kv := VBoxContainer.new()
	kv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kv.add_theme_constant_override("separation", 6)
	scroll.add_child(kv)
	for gid in (["global"] if _game == "global" else ["global", _game]):
		if not Controls.ACTIONS.has(gid):
			continue
		for a in Controls.ACTIONS[gid]:
			var aid := str(a[0])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var lab := Label.new()
			lab.text = str(a[1])
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.add_theme_font_size_override("font_size", 16)
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lab.clip_text = true
			row.add_child(lab)
			var b := Button.new()
			b.custom_minimum_size = Vector2(120, 40)
			b.text = Controls.names(gid, aid)
			b.add_theme_font_size_override("font_size", 17)
			UISkin.style_tile(b, 8.0)
			b.pressed.connect(_on_remap.bind(gid, aid, b))
			row.add_child(b)
			kv.add_child(row)
	var back := Button.new()
	back.text = "닫기"
	back.custom_minimum_size = Vector2(160, 54)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 20)
	UISkin.style_button(back)
	back.pressed.connect(func() -> void: visible = false)
	_vbox.add_child(back)

func _add_slider(label_text: String, kind: String, slider_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(90, 0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 18)
	row.add_child(lab)
	var sl := HSlider.new()
	sl.name = slider_name
	sl.custom_minimum_size = Vector2(160, 0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.max_value = 100.0
	sl.step = 1.0
	sl.value = AudioSetup.get_vol(kind, 100.0)
	sl.value_changed.connect(_on_vol.bind(kind))
	row.add_child(sl)
	UISkin.style_slider(sl)
	var val := Label.new()
	val.custom_minimum_size = Vector2(48, 0)
	val.add_theme_font_size_override("font_size", 18)
	val.text = "%d" % int(sl.value)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	if kind == "master":
		_master_val = val
	else:
		_sfx_val = val
	_vbox.add_child(row)

func _on_vol(v: float, kind: String) -> void:
	AudioSetup.set_vol(kind, v)
	if kind == "master":
		_master_val.text = "%d" % int(v)
	else:
		_sfx_val.text = "%d" % int(v)

func _on_mobile_toggle(v: bool, _mc: Button) -> void:
	AudioSetup.set_mobile(v)
	var mp := get_parent().get_node_or_null("MobilePad") as Control
	if mp != null:
		mp.visible = v

func _on_remap(gid: String, aid: String, b: Button) -> void:
	_listening = [gid, aid, b]
	b.text = "..."

func _unhandled_key_input(event: InputEvent) -> void:
	if _listening == null or not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.physical_keycode == KEY_ESCAPE:
			_listening[2].text = Controls.names(str(_listening[0]), str(_listening[1]))
		else:
			Controls.set_keys(str(_listening[0]), str(_listening[1]), [int(k.physical_keycode)])
			_listening[2].text = Controls.names(str(_listening[0]), str(_listening[1]))
		_listening = null
		get_viewport().set_input_as_handled()
