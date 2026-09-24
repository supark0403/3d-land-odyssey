extends Node3D
## 3D 탄막슈팅: 3스테이지 + 스테이지별 보스. 뒤에서 살짝 비스듬히 보는 시점.
## 자동 발사. 이동 범위는 x±9, y1..9 고정 z=10 평면. 전부 키네마틱.

const PX := 9.0
const PY_MIN := 1.0
const PY_MAX := 9.0
const PZ := 10.0
const SAVE_PATH := "user://g2048.cfg"
# 적 기수 +X 가정 → -PI/2 로 +Z(플레이어 쪽)를 봄. 이상하면 부호 뒤집기
const ENEMY_YAW := -PI * 0.5

var score := 0
var best := 0
var stage := 1
var over := false
var won := false
var hp := 3
var power := 1
var fire_t := 0.0
var iframes := 0.0
var touch := Vector2.ZERO
var stick: VirtualStick
var last_sfx := ""
var rng := RandomNumberGenerator.new()

var player: Node3D
var enemies: Array = [] # {node, kind, hp, speed, t, fire_t, score, r, boss, maxhp, phase}
var bolts: Array = [] # {node, vel, team(0自/1敌), dmg}
var items: Array = [] # {node, kind(P/H), vel}
var stars: Array = []
var stage_t := 0.0
var spawn_queue: Array = [] # {t, kind}
var boss_ref: Node = null
var boss_warn_t := 0.0
var stage_phase := "waves" # waves -> warn -> boss -> clear

const PLANES := {
	"player": {"file": "res://assets/planes/plane01.obj", "scl": 0.45},
	"dart": {"file": "res://assets/planes/plane06.obj", "scl": 0.4},
	"gunship": {"file": "res://assets/planes/plane05.obj", "scl": 0.45},
	"shooter": {"file": "res://assets/planes/plane03.obj", "scl": 0.45},
	"boss1": {"file": "res://assets/planes/plane05.obj", "scl": 1.0, "tint": Color(1.0, 0.35, 0.3)},
	"boss2": {"file": "res://assets/planes/plane03.obj", "scl": 1.1, "tint": Color(1.0, 0.6, 0.2)},
	"boss3": {"file": "res://assets/planes/plane01.obj", "scl": 1.25, "tint": Color(0.7, 0.4, 1.0)},
}
# kind: hp, speed, score, r, fire_interval(0=안쏨)
const FOE := {
	"dart": {"hp": 2.0, "speed": 7.0, "score": 100, "r": 1.0, "fire": 0.0, "pattern": "aimed1", "interval": 3.0},
	"gunship": {"hp": 6.0, "speed": 4.5, "score": 250, "r": 1.2, "fire": 0.0, "pattern": "spread3", "interval": 2.5},
	"shooter": {"hp": 4.0, "speed": 3.5, "score": 400, "r": 1.1, "fire": 2.2, "pattern": "spread2", "interval": 2.0},
	"boss1": {"hp": 120.0, "speed": 2.0, "score": 5000, "r": 2.2, "fire": 1.6},
	"boss2": {"hp": 200.0, "speed": 2.2, "score": 8000, "r": 2.4, "fire": 1.4},
	"boss3": {"hp": 300.0, "speed": 2.4, "score": 15000, "r": 2.6, "fire": 1.2},
}

@onready var cam: Camera3D = $Camera3D
@onready var enemies_node: Node3D = $Enemies
@onready var bolts_node: Node3D = $Bolts
@onready var items_node: Node3D = $Items
@onready var score_label: Label = $UI/ScoreLabel
@onready var best_label: Label = $UI/BestLabel
@onready var stage_label: Label = $UI/StageLabel
@onready var hp_hearts: Array = [$UI/HpHearts/HpH0, $UI/HpHearts/HpH1, $UI/HpHearts/HpH2]
@onready var heart_full_tex: Texture2D = load("res://assets/pxui/hearts/heart_full.png")
@onready var heart_empty_tex: Texture2D = load("res://assets/pxui/hearts/heart_empty.png")
@onready var boss_bar: ProgressBar = $UI/BossBar
@onready var boss_label: Label = $UI/BossLabel
@onready var banner_label: Label = $UI/BannerLabel
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_shoot: AudioStreamPlayer = $SfxShoot
@onready var sfx_kill: AudioStreamPlayer = $SfxKill
@onready var sfx_hurt: AudioStreamPlayer = $SfxHurt
@onready var sfx_item: AudioStreamPlayer = $SfxItem
@onready var sfx_win: AudioStreamPlayer = $SfxWin
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	rng.randomize()
	_build_stars()
	_build_player()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best_shmup", 0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func _plane_mesh(kind: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = load(str(PLANES[kind]["file"])) as ArrayMesh
	var s := float(PLANES[kind]["scl"])
	mi.scale = Vector3.ONE * s
	if PLANES[kind].has("tint"):
		mi.material_override = _tint_mat(PLANES[kind]["tint"])
	root.add_child(mi)
	return root

