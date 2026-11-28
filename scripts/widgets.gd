class_name Widgets
extends RefCounted
## Небольшие рисуемые элементы: логотип, заставка, превью стилей, демо обучения, переключатели.

const PAL := [Color("ff5d5d"), Color("ffa93b"), Color("ffd84d"), Color("4fd67a"),
	Color("36c3ff"), Color("5d7bff"), Color("b45dff"), Color("ff6fc8")]


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Логотип «BLOCK BOOM»: буквы влетают по очереди и покачиваются
class Logo extends Control:
	var font_size := 96
	var delay := 0.0
	var t0 := 0.0

	func _init(fs := 96, d := 0.0) -> void:
		font_size = fs
		delay = d
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(fs * 4.2, fs * 0.92 * 2 + 20)
		restart()

	func restart() -> void:
		t0 = Widgets.now()

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var f: Font = UI.F_BLACK
		var t := Widgets.now() - t0
		var k := 0
		var lines := ["BLOCK", "BOOM"]   # название игры не переводим
		var lh := font_size * 0.92
		var top := (size.y - lh * 2) * 0.5
		for li in lines.size():
			var word: String = lines[li]
			var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var x := (size.x - w) * 0.5
			var base_y := top + lh * li + f.get_ascent(font_size) * 0.86
			for ch in word:
				var cw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var col: Color = Widgets.PAL[(k * 3) % 8]
				# Влёт: сверху, из маленького размера, с перелётом
				var e := clampf((t - delay - k * 0.07) / 0.55, 0.0, 1.0)
				var over := 1.0 + 2.4 * pow(e - 1.0, 3) + 1.4 * pow(e - 1.0, 2)
				var dy := -60.0 * 1.8 * (1.0 - over)
				var sc := lerpf(0.3, 1.0, over)
				var a := clampf(e * 1.6, 0.0, 1.0)
				# Покачивание
				var bt := t - delay - k * 0.15 - 0.8
				var rot := 0.0
				if bt > 0.0:
					var bw := Skins.wave(fposmod(bt, 3.0) / 3.0)
					dy += -5.0 * 1.8 * bw
					rot = deg_to_rad(-3.0) * bw
				var c := Vector2(x + cw * 0.5, base_y - font_size * 0.35)
				draw_set_transform(c + Vector2(0, dy), rot, Vector2.ONE * sc)
				var p := Vector2(-cw * 0.5, font_size * 0.35)
				draw_string(f, p + Vector2(0, 9), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.28 * a))
				draw_string(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(col, a))
				x += cw
				k += 1
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Заставка: блоки 4×4 падают сверху, средние ряды «взрываются»
class SplashGrid extends Control:
	const CELL := 68.0
	const GAP := 7.0
	var t0 := 0.0
	var popped := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2.ONE * (CELL * 4 + GAP * 3)
		t0 = Widgets.now()

	func cell_center_global(i: int) -> Vector2:
		return get_global_transform() * (Vector2(i % 4, i / 4) * (CELL + GAP) + Vector2.ONE * CELL * 0.5)

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := Widgets.now() - t0
		for i in 16:
			var col: Color = Widgets.PAL[(i * 5) % 8]
			var p := Vector2(i % 4, i / 4) * (CELL + GAP)
			var e := clampf((t - (15 - i) * 0.055) / 0.55, 0.0, 1.0)
			if e <= 0.0:
				continue
			var over := 1.0 + 2.0 * pow(e - 1.0, 3) + 1.0 * pow(e - 1.0, 2)
			var dy := -1400.0 * (1.0 - over)
			var sc := 1.0
			Skins.reset_filters()
			if i >= 4 and i < 12:
				var pe := (t - 1.1 - ((i - 4) % 4) * 0.04) / 0.32
				if pe >= 1.0:
					continue
				if pe > 0.0:
					sc = lerpf(1.0, 0.2, pe)
					Skins.ALPHA = 1.0 - pe
					Skins.BRIGHT = lerpf(1.6, 1.0, pe)
			Skins.block(self, p + Vector2(0, dy), CELL, col, 0, t, i, "", false, sc)
		Skins.reset_filters()


