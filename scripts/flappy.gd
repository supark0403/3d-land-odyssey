extends Node3D
## 비행 시뮬레이터: WASD로 상하좌우, 링 30개 통과하면 클리어(타임 기록).
## 링은 앞에서 오고, 카메라는 TPS 추적. 물리 없이 키네마틱.

const SPEED := 8.0
const SCROLL := 9.0
const RINGS_GOAL := 30
const SAVE_PATH := "user://g2048.cfg"
# 모델 정면 +X 가정
const PLANE_YAW := 0.0

var rings_done := 0
var best_time := -1.0
var t := 0.0
var over := false
var vy := 0.0
var vz := 0.0
var touch_move := Vector2.ZERO
var stick: VirtualStick
var last_sfx := ""
var rng := RandomNumberGenerator.new()

var plane: Node3D
var plane_model: Node3D
var rings: Array = [] # {node, passed}
var _spawn_t := 0.0
var _mat_ball: StandardMaterial3D
var _mat_done: StandardMaterial3D
var stars: Array = []
const BALL_R := 1.5

@onready var cam: Camera3D = $Camera3D
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var timer_label: Label = $UI/TimerLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_ring: AudioStreamPlayer = $SfxRing
@onready var sfx_clear: AudioStreamPlayer = $SfxClear
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_mat_ball = StandardMaterial3D.new()
	_mat_ball.albedo_color = Color(1.0, 0.85, 0.2, 0.75)
	_mat_ball.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ball.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_done = StandardMaterial3D.new()
	_mat_done.albedo_color = Color(0.3, 0.9, 0.35, 0.75)
	_mat_done.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_done.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_build_plane()
	_build_stars()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_time = float(cfg.get_value("game", "best_flight", -1.0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func _build_plane() -> void:
	plane = Node3D.new()
	plane.name = "Plane"
	add_child(plane)
	plane_model = Node3D.new()
	plane_model.rotation.y = PLANE_YAW
	plane.add_child(plane_model)
	var mesh: ArrayMesh = load("res://assets/plane/Plane02.obj")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * 0.5
	plane_model.add_child(mi)

func restart() -> void:
	for r in rings:
		if is_instance_valid(r["node"]):
			(r["node"] as Node).queue_free()
	rings.clear()
	rings_done = 0
	t = 0.0
	over = false
	vy = 0.0
	vz = 0.0
	plane.position = Vector3.ZERO
	_spawn_t = 0.5
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_ui()

func scroll_speed() -> float:
	return SCROLL + minf(float(rings_done) * 0.1, 4.0)

func _physics_process(delta: float) -> void:
	if over or get_tree().paused:
		return
	t += delta
	# 이동 (W위/S아래/A왼쪽/D오른쪽, 화면 기준)
	var sv: Vector2 = stick.value if stick != null else Vector2.ZERO
	var ax := touch_move.x + sv.x + Controls.axis_pressed("flight", "left", "right")
	var ay := touch_move.y - sv.y + Controls.axis_pressed("flight", "down", "up")
	vz = move_toward(vz, clampf(ax, -1.0, 1.0) * SPEED, 40.0 * delta)
	vy = move_toward(vy, clampf(ay, -1.0, 1.0) * SPEED, 40.0 * delta)
	plane.position.z = clampf(plane.position.z + vz * delta, -6.0, 6.0)
	plane.position.y = clampf(plane.position.y + vy * delta, 1.0, 10.0)
	plane_model.rotation.z = clampf(vy * 0.05, -0.45, 0.45)
	plane_model.rotation.x = clampf(vz * 0.04, -0.35, 0.35)
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 14.0 / scroll_speed()
		_spawn_ring()
	_update_rings(delta)
	_update_stars(delta)
	_update_camera(delta)
	_refresh_ui()

func _build_stars() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.85, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(60):
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.5, 0.22, 0.22)
		b.material = m
		mi.mesh = b
		mi.position = Vector3(rng.randf_range(-28, 28), rng.randf_range(-2, 14), rng.randf_range(-12, 12))
		add_child(mi)
		stars.append(mi)

func _update_stars(delta: float) -> void:
	var sp := scroll_speed()
	for s in stars:
		(s as Node3D).position.x -= sp * delta
		if (s as Node3D).position.x < -28.0:
			(s as Node3D).position.x = 28.0

func _spawn_ring() -> void:
	# 노란 공: 보이는 크기 = 충돌 판정 그대로
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.material = _mat_ball
	mi.mesh = sm
	root.add_child(mi)
	root.position = Vector3(18.0, rng.randf_range(2.0, 9.0), rng.randf_range(-5.0, 5.0))
	add_child(root)
	rings.append({"node": root, "passed": false})

func _update_rings(delta: float) -> void:
	var sp := scroll_speed()
	for i in range(rings.size() - 1, -1, -1):
		var r: Dictionary = rings[i]
		if not is_instance_valid(r["node"]):
			rings.remove_at(i)
			continue
		var node := r["node"] as Node3D
		node.position.x -= sp * delta
		# 엄밀 판정: 3D 거리 그대로 (보이는 공 = 히트박스)
		# 닿은 공은 초록으로 바뀌고 지나감 (중복 카운트 없음)
		if not bool(r.get("done", false)) and node.position.distance_to(plane.position) < BALL_R:
			_collect_ring(node)
			r["done"] = true
		if node.position.x < -6.0:
			node.queue_free()
			rings.remove_at(i)

func _collect_ring(node: Node3D) -> void:
	rings_done += 1
	_play_sfx("ring", sfx_ring, minf(1.5, 1.0 + 0.015 * float(rings_done)))
	(node.get_child(0) as MeshInstance3D).material_override = _mat_done
	if rings_done >= RINGS_GOAL:
		over = true
		_play_sfx("clear", sfx_clear, 1.0)
		if best_time < 0.0 or t < best_time:
			best_time = t
			var cfg := ConfigFile.new()
			cfg.load(SAVE_PATH)
			cfg.set_value("game", "best_flight", best_time)
			cfg.save(SAVE_PATH)
		msg_label.text = "클리어! %.1f초 (R: 재시작)" % t
		msg_panel.visible = true
	_refresh_ui()

func _update_camera(delta: float) -> void:
	var want_pos := plane.position + Vector3(-6.0, 3.2, 0)
	var want_look := plane.position + Vector3(4.0, 0.5, 0)
	var k := 1.0 - exp(-5.0 * delta)
	cam.position = cam.position.lerp(want_pos, k)
	var cur_fwd := -cam.global_transform.basis.z
	var want_dir: Vector3 = (want_look - cam.position).normalized() if cam.position.distance_to(want_look) > 0.05 else cur_fwd
	var look: Vector3 = (cam.position + cur_fwd).lerp(cam.position + want_dir, k)
	if look.distance_to(cam.position) > 0.05:
		cam.look_at(look)

# ---------- 입력/UI ----------

func _wire_mobile() -> void:
	stick = mobile_pad.get_node_or_null("Stick") as VirtualStick

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := int(k.physical_keycode)
	if code in Controls.keys_for("global", "restart"):
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
	score_label.text = "%d/30" % rings_done
	best_label.text = "최고: %s" % ("%.1f초" % best_time if best_time >= 0.0 else "-")
	timer_label.text = "%.1f초" % t
