extends Node3D
## 마우스 궤도 카메라: 좌드래그 회전, 휠 줌 (기준면 고정이라 면 선택 없음)

@onready var yaw: Node3D = $Yaw
@onready var pitch: Node3D = $Yaw/Pitch
@onready var cam: Camera3D = $Yaw/Pitch/Camera3D

@export var start_yaw := 0.6
@export var start_pitch := -0.5
@export var start_dist := 9.5
var distance := 9.5
var _lmb := false
var _touching := false
var _touch_start := Vector2.ZERO
var _touch_moved := false

func _ready() -> void:
	yaw.rotation.y = start_yaw
	pitch.rotation.x = start_pitch
	distance = start_dist
	_apply_dist()

func _apply_dist() -> void:
	cam.position = Vector3(0, 0, distance)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_lmb = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance - 0.8, 5.5, 15.0)
			_apply_dist()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance + 0.8, 5.5, 15.0)
			_apply_dist()
	elif event is InputEventMouseMotion and _lmb:
		var mm := event as InputEventMouseMotion
		yaw.rotation.y -= mm.relative.x * 0.008
		pitch.rotation.x = clampf(pitch.rotation.x - mm.relative.y * 0.008, -1.45, 1.45)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touching = true
			_touch_moved = false
			_touch_start = st.position
		else:
			_touching = false
	elif event is InputEventScreenDrag and _touching:
		var sd := event as InputEventScreenDrag
		if (sd.position - _touch_start).length() > 8.0:
			_touch_moved = true
		if _touch_moved:
			yaw.rotation.y -= sd.relative.x * 0.008
			pitch.rotation.x = clampf(pitch.rotation.x - sd.relative.y * 0.008, -1.45, 1.45)
