extends Node3D
## 3D 플래피 버드: 스페이스=상승, A/D=좌우. 장애물은 오른쪽에서 옴.
## 카메라는 비행기 45도 오른쪽 뒤 고정 추적. 물리 없이 키네마틱.

const GRAV := 24.0
const FLAP_VY := 7.5
const MAX_FALL := -13.0
const LAT_SPEED := 7.5
const PLANE_R := 0.9
const BASE_SPEED := 7.0
const GATE_SPACING := 16.0
const SPAWN_X := 16.0
const KILL_X := -12.0
const SAVE_PATH := "user://g2048.cfg"
# 모델 정면 +Z 가정 → +X(장애물 쪽)로 비행. 뒤집혀 보이면 -PI*0.5로
const PLANE_YAW := PI * 0.5
# 히트박스 (관대하게): 기체 반경, 게이트 반두께, 가장자리 여유, 상하 여유
const GATE_HALF := 0.5
const EDGE_M := 0.25
const Y_M := 0.7
const GROUND_Y := 0.85

var score := 0
var best := 0
var over := false
var vy := 0.0
var vz := 0.0
var touch_x := 0.0
var last_sfx := ""
var rng := RandomNumberGenerator.new()

var plane: Node3D
var plane_model: Node3D
var pitch_node: Node3D
var gates: Array = [] # {node, gap_top, gap_bottom, zc, zw, scored}
var _mat_body: StandardMaterial3D
var _mat_lip: StandardMaterial3D

@onready var cam: Camera3D = $Camera3D
@onready var score_digits: HBoxContainer = $UI/ScoreDigits
@onready var best_label: Label = $UI/BestLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_flap: AudioStreamPlayer = $SfxFlap
@onready var sfx_score: AudioStreamPlayer = $SfxScore
@onready var sfx_crash: AudioStreamPlayer = $SfxCrash
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_mat_body = StandardMaterial3D.new()
	_mat_body.albedo_color = Color(0.95, 0.45, 0.2)
	_mat_body.roughness = 0.6
	_mat_lip = StandardMaterial3D.new()
	_mat_lip.albedo_color = Color(0.95, 0.95, 0.95)
	_mat_lip.roughness = 0.5
	_build_plane()
	_build_ground()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best_flappy", 0))
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
	pitch_node = Node3D.new()
	plane_model.add_child(pitch_node)
	var mesh: ArrayMesh = load("res://assets/plane/Plane02.obj")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * 0.5
	pitch_node.add_child(mi)

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 120)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.15, 0.22)
	m.roughness = 0.9
	pm.material = m
	mi.mesh = pm
	add_child(mi)

func restart() -> void:
	for g in gates:
		if is_instance_valid(g["node"]):
			(g["node"] as Node).queue_free()
	gates.clear()
	score = 0
	over = false
	vy = 0.0
	vz = 0.0
	plane.position = Vector3(0, 5.5, 0)
	_spawn_gate(SPAWN_X)
	_spawn_gate(SPAWN_X + GATE_SPACING)
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_ui()

func speed() -> float:
	return BASE_SPEED + minf(score * 0.15, 5.0)

func flap() -> void:
	if over or get_tree().paused:
		return
	vy = FLAP_VY
	_play_sfx("flap", sfx_flap, 1.0)

func _physics_process(delta: float) -> void:
	if over or get_tree().paused:
		return
	# 상하
	vy = maxf(MAX_FALL, vy - GRAV * delta)
	plane.position.y += vy * delta
	if plane.position.y > 11.0:
		plane.position.y = 11.0
		vy = minf(vy, 0.0)
	if plane.position.y < GROUND_Y:
		_crash()
		return
	# 좌우 (A/왼쪽 = -Z: 화면 왼쪽, 기체 오른쪽. 체이스캠 기준)
	var ax := touch_x
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		ax -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		ax += 1.0
	vz = move_toward(vz, clampf(ax, -1.0, 1.0) * LAT_SPEED, 30.0 * delta)
	plane.position.z = clampf(plane.position.z + vz * delta, -5.0, 5.0)
	# 피치 (상승 시 기수 위)
	pitch_node.rotation.x = clampf(-vy * 0.06, -0.5, 0.6)
	_update_gates(delta)
	_update_camera()

func _update_camera() -> void:
	cam.position = plane.position + Vector3(-6.4, 3.5, 6.4)
	cam.look_at(plane.position + Vector3(3.5, 0.8, 0))

