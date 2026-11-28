extends Node
## Autoload "Missions": три задания на день, ключи за выполнение и сундук с наградой.
## Игра сообщает о событиях: Missions.add("lines", 2), Missions.reach("combo", 4).
## За каждое выполненное задание — 🔑; три ключа открывают сундук с новым стилем или эффектом.

signal done(text: String)

const KEYS_PER_CHEST := 3

## id: [текст с %d, варианты цели]
const POOL := {
	"lines": ["Очисти %d линий", [20, 30, 45]],
	"triple": ["Снеси 3+ линии за ход: %d раз", [1, 2]],
	"combo": ["Сделай комбо ×%d", [3, 4, 5]],
	"score": ["Набери %d очков за одну игру", [800, 1500, 2500]],
	"perfect": ["Очисти поле целиком", [1]],
	"win": ["Победи бота или соперника: %d раз", [1, 2]],
	"arcade": ["Пройди уровни Аркады: %d", [1, 2]],
	"pieces": ["Поставь %d фигур", [50, 80, 120]],
	"fruit": ["Собери %d фруктов в Аркаде", [10, 20]],
	"daily": ["Сыграй вызов дня", [1]],
}
## Задания, где важен лучший результат, а не сумма
const MAX_KIND := ["combo", "score"]


func _ready() -> void:
	ensure_today()


## Новый день — новые задания (по местной дате; у каждого игрока свой набор)
func ensure_today() -> void:
	var day := Time.get_date_string_from_system()
	var cur: Dictionary = Save.get_v("missions", {})
	if cur.get("day", "") == day:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day + Save.player_id)
	var ids := POOL.keys()
	var list := []
	while list.size() < 3:
		var id: String = ids[rng.randi() % ids.size()]
		if list.any(func(m): return m.id == id):
			continue
		var opts: Array = POOL[id][1]
		list.append({"id": id, "target": opts[rng.randi() % opts.size()], "prog": 0, "done": false})
	Save.set_v("missions", {"day": day, "list": list})


func list() -> Array:
	ensure_today()
	return Save.get_v("missions", {}).get("list", [])


func text(m: Dictionary) -> String:
	var t: String = tr(POOL[m.id][0])
	return t % m.target if t.contains("%d") else t


func done_count() -> int:
	return list().filter(func(m): return m.done).size()


var keys: int:
	get: return Save.get_v("keys", 0)
	set(v): Save.set_v("keys", v)


func chest_ready() -> bool:
	return keys >= KEYS_PER_CHEST


## Сумма: линии, фигуры, победы…
func add(id: String, amount := 1) -> void:
	_update(id, func(m): m.prog += amount)


## Лучший результат: комбо, очки за игру
func reach(id: String, value: int) -> void:
	_update(id, func(m): m.prog = maxi(m.prog, value))


func _update(id: String, change: Callable) -> void:
	ensure_today()
	var cur: Dictionary = Save.get_v("missions", {})
	var changed := false
	for m in cur.list:
		if m.id != id or m.done:
			continue
		change.call(m)
		changed = true
		if m.prog >= m.target:
			m.prog = m.target
			m.done = true
			keys += 1
			done.emit(text(m))
	if changed:
		Save.set_v("missions", cur)


## Сундук: случайная закрытая награда (стиль блоков, эффект очистки или фон).
## Возвращает {kind: "skin"/"effect"/"", id, name}
func open_chest() -> Dictionary:
	if not chest_ready():
		return {}
	var pool := []
	var got := Save.got()
	for s in BB.SKINS:
		if not got.has(s[0]):
			pool.append({"kind": "skin", "id": s[0], "name": s[1]})
	var eff := Save.effects_got()
	for e in BB.EFFECTS:
		if not eff.has(e[0]):
			pool.append({"kind": "effect", "id": e[0], "name": e[1]})
	var th := Save.themes_got()
	for e in BB.THEMES:
		if not th.has(e[0]):
			pool.append({"kind": "theme", "id": e[0], "name": e[1]})
	keys -= KEYS_PER_CHEST
	if pool.is_empty():
		return {"kind": "", "id": "", "name": ""}
	var r: Dictionary = pool[randi() % pool.size()]
	match r.kind:
		"skin":
			Save.add_skin(r.id)
		"effect":
			Save.add_effect(r.id)
		"theme":
			Save.add_theme(r.id)
	return r
