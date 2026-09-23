extends Node3D
## 쿼터뷰 뱀파이어 서바이버: 5분 생존. 자동 공격 + 이동 회피 + 레벨업 강화.
## 물리 없이 전부 키네마틱 (결정적, 테스트 용이)

const ARENA := 50.0
const SPAWN_R := 22.0
const ENEMY_CAP := 70
# 타일 톤다운 (노란기·밝기 완화): 임포트 머티리얼 복제 후 albedo 승산
const TILE_TINT := Color(0.72, 0.74, 0.76)

var survive_time := 300.0
var t := 0.0
var score_kills := 0
var over := false
var won := false
var upgrading := false
var last_sfx := ""
const SAVE_PATH := "user://g2048.cfg"
var best := 0

var player: Node3D
var enemies: Array = []
var bolts: Array = [] # {node, vel, dmg, pierce, team, life, homing, hit}
var gems: Array = [] # {node, value}
var _dying: Array = []
var _spawn_t := 0.0
var _up_options: Array = []
var _up_stacks := {}
var stage := 1
var stage_t := 0.0
var stage_phase := "waves" # waves -> warn -> boss
var spawn_queue: Array = []
var boss_ref: Node = null
var boss_warn_t := 0.0
var _player_dying := false
var _player_death_t := 0.0
var _mesh_cache := {}
var rng := RandomNumberGenerator.new()

const SurvivorPlayerScript := preload("res://scripts/survivor_player.gd")
const SurvivorEnemyScript := preload("res://scripts/survivor_enemy.gd")

@onready var enemies_node: Node3D = $Enemies
@onready var bolts_node: Node3D = $Bolts
@onready var gems_node: Node3D = $Gems
@onready var cam: Camera3D = $Camera3D
@onready var hp_bar_img: TextureRect = $UI/HpBarImg
@onready var xp_bar_img: TextureRect = $UI/XpBarImg
@onready var timer_label: Label = $UI/TimerLabel
@onready var level_label: Label = $UI/LevelLabel
@onready var kill_label: Label = $UI/KillLabel
@onready var banner_label: Label = $UI/BannerLabel
@onready var boss_bar_img: TextureRect = $UI/BossBarImg
var _health_imgs: Array = []
var _mana_imgs: Array = []
@onready var msg_panel: PanelContainer = $UI/MsgPanel
@onready var msg_label: Label = $UI/MsgPanel/VBox/MsgLabel
@onready var restart_btn: Button = $UI/MsgPanel/VBox/RestartButton
@onready var up_panel: PanelContainer = $UI/UpgradePanel
@onready var pause_btn: Button = $UI/PauseButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var continue_btn: Button = $UI/PausePanel/VBox/ContinueButton
@onready var menu_btn: Button = $UI/PausePanel/VBox/MenuButton
@onready var mobile_pad: Control = $UI/MobilePad
@onready var sfx_shoot: AudioStreamPlayer = $SfxShoot
@onready var sfx_kill: AudioStreamPlayer = $SfxKill
@onready var sfx_level: AudioStreamPlayer = $SfxLevel
@onready var sfx_pick: AudioStreamPlayer = $SfxPick
@onready var sfx_hurt: AudioStreamPlayer = $SfxHurt
@onready var sfx_win: AudioStreamPlayer = $SfxWin
@onready var sfx_over: AudioStreamPlayer = $SfxOver
@onready var sfx_restart: AudioStreamPlayer = $SfxRestart

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene($UI)
	for i in range(9):
		_health_imgs.append(load("res://assets/pxui/bars/bar_health_8seg_%dfilled.png" % i))
		_mana_imgs.append(load("res://assets/pxui/bars/bar_mana_8seg_%dfilled.png" % i))
	rng.randomize()
	_build_floor()
	var cfg0 := ConfigFile.new()
	if cfg0.load(SAVE_PATH) == OK:
		best = int(cfg0.get_value("game", "best_surv", 0))
	restart_btn.pressed.connect(_on_restart_button)
	pause_btn.pressed.connect(pause_game)
	continue_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_button)
	for i in range(3):
		var b: Button = $UI/UpgradePanel/VBox.get_node("UpBtn" + str(i)) as Button
		b.pressed.connect(_apply_upgrade.bind(i))
	mobile_pad.visible = AudioSetup.mobile_enabled()
	_wire_mobile()
	restart()

