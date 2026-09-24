extends Node3D
## 3D 지렁이 (9x9x9 큐브): 6방향 이동 + 머리 추적 TPS 카메라.
## 사과 +1칸·가속 (황금 +3). 반전 금지, 벽·자기충돌 사망.

const GS := 9
const SAVE_PATH := "user://g2048.cfg"

var snake: Array = [] # Vector3i head-first
var dir := Vector3i(0, 0, -1)
var queued: Array = []
var apple := Vector3i(-1, -1, -1)
var golden := false
var grow_pending := 0
var score := 0
var best := 0
var over := false
var interval := 0.22
var acc := 0.0
var last_sfx := ""
var rng := RandomNumberGenerator.new()
var _cam_flat := Vector3(0, 0, -1) # 카메라용 수평 헤딩 (수직 이동 때도 유지)

var _body_node: Node3D
var _apple_node: Node3D
var _box_mesh: BoxMesh
var _mats := {}

@onready var cam: Camera3D = $Camera3D
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var len_label: Label = $UI/LenLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_eat: AudioStreamPlayer = $SfxEat
@onready var sfx_gold: AudioStreamPlayer = $SfxGold
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c) - Vector3(4, 4, 4)

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.92, 0.92, 0.92)
	_build_cube()
	_body_node = Node3D.new()
	_body_node.name = "Body"
	add_child(_body_node)
	_apple_node = Node3D.new()
	_apple_node.name = "Apple"
	add_child(_apple_node)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best_snake", 0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func _mat_for(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		if kind == "head":
			m.albedo_color = Color(0.3, 0.9, 0.35)
		elif kind == "body":
			m.albedo_color = Color(0.25, 0.7, 0.3)
		elif kind == "apple":
			m.albedo_color = Color(0.95, 0.25, 0.25)
		else:
			m.albedo_color = Color(1.0, 0.85, 0.2)
		m.roughness = 0.5
		_mats[kind] = m
	return _mats[kind]

func restart() -> void:
	snake = [Vector3i(4, 4, 6), Vector3i(4, 4, 7), Vector3i(4, 4, 8)]
	dir = Vector3i(0, 0, -1)
	queued.clear()
	grow_pending = 0
	score = 0
	over = false
	interval = 0.22
	acc = 0.0
	_spawn_apple()
	_snap_camera()
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_body()
	_refresh_ui()

func _in_cube(c: Vector3i) -> bool:
	return c.x >= 0 and c.x < GS and c.y >= 0 and c.y < GS and c.z >= 0 and c.z < GS

func _free_cells() -> Array:
	var occ := {}
	for c in snake:
		occ[c] = true
	var out := []
	for x in range(GS):
		for y in range(GS):
			for z in range(GS):
				var c := Vector3i(x, y, z)
				if not occ.has(c):
					out.append(c)
	return out

func _spawn_apple() -> void:
	var free := _free_cells()
	if free.is_empty():
		return
	apple = free[rng.randi_range(0, free.size() - 1)]
	golden = rng.randf() < 0.15
	_refresh_apple()

func queue_dir(d: Vector3i) -> void:
	if over or get_tree().paused:
		return
	var last: Vector3i = queued.back() if not queued.is_empty() else dir
	if d + last != Vector3i.ZERO:
		if queued.size() < 3:
			queued.append(d)

## 화면 기준 조향 (sx:+오른쪽, sy:+아래): 카메라에 가장 맞는 수평/수직 방향으로 전환
func _steer(sx: float, sy: float) -> void:
	if over or get_tree().paused:
		return
	var r: Vector3 = cam.global_transform.basis.x
	var u: Vector3 = cam.global_transform.basis.y
	var wish: Vector3 = r * sx + u * -sy
	if wish.length() < 0.05:
		return
	wish = wish.normalized()
	var best := Vector3i.ZERO
	var best_s := 0.3
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if d == dir or d == -dir:
			continue
		var s: float = Vector3(d).dot(wish)
		if s > best_s:
			best_s = s
			best = d
	if best != Vector3i.ZERO:
		queue_dir(best)

func _physics_process(delta: float) -> void:
	if over or get_tree().paused:
		return
	if stick != null and stick.value.length() > 0.4:
		_steer(stick.value.x, stick.value.y)
	acc += delta
	while acc >= interval and not over:
		acc -= interval
		_step()
	_update_camera(delta)

func _step() -> void:
	if not queued.is_empty():
		dir = queued.pop_front()
	var head: Vector3i = snake[0] + dir
	if not _in_cube(head) or head in snake:
		_die()
		return
	snake.push_front(head)
	if head == apple:
		var g := 3 if golden else 1
		grow_pending += g
		score += 50 if golden else 10
		_play_sfx("gold" if golden else "eat", sfx_gold if golden else sfx_eat, 1.0)
		interval = maxf(0.08, interval * (0.94 if golden else 0.97))
		_spawn_apple()
	if grow_pending > 0:
		grow_pending -= 1
	else:
		snake.pop_back()
	_refresh_body()
	_refresh_ui()

func _die() -> void:
	over = true
	_play_sfx("over", sfx_over, 1.0)
	if score > best:
		best = score
		var cfg := ConfigFile.new()
		cfg.load(SAVE_PATH)
		cfg.set_value("game", "best_snake", best)
		cfg.save(SAVE_PATH)
	msg_label.text = "꼬였다! %d점 %d칸 (R: 재시작)" % [score, snake.size()]
	msg_panel.visible = true
	_refresh_ui()

