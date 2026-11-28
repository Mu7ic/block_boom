class_name BB
extends RefCounted
## Общие константы игры: поле, цвета, фигуры, фрукты, стили, уровни Аркады.
## Порт с index.html (веб-версия) — значения совпадают, чтобы баланс был тот же.

const N := 8
const GAME_NAME := "Block Boom"
## Номер сборки: как version/code в export_presets.cfg и code в site/version.json.
## Сервер сообщает последнюю — если она больше, в меню появляется «Есть обновление».
const BUILD := 8
const DOWNLOAD_URL := "https://kyrbo.com/blockboom/"
const COLORS := [
	Color("ff5d5d"), Color("ffa93b"), Color("ffd84d"), Color("4fd67a"),
	Color("36c3ff"), Color("5d7bff"), Color("b45dff"), Color("ff6fc8"),
]
const STONE := Color("5a6396")
const FRUITS := ["🍓", "🍋", "🍇", "🍊", "🍏", "🍒"]

# Цвета интерфейса
const C_BG1 := Color("1d2757")
const C_BG2 := Color("3a2d78")
const C_BOARD := Color("121a3c")
const C_CELL := Color("222b57")
const C_YELLOW := Color("ffe14d")
const C_GOLD := Color("ffd84d")
const C_INK := Color("1d2757")
const C_PINK := Color("ff8fc8")
const C_HOT := Color("ff6fc8")
const C_BLUE := Color("36c3ff")
const C_GREEN := Color("4fd67a")

## Фигуры: '#' — блок, '.' — пусто
const RAW := [
	"#",
	"##", "#\n#",
	"###", "#\n#\n#",
	"####", "#\n#\n#\n#",
	"#####", "#\n#\n#\n#\n#",
	"##\n##",
	"###\n###", "##\n##\n##",
	"###\n###\n###",
	"##\n#.", "##\n.#", "#.\n##", ".#\n##",
	"###\n#..\n#..", "###\n..#\n..#", "#..\n#..\n###", "..#\n..#\n###",
	"#.\n#.\n##", ".#\n.#\n##", "##\n#.\n#.", "##\n.#\n.#",
	"#..\n###", "..#\n###", "###\n#..", "###\n..#",
	"###\n.#.", ".#.\n###", "#.\n##\n#.", ".#\n##\n.#",
	"##.\n.##", ".##\n##.", "#.\n##\n.#", ".#\n##\n#.",
]

## Стили блоков: [id, название]. Рисуются в skins.gd, порядок как в веб-версии
## (онлайн-соперник присылает номер стиля).
const SKINS := [
	["classic", "Классика"],
	["disco", "Диско-шар ✨"],
	["melon", "Арбузики 🍉"],
	["egg", "Яичница 🍳"],
	["neon", "Неон"],
	["candy", "Карамельки 🍬"],
	["jelly", "Желе"],
	["eyes", "Глазастики 👀"],
	["ice", "Лёд ❄️"],
	["gold", "Золото 👑"],
	["pixel", "Пиксели"],
	["water", "Аквариум 🌊"],
	["donut", "Пончики 🍩"],
	["cookie", "Печеньки 🍪"],
	["wood", "Дерево"],
	["galaxy", "Космос 🌌"],
	["bubble", "Пузыри 🔵"],
	["heart", "Сердечки 💖"],
	["matrix", "Матрица"],
	["pizza", "Пицца 🍕"],
]

## Разобранные фигуры: {cells: Array[Vector2i(r, c)], h, w, base: int (битовая маска в углу поля)}
static var SHAPES: Array = _build_shapes()


static func _build_shapes() -> Array:
	var out := []
	for s in RAW:
		var rows: PackedStringArray = String(s).split("\n")
		var cells: Array[Vector2i] = []
		var w := 0
		var base := 0
		for r in rows.size():
			w = maxi(w, rows[r].length())
			for c in rows[r].length():
				if rows[r][c] == "#":
					cells.append(Vector2i(r, c))
					base |= 1 << (r * N + c)
		out.append({"cells": cells, "h": rows.size(), "w": w, "base": base})
	return out


static func skin_index(id: String) -> int:
	for i in SKINS.size():
		if SKINS[i][0] == id:
			return i
	return 0


# ---------- Аркада: бесконечная карта ----------
## Мир — 10 уровней со своим фоном и набором фруктов. После последнего мира
## карта идёт по кругу, а уровни продолжают усложняться.
## [название, значок, цвет фона снизу, цвет фона сверху, фрукты]
const WORLDS := [
	["Сад", "🌷", Color("1f4a3a"), Color("2b6a45"), ["🍓", "🍏", "🍒"]],
	["Цитрусовая роща", "🍋", Color("5a4a16"), Color("8a6420"), ["🍋", "🍊", "🍏"]],
	["Ягодный лес", "🌲", Color("2a1f4f"), Color("4a2d6e"), ["🍇", "🍓", "🍒"]],
	["Остров", "🏝", Color("0f3d5a"), Color("16707e"), ["🍊", "🍇", "🍋"]],
	["Ледник", "❄️", Color("23406e"), Color("4a78a8"), ["🍏", "🍇", "🍒"]],
	["Вулкан", "🌋", Color("4a1a1a"), Color("8a3220"), ["🍓", "🍊", "🍋"]],
]
const LEVELS_PER_WORLD := 10


