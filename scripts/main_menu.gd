extends Control
## 메인 메뉴: 게임 시작, 설정(마스터/SFX 음량)

@onready var best_label: Label = $Center/VBox/BestLabel
@onready var start_btn: Button = $Center/VBox/StartButton
@onready var list_panel: PanelContainer = $GameListPanel
@onready var game_btn_2048: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtn2048
@onready var game_btn_suika: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnSuika
@onready var game_btn_surv: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnSurv
@onready var game_btn_flappy: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnFlappy
@onready var game_btn_tetris: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnTetris
@onready var game_btn_shmup: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnShmup
@onready var game_btn_breakout: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnBreakout
@onready var game_btn_snake: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnSnake
@onready var game_btn_mines: Button = $GameListPanel/VBox/GridCenter/Grid/GameBtnMines
@onready var list_back_btn: Button = $GameListPanel/VBox/ListBackButton
@onready var settings_btn: Button = $Center/VBox/SettingsButton
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var master_slider: HSlider = $SettingsPanel/Margin/VBox/MasterRow/MasterSlider
@onready var master_value: Label = $SettingsPanel/Margin/VBox/MasterRow/MasterValue
@onready var sfx_slider: HSlider = $SettingsPanel/Margin/VBox/SfxRow/SfxSlider
@onready var sfx_value: Label = $SettingsPanel/Margin/VBox/SfxRow/SfxValue
@onready var back_btn: Button = $SettingsPanel/Margin/VBox/BackButton
@onready var mobile_check: CheckButton = $SettingsPanel/Margin/VBox/MobileCheck
@onready var click_player: AudioStreamPlayer = $ClickPlayer

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene(self)
	var cfg := ConfigFile.new()
	var best := 0
	var best_suika := 0
	if cfg.load("user://g2048.cfg") == OK:
		best = int(cfg.get_value("game", "best", 0))
		best_suika = int(cfg.get_value("game", "best_suika", 0))
	best_label.text = "2048 최고: %d · 수박 최고: %d" % [best, best_suika]
	master_slider.value = AudioSetup.get_vol("master", 100.0)
	sfx_slider.value = AudioSetup.get_vol("sfx", 100.0)
	_update_vol_labels()
	start_btn.pressed.connect(_on_select)
	game_btn_2048.pressed.connect(_on_start)
	game_btn_suika.pressed.connect(_on_suika)
	game_btn_surv.pressed.connect(_on_surv)
	game_btn_flappy.pressed.connect(_on_flappy)
	game_btn_tetris.pressed.connect(_on_tetris)
	game_btn_shmup.pressed.connect(_on_shmup)
	game_btn_breakout.pressed.connect(_on_breakout)
	game_btn_snake.pressed.connect(_on_snake)
	game_btn_mines.pressed.connect(_on_mines)
	list_back_btn.pressed.connect(_on_list_back)
	settings_btn.pressed.connect(_on_settings)
	back_btn.pressed.connect(_on_back)
	mobile_check.button_pressed = AudioSetup.mobile_enabled()
	mobile_check.toggled.connect(_on_mobile_toggled)
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	start_btn.grab_focus()

func _click() -> void:
	click_player.play()

func _on_select() -> void:
	_click()
	list_panel.visible = true

func _on_list_back() -> void:
	_click()
	list_panel.visible = false

func _on_start() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_suika() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/suika.tscn")

func _on_surv() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/charselect.tscn")

func _on_flappy() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/flappy.tscn")

func _on_tetris() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/tetris.tscn")

func _on_shmup() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/shmup.tscn")

func _on_breakout() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/breakout.tscn")

func _on_snake() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/snake.tscn")

func _on_mines() -> void:
	_click()
	get_tree().change_scene_to_file("res://scenes/mines3d.tscn")

func _on_settings() -> void:
	_click()
	settings_panel.visible = true

func _on_back() -> void:
	_click()
	settings_panel.visible = false

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

func _unhandled_key_input(event: InputEvent) -> void:
	if settings_panel.visible or list_panel.visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_KP_ENTER or k.physical_keycode == KEY_SPACE):
			_on_select()
