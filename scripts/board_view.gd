class_name BoardView
extends Control
## Поле 8×8: клетки со стилем, подсветка установки, анимации очистки/приземления/проигрыша, тряска.

const N := 8

var cells: Array = []        ## 64 × (null | {c: Color, f: String})
var skin := 0
var cell := 74.0
var gap := 5.0
var pad := 14.0
var radius := 0.125
var corner := 28.0
var show_fruits := true

var preview := {}            ## idx → {c, f} — фигура, которую держат над полем
var willclear := {}          ## idx → Color — линии, которые исчезнут
var _anims := {}             ## idx → {type, t0, delay, cell}
var _dead_t0 := -1.0
var _flash_t0 := -10.0
var _shake_t0 := -10.0
var _shake_pow := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.resize(N * N)


func set_metrics(c: float, g: float, p: float) -> void:
	cell = c
	gap = g
	pad = p
	custom_minimum_size = Vector2.ONE * board_size()
	size = custom_minimum_size


func board_size() -> float:
	return pad * 2.0 + N * cell + (N - 1) * gap


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func reset_fx() -> void:
	_anims.clear()
	_dead_t0 = -1.0
	preview.clear()
	willclear.clear()


func _process(_dt: float) -> void:
	queue_redraw()


## Левый верхний угол клетки idx в локальных координатах
func cell_pos(idx: int) -> Vector2:
	return Vector2(pad + (idx % N) * (cell + gap), pad + (idx / N) * (cell + gap))


func cell_center_global(idx: int) -> Vector2:
	return get_global_transform() * (cell_pos(idx) + Vector2.ONE * cell * 0.5)


## Клетка под точкой (глобальные координаты левого верхнего угла фигуры) — с округлением
func cell_at_global(p: Vector2) -> Vector2i:
	var loc: Vector2 = get_global_transform().affine_inverse() * p
	var step := cell + gap
	return Vector2i(roundi((loc.y - pad) / step), roundi((loc.x - pad) / step))


func step_global() -> float:
	return (cell + gap) * get_global_transform().get_scale().x


# ---------- Анимации ----------
func anim_clear(idx: int, old: Dictionary, delay: float) -> void:
	_anims[idx] = {"type": "clear", "t0": now(), "delay": delay, "cell": old}


func anim_land(idx: int) -> void:
	_anims[idx] = {"type": "land", "t0": now(), "delay": 0.0}


func anim_dead() -> void:
	_dead_t0 = now()


func flash() -> void:
	_flash_t0 = now()


func shake(power: float) -> void:
	_shake_pow = power
	_shake_t0 = now()


func _shake_offset(t: float) -> Vector2:
	var e := (t - _shake_t0) / 0.4
	if e < 0.0 or e >= 1.0:
		return Vector2.ZERO
	var s := _shake_pow
	var fr := [[0.0, 0.0, 0.0], [0.2, -1.0, 0.5], [0.4, 1.0, -0.5], [0.6, -0.6, 0.0], [0.8, 0.4, 0.3], [1.0, 0.0, 0.0]]
	for k in range(1, fr.size()):
		if e <= fr[k][0]:
			var u: float = (e - fr[k - 1][0]) / 0.2
			return Vector2(lerpf(fr[k - 1][1], fr[k][1], u), lerpf(fr[k - 1][2], fr[k][2], u)) * s
	return Vector2.ZERO


func _draw() -> void:
	var t := now()
	var off := _shake_offset(t)
	var bs := board_size()
	var br := Rect2(off, Vector2(bs, bs))
	# Вспышка при новом стиле
	var fe := (t - _flash_t0) / 0.7
	if fe >= 0.0 and fe < 1.0:
		var k := Skins.keys(fe, [[0.0, 0.0], [0.3, 1.0], [1.0, 0.0]])
		for g in 4:
			Skins.rrect(self, br.grow(8.0 + g * 14.0 * k), Color(1, 1, 1, 0.16 * k), corner + 10.0 + g * 14.0)
		Skins.rrect(self, br.grow(7.0 * k), Color(BB.C_GOLD, k), corner + 6.0)
	else:
		Skins.rrect(self, Rect2(br.position + Vector2(0, 16), br.size), Color(0, 0, 0, 0.25), corner)
	Skins.rrect(self, br, BB.C_BOARD, corner)

	for idx in N * N:
		var p := cell_pos(idx) + off
		Skins.reset_filters()
		Skins.rrect(self, Rect2(p, Vector2(cell, cell)), BB.C_CELL, cell * radius)
		var wave := (idx % N) + (idx / N)
		var cur = cells[idx]
		var a: Dictionary = _anims.get(idx, {})
		if not a.is_empty():
			var e: float = t - a.t0 - a.delay
			if a.type == "clear":
				if e < 0.0:
					_cell(p, a.cell, wave, 1.0)
					continue
				var k := e / 0.32
				if k < 1.0:
					Skins.ALPHA = 1.0 - k
					Skins.BRIGHT = lerpf(1.6, 1.0, k)
					_cell(p, a.cell, wave, lerpf(1.0, 0.2, k))
					Skins.reset_filters()
					if not preview.has(idx):
						continue
				else:
					_anims.erase(idx)
			elif a.type == "land":
				var k := e / 0.3
				if k < 1.0 and cur != null:
					var sc := Skins.keys(k, [[0.0, 1.2], [0.55, 0.88], [1.0, 1.0]])
					_cell(p, cur, wave, sc)
					continue
				_anims.erase(idx)
		if preview.has(idx):
			var pv: Dictionary = preview[idx]
			if willclear.has(idx):
				Skins.BRIGHT = 1.15
				_cell(p, {"c": willclear[idx], "f": pv.f}, wave, 1.0)
			else:
				Skins.ALPHA = 0.55
				_cell(p, pv, wave, 1.0)
			continue
		if cur == null:
			continue
		if willclear.has(idx):
			Skins.BRIGHT = 1.15
			_cell(p, {"c": willclear[idx], "f": cur.f}, wave, 1.0)
			continue
		if _dead_t0 >= 0.0:
			var k := clampf((t - _dead_t0 - (idx / N) * 0.06) / 0.4, 0.0, 1.0)
			Skins.GRAY = k
			Skins.BRIGHT = lerpf(1.0, 0.55, k)
		_cell(p, cur, wave, 1.0)
	Skins.reset_filters()


func _cell(p: Vector2, c: Dictionary, wave: int, scale: float) -> void:
	var stone: bool = c.c == BB.STONE
	var fv = c.get("f")
	var f := "" if fv == null or not show_fruits else str(fv)
	Skins.block(self, p, cell, c.c, skin, now(), wave, f, stone, scale, radius)
