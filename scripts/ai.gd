class_name BBAI
extends RefCounted
## Логика поля на битовых масках (64 клетки = одно int): проверка ходов, линии,
## оценка хода, «умная» выдача фигур и «джекпоты». Порт bestMove/smartSet/findJackpot из index.html.
## Бит клетки (r, c) = r * 8 + c.

const N := 8
const ASSIST := 0.8      ## доля «умных» слотов (остальные — случайные, но тоже влезают)
const CANDIDATES := 14   ## сколько случайных фигур рассматриваем на слот
## Помощь, когда поле забито: с DANGER_FILL клеток все фигуры подбираются под поле
## (лучшие из большего числа кандидатов) — новичку легче выбраться
const DANGER_FILL := 22
const DANGER_CANDIDATES := 24
static var ease := true      ## выключается только в tools/classic_sim.gd для сравнения
const LOW56 := 0x00FFFFFFFFFFFFFF

static var ROW: PackedInt64Array
static var COL: PackedInt64Array
static var NOT_C0 := 0
static var NOT_C7 := 0
static var POP: PackedByteArray
static var BIG: Array[int] = []
static var FIN: Array[int] = []
static var _tables_ok := _init_tables()


static func _init_tables() -> bool:
	ROW.resize(N)
	COL.resize(N)
	for i in N:
		ROW[i] = 0xFF << (i * N)
		var c := 0
		for r in N:
			c |= 1 << (r * N + i)
		COL[i] = c
	NOT_C0 = ~COL[0]
	NOT_C7 = ~COL[N - 1]
	POP.resize(256)
	for v in 256:
		var k := 0
		var x := v
		while x:
			k += x & 1
			x >>= 1
		POP[v] = k
	for s in ["###\n###\n###", "###\n###", "##\n##\n##", "##\n##"]:
		BIG.append(BB.RAW.find(s))
	for i in BB.SHAPES.size():
		var sh: Dictionary = BB.SHAPES[i]
		if BIG.has(i) or (sh.h == 1 and sh.w >= 3) or (sh.w == 1 and sh.h >= 3):
			FIN.append(i)
	return true


static func popcount(x: int) -> int:
	return (POP[x & 0xFF] + POP[(x >> 8) & 0xFF] + POP[(x >> 16) & 0xFF] + POP[(x >> 24) & 0xFF]
		+ POP[(x >> 32) & 0xFF] + POP[(x >> 40) & 0xFF] + POP[(x >> 48) & 0xFF] + POP[(x >> 56) & 0xFF])


# Сдвиги: каждая клетка уезжает к соседу в нужную сторону (выпавшие за край отбрасываются)
static func sh_down(x: int) -> int: return x << 8
static func sh_up(x: int) -> int: return (x >> 8) & LOW56
static func sh_right(x: int) -> int: return (x << 1) & NOT_C0
static func sh_left(x: int) -> int: return (x >> 1) & NOT_C7


## Маска фигуры из списка клеток (для фигур без номера, напр. от онлайн-соперника)
static func cells_mask(cells: Array) -> int:
	var m := 0
	for v in cells:
		m |= 1 << (v.x * N + v.y)
	return m


static func can_place(b: int, piece: Dictionary, r: int, c: int) -> bool:
	if r < 0 or c < 0 or r + piece.h > N or c + piece.w > N:
		return false
	return (b & (int(piece.base) << (r * N + c))) == 0


static func fits_anywhere(b: int, piece: Dictionary) -> bool:
	var base: int = piece.base
	for r in N - piece.h + 1:
		for c in N - piece.w + 1:
			if (b & (base << (r * N + c))) == 0:
				return true
	return false


## Маска всех заполненных линий и их количество: [mask, n]
static func full_lines(b: int) -> Array:
	var m := 0
	var n := 0
	for i in N:
		if (b & ROW[i]) == ROW[i]:
			m |= ROW[i]
			n += 1
		if (b & COL[i]) == COL[i]:
			m |= COL[i]
			n += 1
	return [m, n]


## Оценка хода фигуры-маски m на поле b (как в веб-версии).
## На поле b готовых линий нет, поэтому заполниться могут только затронутые строки/столбцы.
## Без общего состояния — можно звать из фонового потока.


