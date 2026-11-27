class_name FxLayer
extends Control
## Верхний слой: частицы, «призрак» перетаскиваемой фигуры, всплывающие надписи, летящие фрукты.

var parts: Array = []

# Призрак фигуры
var ghost = null             ## фигура или null
var ghost_pos := Vector2.ZERO   ## левый верхний угол (глобально)
var ghost_scale := 1.0
var ghost_cell := 74.0
var ghost_gap := 5.0
var ghost_skin := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func burst(pos: Vector2, color: Color, count: int, delay := 0.0) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): burst(pos, color, count))
		return
	var k := 1.8
	for i in count:
		parts.append({
			"p": pos, "v": Vector2((randf() - 0.5) * 7.0, -randf() * 6.0 - 1.0) * k,
			"s": (4.0 + randf() * 6.0) * k, "life": 1.0, "c": color,
			"rot": randf() * 6.0, "vr": (randf() - 0.5) * 0.4,
		})


func ghost_size() -> Vector2:
	if ghost == null:
		return Vector2.ZERO
	return Vector2(ghost.w * ghost_cell + (ghost.w - 1) * ghost_gap, ghost.h * ghost_cell + (ghost.h - 1) * ghost_gap)


func _process(dt: float) -> void:
	var f := dt * 60.0
	for p in parts:
		var v: Vector2 = p.v
		v.y += 0.28 * 1.8 * f
		p.v = v
		p.p += v * f
		p.rot += p.vr * f
		p.life -= 0.02 * f
	parts = parts.filter(func(p): return p.life > 0.0)
	queue_redraw()


func _draw() -> void:
	var inv := get_global_transform().affine_inverse()
	for p in parts:
		draw_set_transform(inv * p.p, p.rot, Vector2.ONE)
		draw_rect(Rect2(-p.s / 2.0, -p.s / 2.0, p.s, p.s), Color(p.c, maxf(p.life, 0.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ghost != null:
		var t := Time.get_ticks_msec() / 1000.0
		var o: Vector2 = inv * ghost_pos
		var step := (ghost_cell + ghost_gap) * ghost_scale
		# Тень под фигурой
		for k in ghost.cells.size():
			var v: Vector2i = ghost.cells[k]
			var pos := o + Vector2(v.y, v.x) * step + Vector2(0, 14)
			Skins.rrect(self, Rect2(pos, Vector2.ONE * ghost_cell * ghost_scale), Color(0, 0, 0, 0.18), 10)
		Skins.reset_filters()
		for k in ghost.cells.size():
			var v: Vector2i = ghost.cells[k]
			var pos := o + Vector2(v.y, v.x) * step
			var half := Vector2.ONE * ghost_cell * 0.5
			var fr: String = ghost.fruits[k] if ghost.has("fruits") else ""
			Skins.block(self, pos + half * ghost_scale - half, ghost_cell, ghost.color, ghost_skin, t, v.x * ghost.w + v.y, fr, false, ghost_scale)


## Всплывающая надпись над точкой (глобально): крупный текст + мелкая подпись
func float_text(center: Vector2, main: String, sub: String, size := 1, gold := false) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", -6)
	var fs := int((30 + size * 5) * 1.8)
	var l := UI.label(main, fs, BB.C_GOLD if gold else Color.WHITE, UI.F_BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	box.add_child(l)
	if sub != "":
		var s := UI.label(sub, 36, BB.C_YELLOW, UI.F_BLACK)
		s.add_theme_constant_override("outline_size", 8)
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
		box.add_child(s)
	add_child(box)
	box.reset_size()
	var sz := box.get_combined_minimum_size()
	box.size = sz
	box.pivot_offset = sz * 0.5
	var c: Vector2 = get_global_transform().affine_inverse() * center
	box.position = c - sz * 0.5 + Vector2(0, sz.y * 0.2)
	box.scale = Vector2.ONE * 0.7
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.15)
	tw.tween_property(box, "scale", Vector2.ONE * 1.1, 0.15)
	tw.tween_property(box, "position:y", c.y - sz.y * 0.5, 0.15)
	tw.chain().set_parallel(true)
	tw.tween_property(box, "scale", Vector2.ONE, 0.85).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "position:y", c.y - sz.y * 1.3, 0.85).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(box, "modulate:a", 0.0, 0.85).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(box.queue_free)


## Фрукт летит из клетки в счётчик задания
func fly(text: String, from: Vector2, to: Vector2, size: int, done: Callable) -> void:
	var l := UI.label(text, size)
	add_child(l)
	l.reset_size()
	var sz := l.size
	var inv := get_global_transform().affine_inverse()
	l.position = inv * from - sz * 0.5
	var tw := l.create_tween()
	tw.tween_property(l, "position", inv * to - sz * 0.5, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "scale", Vector2.ONE * 0.8, 0.6)
	tw.tween_callback(func():
		l.queue_free()
		done.call())
