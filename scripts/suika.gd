extends Node3D
## 3D 수박 게임: 위에서 WASD로 위치, 클릭/스페이스로 낙하. 같은 과일끼리 합체.
## 통: x,z ±3, 높이 10. 카메라는 고정(위에서 보는 기준).

const BOX_HALF := 3.0
const BOX_H := 10.0
const DROP_Y := 9.0
const DEAD_Y := 8.0
const OVER_TIME := 2.0
const DROP_CD := 0.4
const CURSOR_SPEED := 6.0

# tier 반경 / 생성 점수(삼각수) / 메시 스케일·오프셋 (실측 기반)
const TIERS := [
	{"name": "낱알포도", "file": "res://assets/fruits/grapesingle.glb", "r": 0.35, "score": 0, "scl": 8.75, "off": Vector3.ZERO},
	{"name": "포도", "file": "res://assets/fruits/grape.glb", "r": 0.5, "score": 1, "scl": 2.857, "off": Vector3(-0.3, 0.19, -0.01)},
	{"name": "바나나", "file": "res://assets/fruits/banana.glb", "r": 0.7, "score": 3, "scl": 1.818, "off": Vector3.ZERO},
	{"name": "오렌지", "file": "res://assets/fruits/orange.glb", "r": 0.95, "score": 6, "scl": 4.222, "off": Vector3.ZERO},
	{"name": "망고", "file": "res://assets/fruits/mango.glb", "r": 1.2, "score": 10, "scl": 5.0, "off": Vector3.ZERO},
	{"name": "사과", "file": "res://assets/fruits/applered.glb", "r": 1.5, "score": 15, "scl": 10.0, "off": Vector3.ZERO},
	{"name": "수박", "file": "res://assets/fruits/watermelon.glb", "r": 1.85, "score": 21, "scl": 3.814, "off": Vector3.ZERO},
]
const DROP_POOL := [0, 1, 2, 3]
const SAVE_PATH := "user://g2048.cfg"

var score := 0
var best := 0
var over := false
var held := 0
var next_tier := 1
var cursor := Vector3(0, DROP_Y, 0)
var rng := RandomNumberGenerator.new()
var last_sfx := ""
var touch_move := Vector2.ZERO # 모바일 D패드: x=D+, y=S+
var _cd := 0.0
var _over_t := {} # instance_id -> 누적 시간
var _guide_line: MeshInstance3D
var _guide_disc: MeshInstance3D

@onready var fruits_node: Node3D = $Fruits
@onready var held_node: Node3D = $Held
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var next_label: Label = $UI/NextLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var sfx_drop: AudioStreamPlayer = $SfxDrop
@onready var sfx_merge: AudioStreamPlayer = $SfxMerge
@onready var sfx_fanfare: AudioStreamPlayer = $SfxFanfare
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var rig_yaw: Node3D = $CameraRig/Yaw
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_build_box()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best_suika", 0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func restart() -> void:
	for c in fruits_node.get_children():
		c.queue_free()
	_over_t.clear()
	score = 0
	over = false
	_cd = 0.0
	cursor = Vector3(0, DROP_Y, 0)
	held = _pick_drop()
	next_tier = _pick_drop()
	_rebuild_held()
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_ui()

func _wire_mobile() -> void:
	var defs := {"MW": "w", "MA": "a", "MS": "s", "MD": "d"}
	for n in defs.keys():
		var b: Button = mobile_pad.get_node_or_null(n) as Button
		if b == null:
			continue
		b.button_down.connect(_on_touch.bind(str(defs[n]), true))
		b.button_up.connect(_on_touch.bind(str(defs[n]), false))
	var drop_b: Button = mobile_pad.get_node_or_null("MDrop") as Button
	if drop_b != null:
		drop_b.pressed.connect(drop)

func _on_touch(dir: String, pressed: bool) -> void:
	match dir:
		"w":
			touch_move.y = -1.0 if pressed else 0.0
		"s":
			touch_move.y = 1.0 if pressed else 0.0
		"a":
			touch_move.x = -1.0 if pressed else 0.0
		"d":
			touch_move.x = 1.0 if pressed else 0.0

func _pick_drop() -> int:
	return DROP_POOL[rng.randi_range(0, DROP_POOL.size() - 1)]

