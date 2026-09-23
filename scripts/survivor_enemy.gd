extends Node3D
## 적: 추적 + 접촉 피해 + 원거리(메이지). 키네마틱 이동, 물리 없음

var type := "minion"
var hp := 18.0
var max_hp := 18.0
var speed := 3.2
var dmg := 8.0
var xp_value := 1
var radius := 0.55
var ranged := false
var shoot_cd := 0.0

var model: Node3D
var anim: AnimationPlayer
var hit_cd := 0.0
var hurt_t := 0.0
var atk_t := 0.0
var atk_clip := "combat/Melee_Unarmed_Attack_Punch_A"
var alt := 0
var adds := 0.0
var spin := 0.0
var tick := 0.0
var dying := false
var death_t := 0.0
var rng := RandomNumberGenerator.new()

func setup(t: String, hp_mul: float) -> void:
	type = t
	var d: Dictionary = SurvivorSetup.ENEMIES[t]
	max_hp = float(d["hp"]) * hp_mul
	hp = max_hp
	speed = float(d["speed"])
	dmg = float(d["dmg"])
	xp_value = int(d["xp"])
	radius = float(d["r"])
	ranged = (t == "mage")
	rng.randomize()
	var scl := float(d["scl"])
	scale = Vector3.ONE * scl
	set_meta("base_scl", scl)
	model = Node3D.new()
	add_child(model)
	var body := (load(str(d["file"])) as PackedScene).instantiate() as Node3D
	model.add_child(body)
	if d.has("tint"):
		var tm := StandardMaterial3D.new()
		tm.albedo_color = d["tint"]
		tm.roughness = 0.6
		var st := [self]
		while not st.is_empty():
			var nn: Node = st.pop_back()
			if nn is MeshInstance3D:
				(nn as MeshInstance3D).material_override = tm
			for cc in nn.get_children():
				st.append(cc)
	anim = AnimationPlayer.new()
	body.add_child(anim)
	_add_lib(SurvivorSetup.ANIM_MOVE, "move")
	_add_lib(SurvivorSetup.ANIM_GENERAL, "gen")
	_add_lib(SurvivorSetup.ANIM_COMBAT, "combat")
	_add_lib(SurvivorSetup.ANIM_RANGED, "combat2")
	for clip in ["move/Walking_A", "gen/Idle_A"]:
		if anim.has_animation(clip):
			(anim.get_animation(clip) as Animation).loop_mode = Animation.LOOP_LINEAR
	anim.play("move/Walking_A", 0.2)

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

func take_hit(dmg_amount: float, from: Vector3, knock: float) -> bool:
	hp -= dmg_amount
	var away := global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		global_position += away.normalized() * knock
	scale = Vector3.ONE * (float(SurvivorSetup.ENEMIES[type]["scl"]) * 1.15)
	return hp <= 0.0
