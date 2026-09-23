class_name AudioSetup
extends RefCounted
## 오디오 설정: SFX 버스 보장 + 마스터/SFX 음량 저장·적용 (user://g2048.cfg)

const PATH := "user://g2048.cfg"

static func sfx_bus() -> int:
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == "SFX":
			return i
	return -1

static func ensure_bus() -> void:
	if sfx_bus() == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")

static func get_vol(key: String, dflt: float = 100.0) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		return clampf(float(cfg.get_value("audio", key, dflt)), 0.0, 100.0)
	return dflt

static func set_vol(key: String, v: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("audio", key, clampf(v, 0.0, 100.0))
	cfg.save(PATH)
	apply_volumes()

static func to_db(v: float) -> float:
	if v <= 0.5:
		return -60.0
	return linear_to_db(v / 100.0)

static func mobile_enabled() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		return bool(cfg.get_value("gameplay", "mobile_mode", false))
	return false

static func set_mobile(v: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("gameplay", "mobile_mode", v)
	cfg.save(PATH)

static func apply_volumes() -> void:
	ensure_bus()
	AudioServer.set_bus_volume_db(0, to_db(get_vol("master", 100.0)))
	var s := sfx_bus()
	if s >= 0:
		AudioServer.set_bus_volume_db(s, to_db(get_vol("sfx", 100.0)))