var _tint_cache := {}

func _tint_mat(c: Color) -> StandardMaterial3D:
	var k := str(c)
	if not _tint_cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.5
		_tint_cache[k] = m
	return _tint_cache[k]

func _build_player() -> void:
	player = Node3D.new()
	player.name = "Player"
	var vis := _plane_mesh("player")
	vis.rotation.y = PI * 0.5 # 기수 +X 가정, -Z(적 방향)를 봄
	player.add_child(vis)
	add_child(player)

func _build_stars() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.85, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(50):
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.25, 0.25, 1.5)
		b.material = m
		mi.mesh = b
		mi.position = Vector3(rng.randf_range(-25, 25), rng.randf_range(-4, 14), rng.randf_range(-40, 20))
		add_child(mi)
		stars.append(mi)

func restart() -> void:
	for e in enemies:
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
	enemies.clear()
	for b in bolts:
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
	bolts.clear()
	for it in items:
		if is_instance_valid(it["node"]):
			(it["node"] as Node).queue_free()
	items.clear()
	score = 0
	stage = 1
	over = false
	won = false
	hp = 3
	power = 1
	fire_t = 0.5
	iframes = 0.0
	boss_ref = null
	player.position = Vector3(0, 4, PZ)
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	banner_label.visible = false
	boss_bar.visible = false
	boss_label.visible = false
	_start_stage(1)
	_refresh_ui()

func _start_stage(s: int) -> void:
	stage = s
	stage_t = 0.0
	stage_phase = "waves"
	spawn_queue.clear()
	# 웨이브 타임라인 (스테이지별 밀도 증가)
	var n := 10 + s * 6
	for i in range(n):
		var tt := 1.0 + float(i) * lerpf(2.2, 1.2, float(s - 1) / 2.0)
		var kind := "dart"
		var roll := rng.randf()
		if roll < 0.2 + 0.08 * float(s):
			kind = "shooter" if s >= 1 else "dart"
		elif roll < 0.45:
			kind = "gunship"
		spawn_queue.append({"t": tt, "kind": kind})
	_show_banner("STAGE %d" % s)

func _show_banner(t: String) -> void:
	banner_label.text = t
	banner_label.visible = true
	banner_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(banner_label.hide)

# ---------- 적 ----------