func restart() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for e in _dying:
		if is_instance_valid(e):
			e.queue_free()
	_dying.clear()
	for b in bolts:
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
	bolts.clear()
	for gm in gems:
		if is_instance_valid(gm["node"]):
			(gm["node"] as Node).queue_free()
	gems.clear()
	if player != null and is_instance_valid(player):
		player.queue_free()
	t = 0.0
	score_kills = 0
	over = false
	won = false
	upgrading = false
	_player_dying = false
	_player_death_t = 0.0
	_up_stacks.clear()
	boss_ref = null
	_spawn_t = 0.5
	player = SurvivorPlayerScript.new()
	player.name = "Player"
	player.setup(SurvivorSetup.selected)
	player.global_position = Vector3.ZERO
	add_child(player)
	get_tree().paused = false
	msg_panel.visible = false
	pause_panel.visible = false
	up_panel.visible = false
	_start_stage(1)
	_refresh_ui()

# ---------- 바닥 (육각 타일 MultiMesh) ----------

func _collect_meshes(n: Node, acc: Transform3D, out: Array) -> void:
	var tt: Transform3D = acc * n.transform
	if n is MeshInstance3D:
		out.append({"mesh": (n as MeshInstance3D).mesh, "local": tt})
	for c in n.get_children():
		_collect_meshes(c, tt, out)

func _mesh_entries(path: String) -> Array:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var out := []
	var packed: PackedScene = load(path)
	if packed != null:
		var tmp: Node = packed.instantiate()
		_collect_meshes(tmp, Transform3D.IDENTITY, out)
		tmp.queue_free()
	_mesh_cache[path] = out
	_tint_entries(out)
	return out

func _tint_entries(entries: Array) -> void:
	for entry in entries:
		var mesh := entry["mesh"] as Mesh
		if mesh == null or mesh.has_meta("tinted"):
			continue
		mesh.set_meta("tinted", true)
		for si in range(mesh.get_surface_count()):
			var sm := mesh.surface_get_material(si)
			if sm is StandardMaterial3D:
				var dm := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
				dm.albedo_color = TILE_TINT
				mesh.surface_set_material(si, dm)

