class_name BB
extends RefCounted
## Общие константы игры: поле, цвета, фигуры, фрукты, стили, уровни Аркады.
## Порт с index.html (веб-версия) — значения совпадают, чтобы баланс был тот же.

const N := 8
const GAME_NAME := "Блок Бум!"
const COLORS := [
	Color("ff5d5d"), Color("ffa93b"), Color("ffd84d"), Color("4fd67a"),
	Color("36c3ff"), Color("5d7bff"), Color("b45dff"), Color("ff6fc8"),
]
const STONE := Color("5a6396")
const FRUITS := ["🍓", "🍋", "🍇", "🍊", "🍏", "🍒"]
const LEVEL_COUNT := 30

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


## Уровень Аркады: больше фруктов, больше видов, больше камней на старте
static func level_def(n: int) -> Dictionary:
	var kinds := 1 if n <= 3 else (2 if n <= 10 else 3)
	var start := (n * 2) % FRUITS.size()
	var goals := []
	for k in kinds:
		var need := maxi(3, 3 + int(floor(n * 0.7)) - k * 2)
		goals.append({"f": FRUITS[(start + k) % FRUITS.size()], "need": need, "left": need})
	var stones := 0 if n < 3 else mini(4 + n, 24)
	return {"goals": goals, "stones": stones}


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
	return "%s %s · %d" % [l[2], l[1], rating]


## День по UTC, как у сервера: «2026-11-27»
static func today() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))


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


static func effect_index(id: String) -> int:
	for i in EFFECTS.size():
		if EFFECTS[i][0] == id:
			return i
	return 0
