class_name SurvivorSetup
extends RefCounted
## 캐릭터/무기/적 정의 + 선택 저장 (static은 씬 전환 후에도 유지)

static var selected := "knight"

const CHARS := {
	"knight": {"name": "기사", "file": "res://assets/surv/chars/Knight.glb", "speed": 5.2, "hp": 100.0, "weapon": "sword"},
	"barbarian": {"name": "바바리안", "file": "res://assets/surv/chars/Barbarian.glb", "speed": 4.6, "hp": 140.0, "weapon": "axe"},
	"ranger": {"name": "레인저", "file": "res://assets/surv/chars/Ranger.glb", "speed": 5.6, "hp": 80.0, "weapon": "bow"},
	"mage": {"name": "메이지", "file": "res://assets/surv/chars/Mage.glb", "speed": 5.0, "hp": 70.0, "weapon": "staff"},
	"rogue": {"name": "로그", "file": "res://assets/surv/chars/Rogue.glb", "speed": 6.0, "hp": 85.0, "weapon": "xbow"},
}
const ORDER := ["knight", "barbarian", "ranger", "mage", "rogue"]

# kind: melee=범위 타격 / proj=투사체
const WEAPONS := {
	"sword": {"label": "칼", "kind": "melee", "dmg": 14.0, "cd": 0.55, "range": 2.6, "arc": 100.0, "count": 1, "pierce": 0, "pspeed": 0.0, "clip": "combat/Melee_1H_Attack_Slice_Horizontal", "item": "res://assets/surv/weapons/sword_1handed.gltf", "rot": Vector3.ZERO},
	"axe": {"label": "도끼", "kind": "melee", "dmg": 26.0, "cd": 0.85, "range": 3.0, "arc": 140.0, "count": 1, "pierce": 0, "pspeed": 0.0, "clip": "combat/Melee_2H_Attack_Chop", "item": "res://assets/surv/weapons/axe_2handed.gltf", "rot": Vector3.ZERO},
	"bow": {"label": "활", "kind": "proj", "dmg": 9.0, "cd": 0.45, "range": 13.0, "arc": 0.0, "count": 1, "pierce": 0, "pspeed": 16.0, "clip": "combat2/Ranged_Bow_Release", "item": "res://assets/surv/weapons/bow_withString.gltf", "rot": Vector3(PI * 0.5, 0, 0)},
	"staff": {"label": "지팡이", "kind": "proj", "dmg": 16.0, "cd": 0.95, "range": 12.0, "arc": 0.0, "count": 1, "pierce": 2, "pspeed": 9.0, "clip": "combat2/Ranged_Magic_Shoot", "item": "res://assets/surv/weapons/staff.gltf", "rot": Vector3.ZERO, "homing": true},
	"xbow": {"label": "석궁", "kind": "proj", "dmg": 22.0, "cd": 1.15, "range": 14.0, "arc": 0.0, "count": 1, "pierce": 1, "pspeed": 20.0, "clip": "combat2/Ranged_1H_Shoot", "item": "res://assets/surv/weapons/crossbow_1handed.gltf", "rot": Vector3.ZERO},
}

const ENEMIES := {
	"minion": {"file": "res://assets/surv/enemies/Skeleton_Minion.glb", "hp": 18.0, "speed": 3.2, "dmg": 8.0, "xp": 1, "r": 0.55, "scl": 1.0},
	"rogue": {"file": "res://assets/surv/enemies/Skeleton_Rogue.glb", "hp": 10.0, "speed": 5.0, "dmg": 5.0, "xp": 1, "r": 0.5, "scl": 0.95},
	"warrior": {"file": "res://assets/surv/enemies/Skeleton_Warrior.glb", "hp": 55.0, "speed": 2.4, "dmg": 16.0, "xp": 3, "r": 0.65, "scl": 1.1},
	"mage": {"file": "res://assets/surv/enemies/Skeleton_Mage.glb", "hp": 26.0, "speed": 2.8, "dmg": 6.0, "xp": 2, "r": 0.55, "scl": 1.0},
	"boss1": {"file": "res://assets/surv/enemies/Skeleton_Warrior.glb", "hp": 150.0, "speed": 2.6, "dmg": 18.0, "xp": 12, "r": 1.0, "scl": 1.5, "tint": Color(1.0, 0.45, 0.4)},
	"boss2": {"file": "res://assets/surv/enemies/Skeleton_Mage.glb", "hp": 260.0, "speed": 2.4, "dmg": 22.0, "xp": 20, "r": 1.1, "scl": 1.7, "tint": Color(1.0, 0.65, 0.3)},
	"boss3": {"file": "res://assets/surv/enemies/Skeleton_Warrior.glb", "hp": 420.0, "speed": 2.6, "dmg": 26.0, "xp": 30, "r": 1.3, "scl": 2.0, "tint": Color(0.75, 0.5, 1.0)},
}

const ANIM_MOVE := "res://assets/surv/anims/Anim_MovementBasic.glb"
const ANIM_GENERAL := "res://assets/surv/anims/Anim_General.glb"
const ANIM_COMBAT := "res://assets/surv/anims/Anim_CombatMelee.glb"
const ANIM_RANGED := "res://assets/surv/anims/Anim_CombatRanged.glb"
