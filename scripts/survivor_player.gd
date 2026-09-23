extends Node3D
## 플레이어: 이동 + 체력/XP/레벨 + 무기 상태. 발사는 game이 적 목록으로 중재

var char_id := "knight"
var weapon_id := "sword"
var speed := 5.2
var max_hp := 100.0
var hp := 100.0
var level := 1
var xp := 0
var xp_need := 7
var magnet_r := 3.0
var might := 1.0
var regen := 0.0
var armor := 0.0
# 무기 강화 스탯
var w_dmg_mul := 1.0
var w_cd_mul := 1.0
var w_count := 1
var w_pierce := 0
var w_range_mul := 1.0
var w_arc_bonus := 0.0

var model: Node3D
var anim: AnimationPlayer
var vel := Vector3.ZERO
var touch_dir := Vector2.ZERO
var iframes := 0.0
var swing_cd := 0.0
var act_t := 0.0
var act_clip := ""
var rng := RandomNumberGenerator.new()

func setup(cid: String) -> void:
	char_id = cid
	var c: Dictionary = SurvivorSetup.CHARS[cid]
	weapon_id = str(c["weapon"])
	speed = float(c["speed"])
	max_hp = float(c["hp"])
	hp = max_hp
	rng.randomize()
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var body := (load(str(c["file"])) as PackedScene).instantiate() as Node3D
	model.add_child(body)
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	body.add_child(anim)
	_add_lib(SurvivorSetup.ANIM_MOVE, "move")
	_add_lib(SurvivorSetup.ANIM_GENERAL, "gen")
	_add_lib(SurvivorSetup.ANIM_COMBAT, "combat")
	_add_lib(SurvivorSetup.ANIM_RANGED, "combat2")
	for clip in ["move/Walking_A", "move/Running_A", "gen/Idle_A"]:
		if anim.has_animation(clip):
			(anim.get_animation(clip) as Animation).loop_mode = Animation.LOOP_LINEAR
	_attach_weapon(body)
	_play("gen/Idle_A")

func _add_lib(path: String, target: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	var src: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if src == null:
		inst.queue_free()
		return
	for lib_name in src.get_animation_library_list():
		if anim.has_animation_library(target):
			anim.remove_animation_library(target)
		anim.add_animation_library(target, src.get_animation_library(lib_name))
	inst.queue_free()

func _attach_weapon(body: Node3D) -> void:
	var skel := body.get_node_or_null("Rig_Medium/Skeleton3D") as Skeleton3D
	if skel == null:
		skel = body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var idx := skel.find_bone("hand.r")
	if idx < 0:
		return
	var w: Dictionary = SurvivorSetup.WEAPONS[weapon_id]
	var attach := BoneAttachment3D.new()
	attach.bone_idx = idx
	skel.add_child(attach)
	var item := (load(str(w["item"])) as PackedScene).instantiate() as Node3D
	item.rotation = w["rot"] as Vector3
	attach.add_child(item)

func weapon_stats() -> Dictionary:
	var w: Dictionary = SurvivorSetup.WEAPONS[weapon_id]
	return {
		"kind": str(w["kind"]), "dmg": float(w["dmg"]) * w_dmg_mul * might,
		"cd": float(w["cd"]) * w_cd_mul, "range": float(w["range"]) * w_range_mul,
		"arc": float(w["arc"]) + w_arc_bonus, "count": int(w["count"]) + w_count - 1,
		"pierce": int(w["pierce"]) + w_pierce, "pspeed": float(w["pspeed"]),
		"clip": str(w["clip"]), "homing": w.get("homing", false) == true,
		"knock": 1.4 if weapon_id == "axe" else 0.4,
	}

func gain_xp(v: int) -> bool:
	xp += v
	if xp >= xp_need:
		xp -= xp_need
		level += 1
		xp_need = 6 + level * 5
		return true
	return false

func heal_full() -> void:
	hp = max_hp

func take_hit(raw: float) -> bool:
	if iframes > 0.0:
		return false
	iframes = 0.6
	hp -= maxf(1.0, raw - armor)
	return hp <= 0.0

func _move_axis() -> Vector2:
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		x -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		y += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		y -= 1.0
	return Vector2(clampf(x + touch_dir.x, -1.0, 1.0), clampf(y + touch_dir.y, -1.0, 1.0))

func update_alive(delta: float, game: Node) -> void:
	if iframes > 0.0:
		iframes -= delta
	if regen > 0.0:
		hp = minf(max_hp, hp + regen * delta)
	if swing_cd > 0.0:
		swing_cd -= delta
	if act_t > 0.0:
		act_t -= delta
		if act_t <= 0.0:
			act_clip = ""
	var axis := _move_axis()
	var dir := Vector3(axis.x, 0.0, axis.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	global_position += dir * speed * delta
	global_position.x = clampf(global_position.x, -50.0, 50.0)
	global_position.z = clampf(global_position.z, -50.0, 50.0)
	var hspeed := dir.length() * speed
	if hspeed > 0.5:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-12.0 * delta))
	# 무기 발사
	if swing_cd <= 0.0:
		var st := weapon_stats()
		var target: Vector3 = game.nearest_enemy(global_position, float(st["range"]))
		if target.x < 9000.0:
			_fire(game, st, (target - global_position).normalized())
	# 애니메이션
	if act_t <= 0.0:
		var want := "gen/Idle_A"
		if hspeed > 0.5:
			want = "move/Walking_A"
		_play(want)

func _fire(game: Node, st: Dictionary, dir: Vector3) -> void:
	swing_cd = float(st["cd"])
	act_clip = str(st["clip"])
	if anim.has_animation(act_clip):
		act_t = minf(0.45, (anim.get_animation(act_clip) as Animation).length)
		anim.play(act_clip, 0.1)
	model.rotation.y = atan2(dir.x, dir.z)
	if str(st["kind"]) == "melee":
		game.melee_hit(self, dir, st)
	else:
		game.spawn_bolts(self, dir, st)

func _play(clip: String) -> void:
	if anim.current_animation != clip:
		anim.play(clip, 0.15)