static func _score(b: int, m: int, r: int, c: int, h: int, w: int) -> float:
	var pre := b | m
	var lm := 0
	var n := 0
	var s := 0.0
	# Заполненность затронутых строк/столбцов и готовые линии
	for rr in range(r, r + h):
		var row: int = ROW[rr]
		var pc := popcount(pre & row)
		if pc == N:
			lm |= row
			n += 1
		s += pc * pc * 0.3125   # (pc / 8)^2 * 20
	for cc in range(c, c + w):
		var col: int = COL[cc]
		var pc := popcount(pre & col)
		if pc == N:
			lm |= col
			n += 1
		s += pc * pc * 0.3125
	var post := pre & ~lm
	s += n * 100 + (n * 60 if n > 1 else 0)
	# Плотность: соседи-блоки и стены
	var other := pre & ~m
	s += 2.5 * (popcount(sh_down(m) & other) + popcount(sh_up(m) & other)
		+ popcount(sh_right(m) & other) + popcount(sh_left(m) & other))
	s += 1.5 * (popcount(m & ROW[N - 1]) + popcount(m & ROW[0]) + popcount(m & COL[N - 1]) + popcount(m & COL[0]))
	# Штраф за «дырки» — пустые клетки, зажатые со всех сторон
	var closed := ~post & (sh_up(post) | ROW[N - 1]) & (sh_down(post) | ROW[0]) 		& (sh_left(post) | COL[N - 1]) & (sh_right(post) | COL[0])
	if closed:
		s -= 10.0 * (popcount(sh_down(m) & closed) + popcount(sh_up(m) & closed)
			+ popcount(sh_right(m) & closed) + popcount(sh_left(m) & closed))
	return s


static func _eval(b: int, m: int, r: int, c: int, h: int, w: int) -> Dictionary:
	var s := _score(b, m, r, c, h, w)
	var fl := full_lines(b | m)
	return {"r": r, "c": c, "score": s, "lines": fl[1], "board": (b | m) & ~int(fl[0])}


## Лучший ход фигуры (или {}), all — если передан, туда складываются все ходы
## Во сколько мест можно поставить фигуру
static func places(b: int, piece: Dictionary) -> int:
	var base: int = piece.base
	var n := 0
	for r in N - piece.h + 1:
		for c in N - piece.w + 1:
			if not (b & (base << (r * N + c))):
				n += 1
	return n


static func best_move(b: int, piece: Dictionary, all = null) -> Dictionary:
	var base: int = piece.base
	var h: int = piece.h
	var w: int = piece.w
	var found := false
	var bs := 0.0
	var br := 0
	var bc := 0
	for r in N - h + 1:
		for c in N - w + 1:
			var m := base << (r * N + c)
			if b & m:
				continue
			if all != null:
				all.append(_eval(b, m, r, c, h, w))
				var sc: float = all[all.size() - 1].score
				if not found or sc > bs:
					found = true
					bs = sc
					br = r
					bc = c
				continue
			var s := _score(b, m, r, c, h, w)
			if not found or s > bs:
				found = true
				bs = s
				br = r
				bc = c
	if not found:
		return {}
	return _eval(b, base << (br * N + bc), br, bc, h, w)


## Лучшие per ходов фигуры: [[очки, r, c], ...] по убыванию
static func _top_moves(b: int, piece: Dictionary, per: int) -> Array:
	var base: int = piece.base
	var h: int = piece.h
	var w: int = piece.w
	var top := []
	for r in N - h + 1:
		for c in N - w + 1:
			var m := base << (r * N + c)
			if b & m:
				continue
			var s := _score(b, m, r, c, h, w)
			if top.size() < per or s > top[top.size() - 1][0]:
				var k := top.size()
				while k > 0 and top[k - 1][0] < s:
					k -= 1
				top.insert(k, [s, r, c])
				if top.size() > per:
					top.pop_back()
	return top


## Лучший ход, который чистит 3+ линии (или {})
static func big_clear(b: int, piece: Dictionary) -> Dictionary:
	var best := {}
	var base: int = piece.base
	var h: int = piece.h
	var w: int = piece.w
	for r in N - h + 1:
		for c in N - w + 1:
			var m := base << (r * N + c)
			if b & m:
				continue
			var pre := b | m
			var n := 0
			for rr in range(r, r + h):
				if (pre & ROW[rr]) == ROW[rr]:
					n += 1
			for cc in range(c, c + w):
				if (pre & COL[cc]) == COL[cc]:
					n += 1
			if n < 3:
				continue
			var mv := _eval(b, m, r, c, h, w)
			if best.is_empty() or mv.lines > best.lines or (mv.lines == best.lines and mv.score > best.score):
				best = mv
	return best


