extends Node3D
## 블록 스택: 옆에서 날아오는 블록을 타이밍 맞춰 쌓기. 삐져나온 부분은 잘려 떨어짐.
## 오차 ±0.18 이내면 퍼펙트(크기 유지), 2연속부터 0.3 회복. 빗나가면 게임 오버.

const BLOCK_H := 0.6
const START_SIZE := 3.0
const RANGE := 4.5
const PERFECT_TOL := 0.18
const SAVE_PATH := "user://g2048.cfg"

var level := 0 # 쌓은 층수
var size_x := START_SIZE
var size_z := START_SIZE
var top_x := 0.0
var top_z := 0.0
var combo := 0
var best := 0
var over := false
var last_sfx := ""
var rng := RandomNumberGenerator.new()

var move_axis := 0 # 0=X, 1=Z (층마다 교대)
var move_pos := 0.0
var move_dir := 1.0

var tower: Node3D
var mover: MeshInstance3D
var debris: Array = [] # {node, vel, t}
var _unit_box: BoxMesh
var _pal: Array = [] # 16색 팔레트

@onready var cam: Camera3D = $Camera3D
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var combo_label: Label = $UI/ComboLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_place: AudioStreamPlayer = $SfxPlace
@onready var sfx_perfect: AudioStreamPlayer = $SfxPerfect
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	for i in range(16):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(fmod(0.55 + float(i) * 0.0625, 1.0), 0.6, 0.95)
		m.roughness = 0.5
		_pal.append(m)
	tower = Node3D.new()
	tower.name = "Tower"
	add_child(tower)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best_stack", 0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	var md: Button = mobile_pad.get_node_or_null("MDrop") as Button
	if md != null:
		md.pressed.connect(drop)
	restart()

func _mat_for(lv: int) -> StandardMaterial3D:
	return _pal[lv % 16] as StandardMaterial3D

func _add_block(cx: float, cz: float, sx: float, sz: float, y: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_box
	mi.material_override = mat
	mi.position = Vector3(cx, y, cz)
	mi.scale = Vector3(sx, BLOCK_H, sz)
	tower.add_child(mi)
	return mi

func restart() -> void:
	for c in tower.get_children():
		c.queue_free()
	for d in debris:
		if is_instance_valid(d["node"]):
			(d["node"] as Node).queue_free()
	debris.clear()
	if is_instance_valid(mover):
		mover.queue_free()
	level = 0
	size_x = START_SIZE
	size_z = START_SIZE
	top_x = 0.0
	top_z = 0.0
	combo = 0
	over = false
	# 기반
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.25, 0.28, 0.35)
	base_mat.roughness = 0.7
	_add_block(0.0, 0.0, START_SIZE + 1.2, START_SIZE + 1.2, -BLOCK_H * 0.5, base_mat)
	_spawn_mover()
	_snap_camera()
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_ui()

func move_speed() -> float:
	return minf(3.0 + float(level) * 0.15, 8.5)

func _spawn_mover() -> void:
	move_axis = level % 2 # 0=X, 1=Z 교대
	var side := 1.0 if level % 4 < 2 else -1.0
	move_pos = -RANGE * side
	move_dir = side # 중앙을 향해 진입
	mover = MeshInstance3D.new()
	mover.mesh = _unit_box
	mover.material_override = _mat_for(level)
	tower.add_child(mover)
	_place_mover()

func _place_mover() -> void:
	var y := float(level) * BLOCK_H + BLOCK_H * 0.5
	if move_axis == 0:
		mover.position = Vector3(move_pos, y, top_z)
		mover.scale = Vector3(size_x, BLOCK_H, size_z)
	else:
		mover.position = Vector3(top_x, y, move_pos)
		mover.scale = Vector3(size_x, BLOCK_H, size_z)

func _physics_process(delta: float) -> void:
	if over or get_tree().paused:
		return
	move_pos += move_dir * move_speed() * delta
	if move_pos > RANGE:
		move_pos = RANGE
		move_dir = -1.0
	elif move_pos < -RANGE:
		move_pos = -RANGE
		move_dir = 1.0
	_place_mover()
	_update_debris(delta)
	_update_camera(delta)

func _update_debris(delta: float) -> void:
	var top_y := float(level) * BLOCK_H
	for i in range(debris.size() - 1, -1, -1):
		var d: Dictionary = debris[i]
		if not is_instance_valid(d["node"]):
			debris.remove_at(i)
			continue
		var node := d["node"] as Node3D
		var v := d["vel"] as Vector3
		v.y -= 18.0 * delta
		d["vel"] = v
		node.position += v * delta
		d["t"] = float(d["t"]) - delta
		if float(d["t"]) <= 0.0 or node.position.y < top_y - 10.0:
			node.queue_free()
			debris.remove_at(i)

