extends Node3D
## 3D 테트리스 (5x5x12): 중력 없이 상단 대기 → 위치 확정 후 하드드랍.
## 회전 6종: Q/E Yaw, W/S Pitch(X축), A/D Roll(Z축). 홀드(C), Space 하드드랍.

const W := 5
const D := 5
const H := 12
const SAVE_PATH := "user://g2048.cfg"

const PIECES := [
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)], "col": Color(0.2, 0.85, 0.9)}, # I
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)], "col": Color(0.95, 0.85, 0.25)}, # O
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(1, 0, 1)], "col": Color(0.65, 0.35, 0.9)}, # T
	{"cells": [Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)], "col": Color(0.3, 0.85, 0.35)}, # S
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(2, 0, 1)], "col": Color(0.9, 0.3, 0.3)}, # Z
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, 1)], "col": Color(0.95, 0.6, 0.2)}, # L
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(2, 0, 1)], "col": Color(0.3, 0.5, 0.95)}, # J
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1)], "col": Color(0.6, 0.6, 0.65)}, # Cube
	{"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)], "col": Color(0.95, 0.45, 0.75)}, # Corner
	{"cells": [Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 2, 0), Vector3i(0, 2, 1)], "col": Color(0.25, 0.75, 0.75)}, # Tower
]
const CLEAR_SCORE := [0, 100, 300, 600, 1000, 1500]
const KICKS := [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

var grid := {} # Vector3i -> int (piece idx)
var bag: Array = []
var cur_type := 0
var cur_cells: Array = []
var cur_pos := Vector3i.ZERO
var next_type := 0
var held := -1
var can_hold := true
var score := 0
var lines := 0
var best := 0
var over := false
var last_sfx := ""
var _last_locked: Array = []
var rng := RandomNumberGenerator.new()

var _mats := {}
var _active_node: Node3D
var _ghost_node: Node3D
var _locked_node: Node3D
var _next_node: Node3D
var _hold_node: Node3D
var _ghost_mat: StandardMaterial3D
var _box_mesh: BoxMesh

@onready var rig_yaw: Node3D = $CameraRig/Yaw
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var lines_label: Label = $UI/LinesLabel
@onready var hold_label: Label = $UI/HoldLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_move: AudioStreamPlayer = $SfxMove
@onready var sfx_rot: AudioStreamPlayer = $SfxRot
@onready var sfx_drop: AudioStreamPlayer = $SfxDrop
@onready var sfx_clear: AudioStreamPlayer = $SfxClear
@onready var sfx_hold: AudioStreamPlayer = $SfxHold
@onready var sfx_invalid: AudioStreamPlayer = $SfxInvalid
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(float(c.x) - 2.0, float(c.y) + 0.5, float(c.z) - 2.0)

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.94, 0.94, 0.94)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.25)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_active_node = Node3D.new()
	_active_node.name = "Active"
	add_child(_active_node)
	_ghost_node = Node3D.new()
	_ghost_node.name = "Ghost"
	add_child(_ghost_node)
	_locked_node = Node3D.new()
	_locked_node.name = "Locked"
	add_child(_locked_node)
	_next_node = Node3D.new()
	_next_node.position = Vector3(4.6, 10.5, 0)
	add_child(_next_node)
	_hold_node = Node3D.new()
	_hold_node.position = Vector3(-4.6, 10.5, 0)
	add_child(_hold_node)
	_label3d("다음", Vector3(4.6, 12.2, 0))
	_label3d("홀드(C)", Vector3(-4.6, 12.2, 0))
	_build_frame()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best_tetris", 0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func _label3d(t: String, pos: Vector3) -> void:
	var lab := Label3D.new()
	lab.text = t
	lab.font_size = 64
	lab.pixel_size = 0.01
	lab.position = pos
	add_child(lab)

func _mat_for(t: int) -> StandardMaterial3D:
	if not _mats.has(t):
		var m := StandardMaterial3D.new()
		m.albedo_color = PIECES[t]["col"]
		m.roughness = 0.5
		_mats[t] = m
	return _mats[t]