func _spawn_foe(kind: String, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	var vis := _plane_mesh(kind)
	vis.rotation.y = ENEMY_YAW
	root.add_child(vis)
	root.position = pos
	enemies_node.add_child(root)
	var d: Dictionary = FOE[kind]
	var hp0 := float(d["hp"]) * (1.0 + 0.25 * float(stage - 1))
	var e := {"node": root, "kind": kind, "hp": hp0, "maxhp": hp0, "speed": float(d["speed"]), "score": int(d["score"]), "r": float(d["r"]), "fire": float(d["fire"]), "fire_t": rng.randf_range(1.0, 2.0), "boss": kind.begins_with("boss"), "t": 0.0, "base_x": pos.x, "seed": rng.randf() * TAU, "pattern": str(d.get("pattern", ""))}
	enemies.append(e)
	return e

func _spawn_boss() -> void:
	var names := ["boss1", "boss2", "boss3"]
	var kind: String = names[mini(stage - 1, 2)]
	var e := _spawn_foe(kind, Vector3(0, 6, -14))
	boss_ref = e["node"]
	stage_phase = "boss"
	boss_bar.visible = true
	boss_label.visible = true
	_show_banner("WARNING")
	_play_sfx("warn", sfx_over, 0.8)

func _boss_pattern(e: Dictionary, dt: float) -> void:
	var node := e["node"] as Node3D
	e["t"] = float(e["t"]) + dt
	var kind := str(e["kind"])
	# 좌우 사인 기동
	node.position.x = clampf(float(e["base_x"]) + sin(float(e["t"]) * 0.7) * 6.0, -PX, PX)
	if node.position.z < -8.0:
		node.position.z += float(e["speed"]) * dt
	e["fire_t"] = float(e["fire_t"]) - dt
	if float(e["fire_t"]) > 0.0:
		return
	var pp := player.position
	if kind == "boss1":
		e["fire_t"] = 1.6
		_aimed_burst(node.global_position, pp, 3, 0.25, 11.0)
		if int(e.get("alt", 0)) % 2 == 0:
			_radial(node.global_position, 8, 9.0)
		e["alt"] = int(e.get("alt", 0)) + 1
	elif kind == "boss2":
		e["fire_t"] = 1.4
		_radial(node.global_position, 12, 10.0)
		_aimed_burst(node.global_position, pp, 5, 0.18, 12.0)
		e["adds"] = float(e.get("adds", 0.0)) + dt
		if float(e.get("adds", 0.0)) > 6.0 and enemies.size() < 12:
			e["adds"] = 0.0
			_spawn_foe("dart", node.global_position + Vector3(-3, 0, 2))
			_spawn_foe("dart", node.global_position + Vector3(3, 0, 2))
	else:
		e["fire_t"] = 0.5
		e["spin"] = float(e.get("spin", 0.0)) + 0.9
		for k in range(2):
			var a: float = float(e.get("spin", 0.0)) + PI * float(k)
			_enemy_bolt(node.global_position, Vector3(cos(a), 0, sin(a)).normalized() * 9.0)

func _aimed_burst(from: Vector3, target: Vector3, n: int, spread: float, spd: float) -> void:
	var base: Vector3 = (target - from).normalized()
	for i in range(n):
		var a := (float(i) - float(n - 1) * 0.5) * spread
		_enemy_bolt(from, base.rotated(Vector3.UP, a) * spd)

func _radial(from: Vector3, n: int, spd: float) -> void:
	for i in range(n):
		var a := TAU * float(i) / float(n)
		_enemy_bolt(from, Vector3(cos(a), 0, sin(a)) * spd)

func _enemy_bolt(pos: Vector3, vel: Vector3) -> void:
	_bolt(pos, vel, 1.0, 1, Color(1.0, 0.3, 0.3), 0.3)

func _player_bolt(pos: Vector3, vel: Vector3) -> void:
	_bolt(pos, vel, 1.0, 0, Color(0.4, 0.9, 1.0), 0.25)

func _bolt(pos: Vector3, vel: Vector3, dmg: float, team: int, col: Color, r: float) -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp.material = m
	mi.mesh = sp
	root.add_child(mi)
	root.position = pos
	bolts_node.add_child(root)
	bolts.append({"node": root, "vel": vel, "dmg": dmg, "team": team, "life": 4.0, "pierce": 0, "hit": []})

func _drop_item(pos: Vector3, force: String = "") -> void:
	var kind := force
	if kind == "":
		if rng.randf() > 0.08:
			return
		kind = "H" if (hp < 3 and rng.randf() < 0.35) else "P"
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 1.0, 0.4) if kind == "H" else Color(1.0, 0.85, 0.2)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	mi.mesh = sm
	root.add_child(mi)
	root.position = pos
	items_node.add_child(root)
	items.append({"node": root, "kind": kind})

# ---------- 프레임 ----------

func _physics_process(delta: float) -> void:
	if get_tree().paused or over or won:
		return
	_update_player(delta)
	_update_stage(delta)
	_update_enemies(delta)
	_update_bolts(delta)
	_update_items(delta)
	_update_stars(delta)
	_update_camera()
	_refresh_ui()

