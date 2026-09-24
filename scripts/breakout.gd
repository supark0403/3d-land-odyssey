extends Node3D
## 3D 블록깨기: 패들(X축) + 3D 탄착 볼. 벽돌 8x4x2. 전부 키네마틱.

const ARENA_X := 8.5
const ARENA_Y_MIN := 0.5
const ARENA_Y_MAX := 10.5
const BACK_Z := -10.0
const FRONT_Z := 10.0
const GATE_X := 2.0
const GATE_Y := 1.5
const GATE_CY := 5.5
const PADDLE_Y_MIN := 0.8
const PADDLE_Y_MAX := 6.0
const BALL_EVERY := 25.0
const BALL_MAX := 5
const PADDLE_Z := 8.0
const PADDLE_W := 2.6
const COLS := 8
const ROWS := 4
const LAYERS := 2
const SAVE_PATH := "user://g2048.cfg"

var score := 0
var best := 0
var lives := 3
var level := 1
var over := false
var balls: Array = [] # {node, vel, stuck}
var ball_timer := 0.0
var ball_speed := 12.0
var last_sfx := ""
var rng := RandomNumberGenerator.new()

var paddle: Node3D
var paddle_vx := 0.0
var paddle_vy := 0.0
var touch_x := 0.0
var touch_y := 0.0
var stick: VirtualStick
var blocks := {} # Vector3i -> {node, hp}
var _mats := {}

@onready var blocks_node: Node3D = $Blocks
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var level_label: Label = $UI/LevelLabel
@onready var lives_box: HBoxContainer = $UI/LivesBox
@onready var heart_full_tex: Texture2D = load("res://assets/pxui/hearts/heart_full.png")
@onready var heart_empty_tex: Texture2D = load("res://assets/pxui/hearts/heart_empty.png")
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_hit: AudioStreamPlayer = $SfxHit
@onready var sfx_break: AudioStreamPlayer = $SfxBreak
@onready var sfx_wall: AudioStreamPlayer = $SfxWall
@onready var sfx_lose: AudioStreamPlayer = $SfxLose
@onready var sfx_win: AudioStreamPlayer = $SfxWin
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

static func cell_center(c: Vector3i) -> Vector3:
	return Vector3((float(c.x) - 3.5) * 1.05, 3.0 + float(c.y) * 1.05, -8.0 + float(c.z) * 1.05)

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_build_actors()
	_build_room()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best_breakout", 0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func _mat_for(row: int, hp: int) -> StandardMaterial3D:
	var key := str(row) + "_" + str(hp)
	if not _mats.has(key):
		var cols := [Color(0.95, 0.35, 0.3), Color(0.95, 0.6, 0.2), Color(0.95, 0.9, 0.3), Color(0.35, 0.85, 0.4)]
		var m := StandardMaterial3D.new()
		var c: Color = cols[row % 4]
		m.albedo_color = c if hp <= 1 else c.darkened(0.45)
		m.roughness = 0.5
		_mats[key] = m
	return _mats[key]