func _cell_box(parent: Node3D, c: Vector3i, t: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh
	mi.material_override = _mat_for(t)
	mi.position = cell_to_world(c)
	parent.add_child(mi)

func restart() -> void:
	grid.clear()
	bag.clear()
	held = -1
	can_hold = true
	score = 0
	lines = 0
	over = false
	_next_type()
	_spawn()
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_locked()
	_refresh_ui()

func _next_type() -> void:
	if bag.is_empty():
		bag = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
		bag.shuffle()
	next_type = bag.pop_back()

static func _normalize(cells: Array) -> Array:
	var mn := Vector3i(99, 99, 99)
	for c in cells:
		mn.x = mini(mn.x, c.x)
		mn.y = mini(mn.y, c.y)
		mn.z = mini(mn.z, c.z)
	var out := []
	for c in cells:
		out.append(c - mn)
	return out

func fits(cells: Array, pos: Vector3i) -> bool:
	for c in cells:
		var p: Vector3i = pos + c
		if p.x < 0 or p.x >= W or p.y < 0 or p.z < 0 or p.z >= D:
			return false
		if p.y >= H:
			return false
		if grid.has(p):
			return false
	return true

func _spawn() -> void:
	cur_type = next_type
	_next_type()
	cur_cells = _normalize((PIECES[cur_type]["cells"] as Array).duplicate())
	var maxv := Vector3i.ZERO
	for c in cur_cells:
		maxv.x = maxi(maxv.x, c.x)
		maxv.y = maxi(maxv.y, c.y)
		maxv.z = maxi(maxv.z, c.z)
	cur_pos = Vector3i((W - 1 - maxv.x) / 2, H - 1 - maxv.y, (D - 1 - maxv.z) / 2)
	can_hold = true
	if not fits(cur_cells, cur_pos):
		over = true
		_play_sfx("over", sfx_over, 1.0)
		msg_label.text = "막혔다! %d점 %d줄 (R: 재시작)" % [score, lines]
		msg_panel.visible = true
	_refresh_active()
	_refresh_previews()

func try_move(dx: int, dz: int) -> bool:
	if over or get_tree().paused:
		return false
	if fits(cur_cells, cur_pos + Vector3i(dx, 0, dz)):
		cur_pos += Vector3i(dx, 0, dz)
		_play_sfx("move", sfx_move, 1.0)
		_refresh_active()
		return true
	_play_sfx("invalid", sfx_invalid, 1.0)
	return false

static func rot_x(c: Vector3i, sign: int) -> Vector3i:
	return Vector3i(c.x, -c.z * sign, c.y * sign)

static func rot_y(c: Vector3i, sign: int) -> Vector3i:
	return Vector3i(c.z * sign, c.y, -c.x * sign)

static func rot_z(c: Vector3i, sign: int) -> Vector3i:
	return Vector3i(-c.y * sign, c.x * sign, c.z)

func try_rotate(kind: String) -> bool:
	if over or get_tree().paused:
		return false
	var rotated := []
	for c in cur_cells:
		match kind:
			"yaw+":
				rotated.append(rot_y(c, 1))
			"yaw-":
				rotated.append(rot_y(c, -1))
			"pitch+":
				rotated.append(rot_x(c, 1))
			"pitch-":
				rotated.append(rot_x(c, -1))
			"roll+":
				rotated.append(rot_z(c, 1))
			_:
				rotated.append(rot_z(c, -1))
	rotated = _normalize(rotated)
	for k in KICKS:
		if fits(rotated, cur_pos + k):
			cur_cells = rotated
			cur_pos += k
			_play_sfx("rot", sfx_rot, 1.1)
			_refresh_active()
			return true
	_play_sfx("invalid", sfx_invalid, 1.0)
	return false

func hard_drop() -> void:
	if over or get_tree().paused:
		return
	while fits(cur_cells, cur_pos + Vector3i(0, -1, 0)):
		cur_pos += Vector3i(0, -1, 0)
	_lock()

func ghost_y() -> int:
	var y := cur_pos.y
	while fits(cur_cells, Vector3i(cur_pos.x, y - 1, cur_pos.z)):
		y -= 1
	return y

func hold_piece() -> void:
	if over or get_tree().paused or not can_hold:
		return
	can_hold = false
	if held < 0:
		held = cur_type
		_next_type()
		cur_type = next_type
		_next_type()
	else:
		var tmp := cur_type
		cur_type = held
		held = tmp
	cur_cells = _normalize((PIECES[cur_type]["cells"] as Array).duplicate())
	var maxv := Vector3i.ZERO
	for c in cur_cells:
		maxv.x = maxi(maxv.x, c.x)
		maxv.y = maxi(maxv.y, c.y)
		maxv.z = maxi(maxv.z, c.z)
	cur_pos = Vector3i((W - 1 - maxv.x) / 2, H - 1 - maxv.y, (D - 1 - maxv.z) / 2)
	_play_sfx("hold", sfx_hold, 1.2)
	if not fits(cur_cells, cur_pos):
		over = true
		msg_label.text = "막혔다! %d점 %d줄 (R: 재시작)" % [score, lines]
		msg_panel.visible = true
	_refresh_active()
	_refresh_previews()

func _lock() -> void:
	_last_locked = []
	for c in cur_cells:
		grid[cur_pos + c] = cur_type
		_last_locked.append(cur_pos + c)
	_play_sfx("drop", sfx_drop, 1.0)
	var cleared := _clear_layers()
	if cleared > 0:
		lines += cleared
		score += CLEAR_SCORE[mini(cleared, 5)]
		_play_sfx("clear", sfx_clear, 1.0 + 0.1 * float(cleared))
		if score > best:
			best = score
			var cfg := ConfigFile.new()
			cfg.load(SAVE_PATH)
			cfg.set_value("game", "best_tetris", best)
			cfg.save(SAVE_PATH)
	_refresh_locked()
	_spawn()
	_refresh_ui()

func _clear_layers() -> int:
	var full := []
	for y in range(H):
		var n := 0
		for x in range(W):
			for z in range(D):
				if grid.has(Vector3i(x, y, z)):
					n += 1
		if n == W * D:
			full.append(y)
	if full.is_empty():
		return 0
	var ng := {}
	for p in grid.keys():
		if (p as Vector3i).y in full:
			continue
		var drop := 0
		for fy in full:
			if fy < (p as Vector3i).y:
				drop += 1
		ng[(p as Vector3i) + Vector3i(0, -drop, 0)] = grid[p]
	grid = ng
	return full.size()

# ---------- 렌더 ----------

func _refresh_locked() -> void:
	for c in _locked_node.get_children():
		c.queue_free()
	for p in grid.keys():
		_cell_box(_locked_node, p, int(grid[p]))

func _refresh_active() -> void:
	for c in _active_node.get_children():
		c.queue_free()
	for c in _ghost_node.get_children():
		c.queue_free()
	for c in cur_cells:
		_cell_box(_active_node, cur_pos + c, cur_type)
	var gy := ghost_y()
	for c in cur_cells:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh
		mi.material_override = _ghost_mat
		mi.position = cell_to_world(Vector3i(cur_pos.x, gy, cur_pos.z) + c)
		_ghost_node.add_child(mi)

func _refresh_previews() -> void:
	for n in [_next_node, _hold_node]:
		for c in (n as Node3D).get_children():
			if not (c is Label3D):
				c.queue_free()
	_preview_piece(_next_node, next_type)
	if held >= 0:
		_preview_piece(_hold_node, held)

func _preview_piece(holder: Node3D, t: int) -> void:
	var cells: Array = _normalize((PIECES[t]["cells"] as Array).duplicate())
	var ctr := Vector3.ZERO
	for c in cells:
		ctr += Vector3(c)
	ctr /= float(cells.size())
	for c in cells:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh
		mi.material_override = _mat_for(t)
		mi.position = (Vector3(c) - ctr) * 0.9
		holder.add_child(mi)

func _build_frame() -> void:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.75, 1.0, 0.1)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.5, 0.55, 0.7)
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.16, 0.17, 0.24)
	_solid(Vector3(0, -0.25, 0), Vector3(6.0, 0.5, 6.0), floor_m)
	var hw := W * 0.5 + 0.05
	var hd := D * 0.5 + 0.05
	_solid(Vector3(0, H * 0.5, -hd), Vector3(W + 0.2, H, 0.1), glass)
	_solid(Vector3(0, H * 0.5, hd), Vector3(W + 0.2, H, 0.1), glass)
	_solid(Vector3(-hw, H * 0.5, 0), Vector3(0.1, H, D + 0.2), glass)
	_solid(Vector3(hw, H * 0.5, 0), Vector3(0.1, H, D + 0.2), glass)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_solid(Vector3(sx * hw, H * 0.5, sz * hd), Vector3(0.14, H, 0.14), edge)