## Превью стиля 2×2 для коллекции
class SkinPreview extends Control:
	var skin := 0
	var locked := false
	var cell := 44.0

	func _init(s: int, l: bool, c := 44.0) -> void:
		skin = s
		locked = l
		cell = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2.ONE * (cell * 2 + 5)

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var pal := [Color("ff5d5d"), Color("36c3ff"), Color("4fd67a"), Color("ffd84d")]
		var t := Widgets.now()
		Skins.reset_filters()
		if locked:
			Skins.GRAY = 1.0
			Skins.BRIGHT = 0.45
		for k in 4:
			var p := Vector2(k % 2, k / 2) * (cell + 5)
			Skins.block(self, p, cell, pal[k], 0 if locked else skin, t, k)
		Skins.reset_filters()


## Круглый переключатель (звук, музыка, вибрация): выключенный — бледный и перечёркнутый
class Toggle extends Button:
	var on := true

	func _init(icon: String) -> void:
		text = icon
		custom_minimum_size = Vector2(92, 92)
		UI.style_button(self, Color(1, 1, 1, 0.14), Color.WHITE, 40)

	func set_on(v: bool) -> void:
		on = v
		modulate.a = 1.0 if on else 0.4
		queue_redraw()

	func _draw() -> void:
		if not on:
			var c := size * 0.5
			var d := Vector2(cos(deg_to_rad(-45)), sin(deg_to_rad(-45))) * (size.x * 0.5 - 20)
			draw_line(c - d, c + d, BB.C_PINK, 6, true)