func _build_room() -> void:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.75, 1.0, 0.1)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.5, 0.55, 0.7)
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.13, 0.14, 0.2)
	_solid(Vector3(0, 0.25, 0), Vector3(18.0, 0.5, 21.0), floor_m)
	_solid(Vector3(-8.75, 5.5, 0), Vector3(0.1, 10.0, 20.0), glass)
	_solid(Vector3(8.75, 5.5, 0), Vector3(0.1, 10.0, 20.0), glass)
	_solid(Vector3(0, 5.5, -10.25), Vector3(18.0, 10.0, 0.1), glass)
	# 앞벽 (게이트 구멍 포함): 구멍으로 빠지면 실점, 나머지는 반사
	_solid(Vector3(-(GATE_X + 8.75) * 0.5, 5.5, FRONT_Z), Vector3(8.75 - GATE_X, 10.0, 0.2), glass)
	_solid(Vector3((GATE_X + 8.75) * 0.5, 5.5, FRONT_Z), Vector3(8.75 - GATE_X, 10.0, 0.2), glass)
	_solid(Vector3(0, (0.5 + GATE_CY - GATE_Y) * 0.5, FRONT_Z), Vector3(GATE_X * 2.0, GATE_CY - GATE_Y - 0.5, 0.2), glass)
	_solid(Vector3(0, (GATE_CY + GATE_Y + 10.5) * 0.5, FRONT_Z), Vector3(GATE_X * 2.0, 10.5 - GATE_CY - GATE_Y, 0.2), glass)
	for sx in [-1.0, 1.0]:
		_solid(Vector3(sx * GATE_X, GATE_CY, FRONT_Z), Vector3(0.16, GATE_Y * 2.0, 0.3), edge)
	for sy in [GATE_CY - GATE_Y, GATE_CY + GATE_Y]:
		_solid(Vector3(0, sy, FRONT_Z), Vector3(GATE_X * 2.0 + 0.16, 0.16, 0.3), edge)
	_solid(Vector3(0, 10.75, 0), Vector3(18.0, 0.1, 20.0), glass)
	for sx in [-1.0, 1.0]:
		for sy in [0.5, 10.5]:
			_solid(Vector3(sx * 8.75, sy, 0), Vector3(0.16, 0.16, 20.0), edge)
	for sz in [-10.0, 10.0]:
		for sx in [-8.75, 8.75]:
			_solid(Vector3(sx, 5.5, sz), Vector3(0.16, 10.0, 0.16), edge)
		_solid(Vector3(0, 10.5, sz), Vector3(18.0, 0.16, 0.16), edge)

func _solid(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	add_child(mi)

func _build_actors() -> void:
	paddle = Node3D.new()
	paddle.name = "Paddle"
	var pm := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(PADDLE_W, 0.5, 1.0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.4, 0.8, 1.0)
	pb.material = pmat
	pm.mesh = pb
	paddle.add_child(pm)
	paddle.position = Vector3(0, 1.0, PADDLE_Z)
	add_child(paddle)

func _make_ball() -> Node3D:
	var root := Node3D.new()
	root.name = "Ball"
	var bm := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.3
	bs.height = 0.6
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1, 1, 1)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bs.material = bmat
	bm.mesh = bs
	root.add_child(bm)
	add_child(root)
	return root

func restart() -> void:
	for k in blocks.keys():
		(blocks[k]["node"] as Node).queue_free()
	blocks.clear()
	score = 0
	lives = 3
	level = 1
	ball_speed = 12.0
	over = false
	_build_level()
	_stick_ball()
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	_refresh_ui()

func _build_level() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.98, 0.98, 0.98)
	for x in range(COLS):
		for y in range(ROWS):
			for z in range(LAYERS):
				var hp := 1
				if level >= 2 and z == 0:
					hp = 2
				var mi := MeshInstance3D.new()
				mi.mesh = bm
				mi.material_override = _mat_for(y, hp)
				mi.position = cell_center(Vector3i(x, y, z))
				blocks_node.add_child(mi)
				blocks[Vector3i(x, y, z)] = {"node": mi, "hp": hp}

func _stick_ball() -> void:
	for b in balls:
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
	balls.clear()
	ball_timer = 0.0
	var nb := _make_ball()
	nb.position = paddle.position + Vector3(0, 0.6, 0)
	balls.append({"node": nb, "vel": Vector3.ZERO, "stuck": true})

func _any_stuck() -> bool:
	for b in balls:
		if bool(b["stuck"]):
			return true
	return false

func launch() -> void:
	if over or get_tree().paused:
		return
	var did := false
	for b in balls:
		if bool(b["stuck"]):
			b["stuck"] = false
			var a := rng.randf_range(-0.4, 0.4)
			b["vel"] = Vector3(sin(a), 0.35, -cos(a)).normalized() * ball_speed
			did = true
	if did:
		_play_sfx("launch", sfx_hit, 1.0)

