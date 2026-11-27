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


# ---------- Онлайн-профиль ----------
## Случайный токен игрока: по нему сервер хранит рейтинг. Никому не показывается.
var player_id: String:
	get:
		var id: String = get_v("pid", "")
		if id.length() < 32:
			id = Crypto.new().generate_random_bytes(16).hex_encode()
			set_v("pid", id)
		return id
## Последний известный рейтинг (с сервера), чтобы показывать его и без связи
var rating: int:
	get: return get_v("rating", 1000)
	set(v): set_v("rating", v)
var rated_games: int:
	get: return get_v("rated_games", 0)
	set(v): set_v("rated_games", v)


# ---------- Вызов дня ----------
func daily_best(day: String) -> int:
	return get_v("daily_best", 0) if get_v("daily_day", "") == day else 0


func set_daily_best(day: String, v: int) -> void:
	set_v("daily_day", day)
	set_v("daily_best", v)


## Серия дней подряд; если пропущен день — серия сгорела
var daily_streak: int:
	get:
		var last: String = get_v("daily_last", "")
		if last == BB.today() or last == _day_before(BB.today()):
			return get_v("daily_streak", 0)
		return 0


func daily_played(day: String) -> void:
	var last: String = get_v("daily_last", "")
	if last == day:
		return
	set_v("daily_streak", get_v("daily_streak", 0) + 1 if last == _day_before(day) else 1)
	set_v("daily_last", day)


func _day_before(day: String) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(day) - 86400)


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


# ---------- Эффекты очистки ----------
var effect: String:
	get: return get_v("effect", "confetti")
	set(v): set_v("effect", v)


func effects_got() -> Array:
	return get_v("effects", ["confetti"])


func add_effect(id: String) -> void:
	var e := effects_got()
	if not e.has(id):
		e.append(id)
		set_v("effects", e)


# ---------- Одноразовые подсказки ----------
func hint_once(key: String) -> bool:
	var h: Array = get_v("hints", [])
	if h.has(key):
		return false
	h.append(key)
	set_v("hints", h)
	return true
