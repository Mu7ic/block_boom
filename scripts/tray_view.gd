class_name TrayView
extends Control
## Лоток с тремя фигурами. Хватать можно за весь слот — на телефоне по маленьким фигурам легко промахнуться.

signal grab(slot: int, global_pos: Vector2)

var pieces: Array = [null, null, null]
var nofit: Array = [false, false, false]
var skin := 0
var mini := 37.0
var gap := 4.0
var hidden_slot := -1
var thinking := -1           ## бот «берёт» фигуру — она подпрыгивает
var interactive := true
var _think_t0 := 0.0
var _appear_t0 := -10.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func set_pieces(p: Array, nf: Array, animate := false) -> void:
	pieces = p.duplicate()
	nofit = nf.duplicate()
	if animate:
		_appear_t0 = now()


func set_thinking(i: int) -> void:
	thinking = i
	_think_t0 = now()


func slot_rect(i: int) -> Rect2:
	var w := size.x / 3.0
	return Rect2(Vector2(w * i, 0), Vector2(w, size.y))


func piece_size(p: Dictionary) -> Vector2:
	return Vector2(p.w * mini + (p.w - 1) * gap, p.h * mini + (p.h - 1) * gap)


## Левый верхний угол фигуры в слоте (глобально) и масштаб относительно клетки поля
func piece_origin_global(i: int) -> Vector2:
	var p: Dictionary = pieces[i] if pieces[i] != null else {"w": 1, "h": 1}
	var r := slot_rect(i)
	return get_global_transform() * (r.get_center() - piece_size(p) * 0.5)


func _process(_dt: float) -> void:
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if not interactive:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var i := clampi(int(ev.position.x / (size.x / 3.0)), 0, 2)
		if pieces[i] != null and i != hidden_slot:
			accept_event()
			grab.emit(i, ev.global_position)


func _draw() -> void:
	var t := now()
	for i in 3:
		var p = pieces[i]
		if p == null or i == hidden_slot:
			continue
		var sc := 1.0
		var dy := 0.0
		var a := 0.3 if nofit[i] else 1.0
		var e := (t - _appear_t0 - i * 0.09) / 0.4
		if e < 1.0:
			if e <= 0.0:
				continue
			# cubic-bezier(.3, 1.6, .6, 1) — «выпрыгивание» с перелётом
			var k := 1.0 + 2.2 * pow(e - 1.0, 3) + 1.2 * pow(e - 1.0, 2)
			sc = clampf(k, 0.0, 1.3)
			dy = 40.0 * (1.0 - e)
			a *= clampf(e * 2.0, 0.0, 1.0)
		if i == thinking:
			var te := (t - _think_t0) / 0.45
			if te < 1.0:
				sc *= 1.0 + 0.4 * sin(PI * te)
		var r := slot_rect(i)
		var ps := piece_size(p)
		var c := r.get_center() + Vector2(0, dy)
		Skins.reset_filters()
		Skins.ALPHA = a
		for cell in p.cells.size():
			var v: Vector2i = p.cells[cell]
			var local := Vector2(v.y * (mini + gap), v.x * (mini + gap)) - ps * 0.5
			var half := Vector2(mini, mini) * 0.5
			var pos := c + (local + half) * sc - half
			var fr: String = p.fruits[cell] if p.has("fruits") else ""
			Skins.block(self, pos, mini, p.color, skin, t, v.x * p.w + v.y, fr, false, sc, 0.11)
		Skins.reset_filters()