func _spawn_extra() -> void:
	var nb := _make_ball()
	nb.position = paddle.position + Vector3(0, 0.6, 0)
	var a := rng.randf_range(-0.5, 0.5)
	balls.append({"node": nb, "vel": Vector3(sin(a), 0.45, -cos(a)).normalized() * ball_speed, "stuck": false})
	_play_sfx("launch", sfx_hit, 0.8)
	_refresh_ui()

func _physics_process(delta: float) -> void:
	if over or get_tree().paused:
		return
	# 패들 (좌우 + 상하)
	var sv: Vector2 = stick.value if stick != null else Vector2.ZERO
	var ax := sv.x + Controls.axis_pressed("breakout", "left", "right")
	var ay := -sv.y + Controls.axis_pressed("breakout", "down", "up")
	paddle_vx = move_toward(paddle_vx, clampf(ax, -1.0, 1.0) * 11.0, 60.0 * delta)
	paddle_vy = move_toward(paddle_vy, clampf(ay, -1.0, 1.0) * 9.0, 50.0 * delta)
	paddle.position.x = clampf(paddle.position.x + paddle_vx * delta, -ARENA_X + PADDLE_W * 0.5, ARENA_X - PADDLE_W * 0.5)
	paddle.position.y = clampf(paddle.position.y + paddle_vy * delta, PADDLE_Y_MIN, PADDLE_Y_MAX)
	# 시간 경과 멀티볼
	if not _any_stuck():
		ball_timer += delta
		if ball_timer >= BALL_EVERY and balls.size() < BALL_MAX:
			ball_timer = 0.0
			_spawn_extra()
	for i in range(balls.size() - 1, -1, -1):
		var b: Dictionary = balls[i]
		if not is_instance_valid(b["node"]):
			balls.remove_at(i)
			continue
		if bool(b["stuck"]):
			(b["node"] as Node3D).position = paddle.position + Vector3(0, 0.6, 0)
		else:
			_move_ball(i, delta)
			if i >= balls.size():
				break # 레벨 클리어로 공 배열 교체됨
	if balls.is_empty() and not over:
		_lose_life()

func _move_ball(bi: int, delta: float) -> void:
	var b: Dictionary = balls[bi]
	var node := b["node"] as Node3D
	var vel := b["vel"] as Vector3
	node.position += vel * delta
	var p := node.position
	# 벽
	if p.x < -ARENA_X + 0.3:
		p.x = -ARENA_X + 0.3
		vel.x = absf(vel.x)
		_play_sfx("wall", sfx_wall, 1.0)
	elif p.x > ARENA_X - 0.3:
		p.x = ARENA_X - 0.3
		vel.x = -absf(vel.x)
		_play_sfx("wall", sfx_wall, 1.0)
	if p.y < ARENA_Y_MIN + 0.3:
		p.y = ARENA_Y_MIN + 0.3
		vel.y = absf(vel.y)
		_play_sfx("wall", sfx_wall, 1.0)
	elif p.y > ARENA_Y_MAX - 0.3:
		p.y = ARENA_Y_MAX - 0.3
		vel.y = -absf(vel.y)
		_play_sfx("wall", sfx_wall, 1.0)
	if p.z < BACK_Z + 0.3:
		p.z = BACK_Z + 0.3
		vel.z = absf(vel.z)
		_play_sfx("wall", sfx_wall, 1.0)
	elif p.z > FRONT_Z - 0.3:
		# 앞벽: 게이트 안이면 통과(실점), 아니면 반사
		if absf(p.x) < GATE_X - 0.3 and absf(p.y - GATE_CY) < GATE_Y - 0.3:
			pass
		else:
			p.z = FRONT_Z - 0.3
			vel.z = -absf(vel.z)
			_play_sfx("wall", sfx_wall, 1.0)
	node.position = p
	# 패들 (위에서 떨어질 때만)
	if vel.z > 0.0 and absf(p.z - PADDLE_Z) < 0.8 and absf(p.x - paddle.position.x) < PADDLE_W * 0.5 + 0.3 and absf(p.y - paddle.position.y) < 0.8:
		var off := clampf((p.x - paddle.position.x) / (PADDLE_W * 0.5), -1.0, 1.0)
		vel = Vector3(off * 7.0 + paddle_vx * 0.4, clampf(2.0 + paddle_vy * 0.3, -6.0, 6.0), -absf(vel.z)).normalized() * ball_speed
		_play_sfx("paddle", sfx_hit, 1.0)
	b["vel"] = vel
	# 게이트 탈출: 이 공만 제거, 전부 소진 시 실점
	if p.z > FRONT_Z + 1.0:
		node.queue_free()
		balls.remove_at(bi)
		return
	_hit_blocks(bi)

