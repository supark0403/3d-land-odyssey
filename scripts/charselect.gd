extends Control
## 캐릭터 선택: 5종 정사각형 버튼 (이름 + 무기 + 특성)

@onready var grid: GridContainer = $Center/VBox/GridCenter/Grid
@onready var back_btn: Button = $Center/VBox/BackButton
@onready var click_player: AudioStreamPlayer = $ClickPlayer

const INFO := {
	"knight": "기사\n검·균형",
	"barbarian": "바바리안\n도끼·맷집",
	"ranger": "레인저\n활·신속",
	"mage": "메이지\n지팡이·관통",
	"rogue": "로그\n석궁·이속",
}

func _ready() -> void:
	AudioSetup.apply_volumes()
	UISkin.skin_scene(self)
	for cid in SurvivorSetup.ORDER:
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 180)
		b.add_theme_font_size_override("font_size", 26)
		b.text = str(INFO[cid])
		b.name = "Char_" + cid
		grid.add_child(b)
		b.pressed.connect(_on_pick.bind(cid))
	back_btn.pressed.connect(_on_back)

func _on_pick(cid: String) -> void:
	click_player.play()
	SurvivorSetup.selected = cid
	get_tree().change_scene_to_file("res://scenes/survivors.tscn")

func _on_back() -> void:
	click_player.play()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
