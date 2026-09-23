extends Node3D
## 3D 지렁이: 바닥 12x12 그리드, 사과 먹으면 +1칸·가속. 고정 카메라(방향 혼동 방지).

const COLS := 12
const ROWS := 12
const SAVE_PATH := "user://g2048.cfg"

var snake: Array = [] # Vector2i head-first
var dir := Vector2i(0, -1)
var queued: Array = []
var apple := Vector2i(-1, -1)
var golden := false
var grow_pending := 0
var score := 0
var best := 0
var over := false
var interval := 0.22
var acc := 0.0
var last_sfx := ""
var rng := RandomNumberGenerator.new()

var _body_node: Node3D
var _apple_node: Node3D
var _box_mesh: BoxMesh
var _mats := {}

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

static func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3((float(c.x) - 5.5), 0.35, (float(c.y) - 5.5))

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.92, 0.7, 0.92)
	_build_floor()
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
	snake = [Vector2i(6, 8), Vector2i(6, 9), Vector2i(6, 10)]
	dir = Vector2i(0, -1)
	queued.clear()
	grow_pending = 0
	score = 0
	over = false
	interval = 0.22
	acc = 0.0
	_spawn_apple()
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_body()
	_refresh_ui()

func _free_cells() -> Array:
	var occ := {}
	for c in snake:
		occ[c] = true
	var out := []
	for x in range(COLS):
		for y in range(ROWS):
			if not occ.has(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out

func _spawn_apple() -> void:
	var free := _free_cells()
	if free.is_empty():
		return
	apple = free[rng.randi_range(0, free.size() - 1)]
	golden = rng.randf() < 0.15
	_refresh_apple()

func queue_dir(d: Vector2i) -> void:
	if over or get_tree().paused:
		return
	var last: Vector2i = queued.back() if not queued.is_empty() else dir
	if d + last != Vector2i.ZERO:
		if queued.size() < 3:
			queued.append(d)

func _physics_process(delta: float) -> void:
	if over or get_tree().paused:
		return
	acc += delta
	while acc >= interval and not over:
		acc -= interval
		_step()

func _step() -> void:
	if not queued.is_empty():
		dir = queued.pop_front()
	var head: Vector2i = snake[0] + dir
	if head.x < 0 or head.x >= COLS or head.y < 0 or head.y >= ROWS or head in snake:
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

func _refresh_body() -> void:
	for c in _body_node.get_children():
		c.queue_free()
	for i in range(snake.size()):
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh
		mi.material_override = _mat_for("head" if i == 0 else "body")
		mi.position = cell_to_world(snake[i])
		_body_node.add_child(mi)
	# 머리 눈 (진행 방향)
	if not snake.is_empty():
		var fwd := Vector3(dir.x, 0, dir.y)
		for sx in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.11
			sm.height = 0.22
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(0.05, 0.05, 0.08)
			sm.material = em
			eye.mesh = sm
			var side := Vector3(-fwd.z, 0, fwd.x)
			eye.position = cell_to_world(snake[0]) + fwd * 0.35 + side * 0.2 * sx + Vector3(0, 0.25, 0)
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
	mi.position = cell_to_world(apple) + Vector3(0, 0.1, 0)
	_apple_node.add_child(mi)

func _build_floor() -> void:
	var mats := {}
	for k in ["a", "b"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.18, 0.26) if k == "a" else Color(0.2, 0.22, 0.32)
		m.roughness = 0.9
		mats[k] = m
	for x in range(COLS):
		for y in range(ROWS):
			var mi := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.98, 0.2, 0.98)
			b.material = mats["a" if (x + y) % 2 == 0 else "b"]
			mi.mesh = b
			mi.position = Vector3(float(x) - 5.5, -0.1, float(y) - 5.5)
			add_child(mi)
	# 유리 테두리
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.5, 0.55, 0.7)
	var hw := COLS * 0.5 + 0.05
	for spec in [
		[Vector3(0, 0.5, -hw), Vector3(COLS + 0.2, 1.0, 0.12)],
		[Vector3(0, 0.5, hw), Vector3(COLS + 0.2, 1.0, 0.12)],
		[Vector3(-hw, 0.5, 0), Vector3(0.12, 1.0, ROWS + 0.2)],
		[Vector3(hw, 0.5, 0), Vector3(0.12, 1.0, ROWS + 0.2)],
	]:
		var mi2 := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = spec[1]
		b2.material = edge
		mi2.mesh = b2
		mi2.position = spec[0]
		add_child(mi2)

# ---------- 입력/UI ----------

func _wire_mobile() -> void:
	var defs := {"MW": Vector2i(0, -1), "MA": Vector2i(-1, 0), "MS": Vector2i(0, 1), "MD": Vector2i(1, 0)}
	for n in defs.keys():
		var b: Button = mobile_pad.get_node_or_null(n) as Button
		if b != null:
			b.pressed.connect(queue_dir.bind(defs[n] as Vector2i))

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_W, KEY_UP:
			queue_dir(Vector2i(0, -1))
		KEY_S, KEY_DOWN:
			queue_dir(Vector2i(0, 1))
		KEY_A, KEY_LEFT:
			queue_dir(Vector2i(-1, 0))
		KEY_D, KEY_RIGHT:
			queue_dir(Vector2i(1, 0))
		KEY_R:
			restart()
		KEY_P:
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
