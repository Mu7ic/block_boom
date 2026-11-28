class_name Scoring
extends RefCounted
## Очки «Классики», вызова дня и боёв — одна формула для игрока, бота и симуляции.
##   фигура:      10 за клетку
##   линии:       100 · n·(n+1)/2  → 1 линия 100, 2 — 300, 3 — 600, 4 — 1000
##   серия:       очищение линий подряд умножает очки линий: ×1, ×2, ×3…
##                серия не рвётся, пока между очищениями не больше COMBO_GRACE ходов без линий
##   чистое поле: +3000

const PER_CELL := 10
const PER_LINE := 100
const PERFECT := 3000
const COMBO_GRACE := 3      ## сколько ходов подряд без линий можно сделать, не потеряв серию

var score := 0
var combo := 0              ## текущая серия очищений
var miss := 0               ## ходов подряд без линий
var max_combo := 0


## Очки за ход; возвращает {gained, bonus, combo, kept}
func add(cells: int, n: int, perfect: bool) -> Dictionary:
	var gained := cells * PER_CELL
	var bonus := 0
	if n > 0:
		combo += 1
		miss = 0
		max_combo = maxi(max_combo, combo)
		bonus = line_points(n) * combo
		if perfect:
			bonus += PERFECT
		gained += bonus
	else:
		miss += 1
		if miss >= COMBO_GRACE:
			combo = 0
	score += gained
	return {"gained": gained, "bonus": bonus, "combo": combo}


## Сколько ходов осталось, чтобы продлить серию (0 — серии нет)
func moves_left() -> int:
	return COMBO_GRACE - miss if combo > 0 else 0


static func line_points(n: int) -> int:
	return PER_LINE * n * (n + 1) / 2