func _solid(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	add_child(mi)

# ---------- 입력/UI ----------

func _cam_snapped() -> Basis:
	var yaw: float = (rig_yaw as Node3D).rotation.y
	return Basis(Vector3.UP, roundf(yaw / (PI * 0.5)) * (PI * 0.5))

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := int(k.physical_keycode)
	if code in Controls.keys_for("tetris", "drop"):
		hard_drop()
		return
	if code in Controls.keys_for("tetris", "hold"):
		hold_piece()
		return
	if code in Controls.keys_for("global", "restart"):
		restart()
		return
	if code in Controls.keys_for("global", "pause"):
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
		return
	for r in [["yawp", "yaw+"], ["yawm", "yaw-"], ["pitchp", "pitch-"], ["pitchm", "pitch+"], ["rollp", "roll+"], ["rollm", "roll-"]]:
		if code in Controls.keys_for("tetris", str(r[0])):
			try_rotate(str(r[1]))
			return
	var mv := Vector3.ZERO
	if code in Controls.keys_for("tetris", "up"):
		mv = Vector3(0, 0, -1)
	elif code in Controls.keys_for("tetris", "down"):
		mv = Vector3(0, 0, 1)
	elif code in Controls.keys_for("tetris", "left"):
		mv = Vector3(-1, 0, 0)
	elif code in Controls.keys_for("tetris", "right"):
		mv = Vector3(1, 0, 0)
	else:
		return
	var b := _cam_snapped() * mv
	try_move(int(roundf(b.x)), int(roundf(b.z)))

func _wire_mobile() -> void:
	var moves := {"MUp": [0, -1], "MDown": [0, 1], "MLeft": [-1, 0], "MRight": [1, 0]}
	for n in moves.keys():
		var b: Button = mobile_pad.get_node_or_null(n) as Button
		if b != null:
			var d: Array = moves[n]
			b.pressed.connect(_mobile_move.bind(int(d[0]), int(d[1])))
	for n in ["MDrop", "MHold", "MRy", "MRx", "MRz"]:
		var b2: Button = mobile_pad.get_node_or_null(n) as Button
		if b2 == null:
			continue
		match n:
			"MDrop":
				b2.pressed.connect(hard_drop)
			"MHold":
				b2.pressed.connect(hold_piece)
			"MRy":
				b2.pressed.connect(try_rotate.bind("yaw+"))
			"MRx":
				b2.pressed.connect(try_rotate.bind("pitch-"))
			"MRz":
				b2.pressed.connect(try_rotate.bind("roll+"))

func _mobile_move(dx: int, dz: int) -> void:
	var b := _cam_snapped() * Vector3(dx, 0, dz)
	try_move(int(roundf(b.x)), int(roundf(b.z)))

func pause_game() -> void:
	if over:
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
	score_label.text = "점수: %d" % score
	best_label.text = "최고: %d" % best
	lines_label.text = "%d줄" % lines
	hold_label.text = "홀드: 없음" if held < 0 else "홀드 있음"