func _build_floor() -> void:
	var frng := RandomNumberGenerator.new()
	frng.seed = 4242
	var ponds := [Vector3(-14, 0, -10), Vector3(16, 0, 8), Vector3(2, 0, 20)]
	var placements := {}
	for q in range(-32, 33):
		for r in range(-32, 33):
			var wx := 2.0 * (float(q) + float(r) * 0.5)
			var wz := 1.732 * float(r)
			if absf(wx) > 55.0 or absf(wz) > 55.0:
				continue
			var kind := "res://assets/surv/hex/hex_grass.gltf"
			var rot := 0.0
			for pd in ponds:
				if Vector2(wx - pd.x, wz - pd.z).length() < 4.5:
					kind = "res://assets/surv/hex/hex_water.gltf"
			if kind.ends_with("hex_grass.gltf") and frng.randf() < 0.09:
				var letters := ["A", "B", "C", "D", "E"]
				kind = "res://assets/surv/hex/hex_road_" + letters[frng.randi_range(0, 4)] + ".gltf"
				rot = float(frng.randi_range(0, 5)) * PI / 3.0
			if not placements.has(kind):
				placements[kind] = []
			(placements[kind] as Array).append(Transform3D(Basis(Vector3.UP, rot), Vector3(wx, 0, wz)))
	var map_aabb := AABB(Vector3(-60, -2, -60), Vector3(120, 8, 120))
	for kind in placements.keys():
		for entry in _mesh_entries(str(kind)):
			var cells: Array = placements[kind]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = entry["mesh"]
			mm.instance_count = cells.size()
			for i in range(cells.size()):
				mm.set_instance_transform(i, (cells[i] as Transform3D) * (entry["local"] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.custom_aabb = map_aabb
			add_child(mmi)

# ---------- 전투 중재 ----------

func nearest_enemy(pos: Vector3, max_range: float) -> Vector3:
	var best_d := max_range
	var best := Vector3(9999, 0, 0)
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = pos.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = (e as Node3D).global_position
	return best

func melee_hit(_player: Node3D, dir: Vector3, st: Dictionary) -> void:
	var count: int = int(st["count"])
	for i in range(count):
		var a := (float(i) - float(count - 1) * 0.5) * 0.35
		var d := dir.rotated(Vector3.UP, a)
		for e in enemies.duplicate():
			if not is_instance_valid(e):
				continue
			var to: Vector3 = (e as Node3D).global_position - _player.global_position
			to.y = 0.0
			if to.length() > float(st["range"]) + float((e as Node).get("radius")):
				continue
			var ang := rad_to_deg(acos(clampf(d.normalized().dot(to.normalized()), -1.0, 1.0))) if to.length() > 0.05 else 0.0
			if ang <= float(st["arc"]) * 0.5:
				_damage_enemy(e, float(st["dmg"]), _player.global_position, float(st.get("knock", 0.4)))

func spawn_bolts(_player: Node3D, dir: Vector3, st: Dictionary) -> void:
	var count: int = int(st["count"])
	for i in range(count):
		var a := (float(i) - float(count - 1) * 0.5) * 0.12
		var d := dir.rotated(Vector3.UP, a)
		_spawn_bolt(_player.global_position + Vector3(0, 1.2, 0) + d * 0.6, d * float(st["pspeed"]), float(st["dmg"]), int(st["pierce"]), 0, float(st["range"]) / float(st["pspeed"]), st.get("homing", false) == true, Color(0.4, 0.9, 1.0))
	_play_sfx("shoot", sfx_shoot, 1.0)

func spawn_enemy_bolt(pos: Vector3, dir: Vector3) -> void:
	_spawn_bolt(pos, dir * 9.0, 8.0, 0, 1, 2.5, false, Color(0.9, 0.3, 0.9))

func _spawn_bolt(pos: Vector3, vel: Vector3, dmg: float, pierce: int, team: int, life: float, homing: bool, col: Color) -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.22 if team == 0 else 0.3
	sp.height = 0.44 if team == 0 else 0.6
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp.material = m
	mi.mesh = sp
	root.add_child(mi)
	root.position = pos
	bolts_node.add_child(root)
	bolts.append({"node": root, "vel": vel, "dmg": dmg, "pierce": pierce, "team": team, "life": life, "homing": homing, "hit": []})

func _damage_enemy(e: Node, dmg: float, from: Vector3, knock: float) -> void:
	if not is_instance_valid(e) or (e as Node).get("dying") == true:
		return
	var dead: bool = (e as Node).call("take_hit", dmg, from, knock)
	if dead:
		_start_death(e)
	else:
		(e as Node).set("hurt_t", 0.25)

func _start_death(e: Node) -> void:
	enemies.erase(e)
	score_kills += 1
	_spawn_gem((e as Node3D).global_position, int((e as Node).get("xp_value")))
	_play_sfx("kill", sfx_kill, 1.0)
	var etype := str((e as Node).get("type"))
	if etype.begins_with("boss"):
		if stage >= 3:
			won = true
			over = true
			_play_sfx("win", sfx_win, 1.0)
			if score_kills > best:
				best = score_kills
				var cfg := ConfigFile.new()
				cfg.load(SAVE_PATH)
				cfg.set_value("game", "best_surv", best)
				cfg.save(SAVE_PATH)
			msg_label.text = "3 스테이지 클리어! %d킬" % score_kills
			msg_panel.visible = true
		else:
			_start_stage(stage + 1)
	(e as Node).set("dying", true)
	var clip := "gen/Death_A" if rng.randf() < 0.5 else "gen/Death_B"
	var ap: AnimationPlayer = (e as Node).get("anim")
	if ap.has_animation(clip):
		(e as Node).set("death_t", (ap.get_animation(clip) as Animation).length)
		ap.play(clip, 0.1)
	else:
		(e as Node).set("death_t", 0.3)
	_dying.append(e)

func _spawn_gem(pos: Vector3, value: int) -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 1.0, 0.4)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	mi.mesh = sm
	root.add_child(mi)
	root.position = pos + Vector3(0, 0.4, 0)
	gems_node.add_child(root)
	gems.append({"node": root, "value": value})

# ---------- 스폰 ----------

func _spawn_enemy() -> void:
	_spawn_enemy_at(_pick_type(), Vector3.ZERO, true)

func _pick_type() -> String:
	var roll := rng.randf()
	var ttype := "minion"
	if t > 150.0 and roll < 0.15:
		ttype = "mage"
	elif t > 100.0 and roll < 0.38:
		ttype = "warrior"
	elif t > 45.0 and roll < 0.62:
		ttype = "rogue"
	return ttype

## 테스트용: 지정 타입을 지정 위치에 (ring=false면 그대로)
func _spawn_enemy_forced(ttype: String, pos: Vector3) -> Node:
	return _spawn_enemy_at(ttype, pos, false)

func _spawn_enemy_at(ttype: String, pos: Vector3, use_ring: bool) -> Node:
	var e: Node = SurvivorEnemyScript.new()
	(e as Node).call("setup", ttype, 1.0 + t / 75.0)
	var p := pos
	if use_ring:
		var a := rng.randf() * TAU
		p = player.global_position + Vector3(cos(a), 0, sin(a)) * SPAWN_R
		p.x = clampf(p.x, -ARENA + 2.0, ARENA - 2.0)
		p.z = clampf(p.z, -ARENA + 2.0, ARENA - 2.0)
		p.y = 0.0
	(e as Node3D).global_position = p
	enemies_node.add_child(e)
	enemies.append(e)
	return e

# ---------- 스테이지 (3탄 + 보스) ----------

func _start_stage(s: int) -> void:
	stage = s
	stage_t = 0.0
	stage_phase = "waves"
	spawn_queue.clear()
	boss_ref = null
	var n := 10 + s * 6
	for i in range(n):
		var tt := 1.0 + float(i) * lerpf(2.2, 1.2, float(s - 1) / 2.0)
		spawn_queue.append({"t": tt, "kind": _pick_stage_type(s)})
	_show_banner("STAGE %d" % s)

func _pick_stage_type(s: int) -> String:
	var roll := rng.randf()
	if s >= 3 and roll < 0.12:
		return "mage"
	if s >= 2 and roll < 0.3:
		return "rogue" if roll < 0.18 else "warrior"
	if roll < 0.25:
		return "gunship" if s >= 2 else "minion"
	if roll < 0.45:
		return "shooter" if t > 30.0 else "minion"
	return "minion"

func _show_banner(t: String) -> void:
	banner_label.text = t
	banner_label.visible = true
	banner_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(banner_label.hide)

func _spawn_boss() -> void:
	var names := ["boss1", "boss2", "boss3"]
	var kind: String = names[mini(stage - 1, 2)]
	var e := _spawn_enemy_forced(kind, Vector3(0, 0, -16))
	boss_ref = e
	stage_phase = "boss"
	_show_banner("WARNING")
	_play_sfx("warn", sfx_over, 0.8)

func _boss_pattern(e: Node, dt: float) -> void:
	var node := e as Node3D
	var kind := str(e.get("type"))
	e.set("shoot_cd", float(e.get("shoot_cd")) - dt)
	var pp := player.global_position
	var fw: Vector3 = (pp - node.global_position)
	fw.y = 0.0
	fw = fw.normalized() if fw.length() > 0.05 else Vector3(0, 0, 1)
	if kind == "boss1":
		if float(e.get("shoot_cd")) <= 0.0:
			e.set("shoot_cd", 1.8)
			_aimed_burst(node.global_position + Vector3(0, 1.5, 0), pp, 3, 0.25)
			e.set("alt", int(e.get("alt")) + 1)
			if int(e.get("alt")) % 2 == 0:
				_radial(node.global_position + Vector3(0, 1.5, 0), 8)
	elif kind == "boss2":
		if float(e.get("shoot_cd")) <= 0.0:
			e.set("shoot_cd", 1.6)
			_radial(node.global_position + Vector3(0, 1.5, 0), 12)
			_aimed_burst(node.global_position + Vector3(0, 1.5, 0), pp, 5, 0.18)
		e.set("adds", float(e.get("adds")) + dt)
		if float(e.get("adds")) > 7.0 and enemies.size() < 40:
			e.set("adds", 0.0)
			_spawn_enemy_forced("minion", node.global_position + Vector3(-3, 0, 2))
			_spawn_enemy_forced("minion", node.global_position + Vector3(3, 0, 2))
	else:
		e.set("spin", float(e.get("spin")) + dt * 2.2)
		e.set("tick", float(e.get("tick")) + dt)
		if float(e.get("tick")) > 0.35:
			e.set("tick", 0.0)
			e.set("shoot_cd", 1.0)
			for k in range(2):
				var a: float = float(e.get("spin")) + PI * float(k)
				spawn_enemy_bolt(node.global_position + Vector3(0, 1.5, 0), Vector3(cos(a), 0, sin(a)) * 9.0)
		if float(e.get("shoot_cd")) <= 0.0:
			_radial(node.global_position + Vector3(0, 1.5, 0), 16)

func _aimed_burst(from: Vector3, target: Vector3, n: int, spread: float) -> void:
	var base: Vector3 = target - from
	base.y = 0.0
	base = base.normalized() if base.length() > 0.05 else Vector3(0, 0, 1)
	for i in range(n):
		var a := (float(i) - float(n - 1) * 0.5) * spread
		spawn_enemy_bolt(from, base.rotated(Vector3.UP, a) * 11.0)

func _radial(from: Vector3, n: int) -> void:
	for i in range(n):
		var a := TAU * float(i) / float(n)
		spawn_enemy_bolt(from, Vector3(cos(a), 0, sin(a)) * 9.0)

# ---------- 업그레이드 ----------

func _stack(id: String) -> int:
	return int(_up_stacks.get(id, 0))

func build_options() -> Array:
	var opts := []
	var wkind: String = str(SurvivorSetup.WEAPONS[str(SurvivorSetup.CHARS[str(player.get("char_id"))]["weapon"])]["kind"])
	if _stack("w_dmg") < 5:
		opts.append({"id": "w_dmg", "label": "무기 강화", "desc": "무기 피해 +30%"})
	if _stack("w_rate") < 5:
		opts.append({"id": "w_rate", "label": "연사 강화", "desc": "공격 간격 -15%"})
	if _stack("w_multi") < 3:
		opts.append({"id": "w_multi", "label": "확산 강화" if wkind == "proj" else "범위 확대", "desc": "+1 투사체" if wkind == "proj" else "범위+거리 증가"})
	if wkind == "proj" and _stack("w_pierce") < 3:
		opts.append({"id": "w_pierce", "label": "관통 강화", "desc": "관통 +1"})
	if _stack("might") < 5:
		opts.append({"id": "might", "label": "힘", "desc": "모든 피해 +12%"})
	if _stack("swift") < 3:
		opts.append({"id": "swift", "label": "신속", "desc": "이동 속도 +8%"})
	if _stack("vitality") < 3:
		opts.append({"id": "vitality", "label": "체력", "desc": "최대 체력 +25, 회복"})
	if _stack("magnet") < 3:
		opts.append({"id": "magnet", "label": "자석", "desc": "획득 범위 +40%"})
	if _stack("regen") < 3:
		opts.append({"id": "regen", "label": "재생", "desc": "초당 +0.6 회복"})
	if _stack("armor") < 3:
		opts.append({"id": "armor", "label": "갑옷", "desc": "받는 피해 -2"})
	while opts.size() > 3:
		opts.remove_at(rng.randi_range(0, opts.size() - 1))
	return opts

const UP_ICONS := {
	"w_dmg": "res://assets/pxui/icons/icon_sword.png",
	"w_rate": "res://assets/pxui/icons/icon_bow.png",
	"vitality": "res://assets/pxui/icons/icon_potion.png",
	"armor": "res://assets/pxui/icons/icon_armor.png",
	"swift": "res://assets/pxui/icons/icon_boots.png",
}

func _offer_upgrades() -> void:
	upgrading = true
	get_tree().paused = true
	_up_options = build_options()
	for i in range(3):
		var b: Button = $UI/UpgradePanel/VBox.get_node("UpBtn" + str(i)) as Button
		if i < _up_options.size():
			b.visible = true
			var o: Dictionary = _up_options[i]
			b.text = "[%d] %s\n%s" % [i + 1, str(o["label"]), str(o["desc"])]
			if UP_ICONS.has(str(o["id"])):
				b.icon = load(str(UP_ICONS[str(o["id"])])) as Texture2D
			else:
				b.icon = null
		else:
			b.visible = false
	up_panel.visible = true

func _apply_upgrade(i: int) -> void:
	if not upgrading or i < 0 or i >= _up_options.size():
		return
	var o: Dictionary = _up_options[i]
	var id := str(o["id"])
	_up_stacks[id] = _stack(id) + 1
	match id:
		"w_dmg":
			player.set("w_dmg_mul", float(player.get("w_dmg_mul")) * 1.3)
		"w_rate":
			player.set("w_cd_mul", float(player.get("w_cd_mul")) * 0.85)
		"w_multi":
			var wkind: String = str(SurvivorSetup.WEAPONS[str(SurvivorSetup.CHARS[str(player.get("char_id"))]["weapon"])]["kind"])
			if wkind == "proj":
				player.set("w_count", int(player.get("w_count")) + 1)
			else:
				player.set("w_arc_bonus", float(player.get("w_arc_bonus")) + 40.0)
				player.set("w_range_mul", float(player.get("w_range_mul")) * 1.15)
		"w_pierce":
			player.set("w_pierce", int(player.get("w_pierce")) + 1)
		"might":
			player.set("might", float(player.get("might")) * 1.12)
		"swift":
			player.set("speed", float(player.get("speed")) * 1.08)
		"vitality":
			player.set("max_hp", float(player.get("max_hp")) + 25.0)
			player.call("heal_full")
		"magnet":
			player.set("magnet_r", float(player.get("magnet_r")) * 1.4)
		"regen":
			player.set("regen", float(player.get("regen")) + 0.6)
		"armor":
			player.set("armor", float(player.get("armor")) + 2.0)
	_play_sfx("pick", sfx_pick, 1.0)
	upgrading = false
	get_tree().paused = false
	up_panel.visible = false
	if player.get("xp") >= player.get("xp_need"):
		player.set("xp", int(player.get("xp")) - int(player.get("xp_need")))
		player.set("level", int(player.get("level")) + 1)
		player.set("xp_need", 6 + int(player.get("level")) * 5)
		_offer_upgrades()
	_refresh_ui()

# ---------- 프레임 ----------

func _physics_process(delta: float) -> void:
	if get_tree().paused or over or won or player == null or not is_instance_valid(player):
		return
	t += delta
	if t >= survive_time:
		won = true
		over = true
		_play_sfx("win", sfx_win, 1.0)
		msg_label.text = "생존 성공! %d킬" % score_kills
		msg_panel.visible = true
		return
	if not _player_dying:
		player.call("update_alive", delta, self)
	else:
		_player_death_t -= delta
		if _player_death_t <= 0.0:
			_player_die()
			return
	cam.position = player.global_position + Vector3(0, 17, 11)
	# 스테이지 진행
	if stage_phase == "waves":
		stage_t += delta
		while not spawn_queue.is_empty() and float(spawn_queue[0]["t"]) <= stage_t:
			var s: Dictionary = spawn_queue.pop_front()
			_spawn_enemy_at(str(s["kind"]), Vector3.ZERO, true)
		if spawn_queue.is_empty() and enemies.is_empty():
			stage_phase = "warn"
			boss_warn_t = 2.0
			_show_banner("BOSS")
	elif stage_phase == "warn":
		boss_warn_t -= delta
		if boss_warn_t <= 0.0:
			_spawn_boss()
	_update_enemies(delta)
	_update_bolts(delta)
	_update_gems(delta)
	_update_dying(delta)
	_refresh_ui()

func _update_dying(delta: float) -> void:
	for i in range(_dying.size() - 1, -1, -1):
		var e: Node = _dying[i]
		if not is_instance_valid(e):
			_dying.remove_at(i)
			continue
		e.set("death_t", float(e.get("death_t")) - delta)
		if float(e.get("death_t")) <= 0.0:
			e.queue_free()
			_dying.remove_at(i)

func _update_enemies(delta: float) -> void:
	var pp: Vector3 = player.global_position
	# 분리 (O(n^2), n<=70)
	for i in range(enemies.size()):
		var a: Node = enemies[i]
		if not is_instance_valid(a):
			continue
		(a as Node).set("hit_cd", maxf(0.0, float((a as Node).get("hit_cd")) - delta))
		var pa: Vector3 = (a as Node3D).global_position
		for j in range(i + 1, enemies.size()):
			var b: Node = enemies[j]
			if not is_instance_valid(b):
				continue
			var pb: Vector3 = (b as Node3D).global_position
			var d := pa - pb
			d.y = 0.0
			var dist := d.length()
			if dist > 0.01 and dist < 1.2:
				var push := d.normalized() * (1.2 - dist) * 2.0 * delta
				(a as Node3D).global_position = pa + push
				(b as Node3D).global_position = pb - push
				pa = (a as Node3D).global_position
	for e in enemies.duplicate():
		if not is_instance_valid(e):
			continue
		var en := e as Node3D
		var to: Vector3 = pp - en.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.05:
			en.global_position += to.normalized() * float(e.get("speed")) * delta
			(e.get("model") as Node3D).rotation.y = lerp_angle((e.get("model") as Node3D).rotation.y, atan2(to.x, to.z), 1.0 - exp(-10.0 * delta))
		# 스케일 팝 복구
		var base: float = float(e.get_meta("base_scl"))
		(e as Node3D).scale = (e as Node3D).scale.lerp(Vector3.ONE * base, 1.0 - exp(-8.0 * delta))
		# 상태 애니메이션: 공격 > 피격 > 걷기
		_enemy_anim(e, delta)
		# 접촉 피해
		if dist < float(e.get("radius")) + 0.5 and float(e.get("hit_cd")) <= 0.0 and not _player_dying:
			(e as Node).set("hit_cd", 1.0)
			(e as Node).set("atk_t", 0.45)
			(e as Node).set("atk_clip", "combat/Melee_Unarmed_Attack_Punch_A")
			if _hurt_player(float(e.get("dmg"))):
				return
			_play_sfx("hurt", sfx_hurt, 1.0)
		# 메이지 원거리
		if e.get("ranged") == true and dist < 14.0 and dist > 3.0:
			(e as Node).set("shoot_cd", float(e.get("shoot_cd")) - delta)
			if float(e.get("shoot_cd")) <= 0.0:
				(e as Node).set("shoot_cd", 2.6)
				(e as Node).set("atk_t", 0.6)
				(e as Node).set("atk_clip", "combat2/Ranged_Magic_Shoot")
				spawn_enemy_bolt(en.global_position + Vector3(0, 1.4, 0), to.normalized())
		# 보스 탄막
		if str(e.get("type")).begins_with("boss"):
			_boss_pattern(e, delta)
	for i in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[i]):
			enemies.remove_at(i)