func _hit_blocks(bi: int) -> void:
	var b: Dictionary = balls[bi]
	var node := b["node"] as Node3D
	var vel := b["vel"] as Vector3
	var p := node.position
	for k in blocks.keys():
		var c: Vector3 = cell_center(k)
		var d := p - c
		if absf(d.x) < 0.8 and absf(d.y) < 0.8 and absf(d.z) < 0.8:
			# 최소 침투 축으로 반사
			var px := 0.8 - absf(d.x)
			var py := 0.8 - absf(d.y)
			var pz := 0.8 - absf(d.z)
			if px < py and px < pz:
				vel.x = signf(d.x) * absf(vel.x)
				if d.x == 0.0:
					vel.x = -vel.x
			elif py < pz:
				vel.y = signf(d.y) * absf(vel.y)
				if d.y == 0.0:
					vel.y = -vel.y
			else:
				vel.z = signf(d.z) * absf(vel.z)
				if d.z == 0.0:
					vel.z = -vel.z
			b["vel"] = vel
			node.position = p + vel.normalized() * 0.05
			_damage_block(k, bi)
			break

func _damage_block(k: Vector3i, bi: int) -> void:
	var b: Dictionary = blocks[k]
	b["hp"] = int(b["hp"]) - 1
	if int(b["hp"]) <= 0:
		(b["node"] as Node).queue_free()
		blocks.erase(k)
		score += 50
		ball_speed = minf(ball_speed + 0.15, 20.0)
		if bi < balls.size() and is_instance_valid(balls[bi]["node"]):
			balls[bi]["vel"] = (balls[bi]["vel"] as Vector3).normalized() * ball_speed
		_play_sfx("break", sfx_break, minf(1.4, 1.0 + 0.02 * float(score / 50)))
		if blocks.is_empty():
			_next_level()
	else:
		((b["node"] as Node3D).get_child(0) as MeshInstance3D).material_override = _mat_for(k.y, int(b["hp"]))
		_play_sfx("crack", sfx_hit, 0.8)
	_refresh_ui()

func _next_level() -> void:
	level += 1
	lives = mini(3, lives + 1)
	ball_speed = minf(12.0 + float(level - 1), 18.0)
	_play_sfx("win", sfx_win, 1.0)
	_build_level()
	_stick_ball()
	_refresh_ui()

func _lose_life() -> void:
	lives -= 1
	_play_sfx("lose", sfx_lose, 1.0)
	if lives <= 0:
		over = true
		_play_sfx("over", sfx_over, 1.0)
		if score > best:
			best = score
			var cfg := ConfigFile.new()
			cfg.load(SAVE_PATH)
			cfg.set_value("game", "best_breakout", best)
			cfg.save(SAVE_PATH)
		msg_label.text = "게임 오버! %d점 (R: 재시작)" % score
		msg_panel.visible = true
	else:
		_stick_ball()
	_refresh_ui()

# ---------- 입력/UI ----------

func _wire_mobile() -> void:
	stick = mobile_pad.get_node_or_null("Stick") as VirtualStick
	var mf: Button = mobile_pad.get_node_or_null("MFire") as Button
	if mf != null:
		mf.pressed.connect(launch)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := int(k.physical_keycode)
	if code in Controls.keys_for("breakout", "launch"):
		launch()
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
			launch()

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
	level_label.text = "LV.%d (공%d)" % [level, balls.size()]
	for i in range(3):
		var h: TextureRect = lives_box.get_node("HpH" + str(i))
		h.texture = heart_full_tex if lives > i else heart_empty_tex
