class_name VirtualStick
extends Control
## 가상 조이스틱: 드래그 방향·세기(-1~1)를 value로. y+ = 아래(화면 기준).

var value := Vector2.ZERO
var radius := 86.0

var _tid := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_tid = -2
				_drag(mb.position)
			elif _tid == -2:
				_release()
	elif event is InputEventMouseMotion:
		if _tid == -2:
			_drag((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_tid = st.index
			_drag(st.position)
		elif st.index == _tid:
			_release()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _tid:
			_drag(sd.position)

func _drag(p: Vector2) -> void:
	var d := p - size * 0.5
	if d.length() > radius:
		d = d.normalized() * radius
	value = d / radius
	queue_redraw()

func _release() -> void:
	_tid = -1
	value = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, radius + 16.0, Color(0.1, 0.14, 0.2, 0.55))
	draw_arc(c, radius + 16.0, 0.0, TAU, 48, Color(0.55, 0.9, 1.0, 0.8), 3.0)
	draw_circle(c + value * radius, 32.0, Color(0.35, 0.8, 0.9, 0.9))
	draw_arc(c + value * radius, 32.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.0)
