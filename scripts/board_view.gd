extends Node3D
## 4x4x4 보드 3D 렌더링: 타일 생성/갱신, 슬라이드·합체·스폰 애니메이션, 선택 면 하이라이트

const HALF := 2.0
const TILE := 0.92

const COLORS := {
	2: Color("eee4da"), 4: Color("ede0c8"), 8: Color("f2b179"),
	16: Color("f95c63"), 32: Color("f67c5f"), 64: Color("f65e3b"),
	128: Color("edcf72"), 256: Color("edcc61"), 512: Color("edc850"),
	1024: Color("edc53f"), 2048: Color("edc22e"),
}
const SUPER_COLOR := Color("3c3a32")

var tiles := {} # Vector3i -> Node3D
var _mats := {} # value -> StandardMaterial3D
var _select_frame: Node3D

static func cell_to_world(p: Vector3i) -> Vector3:
	return Vector3(float(p.x) - 1.5, float(p.y) - 1.5, float(p.z) - 1.5)

func _ready() -> void:
	_build_frame()
	_build_select_frame()

func _mat_for(v: int) -> StandardMaterial3D:
	if _mats.has(v):
		return _mats[v]
	var m := StandardMaterial3D.new()
	m.albedo_color = COLORS.get(v, SUPER_COLOR)
	m.roughness = 0.55
	_mats[v] = m
	return m

func _text_color_for(v: int) -> Color:
	return Color("776e65") if v <= 4 else Color("f9f6f2")

func _make_tile(v: int) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(TILE, TILE, TILE)
	box.material = _mat_for(v)
	mi.mesh = box
	root.add_child(mi)
	var tc := _text_color_for(v)
	for f in range(6):
		var lab := Label3D.new()
		lab.text = str(v)
		lab.font_size = 96 if v < 10000 else 72
		lab.pixel_size = 0.006
		lab.modulate = tc
		lab.outline_size = 0
		# no_depth_test 끄기: 뒤집힌 뒷면/뒤쪽 타일 숫자가 겹쳐 보이지 않게 뎁스 테스트 유지
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		var d := 0.47
		match f:
			0:
				lab.position = Vector3(0, 0, d)
			1:
				lab.position = Vector3(0, 0, -d)
				lab.rotation.y = PI
			2:
				lab.position = Vector3(d, 0, 0)
				lab.rotation.y = PI * 0.5
			3:
				lab.position = Vector3(-d, 0, 0)
				lab.rotation.y = -PI * 0.5
			4:
				lab.position = Vector3(0, d, 0)
				lab.rotation.x = -PI * 0.5
			5:
				lab.position = Vector3(0, -d, 0)
				lab.rotation.x = PI * 0.5
		root.add_child(lab)
	return root

func sync_full(logic: G2048) -> void:
	for k in tiles.keys():
		(tiles[k] as Node).queue_free()
	tiles.clear()
	for i in range(logic.cells.size()):
		var v: int = logic.cells[i]
		if v != 0:
			var p := G2048.pos_of(i)
			var t := _make_tile(v)
			t.position = cell_to_world(p)
			add_child(t)
			tiles[p] = t

