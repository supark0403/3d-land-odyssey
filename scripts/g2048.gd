class_name G2048
extends RefCounted
## 4x4x4 3D 2048 순수 로직 (노드 없음, 헤드리스 테스트 가능)
## 셀 값 0=빈칸. move(d): d 방향으로 16개 라인을 표준 2048 규칙으로 슬라이드+합체

const N := 4
const WIN := 2048

var cells := PackedInt32Array()
var score := 0
var moves := 0
var won := false
var rng := RandomNumberGenerator.new()

static func idx(x: int, y: int, z: int) -> int:
	return x + N * (y + N * z)

static func pos_of(i: int) -> Vector3i:
	return Vector3i(i % N, (i / N) % N, i / (N * N))

func _init() -> void:
	cells.resize(N * N * N)
	cells.fill(0)
	rng.randomize()

func reset() -> void:
	cells.fill(0)
	score = 0
	moves = 0
	won = false
	spawn_tile()
	spawn_tile()

func get_cell(x: int, y: int, z: int) -> int:
	return cells[idx(x, y, z)]

func set_cell(x: int, y: int, z: int, v: int) -> void:
	cells[idx(x, y, z)] = v

func empty_cells() -> Array:
	var out := []
	for i in range(cells.size()):
		if cells[i] == 0:
			out.append(pos_of(i))
	return out

func spawn_tile() -> bool:
	var empty := empty_cells()
	if empty.is_empty():
		return false
	var p: Vector3i = empty[rng.randi_range(0, empty.size() - 1)]
	set_cell(p.x, p.y, p.z, 4 if rng.randf() < 0.1 else 2)
	return true

func max_tile() -> int:
	var m := 0
	for v in cells:
		m = maxi(m, v)
	return m

## d는 ±X, ±Y, ±Z 중 하나. 반환: {changed, gained, movements:[{from,to,value,merged}]}
func move(d: Vector3i) -> Dictionary:
	var gained := 0
	var changed := false
	var movements := []
	var ax := 0 if d.x != 0 else (1 if d.y != 0 else 2)
	for a in range(N):
		for b in range(N):
			var line := _line(ax, a, b, d)
			var old := []
			for c in line:
				old.append(get_cell(c.x, c.y, c.z))
			var items := []
			for ci in range(line.size()):
				if old[ci] != 0:
					items.append({"pos": line[ci], "v": old[ci]})
			var merged := []
			var k := 0
			while k < items.size():
				if k + 1 < items.size() and items[k]["v"] == items[k + 1]["v"]:
					merged.append({"v": items[k]["v"] * 2, "m": true, "srcs": [items[k]["pos"], items[k + 1]["pos"]]})
					gained += items[k]["v"] * 2
					k += 2
				else:
					merged.append({"v": items[k]["v"], "m": false, "srcs": [items[k]["pos"]]})
					k += 1
			while merged.size() < N:
				merged.append({"v": 0, "m": false, "srcs": []})
			# 기록: 실제 출발칸들 -> 도착칸 (애니메이션용)
			for t in range(N):
				var want: int = merged[t]["v"]
				if want != 0:
					for s in merged[t]["srcs"]:
						movements.append({"from": s, "to": line[t], "value": want, "merged": merged[t]["m"]})
			for t in range(N):
				var c: Vector3i = line[t]
				var nv: int = merged[t]["v"]
				if get_cell(c.x, c.y, c.z) != nv:
					changed = true
					set_cell(c.x, c.y, c.z, nv)
	if changed:
		moves += 1
		score += gained
		if max_tile() >= WIN:
			won = true
	return {"changed": changed, "gained": gained, "movements": movements}

## 목적지 쪽 셀부터 순서대로 라인 반환 (ax: 이동 축 0=x,1=y,2=z)
func _line(ax: int, a: int, b: int, d: Vector3i) -> Array:
	var line := []
	var sign := 1
	if (ax == 0 and d.x > 0) or (ax == 1 and d.y > 0) or (ax == 2 and d.z > 0):
		sign = -1 # +방향으로 밀면 far(3)부터
	for t in range(N):
		var k := (N - 1 - t) if sign < 0 else t
		if ax == 0:
			line.append(Vector3i(k, a, b))
		elif ax == 1:
			line.append(Vector3i(a, k, b))
		else:
			line.append(Vector3i(a, b, k))
	return line

func can_move() -> bool:
	if not empty_cells().is_empty():
		return true
	for d in [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]:
		var ax := 0 if d.x != 0 else (1 if d.y != 0 else 2)
		for a in range(N):
			for b in range(N):
				var line := _line(ax, a, b, d)
				for t in range(N - 1):
					var u: Vector3i = line[t]
					var w: Vector3i = line[t + 1]
					if get_cell(u.x, u.y, u.z) == get_cell(w.x, w.y, w.z):
						return true
	return false