func _update_player(delta: float) -> void:
	if iframes > 0.0:
		iframes -= delta
	var sv: Vector2 = stick.value if stick != null else Vector2.ZERO
	var ax := touch.x + sv.x + Controls.axis_pressed("shmup", "left", "right")
	var ay := touch.y - sv.y + Controls.axis_pressed("shmup", "down", "up")
	var d := Vector3(clampf(ax, -1.0, 1.0), clampf(ay, -1.0, 1.0), 0.0)
	if d.length() > 1.0:
		d = d.normalized()
	player.position.x = clampf(player.position.x + d.x * 10.0 * delta, -PX, PX)
	player.position.y = clampf(player.position.y + d.y * 8.0 * delta, PY_MIN, PY_MAX)
	player.position.z = PZ
	player.rotation.z = lerpf(player.rotation.z, -d.x * 0.35, 1.0 - exp(-8.0 * delta))
	player.rotation.x = lerpf(player.rotation.x, d.y * 0.2, 1.0 - exp(-8.0 * delta))
	# 자동 발사
	fire_t -= delta
	if fire_t <= 0.0:
		fire_t = 0.16 if power >= 4 else 0.22
		_fire_power()
		_play_sfx("shoot", sfx_shoot, 1.0)

func _fire_power() -> void:
	var p := player.position + Vector3(0, 0, -1.5)
	var v := Vector3(0, 0, -30)
	if power == 1:
		_player_bolt(p, v)
	elif power == 2:
		_player_bolt(p + Vector3(-0.6, 0, 0), v)
		_player_bolt(p + Vector3(0.6, 0, 0), v)
	elif power == 3:
		_player_bolt(p, v)
		_player_bolt(p, v.rotated(Vector3.UP, 0.1))
		_player_bolt(p, v.rotated(Vector3.UP, -0.1))
	else:
		_player_bolt(p + Vector3(-0.6, 0, 0), v)
		_player_bolt(p + Vector3(0.6, 0, 0), v)
		_player_bolt(p, v.rotated(Vector3.UP, 0.08))
		_player_bolt(p, v.rotated(Vector3.UP, -0.08))

func _update_stage(delta: float) -> void:
	if stage_phase == "waves":
		stage_t += delta
		while not spawn_queue.is_empty() and float(spawn_queue[0]["t"]) <= stage_t:
			var s: Dictionary = spawn_queue.pop_front()
			_spawn_foe(str(s["kind"]), Vector3(rng.randf_range(-PX, PX), rng.randf_range(2.0, 8.0), -26.0))
		if spawn_queue.is_empty() and enemies.is_empty():
			stage_phase = "warn"
			boss_warn_t = 2.0
			_show_banner("BOSS")
	elif stage_phase == "warn":
		boss_warn_t -= delta
		if boss_warn_t <= 0.0:
			_spawn_boss()

func _update_enemies(delta: float) -> void:
	var pp := player.position
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		if not is_instance_valid(e["node"]):
			enemies.remove_at(i)
			continue
		var node := e["node"] as Node3D
		if bool(e.get("boss", false)):
			_boss_pattern(e, delta)
		else:
			node.position.z += float(e["speed"]) * delta
			node.position.x += sin(Time.get_ticks_msec() / 1000.0 + float(e.get("seed", 0.0))) * 1.5 * delta
			e["fire_t"] = float(e.get("fire_t", 0.0)) - delta
			if str(e.get("pattern", "")) != "" and float(e["fire_t"]) <= 0.0 and node.position.z > -20.0 and node.position.z < 6.0:
				e["fire_t"] = float(FOE[str(e["kind"])]["interval"])
				var from: Vector3 = node.global_position
				var aim: Vector3 = (pp - from).normalized()
				match str(e.get("pattern", "")):
					"aimed1":
						_enemy_bolt(from, aim * 10.0)
					"spread2":
						_aimed_burst(from, pp, 2, 0.22, 12.0)
					"spread3":
						_aimed_burst(from, pp, 3, 0.2, 11.0)
		# 화면 밖 제거
		if node.position.z > 16.0:
			node.queue_free()
			enemies.remove_at(i)
			continue
		# 플레이어 충돌
		if node.position.distance_to(pp) < 1.6 and iframes <= 0.0:
			_hurt_player()
			node.queue_free()
			enemies.remove_at(i)

