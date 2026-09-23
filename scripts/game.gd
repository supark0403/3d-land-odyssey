extends Node3D
## 3D 2048 게임 진행: 기준면(+Z 앞면) 고정, 방향키 상하좌우 + W안쪽 S바깥쪽 + A/D 좌우

# 기준면(+Z, 앞면) 고정 이동축
const KEY_DIRS := {
	KEY_UP: Vector3i(0, 1, 0), KEY_DOWN: Vector3i(0, -1, 0),
	KEY_LEFT: Vector3i(-1, 0, 0), KEY_RIGHT: Vector3i(1, 0, 0),
	KEY_A: Vector3i(-1, 0, 0), KEY_D: Vector3i(1, 0, 0),
	KEY_W: Vector3i(0, 0, -1), KEY_S: Vector3i(0, 0, 1),
}

const SAVE_PATH := "user://g2048.cfg"

var logic := G2048.new()
var best := 0
var over := false
var win_shown := false
var busy := false
var last_sfx := "" # 테스트용: 마지막 재생 효과음명

@onready var view: Node3D = $Board
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var sfx_move: AudioStreamPlayer = $SfxMove
@onready var sfx_merge: AudioStreamPlayer = $SfxMerge
@onready var sfx_win: AudioStreamPlayer = $SfxWin
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var sfx_invalid: AudioStreamPlayer = $SfxInvalid
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	_load_best()
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func _wire_mobile() -> void:
	var defs := {
		"MUp": Vector3i(0, 1, 0), "MDown": Vector3i(0, -1, 0),
		"MLeft": Vector3i(-1, 0, 0), "MRight": Vector3i(1, 0, 0),
		"MFront": Vector3i(0, 0, -1), "MBack": Vector3i(0, 0, 1),
	}
	for n in defs.keys():
		var b: Button = mobile_pad.get_node_or_null(n) as Button
		if b != null:
			b.pressed.connect(_do_move.bind(defs[n] as Vector3i))

func restart() -> void:
	logic = G2048.new() # _init에서 rng 자동 randomize
	logic.reset() # 빈 판 + 타일 2개
	over = false
	win_shown = false
	busy = false
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	view.sync_full(logic)
	view.show_face(Vector3i(0, 0, 1)) # 기준면 표시 고정
	_refresh_ui()

func _on_restart_button() -> void:
	_play_sfx("restart", sfx_restart, 1.0)
	restart()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_R:
		restart()
		return
	if k.physical_keycode == KEY_P:
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
		return
	if KEY_DIRS.has(k.physical_keycode):
		_do_move(KEY_DIRS[k.physical_keycode])

func pause_game() -> void:
	if over:
		return
	get_tree().paused = true
	pause_panel.visible = true

func resume_game() -> void:
	get_tree().paused = false
	pause_panel.visible = false

func _on_menu_button() -> void:
	_play_sfx("restart", sfx_restart, 1.0)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _do_move(d: Vector3i) -> void:
	if over or busy or get_tree().paused:
		return
	var r: Dictionary = logic.move(d)
	if bool(r["changed"]):
		busy = true
		_play_sfx("move", sfx_move, 1.0)
		await view.play_move(logic, r["movements"])
		logic.spawn_tile()
		# 새로 스폰된 타일 pop (logic에 있고 view에 없는 칸 탐색)
		_sync_new_tiles()
		busy = false
		if int(r["gained"]) > 0:
			_play_sfx("merge", sfx_merge, _merge_pitch(r["movements"]))
		if logic.score > best:
			best = logic.score
			_save_best()
		_refresh_ui()
		if logic.won and not win_shown:
			win_shown = true
			_play_sfx("win", sfx_win, 1.0)
			_show_msg("2048 완성! 계속 플레이 가능 (R: 재시작)")
	else:
		_play_sfx("invalid", sfx_invalid, 1.0)
	if not logic.can_move():
		over = true
		_play_sfx("over", sfx_over, 1.0)
		_show_msg("게임 오버! 점수 %d (R: 재시작)" % logic.score)

## 합체 중 최대값에 따라 피치 (4->1.0, 값이 2배마다 +0.06, 최대 1.5)
func _merge_pitch(movements: Array) -> float:
	var top := 4
	for m in movements:
		if bool(m["merged"]):
			top = maxi(top, int(m["value"]))
	return minf(1.5, 1.0 + 0.06 * log(float(top) / 4.0) / log(2.0))

func _play_sfx(sfx_name: String, player: AudioStreamPlayer, pitch: float) -> void:
	last_sfx = sfx_name
	player.pitch_scale = pitch
	player.play()

func _sync_new_tiles() -> void:
	var have := {}
	for k in view.tiles.keys():
		have[k] = true
	for i in range(logic.cells.size()):
		var v: int = logic.cells[i]
		if v == 0:
			continue
		var p := G2048.pos_of(i)
		if not have.has(p):
			view.spawn_pop(p, v)

func _show_msg(t: String) -> void:
	msg_label.text = t
	msg_panel.visible = true

func _refresh_ui() -> void:
	score_label.text = "점수: %d" % logic.score
	best_label.text = "최고: %d" % best

func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best", 0))

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.save(SAVE_PATH)