func _update_bolts(delta: float) -> void:
	for bi in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[bi]
		if not is_instance_valid(b["node"]):
			bolts.remove_at(bi)
			continue
		var node := b["node"] as Node3D
		var vel: Vector3 = b["vel"]
		if b["homing"] == true:
			var tgt := nearest_enemy(node.global_position, 8.0)
			if tgt.x < 9000.0:
				var want: Vector3 = (tgt - node.global_position).normalized() * vel.length()
				vel = vel.lerp(want, 1.0 - exp(-4.0 * delta))
				b["vel"] = vel
		node.global_position += vel * delta
		node.global_position.y = clampf(node.global_position.y, 0.3, 4.0)
		b["life"] = float(b["life"]) - delta
		var dead := float(b["life"]) <= 0.0 or node.global_position.y <= 0.25
		if not dead:
			if int(b["team"]) == 0:
				for e in enemies.duplicate():
					if not is_instance_valid(e) or (b["hit"] as Array).has(e):
						continue
					if node.global_position.distance_to((e as Node3D).global_position + Vector3(0, 1.0, 0)) < float(e.get("radius")) + 0.35:
						(b["hit"] as Array).append(e)
						_damage_enemy(e, float(b["dmg"]), node.global_position, 0.3)
						b["pierce"] = int(b["pierce"]) - 1
						if int(b["pierce"]) < 0:
							dead = true
							break
			else:
				if node.global_position.distance_to(player.global_position + Vector3(0, 1.0, 0)) < 0.85:
					_hurt_player(float(b["dmg"]))
					_play_sfx("hurt", sfx_hurt, 1.0)
					dead = true
		if dead:
			node.queue_free()
			bolts.remove_at(bi)

