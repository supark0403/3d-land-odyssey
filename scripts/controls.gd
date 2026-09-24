class_name Controls
extends RefCounted
## 게임별 키 설정: 기본값 + 저장/로드 (user://g2048.cfg [controls])

const PATH := "user://g2048.cfg"

const GAMES := [
	{"id": "global", "label": "Common"},
	{"id": "g2048", "label": "2048"},
	{"id": "suika", "label": "Suika"},
	{"id": "surv", "label": "Survivor"},
	{"id": "flight", "label": "Flight"},
	{"id": "shmup", "label": "Shooter"},
	{"id": "tetris", "label": "Tetris"},
	{"id": "snake", "label": "Snake"},
	{"id": "stack", "label": "Stack"},
]

const ACTIONS := {
	"g2048": [["up", "위"], ["down", "아래"], ["left", "왼쪽"], ["right", "오른쪽"], ["front", "안쪽"], ["back", "바깥쪽"]],
	"suika": [["up", "위"], ["down", "아래"], ["left", "왼쪽"], ["right", "오른쪽"], ["drop", "낙하"]],
	"surv": [["up", "위"], ["down", "아래"], ["left", "왼쪽"], ["right", "오른쪽"]],
	"flight": [["up", "위"], ["down", "아래"], ["left", "왼쪽"], ["right", "오른쪽"]],
	"shmup": [["up", "위"], ["down", "아래"], ["left", "왼쪽"], ["right", "오른쪽"]],
	"breakout": [["left", "왼쪽"], ["right", "오른쪽"], ["up", "위"], ["down", "아래"], ["launch", "발사"]],
	"tetris": [["up", "이동 위"], ["down", "이동 아래"], ["left", "이동 왼쪽"], ["right", "이동 오른쪽"], ["yawp", "Yaw+반시계"], ["yawm", "Yaw-시계"], ["pitchp", "앞으로 기울기"], ["pitchm", "뒤로 기울기"], ["rollp", "왼쪽 기울기"], ["rollm", "오른쪽 기울기"], ["drop", "하드드랍"], ["hold", "홀드"]],
	"snake": [["up", "위"], ["down", "아래"], ["left", "왼쪽"], ["right", "오른쪽"], ["altup", "상승"], ["altdown", "하강"]],
	"stack": [["drop", "쌓기"]],
	"global": [["restart", "재시작"], ["pause", "일시정지"]],
}

const DEFAULTS := {
	"g2048": {"up": [4194320], "down": [4194322], "left": [4194319, 65], "right": [4194321, 68], "front": [87], "back": [83]},
	"suika": {"up": [87, 4194320], "down": [83, 4194322], "left": [65, 4194319], "right": [68, 4194321], "drop": [32]},
	"surv": {"up": [87, 4194320], "down": [83, 4194322], "left": [65, 4194319], "right": [68, 4194321]},
	"flight": {"up": [87, 4194320], "down": [83, 4194322], "left": [65, 4194319], "right": [68, 4194321]},
	"shmup": {"up": [87, 4194320], "down": [83, 4194322], "left": [65, 4194319], "right": [68, 4194321]},
	"breakout": {"left": [65, 4194319], "right": [68, 4194321], "up": [87, 4194320], "down": [83, 4194322], "launch": [32]},
	"tetris": {"up": [4194320], "down": [4194322], "left": [4194319], "right": [4194321], "yawp": [81], "yawm": [69], "pitchp": [87], "pitchm": [83], "rollp": [65], "rollm": [68], "drop": [32], "hold": [67, 4194325]},
	"snake": {"up": [87, 4194320], "down": [83, 4194322], "left": [65, 4194319], "right": [68, 4194321], "altup": [32], "altdown": [67, 4194325]},
	"stack": {"drop": [32]},
	"global": {"restart": [82], "pause": [80]},
}

static var _cache := {}

static func _ensure() -> void:
	if not _cache.is_empty():
		return
	for g in DEFAULTS.keys():
		_cache[g] = {}
		for a in (DEFAULTS[g] as Dictionary).keys():
			_cache[g][a] = ((DEFAULTS[g] as Dictionary)[a] as Array).duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for g in _cache.keys():
			for a in (_cache[g] as Dictionary).keys():
				var v = cfg.get_value("controls", str(g) + "/" + str(a), null)
				if v is Array and not (v as Array).is_empty():
					_cache[g][a] = (v as Array).duplicate()

static func keys_for(game: String, action: String) -> Array:
	_ensure()
	if _cache.has(game) and (_cache[game] as Dictionary).has(action):
		return (_cache[game] as Dictionary)[action]
	return []

static func set_keys(game: String, action: String, codes: Array) -> void:
	_ensure()
	if _cache.has(game):
		(_cache[game] as Dictionary)[action] = codes.duplicate()
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("controls", game + "/" + action, codes.duplicate())
	cfg.save(PATH)

static func key_name(code: int) -> String:
	var s := OS.get_keycode_string(code)
	return s if s != "" else ("Key" + str(code))

static func names(game: String, action: String) -> String:
	var parts := []
	for c in keys_for(game, action):
		parts.append(key_name(int(c)))
	return "+".join(parts)

## 액션 쌍의 -1/0/+1 축 입력 (폴링용)
static func axis_pressed(game: String, neg_action: String, pos_action: String) -> float:
	for c in keys_for(game, neg_action):
		if Input.is_physical_key_pressed(int(c)):
			return -1.0
	for c in keys_for(game, pos_action):
		if Input.is_physical_key_pressed(int(c)):
			return 1.0
	return 0.0
