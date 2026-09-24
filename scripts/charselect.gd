extends Control
## 캐릭터 선택: 5종 정사각형 버튼 (이름 + 무기 + 특성)

@onready var grid: GridContainer = $Center/VBox/GridCenter/Grid
@onready var click_player: AudioStreamPlayer = $ClickPlayer

const INFO := {
	"knight": "기사\n검·균형",
	"barbarian": "바바리안\n도끼·맷집",
	"ranger": "레인저\n활·신속",
	"mage": "메이지\n지팡이·관통",
	"rogue": "로그\n석궁·이속",
}

var _models: Array = []

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene(self)
	for cid in SurvivorSetup.ORDER:
		grid.add_child(_make_cell(cid))

func _make_cell(cid: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(190, 270)
	b.text = ""
	b.name = "Char_" + cid
	UISkin.style_button(b)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 6)
	b.add_child(vb)
	var svc := SubViewportContainer.new()
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.stretch = true
	svc.custom_minimum_size = Vector2(170, 150)
	svc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.size = Vector2i(170, 150)
	svc.add_child(sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 1.0)
	e.ambient_light_energy = 0.9
	env.environment = e
	sv.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.6, 0.5, 0.0)
	sv.add_child(light)
	var cam := Camera3D.new()
	sv.add_child(cam)
	var model := (load("res://assets/surv/chars/" + cid.capitalize() + ".glb") as PackedScene).instantiate()
	sv.add_child(model)
	_fit_camera(cam, model)
	_models.append(model)
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.text = str(INFO[cid])
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 18)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(lab)
	b.pressed.connect(_on_pick.bind(cid))
	return b

func _fit_camera(cam: Camera3D, model: Node) -> void:
	var box := AABB()
	var has := false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_aabb()
		m = (mi as MeshInstance3D).global_transform * m
		box = m if not has else box.merge(m)
		has = true
	if not has:
		cam.position = Vector3(0, 1.0, 2.5)
		cam.look_at(Vector3(0, 0.8, 0))
		return
	var c := box.get_center()
	var s := box.size
	var dist := maxf(maxf(s.x, s.y), s.z) * 0.9 + 0.1
	cam.position = c + Vector3(0, s.y * 0.12, dist)
	cam.look_at(c)

func _process(delta: float) -> void:
	for m in _models:
		if is_instance_valid(m):
			(m as Node3D).rotate_y(delta * 0.8)

func _on_pick(cid: String) -> void:
	click_player.play()
	SurvivorSetup.selected = cid
	get_tree().change_scene_to_file("res://scenes/survivors.tscn")