func _update_gems(_delta: float) -> void:
	var pp: Vector3 = player.global_position
	var mr: float = float(player.get("magnet_r"))
	for gi in range(gems.size() - 1, -1, -1):
		var gm: Dictionary = gems[gi]
		if not is_instance_valid(gm["node"]):
			gems.remove_at(gi)
			continue
		var node := gm["node"] as Node3D
		node.rotation.y += 2.0 * _delta
		var d: float = node.global_position.distance_to(pp)
		if d < mr:
			node.global_position = node.global_position.move_toward(pp + Vector3(0, 0.6, 0), 14.0 * _delta)
			d = node.global_position.distance_to(pp)
		if d < 0.9:
			node.queue_free()
			gems.remove_at(gi)
			if player.call("gain_xp", int(gm["value"])):
				_play_sfx("level", sfx_level, 1.0)
				_offer_upgrades()
				return

func _enemy_anim(e: Node, delta: float) -> void:
	var ap: AnimationPlayer = e.get("anim")
	if ap == null:
		return
	var want := "move/Walking_A"
	if float(e.get("atk_t")) > 0.0:
		e.set("atk_t", float(e.get("atk_t")) - delta)
		want = str(e.get("atk_clip"))
	elif float(e.get("hurt_t")) > 0.0:
		e.set("hurt_t", float(e.get("hurt_t")) - delta)
		want = "gen/Hit_A"
	if ap.has_animation(want) and ap.current_animation != want:
		ap.play(want, 0.1)