## Демо-анимации обучения
class TutDemo extends Control:
	var step := 0
	var t0 := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(360, 270)

	func set_step(s: int) -> void:
		step = s
		t0 = Widgets.now()

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := Widgets.now() - t0
		var k := 1.8
		Skins.reset_filters()
		match step:
			0:
				var on := [0, 1, 2, 5, 6, 10, 11, 12, 15, 16, 17, 19]
				var c := 18.0 * k
				var g := 2.0 * k
				var o := Vector2(51, 8) * k
				for i in 20:
					var p := o + Vector2(i % 5, i / 5) * (c + g)
					if on.has(i):
						Skins.block(self, p, c, Color("5d7bff"), 0, 0, i)
					else:
						Skins.rrect(self, Rect2(p, Vector2(c, c)), BB.C_CELL, 6)
				var e := fposmod(t, 2.8) / 2.8
				var pp := Vector2(Skins.keys(e, [[0.0, 83], [0.15, 83], [0.55, 111], [1.0, 111]]),
					Skins.keys(e, [[0.0, 112], [0.15, 112], [0.55, 28], [1.0, 28]])) * k
				var sc := Skins.keys(e, [[0.0, 0.7], [0.15, 0.7], [0.55, 1.0], [1.0, 1.0]])
				var a := Skins.keys(e, [[0.0, 1.0], [0.85, 1.0], [1.0, 0.0]])
				Skins.ALPHA = a
				for j in 2:
					var half := Vector2.ONE * c * 0.5
					Skins.block(self, pp + (Vector2(0, j * (c + g)) + half) * sc - half, c, Color("ff6fc8"), 0, 0, j, "", false, sc)
				var hp := Vector2(Skins.keys(e, [[0.0, 88], [0.15, 88], [0.55, 116], [0.7, 140], [1.0, 140]]),
					Skins.keys(e, [[0.0, 128], [0.15, 128], [0.55, 44], [0.7, 90], [1.0, 90]])) * k
				var ha := Skins.keys(e, [[0.0, 1.0], [0.55, 1.0], [0.7, 0.0], [1.0, 0.0]])
				draw_string(UI.F_BOLD, hp + Vector2(0, 50), "👆", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(1, 1, 1, ha))
			1:
				var c := 20.0 * k
				var g := 3.0 * k
				var w := 8 * c + 7 * g
				var o := Vector2((size.x - w) * 0.5, size.y * 0.5 - c * 0.5)
				var e := fposmod(t, 2.6) / 2.6
				var clr := 1.0
				var csc := 1.0
				var bright := 1.0
				if e > 0.55:
					bright = Skins.keys(e, [[0.55, 1.0], [0.6, 1.8], [0.72, 1.0], [1.0, 1.0]])
					csc = Skins.keys(e, [[0.55, 1.0], [0.6, 1.0], [0.72, 0.2], [0.92, 0.6], [1.0, 1.0]])
					clr = Skins.keys(e, [[0.55, 1.0], [0.6, 1.0], [0.72, 0.0], [0.92, 0.0], [1.0, 1.0]])
				for i in 8:
					var p := o + Vector2(i * (c + g), 0)
					Skins.rrect(self, Rect2(p, Vector2(c, c)), BB.C_CELL, 6)
					if i < 6:
						Skins.ALPHA = clr
						Skins.BRIGHT = bright
						Skins.block(self, p, c, Color("36c3ff"), 0, 0, i, "", false, csc)
						Skins.reset_filters()
				# Падающая пара
				var dy := Skins.keys(e, [[0.0, -70.0], [0.4, 0.0], [1.0, 0.0]]) * k
				var da := Skins.keys(e, [[0.0, 0.0], [0.15, 1.0], [0.55, 1.0], [0.72, 0.0], [1.0, 0.0]])
				var dsc := Skins.keys(e, [[0.0, 1.0], [0.6, 1.0], [0.72, 0.2], [1.0, 0.2]])
				Skins.ALPHA = da
				Skins.BRIGHT = bright
				for j in 2:
					Skins.block(self, o + Vector2((6 + j) * (c + g), dy), c, Color("ffd84d"), 0, 0, j, "", false, dsc)
				Skins.reset_filters()
			2:
				var pul := Skins.wave(fposmod(t, 1.2) / 1.2)
				var fs := int(44 * k)
				var txt := "×5"
				var tw := UI.F_BLACK.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_set_transform(Vector2(size.x * 0.5, 70), 0, Vector2.ONE * (1.0 + 0.25 * pul))
				draw_string(UI.F_BLACK, Vector2(-tw * 0.5, 34 + 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.3))
				draw_string(UI.F_BLACK, Vector2(-tw * 0.5, 34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BB.C_GOLD.lerp(BB.C_YELLOW, pul))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				var pal := [Color("ff5d5d"), Color("36c3ff"), Color("4fd67a"), Color("ffd84d")]
				var c := 32.0 * k
				var g := 4.0 * k
				var w := 4 * c + 3 * g
				var skin := (int(t / 1.1) % (BB.SKINS.size() - 1)) + 1
				for i in 4:
					Skins.block(self, Vector2((size.x - w) * 0.5 + i * (c + g), size.y - 14 * k - c), c, pal[i], skin, Widgets.now(), i)
			3:
				var em := ["🏆", "🍓", "🤖"]
				var fs := int(46 * k)
				var gap := 22.0 * k
				var ws := 0.0
				for s in em:
					ws += UI.F_BOLD.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				ws += gap * 2
				var x := (size.x - ws) * 0.5
				for i in 3:
					var b := Skins.wave(fposmod(t - i * 0.3, 2.0) / 2.0)
					draw_set_transform(Vector2(x, size.y * 0.5 + fs * 0.35 - 9.0 * b), deg_to_rad(-3.0) * b, Vector2.ONE)
					draw_string(UI.F_BOLD, Vector2.ZERO, em[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
					x += UI.F_BOLD.get_string_size(em[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		Skins.reset_filters()
