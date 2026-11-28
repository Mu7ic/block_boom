extends Node
## Autoload "Save": настройки и прогресс (аналог localStorage веб-версии), файл user://blockboom.cfg.

const PATH := "user://blockboom.cfg"
## Адрес сервера онлайн-боя по умолчанию (тот же server.js, что и у веб-версии).
## Для VPS: "wss://ИМЯ_ДОМЕНА/ws". Игрок может поменять адрес в лобби.
const DEFAULT_SERVER := "wss://kyrbo.com/ws"
const OLD_DEFAULT := "ws://127.0.0.1:8765/ws"   ## прежний адрес по умолчанию — заменяем новым

var _cfg := ConfigFile.new()
var _path := PATH


func _ready() -> void:
	# Проверочные сцены из tools/ пишут в отдельный файл, чтобы не трогать прогресс игрока
	if "--test-save" in OS.get_cmdline_user_args():
		_path = "user://blockboom_test.cfg"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	_migrate_old_dir()
	_cfg.load(_path)


## На ПК папка сохранений зависит от названия игры: после переименования
## «Блок Бум!» → «Block Boom» забираем прогресс из старой папки (на телефоне путь не менялся)
func _migrate_old_dir() -> void:
	var cur := ProjectSettings.globalize_path(PATH)
	if FileAccess.file_exists(cur) or OS.has_feature("mobile"):
		return
	var old := OS.get_user_data_dir().get_base_dir().path_join("Блок Бум!").path_join(PATH.get_file())
	if FileAccess.file_exists(old):
		DirAccess.make_dir_recursive_absolute(cur.get_base_dir())
		DirAccess.copy_absolute(old, cur)


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


# ---------- Вызов дня без сети ----------
## Результат, который не удалось отправить: {day, score}. Уйдёт в таблицу, когда появится интернет.
var daily_pending: Dictionary:
	get: return get_v("daily_pending", {})
	set(v): set_v("daily_pending", v)


# ---------- Незаконченная партия «Классики» ----------
var run: Dictionary:
	get: return get_v("run", {})
	set(v): set_v("run", v)


func clear_run() -> void:
	if _cfg.has_section_key("save", "run"):
		_cfg.erase_section_key("save", "run")
		_cfg.save(_path)


# ---------- Звёзды уровней Аркады ----------
func level_stars(n: int) -> int:
	return int(get_v("stars", {}).get(str(n), 0))


## Запомнить лучший результат уровня
func set_level_stars(n: int, st: int) -> void:
	var all: Dictionary = get_v("stars", {})
	if st > int(all.get(str(n), 0)):
		all[str(n)] = st
		set_v("stars", all)


func total_stars() -> int:
	var t := 0
	for v in get_v("stars", {}).values():
		t += int(v)
	return t
var skin: int:
	get: return BB.skin_index(get_v("skin", "classic"))
	set(v): set_v("skin", BB.SKINS[v][0])
var player_name: String:
	get: return get_v("name", "")
	set(v): set_v("name", v)
var server: String:
	get:
		# Проверочные сцены никогда не ходят на боевой сервер (иначе их результаты попадают в таблицы)
		if _path != PATH and not _cfg.has_section_key("save", "server"):
			return "ws://127.0.0.1:9/ws"
		var v: String = get_v("server", "")
		return DEFAULT_SERVER if v == "" or v == OLD_DEFAULT else v
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


# ---------- Фоны ----------
var bg_theme: String:
	get: return get_v("theme", "night")
	set(v): set_v("theme", v)


func themes_got() -> Array:
	return get_v("themes", ["night"])


func add_theme(id: String) -> void:
	var e := themes_got()
	if not e.has(id):
		e.append(id)
		set_v("themes", e)


# ---------- Одноразовые подсказки ----------
func hint_once(key: String) -> bool:
	var h: Array = get_v("hints", [])
	if h.has(key):
		return false
	h.append(key)
	set_v("hints", h)
	return true