static func _prefer(list: Array) -> Dictionary:
	var big := list.filter(func(x): return BIG.has(x.s[x.s.size() - 1]))
	var pool := big if not big.is_empty() and randf() < 0.75 else list
	return pool[randi() % pool.size()]


static func _tops_on(bb: int, k: int, per: int) -> Array:
	var res := []
	for s in BB.SHAPES.size():
		var sh: Dictionary = BB.SHAPES[s]
		var top := _top_moves(bb, sh, per)
		if top.is_empty():
			continue
		var moves := []
		for t in top:
			moves.append(_eval(bb, int(sh.base) << (int(t[1]) * N + int(t[2])), t[1], t[2], sh.h, sh.w))
		res.append({"s": s, "moves": moves})
	res.sort_custom(func(x, y): return x.moves[0].score > y.moves[0].score)
	return res.slice(0, k)


## «Джекпот»: 1–3 фигуры, после которых можно сразу снять 3+ линии.
## Возвращает {s: [номера фигур по порядку], board} или {}.
static func find_jackpot(b: int) -> Dictionary:
	if popcount(b) < 8:
		return {}
	var shapes: Array = BB.SHAPES
	var found := []
	# Одна фигура сразу закрывает 3+ линии
	for s in shapes.size():
		var m := big_clear(b, shapes[s])
		if not m.is_empty():
			found.append({"s": [s], "board": m.board})
	if not found.is_empty():
		return _prefer(found)
	# Две фигуры: первая готовит поле, вторая сносит 3+
	var tops := _tops_on(b, 10, 3)
	for A in tops:
		for ma in A.moves:
			for s in shapes.size():
				var m := big_clear(ma.board, shapes[s])
				if not m.is_empty():
					found.append({"s": [A.s, s], "board": m.board})
	if not found.is_empty():
		return _prefer(found)
	# Три фигуры: две готовят, третья (большая или длинная линия) сносит 3+
	for A in tops.slice(0, 6):
		for ma in A.moves.slice(0, 2):
			for B in _tops_on(ma.board, 6, 2):
				for mb in B.moves:
					for s in FIN:
						var m := big_clear(mb.board, shapes[s])
						if not m.is_empty():
							found.append({"s": [A.s, B.s, s], "board": m.board})
	return _prefer(found) if not found.is_empty() else {}


## Тройка фигур под поле b0: закрывают почти полные линии и гарантированно ставятся все три.
## gen — {since: сколько троек подряд без очистки 3+ линий}. Возвращает номера фигур или [].
static func smart_set(b0: int, gen: Dictionary) -> Array:
	var b := b0
	var chosen := []
	var used := {}
	var chance := minf(0.9, 0.3 + gen.since * 0.2)
	if randf() < chance:
		var j := find_jackpot(b0)
		if not j.is_empty():
			chosen.append_array(j.s)
			for s in j.s:
				used[s] = true
			b = j.board
	gen.since += 1
	var danger := ease and popcount(b0) >= DANGER_FILL
	var tries := DANGER_CANDIDATES if danger else CANDIDATES

	for k in range(chosen.size(), 3):
		var cands := []
		# Большие прямоугольники всегда среди кандидатов
		var big_s: int = BIG[randi() % BIG.size()]
		if not used.has(big_s):
			used[big_s] = true
			var m := best_move(b, BB.SHAPES[big_s])
			if not m.is_empty():
				cands.append({"s": big_s, "m": m})
		for t in tries:
			var s := randi() % BB.SHAPES.size()
			if used.has(s):
				continue
			used[s] = true
			var m := best_move(b, BB.SHAPES[s])
			if not m.is_empty():
				cands.append({"s": s, "m": m})
		if cands.is_empty():
			return []
		cands.sort_custom(func(x, y): return x.m.score > y.m.score)
		var pick: Dictionary
		if danger:
			# Поле забито: фигура, что сразу чистит линии, иначе мелкая и влезающая во много мест
			for cd in cands:
				cd.rescue = int(cd.m.lines) * 100 - BB.SHAPES[cd.s].cells.size() * 6 + mini(places(b, BB.SHAPES[cd.s]), 20)
			cands.sort_custom(func(x, y): return x.rescue > y.rescue)
			pick = cands[0]
		elif randf() < ASSIST:
			pick = cands[randi() % mini(3, cands.size())]   # одна из трёх лучших
		else:
			pick = cands[randi() % cands.size()]            # любая, что влезает
		chosen.append(pick.s)
		b = pick.m.board   # следующую фигуру подбираем уже под поле после этой
	chosen.shuffle()
	return chosen