func _update_bolts(delta: float) -> void:
	for bi in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[bi]
		if not is_instance_valid(b["node"]):
			bolts.remove_at(bi)
			continue
		var node := b["node"] as Node3D
		node.global_position += (b["vel"] as Vector3) * delta
		b["life"] = float(b["life"]) - delta
		var dead := float(b["life"]) <= 0.0 or absf(node.position.x) > 30.0 or absf(node.position.y) > 20.0 or node.position.z < -40.0 or node.position.z > 20.0
		if not dead:
			if int(b["team"]) == 0:
				for e in enemies.duplicate():
					if not is_instance_valid(e["node"]):
						continue
					var en := e["node"] as Node3D
					var dd: Vector3 = node.global_position - en.global_position
					var er: float = (1.2 if bool(e.get("boss", false)) else 0.9) + 0.35
					if Vector2(dd.x, dd.z).length() < er and absf(dd.y) < 1.6:
						e["hp"] = float(e["hp"]) - float(b["dmg"])
						dead = true
						if float(e["hp"]) <= 0.0:
							_kill_foe(e)
						break
			else:
				if node.global_position.distance_to(player.position) < 0.9 and iframes <= 0.0:
					dead = true
					_hurt_player()
		if dead:
			node.queue_free()
			bolts.remove_at(bi)

func _update_items(delta: float) -> void:
	for ii in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[ii]
		if not is_instance_valid(it["node"]):
			items.remove_at(ii)
			continue
		var node := it["node"] as Node3D
		node.position.z += 3.0 * delta
		node.rotation.y += 3.0 * delta
		var d: float = node.position.distance_to(player.position)
		if d < 3.0:
			node.position = node.position.move_toward(player.position, 10.0 * delta)
		if d < 1.3:
			if str(it["kind"]) == "P":
				power = mini(4, power + 1)
			else:
				hp = mini(3, hp + 1)
			_play_sfx("item", sfx_item, 1.0)
			node.queue_free()
			items.remove_at(ii)
		elif node.position.z > 16.0:
			node.queue_free()
			items.remove_at(ii)

func _update_stars(delta: float) -> void:
	for s in stars:
		(s as Node3D).position.z += 12.0 * delta
		if (s as Node3D).position.z > 20.0:
			(s as Node3D).position.z = -40.0

func _update_camera() -> void:
	cam.position = player.position + Vector3(0, 4.5, 9.5)
	cam.look_at(player.position + Vector3(0, 1.0, -6.0))

func _kill_foe(e: Dictionary) -> void:
	score += int(e["score"])
	_play_sfx("kill", sfx_kill, 1.0)
	_drop_item((e["node"] as Node3D).global_position)
	if bool(e.get("boss", false)):
		boss_bar.visible = false
		boss_label.visible = false
		boss_ref = null
		_drop_item((e["node"] as Node3D).global_position + Vector3(-1, 0, 0), "H")
		if stage >= 3:
			won = true
			over = true
			_play_sfx("win", sfx_win, 1.0)
			if score > best:
				best = score
				_save_best()
			msg_label.text = "STAGE ALL CLEAR! %d점" % score
			msg_panel.visible = true
		else:
			_start_stage(stage + 1)
	(e["node"] as Node).queue_free()
	enemies.erase(e)

func _hurt_player() -> void:
	if iframes > 0.0:
		return
	hp -= 1
	iframes = 1.5
	_play_sfx("hurt", sfx_hurt, 1.0)
	if hp <= 0:
		over = true
		_play_sfx("over", sfx_over, 1.0)
		if score > best:
			best = score
			_save_best()
		msg_label.text = "격추! STAGE %d %d점 (R: 재시작)" % [stage, score]
		msg_panel.visible = true

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("game", "best_shmup", best)
	cfg.save(SAVE_PATH)

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
	score_label.text = "점수: %d" % score
	best_label.text = "최고: %d" % best
	stage_label.text = "STAGE %d/3" % stage
	for i in range(3):
		(hp_hearts[i] as TextureRect).texture = heart_full_tex if hp > i else heart_empty_tex
	if boss_ref != null and is_instance_valid(boss_ref):
		for e in enemies:
			if e["node"] == boss_ref:
				boss_bar.max_value = float(e.get("maxhp", 100.0))
				boss_bar.value = float(e.get("hp"))
				boss_label.text = "BOSS"
				break