## 플레이어 피격 (Hit 모션 + 사망 시퀀스). 사망이면 true
func _hurt_player(raw: float) -> bool:
	if _player_dying:
		return false
	var dead: bool = player.call("take_hit", raw)
	if dead:
		_player_dying = true
		_player_death_t = 1.2
		var pap: AnimationPlayer = player.get("anim")
		if pap.has_animation("gen/Death_A"):
			pap.play("gen/Death_A", 0.1)
		return false
	var pact: float = float(player.get("act_t"))
	if pact <= 0.0:
		var pap2: AnimationPlayer = player.get("anim")
		if pap2.has_animation("gen/Hit_A"):
			player.set("act_t", 0.3)
			player.set("act_clip", "gen/Hit_A")
			pap2.play("gen/Hit_A", 0.1)
	return false

func _player_die() -> void:
	over = true
	_play_sfx("over", sfx_over, 1.0)
	if score_kills > best:
		best = score_kills
		var cfg := ConfigFile.new()
		cfg.load(SAVE_PATH)
		cfg.set_value("game", "best_surv", best)
		cfg.save(SAVE_PATH)
	msg_label.text = "전사! %d킬 %d초 생존 (R: 재시작)" % [score_kills, int(t)]
	msg_panel.visible = true

# ---------- 입력/UI ----------