func _fruit_mesh(tier: int) -> Node3D:
	var root := Node3D.new()
	var packed: PackedScene = load(str(TIERS[tier]["file"]))
	var body := packed.instantiate() as Node3D
	body.scale = Vector3.ONE * float(TIERS[tier]["scl"])
	body.position = TIERS[tier]["off"] as Vector3
	root.add_child(body)
	return root

func _rebuild_held() -> void:
	for c in held_node.get_children():
		c.queue_free()
	held_node.add_child(_fruit_mesh(held))
	held_node.position = cursor
	_update_guide()

func _make_fruit(tier: int, pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = pow(float(TIERS[tier]["r"]), 3.0)
	b.linear_damp = 0.05
	b.angular_damp = 0.3
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.25
	b.physics_material_override = pm
	b.contact_monitor = true
	b.max_contacts_reported = 8
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = float(TIERS[tier]["r"])
	cs.shape = sp
	b.add_child(cs)
	b.add_child(_fruit_mesh(tier))
	b.position = pos
	b.set_meta("tier", tier)
	b.set_meta("born", Time.get_ticks_msec())
	b.add_to_group("fruit")
	fruits_node.add_child(b)
	b.body_entered.connect(_on_fruit_contact.bind(b))
	return b

func drop() -> void:
	if over or _cd > 0.0 or get_tree().paused:
		return
	_cd = DROP_CD
	_make_fruit(held, cursor)
	_play_sfx("drop", sfx_drop, 1.0)
	held = next_tier
	next_tier = _pick_drop()
	_rebuild_held()
	_refresh_ui()

func _physics_process(delta: float) -> void:
	if over or get_tree().paused:
		return
	if _cd > 0.0:
		_cd -= delta
	var ax := 0.0
	var az := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		ax -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		ax += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		az -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		az += 1.0
	# 카메라 기준 이동 (궤도 회전해도 화면 방향과 일치)
	var wish: Vector3 = Basis(Vector3.UP, rig_yaw.rotation.y) * Vector3(ax + touch_move.x, 0.0, az + touch_move.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var lim: float = BOX_HALF - float(TIERS[held]["r"]) - 0.1
	cursor.x = clampf(cursor.x + wish.x * CURSOR_SPEED * delta, -lim, lim)
	cursor.z = clampf(cursor.z + wish.z * CURSOR_SPEED * delta, -lim, lim)
	held_node.position = cursor
	_update_guide()
	_check_deadline(delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_SPACE:
		drop()
	elif k.physical_keycode == KEY_R:
		restart()
	elif k.physical_keycode == KEY_P:
		if get_tree().paused:
			resume_game()
		else:
			pause_game()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			drop()

func _on_fruit_contact(other: Node, me: RigidBody3D) -> void:
	if over:
		return
	if not (other is RigidBody3D and (other as Node).is_in_group("fruit")):
		return
	if not is_instance_valid(me):
		return
	var ta: int = me.get_meta("tier")
	var tb: int = other.get_meta("tier")
	if ta != tb:
		return
	if me.has_meta("merging") or other.has_meta("merging"):
		return
	me.set_meta("merging", true)
	other.set_meta("merging", true)
	call_deferred("_do_merge", me, other, ta)

func _do_merge(a: RigidBody3D, b: RigidBody3D, tier: int) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var mid := (a.global_position + b.global_position) * 0.5
	a.queue_free()
	b.queue_free()
	if tier >= TIERS.size() - 1:
		score += 100 # 수박+수박 보너스
		_play_sfx("fanfare", sfx_fanfare, 1.3)
	else:
		var nb := _make_fruit(tier + 1, mid)
		nb.scale = Vector3.ONE * 1.3
		var tw := create_tween()
		tw.tween_property(nb, "scale", Vector3.ONE, 0.15)
		score += int(TIERS[tier + 1]["score"])
		_play_sfx("merge", sfx_merge, minf(1.5, 1.0 + 0.07 * float(tier + 1)))
		if tier + 1 == TIERS.size() - 1:
			_play_sfx("fanfare", sfx_fanfare, 1.0)
	if score > best:
		best = score
		var cfg := ConfigFile.new()
		cfg.load(SAVE_PATH)
		cfg.set_value("game", "best_suika", best)
		cfg.save(SAVE_PATH)
	_refresh_ui()

func _check_deadline(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for f in get_tree().get_nodes_in_group("fruit"):
		var rb := f as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var id := rb.get_instance_id()
		var fresh: bool = float(now - int(rb.get_meta("born"))) < 1000.0
		if not fresh and rb.global_position.y > DEAD_Y and rb.linear_velocity.length() < 0.6:
			_over_t[id] = float(_over_t.get(id, 0.0)) + delta
			if float(_over_t[id]) > OVER_TIME:
				game_over()
				return
		else:
			_over_t.erase(id)
	for id in _over_t.keys():
		if not is_instance_valid(instance_from_id(id)):
			_over_t.erase(id)

func game_over() -> void:
	over = true
	_play_sfx("over", sfx_over, 1.0)
	msg_label.text = "게임 오버! 점수 %d (R: 재시작)" % score
	msg_panel.visible = true

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

func _play_sfx(sfx_name: String, player: AudioStreamPlayer, pitch: float) -> void:
	last_sfx = sfx_name
	player.pitch_scale = pitch
	player.play()

func _refresh_ui() -> void:
	score_label.text = "점수: %d" % score
	best_label.text = "최고: %d" % best
	next_label.text = "다음: " + str(TIERS[next_tier]["name"])

func _build_guide() -> void:
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.4, 1.0, 0.9, 0.45)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_guide_line = MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.08, 1.0, 0.08)
	lb.material = gm
	_guide_line.mesh = lb
	add_child(_guide_line)
	_guide_disc = MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 1.0
	dc.bottom_radius = 1.0
	dc.height = 0.06
	dc.material = gm
	_guide_disc.mesh = dc
	add_child(_guide_disc)

func _update_guide() -> void:
	if _guide_line == null:
		return
	_guide_line.position = Vector3(cursor.x, cursor.y * 0.5, cursor.z)
	_guide_line.scale = Vector3(1.0, cursor.y, 1.0)
	var r: float = float(TIERS[held]["r"])
	_guide_disc.position = Vector3(cursor.x, 0.08, cursor.z)
	_guide_disc.scale = Vector3(r, 1.0, r)

func _build_box() -> void:
	_build_guide()
	var wall_mat := StandardMaterial3D.new()
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.albedo_color = Color(0.6, 0.75, 1.0, 0.12)
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.5, 0.55, 0.7)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.24)
	# 바닥
	_solid(Vector3(0, -0.25, 0), Vector3(BOX_HALF * 2 + 1.0, 0.5, BOX_HALF * 2 + 1.0), floor_mat, true)
	# 4면 벽(충돌) + 유리 비주얼
	var t := 0.4
	_solid(Vector3(0, BOX_H * 0.5, -BOX_HALF - t * 0.5), Vector3(BOX_HALF * 2 + t * 2.0, BOX_H, t), wall_mat, false)
	_solid(Vector3(0, BOX_H * 0.5, BOX_HALF + t * 0.5), Vector3(BOX_HALF * 2 + t * 2.0, BOX_H, t), wall_mat, false)
	_solid(Vector3(-BOX_HALF - t * 0.5, BOX_H * 0.5, 0), Vector3(t, BOX_H, BOX_HALF * 2.0), wall_mat, false)
	_solid(Vector3(BOX_HALF + t * 0.5, BOX_H * 0.5, 0), Vector3(t, BOX_H, BOX_HALF * 2.0), wall_mat, false)
	# 모서리 바 + 데드라인
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_bar(Vector3(sx * BOX_HALF, BOX_H * 0.5, sz * BOX_HALF), Vector3(0.12, BOX_H, 0.12), edge_mat)
	var dead := MeshInstance3D.new()
	var dq := BoxMesh.new()
	dq.size = Vector3(BOX_HALF * 2, 0.05, BOX_HALF * 2)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(1.0, 0.3, 0.3, 0.25)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dq.material = dm
	dead.mesh = dq
	dead.position = Vector3(0, DEAD_Y, 0)
	add_child(dead)

func _solid(pos: Vector3, size: Vector3, mat: Material, _floor: bool) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	body.position = pos
	add_child(body)

func _bar(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	add_child(mi)