static func world_of(n: int) -> int:
	return (n - 1) / LEVELS_PER_WORLD


static func world_def(w: int) -> Array:
	return WORLDS[w % WORLDS.size()]


## Уровень n (с 1, без верхней границы). Всё зависит только от n:
## у всех игроков и при каждой попытке уровень одинаковый.
static func level_def(n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("blockboom-arcade-%d" % n)
	var w := world_of(n)
	var i := (n - 1) % LEVELS_PER_WORLD        # место в мире: 0…9
	var boss := i == LEVELS_PER_WORLD - 1      # каждый 10-й — «босс»: больше камней и фруктов
	# Сложность растёт быстро в начале и плавно выходит на плато, но не останавливается
	var d := 1.0 - exp(-float(n) / 35.0)
	var loop := w / WORLDS.size()
	var kinds := 1 if n <= 3 else (2 if n <= 12 else 3)
	if boss and n > 3:
		kinds = mini(3, kinds + 1)
	var fruits: Array = world_def(w)[4].duplicate()
	# Порядок фруктов в мире перемешиваем от номера уровня
	for k in range(fruits.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = fruits[k]
		fruits[k] = fruits[j]
		fruits[j] = tmp
	var goals := []
	var total := 0
	for k in kinds:
		var need := 3 + roundi(8.0 * d) + i / 3 + loop - k * 2 + rng.randi_range(-1, 1)
		if boss:
			need = roundi(need * 1.3)
		need = clampi(need, 3, 30)
		total += need
		goals.append({"f": fruits[k], "need": need, "left": need})
	var stones := 0
	if n >= 3:
		stones = clampi(3 + roundi(15.0 * d) + rng.randi_range(-2, 2) + (4 if boss else 0), 0, 24)
	# Ходов на три звезды: подобрано по прохождениям ИИ (tools/arcade_calib.gd)
	var par := ceili(total * PAR_PER_FRUIT + stones * PAR_PER_STONE + PAR_BASE)
	return {"goals": goals, "stones": stones, "par": par, "world": w, "boss": boss, "seed": rng.randi()}


const PAR_PER_FRUIT := 1.2
const PAR_PER_STONE := 0.0
const PAR_BASE := 5.0


## Звёзды за пройденный уровень по числу ходов
static func level_stars(moves: int, par: int) -> int:
	if moves <= par:
		return 3
	if moves <= ceili(par * 1.5):
		return 2
	return 1


## Ключей в награду за сезон — по лиге на его конец (как на сервере, SEASON_KEYS)
static func season_keys(rating: int) -> int:
	for row in [[1600, 6], [1400, 4], [1250, 3], [1100, 2]]:
		if rating >= row[0]:
			return row[1]
	return 1


static func color_hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func is_color_str(v) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s: String = v
	return s.length() == 7 and s[0] == "#" and s.substr(1).is_valid_hex_number()


# ---------- Лиги онлайн-рейтинга ----------
## [порог рейтинга, название, значок, цвет]
const LEAGUES := [
	[0, "Бронза", "🥉", Color("d9935a")],
	[1100, "Серебро", "🥈", Color("cfd8e8")],
	[1250, "Золото", "🥇", Color("ffd84d")],
	[1400, "Платина", "💠", Color("6fe0e0")],
	[1600, "Алмаз", "💎", Color("9fb4ff")],
]


static func league(rating: int) -> Array:
	var out: Array = LEAGUES[0]
	for l in LEAGUES:
		if rating >= l[0]:
			out = l
	return out


## «🥈 Серебро · 1180»
static func league_text(rating: int) -> String:
	var l := league(rating)
	return "%s %s · %d" % [l[2], I18N.t(l[1]), rating]


## День по UTC, как у сервера: «2026-11-27»
static func today(shift_sec := 0) -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) + shift_sec)


# ---------- Эффекты очистки линий ----------
## [id, название, значок] — открываются в сундуке заданий
const EFFECTS := [
	["confetti", "Конфетти", "🎊"],
	["sparks", "Искры", "✨"],
	["stars", "Звёзды", "⭐"],
	["hearts", "Сердечки", "💖"],
	["bubbles", "Пузыри", "🔵"],
	["rings", "Волны", "🌀"],
]


# ---------- Фоны ----------
## [id, название, цвет сверху-слева, цвет снизу-справа]
const THEMES := [
	["night", "Сумерки", Color("1d2757"), Color("3a2d78")],
	["ocean", "Океан", Color("0b3550"), Color("16707e")],
	["sunset", "Закат", Color("4a1f4f"), Color("b04a3c")],
	["forest", "Лес", Color("0f3328"), Color("2c6236")],
	["space", "Космос", Color("07071c"), Color("281450")],
	["candy", "Карамель", Color("5c2463"), Color("c2557f")],
]


static func theme_def(id: String) -> Array:
	for t in THEMES:
		if t[0] == id:
			return t
	return THEMES[0]


static func effect_index(id: String) -> int:
	for i in EFFECTS.size():
		if EFFECTS[i][0] == id:
			return i
	return 0
