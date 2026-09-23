extends Node3D
## 3D 지뢰찾기 (5x5x5, 15개). 좌클릭 열기·우클릭 깃발, 0연쇄 개방. 궤도 카메라.

const N := 5
const MINES := 15
const SAVE_PATH := "user://g2048.cfg"

const NUM_COLS := {
	1: Color(0.3, 0.55, 1.0), 2: Color(0.3, 0.8, 0.35), 3: Color(1.0, 0.35, 0.3),
	4: Color(0.7, 0.4, 1.0), 5: Color(1.0, 0.65, 0.2),
}

var mines := {} # Vector3i -> true
var state := {} # Vector3i -> 0 скрыт/1 открыт/2 флаг (0=숨김,1=열림,2=깃발)
var started := false
var over := false
var won := false
var elapsed := 0.0
var best := -1.0
var flag_mode := false # 모바일용
var last_sfx := ""
var rng := RandomNumberGenerator.new()

var _box_mesh: BoxMesh
var _mats := {}
var _press_pos := Vector2.ZERO
var _pressing := false
var _touch_pos := Vector2.ZERO
var _touching := false

@onready var board_node: Node3D = $Board
@onready var rig: Node3D = $CameraRig
@onready var cam: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var mines_label: Label = $UI/MinesLabel
@onready var timer_label: Label = $UI/TimerLabel
@onready var best_label: Label = $UI/BestLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var flag_btn: Button = $UI/MobilePad/FlagButton
@onready var sfx_open: AudioStreamPlayer = $SfxOpen
@onready var sfx_flag: AudioStreamPlayer = $SfxFlag
@onready var sfx_boom: AudioStreamPlayer = $SfxBoom
@onready var sfx_win: AudioStreamPlayer = $SfxWin
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(float(c.x) - 2.0, float(c.y) - 2.0, float(c.z) - 2.0)

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.94, 0.94, 0.94)
	_build_frame()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = float(cfg.get_value("game", "best_mines", -1.0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	flag_btn.pressed.connect(_toggle_flag_mode)
	restart()

func _mat_for(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		if kind == "hidden":
			m.albedo_color = Color(0.35, 0.5, 0.75)
		elif kind == "flag":
			m.albedo_color = Color(0.95, 0.6, 0.2)
		elif kind == "mine":
			m.albedo_color = Color(0.9, 0.2, 0.2)
		else:
			m.albedo_color = Color(0.12, 0.13, 0.2)
		m.roughness = 0.6
		_mats[kind] = m
	return _mats[kind]

func restart() -> void:
	mines.clear()
	state.clear()
	started = false
	over = false
	won = false
	elapsed = 0.0
	flag_mode = false
	_update_flag_btn()
	var all := []
	for x in range(N):
		for y in range(N):
			for z in range(N):
				var c := Vector3i(x, y, z)
				state[c] = 0
				all.append(c)
	all.shuffle()
	for i in range(MINES):
		mines[all[i]] = true
	_render_all()
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_ui()

func _neighbors(c: Vector3i) -> Array:
	var out := []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var n := c + Vector3i(dx, dy, dz)
				if n.x >= 0 and n.x < N and n.y >= 0 and n.y < N and n.z >= 0 and n.z < N:
					out.append(n)
	return out

func _count(c: Vector3i) -> int:
	var n := 0
	for nb in _neighbors(c):
		if mines.has(nb):
			n += 1
	return n

func reveal(c: Vector3i) -> void:
	if over or won or get_tree().paused:
		return
	if int(state.get(c, 1)) != 0:
		return
	if not started:
		started = true
		if mines.has(c):
			mines.erase(c)
			while true:
				var nc := Vector3i(rng.randi_range(0, N - 1), rng.randi_range(0, N - 1), rng.randi_range(0, N - 1))
				if nc != c and not mines.has(nc):
					mines[nc] = true
					break
	if mines.has(c):
		state[c] = 1
		_render_all()
		_game_over()
		return
	_play_sfx("open", sfx_open, 1.0)
	_flood(c)
	_render_all()
	if _revealed_count() == N * N * N - MINES:
		won = true
		_play_sfx("win", sfx_win, 1.0)
		if best < 0.0 or elapsed < best:
			best = elapsed
			var cfg := ConfigFile.new()
			cfg.load(SAVE_PATH)
			cfg.set_value("game", "best_mines", best)
			cfg.save(SAVE_PATH)
		msg_label.text = "클리어! %s (R: 재시작)" % _fmt_time(elapsed)
		msg_panel.visible = true
	_refresh_ui()

func _flood(start: Vector3i) -> void:
	var stack := [start]
	while not stack.is_empty():
		var c: Vector3i = stack.pop_back()
		if int(state.get(c, 1)) != 0:
			continue
		state[c] = 1
		if _count(c) == 0:
			for nb in _neighbors(c):
				if int(state.get(nb, 1)) == 0:
					stack.append(nb)

func toggle_flag(c: Vector3i) -> void:
	if over or won or get_tree().paused:
		return
	if int(state.get(c, 1)) == 0:
		state[c] = 2
		_play_sfx("flag", sfx_flag, 1.0)
		_render_all()
	elif int(state.get(c, 1)) == 2:
		state[c] = 0
		_play_sfx("flag", sfx_flag, 0.8)
		_render_all()
	_refresh_ui()

func _revealed_count() -> int:
	var n := 0
	for c in state.keys():
		if int(state[c]) == 1 and not mines.has(c):
			n += 1
	return n

func _flag_count() -> int:
	var n := 0
	for c in state.keys():
		if int(state[c]) == 2:
			n += 1
	return n

func _game_over() -> void:
	over = true
	_play_sfx("boom", sfx_boom, 1.0)
	for m in mines.keys():
		state[m] = 1
	_render_all()
	msg_label.text = "펑! (R: 재시작)"
	msg_panel.visible = true
	_refresh_ui()

func _toggle_flag_mode() -> void:
	flag_mode = not flag_mode
	_update_flag_btn()

func _update_flag_btn() -> void:
	flag_btn.text = "깃발: 켬" if flag_mode else "깃발: 끔"

# ---------- 렌더 ----------

func _render_all() -> void:
	for c in board_node.get_children():
		c.queue_free()
	for x in range(N):
		for y in range(N):
			for z in range(N):
				_render_cell(Vector3i(x, y, z))

func _render_cell(c: Vector3i) -> void:
	var st := int(state.get(c, 0))
	if st == 1 and not mines.has(c):
		# 열린 칸은 박스 없이 숫자만 (뒤쪽 클릭이 통과함)
		if _count(c) > 0:
			var mi := MeshInstance3D.new()
			mi.mesh = _box_mesh
			mi.visible = false
			_add_mark(mi, str(_count(c)), NUM_COLS.get(_count(c), Color.WHITE))
			mi.position = cell_to_world(c)
			board_node.add_child(mi)
		return
	var mi2 := MeshInstance3D.new()
	mi2.mesh = _box_mesh
	if st == 0:
		mi2.material_override = _mat_for("hidden")
	elif st == 2:
		mi2.material_override = _mat_for("flag")
	else:
		mi2.material_override = _mat_for("mine")
		_add_mark(mi2, "X", Color.WHITE)
	mi2.position = cell_to_world(c)
	board_node.add_child(mi2)

func _add_mark(mi: MeshInstance3D, t: String, col: Color) -> void:
	var lab := Label3D.new()
	lab.text = t
	lab.font_size = 96
	lab.pixel_size = 0.006
	lab.modulate = col
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mi.add_child(lab)

func _build_frame() -> void:
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.5, 0.55, 0.7)
	var h := N * 0.5 + 0.07
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_bar(Vector3(sx * h, 0, sy * h), Vector3(0.09, N + 0.18, 0.09), edge)
			_bar(Vector3(sx * h, sy * h, 0), Vector3(0.09, 0.09, N + 0.18), edge)
			_bar(Vector3(0, sx * h, sy * h), Vector3(N + 0.18, 0.09, 0.09), edge)

func _bar(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	add_child(mi)

# ---------- 입력 ----------

func _ray_cell(screen_pos: Vector2) -> Variant:
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var best_t := INF
	var best = null
	for x in range(N):
		for y in range(N):
			for z in range(N):
				var c := Vector3i(x, y, z)
				if int(state.get(c, 0)) == 1:
					continue # 열린 칸은 클릭 통과
				var p := cell_to_world(c)
				var t := _ray_box(origin, dir, p, 0.47)
				if t > 0.0 and t < best_t:
					best_t = t
					best = c
	return best

func _ray_box(o: Vector3, d: Vector3, center: Vector3, half: float) -> float:
	var tmin := 0.0
	var tmax := INF
	for ax in range(3):
		var oo: float = o[ax]
		var dd: float = d[ax]
		var cc: float = center[ax]
		if absf(dd) < 0.00001:
			if oo < cc - half or oo > cc + half:
				return -1.0
		else:
			var t1 := (cc - half - oo) / dd
			var t2 := (cc + half - oo) / dd
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
			if tmin > tmax:
				return -1.0
	return tmin

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_pos = mb.position
			elif _pressing:
				_pressing = false
				if (mb.position - _press_pos).length() < 8.0:
					var c = _ray_cell(mb.position)
					if c != null:
						if flag_mode:
							toggle_flag(c)
						else:
							reveal(c)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var c2 = _ray_cell(mb.position)
			if c2 != null:
				toggle_flag(c2)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touching = true
			_touch_pos = st.position
		else:
			if _touching and (st.position - _touch_pos).length() < 12.0:
				var c3 = _ray_cell(st.position)
				if c3 != null:
					if flag_mode:
						toggle_flag(c3)
					else:
						reveal(c3)
			_touching = false

func _physics_process(delta: float) -> void:
	if started and not over and not won and not get_tree().paused:
		elapsed += delta
		_refresh_timer()

func _refresh_timer() -> void:
	timer_label.text = _fmt_time(elapsed)

func _fmt_time(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

func pause_game() -> void:
	if over or won:
		return
	get_tree().paused = true
	pause_panel.visible = true

func resume_game() -> void:
	get_tree().paused = false
	pause_panel.visible = false

func _on_restart_button() -> void:
	_play_sfx("restart", sfx_restart, 1.0)
	restart()

func _on_menu_button() -> void:
	_play_sfx("restart", sfx_restart, 1.0)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _play_sfx(sfx_name: String, player_node: AudioStreamPlayer, pitch: float) -> void:
	last_sfx = sfx_name
	player_node.pitch_scale = pitch
	player_node.play()

func _refresh_ui() -> void:
	mines_label.text = "지뢰: %d" % (MINES - _flag_count())
	best_label.text = "최고: %s" % (_fmt_time(best) if best >= 0.0 else "-")
	_refresh_timer()