func _wire_mobile() -> void:
	var defs := {"MW": "w", "MA": "a", "MS": "s", "MD": "d"}
	for n in defs.keys():
		var b: Button = mobile_pad.get_node_or_null(n) as Button
		if b == null:
			continue
		b.button_down.connect(_on_touch.bind(str(defs[n]), true))
		b.button_up.connect(_on_touch.bind(str(defs[n]), false))

func _on_touch(dir: String, pressed: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var td: Vector2 = player.get("touch_dir")
	match dir:
		"w":
			td.y = -1.0 if pressed else 0.0
		"s":
			td.y = 1.0 if pressed else 0.0
		"a":
			td.x = -1.0 if pressed else 0.0
		"d":
			td.x = 1.0 if pressed else 0.0
	player.set("touch_dir", td)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_R:
		restart()
	elif k.physical_keycode == KEY_P:
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
	elif upgrading and k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_3:
		_apply_upgrade(int(k.physical_keycode) - int(KEY_1))

func pause_game() -> void:
	if over:
		return
	get_tree().paused = true
	pause_panel.visible = true

func resume_game() -> void:
	if upgrading:
		return
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

func _bar_idx(frac: float) -> int:
	return clampi(int(roundf(frac * 8.0)), 0, 8)

func _refresh_ui() -> void:
	hp_bar_img.texture = _health_imgs[_bar_idx(float(player.get("hp")) / float(player.get("max_hp")))]
	xp_bar_img.texture = _mana_imgs[_bar_idx(float(player.get("xp")) / float(player.get("xp_need")))]
	var mm := int(t) / 60
	var ss := int(t) % 60
	timer_label.text = "%d:%02d / 5:00" % [mm, ss]
	level_label.text = "Lv.%d" % int(player.get("level"))
	kill_label.text = "%d킬" % score_kills
	var boss_found := false
	for e in enemies:
		if e is Node and is_instance_valid(e) and str((e as Node).get("type")).begins_with("boss"):
			var fr: float = float(e.get("hp")) / float(e.get("max_hp"))
			boss_bar_img.visible = true
			boss_bar_img.texture = _health_imgs[_bar_idx(fr)]
			boss_found = true
			break
	if not boss_found:
		boss_bar_img.visible = false