func drop() -> void:
	if over or get_tree().paused:
		return
	var c0 := top_x if move_axis == 0 else top_z
	var s := size_x if move_axis == 0 else size_z
	var off := move_pos - c0
	if absf(off) <= PERFECT_TOL:
		# 퍼펙트: 크기 유지 + 2연속부터 회복
		combo += 1
		if combo >= 2:
			s = minf(s + 0.3, START_SIZE)
		_apply_size(s)
		_add_block(top_x, top_z, size_x, size_z, float(level) * BLOCK_H + BLOCK_H * 0.5, _mat_for(level))
		_play_sfx("perfect", sfx_perfect, minf(1.4, 1.0 + 0.02 * float(combo)))
	else:
		combo = 0
		var overlap := s - absf(off)
		if overlap <= 0.05:
			_miss()
			return
		# 잘린 조각은 잔해로
		var cx := c0 + off * 0.5
		var debris_c := c0 + signf(off) * (s * 0.5 + absf(off) * 0.5)
		_spawn_debris(debris_c, absf(off))
		if move_axis == 0:
			top_x = cx
			size_x = overlap
		else:
			top_z = cx
			size_z = overlap
		_add_block(top_x, top_z, size_x, size_z, float(level) * BLOCK_H + BLOCK_H * 0.5, _mat_for(level))
		_play_sfx("place", sfx_place, 1.0)
	level += 1
	mover.queue_free()
	_spawn_mover()
	_refresh_ui()

func _apply_size(s: float) -> void:
	if move_axis == 0:
		size_x = s
	else:
		size_z = s

func _spawn_debris(center_along: float, w: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_box
	mi.material_override = _mat_for(level)
	var y := float(level) * BLOCK_H + BLOCK_H * 0.5
	if move_axis == 0:
		mi.position = Vector3(center_along, y, top_z)
		mi.scale = Vector3(w, BLOCK_H, size_z)
		tower.add_child(mi)
		debris.append({"node": mi, "vel": Vector3(signf(move_dir) * move_speed() * 0.6, 1.0, 0), "t": 1.6})
	else:
		mi.position = Vector3(top_x, y, center_along)
		mi.scale = Vector3(size_x, BLOCK_H, w)
		tower.add_child(mi)
		debris.append({"node": mi, "vel": Vector3(0, 1.0, signf(move_dir) * move_speed() * 0.6), "t": 1.6})

func _miss() -> void:
	# 통째로 떨어뜨리고 게임 오버
	var mi := mover
	mover = null
	var v := Vector3(move_dir * move_speed() * 0.6, 1.0, 0) if move_axis == 0 else Vector3(0, 1.0, move_dir * move_speed() * 0.6)
	debris.append({"node": mi, "vel": v, "t": 1.6})
	over = true
	_play_sfx("over", sfx_over, 1.0)
	if level > best:
		best = level
		var cfg := ConfigFile.new()
		cfg.load(SAVE_PATH)
		cfg.set_value("game", "best_stack", best)
		cfg.save(SAVE_PATH)
	msg_label.text = "무너졌다! %d층 (R: 재시작)" % level
	msg_panel.visible = true
	_refresh_ui()

func _snap_camera() -> void:
	var top_y := 0.0
	cam.position = Vector3(7.0, top_y + 5.5, 7.0)
	cam.look_at(Vector3(0, top_y - 0.5, 0))

func _update_camera(delta: float) -> void:
	var top_y := float(level) * BLOCK_H
	var want_pos := Vector3(7.0, top_y + 5.5, 7.0)
	var want_look := Vector3(0, top_y - 0.5, 0)
	var k := 1.0 - exp(-4.0 * delta)
	cam.position = cam.position.lerp(want_pos, k)
	var cur_fwd := -cam.global_transform.basis.z
	var want_dir: Vector3 = (want_look - cam.position).normalized() if cam.position.distance_to(want_look) > 0.05 else cur_fwd
	var look: Vector3 = (cam.position + cur_fwd).lerp(cam.position + want_dir, k)
	if look.distance_to(cam.position) > 0.05:
		cam.look_at(look)

func signf(x: float) -> float:
	return 1.0 if x >= 0.0 else -1.0

# ---------- 입력/UI ----------

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := int(k.physical_keycode)
	if code in Controls.keys_for("stack", "drop"):
		drop()
	elif code in Controls.keys_for("global", "restart"):
		restart()
	elif code in Controls.keys_for("global", "pause"):
		if get_tree().paused:
			resume_game()
		else:
			pause_game()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			drop()

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
	score_label.text = "%d층" % level
	best_label.text = "최고: %d층" % best
	if combo >= 2:
		combo_label.text = "PERFECT x%d" % combo
		combo_label.visible = true
	else:
		combo_label.visible = false