## movements 반영: 타일 이동 트윈 후 최종값으로 갱신. 새 스폰 타일 pop. 완료 시그널 await용
func play_move(logic: G2048, movements: Array) -> void:
	var by_target := {}
	for m in movements:
		var to: Vector3i = m["to"]
		if not by_target.has(to):
			by_target[to] = []
		(by_target[to] as Array).append(m)
	var tw := create_tween().set_parallel(true)
	var dur := 0.11
	# 1단계: 출발칸 노드 전부 회수 (연쇄 이동 순서 문제 방지)
	var moving := {}
	for m in movements:
		var f: Vector3i = m["from"]
		if tiles.has(f) and not moving.has(f):
			moving[f] = tiles[f]
			tiles.erase(f)
	for k in tiles.keys():
		(tiles[k] as Node).queue_free()
	tiles.clear()
	# 2단계: 도착칸 배치 + 트윈
	for to in by_target.keys():
		var group: Array = by_target[to]
		var node: Node = moving.get(group[0]["from"])
		if node == null:
			continue
		tiles[to] = node
		tw.tween_property(node, "position", cell_to_world(to), dur)
		for gi in range(1, group.size()):
			var extra: Node = moving.get(group[gi]["from"])
			if extra != null:
				tw.tween_property(extra, "position", cell_to_world(to), dur)
				tw.tween_callback(extra.queue_free).set_delay(dur)
	await tw.finished
	# 최종값/색상 반영 + 합체 펄스
	for to in by_target.keys():
		var v: int = logic.get_cell(to.x, to.y, to.z)
		var node: Node3D = tiles.get(to)
		if node == null or v == 0:
			continue
		_refresh_tile(node, v)
		if bool(by_target[to][0]["merged"]):
			node.scale = Vector3.ONE * 1.22
			var t2 := create_tween()
			t2.tween_property(node, "scale", Vector3.ONE, 0.12)

func _refresh_tile(node: Node3D, v: int) -> void:
	(node.get_child(0) as MeshInstance3D).material_override = _mat_for(v)
	for c in node.get_children():
		if c is Label3D:
			(c as Label3D).text = str(v)
			(c as Label3D).modulate = _text_color_for(v)
			(c as Label3D).font_size = 96 if v < 10000 else 72

func spawn_pop(p: Vector3i, v: int) -> void:
	var t := _make_tile(v)
	t.position = cell_to_world(p)
	t.scale = Vector3.ONE * 0.01
	add_child(t)
	tiles[p] = t
	var tw := create_tween()
	tw.tween_property(t, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func tile_count() -> int:
	return tiles.size()

func _build_frame() -> void:
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.45, 0.5, 0.65)
	edge_mat.roughness = 0.4
	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.6, 0.7, 1.0, 0.05)
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(HALF * 2 + 0.1, HALF * 2 + 0.1, HALF * 2 + 0.1)
	gb.material = glass_mat
	glass.mesh = gb
	add_child(glass)
	# 12개 모서리 바
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_add_bar(Vector3(sx * HALF, 0, sy * HALF), Vector3(0.07, HALF * 2 + 0.14, 0.07), edge_mat)
			_add_bar(Vector3(sx * HALF, sy * HALF, 0), Vector3(0.07, 0.07, HALF * 2 + 0.14), edge_mat)
			_add_bar(Vector3(0, sx * HALF, sy * HALF), Vector3(HALF * 2 + 0.14, 0.07, 0.07), edge_mat)

func _add_bar(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	add_child(mi)

func _build_select_frame() -> void:
	# 활성화 면의 모서리에 딱 붙는 노란 테두리 (면 전체 쿼드 대신)
	_select_frame = Node3D.new()
	_select_frame.name = "SelectFrame"
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.2, 0.9)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var e := HALF + 0.175
	var t := 0.1
	for spec in [
		[Vector3(0, e, 0), Vector3(e * 2 + t, t, t)],
		[Vector3(0, -e, 0), Vector3(e * 2 + t, t, t)],
		[Vector3(e, 0, 0), Vector3(t, e * 2 + t, t)],
		[Vector3(-e, 0, 0), Vector3(t, e * 2 + t, t)],
	]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = spec[1]
		b.material = m
		mi.mesh = b
		mi.position = spec[0]
		_select_frame.add_child(mi)
	add_child(_select_frame)

func show_face(normal: Vector3i) -> void:
	var n := Vector3(normal)
	_select_frame.position = n * (HALF + 0.12)
	if absf(n.x) > 0.5:
		_select_frame.rotation = Vector3(0, PI * 0.5, 0)
	elif absf(n.y) > 0.5:
		_select_frame.rotation = Vector3(PI * 0.5, 0, 0)
	else:
		_select_frame.rotation = Vector3.ZERO