func _spawn_gate(x: float) -> void:
	var gap_h := 3.6
	var gap_y := rng.randf_range(3.2, 7.8)
	var zc := rng.randf_range(-2.0, 2.0)
	var zw := 5.5
	var gap_top := gap_y + gap_h * 0.5
	var gap_bottom := gap_y - gap_h * 0.5
	var root := Node3D.new()
	root.position = Vector3(x, 0, 0)
	add_child(root)
	# 위 기둥 (gap_top ~ 12)
	_box(root, Vector3(0, (gap_top + 12.0) * 0.5, zc), Vector3(1.0, 12.0 - gap_top, zw), _mat_body)
	# 아래 기둥 (0 ~ gap_bottom)
	_box(root, Vector3(0, gap_bottom * 0.5, zc), Vector3(1.0, gap_bottom, zw), _mat_body)
	# 갭 입술 (흰색)
	_box(root, Vector3(0, gap_top - 0.15, zc), Vector3(1.1, 0.3, zw + 0.2), _mat_lip)
	_box(root, Vector3(0, gap_bottom + 0.15, zc), Vector3(1.1, 0.3, zw + 0.2), _mat_lip)
	gates.append({"node": root, "gap_top": gap_top, "gap_bottom": gap_bottom, "zc": zc, "zw": zw, "scored": false})

func _box(parent: Node, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)

func _update_gates(delta: float) -> void:
	var sp := speed()
	var last_x := -999.0
	for g in gates:
		if is_instance_valid(g["node"]):
			(g["node"] as Node3D).position.x -= sp * delta
			last_x = maxf(last_x, (g["node"] as Node3D).position.x)
	for i in range(gates.size() - 1, -1, -1):
		var g: Dictionary = gates[i]
		if not is_instance_valid(g["node"]):
			gates.remove_at(i)
			continue
		var gx: float = (g["node"] as Node3D).position.x
		if gx < KILL_X:
			(g["node"] as Node).queue_free()
			gates.remove_at(i)
			continue
		if not bool(g["scored"]) and gx < -1.4:
			g["scored"] = true
			score += 1
			_play_sfx("score", sfx_score, minf(1.4, 1.0 + 0.03 * float(score)))
			_refresh_ui()
		_check_gate(g, gx)
	if last_x < SPAWN_X - GATE_SPACING and last_x > -900.0:
		_spawn_gate(last_x + GATE_SPACING)

func _check_gate(g: Dictionary, gx: float) -> void:
	if absf(gx) > PLANE_R + GATE_HALF:
		return
	if absf(plane.position.z - float(g["zc"])) > float(g["zw"]) * 0.5 + EDGE_M:
		return # 게이트 옆으로 통과
	if plane.position.y + Y_M > float(g["gap_top"]) or plane.position.y - Y_M < float(g["gap_bottom"]):
		_crash()

func _crash() -> void:
	if over:
		return
	over = true
	_play_sfx("crash", sfx_crash, 1.0)
	if score > best:
		best = score
		var cfg := ConfigFile.new()
		cfg.load(SAVE_PATH)
		cfg.set_value("game", "best_flappy", best)
		cfg.save(SAVE_PATH)
	msg_label.text = "추락! %d점 (R: 재시작)" % score
	msg_panel.visible = true
	_refresh_ui()

# ---------- 입력/UI ----------

func _wire_mobile() -> void:
	var ml: Button = mobile_pad.get_node_or_null("MLeft") as Button
	var mr: Button = mobile_pad.get_node_or_null("MRight") as Button
	if ml != null:
		ml.button_down.connect(_on_touch.bind(-1.0))
		ml.button_up.connect(_on_touch.bind(0.0))
	if mr != null:
		mr.button_down.connect(_on_touch.bind(1.0))
		mr.button_up.connect(_on_touch.bind(0.0))
	var mf: Button = mobile_pad.get_node_or_null("MFlap") as Button
	if mf != null:
		mf.pressed.connect(flap)

func _on_touch(v: float) -> void:
	touch_x = v

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_SPACE:
		flap()
	elif k.physical_keycode == KEY_R:
		restart()
	elif k.physical_keycode == KEY_P:
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
	_refresh_digits()
	best_label.text = "최고: %d" % best

func _refresh_digits() -> void:
	for c in score_digits.get_children():
		c.queue_free()
	var s := str(score)
	if s == "":
		s = "0"
	for ch in s:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(54, 72)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load("res://assets/pxui/digits/digit_" + ch + ".png") as Texture2D
		score_digits.add_child(tr)
