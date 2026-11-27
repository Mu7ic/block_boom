extends Node
## Autoload "Save": настройки и прогресс (аналог localStorage веб-версии), файл user://blockboom.cfg.

const PATH := "user://blockboom.cfg"
## Адрес сервера онлайн-боя по умолчанию (тот же server.js, что и у веб-версии).
## Для VPS: "wss://ИМЯ_ДОМЕНА/ws". Игрок может поменять адрес в лобби.
const DEFAULT_SERVER := "ws://127.0.0.1:8765/ws"

var _cfg := ConfigFile.new()
var _path := PATH


func _ready() -> void:
	# Проверочные сцены из tools/ пишут в отдельный файл, чтобы не трогать прогресс игрока
	if "--test-save" in OS.get_cmdline_user_args():
		_path = "user://blockboom_test.cfg"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	_cfg.load(_path)


func get_v(key: String, def = null):
	if not _cfg.has_section_key("save", key):
		return def
	return _cfg.get_value("save", key, def)


func set_v(key: String, v) -> void:
	_cfg.set_value("save", key, v)
	_cfg.save(_path)


var sound: bool:
	get: return get_v("sound", true)
	set(v): set_v("sound", v)
var music: bool:
	get: return get_v("music", true)
	set(v): set_v("music", v)
var vibro: bool:
	get: return get_v("vibro", true)
	set(v): set_v("vibro", v)
var best: int:
	get: return get_v("best", 0)
	set(v): set_v("best", v)
var unlocked: int:
	get: return get_v("unlocked", 1)
	set(v): set_v("unlocked", v)
var skin: int:
	get: return BB.skin_index(get_v("skin", "classic"))
	set(v): set_v("skin", BB.SKINS[v][0])
var player_name: String:
	get: return get_v("name", "")
	set(v): set_v("name", v)
var server: String:
	get: return get_v("server", DEFAULT_SERVER)
	set(v): set_v("server", v)


# ---------- Коллекция стилей ----------
func got() -> Array:
	return get_v("got", [])


func seen() -> Array:
	return get_v("seen", [])


## Отметить стиль открытым; true — если он новый
func add_skin(id: String) -> bool:
	var s := got()
	if s.has(id):
		return false
	s.append(id)
	set_v("got", s)
	return true


func mark_seen() -> void:
	set_v("seen", got().duplicate())


func has_new_skins() -> bool:
	var sn := seen()
	for id in got():
		if not sn.has(id):
			return true
	return false


# ---------- Одноразовые подсказки ----------
func hint_once(key: String) -> bool:
	var h: Array = get_v("hints", [])
	if h.has(key):
		return false
	h.append(key)
	set_v("hints", h)
	return true