func _heading() -> Vector3:
	return Vector3(dir)

func _snap_camera() -> void:
	_cam_flat = Vector3(dir.x, 0, dir.z)
	if _cam_flat.length() < 0.05:
		_cam_flat = Vector3(0, 0, -1)
	var hp := cell_to_world(snake[0])
	var h := _heading()
	# 수직 이동 때도 앞이 보이게: 올라가면 카메라는 밑으로, 내려가면 위로
	cam.position = hp - _cam_flat * 5.5 + Vector3(0, 2.2 - h.y * 3.0, 0)
	cam.look_at(hp + h * 2.5 + _cam_flat * 0.6)

func _update_camera(delta: float) -> void:
	if snake.is_empty():
		return
	var h := _heading()
	if absf(h.y) < 0.5 and h.length() > 0.05:
		_cam_flat = Vector3(h.x, 0, h.z).normalized()
	var hp := cell_to_world(snake[0])
	var want_pos := hp - _cam_flat * 5.5 + Vector3(0, 2.2 - h.y * 3.0, 0)
	var want_look := hp + h * 2.5 + _cam_flat * 0.6
	var k := 1.0 - exp(-6.0 * delta)
	cam.position = cam.position.lerp(want_pos, k)
	var cur_fwd := -cam.global_transform.basis.z
	var want_dir: Vector3 = (want_look - cam.position).normalized() if cam.position.distance_to(want_look) > 0.05 else cur_fwd
	var cur_look: Vector3 = cam.position + cur_fwd
	var look: Vector3 = cur_look.lerp(cam.position + want_dir * cur_look.distance_to(cam.position), k)
	if look.distance_to(cam.position) > 0.05:
		cam.look_at(look)

func _refresh_body() -> void:
	for c in _body_node.get_children():
		c.queue_free()
	var h := _heading()
	var side := h.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	for i in range(snake.size()):
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh
		mi.material_override = _mat_for("head" if i == 0 else "body")
		mi.position = cell_to_world(snake[i])
		_body_node.add_child(mi)
	if not snake.is_empty():
		var hp := cell_to_world(snake[0])
		for sx in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.11
			sm.height = 0.22
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(0.05, 0.05, 0.08)
			sm.material = em
			eye.mesh = sm
			eye.position = hp + h * 0.35 + side * 0.2 * sx + Vector3(0, 0.25, 0)
			_body_node.add_child(eye)

func _refresh_apple() -> void:
	for c in _apple_node.get_children():
		c.queue_free()
	if apple.x < 0:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42 if golden else 0.34
	sm.height = 0.84 if golden else 0.68
	sm.material = _mat_for("gold" if golden else "apple")
	mi.mesh = sm
	mi.position = cell_to_world(apple)
	_apple_node.add_child(mi)

func _build_cube() -> void:
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.5, 0.55, 0.7)
	var e := 4.5
	var t := 0.12
	for spec in [
		[Vector3(e, 0, e), Vector3(t, 9.2, t)], [Vector3(-e, 0, e), Vector3(t, 9.2, t)],
		[Vector3(e, 0, -e), Vector3(t, 9.2, t)], [Vector3(-e, 0, -e), Vector3(t, 9.2, t)],
		[Vector3(0, e, e), Vector3(9.2, t, t)], [Vector3(0, -e, e), Vector3(9.2, t, t)],
		[Vector3(0, e, -e), Vector3(9.2, t, t)], [Vector3(0, -e, -e), Vector3(9.2, t, t)],
		[Vector3(e, e, 0), Vector3(t, t, 9.2)], [Vector3(-e, e, 0), Vector3(t, t, 9.2)],
		[Vector3(e, -e, 0), Vector3(t, t, 9.2)], [Vector3(-e, -e, 0), Vector3(t, t, 9.2)],
	]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = spec[1]
		b.material = edge
		mi.mesh = b
		mi.position = spec[0]
		add_child(mi)

# ---------- 입력/UI ----------

var stick: VirtualStick

func _wire_mobile() -> void:
	stick = mobile_pad.get_node_or_null("Stick") as VirtualStick
	var bu: Button = mobile_pad.get_node_or_null("MUp") as Button
	if bu != null:
		bu.pressed.connect(queue_dir.bind(Vector3i(0, 1, 0)))
	var bd: Button = mobile_pad.get_node_or_null("MDown") as Button
	if bd != null:
		bd.pressed.connect(queue_dir.bind(Vector3i(0, -1, 0)))

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := int(k.physical_keycode)
	if code in Controls.keys_for("snake", "up"):
		_steer(0.0, -1.0)
	elif code in Controls.keys_for("snake", "down"):
		_steer(0.0, 1.0)
	elif code in Controls.keys_for("snake", "left"):
		_steer(-1.0, 0.0)
	elif code in Controls.keys_for("snake", "right"):
		_steer(1.0, 0.0)
	elif code in Controls.keys_for("snake", "altup"):
		queue_dir(Vector3i(0, 1, 0))
	elif code in Controls.keys_for("snake", "altdown"):
		queue_dir(Vector3i(0, -1, 0))
	elif code in Controls.keys_for("global", "restart"):
		restart()
	elif code in Controls.keys_for("global", "pause"):
		if get_tree().paused:
			resume_game()
		else:
			pause_game()

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
	len_label.text = "%d칸" % snake.size()
